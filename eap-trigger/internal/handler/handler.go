package handler

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"eap-trigger/internal/model"
	"eap-trigger/internal/service"
)

// Handler holds all HTTP handlers for the conditional order API.
type Handler struct {
	svc *service.TriggerService
}

func New(svc *service.TriggerService) *Handler {
	return &Handler{svc: svc}
}

// RegisterRoutes adds all routes to the default mux.
// Go 1.22+ supports method+pattern in http.HandleFunc.
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /health", h.health)
	mux.HandleFunc("POST /api/conditional-orders", h.create)
	mux.HandleFunc("GET /api/conditional-orders/{id}", h.getByID)
	mux.HandleFunc("DELETE /api/conditional-orders/{id}", h.cancel)
	mux.HandleFunc("GET /api/users/{userId}/conditional-orders", h.getByUserID)
}

// POST /api/conditional-orders
func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	var req model.CreateConditionalOrderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	if msg := req.Validate(); msg != "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": msg})
		return
	}

	order, err := h.svc.Create(&req)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusCreated, order)
}

// GET /api/conditional-orders/{id}
func (h *Handler) getByID(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid id"})
		return
	}

	order, err := h.svc.GetByID(id)
	if err != nil {
		if strings.Contains(err.Error(), "no rows") {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "not found"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, order)
}

// DELETE /api/conditional-orders/{id}
func (h *Handler) cancel(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid id"})
		return
	}

	ok, err := h.svc.Cancel(id)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	if !ok {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "not found or not pending"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "cancelled"})
}

// GET /api/users/{userId}/conditional-orders
func (h *Handler) getByUserID(w http.ResponseWriter, r *http.Request) {
	userID := r.PathValue("userId")
	orders, err := h.svc.GetByUserID(userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	if orders == nil {
		orders = []model.ConditionalOrder{} // return [] not null
	}
	writeJSON(w, http.StatusOK, orders)
}

// GET /health
func (h *Handler) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"status":        "ok",
		"service":       "eap-trigger",
		"pendingOrders": h.svc.PendingCount(),
	})
}

func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}
