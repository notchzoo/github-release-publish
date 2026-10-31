<#
.SYNOPSIS
    Read-only GitHub release state probe.

.DESCRIPTION
    Inspects the current project and prints key=value lines describing:
    whether it is a git repository, the current branch, the GitHub remote slug
    (owner/repo), dirty file count, local tags, the latest local tag, and
    suggested next version numbers. With -CheckRemote it also queries the
    GitHub API for repository visibility, default branch and releases, using
    credentials from the configured git credential helper (never printed).

    The script never writes, commits, tags or pushes anything.

.PARAMETER Path
    Project directory to inspect. Default: current directory.

.PARAMETER CheckRemote
    Also call the GitHub API (requires stored credentials).

.EXAMPLE
    ./detect-state.ps1 -Path .

.EXAMPLE
    ./detect-state.ps1 -Path . -CheckRemote
#>
param(
    [string]$Path = ".",
    [switch]$CheckRemote
)

# Native commands legitimately exit non-zero here, so do not stop on stderr.
$ErrorActionPreference = "Continue"

function Write-Kv([string]$Key, $Value) { "{0}={1}" -f $Key, $Value }

$script:lastGitError = ""
function Invoke-Git {
    param([string[]]$Arguments)
    $output = @(& git @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $script:lastGitError = (($output | ForEach-Object { "$_" }) -join " ").Trim()
        return @()
    }
    return @($output)
}

$root = (Resolve-Path -LiteralPath $Path).Path
Write-Kv "path" $root

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Kv "state" "no-git-binary"
    return
}

Push-Location $root
try {
    $inside = @(Invoke-Git @("rev-parse", "--is-inside-work-tree"))
    if (($inside -join "") -ne "true") {
        Write-Kv "state" "A-no-repository"
        Write-Kv "next" "git init -b main; add .gitignore; commit; create repo; push"
        if ($script:lastGitError) {
            if ($script:lastGitError -match 'dubious ownership') {
                Write-Kv "hint" "git refuses this path (dubious ownership); add it to safe.directory or fix ownership"
            }
            Write-Kv "git_error" $script:lastGitError
        }
        return
    }

    Write-Kv "repo_root" ((Invoke-Git @("rev-parse", "--show-toplevel")) -join "")
    $branch = ((Invoke-Git @("rev-parse", "--abbrev-ref", "HEAD")) -join "")
    Write-Kv "branch" $branch

    $dirty = @(Invoke-Git @("status", "--porcelain"))
    Write-Kv "dirty_files" $dirty.Count

    $remotes = @(Invoke-Git @("remote", "-v"))
    Write-Kv "remotes" $(if ($remotes.Count -gt 0) { ($remotes -join " | ") } else { "none" })

    $originUrl = ((Invoke-Git @("remote", "get-url", "origin")) -join "")
    $slug = "none"
    if ($originUrl) {
        Write-Kv "origin_url" $originUrl
        if ($originUrl -match 'github\.com[:/]+([^/]+)/([^/]+?)(\.git)?$') {
            $slug = "{0}/{1}" -f $Matches[1], $Matches[2]
        }
    }
    Write-Kv "slug" $slug

    $tags = @(Invoke-Git @("tag", "--sort=-v:refname"))
    Write-Kv "tag_count" $tags.Count
    Write-Kv "latest_tag" $(if ($tags.Count -gt 0) { $tags[0] } else { "none" })

    if ($tags.Count -gt 0 -and $tags[0] -match '^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?$') {
        $major = [int]$Matches[1]
        $minor = if ($Matches[2]) { [int]$Matches[2] } else { 0 }
        $patch = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
        Write-Kv "suggest_patch" ("v{0}.{1}.{2}" -f $major, $minor, ($patch + 1))
        Write-Kv "suggest_minor" ("v{0}.{1}.0" -f $major, ($minor + 1))
        Write-Kv "suggest_major" ("v{0}.0.0" -f ($major + 1))
    }
    else {
        Write-Kv "suggest_first" "v0.1.0"
    }

    if ($slug -eq "none") {
        Write-Kv "state" "B-no-github-remote"
        Write-Kv "next" "create repository on GitHub, then git remote add origin and push"
    }
    elseif ($tags.Count -gt 0) {
        Write-Kv "state" "C-released"
        Write-Kv "next" "ASK user: publish a new version, or overwrite the current latest version"
    }
    else {
        Write-Kv "state" "C-not-yet-released"
        Write-Kv "next" "publish the first version, no overwrite question needed"
    }

    if ($CheckRemote -and $slug -ne "none") {
        $env:GIT_TERMINAL_PROMPT = "0"
        $cred = @("protocol=https`nhost=github.com`n`n" | & git credential fill 2>$null) -join "`n"
        if ($cred -match '(?m)^password=(.+)$') {
            $token = $Matches[1].Trim()
            $headers = @{
                Authorization = "token $token"
                Accept        = "application/vnd.github+json"
                "User-Agent"  = "dsh-detect-state"
            }
            try {
                $repo = Invoke-RestMethod -Uri "https://api.github.com/repos/$slug" -Headers $headers -Method Get
                Write-Kv "repo_private" $repo.private
                Write-Kv "repo_default_branch" $repo.default_branch
                $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$slug/releases" -Headers $headers -Method Get
                $rels = @($response | ForEach-Object { $_ })
                Write-Kv "release_count" $rels.Count
                if ($rels.Count -gt 0) {
                    Write-Kv "latest_release" $rels[0].tag_name
                    Write-Kv "latest_release_draft" $rels[0].draft
                    Write-Kv "latest_release_url" $rels[0].html_url
                }
            }
            catch {
                Write-Kv "remote_error" $_.Exception.Message
            }
        }
        else {
            Write-Kv "remote_error" "no stored credential; run gh auth login or configure credential.helper"
        }
    }
}
finally {
    Pop-Location
}