#!/bin/bash
set -euo pipefail

# Cleans up a git worktree after PR has been merged.
#
# This script removes the worktree, deletes the branch (local and optionally remote),
# and cleans up any remaining files.
#
# Usage:
#   wt-cleanup <worktree-name> [-r] [-f]
#
# Options:
#   -r, --remote    Also delete the remote branch
#   -f, --force     Skip confirmation prompt
#
# Examples:
#   wt-cleanup feature-add-auth
#   wt-cleanup feature-add-auth -r
#   wt-cleanup feature-add-auth -r -f

# Parse arguments
WORKTREE_NAME=""
DELETE_REMOTE=0
FORCE=0

show_help() {
    echo "Usage: wt-cleanup <worktree-name> [-r] [-f]"
    echo ""
    echo "Cleans up a git worktree after PR has been merged"
    echo ""
    echo "Arguments:"
    echo "  worktree-name  The name of the worktree folder to remove"
    echo ""
    echo "Options:"
    echo "  -r, --remote   Also delete the remote branch"
    echo "  -f, --force    Skip confirmation prompt"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "Examples:"
    echo "  wt-cleanup feature-add-auth"
    echo "  wt-cleanup feature-add-auth -r"
    echo "  wt-cleanup feature-add-auth -r -f"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -r|--remote)
            DELETE_REMOTE=1
            shift
            ;;
        -f|--force)
            FORCE=1
            shift
            ;;
        *)
            if [ -z "$WORKTREE_NAME" ]; then
                WORKTREE_NAME="$1"
            fi
            shift
            ;;
    esac
done

# Configuration
WORKTREES_BASE="$HOME/Dev/worktrees"

# Get the current git repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "Error: Not inside a git repository. Please run this from within your project."
    exit 1
}

REPO_NAME=$(basename "$REPO_ROOT")

# Build worktree path
REPO_WORKTREES_DIR="$WORKTREES_BASE/$REPO_NAME"

# If no worktree name given, show interactive picker
if [ -z "$WORKTREE_NAME" ]; then
    if [ ! -d "$REPO_WORKTREES_DIR" ] || [ -z "$(ls -A "$REPO_WORKTREES_DIR" 2>/dev/null)" ]; then
        echo "Error: No worktrees found for $REPO_NAME"
        exit 1
    fi

    WORKTREE_DIRS=()
    for d in "$REPO_WORKTREES_DIR"/*/; do
        [ -d "$d" ] && WORKTREE_DIRS+=("$(basename "$d")")
    done

    if [ ${#WORKTREE_DIRS[@]} -eq 0 ]; then
        echo "Error: No worktrees found for $REPO_NAME"
        exit 1
    fi

    if command -v fzf &> /dev/null; then
        WORKTREE_NAME=$(printf '%s\n' "${WORKTREE_DIRS[@]}" | fzf --prompt="Select worktree to clean up: ")
        if [ -z "$WORKTREE_NAME" ]; then
            echo "Cancelled."
            exit 0
        fi
    else
        echo "Available worktrees for $REPO_NAME:"
        for i in "${!WORKTREE_DIRS[@]}"; do
            echo "  $((i+1))) ${WORKTREE_DIRS[$i]}"
        done
        echo ""
        read -p "Select worktree (1-${#WORKTREE_DIRS[@]}): " SELECTION
        if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt ${#WORKTREE_DIRS[@]} ]; then
            echo "Invalid selection."
            exit 1
        fi
        WORKTREE_NAME="${WORKTREE_DIRS[$((SELECTION-1))]}"
    fi
fi

WORKTREE_PATH="$REPO_WORKTREES_DIR/$WORKTREE_NAME"

# Check if worktree exists
if [ ! -d "$WORKTREE_PATH" ]; then
    echo "Error: Worktree not found at: $WORKTREE_PATH"
    echo ""
    echo "Existing worktrees:"
    git worktree list
    exit 1
fi

# Get branch name from worktree
BRANCH_NAME=$(git -C "$WORKTREE_PATH" branch --show-current)

echo "========================================"
echo "Worktree Cleanup"
echo "========================================"
echo "Worktree: $WORKTREE_PATH"
echo "Branch: $BRANCH_NAME"
if [ $DELETE_REMOTE -eq 1 ]; then
    echo "Remote branch will also be deleted"
fi

# Confirmation
if [ $FORCE -eq 0 ]; then
    echo ""
    read -p "Are you sure you want to remove this worktree? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

# Step 1: Kill any running dev server on this worktree's port
echo ""
echo "[1/5] Checking for running dev servers..."
ENV_LOCAL_PATH="$WORKTREE_PATH/.env"
if [ -f "$ENV_LOCAL_PATH" ]; then
    PORT_MATCH=$(grep -o 'NEXT_PUBLIC_APP_URL=http://localhost:[0-9]*' "$ENV_LOCAL_PATH" | grep -o '[0-9]*$' || true)
    if [ -n "$PORT_MATCH" ]; then
        echo "  Checking port $PORT_MATCH..."

        # Find and kill process on that port (macOS uses lsof)
        PID=$(lsof -ti tcp:$PORT_MATCH 2>/dev/null || true)
        if [ -n "$PID" ]; then
            echo "  Stopping process $PID on port $PORT_MATCH..."
            kill "$PID" 2>/dev/null || true
            sleep 2
            if kill -0 "$PID" 2>/dev/null; then
                echo "  Process didn't stop gracefully, force killing..."
                kill -9 "$PID" 2>/dev/null || true
            fi
        fi
    fi
fi

# Step 2: Sync new env variables back to main repo
echo ""
echo "[2/5] Syncing new .env variables to main repo..."
MAIN_ENV_LOCAL="$REPO_ROOT/.env"
WT_ENV_LOCAL="$WORKTREE_PATH/.env"
if [ -f "$WT_ENV_LOCAL" ]; then
    if [ -f "$MAIN_ENV_LOCAL" ]; then
        NEW_VARS=()
        while IFS= read -r line; do
            # Skip empty lines and comments
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            # Extract variable name (everything before the first =)
            VAR_NAME="${line%%=*}"
            # Check if this variable exists in the main .env.local
            if ! grep -q "^${VAR_NAME}=" "$MAIN_ENV_LOCAL"; then
                NEW_VARS+=("$line")
            fi
        done < "$WT_ENV_LOCAL"

        if [ ${#NEW_VARS[@]} -gt 0 ]; then
            echo "" >> "$MAIN_ENV_LOCAL"
            ENV_SAMPLE="$REPO_ROOT/.env.sample"
            for var in "${NEW_VARS[@]}"; do
                echo "$var" >> "$MAIN_ENV_LOCAL"
                echo "  Added to .env: $var"

                # Add variable name (without value) to .env.sample
                if [ -f "$ENV_SAMPLE" ]; then
                    VAR_NAME="${var%%=*}"
                    if ! grep -q "^${VAR_NAME}=" "$ENV_SAMPLE"; then
                        echo "${VAR_NAME}=" >> "$ENV_SAMPLE"
                        echo "  Added to .env.sample: ${VAR_NAME}="
                    fi
                fi
            done
        else
            echo "  No new variables to sync"
        fi
    else
        echo "  Skipped: Main repo .env not found at $MAIN_ENV_LOCAL"
    fi
else
    echo "  Skipped: Worktree .env not found"
fi

# Step 3: Remove the worktree
echo ""
echo "[3/5] Removing worktree..."
cd "$REPO_ROOT"
if ! git worktree remove "$WORKTREE_PATH" --force 2>/dev/null; then
    echo "  Warning: git worktree remove failed, trying manual cleanup..."
    rm -rf "$WORKTREE_PATH"
    git worktree prune
fi
cd - > /dev/null

# Step 4: Delete local branch
echo ""
echo "[4/5] Deleting local branch: $BRANCH_NAME..."
if [ -n "$BRANCH_NAME" ] && [ "$BRANCH_NAME" != "main" ] && [ "$BRANCH_NAME" != "master" ]; then
    cd "$REPO_ROOT"
    git branch -D "$BRANCH_NAME" 2>/dev/null || echo "  Branch may have already been deleted or merged"
    cd - > /dev/null
else
    echo "  Skipping deletion of protected branch: $BRANCH_NAME"
fi

# Step 5: Delete remote branch if requested
if [ $DELETE_REMOTE -eq 1 ] && [ -n "$BRANCH_NAME" ] && [ "$BRANCH_NAME" != "main" ] && [ "$BRANCH_NAME" != "master" ]; then
    echo ""
    echo "[5/5] Deleting remote branch: origin/$BRANCH_NAME..."
    cd "$REPO_ROOT"
    git push origin --delete "$BRANCH_NAME" 2>/dev/null || echo "  Remote branch may have already been deleted"
    cd - > /dev/null
else
    echo ""
    echo "[5/5] Skipping remote branch deletion"
fi

# Clean up empty directories
if [ -d "$REPO_WORKTREES_DIR" ]; then
    REMAINING=$(ls -A "$REPO_WORKTREES_DIR" 2>/dev/null || true)
    if [ -z "$REMAINING" ]; then
        rmdir "$REPO_WORKTREES_DIR" 2>/dev/null || true
        echo ""
        echo "Cleaned up empty directory: $REPO_WORKTREES_DIR"
    fi
fi

echo ""
echo "========================================"
echo "Cleanup complete!"
echo "========================================"
