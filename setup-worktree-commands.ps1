<#
.SYNOPSIS
    Sets up wt-create and wt-cleanup as global PowerShell commands.

.DESCRIPTION
    Run this script once to add the worktree commands to your PowerShell profile.
    After running, you can use 'wt-create' and 'wt-cleanup' from any directory.
#>

$ScriptsDir = "C:\Users\tzah_\Dev\scripts"
$ProfilePath = $PROFILE.CurrentUserAllHosts

# Create profile if it doesn't exist
if (-not (Test-Path $ProfilePath)) {
    New-Item -Path $ProfilePath -ItemType File -Force | Out-Null
    Write-Host "Created PowerShell profile at: $ProfilePath" -ForegroundColor Green
}

# Check if already added
$profileContent = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue
$marker = "# Worktree Commands"

if ($profileContent -and $profileContent.Contains($marker)) {
    Write-Host "Worktree commands already configured in profile." -ForegroundColor Yellow
} else {
    # Add to profile
    $addition = @"

$marker
function wt-create { & "$ScriptsDir\wt-create.ps1" @args }
function wt-cleanup { & "$ScriptsDir\wt-cleanup.ps1" @args }
"@
    
    Add-Content $ProfilePath $addition
    Write-Host "Added worktree commands to profile." -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "To activate, either:" -ForegroundColor Yellow
Write-Host "  1. Restart your terminal, OR"
Write-Host "  2. Run: . `$PROFILE"
Write-Host ""
Write-Host "Usage:" -ForegroundColor Yellow
Write-Host "  wt-create <branch-name> [-Port <port>]"
Write-Host "  wt-cleanup <worktree-name> [-DeleteRemote] [-Force]"
Write-Host ""
Write-Host "Examples:" -ForegroundColor Yellow
Write-Host "  wt-create feature/add-oauth"
Write-Host "  wt-create bugfix/fix-login -Port 3005"
Write-Host "  wt-cleanup feature-add-oauth"
Write-Host "  wt-cleanup feature-add-oauth -DeleteRemote"
