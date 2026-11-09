package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const (
	firstID          = "11111111-1111-4111-8111-111111111111"
	secondID         = "22222222-2222-4222-8222-222222222222"
	positionTemplate = "---\ndate: {{date}}\ntime: {{time}}\nlocation:\n  - \"{{lat}}\"\n  - \"{{lon}}\"\nid: {{id}}\n---\n"
)

func testVault(t *testing.T) http.Handler {
	t.Helper()
	vaultDir = t.TempDir()
	vaultLoc = time.UTC
	token = "test-token"
	path := filepath.Join(vaultDir, "template.md")
	putFile(t, path, positionTemplate)
	if err := loadTemplate(path); err != nil {
		t.Fatal(err)
	}
	if err := buildIndex(); err != nil {
		t.Fatal(err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/", handleGet)
	mux.HandleFunc("POST /api/", handlePost)
	mux.HandleFunc("PATCH /api/", handlePatch)
	mux.HandleFunc("DELETE /api/", handleDelete)
	return jsonMiddleware(mux)
}

func request(t *testing.T, handler http.Handler, method, body string, status int) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(method, "/api/", strings.NewReader(body))
	r.Header.Set("Authorization", "Bearer test-token")
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, r)
	if w.Code != status {
		t.Fatalf("%s: status %d, want %d: %s", method, w.Code, status, w.Body.String())
	}
	return w
}

func upload(t *testing.T, handler http.Handler, id, timestamp string, status int) {
	t.Helper()
	body, err := json.Marshal(CreateEntry{ID: id, Lat: 59.33, Lon: 18.07, Timestamp: timestamp})
	if err != nil {
		t.Fatal(err)
	}
	request(t, handler, http.MethodPost, string(body), status)
}

func putFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func wantFile(t *testing.T, path, content string) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != content {
		t.Fatalf("%s: got %q, want %q", filepath.Base(path), data, content)
	}
}

func TestPositionLifecycle(t *testing.T) {
	handler := testVault(t)
	upload(t, handler, firstID, "2026-01-01T13:00:00Z", http.StatusOK)
	path := filepath.Join(vaultDir, "2026-01-01 1300.md")
	// Replacement needs directory permissions, not permission to truncate a note.
	if err := os.Chmod(path, 0o444); err != nil {
		t.Fatal(err)
	}
	upload(t, handler, secondID, "2026-01-01T13:00:30Z", http.StatusOK)
	entries := getEntries(t, handler)
	if len(entries) != 1 || entries[0].ID != secondID || entries[0].Timestamp != "2026-01-01T13:00:30Z" {
		t.Fatalf("latest position: %+v", entries)
	}
	request(t, handler, http.MethodDelete, `{"id":"`+firstID+`"}`, http.StatusNotFound)
	if err := os.Chmod(path, 0o600); err != nil {
		t.Fatal(err)
	}
	request(t, handler, http.MethodPatch, `{"id":"`+secondID+`","note":"updated body"}`, http.StatusOK)
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("patched permissions: %o, want 600", info.Mode().Perm())
	}
	entries = getEntries(t, handler)
	if len(entries) != 1 || entries[0].Note == nil || *entries[0].Note != "updated body" {
		t.Fatalf("patched position: %+v", entries)
	}
	upload(t, handler, secondID, "2026-01-01T14:00:00Z", http.StatusOK)
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("old path after move: %v", err)
	}
	request(t, handler, http.MethodDelete, `{"id":"`+secondID+`"}`, http.StatusOK)
	if _, err := os.Stat(filepath.Join(vaultDir, "2026-01-01 1400.md")); !os.IsNotExist(err) {
		t.Fatalf("path after delete: %v", err)
	}
	w := request(t, handler, http.MethodGet, "", http.StatusOK)
	if !strings.Contains(w.Body.String(), `"no_location_found"`) {
		t.Fatalf("positions after delete: %s", w.Body.String())
	}
}

func TestFailedUploadPreservesIndexedPosition(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("requires unprivileged filesystem permissions")
	}
	handler := testVault(t)
	upload(t, handler, firstID, "2026-01-01T13:00:00Z", http.StatusOK)
	path := filepath.Join(vaultDir, "2026-01-01 1300.md")
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0o444); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(vaultDir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := os.Chmod(vaultDir, 0o755); err != nil {
			t.Error(err)
		}
	})

	upload(t, handler, secondID, "2026-01-01T13:00:30Z", http.StatusInternalServerError)
	wantFile(t, path, string(before))
	entries := getEntries(t, handler)
	if len(entries) != 1 || entries[0].ID != firstID {
		t.Fatalf("positions after failed upload: %+v", entries)
	}
}

func TestUploadPreservesFallbackCollisions(t *testing.T) {
	handler := testVault(t)
	base := filepath.Join(vaultDir, "2026-01-01 1300.md")
	fallback := filepath.Join(vaultDir, "2026-01-01 1300 (111111).md")
	putFile(t, base, "daily note\n")
	putFile(t, fallback, "handwritten fallback\n")

	upload(t, handler, firstID, "2026-01-01T13:00:00Z", http.StatusOK)
	wantFile(t, base, "daily note\n")
	wantFile(t, fallback, "handwritten fallback\n")
	entries := getEntries(t, handler)
	if len(entries) != 1 || entries[0].ID != firstID {
		t.Fatalf("positions: %+v", entries)
	}
}

func getEntries(t *testing.T, handler http.Handler) []Entry {
	t.Helper()
	w := request(t, handler, http.MethodGet, "", http.StatusOK)
	var entries []Entry
	if err := json.Unmarshal(w.Body.Bytes(), &entries); err != nil {
		t.Fatal(err)
	}
	return entries
}

func TestLatestPositionWinsWithForeignBase(t *testing.T) {
	handler := testVault(t)
	base := filepath.Join(vaultDir, "2026-01-01 1300.md")
	putFile(t, base, "daily note\n")
	upload(t, handler, firstID, "2026-01-01T13:00:00Z", http.StatusOK)
	upload(t, handler, secondID, "2026-01-01T13:00:30Z", http.StatusOK)

	wantFile(t, base, "daily note\n")
	entries := getEntries(t, handler)
	if len(entries) != 1 || entries[0].ID != secondID {
		t.Fatalf("latest position: %+v", entries)
	}
	request(t, handler, http.MethodDelete, `{"id":"`+firstID+`"}`, http.StatusNotFound)
	files, err := filepath.Glob(filepath.Join(vaultDir, "2026-01-01 1300*.md"))
	if err != nil || len(files) != 2 {
		t.Fatalf("minute files: %v, %v", files, err)
	}
}

func TestPatchRejectsReplacedPosition(t *testing.T) {
	handler := testVault(t)
	upload(t, handler, firstID, "2026-01-01T13:00:00Z", http.StatusOK)
	path := filepath.Join(vaultDir, "2026-01-01 1300.md")
	replacement := "---\ntime: 2026-01-01T13:00:00\nlocation:\n  - \"59\"\n  - \"18\"\nid: " + secondID + "\n---\n\nreplacement body\n"
	putFile(t, path, replacement)

	request(t, handler, http.MethodPatch, `{"id":"`+firstID+`","note":"wrong owner"}`, http.StatusNotFound)
	wantFile(t, path, replacement)
}

func TestMovePreservesReplacedNote(t *testing.T) {
	for _, replacement := range []string{
		"handwritten note\n",
		"---\nid: " + secondID + "\n---\nreplacement position\n",
	} {
		t.Run(replacement, func(t *testing.T) {
			handler := testVault(t)
			upload(t, handler, firstID, "2026-01-01T13:00:00Z", http.StatusOK)
			old := filepath.Join(vaultDir, "2026-01-01 1300.md")
			putFile(t, old, replacement)

			upload(t, handler, firstID, "2026-01-01T14:00:00Z", http.StatusOK)
			wantFile(t, old, replacement)
			data, err := os.ReadFile(filepath.Join(vaultDir, "2026-01-01 1400.md"))
			if err != nil || !strings.Contains(string(data), "id: "+firstID) {
				t.Fatalf("moved position: %q, %v", data, err)
			}
		})
	}
}

func TestDeletePreservesReplacedNote(t *testing.T) {
	for _, replacement := range []string{
		"handwritten note\n",
		"---\nid: " + secondID + "\n---\nreplacement position\n",
	} {
		t.Run(replacement, func(t *testing.T) {
			handler := testVault(t)
			upload(t, handler, firstID, "2026-01-01T13:00:00Z", http.StatusOK)
			path := filepath.Join(vaultDir, "2026-01-01 1300.md")
			putFile(t, path, replacement)

			request(t, handler, http.MethodDelete, `{"id":"`+firstID+`"}`, http.StatusNotFound)
			wantFile(t, path, replacement)
		})
	}
}
