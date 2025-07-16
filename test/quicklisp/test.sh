#!/usr/bin/env bash

set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

# Feature-specific tests
check "Quicklisp" ls ~/quicklisp

# Report result
reportResults