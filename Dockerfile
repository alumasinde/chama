# Build the static binary, then run it on distroless.
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY backend/go.mod backend/go.sum* ./
RUN go mod download
COPY backend/ ./
RUN go run ./cmd/brandgen \
    && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /out/chama-server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/chama-server /chama-server
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/chama-server"]
