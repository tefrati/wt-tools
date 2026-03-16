# Worktree Management Scripts (macOS)

Quick parallel development workflow using git worktrees.

## Setup (One-time)

```bash
cd ~/Dev/scripts
chmod +x setup-worktree-commands.sh wt-create.sh wt-cleanup.sh
./setup-worktree-commands.sh
```

Then restart your terminal or run `source ~/.zshrc` (or `source ~/.bashrc` if using bash)

## Commands

### Create a worktree

```bash
# From inside any git repo
wt-create feature/add-oauth

# With specific port
wt-create feature/add-oauth -p 3005
```

**What it does:**
1. Creates worktree at `~/Dev/worktrees/<repo-name>/<branch-name>`
2. Copies `.env.local` and `.claude/settings.local.json` from main repo
3. Updates port in `.env.local`
4. Creates `TASKS.md` for task tracking
5. Runs `pnpm install`
6. Opens Cursor IDE in the worktree (or VS Code if Cursor not found)
7. Starts dev server in a new terminal window/tab
8. Opens browser at the assigned port

### Cleanup a worktree

```bash
# Basic cleanup (after PR merged)
wt-cleanup feature-add-oauth

# Also delete remote branch
wt-cleanup feature-add-oauth -r

# Skip confirmation
wt-cleanup feature-add-oauth -r -f
```

**What it does:**
1. Kills any dev server running on the worktree's port
2. Removes the git worktree
3. Deletes the local branch
4. Optionally deletes the remote branch
5. Cleans up empty directories

## File Structure

```
~/Dev/
├── scripts/
│   ├── wt-create.sh
│   ├── wt-cleanup.sh
│   └── setup-worktree-commands.sh
├── worktrees/
│   └── <repo-name>/
│       ├── feature-add-oauth/     # Port 3001
│       └── bugfix-fix-login/      # Port 3002
└── <your-project>/                    # Main repo (port 3000)
```

## Port Assignment

- Main repo: 3000 (default)
- Worktrees: Auto-assigned starting from 3001
- Specify manually with `-p` if needed

## Terminal Integration

The scripts work best with:
- **Ghostty** (recommended) - automatically opens new terminal for dev server
- **macOS Terminal** - uses AppleScript to open new tab
- **GNOME Terminal** - opens new terminal window
- **Fallback** - runs dev server in background

## Tips

- Branch names with `/` are converted to `-` for folder names
- The worktree name shown in terminal is what you use for cleanup
- `TASKS.md` is created in each worktree for tracking work
- If Cursor IDE is not installed, it falls back to VS Code, then Finder

## Troubleshooting

**Scripts not executable:**
```bash
chmod +x ~/Dev/scripts/*.sh
```

**Commands not found after setup:**
```bash
source ~/.zshrc  # or ~/.bashrc for bash
```

**Port already in use:**
```bash
# Find what's using the port
lsof -ti tcp:3001

# Kill it
kill -9 $(lsof -ti tcp:3001)
```

**Worktree path issues:**
Make sure you're running from inside a git repository.
