FROM golang:1.22
WORKDIR /app
COPY . .
RUN go mod tidy && go build -o /usr/local/bin/server-monitor ./cmd/monitor
CMD ["/usr/local/bin/server-monitor", "start"]
