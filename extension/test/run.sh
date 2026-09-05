#!/bin/sh
# Optional runner for the extension's pure-function tests.
# Usage: extension/test/run.sh   (equivalent to: node --test extension/test/)
DIR="$(cd "$(dirname "$0")" && pwd)"
exec node --test "$DIR/picker-selectors.test.mjs"
