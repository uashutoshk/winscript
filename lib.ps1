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
