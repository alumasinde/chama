// Package httpx holds the error envelope, request context and HTTP middleware.
package httpx

import (
	"fmt"
	"net/http"
)

// Error is a deliberate API failure that maps to one status and one stable code.
type Error struct {
	Status  int
	Code    string
	Message string
	Fields  map[string]string
	Err     error
}

func (e *Error) Error() string {
	if e.Err != nil {
		return fmt.Sprintf("%s: %v", e.Code, e.Err)
	}
	return e.Code
}

func (e *Error) Unwrap() error { return e.Err }

func NewError(status int, code, message string) *Error {
	return &Error{Status: status, Code: code, Message: message}
}

func BadRequest(message string) *Error {
	return NewError(http.StatusBadRequest, "validation_failed", message)
}

func Validation(fields map[string]string) *Error {
	return &Error{Status: http.StatusBadRequest, Code: "validation_failed",
		Message: "Some fields need attention.", Fields: fields}
}

func Unauthorized(message string) *Error {
	return NewError(http.StatusUnauthorized, "unauthorized", message)
}

func Forbidden(message string) *Error {
	return NewError(http.StatusForbidden, "forbidden", message)
}

func StepUpRequired() *Error {
	return NewError(http.StatusForbidden, "step_up_required", "Enter your PIN to continue.")
}

func NotFound(message string) *Error {
	return NewError(http.StatusNotFound, "not_found", message)
}

func Conflict(code, message string) *Error {
	return NewError(http.StatusConflict, code, message)
}

func Unprocessable(code, message string) *Error {
	return NewError(http.StatusUnprocessableEntity, code, message)
}

func TooMany(message string) *Error {
	return NewError(http.StatusTooManyRequests, "rate_limited", message)
}

func Internal(err error) *Error {
	return &Error{Status: http.StatusInternalServerError, Code: "internal_error",
		Message: "Something went wrong on our side.", Err: err}
}
