.PHONY: build test

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")

build:
	dart compile exe bin/flutpak.dart -o flutpak --define=version=$(VERSION)

test:
	dart test
