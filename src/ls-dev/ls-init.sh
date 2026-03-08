#!/usr/bin/env bash
# ls-init.sh — Unified Lisp-Stat developer setup script
#
# Usage:
#   ls-init.sh [--mode experimenter|contributor] [--upstream-dir DIR] [--help]
#
# - Experimenter mode (default): clones upstream repos to a persistent location and symlinks into ~/quicklisp/local-projects
# - Contributor mode: forks repos to your GitHub, clones forks, and relinks local-projects to your forks
# - Can be run interactively or with CLI options for automation

set -euo pipefail


# Debug: Print shell, args, and environment info
echo "[ls-init.sh] SHELL: $SHELL"
echo "[ls-init.sh] Bash version: $BASH_VERSION"
echo "[ls-init.sh] Args: $@"
echo "[ls-init.sh] TTY: $(tty || echo 'not a tty')"
env | grep -E 'TERM|SHELL|USER|HOME|PWD|SHLVL' | sort

# Defaults
MODE="experimenter"
# Default to a user-writable directory unless overridden
UPSTREAM_DIR="$HOME/lisp-stat-upstream"
# Use the actual devcontainer workspace folder by default
WORKSPACE_DIR="${WORKSPACE_FOLDER:-$PWD}"
LOCAL_PROJECTS="$HOME/quicklisp/local-projects"

# Check for required commands
for cmd in git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command '$cmd' not found. Please install it." >&2
        exit 1
    fi
done

# Warn if running as root
if [ "$(id -u)" -eq 0 ]; then
    echo "WARNING: You are running this script as root. It is recommended to run as a normal user." >&2
fi

show_help() {
        cat <<EOF
ls-init.sh — Unified Lisp-Stat developer setup script

Usage:
    ls-init.sh [--mode experimenter|contributor] [--upstream-dir DIR] [--refresh] [--help]

Options:
    --mode           Set mode: experimenter (default) or contributor
    --upstream-dir   Directory for upstream clones (default: /workspaces/lisp-stat-upstream)
    
The workspace directory for symlinks is now /workspaces/ls-dev by default for devcontainer compatibility.
    --refresh        Refresh all upstream repos to latest (experimenter mode only)
    --help           Show this help message

The --refresh option updates all upstream repos to their latest state (git pull --ff-only).
It is intended for non-contributors/experimenter mode. Local changes are not overwritten; repos with local changes are skipped with a warning.

Run with no arguments for interactive mode selection.
EOF
}

# Parse arguments
REFRESH=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="$2"; shift 2;;
        --upstream-dir)
            UPSTREAM_DIR="$2"; shift 2;;
        --refresh)
            REFRESH=1; shift;;
        --help)
            show_help; exit 0;;
        *)
            echo "Unknown option: $1" >&2; show_help; exit 1;;
    esac
done

# Interactive mode selection if no mode specified
if [[ -z "${MODE:-}" ]] || [[ "$MODE" != "experimenter" && "$MODE" != "contributor" ]]; then
    if [ -t 0 ]; then
        echo "Select setup mode:"
        select opt in "Experimenter (default, upstream only)" "Contributor (fork and relink)"; do
            case $REPLY in
                1) MODE="experimenter"; break;;
                2) MODE="contributor"; break;;
                *) echo "Invalid selection";;
            esac
        done
    else
        echo "WARNING: No TTY detected and --mode not specified. Defaulting to 'experimenter' mode." >&2
        MODE="experimenter"
    fi
fi

# List of Lisp-Stat upstream repos
UPSTREAM_REPOS=(
    "https://github.com/Lisp-Stat/data-frame.git"
    "https://github.com/Lisp-Stat/dfio.git"
    "https://github.com/Lisp-Stat/special-functions.git"
    "https://github.com/Lisp-Stat/numerical-utilities.git"
    "https://github.com/Lisp-Stat/array-operations.git"
    "https://github.com/Lisp-Stat/documentation.git"
    "https://github.com/Lisp-Stat/distributions.git"
    "https://github.com/Lisp-Stat/plot.git"
    "https://github.com/Lisp-Stat/select.git"
    "https://github.com/Lisp-Stat/cephes.cl.git"
    "https://github.com/Symbolics/alexandria-plus.git"
    "https://github.com/Lisp-Stat/statistics.git"
    "https://github.com/Lisp-Stat/lisp-stat.git"
    "https://github.com/Lisp-Stat/ls-server.git"
    "https://github.com/Lisp-Stat/lla.git"
)

clone_upstream() {
    echo "Cloning upstream repos to $UPSTREAM_DIR ..."
    if ! mkdir -p "$UPSTREAM_DIR" 2>/dev/null; then
        echo "ERROR: Cannot create directory '$UPSTREAM_DIR'. Permission denied or invalid path." >&2
        echo "       Try running with a different --upstream-dir or check your permissions."
        exit 1
    fi
    if [ ! -w "$UPSTREAM_DIR" ]; then
        echo "ERROR: No write permission for '$UPSTREAM_DIR'." >&2
        exit 1
    fi
    for repo_url in "${UPSTREAM_REPOS[@]}"; do
        repo_name="$(basename "$repo_url" .git)"
        target_dir="$UPSTREAM_DIR/$repo_name"
        if [ ! -d "$target_dir/.git" ]; then
            echo "  Cloning $repo_name ..."
            if ! git clone --depth=1 "$repo_url" "$target_dir"; then
                echo "    ERROR: Failed to clone $repo_name from $repo_url" >&2
            fi
        else
            echo "  $repo_name already cloned. Skipping."
        fi
    done
}

symlink_local_projects() {
    echo "Symlinking repos into $LOCAL_PROJECTS ..."
    if ! mkdir -p "$LOCAL_PROJECTS" 2>/dev/null; then
        echo "ERROR: Cannot create local projects directory '$LOCAL_PROJECTS'." >&2
        exit 1
    fi
    for dir in "$UPSTREAM_DIR"/*; do
        [ -d "$dir/.git" ] || continue
        name="$(basename "$dir")"
        link="$LOCAL_PROJECTS/$name"
        if [ -L "$link" ] && [ "$(readlink "$link")" = "$dir" ]; then
            continue
        fi
        rm -rf "$link"
        if ! ln -s "$dir" "$link"; then
            echo "    ERROR: Failed to symlink $name to $link" >&2
        else
            echo "  Linked $name"
        fi
    done
}

symlink_workspace() {
    echo "Symlinking repos into $WORKSPACE_DIR ..."
    if ! mkdir -p "$WORKSPACE_DIR" 2>/dev/null; then
        echo "ERROR: Cannot create workspace directory '$WORKSPACE_DIR'." >&2
        exit 1
    fi
    for dir in "$UPSTREAM_DIR"/*; do
        [ -d "$dir/.git" ] || continue
        name="$(basename "$dir")"
        link="$WORKSPACE_DIR/$name"
        if [ -L "$link" ] && [ "$(readlink "$link")" = "$dir" ]; then
            continue
        fi
        rm -rf "$link"
        if ! ln -s "$dir" "$link"; then
            echo "    ERROR: Failed to symlink $name to $link" >&2
        fi
    done
}

fork_and_clone() {
    if ! command -v gh >/dev/null 2>&1; then
        echo "ERROR: gh CLI not found. Please install GitHub CLI." >&2
        exit 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
        echo "ERROR: Not authenticated with GitHub. Run: gh auth login" >&2
        exit 1
    fi
    GH_USER=$(gh api user --jq .login)
    echo "Authenticated as: $GH_USER"
    mkdir -p "$WORKSPACE_DIR"
    for dir in "$UPSTREAM_DIR"/*; do
        [ -d "$dir/.git" ] || continue
        repo_name="$(basename "$dir")"
        dest="$WORKSPACE_DIR/$repo_name"
        # Skip if already cloned
        if [ -d "$dest/.git" ]; then
            echo "  $repo_name already forked and cloned."
            continue
        fi
        # Get upstream slug
        upstream_url=$(git -C "$dir" remote get-url origin)
        upstream_slug=$(echo "$upstream_url" | sed -E 's|https://github.com/||; s|git@github.com:||; s|.git$||')
        # Fork
        echo "  FORK  $upstream_slug"
        gh repo fork "$upstream_slug" --clone=false
        # Clone fork
        fork_url="https://github.com/$GH_USER/$repo_name.git"
        echo "  CLONE $fork_url → $dest"
        git clone "$fork_url" "$dest"
        # Add upstream remote
        git -C "$dest" remote add upstream "$upstream_url"
    done
}

relink_local_projects_to_forks() {
    echo "Relinking $LOCAL_PROJECTS to point to forks in $WORKSPACE_DIR ..."
    for dir in "$WORKSPACE_DIR"/*; do
        [ -d "$dir/.git" ] || continue
        name="$(basename "$dir")"
        link="$LOCAL_PROJECTS/$name"
        rm -rf "$link"
        ln -s "$dir" "$link"
        echo "  Linked $name → $dir"
    done
}

refresh_upstream() {
    echo "Refreshing all upstream repos in $UPSTREAM_DIR ..."
    for dir in "$UPSTREAM_DIR"/*; do
        [ -d "$dir/.git" ] || continue
        repo_name="$(basename "$dir")"
        echo "  $repo_name:"
        if git -C "$dir" diff --quiet && git -C "$dir" status --porcelain | grep -q '^'; then
            echo "    WARNING: Local changes present in $repo_name. Skipping."
            continue
        fi
        if ! git -C "$dir" pull --ff-only; then
            echo "    ERROR: Failed to pull latest for $repo_name" >&2
        else
            echo "    Updated."
        fi
    done
}

# Main logic
if [ "$MODE" = "experimenter" ]; then
    if [ "$REFRESH" -eq 1 ]; then
        refresh_upstream
        echo "\nRefresh complete."
        exit 0
    fi
    clone_upstream
    symlink_local_projects
    symlink_workspace
    echo "\nExperimenter mode complete. You can start using Lisp-Stat immediately."
    echo "To become a contributor later, re-run: ls-init.sh --mode contributor"
elif [ "$MODE" = "contributor" ]; then
    clone_upstream
    fork_and_clone
    relink_local_projects_to_forks
    symlink_workspace
    echo "\nContributor mode complete. Your forks are in $WORKSPACE_DIR."
    echo "You can push to your fork and pull from upstream."
else
    echo "Unknown mode: $MODE" >&2
    exit 1
fi
