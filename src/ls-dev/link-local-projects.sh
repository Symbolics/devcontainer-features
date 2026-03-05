#!/usr/bin/env bash
set -euo pipefail

# Prefer the remote user home; fallback to current $HOME
REMOTE_USER="${_REMOTE_USER:-${USERNAME:-vscode}}"
REMOTE_HOME="$(getent passwd "${REMOTE_USER}" | cut -d: -f6 || true)"
REMOTE_HOME="${REMOTE_HOME:-$HOME}"

mkdir -p /workspaces/ls-dev
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

# ── Re-link surviving fork clones after a rebuild ─────────────────────────────
# If /workspaces/lisp-stat/<repo> contains a git repo (from a previous ls-fork
# run on a persistent volume), replace the fresh upstream clone that install.sh
# just created with a symlink back to the fork.  This runs automatically on
# every postCreate so the developer's forks are always active after a rebuild.
FORKS="/workspaces/lisp-stat"
if [ -d "${FORKS}" ]; then
    for fork in "${FORKS}"/*/; do
        [ -d "${fork}/.git" ] || continue
        name="$(basename "${fork%/}")"
        target="${SRC}/${name}"
        # Only replace a real directory (i.e. the fresh upstream clone);
        # leave it alone if it is already a symlink (already relinked).
        if [ -d "${target}" ] && [ ! -L "${target}" ]; then
            rm -rf "${target}"
            ln -s "${fork%/}" "${target}"
            echo "Relinked ${name} → ${fork%/}"
        fi
    done
fi