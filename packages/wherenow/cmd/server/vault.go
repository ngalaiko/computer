package main

// Vault-backed store.
//
// The vault notes ARE the database — there is no JSONL. Each position is one
// markdown note in the vault root, modelled on the kepano Event/Place notes and
// identified by a UUID `id:` front-matter key (nothing else in the vault uses
// one, so we can find/own our notes without a folder). POST/PATCH write a note,
// DELETE removes one, GET reconstructs entries from the notes. An in-memory
// id->path index is built once at startup and kept in step on every write.

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

var (
	vaultDir     string         // --vault-dir; notes are written here (required).
	vaultLoc     *time.Location // resolved from --tz; dates/times render in this zone.
	templateFile string         // resolved template path; re-read on every write.
	noteTmpl     string         // last good template — the fallback when a re-read fails.

	storeMu sync.Mutex        // guards the notes dir and the index.
	index   map[string]string // id -> note path, for the position notes we own.
)

func fmtCoord(f float64) string { return strconv.FormatFloat(f, 'f', -1, 64) }

func strp(p *string) string {
	if p == nil {
		return ""
	}
	return strings.TrimSpace(*p)
}

func fileExists(p string) bool { _, err := os.Stat(p); return err == nil }

// localTime parses the RFC3339 timestamp and renders it in the configured zone.
// The zone decides which day's note a point links to.
func (e Entry) localTime() (time.Time, bool) {
	t, err := time.Parse(time.RFC3339, e.Timestamp)
	if err != nil {
		return time.Time{}, false
	}
	if vaultLoc != nil {
		t = t.In(vaultLoc)
	}
	return t, true
}

// noteContent renders the markdown note for e by filling the current position
// template — {{date}}/{{time}}/{{lat}}/{{lon}}/{{id}} — and appending the
// free-text note, if any, as the body. The template owns the front-matter shape
// (category, keys); this only substitutes values. currentTemplate re-reads the
// file so an edit to the template applies to the very next note.
func noteContent(e Entry, t time.Time) string {
	fm := strings.NewReplacer(
		"{{date}}", t.Format("2006-01-02"),
		"{{time}}", t.Format("2006-01-02T15:04:05"),
		"{{lat}}", fmtCoord(e.Lat),
		"{{lon}}", fmtCoord(e.Lon),
		"{{id}}", strings.ToLower(e.ID),
	).Replace(currentTemplate())

	var b strings.Builder
	b.WriteString(fm) // normalised to end with the closing "---\n"
	if n := strp(e.Note); n != "" {
		fmt.Fprintf(&b, "\n%s\n", n)
	}
	return b.String()
}

// loadTemplate resolves and records the template path (an empty path defaults to
// <vault-dir>/Templates/Position Template.md), then reads it once so a missing or
// malformed template fails startup loudly. After this, currentTemplate re-reads
// the file on every write, so template edits take effect without a restart.
func loadTemplate(path string) error {
	if path == "" {
		path = filepath.Join(vaultDir, "Templates", "Position Template.md")
	}
	templateFile = path
	tmpl, err := readTemplate(path)
	if err != nil {
		return err
	}
	noteTmpl = tmpl
	return nil
}

// readTemplate reads and normalises the template at path: trailing newlines are
// trimmed to exactly the closing "---\n" so a note with no body ends there, and
// one with a body gets a blank line + the text. Fails if a placeholder is
// missing, so a malformed template is never adopted.
func readTemplate(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	tmpl := strings.TrimRight(string(data), "\n") + "\n"
	for _, tok := range []string{"{{date}}", "{{time}}", "{{lat}}", "{{lon}}", "{{id}}"} {
		if !strings.Contains(tmpl, tok) {
			return "", fmt.Errorf("template %s is missing placeholder %s", path, tok)
		}
	}
	return tmpl, nil
}

// currentTemplate returns the template to render the next note with, re-reading
// the file each call so an edit — e.g. one synced in from Obsidian — applies to
// the very next note without restarting the service. A read or validation error
// is logged and the last good template reused, so a transient hiccup (a mid-sync
// rename) or a momentarily broken template can't break note writing. Callers
// hold storeMu, which also guards noteTmpl.
func currentTemplate() string {
	tmpl, err := readTemplate(templateFile)
	if err != nil {
		log.Printf("template: reusing last good %s: %v", templateFile, err)
		return noteTmpl
	}
	noteTmpl = tmpl
	return tmpl
}

func shortID(id string) string {
	h := strings.ReplaceAll(strings.ToLower(id), "-", "")
	if len(h) > 6 {
		return h[:6]
	}
	return h
}

// targetPath is the note path for e: "<date> <HHMM>.md" in the vault root, like
// the migraine events. One note per minute — if that name already holds another
// position, it is overwritten (latest wins), no suffix. Only a foreign note at
// the same name (e.g. a migraine, which has no UUID id) is stepped around with a
// " (<shortid>)" suffix, so wherenow never clobbers a hand-written note. Must be
// called with storeMu held.
func targetPath(e Entry, t time.Time) string {
	base := t.Format("2006-01-02 1504")
	cand := filepath.Join(vaultDir, base+".md")
	if fileExists(cand) {
		if _, err := uuid.Parse(readNoteID(cand)); err != nil {
			// occupied by a non-position note — don't clobber it.
			cand = filepath.Join(vaultDir, base+" ("+shortID(strings.ToLower(e.ID))+").md")
		}
	}
	return cand
}

// writeNote upserts e's note and updates the index. The filename derives from
// the (immutable) timestamp, so an existing id keeps its name across PATCHes; a
// different position that maps to the same name supersedes it (latest wins).
func writeNote(e Entry) error {
	t, ok := e.localTime()
	if !ok {
		return fmt.Errorf("unparseable timestamp %q", e.Timestamp)
	}
	storeMu.Lock()
	defer storeMu.Unlock()
	if err := os.MkdirAll(vaultDir, 0o755); err != nil {
		return err
	}
	id := strings.ToLower(e.ID)
	target := targetPath(e, t)
	if old, ok := index[id]; ok && old != target {
		os.Remove(old) // our own note moved (rare — only if the timestamp changed)
	}
	// Another position already at this name is now superseded — drop its stale
	// index entry so a later PATCH/DELETE of that id can't touch this note.
	for k, v := range index {
		if v == target && k != id {
			delete(index, k)
		}
	}
	if err := writeIfChanged(target, noteContent(e, t)); err != nil {
		return err
	}
	index[id] = target
	return nil
}

func deleteNote(id string) (bool, error) {
	storeMu.Lock()
	defer storeMu.Unlock()
	id = strings.ToLower(id)
	p, ok := index[id]
	if !ok {
		return false, nil
	}
	if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
		return false, err
	}
	delete(index, id)
	return true, nil
}

func getEntry(id string) (Entry, bool) {
	storeMu.Lock()
	p, ok := index[strings.ToLower(id)]
	storeMu.Unlock()
	if !ok {
		return Entry{}, false
	}
	return readNote(p)
}

// listEntries returns the position notes as entries, newest first, up to limit
// (0 = all). RFC3339-UTC timestamps sort lexically, which is chronological.
func listEntries(limit int) []Entry {
	storeMu.Lock()
	paths := make([]string, 0, len(index))
	for _, p := range index {
		paths = append(paths, p)
	}
	storeMu.Unlock()

	var es []Entry
	for _, p := range paths {
		if e, ok := readNote(p); ok {
			es = append(es, e)
		}
	}
	sort.Slice(es, func(i, j int) bool { return es[i].Timestamp > es[j].Timestamp })
	if limit > 0 && len(es) > limit {
		es = es[:limit]
	}
	return es
}

// buildIndex scans the vault root once and records every note we own (its `id:`
// is a UUID). Missing dir => empty index (created lazily on the first write).
func buildIndex() error {
	index = map[string]string{}
	ents, err := os.ReadDir(vaultDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	for _, de := range ents {
		if de.IsDir() || !strings.HasSuffix(de.Name(), ".md") {
			continue
		}
		p := filepath.Join(vaultDir, de.Name())
		id := readNoteID(p)
		if id == "" {
			continue
		}
		if _, err := uuid.Parse(id); err != nil {
			continue // has an id: but not a UUID — not ours.
		}
		index[id] = p
	}
	return nil
}

// ---------- note parsing ----------

// readNoteID returns the `id:` value from a note's first front-matter block,
// lowercased, or "" if absent.
func readNoteID(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	if !sc.Scan() || strings.TrimSpace(sc.Text()) != "---" {
		return ""
	}
	for sc.Scan() {
		line := sc.Text()
		if strings.TrimSpace(line) == "---" {
			return ""
		}
		if strings.HasPrefix(line, "id:") {
			return strings.ToLower(strings.TrimSpace(strings.TrimPrefix(line, "id:")))
		}
	}
	return ""
}

// readNote reconstructs an Entry from one of our notes: id, coordinates, the
// timestamp (rebuilt from the local `time` + the configured zone) and the body
// as the free-text note. ok is false unless the note carries a UUID id and a
// two-element location.
func readNote(path string) (Entry, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Entry{}, false
	}
	s := string(data)
	if !strings.HasPrefix(s, "---\n") {
		return Entry{}, false
	}
	rest := s[len("---\n"):]
	end := strings.Index(rest, "\n---\n")
	if end < 0 {
		return Entry{}, false
	}
	fm := rest[:end]
	body := strings.TrimSpace(rest[end+len("\n---\n"):])

	var id, tstr string
	var coords []string
	lines := strings.Split(fm, "\n")
	for i := 0; i < len(lines); i++ {
		line := lines[i]
		switch {
		case strings.HasPrefix(line, "id:"):
			id = strings.ToLower(strings.TrimSpace(strings.TrimPrefix(line, "id:")))
		case strings.HasPrefix(line, "time:"):
			tstr = strings.TrimSpace(strings.TrimPrefix(line, "time:"))
		case strings.HasPrefix(line, "location:"):
			for i+1 < len(lines) {
				next := strings.TrimSpace(lines[i+1])
				if !strings.HasPrefix(next, "- ") {
					break
				}
				coords = append(coords, strings.Trim(strings.TrimSpace(next[2:]), "\""))
				i++
			}
		}
	}

	if _, err := uuid.Parse(id); err != nil {
		return Entry{}, false
	}
	if len(coords) != 2 {
		return Entry{}, false
	}
	lat, err1 := strconv.ParseFloat(coords[0], 64)
	lon, err2 := strconv.ParseFloat(coords[1], 64)
	if err1 != nil || err2 != nil {
		return Entry{}, false
	}

	loc := vaultLoc
	if loc == nil {
		loc = time.Local
	}
	ts := ""
	if t, err := time.ParseInLocation("2006-01-02T15:04:05", tstr, loc); err == nil {
		ts = t.UTC().Format(time.RFC3339)
	}

	e := Entry{ID: id, Lat: lat, Lon: lon, Timestamp: ts}
	up := "upload"
	e.Reason = &up
	if body != "" {
		e.Note = &body
	}
	return e, true
}

func writeIfChanged(path, content string) error {
	if cur, err := os.ReadFile(path); err == nil && string(cur) == content {
		return nil // byte-identical: skip so Obsidian Sync stays quiet.
	}
	return os.WriteFile(path, []byte(content), 0o644)
}
