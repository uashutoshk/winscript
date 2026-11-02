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
# lgpo-helpers.ps1 is dot-sourced inside the background runspace (after the
# param block) so Invoke-LgpoApply and Invoke-Gpupdate are available there.
function Global:Start-BackgroundTask {
    param(
        [Parameter(Mandatory)][scriptblock]$Work,
        [object[]]$ArgumentList = @(),
        [scriptblock]$OnDone
    )

    $helperPath = Join-Path $PSScriptRoot 'lgpo-helpers.ps1'

    # Insert dot-source after param(...) block so param stays first statement
    $workStr = $Work.ToString()
    $paramKeywordIdx = $workStr.IndexOf('param')
    if ($paramKeywordIdx -ge 0) {
        $parenIdx = $workStr.IndexOf('(', $paramKeywordIdx)
        if ($parenIdx -ge 0) {
            $depth = 1
            $i = $parenIdx + 1
            while ($i -lt $workStr.Length -and $depth -gt 0) {
                $c = $workStr[$i]
                if ($c -eq '(') { $depth++ }
                elseif ($c -eq ')') { $depth-- }
                $i++
            }
            $paramEnd = $i
            $wrappedStr = $workStr.Substring(0, $paramEnd) + "`n. `"$helperPath`"" + $workStr.Substring($paramEnd)
            $wrappedWork = [scriptblock]::Create($wrappedStr)
        }
        else {
            $wrappedWork = $Work
        }
    }
    else {
        $wrappedWork = $Work
    }

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
