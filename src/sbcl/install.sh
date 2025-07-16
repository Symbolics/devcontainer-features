#!/bin/bash

IMPLEMENTATION="sbcl"
USERNAME=${USERNAME:-${_REMOTE_USER:-"automatic"}}

set -ex

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
            # Disable date validation to avoid issues with expired repositories
            apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false update -y
        fi
        apt-get -y install --no-install-recommends "$@"
    fi
}

export DEBIAN_FRONTEND=noninteractive

install_sbcl() {
# If IMPLEMENTATION_VERSION is not set or is 'latest' use the latest version from SourceForge
if [ -z "${IMPLEMENTATION_VERSION}" ] || [ "${IMPLEMENTATION_VERSION}" = "latest" ]; then
    _URL=https://sourceforge.net/projects/sbcl/files/latest/download
else
    _URL="https://downloads.sourceforge.net/project/sbcl/sbcl/${IMPLEMENTATION_VERSION}/sbcl-${IMPLEMENTATION_VERSION}-source.tar.bz2"
fi

echo "Installing $IMPLEMENTATION version ${IMPLEMENTATION_VERSION}..."
WORKDIR=/usr/local/src
mkdir -p "${WORKDIR}/${IMPLEMENTATION}"
cd ${WORKDIR}/${IMPLEMENTATION}

curl -L "${_URL}" | tar xjf - --strip-components=1
if [ ! -f "make.sh" ] || [ ! -f "install.sh" ]; then
    echo "Failed to download or extract SBCL source files."
    exit 1
fi

# Build and install the implementation
sh make.sh --prefix=/usr/local --fancy
sh install.sh

# Cleanup intermediate files
rm -rf output
rm -rf obj
}

cleanup_build_packages() {
    echo "Cleaning up build packages..."
    apt-get remove --purge -y "$@"
    apt-get autoremove -y
    echo "Build packages cleaned up."
}

configure_asdf() {
    echo "Configuring ASDF source registry..."
    mkdir -p /etc/common-lisp/source-registry.conf.d/
    cat <<EOF > /etc/common-lisp/source-registry.conf.d/51-src.conf
;;; -*- Mode: LISP; Syntax: Ansi-Common-Lisp; Base: 10;-*-

;;; Tell ASDF to look in /usr/local/src for system definitions.
(:tree "/usr/local/src")
(:tree "/workspaces")
EOF

    cat <<EOF > /etc/common-lisp/source-registry.conf.d/50-slime.conf
;;; -*- Mode: LISP; Syntax: Ansi-Common-Lisp; Base: 10;-*-

;;; Allow for easy mounting of Slime/Swank
(:tree "/usr/local/share/common-lisp/slime/")
EOF
}



# Main script execution starts here
echo "Installing Common Lisp environment..."
cleanup_apt
check_packages curl time libz-dev m4 sbcl ca-certificates file libzstd-dev build-essential git
install_sbcl
configure_asdf
if [ "${MAKE_SLIM}" = "true" ]; then
    echo "Removing build dependencies for slim image..."
    cleanup_build_packages curl time libz-dev m4 sbcl ca-certificates file libzstd-dev build-essential git
fi
cleanup_apt
echo "Done!"