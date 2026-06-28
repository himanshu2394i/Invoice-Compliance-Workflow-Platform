package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"math/rand"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const (
	apiURL     = "http://localhost:8000/api/v1"
	dataFolder = `d:\MeridianDist\data`
)

// Credentials default to env var overrides (for pointing this at an
// already-seeded tenant); if none are set, main() seeds a fresh demo tenant
// itself and uses whatever emails come back, since seeded demo emails are
// suffixed per-organization to avoid colliding across repeated seed calls.
var (
	workerEmail  = os.Getenv("TESTER_WORKER_EMAIL")
	managerEmail = os.Getenv("TESTER_MANAGER_EMAIL")
	financeEmail = os.Getenv("TESTER_FINANCE_EMAIL")
	demoPassword = envOr("TESTER_PASSWORD", "ChangeMe123!")
)

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

type seedUser struct {
	Email string `json:"email"`
	Role  string `json:"role"`
}

type seedResponse struct {
	Users        []seedUser `json:"users"`
	DemoPassword string     `json:"demo_password"`
	Error        string     `json:"error"`
}

// seedFreshTenant calls the admin seed endpoint and fills in workerEmail/
// managerEmail/financeEmail/demoPassword from the response.
func seedFreshTenant() error {
	resp, err := http.Post(apiURL+"/admin/seed", "application/json", nil)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	var sr seedResponse
	if err := json.NewDecoder(resp.Body).Decode(&sr); err != nil {
		return err
	}
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("seed failed: %s", sr.Error)
	}

	for _, u := range sr.Users {
		switch u.Role {
		case "WORKER":
			workerEmail = u.Email
		case "MANAGER":
			managerEmail = u.Email
		case "FINANCE":
			financeEmail = u.Email
		}
	}
	demoPassword = sr.DemoPassword
	log.Printf("Seeded fresh demo tenant: worker=%s manager=%s finance=%s", workerEmail, managerEmail, financeEmail)
	return nil
}

type UploadResponse struct {
	WorkflowID string `json:"workflow_id"`
	InvoiceID  string `json:"invoice_id"`
	FileName   string `json:"file_name"`
	Status     string `json:"status"`
}

type approveRequest struct {
	Approved bool   `json:"approved"`
	Comments string `json:"comments"`
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type loginResponse struct {
	Token string `json:"token"`
}

// login authenticates and returns a bearer token. The API has no session/cookie
// state, so every concurrent goroutine just reuses these three tokens.
func login(email, password string) (string, error) {
	body, _ := json.Marshal(loginRequest{Email: email, Password: password})
	resp, err := http.Post(apiURL+"/auth/login", "application/json", bytes.NewBuffer(body))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("login failed for %s: status %d (did you run POST /api/v1/admin/seed first?)", email, resp.StatusCode)
	}
	var lr loginResponse
	if err := json.NewDecoder(resp.Body).Decode(&lr); err != nil {
		return "", err
	}
	return lr.Token, nil
}

func authedPost(url, token string, payload interface{}) (*http.Response, error) {
	body, _ := json.Marshal(payload)
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewBuffer(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	return http.DefaultClient.Do(req)
}

// uploadFile streams a real file's bytes as multipart/form-data, matching the
// same contract the worker dashboard's drag-and-drop uses -- this exercises
// the real storage path (internal/storage.Store), not just a filename string.
func uploadFile(url, token, filePath string) (*http.Response, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	part, err := mw.CreateFormFile("file", filepath.Base(filePath))
	if err != nil {
		return nil, err
	}
	if _, err := io.Copy(part, f); err != nil {
		return nil, err
	}
	if err := mw.Close(); err != nil {
		return nil, err
	}

	req, err := http.NewRequest(http.MethodPost, url, &buf)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", mw.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+token)
	return http.DefaultClient.Do(req)
}

func main() {
	rand.Seed(time.Now().UnixNano())

	log.Println("Starting Automated Integration Tester...")

	if workerEmail == "" || managerEmail == "" || financeEmail == "" {
		if err := seedFreshTenant(); err != nil {
			log.Fatalf("Auto-seed failed: %v (or set TESTER_WORKER_EMAIL/TESTER_MANAGER_EMAIL/TESTER_FINANCE_EMAIL/TESTER_PASSWORD to point at an existing tenant)", err)
		}
	}

	workerToken, err := login(workerEmail, demoPassword)
	if err != nil {
		log.Fatalf("Worker login failed: %v", err)
	}
	managerToken, err := login(managerEmail, demoPassword)
	if err != nil {
		log.Fatalf("Manager login failed: %v", err)
	}
	financeToken, err := login(financeEmail, demoPassword)
	if err != nil {
		log.Fatalf("Finance login failed: %v", err)
	}
	log.Println("Authenticated as worker, manager, and finance demo users.")

	log.Println("Reading data directory: ", dataFolder)
	files, err := ioutil.ReadDir(dataFolder)
	if err != nil {
		log.Fatalf("Failed to read data directory: %v", err)
	}

	var targetFiles []string
	for _, f := range files {
		if !f.IsDir() && (strings.HasSuffix(f.Name(), ".jpeg") || strings.HasSuffix(f.Name(), ".jpg")) {
			targetFiles = append(targetFiles, f.Name())
		}
	}

	total := len(targetFiles)
	log.Printf("Found %d images to process.", total)
	if total == 0 {
		log.Fatal("No images found to test.")
	}

	var wg sync.WaitGroup

	// Process in batches to simulate realistic concurrent load
	concurrencyLimit := 5
	sem := make(chan struct{}, concurrencyLimit)

	var successCount int32
	var failCount int32

	for i, file := range targetFiles {
		wg.Add(1)
		sem <- struct{}{} // Acquire token

		go func(idx int, filename string) {
			defer wg.Done()
			defer func() { <-sem }() // Release token

			// Step 1: Upload / Trigger Workflow (requires WORKER or ADMIN role)
			resp, err := uploadFile(apiURL+"/invoices/upload", workerToken, filepath.Join(dataFolder, filename))
			if err != nil {
				log.Printf("[%d/%d] [%s] Upload Failed: %v", idx+1, total, filename, err)
				atomic.AddInt32(&failCount, 1)
				return
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusAccepted {
				log.Printf("[%d/%d] [%s] Unexpected status code: %d", idx+1, total, filename, resp.StatusCode)
				atomic.AddInt32(&failCount, 1)
				return
			}

			var upResp UploadResponse
			json.NewDecoder(resp.Body).Decode(&upResp)
			invoiceID := upResp.InvoiceID
			log.Printf("[%d/%d] [%s] Uploaded -> Invoice %s (workflow %s)", idx+1, total, filename, invoiceID, upResp.WorkflowID)

			// Simulate processing time
			time.Sleep(time.Duration(rand.Intn(1000)+500) * time.Millisecond)

			actionURL := fmt.Sprintf("%s/invoices/%s/approve", apiURL, invoiceID)

			// 20% chance to reject outright; otherwise the mocked GrossAmount (15000)
			// requires both Manager and Finance approval to fully unblock the workflow.
			// Which signal gets sent is derived server-side from whichever token authorizes
			// the request -- there's no "role" field to set anymore.
			action := "approve"
			var actionResp *http.Response
			if rand.Float32() < 0.2 {
				action = "reject"
				actionResp, err = authedPost(actionURL, managerToken, approveRequest{Approved: false, Comments: "automated load test rejection"})
			} else {
				actionResp, err = authedPost(actionURL, managerToken, approveRequest{Approved: true, Comments: "automated load test"})
				if actionResp != nil {
					actionResp.Body.Close()
				}
				time.Sleep(200 * time.Millisecond) // Wait for state transition to PENDING_FINANCE_APPROVAL
				actionResp, err = authedPost(actionURL, financeToken, approveRequest{Approved: true, Comments: "automated load test"})
			}

			if err != nil {
				log.Printf("[%d/%d] [%s] %s Action Failed: %v", idx+1, total, filename, action, err)
				atomic.AddInt32(&failCount, 1)
				return
			}
			defer actionResp.Body.Close()

			if actionResp.StatusCode == http.StatusOK {
				log.Printf("[%d/%d] [%s] Invoice %s -> %s", idx+1, total, filename, invoiceID, strings.ToUpper(action))
				atomic.AddInt32(&successCount, 1)
			} else {
				log.Printf("[%d/%d] [%s] Action failed with status: %d", idx+1, total, filename, actionResp.StatusCode)
				atomic.AddInt32(&failCount, 1)
			}

		}(i, file)
	}

	wg.Wait()
	log.Println("=====================================")
	log.Println("Load Testing Complete!")
	log.Printf("Total Processed: %d", total)
	log.Printf("Successful End-to-End Workflows: %d", atomic.LoadInt32(&successCount))
	log.Printf("Failures: %d", atomic.LoadInt32(&failCount))
	log.Println("=====================================")
}
