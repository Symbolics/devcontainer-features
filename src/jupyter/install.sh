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
            apt-get update -y
        fi
        apt-get -y install --no-install-recommends "$@"
    fi
}

export DEBIAN_FRONTEND=noninteractive

cleanup_build_packages() {
    echo "Cleaning up build packages..."
    apt-get remove --purge -y curl ca-certificates
    apt-get autoremove -y
    echo "Build packages cleaned up."
}

# We really don't want to mess with the whole Jupyter/Python thing if we can avoid it.
# This function is untested as we use an image that already has Jupyter installed.
# install_jupyter() {
#     echo "Installing Jupyter..."
#     mkdir -p /usr/local/src/jupyter
#     cd /usr/local/src/jupyter
#     if ! command -v jupyter-lab > /dev/null; then
#         #check_packages python3 python3-pip python3-venv
#         #pip3 install --upgrade pip
#         #pip3 install jupyterlab jupyter-console jupyterlab-widgets #--break-system-packages
#         check_packages python3 pipx python3-pip
#         pipx install jupyterlab --include-deps
#         pipx install jupyter-console --include-deps
#         pipx ensurepath
#         source ~/.bashrc
#     fi
# }

install_jupyter_kernel() {
    echo "Installing jupyter kernel..."
    check_packages git libczmq-dev build-essential ca-certificates
    git clone https://github.com/yitzchak/delta-vega.git ~/quicklisp/local-projects/delta-vega; \
    git clone https://github.com/yitzchak/resizable-box-clj.git ~/quicklisp/local-projects/resizable-box-clj; \
    git clone https://github.com/yitzchak/ngl-clj.git ~/quicklisp/local-projects/ngl-clj; \
    su ${USERNAME} -c "sbcl --non-interactive \
        --eval \"(ql:quickload '(:common-lisp-jupyter :cytoscape-clj :kekule-clj :resizable-box-clj :ngl-clj :delta-vega))\" \
        --eval \"(clj:install :implementation t)\""
}

install_lisp_stat() {
    echo "Installing Lisp-Stat..."
    check_packages build-essential ca-certificates libblas3 liblapack3 sqlite3



    su ${USERNAME} -c "sbcl --non-interactive \
        --eval \"(ql:quickload '(:lisp-stat :plot/vega))\""
}

#TODO: We should probably just rewrite the entirety of .sbclrc
configure_lisp_stat() {
    echo "Configuring Lisp-Stat..."
    cat <<EOF >> ~/.sbclrc

;;; Lisp-Stat
(setf cl:*print-pretty* t)
(when (asdf:find-system 'lisp-stat nil)
    (asdf:load-system :lisp-stat)
    (in-package :ls-user))
(when (probe-file #P"~/.ls-init.lisp")
    (load #P"~/.ls-init.lisp"))

EOF


    git clone https://github.com/vincentarelbundock/Rdatasets.git ~/Rdatasets
    cat <<EOF >> ~/.ls-init.lisp
;;; -*- Mode: LISP; Base: 10; Syntax: Ansi-Common-Lisp; Package: LS-USER -*-
;;; Copyright (c) 2021-2025 by Symbolics Pte. Ltd.  All rights reserved.
(in-package #:ls-user)

;;; Define logical hosts for external data sets
(setf (logical-pathname-translations "RDATA")
      \`(("**;*.*.*" ,(merge-pathnames "csv/**/*.*" "~/Rdatasets/"))))

(defparameter *default-datasets*
  '("tooth-growth" "plant-growth" "usarrests" "iris" "mtcars")
  "Data sets loaded as part of personal Lisp-Stat initialisation.  Available in every session.")

(map nil #'(lambda (x)
	     (format t "Loading ~A~%" x)
	     (dfio:data x))
	     *default-datasets*)

EOF

}

# We need to configure LLA *before* we install until the new defaults make it into Quicklisp. 2025-07-15
configure_lla() {
    echo "Configuring Lisp Linear Algebra..."
    cat <<EOF >> ~/.sbclrc
;;; Lisp Linear Algebra
(defvar *lla-configuration* ; this can be removed once Quicklisp is updated
  '(:libraries ("libblas.so.3" "liblapack.so.3")))

EOF
}

# Main script execution starts here
echo "Installing Jupyter..."
install_jupyter_kernel
configure_lla # See comment above about why we configure before installing
install_lisp_stat
configure_lisp_stat
cleanup_apt

echo "Done!"