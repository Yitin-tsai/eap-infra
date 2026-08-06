FROM golang:1.26-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /eap-trigger ./cmd/server

FROM alpine:3.21
COPY --from=builder /eap-trigger /eap-trigger
EXPOSE 8085
CMD ["/eap-trigger"]
