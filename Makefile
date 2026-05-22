SHELL := /bin/bash

.PHONY: dev build test logs telemetry debug verify clean

dev:
	./script/build_and_run.sh

build:
	swift build

test:
	swift test

logs:
	./script/build_and_run.sh --logs

telemetry:
	./script/build_and_run.sh --telemetry

debug:
	./script/build_and_run.sh --debug

verify:
	./script/build_and_run.sh --verify

clean:
	swift package clean
