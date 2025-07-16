#!/usr/bin/env bash

set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

# Feature-specific tests
# TODO: Add tests for jupyter feature
#check "jupyter" jupyter --version

# Report result
reportResults