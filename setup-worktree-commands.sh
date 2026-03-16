#!/bin/bash

# Sets up wt-create and wt-cleanup as global shell commands.
# Run this script once to add the worktree commands to your shell profile.
# After running, you can use 'wt-create' and 'wt-cleanup' from any directory.

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect shell and profile file
if [ -n "$ZSH_VERSION" ]; then
    PROFILE_PATH="$HOME/.zshrc"
    SHELL_NAME="zsh"
elif [ -n "$BASH_VERSION" ]; then
    PROFILE_PATH="$HOME/.bashrc"
    # macOS uses .bash_profile instead
    if [ "$(uname)" = "Darwin" ]; then
        PROFILE_PATH="$HOME/.bash_profile"
    fi
    SHELL_NAME="bash"
else
    echo "Unsupported shell. Please use bash or zsh."
    exit 1
fi

# Create profile if it doesn't exist
if [ ! -f "$PROFILE_PATH" ]; then
    touch "$PROFILE_PATH"
    echo "Created shell profile at: $PROFILE_PATH"
fi

# Check if already added
MARKER="# Worktree Commands"
if grep -q "$MARKER" "$PROFILE_PATH" 2>/dev/null; then
    echo "Worktree commands already configured in profile."
else
    # Add to profile
    cat >> "$PROFILE_PATH" << EOF

$MARKER
alias wt-create="$SCRIPTS_DIR/wt-create.sh"
alias wt-cleanup="$SCRIPTS_DIR/wt-cleanup.sh"
EOF
    echo "Added worktree commands to profile."
fi

echo ""
echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo ""
echo "To activate, either:"
echo "  1. Restart your terminal, OR"
echo "  2. Run: source $PROFILE_PATH"
echo ""
echo "Usage:"
echo "  wt-create <branch-name> [-p <port>]"
echo "  wt-cleanup <worktree-name> [-r] [-f]"
echo ""
echo "Examples:"
echo "  wt-create feature/add-oauth"
echo "  wt-create bugfix/fix-login -p 3005"
echo "  wt-cleanup feature-add-oauth"
echo "  wt-cleanup feature-add-oauth -r"
echo ""
