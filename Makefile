.PHONY: build test analyze format clean

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")

build:
	mkdir -p build
	dart compile exe bin/flutpak.dart -o build/flutpak --define=version=$(VERSION)

test:
	dart test

analyze:
	dart analyze --fatal-infos

format:
	dart format bin/ lib/ test/

clean:
	rm -rf build
