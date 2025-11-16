# Multi-stage build for webhook server
FROM golang:1.21-alpine AS builder

WORKDIR /build

# Copy go module files
COPY go.mod go.sum* ./

# Download dependencies if go.mod exists
RUN if [ -f go.mod ]; then go mod download; fi

# Copy source code
COPY main.go ./

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o webhook .

# Final stage - minimal runtime image
FROM alpine:3.19

# Install ca-certificates for HTTPS requests
RUN apk --no-cache add ca-certificates

WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/webhook .

# Create non-root user
RUN addgroup -g 1000 webhook && \
    adduser -D -u 1000 -G webhook webhook

# Switch to non-root user
USER webhook

# Expose webhook port
EXPOSE 8090

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8090/health || exit 1

# Run the webhook server
CMD ["./webhook"]
