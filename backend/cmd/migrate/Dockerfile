FROM golang:1.25-alpine AS build

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -o /migrate ./cmd/migrate

FROM alpine:3.20

WORKDIR /app
COPY --from=build /migrate /migrate
COPY db/migrations ./db/migrations

ENTRYPOINT ["/migrate"]
