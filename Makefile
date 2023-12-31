SERVER_DIR := https/server
CLIENT_DIR := https/client
SCRIPT_DIR := scripts
GOFLAGS := -ldflags="-s -w"
GOOS := linux
GOARCH := amd64

.PHONY: all build-server build-client clean gen-certs release

all: build-server build-client

build-server:
	@echo "Building server..."
	@cd $(SERVER_DIR) && \
	GOOS=$(GOOS) GOARCH=$(GOARCH) go build $(GOFLAGS) -o server

build-client:
	@echo "Building client..."
	@cd $(CLIENT_DIR) && \
	GOOS=$(GOOS) GOARCH=$(GOARCH) go build $(GOFLAGS) -o client

clean:
	@echo "Cleaning up server and client binaries..."
	@rm -f $(SERVER_DIR)/server $(CLIENT_DIR)/client
	@rm -f scripts/ca.* scripts/*.csr scripts/*.crt scripts/*.key
	@rm -f server.tar.gz client.tar.gz
	@rm -rf server_build client_build

gen-certs:
	@echo "Generating certificates..."
	@(cd scripts && ./gen_certs.sh)

release: build-server build-client gen-certs
	@echo "Preparing server release..."
	@mkdir -p server_build && \
	cp https/server/server server_build/ && \
	cp scripts/ca.crt server_build/ && \
	cp scripts/server.crt server_build/ && \
	cp scripts/server.csr server_build/ && \
	cp scripts/server.key server_build/
	tar -czvf server.tar.gz server_build/

	@echo "Preparing client release..."
	@mkdir -p client_build && \
	cp https/client/client client_build/ && \
	cp scripts/ca.crt client_build/ && \
	cp scripts/client.crt client_build/ && \
	cp scripts/client.csr client_build/ && \
	cp scripts/client.key client_build/
	tar -czvf client.tar.gz client_build/