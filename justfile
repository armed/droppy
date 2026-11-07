install-dir := env("DROPPY_INSTALL_DIR", "/Applications/Droppy.app")

[private]
default:
    @just --list

build:
    scripts/build-app.sh release

install: build
    #!/usr/bin/env bash
    set -euo pipefail
    target="{{ install-dir }}"
    if [ -z "$target" ] || [ "$target" = / ] || [ "${target##*.}" != app ]; then
        echo "refusing install-dir '$target'" >&2; exit 1
    fi
    parent="$(dirname "$target")"
    [ -d "$parent" ] || { echo "$parent does not exist" >&2; exit 1; }
    if pgrep -x Droppy >/dev/null; then
        # The bundle id matches the dev build too, which a quit by app name would miss.
        osascript -e 'tell application id "dev.droppy.Droppy" to quit' >/dev/null 2>&1 &
        for _ in $(seq 100); do pgrep -x Droppy >/dev/null || break; sleep 0.1; done
        # A forced exit would kill the user's shells, so a declined quit aborts instead.
        if pgrep -x Droppy >/dev/null; then
            echo "Droppy is still running (declined or busy); nothing was changed" >&2; exit 1
        fi
    fi
    tmp="$target.new"
    rm -rf "$tmp"
    ditto .build/Droppy.app "$tmp" || { rm -rf "$tmp"; echo "copy failed; old version kept" >&2; exit 1; }
    rm -rf "$target"
    mv "$tmp" "$target"
    open "$target"
    sleep 2
    pgrep -fl "$target/Contents/MacOS/Droppy" >/dev/null || { echo "installed, but $target is not running" >&2; exit 1; }
    echo "installed $target ($(du -sh "$target" | cut -f1), binary $(stat -f%z "$target/Contents/MacOS/Droppy") bytes)"

clean:
    swift package clean
