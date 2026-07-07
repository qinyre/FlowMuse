FROM golang:1.25-alpine AS builder

ENV GOPROXY=https://goproxy.cn,direct \
    GOSUMDB=sum.golang.google.cn

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /out/flowmuse-collab-server ./cmd/flowmuse-collab-server

FROM alpine:3.22
WORKDIR /app
COPY --from=builder /out/flowmuse-collab-server /app/flowmuse-collab-server
EXPOSE 48931
ENTRYPOINT ["/app/flowmuse-collab-server"]
