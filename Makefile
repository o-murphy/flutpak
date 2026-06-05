.PHONY: build test analyze clean

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")

build:
	mkdir -p build
	dart compile exe bin/flutpak.dart -o build/flutpak --define=version=$(VERSION)

test:
	dart test

analyze:
	dart analyze --fatal-infos

clean:
	rm -rf build
