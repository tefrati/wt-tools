# wt-tools

Quick parallel development workflow using git worktrees. Cross-platform (Windows, macOS, Linux).

## What it does

`wt-create` sets up a fully isolated worktree with one command:

1. Creates a git worktree with a new branch
2. Copies `.env.local` and `.claude/settings.local.json` from the main repo
3. Auto-assigns a unique dev server port
4. Runs `pnpm install`
5. Opens your IDE (Cursor / VS Code)
6. Starts the dev server and opens your browser

`wt-cleanup` tears it down when you're done — kills the dev server, removes the worktree, deletes the branch.

## Setup

Clone this repo somewhere on your machine, then run the setup script:

```powershell
# Windows (PowerShell)
.\setup-worktree-commands.ps1
```

```bash
# macOS / Linux
chmod +x *.sh
./setup-worktree-commands.sh
```

Restart your terminal (or run `. $PROFILE` / `source ~/.zshrc`).

## Usage

### Create a worktree

```bash
# From inside any git repo
wt-create feature/add-oauth

# With a specific port
wt-create feature/add-oauth -p 3005        # macOS/Linux
wt-create feature/add-oauth -Port 3005      # Windows
```

### Clean up a worktree

```bash
wt-cleanup feature-add-oauth               # basic cleanup
wt-cleanup feature-add-oauth -r            # also delete remote branch (macOS/Linux)
wt-cleanup feature-add-oauth -DeleteRemote  # also delete remote branch (Windows)
```

## Port Assignment

- Main repo: 3000 (default)
- Worktrees: auto-assigned starting from 3001
- Override manually with `-p` / `-Port`

## File Structure

```
~/Dev/
├── wt-tools/                          # This repo
│   ├── wt-create.sh / .ps1
│   ├── wt-cleanup.sh / .ps1
│   └── setup-worktree-commands.sh / .ps1
├── worktrees/
│   └── <repo-name>/
│       ├── feature-add-oauth/         # Port 3001
│       └── bugfix-fix-login/          # Port 3002
└── <your-project>/                    # Main repo (port 3000)
```

## Optional Integrations

- **Backlog Orchestrator**: Set `BACKLOG_ORCHESTRATOR_URL` and `BACKLOG_ORCHESTRATOR_API_KEY` env vars to automatically update ticket status when creating branches. Silently skipped if not configured.
- **Cursor IDE**: Falls back to VS Code if not installed.
- **Ghostty terminal**: Best terminal experience on macOS; falls back to macOS Terminal or runs dev server in background.

## Tips

- Branch names with `/` are converted to `-` for folder names
- The worktree name shown in terminal is what you use for cleanup
- `TASKS.md` is created in each worktree for task tracking

## License

[MIT](LICENSE)
