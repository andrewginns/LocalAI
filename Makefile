GOCMD=go
GOTEST=$(GOCMD) test
GOVET=$(GOCMD) vet
BINARY_NAME=local-ai

# llama.cpp versions
GOLLAMA_VERSION?=371ecd13c7fe00d281cb19c6588574134d7091b1

GOLLAMA_STABLE_VERSION?=50cee7712066d9e38306eccadcfbb44ea87df4b7

# gpt4all version
GPT4ALL_REPO?=https://github.com/nomic-ai/gpt4all
GPT4ALL_VERSION?=27a8b020c36b0df8f8b82a252d261cda47cf44b8

export BUILD_TYPE?=
CGO_LDFLAGS?=
CUDA_LIBPATH?=/usr/local/cuda/lib64/
GO_TAGS?=
BUILD_ID?=git

VERSION?=$(shell git describe --always --tags || echo "dev" )
# go tool nm ./local-ai | grep Commit
LD_FLAGS?=
override LD_FLAGS += -X "github.com/go-skynet/LocalAI/internal.Version=$(VERSION)"
override LD_FLAGS += -X "github.com/go-skynet/LocalAI/internal.Commit=$(shell git rev-parse HEAD)"

OPTIONAL_TARGETS?=

OS := $(shell uname -s)
ARCH := $(shell uname -m)
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
CYAN   := $(shell tput -Txterm setaf 6)
RESET  := $(shell tput -Txterm sgr0)

ifndef UNAME_S
UNAME_S := $(shell uname -s)
endif

# workaround for rwkv.cpp
ifeq ($(UNAME_S),Darwin)
	CGO_LDFLAGS += -lcblas -framework Accelerate
endif

ifeq ($(BUILD_TYPE),openblas)
	CGO_LDFLAGS+=-lopenblas
endif

ifeq ($(BUILD_TYPE),cublas)
	CGO_LDFLAGS+=-lcublas -lcudart -L$(CUDA_LIBPATH)
	export LLAMA_CUBLAS=1
endif

ifeq ($(BUILD_TYPE),metal)
	CGO_LDFLAGS+=-framework Foundation -framework Metal -framework MetalKit -framework MetalPerformanceShaders
	export LLAMA_METAL=1
endif

ifeq ($(BUILD_TYPE),clblas)
	CGO_LDFLAGS+=-lOpenCL -lclblast
endif

# glibc-static or glibc-devel-static required
ifeq ($(STATIC),true)
	LD_FLAGS=-linkmode external -extldflags -static
endif

GRPC_BACKENDS?=backend-assets/grpc/langchain-huggingface backend-assets/grpc/falcon-ggml backend-assets/grpc/llama backend-assets/grpc/llama-stable backend-assets/grpc/gpt4all backend-assets/grpc/dolly backend-assets/grpc/gpt2 backend-assets/grpc/gptj backend-assets/grpc/gptneox backend-assets/grpc/mpt backend-assets/grpc/replit backend-assets/grpc/starcoder $(OPTIONAL_GRPC)

all: help

# Modelling backends
## GPT4ALL
gpt4all:
	git clone --recurse-submodules $(GPT4ALL_REPO) gpt4all
	cd gpt4all && git checkout -b build $(GPT4ALL_VERSION) && git submodule update --init --recursive --depth 1

backend-assets/gpt4all: gpt4all/gpt4all-bindings/golang/libgpt4all.a
	mkdir -p backend-assets/gpt4all
	@cp gpt4all/gpt4all-bindings/golang/buildllm/*.so backend-assets/gpt4all/ || true
	@cp gpt4all/gpt4all-bindings/golang/buildllm/*.dylib backend-assets/gpt4all/ || true
	@cp gpt4all/gpt4all-bindings/golang/buildllm/*.dll backend-assets/gpt4all/ || true

gpt4all/gpt4all-bindings/golang/libgpt4all.a: gpt4all
	$(MAKE) -C gpt4all/gpt4all-bindings/golang/ libgpt4all.a

## CEREBRAS GPT
go-ggml-transformers:
	git clone --recurse-submodules https://github.com/go-skynet/go-ggml-transformers.cpp go-ggml-transformers
	cd go-ggml-transformers && git checkout -b build $(GOGPT2_VERSION) && git submodule update --init --recursive --depth 1

go-ggml-transformers/libtransformers.a: go-ggml-transformers
	$(MAKE) -C go-ggml-transformers BUILD_TYPE=$(BUILD_TYPE) libtransformers.a

go-llama:
	git clone --recurse-submodules https://github.com/go-skynet/go-llama.cpp go-llama
	cd go-llama && git checkout -b build $(GOLLAMA_VERSION) && git submodule update --init --recursive --depth 1

go-llama-stable:
	git clone --recurse-submodules https://github.com/go-skynet/go-llama.cpp go-llama-stable
	cd go-llama-stable && git checkout -b build $(GOLLAMA_STABLE_VERSION) && git submodule update --init --recursive --depth 1

go-llama/libbinding.a: go-llama
	$(MAKE) -C go-llama BUILD_TYPE=$(BUILD_TYPE) libbinding.a

go-llama-stable/libbinding.a: go-llama-stable
	$(MAKE) -C go-llama-stable BUILD_TYPE=$(BUILD_TYPE) libbinding.a

get-sources: go-llama go-llama-stable go-ggml-transformers gpt4all
	touch $@

replace:
	$(GOCMD) mod edit -replace github.com/nomic-ai/gpt4all/gpt4all-bindings/golang=$(shell pwd)/gpt4all/gpt4all-bindings/golang
	$(GOCMD) mod edit -replace github.com/go-skynet/go-ggml-transformers.cpp=$(shell pwd)/go-ggml-transformers

prepare-sources: get-sources replace
	$(GOCMD) mod download

## GENERIC
rebuild: ## Rebuilds the project
	$(GOCMD) clean -cache
	$(MAKE) -C go-llama clean
	$(MAKE) -C go-llama-stable clean
	$(MAKE) -C gpt4all/gpt4all-bindings/golang/ clean
	$(MAKE) -C go-ggml-transformers clean
	# $(MAKE) build

prepare: prepare-sources $(OPTIONAL_TARGETS)
	touch $@

clean: ## Remove build related file
	$(GOCMD) clean -cache
	$(MAKE) -C go-llama clean
	$(MAKE) -C go-llama-stable clean
	$(MAKE) -C gpt4all/gpt4all-bindings/golang/ clean
	$(MAKE) -C go-ggml-transformers clean
	rm -f prepare
	rm -rf ./go-llama
	rm -rf ./gpt4all
	rm -rf ./go-llama-stable
	rm -rf ./go-gpt2
	rm -rf ./go-stable-diffusion
	rm -rf ./go-ggml-transformers
	rm -rf ./backend-assets
	rm -rf ./go-rwkv
	rm -rf ./go-bert
	rm -rf ./bloomz
	rm -rf ./whisper.cpp
	rm -rf ./go-piper
	rm -rf ./go-ggllm
	rm -rf $(BINARY_NAME)
	rm -rf release/

## Help:
help: ## Show this help.
	@echo ''
	@echo 'Usage:'
	@echo '  ${YELLOW}make${RESET} ${GREEN}<target>${RESET}'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} { \
		if (/^[a-zA-Z_-]+:.*?##.*$$/) {printf "    ${YELLOW}%-20s${GREEN}%s${RESET}\n", $$1, $$2} \
		else if (/^## .*$$/) {printf "  ${CYAN}%s${RESET}\n", substr($$1,4)} \
		}' $(MAKEFILE_LIST)

## GRPC

backend-assets/grpc:
	mkdir -p backend-assets/grpc

backend-assets/grpc/llama: backend-assets/grpc go-llama/libbinding.a
	$(GOCMD) mod edit -replace github.com/go-skynet/go-llama.cpp=$(shell pwd)/go-llama
	CGO_LDFLAGS="$(CGO_LDFLAGS)" C_INCLUDE_PATH=$(shell pwd)/go-llama LIBRARY_PATH=$(shell pwd)/go-llama \
	$(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o backend-assets/grpc/llama ./cmd/grpc/llama/
# TODO: every binary should have its own folder instead, so can have different metal implementations
ifeq ($(BUILD_TYPE),metal)
	cp go-llama/build/bin/ggml-metal.metal backend-assets/grpc/
endif

backend-assets/grpc/llama-stable: backend-assets/grpc go-llama-stable/libbinding.a
	$(GOCMD) mod edit -replace github.com/go-skynet/go-llama.cpp=$(shell pwd)/go-llama-stable
	CGO_LDFLAGS="$(CGO_LDFLAGS)" C_INCLUDE_PATH=$(shell pwd)/go-llama-stable LIBRARY_PATH=$(shell pwd)/go-llama \
	$(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o backend-assets/grpc/llama-stable ./cmd/grpc/llama-stable/

backend-assets/grpc/gpt4all: backend-assets/grpc backend-assets/gpt4all gpt4all/gpt4all-bindings/golang/libgpt4all.a
	CGO_LDFLAGS="$(CGO_LDFLAGS)" C_INCLUDE_PATH=$(shell pwd)/gpt4all/gpt4all-bindings/golang/ LIBRARY_PATH=$(shell pwd)/gpt4all/gpt4all-bindings/golang/ \
	$(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o backend-assets/grpc/gpt4all ./cmd/grpc/gpt4all/

backend-assets/grpc/dolly: backend-assets/grpc go-ggml-transformers/libtransformers.a
	CGO_LDFLAGS="$(CGO_LDFLAGS)" C_INCLUDE_PATH=$(shell pwd)/go-ggml-transformers LIBRARY_PATH=$(shell pwd)/go-ggml-transformers \
	$(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o backend-assets/grpc/dolly ./cmd/grpc/dolly/

backend-assets/grpc/gpt2: backend-assets/grpc go-ggml-transformers/libtransformers.a
	CGO_LDFLAGS="$(CGO_LDFLAGS)" C_INCLUDE_PATH=$(shell pwd)/go-ggml-transformers LIBRARY_PATH=$(shell pwd)/go-ggml-transformers \
	$(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o backend-assets/grpc/gpt2 ./cmd/grpc/gpt2/

backend-assets/grpc/gptj: backend-assets/grpc go-ggml-transformers/libtransformers.a
	CGO_LDFLAGS="$(CGO_LDFLAGS)" C_INCLUDE_PATH=$(shell pwd)/go-ggml-transformers LIBRARY_PATH=$(shell pwd)/go-ggml-transformers \
	$(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o backend-assets/grpc/gptj ./cmd/grpc/gptj/

backend-assets/grpc/gptneox: backend-assets/grpc go-ggml-transformers/libtransformers.a
	CGO_LDFLAGS="$(CGO_LDFLAGS)" C_INCLUDE_PATH=$(shell pwd)/go-ggml-transformers LIBRARY_PATH=$(shell pwd)/go-ggml-transformers \
	$(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o backend-assets/grpc/gptneox ./cmd/grpc/gptneox/

backend-assets/grpc/mpt: backend-assets/grpc go-ggml-transformers/libtransformers.a
	CGO_LDFLAGS="$(CGO_LDFLAGS)" C_INCLUDE_PATH=$(shell pwd)/go-ggml-transformers LIBRARY_PATH=$(shell pwd)/go-ggml-transformers \
	$(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o backend-assets/grpc/mpt ./cmd/grpc/mpt/

backend-assets/grpc/replit: backend-assets/grpc go-ggml-transformers/libtransformers.a
	CGO_LDFLAGS="$(CGO_LDFLAGS)" C_INCLUDE_PATH=$(shell pwd)/go-ggml-transformers LIBRARY_PATH=$(shell pwd)/go-ggml-transformers \
	$(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o backend-assets/grpc/replit ./cmd/grpc/replit/

backend-assets/grpc/falcon-ggml: backend-assets/grpc go-ggml-transformers/libtransformers.a
	CGO_LDFLAGS="$(CGO_LDFLAGS)" C_INCLUDE_PATH=$(shell pwd)/go-ggml-transformers LIBRARY_PATH=$(shell pwd)/go-ggml-transformers \
	$(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o backend-assets/grpc/falcon-ggml ./cmd/grpc/falcon-ggml/

backend-assets/grpc/starcoder: backend-assets/grpc go-ggml-transformers/libtransformers.a
	CGO_LDFLAGS="$(CGO_LDFLAGS)" C_INCLUDE_PATH=$(shell pwd)/go-ggml-transformers LIBRARY_PATH=$(shell pwd)/go-ggml-transformers \
	$(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o backend-assets/grpc/starcoder ./cmd/grpc/starcoder/

backend-assets/grpc/langchain-huggingface: backend-assets/grpc
	$(GOCMD) build -ldflags "$(LD_FLAGS)" -tags "$(GO_TAGS)" -o backend-assets/grpc/langchain-huggingface ./cmd/grpc/langchain-huggingface/

grpcs: prepare $(GRPC_BACKENDS)
