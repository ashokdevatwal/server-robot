BINARY=server-monitor

.PHONY: build test run lint

build:
go build -o $(BINARY) ./cmd/monitor

test:
go test ./...

run: build
./$(BINARY) start

lint:
gofmt -w ./cmd ./internal
