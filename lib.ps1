# ---------------------------------------------------------------------------
# Shared state used by every module (background tasks + thread-safe logging)
# ---------------------------------------------------------------------------
$Global:SyncHash = [hashtable]::Synchronized(@{
    LogQueue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
})

function Global:Write-Log {
    param([string]$Message, [string]$Level = "Info")
    $stamp = Get-Date -Format "HH:mm:ss"
    $levelTag = switch ($Level) {
        "Error" { "[ERROR]" }
        "Warn"  { "[WARN] " }
        "Info"  { "[INFO] " }
        default { "[INFO] " }
    }
    $Global:SyncHash.LogQueue.Enqueue("[$stamp]$levelTag $Message")
}

# Runs a scriptblock on a background runspace so the GUI never freezes.
# lgpo-helpers.ps1 is dot-sourced inside the background runspace so that
# Invoke-LgpoApply and Invoke-Gpupdate are available there.
function Global:Start-BackgroundTask {
    param(
        [Parameter(Mandatory)][scriptblock]$Work,
        [object[]]$ArgumentList = @(),
        [scriptblock]$OnDone
    )

    # Ensure LGPO helpers are available inside the background runspace
    $helperPath = Join-Path $PSScriptRoot 'lgpo-helpers.ps1'
    $workText = $Work.ToString()
    $wrappedWork = [scriptblock]::Create(". `"$helperPath`"`n" + $workText)

    $ps = [powershell]::Create()
    $null = $ps.AddScript($wrappedWork).AddArgument($Global:SyncHash)
    foreach ($extraArg in $ArgumentList) { $null = $ps.AddArgument($extraArg) }

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.Open()
    $ps.Runspace = $rs
    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $timer.Tag = [pscustomobject]@{
        Ps     = $ps
        Rs     = $rs
        Handle = $handle
        Queue  = $Global:SyncHash.LogQueue
        OnDone = $OnDone
    }

    $timer.Add_Tick({
        param($timerRef, $timerEventArgs)
        $st = $timerRef.Tag
        if ($null -eq $st)               { $timerRef.Stop(); return }
        if (-not $st.Handle.IsCompleted) { return }

        $timerRef.Stop()
        try   { $null = $st.Ps.EndInvoke($st.Handle) }
        catch { $st.Queue.Enqueue("[ERROR] $($_.Exception.Message)") }

        if ($st.Ps.Streams.Error.Count -gt 0) {
            foreach ($err in $st.Ps.Streams.Error) {
                $st.Queue.Enqueue("[ERROR] $err")
            }
        }

        try { $st.Rs.Close()   } catch {}
        try { $st.Ps.Dispose() } catch {}

        if ($st.OnDone) {
            try { & $st.OnDone }
            catch { $st.Queue.Enqueue("[ERROR] OnDone: $($_.Exception.Message)") }
        }
    })
    $timer.Start()
}
