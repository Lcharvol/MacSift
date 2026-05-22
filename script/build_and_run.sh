#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MacSift"
BUNDLE_ID="com.macsift.app"
LOG_SUBSYSTEM="com.lcharvol.MacSift"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

usage() {
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

stop_running_app() {
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
    "$ROOT_DIR/build-app.sh"
}

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
}

verify_app() {
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
}

cd "$ROOT_DIR"

case "$MODE" in
    run)
        stop_running_app
        build_app
        open_app
        ;;
    --debug|debug)
        stop_running_app
        build_app
        lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        stop_running_app
        build_app
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry|telemetry)
        stop_running_app
        build_app
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$LOG_SUBSYSTEM\" || subsystem == \"$BUNDLE_ID\""
        ;;
    --verify|verify)
        stop_running_app
        build_app
        verify_app
        ;;
    *)
        usage
        exit 2
        ;;
esac
