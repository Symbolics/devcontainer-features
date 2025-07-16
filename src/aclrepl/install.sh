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
    # Clone the linedit repository
    cd /usr/local/src
    git clone https://github.com/sharplispers/linedit.git
    # Load linedit using Quicklisp to obtain dependencies
    /usr/local/bin/sbcl --noinform --eval '(ql:quickload :linedit)'
    cat <<EOF >> ~/.sbclrc
(ql:quickload :linedit)
(linedit:install-repl :wrap-current t :eof-quits t)

EOF
    echo "Linedit installed successfully."
}
export -f install_linedit

configure_aclrepl() {
    echo "Configuring ACLREPL..."
    cat <<EOF >> ~/.sbclrc
(ignore-errors (require 'sb-aclrepl))
(ignore-errors (require 'asdf))
(ignore-errors (require 'quicklisp))

;; Consider using prepl, which has more features and is more actively maintained.
(when (find-package 'sb-aclrepl)
  (push :aclrepl cl:*features*))
 #+aclrepl
 (progn
   (setq sb-aclrepl:*max-history* 100)
   (sb-aclrepl:alias ("cs" 1 "compile system") (sys) (asdf:operate 'asdf:compile-op sys))
   (sb-aclrepl:alias ("ls" 1 "load system") (sys) (asdf:operate 'asdf:load-op sys))
   (sb-aclrepl:alias ("ts" 1 "test system") (sys) (asdf:operate 'asdf:test-op sys))

   ;; The 1 below means that two characters ("up") are required
   (sb-aclrepl:alias ("up" 1 "use package") (package) (use-package package))
   (sb-aclrepl:alias ("ql" 1 "quickload" system) (sys) (ql:quickload sys))
   
   ;; The 0 below means only the first letter ("r") is required,
   ;; such as ":r base64"
   (sb-aclrepl:alias ("require" 0 "require module") (sys) (require sys))
   (setq cl:*features* (delete :aclrepl cl:*features*)))

EOF
}
export -f configure_aclrepl


# Main script execution starts here
echo "Installing aclrepl..."
export DEBIAN_FRONTEND=noninteractive
cleanup_apt

su ${USERNAME} -c configure_aclrepl

if [ ${ENABLE_LINEDIT} ]; then
    check_packages build-essential git
    su ${USERNAME} -c install_linedit
fi

if [ "${MAKE_SLIM}" = "true" ]; then
    echo "Removing build-essential and git for slim image..."
    cleanup_build_packages build-essential git
fi

cleanup_apt
echo "Done!"