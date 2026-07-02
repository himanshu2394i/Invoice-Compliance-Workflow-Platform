package api

import (
	"net/http"
	"testing"
)

func TestMasterData_CRUDAndRoleGates(t *testing.T) {
	ts := startTestServer(t)

	// Workers can read master data but never write it.
	denied := ts.post(t, "/api/v1/principals", ts.WorkerToken,
		map[string]interface{}{"name": "Nestle"})
	denied.Body.Close()
	if denied.StatusCode != http.StatusForbidden {
		t.Fatalf("expected 403 for worker principal create, got %d", denied.StatusCode)
	}

	created := ts.post(t, "/api/v1/principals", ts.AdminToken,
		map[string]interface{}{"name": "Nestle", "code": "DBR"})
	if created.StatusCode != http.StatusCreated {
		t.Fatalf("create principal: expected 201, got %d", created.StatusCode)
	}
	type principal struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	prin := decodeJSON[principal](t, created)

	listResp := ts.get(t, "/api/v1/principals", ts.WorkerToken)
	type principalList struct {
		Principals []principal `json:"principals"`
	}
	list := decodeJSON[principalList](t, listResp)
	if len(list.Principals) != 1 || list.Principals[0].Name != "Nestle" {
		t.Fatalf("expected worker-readable principal list [Nestle], got %+v", list.Principals)
	}

	// Series registry upsert: same prefix twice must update, not duplicate.
	type entityList struct {
		Entities []struct {
			ID string `json:"id"`
		} `json:"entities"`
	}
	entResp := ts.get(t, "/api/v1/entities", ts.AdminToken)
	entities := decodeJSON[entityList](t, entResp)
	if len(entities.Entities) == 0 {
		t.Fatal("seeded org has no entities")
	}
	entityID := entities.Entities[0].ID

	for i := 0; i < 2; i++ {
		up := ts.post(t, "/api/v1/series-registry", ts.AdminToken,
			map[string]interface{}{"series_prefix": "DBR", "entity_id": entityID, "principal_id": prin.ID})
		up.Body.Close()
		if up.StatusCode != http.StatusCreated {
			t.Fatalf("series upsert %d: expected 201, got %d", i, up.StatusCode)
		}
	}
	type seriesList struct {
		Series []struct {
			SeriesPrefix  string  `json:"series_prefix"`
			PrincipalName *string `json:"principal_name"`
		} `json:"series"`
	}
	sl := decodeJSON[seriesList](t, ts.get(t, "/api/v1/series-registry", ts.WorkerToken))
	if len(sl.Series) != 1 {
		t.Fatalf("expected exactly 1 series entry after double upsert, got %d", len(sl.Series))
	}
	if sl.Series[0].PrincipalName == nil || *sl.Series[0].PrincipalName != "Nestle" {
		t.Fatalf("expected series joined to principal Nestle, got %+v", sl.Series[0])
	}

	// Buyer branches: create -> list -> delete, against a real buyer.
	buyerResp := ts.post(t, "/api/v1/buyers", ts.AdminToken, map[string]interface{}{
		"name":  "Vishal Mega Mart",
		"gstin": "06AAAAA0013A1ZD",
	})
	type buyer struct {
		ID string `json:"id"`
	}
	// 201 for a fresh buyer, 200 when the seed data already registered this
	// GSTIN — either way we get the buyer row back.
	if buyerResp.StatusCode != http.StatusCreated && buyerResp.StatusCode != http.StatusOK {
		t.Fatalf("create buyer: expected 200/201, got %d", buyerResp.StatusCode)
	}
	b := decodeJSON[buyer](t, buyerResp)

	branchResp := ts.post(t, "/api/v1/buyers/"+b.ID+"/branches", ts.AdminToken,
		map[string]interface{}{"name": "Badshahpur B-04", "code": "B-04", "gate_entry_prefix": "HH26"})
	if branchResp.StatusCode != http.StatusCreated {
		t.Fatalf("create branch: expected 201, got %d", branchResp.StatusCode)
	}
	type branch struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	br := decodeJSON[branch](t, branchResp)

	type branchList struct {
		Branches []branch `json:"branches"`
	}
	perBuyer := decodeJSON[branchList](t, ts.get(t, "/api/v1/buyers/"+b.ID+"/branches", ts.WorkerToken))
	if len(perBuyer.Branches) != 1 || perBuyer.Branches[0].Name != "Badshahpur B-04" {
		t.Fatalf("expected the created branch in per-buyer list, got %+v", perBuyer.Branches)
	}
	allBranches := decodeJSON[branchList](t, ts.get(t, "/api/v1/buyers/branches", ts.WorkerToken))
	if len(allBranches.Branches) != 1 {
		t.Fatalf("expected 1 branch in the full offline-cache list, got %d", len(allBranches.Branches))
	}

	// Buyer meta patch: valid channel + terms, then an invalid channel.
	patchResp := ts.patch(t, "/api/v1/buyers/"+b.ID, ts.AdminToken,
		map[string]interface{}{"sales_channel": "MT", "default_payment_terms_days": 30})
	if patchResp.StatusCode != http.StatusOK {
		t.Fatalf("patch buyer: expected 200, got %d", patchResp.StatusCode)
	}
	type buyerMeta struct {
		SalesChannel            *string `json:"sales_channel"`
		DefaultPaymentTermsDays *int    `json:"default_payment_terms_days"`
	}
	bm := decodeJSON[buyerMeta](t, patchResp)
	if bm.SalesChannel == nil || *bm.SalesChannel != "MT" || bm.DefaultPaymentTermsDays == nil || *bm.DefaultPaymentTermsDays != 30 {
		t.Fatalf("expected patched buyer meta MT/30, got %+v", bm)
	}
	badPatch := ts.patch(t, "/api/v1/buyers/"+b.ID, ts.AdminToken,
		map[string]interface{}{"sales_channel": "MALL"})
	badPatch.Body.Close()
	if badPatch.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid sales_channel, got %d", badPatch.StatusCode)
	}

	// Deletes.
	delBranch := ts.doRequest(t, http.MethodDelete, "/api/v1/buyers/branches/"+br.ID, ts.AdminToken, nil)
	delBranch.Body.Close()
	if delBranch.StatusCode != http.StatusOK {
		t.Fatalf("delete branch: expected 200, got %d", delBranch.StatusCode)
	}
	delPrin := ts.doRequest(t, http.MethodDelete, "/api/v1/principals/"+prin.ID, ts.WorkerToken, nil)
	delPrin.Body.Close()
	if delPrin.StatusCode != http.StatusForbidden {
		t.Fatalf("expected 403 for worker principal delete, got %d", delPrin.StatusCode)
	}
}

// TestGateEntry_MismatchWithoutFlag_AutoRaisesDispute proves the auto-dispute
// fires on a quantity mismatch even when the client does NOT set
// is_short_receipt, and that re-submitting the gate entry stays idempotent
// (exactly one open dispute).
func TestGateEntry_MismatchWithoutFlag_AutoRaisesDispute(t *testing.T) {
	ts := startTestServer(t)
	invoiceID := createTestInvoice(t, ts)
	documentID := mustPrimaryDocumentID(t, ts, invoiceID)

	for i := 0; i < 2; i++ {
		resp := ts.post(t, "/api/v1/invoices/"+invoiceID+"/gate-entry", ts.WorkerToken, map[string]interface{}{
			"document_id":      documentID,
			"accepted_qty":     90.0,
			"invoice_qty":      92.0,
			"is_short_receipt": false,
		})
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("set gate entry attempt %d: expected 200, got %d", i, resp.StatusCode)
		}
	}

	disputesResp := ts.get(t, "/api/v1/disputes?status=OPEN", ts.AdminToken)
	type dispute struct {
		InvoiceID   string `json:"invoice_id"`
		DisputeType string `json:"dispute_type"`
	}
	type disputeList struct {
		Disputes []dispute `json:"disputes"`
	}
	disputes := decodeJSON[disputeList](t, disputesResp).Disputes
	count := 0
	for _, d := range disputes {
		if d.InvoiceID == invoiceID && d.DisputeType == "SHORT_RECEIPT" {
			count++
		}
	}
	if count != 1 {
		t.Fatalf("expected exactly 1 auto-raised SHORT_RECEIPT dispute, got %d", count)
	}
}
