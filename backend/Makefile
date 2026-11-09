SHELL := /bin/sh
BIN := ../bin/chama-server

.PHONY: brand sqlc migrate migrate-down migrate-version run build test vet size tidy

brand:
	go run ./cmd/brandgen -file ../branding.json -out internal/platform/brand/brand.gen.go

sqlc:
	sqlc generate

migrate:
	go run ./cmd/migrate up

migrate-down:
	go run ./cmd/migrate down

migrate-version:
	go run ./cmd/migrate version

run: brand
	go run ./cmd/server

build: brand
	CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o $(BIN) ./cmd/server

test:
	go test ./...

vet:
	go vet ./...

size:
	../scripts/check-size.sh

tidy:
	go mod tidy
