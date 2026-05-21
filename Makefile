.PHONY: version build test

version:
	dart run tool/update_version.dart

build: version
	dart compile exe bin/flutpak.dart -o flutpak

test:
	dart test
