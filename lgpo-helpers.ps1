# ---------------------------------------------------------------------------
# LGPO helper functions. All policy changes go through LGPO.exe (.pol files).
# No direct registry edits are made by this tool.
# ---------------------------------------------------------------------------

$Global:LgpoExe = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "LGPO.exe"
$Global:PolicyRepoRoot = "config/policies"

function Global:Get-PolicyPath {
    param([string]$Module, [string]$Action)
    # Prefer local copy; fall back to network download at runtime
    $local = Join-Path $Global:LocalRepoPath (Join-Path $Global:PolicyRepoRoot (Join-Path $Module "$Action.pol"))
    if ($local -and (Test-Path $local)) { return $local }
    return "$($Global:BaseRepoUrl)/$($Global:PolicyRepoRoot)/$Module/$Action.pol"
}

function Global:Test-LgpoAvailable {
    if (-not (Test-Path $Global:LgpoExe)) {
        Write-Log "LGPO.exe not found at $($Global:LgpoExe)" "Error"
        return $false
    }
    return $true
}

# Applies a .pol file via LGPO.exe. $Scope is "Machine" (/m) or "User" (/u).
# Returns $true on success, $false on failure.
function Global:Invoke-LgpoApply {
    param([string]$Scope, [string]$PolPath, [switch]$DryRun)

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would run: LGPO.exe /$Scope `"$PolPath`"" "Info"
        Write-Log "[DRY-RUN] Policy file: $PolPath" "Info"
        return $true
    }

    if (-not (Test-LgpoAvailable)) { return $false }

    $arg = if ($Scope -eq "Machine") { "/m" } else { "/u" }
    $proc = Start-Process -FilePath $Global:LgpoExe -ArgumentList "$arg `"$PolPath`" /q" -Wait -NoNewWindow -PassThru
    if ($proc.ExitCode -eq 0) {
        Write-Log "LGPO applied ($Scope): $(Split-Path $PolPath -Leaf)" "Info"
        return $true
    }
    else {
        Write-Log "LGPO failed (exit $($proc.ExitCode)) for $PolPath" "Error"
        return $false
    }
}

# Refreshes Group Policy so changes take effect sooner.
function Global:Invoke-Gpupdate {
    param([switch]$DryRun)

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would run: gpupdate /force" "Info"
        return $true
    }

    Write-Log "Refreshing Group Policy (gpupdate /force)..." "Info"
    $proc = Start-Process -FilePath "gpupdate" -ArgumentList "/force" -Wait -NoNewWindow -PassThru
    if ($proc.ExitCode -eq 0) {
        Write-Log "Group Policy refreshed." "Info"
        return $true
    }
    Write-Log "gpupdate exited with code $($proc.ExitCode). Some settings may require sign-out/reboot." "Warn"
    return $false
}
