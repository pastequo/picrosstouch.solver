.DEFAULT_GOAL := help

SHELL := /bin/bash

##################
# Common variables
###################

# Colors used in this Makefile
escape       := $(shell printf '\033')
RESET_FORMAT := $(escape)[0m
COLOR_RED    := $(escape)[91m
COLOR_YELLOW := $(escape)[38;5;220m
COLOR_GREEN  := $(escape)[0;32m
COLOR_BLUE   := $(escape)[94m
BOLD         := $(escape)[1m

# build and deploy variables
APP_VERSION := $(shell cat $(CURDIR)/VERSION)
GIT_COMMIT := $(shell git rev-list -1 HEAD --abbrev-commit)

IMAGE_NAME := $(DOCKER_REGISTRY)/picrosstouch-solver
IMAGE_TAG := $(APP_VERSION)-$(GIT_COMMIT)
IMAGE_FULL ?= $(or $(IMAGE), $(IMAGE_NAME):$(IMAGE_TAG))

BUILD_DIR := $(CURDIR)/build


#####################
## High level targets
######################

.PHONY: help tools format build check generate

help: help.all
tools: tools.clean tools.get
format: format.imports format.code
build: build.docker
check: check.fmt check.imports check.lint check.licenses
logs: logs.docker
generate: generate.changelog


#########
## Helper
##########

.PHONY: help.all

## help.all: Display this help message
help.all:
	@echo "List of make commands:"
	@grep -hE '^[a-z]+:|^## ' $(MAKEFILE_LIST) | sed 's/## //p' | uniq | \
	awk 'BEGIN {FS = ":";} { \
	if ($$0 ~ /:/) printf("  $(COLOR_BLUE)%-21s$(RESET_FORMAT) %s\n", $$1, $$2); \
	else  printf("\n$(BOLD)%s$(RESET_FORMAT)\n", $$1);    \
	}'


########
## Tools
#########

TOOLS_DIR=$(CURDIR)/tools/bin

.PHONY: tools.clean tools.get

## tools.clean: Remove every tools installed in tools/bin directory
tools.clean:
	@rm -fr $(TOOLS_DIR)/*

## tools.get: Retrieve all tools specified in gex & installed them in tools/bin/
tools.get:
	@cd $(CURDIR)/tools && go generate tools.go


#################
## Format targets
##################

GO_MODULE := $(shell head -n 1 go.mod | cut -d ' ' -f 2)
FILES_LIST := $(shell ls -d */ | grep -v -E "build|tools|vendor")

.PHONY: format.imports format.code

## format.imports: Format go imports
format.imports:
	@$(TOOLS_DIR)/goimports -w -local $(GO_MODULE) $(FILES_LIST)

## format.code: Format go code
format.code:
	@$(TOOLS_DIR)/gofumpt -w $(FILES_LIST)


################
## Check targets
#################

.PHONY: check.licenses check.imports check.fmt check.lint check.test

## check.licenses: Check thirdparties' licences (allow-list in .wwhrd.yml)
check.licenses:
	@$(TOOLS_DIR)/wwhrd check -q

## check.imports: Check if imports are well formated: builtin -> external -> rome -> repo
check.imports:
	@$(TOOLS_DIR)/goimports -l -local $(GO_MODULE) $(FILES_LIST) | wc -l | grep 0

## check.fmt: Check if code is formated according gofumpt rules
check.fmt:
	@$(TOOLS_DIR)/gofumpt -l $(FILES_LIST) | wc -l | grep 0

## check.lint: Run Go linter across the code base without fixing issues
check.lint:
	@$(TOOLS_DIR)/golangci-lint run --timeout 10m

## check.test: Run unit tests and generate coverage report
check.test: build.prepare
	go test ./... -cover -coverprofile=$(BUILD_DIR)/coverage.out.tmp
	cat $(BUILD_DIR)/coverage.out.tmp | grep -vE "/zz_mock_" > $(BUILD_DIR)/coverage.out
	go tool cover -func $(BUILD_DIR)/coverage.out


########
## Build
#########

GO_VERSION := 1.21
BUILD_ENV=CGO_ENABLED=0

.PHONY: build.vendor build.vendor.tidy build.prepare build.local build.docker

## build.vendor: Get dependencies locally
build.vendor:
	go mod vendor

## build.vendor.tidy: Remove unused project's dependencies
build.vendor.tidy:
	go mod tidy

## build.prepare: Create build/ folder
build.prepare:
	@mkdir -p $(BUILD_DIR)

## build.local: Build binary app
build.local: build.prepare
	$(BUILD_ENV) go build \
		-mod readonly     \
		-ldflags "-s -w -extldflags -static \
		  -X 'github.com/prometheus/common/version.Version=$(APP_VERSION)'                  \
		  -X github.com/prometheus/common/version.Revision=$(GIT_COMMIT)                    \
		  -X github.com/prometheus/common/version.Branch=$(shell git branch --show-current) \
		  -X 'github.com/prometheus/common/version.BuildUser=$(shell whoami)'               \
		  -X 'github.com/prometheus/common/version.BuildDate=$(shell date)'                 \
		" \
		-o $(BUILD_DIR)/app \
		$(CURDIR)/cmd/solver/main.go

## build.docker: Build image and tag
build.docker:
	docker build \
		--build-arg GO_VERSION=$(GO_VERSION)    \
		--build-arg CREATION_TIME="$(date -uR)" \
		--build-arg COMMIT=$(GIT_COMMIT)        \
		--build-arg VERSION=$(APP_VERSION)      \
		--ssh default -t $(IMAGE_FULL) .


###########
## Generate
############

.PHONY: generate.changelog

## generate.changelog: Generate a changelog from last tag, based on commit message
generate.changelog:
	$(TOOLS_DIR)/git-chglog --output CHANGELOG.md ..v$(APP_VERSION)


#######
## Logs
########

COLOR_LEVEL_INFO=$(escape)[92m
COLOR_LEVEL_WARN=$(escape)[38;5;208m
COLOR_LEVEL_ERROR=$(escape)[91m

ANYTHING_BETWEEN_QUOTES=\"\([^\"]*\)\"

define COLORIZE
sed -u -e "s/\\\\\"/'/g; \
s/\"caller\":$(ANYTHING_BETWEEN_QUOTES)/\"caller\":\"$(COLOR_BLUE)\1$(RESET_FORMAT)\"/g;         \
s/\"log.logger\":$(ANYTHING_BETWEEN_QUOTES)/\"log.logger\":\"$(COLOR_BLUE)\1$(RESET_FORMAT)\"/g; \
s/\"error\":$(ANYTHING_BETWEEN_QUOTES)/\"error\":\"$(COLOR_RED)\1$(RESET_FORMAT)\"/g;            \
s/\"msg\":$(ANYTHING_BETWEEN_QUOTES)/\"msg\":\"$(COLOR_YELLOW)\1$(RESET_FORMAT)\"/g;             \
s/\"level\":\"info\"/\"level\":\"$(COLOR_LEVEL_INFO)info$(RESET_FORMAT)\"/g;                     \
s/\"level\":\"warning\"/\"level\":\"$(COLOR_LEVEL_WARN)warning$(RESET_FORMAT)\"/g;               \
s/\"level\":\"error\"/\"level\":\"$(COLOR_LEVEL_ERROR)error$(RESET_FORMAT)\"/g"
endef

.PHONY: logs.k8s

## logs.k8s: Display logs of the api
logs.k8s:
	@kubectl logs -n $(NAMESPACE) -f deployment/gladiator-api $(if $(TAIL), --tail=$(TAIL)) | $(COLORIZE)

