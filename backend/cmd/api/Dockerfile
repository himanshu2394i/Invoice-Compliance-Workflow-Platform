FROM golang:1.25-alpine AS build

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -o /api ./cmd/api

FROM alpine:3.20

COPY --from=build /api /api

EXPOSE 8000
CMD ["/api"]
