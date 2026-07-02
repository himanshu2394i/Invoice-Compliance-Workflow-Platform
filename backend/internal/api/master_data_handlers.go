package api

// Master-data management: principals, invoice-series registry, buyer
// branches, and buyer channel/terms. Reads are open to any authenticated
// user (the capture flow caches series/branches offline); writes are
// ADMIN-only (enforced at route registration in api.go).

import (
	"encoding/json"
	"net/http"

	"github.com/jackc/pgx/v5"

	"github.com/himanshu2394i/invoice-saas/internal/db"
)

// ─── Principals ───────────────────────────────────────────────────────────────

type CreatePrincipalRequest struct {
	Name string  `json:"name"`
	Code *string `json:"code,omitempty"`
}

func (s *Server) handleCreatePrincipal(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	var req CreatePrincipalRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	if req.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	p, err := s.Repo.CreatePrincipal(r.Context(), tenantID, req.Name, req.Code)
	if err != nil {
		writeError(w, http.StatusConflict, "Failed to create principal (duplicate name?): "+err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, p)
}

func (s *Server) handleListPrincipals(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	list, err := s.Repo.ListPrincipals(r.Context(), tenantID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to list principals: "+err.Error())
		return
	}
	if list == nil {
		list = []*db.Principal{}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"principals": list})
}

func (s *Server) handleDeletePrincipal(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	if err := s.Repo.DeletePrincipal(r.Context(), tenantID, r.PathValue("id")); err != nil {
		if err == pgx.ErrNoRows {
			writeError(w, http.StatusNotFound, "Principal not found")
			return
		}
		writeError(w, http.StatusConflict, "Failed to delete principal (still referenced?): "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// ─── Series Registry ──────────────────────────────────────────────────────────

type UpsertSeriesRequest struct {
	SeriesPrefix string  `json:"series_prefix"`
	EntityID     *string `json:"entity_id,omitempty"`
	PrincipalID  *string `json:"principal_id,omitempty"`
}

func (s *Server) handleUpsertSeriesEntry(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	var req UpsertSeriesRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	if req.SeriesPrefix == "" {
		writeError(w, http.StatusBadRequest, "series_prefix is required")
		return
	}
	entry, err := s.Repo.UpsertSeriesEntry(r.Context(), tenantID, req.SeriesPrefix, req.EntityID, req.PrincipalID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to save series entry: "+err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, entry)
}

func (s *Server) handleListSeriesRegistry(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	list, err := s.Repo.ListSeriesRegistry(r.Context(), tenantID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to list series registry: "+err.Error())
		return
	}
	if list == nil {
		list = []*db.SeriesRegistryEntry{}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"series": list})
}

func (s *Server) handleDeleteSeriesEntry(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	if err := s.Repo.DeleteSeriesEntry(r.Context(), tenantID, r.PathValue("id")); err != nil {
		if err == pgx.ErrNoRows {
			writeError(w, http.StatusNotFound, "Series entry not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "Failed to delete series entry: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// ─── Buyer Branches ───────────────────────────────────────────────────────────

type CreateBuyerBranchRequest struct {
	Name            string          `json:"name"`
	Code            *string         `json:"code,omitempty"`
	Address         json.RawMessage `json:"address,omitempty"`
	GateEntryPrefix *string         `json:"gate_entry_prefix,omitempty"`
}

func (s *Server) handleCreateBuyerBranch(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	buyerID := r.PathValue("id")

	if _, err := s.Repo.GetBuyerByID(r.Context(), tenantID, buyerID); err != nil {
		writeError(w, http.StatusNotFound, "Buyer not found")
		return
	}
	var req CreateBuyerBranchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	if req.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	branch := &db.BuyerBranch{
		BuyerID:         buyerID,
		Name:            req.Name,
		Code:            req.Code,
		Address:         req.Address,
		GateEntryPrefix: req.GateEntryPrefix,
	}
	if err := s.Repo.CreateBuyerBranch(r.Context(), tenantID, branch); err != nil {
		writeError(w, http.StatusConflict, "Failed to create branch (duplicate name?): "+err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, branch)
}

// handleListBuyerBranches serves both /buyers/{id}/branches and, with an
// empty buyer filter, /buyers/branches (the capture flow's full offline
// cache).
func (s *Server) handleListBuyerBranches(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	buyerID := r.PathValue("id") // empty on the /buyers/branches route
	list, err := s.Repo.ListBuyerBranches(r.Context(), tenantID, buyerID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Failed to list branches: "+err.Error())
		return
	}
	if list == nil {
		list = []*db.BuyerBranch{}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"branches": list})
}

func (s *Server) handleDeleteBuyerBranch(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	if err := s.Repo.DeleteBuyerBranch(r.Context(), tenantID, r.PathValue("branch_id")); err != nil {
		if err == pgx.ErrNoRows {
			writeError(w, http.StatusNotFound, "Branch not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "Failed to delete branch: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// ─── Buyer Meta (channel + default terms) ─────────────────────────────────────

type PatchBuyerRequest struct {
	SalesChannel            *string `json:"sales_channel,omitempty"`
	DefaultPaymentTermsDays *int    `json:"default_payment_terms_days,omitempty"`
}

var validSalesChannels = map[string]bool{
	"GT": true, "MT": true, "ECOM": true, "HOSPITALITY": true, "INDUSTRIAL": true,
}

func (s *Server) handlePatchBuyer(w http.ResponseWriter, r *http.Request) {
	tenantID := claimsFromContext(r.Context()).OrganizationID
	buyerID := r.PathValue("id")

	var req PatchBuyerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	if req.SalesChannel == nil && req.DefaultPaymentTermsDays == nil {
		writeError(w, http.StatusBadRequest, "nothing to update")
		return
	}
	if req.SalesChannel != nil && !validSalesChannels[*req.SalesChannel] {
		writeError(w, http.StatusBadRequest, "sales_channel must be one of GT, MT, ECOM, HOSPITALITY, INDUSTRIAL")
		return
	}
	if req.DefaultPaymentTermsDays != nil && *req.DefaultPaymentTermsDays < 0 {
		writeError(w, http.StatusBadRequest, "default_payment_terms_days must be >= 0")
		return
	}
	if err := s.Repo.UpdateBuyerMeta(r.Context(), tenantID, buyerID, req.SalesChannel, req.DefaultPaymentTermsDays); err != nil {
		if err == pgx.ErrNoRows {
			writeError(w, http.StatusNotFound, "Buyer not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "Failed to update buyer: "+err.Error())
		return
	}
	buyer, err := s.Repo.GetBuyerByID(r.Context(), tenantID, buyerID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Updated but failed to reload buyer: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, buyer)
}
