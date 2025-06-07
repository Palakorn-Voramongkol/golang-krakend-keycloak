# Dockerfile

# ─────────────────────────────────────────────────────────────
# Stage 1: build with Go
# ─────────────────────────────────────────────────────────────
FROM golang:tip-alpine3.22 AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /fiber-demo .

# ─────────────────────────────────────────────────────────────
# Stage 2: minimal runtime on Alpine (Linux)
# ─────────────────────────────────────────────────────────────
FROM alpine:latest

RUN apk add --no-cache ca-certificates
# Install curl so the healthcheck can run
RUN apk add --no-cache curl

COPY --from=builder /fiber-demo /fiber-demo

EXPOSE 3000
CMD ["/fiber-demo"]