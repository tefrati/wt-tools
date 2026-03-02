<#
.SYNOPSIS
    Cleans up a git worktree after PR has been merged.

.DESCRIPTION
    This script removes the worktree, deletes the branch (local and optionally remote),
    and cleans up any remaining files.

.PARAMETER WorktreeName
    The name of the worktree folder to remove (the sanitized branch name, e.g., "feature-add-auth").

.PARAMETER DeleteRemote
    Optional switch. If specified, also deletes the remote branch.

.PARAMETER Force
    Optional switch. Skip confirmation prompt.

.EXAMPLE
    wt-cleanup feature-add-auth
    wt-cleanup feature-add-auth -DeleteRemote
    wt-cleanup feature-add-auth -DeleteRemote -Force
#>

param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$WorktreeName,

    [Parameter(Mandatory=$false)]
    [switch]$DeleteRemote,

    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [switch]$h,

    [Parameter(Mandatory=$false)]
    [switch]$help
)

# Handle help flags
if ($h -or $help) {
    Get-Help $PSCommandPath -Detailed
    exit 0
}

# Configuration
$WorktreesBase = Join-Path $HOME "Dev\worktrees"

# Get the current git repo root
$gitOutput = git rev-parse --show-toplevel 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not inside a git repository. Please run this from within your project."
    exit 1
}
$RepoRoot = ($gitOutput | Out-String).Trim() -replace '/', '\'
$RepoName = [System.IO.Path]::GetFileName($RepoRoot)

# Build worktree path step by step
$RepoWorktreesDir = Join-Path $WorktreesBase $RepoName

# If no worktree name given, show interactive picker
if ([string]::IsNullOrWhiteSpace($WorktreeName)) {
    if (-not (Test-Path $RepoWorktreesDir)) {
        Write-Error "No worktrees found for $RepoName"
        exit 1
    }

    $dirs = Get-ChildItem $RepoWorktreesDir -Directory -ErrorAction SilentlyContinue
    if (-not $dirs -or $dirs.Count -eq 0) {
        Write-Error "No worktrees found for $RepoName"
        exit 1
    }

    if (Get-Command fzf -ErrorAction SilentlyContinue) {
        $WorktreeName = ($dirs | ForEach-Object { $_.Name }) | fzf --prompt="Select worktree to clean up: "
        if ([string]::IsNullOrWhiteSpace($WorktreeName)) {
            Write-Host "Cancelled." -ForegroundColor Yellow
            exit 0
        }
    } else {
        Write-Host "Available worktrees for ${RepoName}:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $dirs.Count; $i++) {
            Write-Host "  $($i + 1)) $($dirs[$i].Name)"
        }
        Write-Host ""
        $selection = Read-Host "Select worktree (1-$($dirs.Count))"
        $selInt = 0
        if (-not [int]::TryParse($selection, [ref]$selInt) -or $selInt -lt 1 -or $selInt -gt $dirs.Count) {
            Write-Host "Invalid selection." -ForegroundColor Red
            exit 1
        }
        $WorktreeName = $dirs[$selInt - 1].Name
    }
}

$WorktreePath = Join-Path $RepoWorktreesDir $WorktreeName

# Check if worktree exists
if (-not (Test-Path $WorktreePath)) {
    Write-Error "Worktree not found at: $WorktreePath"
    Write-Host "`nExisting worktrees:" -ForegroundColor Yellow
    git worktree list
    exit 1
}

# Get branch name from worktree
$branchName = git -C "$WorktreePath" branch --show-current

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Worktree Cleanup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Worktree: $WorktreePath"
Write-Host "Branch: $branchName"
if ($DeleteRemote) {
    Write-Host "Remote branch will also be deleted" -ForegroundColor Yellow
}

# Confirmation
if (-not $Force) {
    $confirmation = Read-Host "`nAre you sure you want to remove this worktree? (y/N)"
    if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Step 1: Kill any running dev server on this worktree's port
Write-Host "`n[1/4] Checking for running dev servers..." -ForegroundColor Yellow
$envLocalPath = Join-Path $WorktreePath ".env.local"
if (Test-Path $envLocalPath) {
    $envContent = Get-Content $envLocalPath -Raw
    if ($envContent -match 'NEXT_PUBLIC_APP_URL=http://localhost:(\d+)') {
        $port = $Matches[1]
        Write-Host "  Checking port $port..." -ForegroundColor Gray
        
        # Find and kill process on that port
        $netstatOutput = netstat -ano | Select-String ":$port\s.*LISTENING"
        if ($netstatOutput) {
            foreach ($line in $netstatOutput) {
                if ($line -match '\s(\d+)$') {
                    $procId = [int]$Matches[1]
                    Write-Host "  Stopping process $procId on port $port..." -ForegroundColor Yellow
                    try {
                        $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
                        if ($proc) {
                            $proc.CloseMainWindow() | Out-Null
                            if (-not $proc.WaitForExit(2000)) {
                                Write-Host "  Process didn't stop gracefully, force killing..." -ForegroundColor Yellow
                                taskkill /PID $procId /F 2>$null
                            }
                        }
                    } catch {
                        taskkill /PID $procId /F 2>$null
                    }
                }
            }
        }
    }
}

# Step 2: Remove the worktree
Write-Host "`n[2/4] Removing worktree..." -ForegroundColor Yellow
Push-Location $RepoRoot
git worktree remove "$WorktreePath" --force 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Warning "git worktree remove failed, trying manual cleanup..."
    Pop-Location
    Remove-Item $WorktreePath -Recurse -Force -ErrorAction SilentlyContinue
    Push-Location $RepoRoot
    git worktree prune
}
Pop-Location

# Step 3: Delete local branch
Write-Host "`n[3/4] Deleting local branch: $branchName..." -ForegroundColor Yellow
if ($branchName -and $branchName -ne "main" -and $branchName -ne "master") {
    Push-Location $RepoRoot
    git branch -D $branchName 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Branch may have already been deleted or merged" -ForegroundColor DarkYellow
    }
    Pop-Location
} else {
    Write-Host "  Skipping deletion of protected branch: $branchName" -ForegroundColor DarkYellow
}

# Step 4: Delete remote branch if requested
if ($DeleteRemote -and $branchName -and $branchName -ne "main" -and $branchName -ne "master") {
    Write-Host "`n[4/4] Deleting remote branch: origin/$branchName..." -ForegroundColor Yellow
    Push-Location $RepoRoot
    git push origin --delete $branchName 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Remote branch may have already been deleted" -ForegroundColor DarkYellow
    }
    Pop-Location
} else {
    Write-Host "`n[4/4] Skipping remote branch deletion" -ForegroundColor Gray
}

# Clean up empty directories
if (Test-Path $RepoWorktreesDir) {
    $remainingWorktrees = Get-ChildItem $RepoWorktreesDir -Directory -ErrorAction SilentlyContinue
    if (-not $remainingWorktrees -or $remainingWorktrees.Count -eq 0) {
        Remove-Item $RepoWorktreesDir -Force -ErrorAction SilentlyContinue
        Write-Host "`nCleaned up empty directory: $RepoWorktreesDir" -ForegroundColor Gray
    }
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Cleanup complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
