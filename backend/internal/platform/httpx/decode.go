package httpx

import (
	"encoding/json"
	"net/http"
)

const maxBodyBytes = 1 << 20

// DecodeJSON enforces a size limit, a single object and no unknown fields.
func DecodeJSON(w http.ResponseWriter, r *http.Request, dst any) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return BadRequest("Request body must be a single JSON object with known fields.")
	}
	if dec.More() {
		return BadRequest("Request body must contain one JSON object.")
	}
	return nil
}
