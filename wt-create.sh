#!/bin/bash
set -euo pipefail

# Creates a git worktree with full development environment setup.
#
# This script creates a new git worktree, copies local config files,
# installs dependencies, and opens your IDE.
#
# Usage:
#   wt-create <branch-name> [-p <port>] [-a <app-dir>]
#   wt-create -b [-p <port>] [-a <app-dir>]
#
# Examples:
#   wt-create feature/add-auth
#   wt-create feature/add-auth -p 3005
#   wt-create feature/add-auth -a app
#   wt-create -b                          # Pick from backlog items

# Parse arguments
BRANCH_NAME=""
PORT=0
APP_DIR=""
DEBT_MODE=0
DEBT_DESCRIPTION=""

show_help() {
    echo "Usage: wt-create <branch-name> [-p <port>] [-a <app-dir>]"
    echo "       wt-create -b [-p <port>] [-a <app-dir>]"
    echo ""
    echo "Creates a new git worktree with full development setup"
    echo ""
    echo "Arguments:"
    echo "  branch-name    The name of the branch to create"
    echo ""
    echo "Options:"
    echo "  -b, --backlog  Pick a backlog item from docs/backlog.md"
    echo "  -a <dir>       App subdirectory (e.g. app) - used for .env and dev server"
    echo "  -p <port>      Port to configure in .env (auto-assigned if not specified)"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "Examples:"
    echo "  wt-create feature/add-auth"
    echo "  wt-create feature/add-auth -p 3005"
    echo "  wt-create feature/add-auth -a app"
    echo "  wt-create -b"
    echo ""
    echo "Backlog Mode (-b):"
    echo "  Reads docs/backlog.md and presents a menu of items."
    echo "  Auto-generates a branch name and launches Claude with /feature-dev."
    echo ""
    echo "  Expected format in docs/backlog.md:"
    echo "    ## BL-001: Summary title"
    echo "    - **Type**: tech-debt"
    echo "    - **Priority**: high"
    echo "    Description text..."
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -b|--backlog)
            DEBT_MODE=1
            shift
            ;;
        -a)
            APP_DIR="$2"
            shift 2
            ;;
        -p)
            PORT="$2"
            shift 2
            ;;
        *)
            if [ -z "$BRANCH_NAME" ]; then
                BRANCH_NAME="$1"
            fi
            shift
            ;;
    esac
done

# --- Technical Debt Mode ---
if [ "$DEBT_MODE" -eq 1 ]; then
    # Need repo root early for debt mode
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "Error: Not inside a git repository."
        exit 1
    }

    DEBT_FILE="$REPO_ROOT/docs/backlog.md"
    if [ ! -f "$DEBT_FILE" ]; then
        echo "Error: No docs/backlog.md found in the repository."
        exit 1
    fi

    # Parse backlog items from docs/backlog.md
    # Format: ## BL-001: Summary title
    #         - **Type**: tech-debt
    #         - **Priority**: critical
    #         (body lines until next --- or ## heading)
    declare -a ITEM_IDS=()
    declare -a ITEM_TYPES=()
    declare -a ITEM_PRIORITIES=()
    declare -a ITEM_SUMMARIES=()
    declare -a ITEM_BODIES=()

    CURRENT_ID=""
    CURRENT_SUMMARY=""
    CURRENT_TYPE=""
    CURRENT_PRIORITY=""
    CURRENT_BODY=""

    save_current() {
        if [ -n "$CURRENT_ID" ]; then
            ITEM_IDS+=("$CURRENT_ID")
            ITEM_SUMMARIES+=("$CURRENT_SUMMARY")
            ITEM_TYPES+=("${CURRENT_TYPE:-unknown}")
            ITEM_PRIORITIES+=("${CURRENT_PRIORITY:-medium}")
            ITEM_BODIES+=("$(echo "$CURRENT_BODY" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sed '/^$/d')")
        fi
    }

    while IFS= read -r line; do
        # ## BL-001: Summary title
        if [[ "$line" =~ ^##[[:space:]]+([A-Z]+-[0-9]+):[[:space:]]+(.+)$ ]]; then
            save_current
            CURRENT_ID="${BASH_REMATCH[1]}"
            CURRENT_SUMMARY="${BASH_REMATCH[2]}"
            CURRENT_TYPE=""
            CURRENT_PRIORITY=""
            CURRENT_BODY=""
        elif [ -n "$CURRENT_ID" ]; then
            # - **Type**: value
            if [[ "$line" =~ ^-[[:space:]]+\*\*Type\*\*:[[:space:]]+(.+)$ ]]; then
                CURRENT_TYPE="${BASH_REMATCH[1]}"
            # - **Priority**: value
            elif [[ "$line" =~ ^-[[:space:]]+\*\*Priority\*\*:[[:space:]]+(.+)$ ]]; then
                CURRENT_PRIORITY="${BASH_REMATCH[1]}"
            elif [[ "$line" == "---" ]]; then
                # separator, skip
                :
            elif [[ ! "$line" =~ ^-[[:space:]]+\*\*(Source|Files)\*\*: ]]; then
                # Append non-metadata lines to body
                if [ -n "$line" ]; then
                    if [ -n "$CURRENT_BODY" ]; then
                        CURRENT_BODY="$CURRENT_BODY
$line"
                    else
                        CURRENT_BODY="$line"
                    fi
                fi
            fi
        fi
    done < "$DEBT_FILE"
    save_current

    if [ ${#ITEM_IDS[@]} -eq 0 ]; then
        echo "Error: No backlog items found in docs/backlog.md."
        echo "Expected ## ID: Summary headings with **Type** and **Priority** metadata."
        exit 1
    fi

    # Display menu sorted by priority
    echo ""
    echo "========================================"
    echo "Backlog Items"
    echo "========================================"
    LAST_PRIORITY=""
    # Build display order sorted by priority: critical, high, medium, low
    declare -a DISPLAY_ORDER=()
    for prio in critical high medium low; do
        for i in "${!ITEM_IDS[@]}"; do
            if [ "${ITEM_PRIORITIES[$i]}" == "$prio" ]; then
                DISPLAY_ORDER+=("$i")
            fi
        done
    done
    # Add any items with unknown priority
    for i in "${!ITEM_IDS[@]}"; do
        FOUND=0
        for d in "${DISPLAY_ORDER[@]}"; do
            if [ "$d" == "$i" ]; then FOUND=1; break; fi
        done
        if [ "$FOUND" -eq 0 ]; then
            DISPLAY_ORDER+=("$i")
        fi
    done

    for idx in "${!DISPLAY_ORDER[@]}"; do
        i="${DISPLAY_ORDER[$idx]}"
        if [ "${ITEM_PRIORITIES[$i]}" != "$LAST_PRIORITY" ]; then
            echo ""
            echo "  --- ${ITEM_PRIORITIES[$i]} ---"
            LAST_PRIORITY="${ITEM_PRIORITIES[$i]}"
        fi
        echo "  $((idx + 1)). [${ITEM_IDS[$i]}] (${ITEM_TYPES[$i]}) ${ITEM_SUMMARIES[$i]}"
    done
    echo ""

    # Get user selection
    TOTAL=${#DISPLAY_ORDER[@]}
    while true; do
        read -rp "Select an item (1-${TOTAL}), or q to quit: " SELECTION
        if [[ "$SELECTION" == "q" || "$SELECTION" == "Q" ]]; then
            echo "Cancelled."
            exit 0
        fi
        if [[ "$SELECTION" =~ ^[0-9]+$ ]] && [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -le "$TOTAL" ]; then
            break
        fi
        echo "Invalid selection. Please enter a number between 1 and ${TOTAL}."
    done

    SORTED_IDX="${DISPLAY_ORDER[$((SELECTION - 1))]}"
    SELECTED_ID="${ITEM_IDS[$SORTED_IDX]}"
    SELECTED_TYPE="${ITEM_TYPES[$SORTED_IDX]}"
    SELECTED_PRIORITY="${ITEM_PRIORITIES[$SORTED_IDX]}"
    SELECTED_SUMMARY="${ITEM_SUMMARIES[$SORTED_IDX]}"
    SELECTED_BODY="${ITEM_BODIES[$SORTED_IDX]}"

    # Build description for /feature-dev
    DEBT_DESCRIPTION="[${SELECTED_ID}] ${SELECTED_SUMMARY} (${SELECTED_TYPE}, ${SELECTED_PRIORITY})"
    if [ -n "$SELECTED_BODY" ]; then
        DEBT_DESCRIPTION="${DEBT_DESCRIPTION}

${SELECTED_BODY}"
    fi

    # Auto-generate branch name: type/id-slug
    SLUG=$(echo "$SELECTED_SUMMARY" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-50)
    TYPE_PREFIX="${SELECTED_TYPE}"
    # Map type to branch prefix
    case "$SELECTED_TYPE" in
        tech-debt) TYPE_PREFIX="debt" ;;
        feature)   TYPE_PREFIX="feature" ;;
        bug)       TYPE_PREFIX="fix" ;;
        *)         TYPE_PREFIX="$SELECTED_TYPE" ;;
    esac
    BRANCH_NAME="${TYPE_PREFIX}/${SELECTED_ID}-${SLUG}"

    echo ""
    echo "Selected: [${SELECTED_ID}] ${SELECTED_SUMMARY}"
    echo "Branch:   $BRANCH_NAME"
    echo ""
fi

# Validate branch name
if [ -z "$BRANCH_NAME" ]; then
    echo "Error: Branch name is required"
    echo "Use -h or --help for usage information"
    exit 1
fi

# Configuration
WORKTREES_BASE="$HOME/Dev/worktrees"
# Build env file path from app directory
if [ -n "$APP_DIR" ]; then
    ENV_PATH="$APP_DIR/.env"
else
    ENV_PATH=".env"
fi

FILES_TO_COPY=(
    "$ENV_PATH"
    ".claude/settings.local.json"
)

# Get the current git repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "Error: Not inside a git repository. Please run this from within your project."
    exit 1
}

# Ensure we're on main and pull latest
CURRENT_BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "Error: You must be on the 'main' branch to create a worktree."
    echo "Current branch: $CURRENT_BRANCH"
    echo "Run: git checkout main"
    exit 1
fi

echo "Pulling latest changes from main..."
git -C "$REPO_ROOT" pull || {
    echo "Error: Failed to pull latest changes."
    exit 1
}

# Get repo name for organizing worktrees
REPO_NAME=$(basename "$REPO_ROOT")
if [ -z "$REPO_NAME" ]; then
    echo "Error: Could not determine repository name from: $REPO_ROOT"
    exit 1
fi

# Sanitize branch name for folder (replace / with -)
WORKTREE_FOLDER_NAME="${BRANCH_NAME//\//-}"

# Build paths
REPO_WORKTREES_DIR="$WORKTREES_BASE/$REPO_NAME"
WORKTREE_PATH="$REPO_WORKTREES_DIR/$WORKTREE_FOLDER_NAME"

# Check if worktree already exists
if [ -d "$WORKTREE_PATH" ]; then
    echo "Error: Worktree already exists at: $WORKTREE_PATH"
    exit 1
fi

# Auto-detect port if not specified
if [ "$PORT" -eq 0 ]; then
    BASE_PORT=3001
    USED_PORTS=()

    # Check existing worktrees for used ports
    if [ -d "$REPO_WORKTREES_DIR" ] && ls "$REPO_WORKTREES_DIR"/* &>/dev/null; then
        for wt in "$REPO_WORKTREES_DIR"/*; do
            if [ -d "$wt" ]; then
                ENV_FILE="$wt/$ENV_PATH"
                if [ -f "$ENV_FILE" ]; then
                    PORT_MATCH=$(grep -o 'NEXT_PUBLIC_APP_URL=http://localhost:[0-9]*' "$ENV_FILE" | grep -o '[0-9]*$' || true)
                    if [ -n "$PORT_MATCH" ]; then
                        USED_PORTS+=("$PORT_MATCH")
                    fi
                fi
            fi
        done
    fi

    # Check what's actually running (macOS uses lsof instead of netstat)
    RUNNING_PORTS=$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk '{print $9}' | grep -o ':[0-9]*$' | grep -o '[0-9]*' || true)

    # Find next available port
    PORT=$BASE_PORT
    while true; do
        PORT_IN_USE=0

        # Check against used ports
        if [ ${#USED_PORTS[@]} -gt 0 ]; then
            for used in "${USED_PORTS[@]}"; do
                if [ "$PORT" -eq "$used" ]; then
                    PORT_IN_USE=1
                    break
                fi
            done
        fi

        # Check against running ports
        if [ $PORT_IN_USE -eq 0 ]; then
            for running in ${RUNNING_PORTS:-}; do
                if [ "$PORT" -eq "$running" ]; then
                    PORT_IN_USE=1
                    break
                fi
            done
        fi

        if [ $PORT_IN_USE -eq 0 ]; then
            break
        fi

        PORT=$((PORT + 1))
    done
fi

echo "========================================"
echo "Creating Worktree: $BRANCH_NAME"
echo "Location: $WORKTREE_PATH"
echo "Port: $PORT"
echo "========================================"

# Create parent directory if needed
mkdir -p "$REPO_WORKTREES_DIR"

# Step 1: Create the worktree with new branch
echo ""
echo "[1/7] Creating git worktree..."
git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" || {
    echo "Error: Failed to create worktree"
    exit 1
}

# Step 2: Copy local config files
echo ""
echo "[2/7] Copying local config files..."
for file in "${FILES_TO_COPY[@]}"; do
    SOURCE_PATH="$REPO_ROOT/$file"
    DEST_PATH="$WORKTREE_PATH/$file"

    if [ -f "$SOURCE_PATH" ]; then
        # Create directory if needed
        DEST_DIR=$(dirname "$DEST_PATH")
        mkdir -p "$DEST_DIR"

        # Copy the file
        cp "$SOURCE_PATH" "$DEST_PATH"
        echo "  Copied: $file"
    else
        echo "  Skipped (not found): $file"
    fi
done

# Step 3: Update port in .env
echo ""
echo "[3/7] Configuring port $PORT..."
ENV_LOCAL_PATH="$WORKTREE_PATH/$ENV_PATH"
if [ -f "$ENV_LOCAL_PATH" ]; then
    # macOS sed requires -i '' for in-place editing
    if [ "$(uname)" = "Darwin" ]; then
        sed -i '' "s|NEXT_PUBLIC_APP_URL=http://localhost:[0-9]*|NEXT_PUBLIC_APP_URL=http://localhost:$PORT|g" "$ENV_LOCAL_PATH"
        sed -i '' "s|NEXTAUTH_URL=http://localhost:[0-9]*|NEXTAUTH_URL=http://localhost:$PORT|g" "$ENV_LOCAL_PATH"
    else
        sed -i "s|NEXT_PUBLIC_APP_URL=http://localhost:[0-9]*|NEXT_PUBLIC_APP_URL=http://localhost:$PORT|g" "$ENV_LOCAL_PATH"
        sed -i "s|NEXTAUTH_URL=http://localhost:[0-9]*|NEXTAUTH_URL=http://localhost:$PORT|g" "$ENV_LOCAL_PATH"
    fi
    echo "  Updated NEXT_PUBLIC_APP_URL and NEXTAUTH_URL to port $PORT"
fi

# Step 4: Create TASKS.md and add to .gitignore
echo ""
echo "[4/7] Creating TASKS.md..."
if [ -n "$DEBT_DESCRIPTION" ]; then
    cat > "$WORKTREE_PATH/TASKS.md" << EOF
# Technical Debt: $(echo "$DEBT_DESCRIPTION" | head -n 1)

Created: $(date "+%Y-%m-%d %H:%M")
Port: $PORT

## Description
$DEBT_DESCRIPTION

## Tasks
- [ ] Investigate and plan approach
- [ ] Implement fix
- [ ] Add/update tests
- [ ] Verify no regressions

## Notes
-

## Done
<!-- Move completed tasks here -->
EOF
else
    cat > "$WORKTREE_PATH/TASKS.md" << EOF
# Tasks for: $BRANCH_NAME

Created: $(date "+%Y-%m-%d %H:%M")
Port: $PORT

## Objectives
- [ ] Define the main goal of this branch

## Tasks
- [ ] Task 1
- [ ] Task 2

## Notes
-

## Done
<!-- Move completed tasks here -->
EOF
fi
echo "  Created TASKS.md"

# Add TASKS.md to the main repo's .gitignore if not already there
GITIGNORE_PATH="$REPO_ROOT/.gitignore"
if [ -f "$GITIGNORE_PATH" ]; then
    if ! grep -q "TASKS\.md" "$GITIGNORE_PATH"; then
        echo "" >> "$GITIGNORE_PATH"
        echo "# Worktree local files" >> "$GITIGNORE_PATH"
        echo "TASKS.md" >> "$GITIGNORE_PATH"
        echo "  Added TASKS.md to main repo .gitignore"
    fi
fi

# Step 5: Install dependencies
echo ""
echo "[5/7] Installing dependencies with pnpm..."
(cd "$WORKTREE_PATH" && pnpm install) || echo "Warning: pnpm install failed. You may need to install dependencies manually."

# Step 6: Start dev server in background
echo ""
echo "[6/7] Starting dev server on port $PORT..."
if [ -n "$APP_DIR" ]; then
    DEV_DIR="$WORKTREE_PATH/$APP_DIR"
else
    DEV_DIR="$WORKTREE_PATH"
fi
pnpm --dir "$DEV_DIR" dev -p "$PORT" &> "$WORKTREE_PATH/.dev-server.log" &
DEV_PID=$!
echo "  Dev server starting (PID: $DEV_PID, log: .dev-server.log)"


echo ""
echo "========================================"
echo "Worktree created successfully!"
echo "========================================"
echo "Branch: $BRANCH_NAME"
echo "Path: $WORKTREE_PATH"
echo "Port: $PORT"
echo ""
echo "Dev server: http://localhost:$PORT (PID: $DEV_PID)"
echo "Dev log: $WORKTREE_PATH/.dev-server.log"
echo "To cleanup when done: wt-cleanup $WORKTREE_FOLDER_NAME"

# Switch to worktree directory and launch Claude
cd "$WORKTREE_PATH"
echo ""
echo "[8/7] Launching Claude in $WORKTREE_PATH..."
if [ -n "$DEBT_DESCRIPTION" ]; then
    DEBT_TITLE=$(echo "$DEBT_DESCRIPTION" | head -n 1)
    echo "(Auto-running /feature-flow for selected tech debt)"
    echo "/feature-flow $DEBT_TITLE - see TASKS.md for full details" | claude
else
    claude
fi
