// storage.go
package storage

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// Store persists uploaded document bytes to the local filesystem, keyed by the
// same logical path scheme ("uploads/<org>/<invoice>/<filename>") that was
// previously only used to fabricate a fake S3 URL. Swapping to real S3/GCS
// later just means implementing this same interface against a bucket instead
// of a directory -- callers never touch the filesystem directly.
type Store struct {
	root string
}

// NewLocalStore creates (if needed) and returns a Store rooted at dir.
func NewLocalStore(dir string) (*Store, error) {
	abs, err := filepath.Abs(dir)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(abs, 0o755); err != nil {
		return nil, err
	}
	return &Store{root: abs}, nil
}

// Save streams r to disk under key and returns the content's SHA-256 hash
// (hex-encoded) and byte size, computed server-side so callers can't lie
// about what they uploaded.
func (s *Store) Save(key string, r io.Reader) (sha256Hash string, size int64, err error) {
	path, err := s.resolve(key)
	if err != nil {
		return "", 0, err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return "", 0, err
	}
	f, err := os.Create(path)
	if err != nil {
		return "", 0, err
	}
	defer f.Close()

	h := sha256.New()
	n, err := io.Copy(f, io.TeeReader(r, h))
	if err != nil {
		return "", 0, err
	}
	return hex.EncodeToString(h.Sum(nil)), n, nil
}

// Open returns a reader for a previously-saved key. Caller must Close it.
func (s *Store) Open(key string) (io.ReadCloser, error) {
	path, err := s.resolve(key)
	if err != nil {
		return nil, err
	}
	return os.Open(path)
}

// resolve maps a logical key to an absolute path guaranteed to stay under
// root, even if key contains ".." segments.
func (s *Store) resolve(key string) (string, error) {
	cleaned := filepath.Clean(string(filepath.Separator) + key)
	full := filepath.Join(s.root, cleaned)
	if full != s.root && !strings.HasPrefix(full, s.root+string(filepath.Separator)) {
		return "", errors.New("storage: invalid key")
	}
	return full, nil
}
