package main

import (
	"crypto/subtle"
	"encoding/json"
	"flag"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
)

const maxBodyBytes = 65536 // 64 KB

type Entry struct {
	ID        string   `json:"id"`
	Lat       float64  `json:"lat"`
	Lon       float64  `json:"lon"`
	Timestamp string   `json:"timestamp"`
	Accuracy  *float64 `json:"accuracy"`
	Label     *string  `json:"label"`
	Note      *string  `json:"note"`
	Category  *string  `json:"category"`
	Reason    *string  `json:"reason"`
}

type CreateEntry struct {
	ID        string   `json:"id"`
	Lat       float64  `json:"lat"`
	Lon       float64  `json:"lon"`
	Timestamp string   `json:"timestamp"`
	Accuracy  *float64 `json:"accuracy"`
	Label     *string  `json:"label"`
	Note      *string  `json:"note"`
	Category  *string  `json:"category"`
	Reason    *string  `json:"reason"`
}

type PatchEntry struct {
	ID       string  `json:"id"`
	Label    *string `json:"label"`
	Note     *string `json:"note"`
	Category *string `json:"category"`
}

type DeleteEntry struct {
	ID string `json:"id"`
}

type ErrorResponse struct {
	Error string `json:"error"`
}

func writeError(w http.ResponseWriter, status int, code string) {
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(ErrorResponse{Error: code})
}

var token string

func main() {
	flag.StringVar(&vaultDir, "vault-dir", "", "vault directory the position notes live in (required)")
	tzName := flag.String("tz", "Local", "IANA timezone for note dates/times (e.g. Europe/Stockholm)")
	templatePath := flag.String("template", "", "position note template (default: <vault-dir>/Templates/Position Template.md)")
	flag.Parse()

	if vaultDir == "" {
		log.Fatal("--vault-dir is required")
	}
	loc, err := time.LoadLocation(*tzName)
	if err != nil {
		log.Fatalf("invalid --tz %q: %v", *tzName, err)
	}
	vaultLoc = loc

	if err := loadTemplate(*templatePath); err != nil {
		log.Fatalf("cannot load position template: %v", err)
	}

	if err := buildIndex(); err != nil {
		log.Fatalf("cannot scan vault %s: %v", vaultDir, err)
	}
	log.Printf("vault: %d existing position notes in %s (tz %s)", len(index), vaultDir, vaultLoc)

	token = os.Getenv("TOKEN")
	if token == "" {
		log.Fatal("TOKEN env var is required")
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/", handleGet)
	mux.HandleFunc("POST /api/", handlePost)
	mux.HandleFunc("PATCH /api/", handlePatch)
	mux.HandleFunc("DELETE /api/", handleDelete)

	log.Printf("listening on :%s, vault=%s", port, vaultDir)
	handler := loggingMiddleware(jsonMiddleware(mux))
	log.Fatal(http.ListenAndServe(":"+port, handler))
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(sw, r)
		log.Printf("%s %s %d %s", r.Method, r.URL, sw.status, time.Since(start))
	})
}

func jsonMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		next.ServeHTTP(w, r)
	})
}

// ---------- auth ----------

func bearerToken(r *http.Request) string {
	auth := r.Header.Get("Authorization")
	if !strings.HasPrefix(auth, "Bearer ") {
		return ""
	}
	return strings.TrimPrefix(auth, "Bearer ")
}

func checkAuth(w http.ResponseWriter, r *http.Request) bool {
	t := bearerToken(r)
	if t == "" || subtle.ConstantTimeCompare([]byte(token), []byte(t)) != 1 {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return false
	}
	return true
}

// ---------- GET /api/ ----------

func handleGet(w http.ResponseWriter, r *http.Request) {
	// unauthenticated ping
	if r.URL.Query().Get("ping") == "1" {
		json.NewEncoder(w).Encode(map[string]bool{"ok": true})
		return
	}
	// authenticated ping
	if r.URL.Query().Get("ping") == "auth" {
		if !checkAuth(w, r) {
			return
		}
		json.NewEncoder(w).Encode(map[string]bool{"ok": true})
		return
	}

	if !checkAuth(w, r) {
		return
	}

	limit := 200
	if l := r.URL.Query().Get("limit"); l != "" {
		if v, err := strconv.Atoi(l); err == nil && v > 0 {
			limit = v
		}
	}
	if limit > 200 {
		limit = 200
	}

	entries := listEntries(limit)
	if len(entries) == 0 {
		json.NewEncoder(w).Encode(ErrorResponse{Error: "no_location_found"})
		return
	}
	json.NewEncoder(w).Encode(entries)
}

// ---------- POST /api/ ----------

func handlePost(w http.ResponseWriter, r *http.Request) {
	if !checkAuth(w, r) {
		return
	}

	var req CreateEntry
	if !readBodyJSON(w, r, &req) {
		return
	}

	if _, err := uuid.Parse(req.ID); err != nil {
		writeError(w, http.StatusBadRequest, "bad_id")
		return
	}
	if req.Lat < -90 || req.Lat > 90 {
		writeError(w, http.StatusBadRequest, "bad_lat")
		return
	}
	if req.Lon < -180 || req.Lon > 180 {
		writeError(w, http.StatusBadRequest, "bad_lon")
		return
	}
	if req.Note != nil && utf8.RuneCountInString(*req.Note) > 500 {
		writeError(w, http.StatusBadRequest, "bad_note")
		return
	}

	// Only "upload" points become notes; anything else is accepted and dropped
	// (the old JSONL kept them but never surfaced them).
	reason := "upload"
	if req.Reason != nil && *req.Reason != "" {
		reason = *req.Reason
	}
	if reason != "upload" {
		json.NewEncoder(w).Encode(map[string]bool{"ok": true})
		return
	}

	ts := req.Timestamp
	if ts == "" {
		ts = time.Now().UTC().Format(time.RFC3339)
	}

	// label, category and accuracy are intentionally not stored.
	if err := writeNote(Entry{
		ID:        strings.ToLower(req.ID),
		Lat:       req.Lat,
		Lon:       req.Lon,
		Timestamp: ts,
		Note:      req.Note,
	}); err != nil {
		log.Printf("post: write failed: %v", err)
		writeError(w, http.StatusInternalServerError, "write_failed")
		return
	}

	json.NewEncoder(w).Encode(map[string]bool{"ok": true})
}

// ---------- PATCH /api/ ----------

func handlePatch(w http.ResponseWriter, r *http.Request) {
	if !checkAuth(w, r) {
		return
	}

	var req PatchEntry
	if !readBodyJSON(w, r, &req) {
		return
	}

	if _, err := uuid.Parse(req.ID); err != nil {
		writeError(w, http.StatusBadRequest, "bad_id")
		return
	}
	id := strings.ToLower(req.ID)

	if req.Label == nil && req.Note == nil && req.Category == nil {
		json.NewEncoder(w).Encode(map[string]any{"ok": true, "id": id, "noop": true})
		return
	}
	if req.Note != nil && utf8.RuneCountInString(*req.Note) > 500 {
		writeError(w, http.StatusBadRequest, "bad_note")
		return
	}

	entry, ok := getEntry(id)
	if !ok {
		writeError(w, http.StatusNotFound, "id_not_found")
		return
	}

	// Only the free-text note is persisted; label/category are accepted (for API
	// compatibility) but not written to the note.
	if req.Note != nil {
		entry.Note = req.Note
	}
	if err := writeNote(entry); err != nil {
		log.Printf("patch: write failed: %v", err)
		writeError(w, http.StatusInternalServerError, "write_failed")
		return
	}

	resp := map[string]any{"ok": true, "id": id}
	if req.Label != nil {
		resp["label"] = *req.Label
	}
	if req.Note != nil {
		resp["note"] = *req.Note
	}
	if req.Category != nil {
		resp["category"] = *req.Category
	}
	json.NewEncoder(w).Encode(resp)
}

// ---------- DELETE /api/ ----------

func handleDelete(w http.ResponseWriter, r *http.Request) {
	if !checkAuth(w, r) {
		return
	}

	var req DeleteEntry
	if !readBodyJSON(w, r, &req) {
		return
	}

	if _, err := uuid.Parse(req.ID); err != nil {
		writeError(w, http.StatusBadRequest, "bad_id")
		return
	}
	id := strings.ToLower(req.ID)

	deleted, err := deleteNote(id)
	if err != nil {
		log.Printf("delete: %v", err)
		writeError(w, http.StatusInternalServerError, "write_failed")
		return
	}
	if !deleted {
		writeError(w, http.StatusNotFound, "id_not_found")
		return
	}

	json.NewEncoder(w).Encode(map[string]any{"ok": true, "id": id, "deleted": true})
}

// ---------- helpers ----------

func readBodyJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	if r.ContentLength > maxBodyBytes {
		writeError(w, http.StatusRequestEntityTooLarge, "payload_too_large")
		return false
	}
	dec := json.NewDecoder(io.LimitReader(r.Body, maxBodyBytes+1))
	if err := dec.Decode(dst); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return false
	}
	return true
}
