<#
.SYNOPSIS
    Creates a git worktree with full development environment setup.

.DESCRIPTION
    This script creates a new git worktree, copies local config files,
    installs dependencies, and opens Cursor IDE.

.PARAMETER BranchName
    The name of the branch to create (also used as worktree folder name and Claude session name).

.PARAMETER Port
    Optional. The port to configure in .env.local. If not specified, auto-increments from 3001.

.PARAMETER Backlog
    Optional. Pick a backlog item from docs/backlog.md to create a worktree for.

.EXAMPLE
    wt-create feature/add-auth
    wt-create feature/add-auth -Port 3005
    wt-create -Backlog
#>

param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$BranchName,

    [Parameter(Mandatory=$false)]
    [int]$Port = 0,

    [Parameter(Mandatory=$false)]
    [switch]$Backlog,

    [Parameter(Mandatory=$false)]
    [switch]$b,

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

$DebtDescription = ""

# --- Backlog Mode ---
if ($Backlog -or $b) {
    # Need repo root early for debt mode
    $gitOutput = git rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Not inside a git repository."
        exit 1
    }
    $DebtRepoRoot = ($gitOutput | Out-String).Trim() -replace '/', '\'
    $DebtFile = Join-Path $DebtRepoRoot "docs\backlog.md"

    if (-not (Test-Path $DebtFile)) {
        Write-Error "No docs/backlog.md found in the repository."
        exit 1
    }

    # Parse backlog items from docs/backlog.md
    # Format: ## BL-001: Summary title
    #         - **Type**: tech-debt
    #         - **Priority**: critical
    $ItemIDs = @()
    $ItemTypes = @()
    $ItemPriorities = @()
    $ItemSummaries = @()
    $ItemBodies = @()

    $CurrentID = ""
    $CurrentSummary = ""
    $CurrentType = ""
    $CurrentPriority = ""
    $CurrentBody = ""

    function Save-Current {
        if ($script:CurrentID) {
            $script:ItemIDs += $script:CurrentID
            $script:ItemSummaries += $script:CurrentSummary
            $script:ItemTypes += if ($script:CurrentType) { $script:CurrentType } else { "unknown" }
            $script:ItemPriorities += if ($script:CurrentPriority) { $script:CurrentPriority } else { "medium" }
            $script:ItemBodies += $script:CurrentBody.Trim()
        }
    }

    foreach ($line in Get-Content $DebtFile) {
        if ($line -match '^##\s+([A-Z]+-\d+):\s+(.+)$') {
            Save-Current
            $CurrentID = $Matches[1]
            $CurrentSummary = $Matches[2]
            $CurrentType = ""
            $CurrentPriority = ""
            $CurrentBody = ""
        } elseif ($CurrentID) {
            if ($line -match '^-\s+\*\*Type\*\*:\s+(.+)$') {
                $CurrentType = $Matches[1]
            } elseif ($line -match '^-\s+\*\*Priority\*\*:\s+(.+)$') {
                $CurrentPriority = $Matches[1]
            } elseif ($line -eq '---') {
                # separator, skip
            } elseif ($line -notmatch '^-\s+\*\*(Source|Files)\*\*:') {
                if ($line.Trim()) {
                    $CurrentBody += "$line`n"
                }
            }
        }
    }
    Save-Current

    if ($ItemIDs.Count -eq 0) {
        Write-Error "No backlog items found in docs/backlog.md."
        exit 1
    }

    # Build display order sorted by priority: critical, high, medium, low
    $DisplayOrder = @()
    foreach ($prio in @("critical", "high", "medium", "low")) {
        for ($i = 0; $i -lt $ItemIDs.Count; $i++) {
            if ($ItemPriorities[$i] -eq $prio) {
                $DisplayOrder += $i
            }
        }
    }
    for ($i = 0; $i -lt $ItemIDs.Count; $i++) {
        if ($DisplayOrder -notcontains $i) {
            $DisplayOrder += $i
        }
    }

    # Display menu
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Backlog Items" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    $lastPriority = ""
    for ($idx = 0; $idx -lt $DisplayOrder.Count; $idx++) {
        $i = $DisplayOrder[$idx]
        if ($ItemPriorities[$i] -ne $lastPriority) {
            Write-Host ""
            Write-Host "  --- $($ItemPriorities[$i]) ---" -ForegroundColor DarkYellow
            $lastPriority = $ItemPriorities[$i]
        }
        Write-Host "  $($idx + 1). [$($ItemIDs[$i])] ($($ItemTypes[$i])) $($ItemSummaries[$i])" -ForegroundColor White
    }
    Write-Host ""

    # Get user selection
    $total = $DisplayOrder.Count
    while ($true) {
        $selection = Read-Host "Select an item (1-$total), or q to quit"
        if ($selection -eq 'q' -or $selection -eq 'Q') {
            Write-Host "Cancelled."
            exit 0
        }
        if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $total) {
            break
        }
        Write-Host "Invalid selection. Please enter a number between 1 and $total."
    }

    $sortedIdx = $DisplayOrder[[int]$selection - 1]
    $SelectedID = $ItemIDs[$sortedIdx]
    $SelectedType = $ItemTypes[$sortedIdx]
    $SelectedPriority = $ItemPriorities[$sortedIdx]
    $SelectedSummary = $ItemSummaries[$sortedIdx]
    $SelectedBody = $ItemBodies[$sortedIdx]

    # Build description for /feature-dev
    $DebtDescription = "[$SelectedID] $SelectedSummary ($SelectedType, $SelectedPriority)"
    if ($SelectedBody) {
        $DebtDescription = "$DebtDescription`n`n$SelectedBody"
    }

    # Auto-generate branch name: type/id-slug
    $slug = $SelectedSummary.ToLower() -replace '[^a-z0-9]', '-' -replace '-+', '-' -replace '^-|-$', ''
    if ($slug.Length -gt 50) { $slug = $slug.Substring(0, 50) }
    $typePrefix = switch ($SelectedType) {
        "tech-debt" { "debt" }
        "feature"   { "feature" }
        "bug"       { "fix" }
        default     { $SelectedType }
    }
    $BranchName = "$typePrefix/$SelectedID-$slug"

    Write-Host ""
    Write-Host "Selected: [$SelectedID] $SelectedSummary" -ForegroundColor Green
    Write-Host "Branch:   $BranchName" -ForegroundColor Green
    Write-Host ""
}

# Validate BranchName is provided
if ([string]::IsNullOrWhiteSpace($BranchName)) {
    Write-Error "BranchName is required. Use -h or --help for usage information."
    exit 1
}

# Configuration
$WorktreesBase = Join-Path $HOME "Dev\worktrees"
$FilesToCopy = @(
    ".env.local",
    ".claude\settings.local.json"
)

# Get the current git repo root
$gitOutput = git rev-parse --show-toplevel 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not inside a git repository. Please run this from within your project."
    exit 1
}
$RepoRoot = ($gitOutput | Out-String).Trim() -replace '/', '\'

# Ensure we're on main and pull latest
$CurrentBranch = (git -C $RepoRoot rev-parse --abbrev-ref HEAD | Out-String).Trim()
if ($CurrentBranch -ne "main") {
    Write-Error "You must be on the 'main' branch to create a worktree. Current branch: $CurrentBranch. Run: git checkout main"
    exit 1
}

Write-Host "Pulling latest changes from main..." -ForegroundColor Yellow
git -C $RepoRoot pull
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to pull latest changes."
    exit 1
}

# Get repo name for organizing worktrees
$RepoName = [System.IO.Path]::GetFileName($RepoRoot)
if ([string]::IsNullOrWhiteSpace($RepoName)) {
    Write-Error "Could not determine repository name from: $RepoRoot"
    exit 1
}

# Sanitize branch name for folder (replace / with -)
$WorktreeFolderName = $BranchName -replace '/', '-'

# Build path step by step (Join-Path with 3 args doesn't work in older PS)
$RepoWorktreesDir = Join-Path $WorktreesBase $RepoName
$WorktreePath = Join-Path $RepoWorktreesDir $WorktreeFolderName

# Check if worktree already exists
if (Test-Path $WorktreePath) {
    Write-Error "Worktree already exists at: $WorktreePath"
    exit 1
}

# Auto-detect port if not specified
if ($Port -eq 0) {
    $BasePort = 3001
    $UsedPorts = @()

    if (Test-Path $RepoWorktreesDir) {
        $ExistingWorktrees = Get-ChildItem $RepoWorktreesDir -Directory -ErrorAction SilentlyContinue
        foreach ($wt in $ExistingWorktrees) {
            $envFile = Join-Path $wt.FullName ".env.local"
            if (Test-Path $envFile) {
                $content = Get-Content $envFile -Raw
                if ($content -match 'NEXT_PUBLIC_APP_URL=http://localhost:(\d+)') {
                    $UsedPorts += [int]$Matches[1]
                }
            }
        }
    }

    # Also check what's actually running
    $runningPorts = @()
    netstat -ano 2>$null | Select-String "LISTENING" | ForEach-Object {
        if ($_.Line -match ':(\d+)\s+.*LISTENING') {
            $runningPorts += [int]$Matches[1]
        }
    }

    $Port = $BasePort
    while (($Port -in $UsedPorts) -or ($Port -in $runningPorts)) {
        $Port++
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Creating Worktree: $BranchName" -ForegroundColor Cyan
Write-Host "Location: $WorktreePath" -ForegroundColor Cyan
Write-Host "Port: $Port" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Create parent directory if needed
if (-not (Test-Path $RepoWorktreesDir)) {
    New-Item -ItemType Directory -Path $RepoWorktreesDir -Force | Out-Null
}

# Step 1: Create the worktree with new branch
Write-Host "`n[1/6] Creating git worktree..." -ForegroundColor Yellow
git worktree add -b "$BranchName" "$WorktreePath"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create worktree"
    exit 1
}

# Step 2: Copy local config files
Write-Host "`n[2/6] Copying local config files..." -ForegroundColor Yellow
foreach ($file in $FilesToCopy) {
    $sourcePath = Join-Path $RepoRoot $file
    $destPath = Join-Path $WorktreePath $file

    if (Test-Path $sourcePath) {
        # Create directory if needed
        $destDir = Split-Path $destPath -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        # Copy the file
        Copy-Item $sourcePath $destPath -Force
        Write-Host "  Copied: $file" -ForegroundColor Green
    } else {
        Write-Host "  Skipped (not found): $file" -ForegroundColor DarkYellow
    }
}

# Step 3: Update port in .env.local
Write-Host "`n[3/6] Configuring port $Port..." -ForegroundColor Yellow
$envLocalPath = Join-Path $WorktreePath ".env.local"
if (Test-Path $envLocalPath) {
    $envContent = Get-Content $envLocalPath -Raw
    $envContent = $envContent -replace 'NEXT_PUBLIC_APP_URL=http://localhost:\d+', "NEXT_PUBLIC_APP_URL=http://localhost:$Port"
    $envContent = $envContent -replace 'NEXTAUTH_URL=http://localhost:\d+', "NEXTAUTH_URL=http://localhost:$Port"
    Set-Content $envLocalPath $envContent -NoNewline
    Write-Host "  Updated NEXT_PUBLIC_APP_URL and NEXTAUTH_URL to port $Port" -ForegroundColor Green
}

# Step 4: Create TASKS.md and add to .gitignore
Write-Host "`n[4/6] Creating TASKS.md..." -ForegroundColor Yellow
if ($DebtDescription) {
    $DebtTitle = ($DebtDescription -split "`n")[0]
    $tasksContent = @"
# Technical Debt: $DebtTitle

Created: $(Get-Date -Format "yyyy-MM-dd HH:mm")
Port: $Port

## Description
$DebtDescription

## Tasks
- [ ] Investigate and plan approach
- [ ] Implement fix
- [ ] Add/update tests
- [ ] Verify no regressions

## Notes
-

## Done
<!-- Move completed tasks here -->
"@
} else {
    $tasksContent = @"
# Tasks for: $BranchName

Created: $(Get-Date -Format "yyyy-MM-dd HH:mm")
Port: $Port

## Objectives
- [ ] Define the main goal of this branch

## Tasks
- [ ] Task 1
- [ ] Task 2

## Notes
-

## Done
<!-- Move completed tasks here -->
"@
}
Set-Content (Join-Path $WorktreePath "TASKS.md") $tasksContent
Write-Host "  Created TASKS.md" -ForegroundColor Green

# Add TASKS.md to the main repo's .gitignore if not already there
$gitignorePath = Join-Path $RepoRoot ".gitignore"
if (Test-Path $gitignorePath) {
    $gitignoreContent = Get-Content $gitignorePath -Raw
    if ($gitignoreContent -notmatch 'TASKS\.md') {
        Add-Content $gitignorePath "`n# Worktree local files`nTASKS.md"
        Write-Host "  Added TASKS.md to .gitignore" -ForegroundColor Green
    }
}

# Step 5: Install dependencies
Write-Host "`n[5/6] Installing dependencies with pnpm..." -ForegroundColor Yellow
Push-Location $WorktreePath
pnpm install
Pop-Location

# Step 6: Open Cursor IDE and configure layout
Write-Host "`n[6/6] Opening Cursor IDE..." -ForegroundColor Yellow
Start-Process "cursor" -ArgumentList "$WorktreePath"

# Wait for Cursor to load, then set layout: explorer open, terminal open, agent panel closed
Start-Sleep -Seconds 3
$wshell = New-Object -ComObject WScript.Shell
$wshell.AppActivate("Cursor") | Out-Null
Start-Sleep -Milliseconds 500
$wshell.SendKeys("^l")          # Ctrl+L: close Agent/Chat panel
Start-Sleep -Milliseconds 300
$wshell.SendKeys("^+e")         # Ctrl+Shift+E: open Explorer sidebar
Start-Sleep -Milliseconds 300
$wshell.SendKeys("^j")          # Ctrl+J: open Terminal panel

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Worktree created successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Branch: $BranchName"
Write-Host "Path: $WorktreePath"
Write-Host "Port: $Port"
Write-Host ""
Write-Host "Start the dev server: pnpm dev -p $Port" -ForegroundColor Cyan
Write-Host "To cleanup when done: wt-cleanup $WorktreeFolderName" -ForegroundColor Cyan

# Switch to worktree directory and launch Claude
Set-Location $WorktreePath
Write-Host "`nLaunching Claude in $WorktreePath..." -ForegroundColor Yellow
if ($DebtDescription) {
    Write-Host "(Auto-running /feature-dev for selected tech debt)" -ForegroundColor Yellow
    claude --prompt "/feature-dev $DebtDescription"
} else {
    claude
}
