#!/bin/bash

# TODO: parametrize and test for the lisp implementation, now hardcoded to SBCL
USERNAME=${USERNAME:-${_REMOTE_USER:-"automatic"}}

# Set BLAS from feature option, default to openblas if not set
BLAS="${BLAS:-openblas}"

if [ "$BLAS" != "intel-mkl" ] && [ "$BLAS" != "openblas" ]; then
    echo "Invalid BLAS option: $BLAS. Must be 'intel-mkl' or 'openblas'."
    exit 1
fi

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

install_mkl() {
    echo "Installing Intel Math Kernel Library..."
    check_packages intel-mkl
}

install_openblas() {
    echo "Installing OpenBLAS..."
    check_packages libblas3 liblapack3
}

install_lisp_stat_src() {
    mkdir -p /home/$USERNAME/quicklisp/local-projects && \
    (cd /home/$USERNAME/quicklisp/local-projects && \
    git clone https://github.com/Lisp-Stat/data-frame.git && \
    git clone https://github.com/Lisp-Stat/dfio.git && \
    git clone https://github.com/Lisp-Stat/special-functions.git && \
    git clone https://github.com/Lisp-Stat/numerical-utilities.git && \
    git clone https://github.com/Lisp-Stat/array-operations.git && \
    git clone https://github.com/Lisp-Stat/documentation.git && \
    git clone https://github.com/Lisp-Stat/distributions.git && \
    git clone https://github.com/Lisp-Stat/plot.git && \
    git clone https://github.com/Lisp-Stat/select.git && \
    git clone https://github.com/Lisp-Stat/cephes.cl.git && \
    git clone https://github.com/Symbolics/alexandria-plus.git && \
    git clone https://github.com/Lisp-Stat/statistics.git && \
    git clone https://github.com/Lisp-Stat/lisp-stat.git && \
    git clone https://github.com/Lisp-Stat/lla.git)
    chown -R $USERNAME:$USERNAME /home/$USERNAME/quicklisp/local-projects
}


#TODO: We should probably just rewrite the entirety of .sbclrc
configure_lisp_stat() {
    echo "Configuring Lisp-Stat..."
    cat <<EOF >> /home/$USERNAME/.sbclrc

;;; Lisp-Stat
(setf cl:*print-pretty* t)
(when (asdf:find-system 'lisp-stat nil)
    (ql:quickload :lisp-stat)
    (in-package :ls-user))
(when (probe-file #P"~/.ls-init.lisp")
    (load #P"~/.ls-init.lisp"))

EOF


    git clone https://github.com/vincentarelbundock/Rdatasets.git /usr/local/src/Rdatasets
    cat <<EOF >> /home/$USERNAME/.ls-init.lisp
;;; -*- Mode: LISP; Base: 10; Syntax: Ansi-Common-Lisp; Package: LS-USER -*-
;;; Copyright (c) 2021-2026 by Symbolics Pte. Ltd.  All rights reserved.
(in-package #:ls-user)

;;; Define logical hosts for external data sets
(setf (logical-pathname-translations "RDATA")
      \`(("**;*" ,(merge-pathnames "csv/**/*" "/usr/local/src/Rdatasets/"))))

(defparameter *default-datasets*
  '("tooth-growth" "plant-growth" "usarrests" "iris" "mtcars")
  "Data sets loaded as part of personal Lisp-Stat initialisation.  Available in every session.")

(map nil #'(lambda (x)
	     (format t "Loading ~A~%" x)
	     (dfio:data x))
	     *default-datasets*)

EOF
chown $USERNAME:$USERNAME -R /home/$USERNAME/.sbclrc /home/$USERNAME/.ls-init.lisp
}
export -f configure_lisp_stat

# We need to configure LLA *before* we install until the new defaults make it into Quicklisp. 2025-07-15
configure_openblas() {
    echo "Configuring Lisp Linear Algebra for OpenBLAS..."
    cat <<EOF >> ~/.sbclrc
;;; Lisp Linear Algebra
(defvar *lla-configuration* ; this can be removed once Quicklisp is updated
  '(:libraries ("libblas.so.3" "liblapack.so.3")))

EOF
}

configure_mkl() {
    echo "Configuring Lisp Linear Algebra for Intel MKL..."
    cat <<EOF >> ~/.sbclrc
;;; Lisp Linear Algebra
(defvar *lla-configuration* ; this can be removed once Quicklisp is updated
  '(:libraries ("libmkl_rt.so" "liblapack.so.3")))

EOF
}

# Main script execution starts here
echo "Installing Lisp-Stat..."

check_packages ca-certificates gh

if [ "${BLAS}" = "intel-mkl" ]; then
    install_mkl
    configure_mkl
else
    install_openblas
    configure_openblas
fi

install_lisp_stat_src
configure_lisp_stat
cleanup_apt
install -d -m 0755 /usr/local/share/lisp-stat
install -m 0755 ./link-local-projects.sh /usr/local/share/lisp-stat/link-local-projects.sh
install -m 0755 ./ls-fork.sh /usr/local/bin/ls-fork

echo "Done!"