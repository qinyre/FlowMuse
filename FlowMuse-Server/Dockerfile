FROM golang:1.25-alpine AS builder

ENV GOPROXY=https://goproxy.cn|https://proxy.golang.org|direct \
    GOSUMDB=sum.golang.google.cn

WORKDIR /src
RUN apk add --no-cache ca-certificates git
COPY go.mod go.sum ./
COPY third_party/engine.io ./third_party/engine.io
RUN go mod download
COPY . .
RUN go build -o /out/flowmuse-collab-server ./cmd/flowmuse-collab-server

FROM alpine:3.22
WORKDIR /app
COPY --from=builder /out/flowmuse-collab-server /app/flowmuse-collab-server
COPY NOTICES /app/NOTICES
EXPOSE 48931
ENTRYPOINT ["/app/flowmuse-collab-server"]
