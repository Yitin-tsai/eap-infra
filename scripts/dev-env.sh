#!/usr/bin/env bash

# Source this file in a shell session before running Gradle/Go commands manually.
# It keeps all tool caches inside the workspace so a new Mac does not depend on
# writable home-directory paths.

export EAP_ROOT="${EAP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export EAP_CACHE="${EAP_CACHE:-$EAP_ROOT/.cache}"

export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$EAP_CACHE/gradle}"
export GOCACHE="${GOCACHE:-$EAP_CACHE/go-build}"
export GOMODCACHE="${GOMODCACHE:-$EAP_CACHE/go-mod}"
export GOPATH="${GOPATH:-$EAP_CACHE/go}"

export PATH="$GOPATH/bin:$PATH"

mkdir -p "$GRADLE_USER_HOME" "$GOCACHE" "$GOMODCACHE" "$GOPATH/bin"

echo "EAP dev environment loaded."
echo "  GRADLE_USER_HOME=$GRADLE_USER_HOME"
echo "  GOCACHE=$GOCACHE"
echo "  GOMODCACHE=$GOMODCACHE"
echo "  GOPATH=$GOPATH"
