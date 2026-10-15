<#
.SYNOPSIS
    Installs the power-platform-alm-toolkit skill into one or more AI tools (Windows, macOS, Linux with PowerShell 5.1+ or 7+).
.EXAMPLE
    .\scripts\install.ps1                         # interactive menu
.EXAMPLE
    .\scripts\install.ps1 -Tool claude            # Claude Code, for your user
.EXAMPLE
    .\scripts\install.ps1 -Tool agents -Scope project   # .agents\skills in the current repo (Codex, Copilot, Cursor, Gemini CLI)
.EXAMPLE
    .\scripts\install.ps1 -Tool all -Uninstall
.EXAMPLE
    # Straight from GitHub:
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/NaveenGaneshe/power-platform-alm-toolkit-skill/main/scripts/install.ps1))) -Tool claude
#>
[CmdletBinding()]
param(
    # One or more of: claude, agents, codex, copilot, cursor, gemini, all (array or comma-separated)
    [string[]]$Tool,
    [ValidateSet('user', 'project')]
    [string]$Scope = 'user',
    [switch]$Uninstall,
    [string]$RepoUrl = $(if ($env:PP_SKILL_REPO_URL) { $env:PP_SKILL_REPO_URL } else { 'https://github.com/NaveenGaneshe/power-platform-alm-toolkit-skill.git' })
)

$ErrorActionPreference = 'Stop'
$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }

if (-not $Tool) {
    Write-Host 'Which AI tool should get the skill?'
    Write-Host '  1) Claude Code'
    Write-Host '  2) Codex / GitHub Copilot / Cursor / Gemini CLI (shared .agents folder)'
    Write-Host '  3) All of the above'
    $choice = Read-Host 'Choose 1-3 [3]'
    $Tool = switch ($choice) { '1' { 'claude' } '2' { 'agents' } default { 'all' } }
}

$valid = 'claude', 'agents', 'codex', 'copilot', 'cursor', 'gemini', 'all'
$requested = @($Tool | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
$unknown = @($requested | Where-Object { $_ -notin $valid })
if ($unknown) { throw "Unknown tool(s): $($unknown -join ', '). Use one of: $($valid -join ', ')." }
$expanded = foreach ($t in $requested) { if ($t -eq 'all') { 'claude'; 'agents' } else { $t } }

function Get-TargetDir([string]$t) {
    $base = if ($Scope -eq 'user') { $HomeDir } else { (Get-Location).Path }
    $rel = switch ($t) {
        'claude'  { '.claude/skills' }
        'agents'  { '.agents/skills' }
        'codex'   { '.agents/skills' }
        'copilot' { if ($Scope -eq 'user') { '.copilot/skills' } else { '.github/skills' } }
        'cursor'  { '.cursor/skills' }
        'gemini'  { '.gemini/skills' }
    }
    return (Join-Path $base $rel)
}

# Locate the skills/ folder next to this script, otherwise download the repo.
$skillsRoot = $null
$tmp = $null
if ($PSScriptRoot) {
    $candidate = Join-Path $PSScriptRoot '../skills'
    if (Test-Path $candidate) { $skillsRoot = (Resolve-Path $candidate).Path }
}
if (-not $skillsRoot -and -not $Uninstall) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("pp-skill-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host "Downloading skills from $RepoUrl ..."
        git clone --depth 1 --quiet $RepoUrl (Join-Path $tmp 'repo')
        if ($LASTEXITCODE -ne 0) { throw "git clone failed for $RepoUrl" }
    }
    else {
        $zipUrl = ($RepoUrl -replace '\.git$', '') + '/archive/refs/heads/main.zip'
        Write-Host "git not found; downloading $zipUrl ..."
        $zip = Join-Path $tmp 'repo.zip'
        Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $tmp
        Get-ChildItem $tmp -Directory | Where-Object Name -like '*-main' | Rename-Item -NewName 'repo'
    }
    $skillsRoot = Join-Path $tmp 'repo/skills'
    if (-not (Test-Path $skillsRoot)) { throw 'skills/ not found in downloaded repository.' }
}

$skillNames = @()
if ($skillsRoot) {
    $skillNames = @(Get-ChildItem $skillsRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } | ForEach-Object { $_.Name })
}
elseif ($Uninstall) {
    # Uninstall without a source checkout: fall back to the names known at release time.
    $skillNames = @('power-platform-alm-toolkit', 'pp-data-ops-agent', 'pp-governance-agent', 'pp-migration-agent')
}

try {
    $done = @{}
    foreach ($t in $expanded) {
        $dir = Get-TargetDir $t
        if ($done.ContainsKey($dir)) { continue }
        $done[$dir] = $true
        foreach ($name in $skillNames) {
            $dest = Join-Path $dir $name
            if ($Uninstall) {
                if (Test-Path $dest) { Remove-Item $dest -Recurse -Force; Write-Host "Removed $dest" } else { Write-Host "Not installed at $dest" }
                continue
            }
            $src = Join-Path $skillsRoot $name
            if (-not (Test-Path (Join-Path $src 'SKILL.md'))) { Write-Warning "SKILL.md not found for $name."; continue }
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            if (Test-Path $dest) { Write-Host "Updating existing install at $dest"; Remove-Item $dest -Recurse -Force }
            Copy-Item -Path $src -Destination $dest -Recurse
            Write-Host "Installed $name for $t -> $dest"
        }
    }
    if (-not $Uninstall) {
        Write-Host ''
        Write-Host 'Done. Restart your AI tool (or start a new session), then try:'
        Write-Host '  "Build a toolkit module that turns off all flows in the Invoicing solution before a release, with a test run first."'
        Write-Host '  "How many contacts in my dev environment have no email address?"'
    }
}
finally {
    if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
