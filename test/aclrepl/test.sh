#!/usr/bin/env bash

set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

# Feature-specific tests
check "aclrepl" grep "(require 'sb-aclrepl)" ~/.sbclrc

# Report result
reportResults