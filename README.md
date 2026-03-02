# Worktree Management Scripts

Quick parallel development workflow using git worktrees.

## Setup (One-time)

```powershell
.\setup-worktree-commands.ps1
```

Then restart your terminal or run `. $PROFILE`

## Commands

### Create a worktree

```powershell
# From inside any git repo
wt-create feature/add-oauth

# With specific port
wt-create feature/add-oauth -Port 3005
```

**What it does:**
1. Creates worktree at `C:\Users\tzah_\Dev\worktrees\<repo-name>\<branch-name>`
2. Copies `.env.local` and `.claude\settings.local.json` from main repo
3. Updates port in `.env.local`
4. Creates `TASKS.md` for task tracking
5. Runs `pnpm install`
6. Opens Cursor IDE in the worktree
7. Starts dev server in a new terminal tab
8. Opens Chrome at the assigned port

### Cleanup a worktree

```powershell
# Basic cleanup (after PR merged)
wt-cleanup feature-add-oauth

# Also delete remote branch
wt-cleanup feature-add-oauth -DeleteRemote

# Skip confirmation
wt-cleanup feature-add-oauth -DeleteRemote -Force
```

**What it does:**
1. Kills any dev server running on the worktree's port
2. Removes the git worktree
3. Deletes the local branch
4. Optionally deletes the remote branch
5. Cleans up empty directories

## File Structure

```
C:\Users\tzah_\Dev\
├── scripts\
│   ├── wt-create.ps1
│   ├── wt-cleanup.ps1
│   └── setup-worktree-commands.ps1
├── worktrees\
│   └── <repo-name>\
│       ├── feature-add-oauth\     # Port 3001
│       └── bugfix-fix-login\      # Port 3002
└── v0-privacy-compliance-dashboard\  # Main repo (port 3000)
```

## Port Assignment

- Main repo: 3000 (default)
- Worktrees: Auto-assigned starting from 3001
- Specify manually with `-Port` if needed

## Tips

- Branch names with `/` are converted to `-` for folder names
- The worktree name shown in terminal is what you use for cleanup
- `TASKS.md` is created in each worktree for tracking work
