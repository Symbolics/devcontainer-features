#!/bin/bash

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

install_linedit() {
    echo "Installing linedit..."
    # Clone as root into /usr/local/src (root-owned); make world-readable
    git clone https://github.com/sharplispers/linedit.git /usr/local/src/linedit
    chmod -R a+rX /usr/local/src/linedit
    # Load linedit via Quicklisp as the target user so it is registered in ~/quicklisp
    su "${USERNAME}" -c '/usr/local/bin/sbcl --noinform --non-interactive --eval "(ql:quickload :linedit)"'
    echo "Linedit installed successfully."
}

# Write a separate init file for terminal REPL enhancements.
# This is loaded by the ls-repl wrapper script, NOT by .sbclrc,
# so it never interferes with SLIME/Swank.
configure_repl_init() {
    echo "Writing terminal REPL init to ~/.sbcl-repl-init.lisp..."
    cat <<'EOF' > ~/.sbcl-repl-init.lisp
;;; -*- Mode: LISP; Syntax: Common-Lisp -*-
;;; Terminal REPL enhancements — loaded by the ls-repl wrapper script.
;;; This file is NOT loaded by .sbclrc, keeping SLIME/Swank clean.

;;; ACLREPL — Allegro-style toplevel aliases
(ignore-errors (require 'sb-aclrepl))
(when (find-package 'sb-aclrepl)
  (push :aclrepl cl:*features*))
#+aclrepl
(progn
  (setq sb-aclrepl:*max-history* 100)
  (sb-aclrepl:alias ("cs" 1 "compile system") (sys) (asdf:operate 'asdf:compile-op sys))
  (sb-aclrepl:alias ("ls" 1 "load system") (sys) (asdf:operate 'asdf:load-op sys))
  (sb-aclrepl:alias ("ts" 1 "test system") (sys) (asdf:operate 'asdf:test-op sys))
  (sb-aclrepl:alias ("up" 1 "use package") (package) (use-package package))
  (sb-aclrepl:alias ("ql" 1 "quickload" system) (sys) (ql:quickload sys))
  (sb-aclrepl:alias ("require" 0 "require module") (sys) (require sys))
  (setq cl:*features* (delete :aclrepl cl:*features*)))

;;; Linedit — nicer line editing for the terminal REPL
(ql:quickload :linedit :silent t)
(uiop:symbol-call :linedit :install-repl :wrap-current t :eof-quits t)
EOF
}
export -f configure_repl_init


# Main script execution starts here
echo "Installing aclrepl..."
export DEBIAN_FRONTEND=noninteractive
cleanup_apt

check_packages build-essential git
install_linedit
su ${USERNAME} -c configure_repl_init

# Install the ls-repl wrapper script
if [ ! -f ./ls-repl ]; then
    echo "ERROR: ./ls-repl not found in feature directory. Aborting." >&2
    exit 1
fi
install -m 0755 ./ls-repl /usr/local/bin/ls-repl

if [ "${MAKE_SLIM}" = "true" ]; then
    echo "Removing git for slim image..."
    cleanup_build_packages git
fi

cleanup_apt
echo "Done!"