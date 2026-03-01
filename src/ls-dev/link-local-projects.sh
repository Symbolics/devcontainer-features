#!/usr/bin/env bash
set -euo pipefail

# Prefer the remote user home; fallback to current $HOME
REMOTE_USER="${_REMOTE_USER:-${USERNAME:-vscode}}"
REMOTE_HOME="$(getent passwd "${REMOTE_USER}" | cut -d: -f6 || true)"
REMOTE_HOME="${REMOTE_HOME:-$HOME}"

SRC="${REMOTE_HOME}/quicklisp/local-projects"
DEST="/workspaces/ls-dev"

[ -d "${SRC}" ] || exit 0

for dir in "${SRC}"/*; do
    [ -d "${dir}" ] || continue
    name="$(basename "${dir}")"

    # Skip if path already exists
    [ -e "${DEST}/${name}" ] && continue

    ln -s "${dir}" "${DEST}/${name}"
done