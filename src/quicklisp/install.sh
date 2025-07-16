#!/bin/bash

# TODO: parametrize and test for the lisp implementation, now hardcoded to SBCL
USERNAME=${USERNAME:-${_REMOTE_USER:-"automatic"}}

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
    for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
        if id -u "${CURRENT_USER}" >/dev/null 2>&1; then
            USERNAME=${CURRENT_USER}
            break
        fi
    done
    if [ "${USERNAME}" = "" ]; then
        USERNAME=root
    fi
elif [ "${USERNAME}" = "none" ] || ! id -u "${USERNAME}" >/dev/null 2>&1; then
    USERNAME=root
fi

cleanup_apt() {
    source /etc/os-release
    if [ "${ID}" = "debian" ] || [ "${ID_LIKE}" = "debian" ]; then
        rm -rf /var/lib/apt/lists/*
    fi
}

# Checks if packages are installed and installs them if not
check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
            echo "Running apt-get update..."
            apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false update -y
        fi
        apt-get -y install --no-install-recommends "$@"
    fi
}

cleanup_build_packages() {
    echo "Cleaning up build packages..."
    apt-get remove --purge -y "$@"
    apt-get autoremove -y
    echo "Build packages cleaned up."
}

install_quicklisp() {
    echo "Installing Quicklisp..."
    if [ -z "$DIST_VERSION" ] || [ "$DIST_VERSION" = "latest" ]; then
        DIST_VERSION=nil
    else
        DIST_VERSION="\"quicklisp/$DIST_VERSION\""
    fi

    if [ -z "$CLIENT_VERSION" ] || [ "$CLIENT_VERSION" = "latest" ]; then
        CLIENT_VERSION=nil
    else
        CLIENT_VERSION="\"$CLIENT_VERSION\""
    fi

    su ${USERNAME} -c "curl -fsSL \"https://beta.quicklisp.org/quicklisp.lisp\" > /tmp/quicklisp.lisp"

    su ${USERNAME} -c "sbcl --non-interactive \
        --load /tmp/quicklisp.lisp \
        --eval \"(quicklisp-quickstart:install :dist-version ${DIST_VERSION} :client-version ${CLIENT_VERSION})\" \
        --eval \"(ql-util:without-prompting (ql:add-to-init-file))\""

    rm /tmp/quicklisp.lisp
}

# Main script execution starts here
export DEBIAN_FRONTEND=noninteractive
# Check if quicklisp is already installed
USER_HOME=$(eval echo "~${USERNAME}")
if [ -f "${USER_HOME}/quicklisp/setup.lisp" ]; then
    echo "Quicklisp is already installed."
    exit 0
fi
echo "Installing Quicklisp..."
check_packages curl ca-certificates
install_quicklisp
if [ "${MAKE_SLIM}" = "true" ]; then
    echo "Removing build dependencies for slim image..."
    cleanup_build_packages curl ca-certificates
fi
cleanup_apt
echo "Done!"