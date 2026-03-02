#!/usr/bin/env bash
# ls-fork — Fork all Lisp-Stat repos to your GitHub account and set up a
# contributor workspace in /workspaces/lisp-stat/.
#
# Usage: ls-fork
#
# What it does:
#   1. Checks gh authentication
#   2. Forks every repo in ~/quicklisp/local-projects/ to your GitHub account
#   3. Clones your fork to /workspaces/lisp-stat/<repo> (persists across rebuilds)
#   4. Adds 'upstream' remote pointing back to the Lisp-Stat origin
#   5. Replaces ~/quicklisp/local-projects/<repo> with a symlink to the clone
#
# Run this once when you are ready to contribute.  It is safe to re-run —
# repos already present in /workspaces/lisp-stat/ are skipped.

set -euo pipefail

LOCAL_PROJECTS="${HOME}/quicklisp/local-projects"
WORKSPACE="/workspaces/lisp-stat"

# ── Preflight ──────────────────────────────────────────────────────────────────

if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh CLI not found. It should be pre-installed in this image." >&2
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "ERROR: Not authenticated with GitHub."
    echo "Run: gh auth login"
    echo "Then re-run ls-fork."
    exit 1
fi

GH_USER=$(gh api user --jq .login)
echo "Authenticated as: ${GH_USER}"
echo "Forking repos into /workspaces/lisp-stat/ ..."
echo ""

mkdir -p "${WORKSPACE}"

# ── Per-repo loop ──────────────────────────────────────────────────────────────

for dir in "${LOCAL_PROJECTS}"/*/; do
    [ -d "${dir}" ] || continue
    repo_name="$(basename "${dir}")"
    dest="${WORKSPACE}/${repo_name}"

    # Resolve symlinks so we can determine if this entry is already a fork clone
    real_dir="$(realpath "${dir}")"

    # Detect upstream org/repo from the git remote
    if ! upstream_url="$(git -C "${real_dir}" remote get-url origin 2>/dev/null)"; then
        echo "  SKIP ${repo_name} — not a git repo"
        continue
    fi

    # Parse org/repo from https or git URLs
    # https://github.com/Org/repo.git  →  Org/repo
    # git@github.com:Org/repo.git      →  Org/repo
    upstream_slug="$(echo "${upstream_url}" \
        | sed -E 's|https://github\.com/||; s|git@github\.com:||; s|\.git$||')"
    upstream_org="$(echo "${upstream_slug}" | cut -d/ -f1)"

    # Skip if already pointing at the user's own fork
    if [ "${upstream_org}" = "${GH_USER}" ]; then
        echo "  SKIP ${repo_name} — already your fork (origin: ${upstream_url})"
        continue
    fi

    # Skip if already cloned to the workspace
    if [ -d "${dest}/.git" ]; then
        echo "  SKIP ${repo_name} — already at ${dest}"
        # Ensure the symlink exists even if the directory predates this script
        if [ ! -L "${dir%/}" ]; then
            rm -rf "${dir%/}"
            ln -s "${dest}" "${dir%/}"
            echo "         → symlinked local-projects/${repo_name} → ${dest}"
        fi
        continue
    fi

    # Fork
    echo "  FORK  ${upstream_slug}"
    gh repo fork "${upstream_slug}" --clone=false

    # Clone fork into workspace
    fork_url="https://github.com/${GH_USER}/${repo_name}.git"
    echo "  CLONE ${fork_url} → ${dest}"
    git clone "${fork_url}" "${dest}"

    # Add upstream remote
    git -C "${dest}" remote add upstream "https://github.com/${upstream_slug}.git"
    echo "        upstream → https://github.com/${upstream_slug}.git"

    # Replace in-container directory with symlink
    rm -rf "${dir%/}"
    ln -s "${dest}" "${dir%/}"
    echo "        symlinked local-projects/${repo_name} → ${dest}"
    echo ""
done

echo "Done."
echo ""
echo "Your forks are in /workspaces/lisp-stat/"
echo "Each repo has:"
echo "  origin   → your fork  (push here)"
echo "  upstream → Lisp-Stat  (fetch updates from here)"
echo ""
echo "To keep a fork up to date:"
echo "  git -C /workspaces/lisp-stat/<repo> fetch upstream"
echo "  git -C /workspaces/lisp-stat/<repo> merge upstream/master"
