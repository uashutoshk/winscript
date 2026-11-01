<#
.SYNOPSIS
    USB Storage module. Toggles removable storage access via Group Policy
    using LGPO.exe (.pol files). Supports dry-run mode.
#>

function Get-DenyUsbStorageTab {
    $tab = New-Object System.Windows.Controls.TabItem
    $tab.Header = "USB Storage"

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = 10

    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = "Blocks or allows read/write access to all removable storage devices (USB drives, SD cards, etc.) via Group Policy (Removable Storage Devices: Deny All)."
    $desc.TextWrapping = 'Wrap'
    $desc.Margin = "0,0,0,10"
    $panel.Children.Add($desc) | Out-Null

    $statusRow = New-Object System.Windows.Controls.StackPanel
    $statusRow.Orientation = 'Horizontal'
    $statusRow.Margin = "0,0,0,10"

    $statusText = New-Object System.Windows.Controls.TextBlock
    $statusText.FontWeight = 'Bold'
    $statusText.VerticalAlignment = 'Center'
    $statusRow.Children.Add($statusText) | Out-Null

    $btnRefresh = New-Object System.Windows.Controls.Button
    $btnRefresh.Content = "Refresh"
    $btnRefresh.Margin = "12,0,0,0"
    $btnRefresh.Padding = "8,2,8,2"
    $statusRow.Children.Add($btnRefresh) | Out-Null

    $panel.Children.Add($statusRow) | Out-Null

    $dryRunCheck = New-Object System.Windows.Controls.CheckBox
    $dryRunCheck.Content = "Dry run (show what would change, do not apply)"
    $dryRunCheck.IsChecked = $true
    $dryRunCheck.Margin = "0,0,0,10"
    $panel.Children.Add($dryRunCheck) | Out-Null

    $updateStatusLabel = {
        $isBlocked = $false

        # Check LGPO / registry state for Deny_All
        if (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices") {
            $val = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices" -Name "Deny_All" -ErrorAction SilentlyContinue).Deny_All
            if ($val -eq 1) { $isBlocked = $true }
        }

        if ($isBlocked) {
            $statusText.Text = "Current state: BLOCKED"
            $statusText.Foreground = $Global:CatBrush.Red
        }
        else {
            $statusText.Text = "Current state: ALLOWED"
            $statusText.Foreground = $Global:CatBrush.Green
        }
    }.GetNewClosure()

    & $updateStatusLabel
    $btnRefresh.Add_Click({ & $updateStatusLabel }.GetNewClosure())

    $btnRow = New-Object System.Windows.Controls.StackPanel
    $btnRow.Orientation = 'Horizontal'

    $btnBlock = New-Object System.Windows.Controls.Button
    $btnBlock.Content = "Block USB Storage"

    $btnAllow = New-Object System.Windows.Controls.Button
    $btnAllow.Content = "Allow USB Storage"

    $btnRow.Children.Add($btnBlock) | Out-Null
    $btnRow.Children.Add($btnAllow) | Out-Null
    $panel.Children.Add($btnRow) | Out-Null

    $note = New-Object System.Windows.Controls.TextBlock
    $note.Text = "Devices already plugged in may need to be unplugged/replugged, or the machine restarted, for the change to fully take effect. Revert manually via gpedit.msc if needed."
    $note.TextWrapping = 'Wrap'
    $note.Foreground = $Global:CatBrush.Subtext0
    $note.Margin = "0,10,0,0"
    $panel.Children.Add($note) | Out-Null

    $applyUsbPolicy = {
        param($Action, $IsDryRun)
        $btnBlock.IsEnabled = $false
        $btnAllow.IsEnabled = $false
        $btnRefresh.IsEnabled = $false

        $moduleName = "usb-storage"
        $polPath = Get-PolicyPath -Module $moduleName -Action $Action

        Write-Log "Applying USB Storage policy: $Action" "Info"

        Start-BackgroundTask -DotSourceFiles @("$PSScriptRoot/lgpo-helpers.ps1") -Work {
            param($SyncHash, $Action, $PolPath, $IsDryRun)
            try {
                $result = Invoke-LgpoApply -Scope "Machine" -PolPath $PolPath -DryRun:$IsDryRun
                if (-not $IsDryRun -and $result) {
                    Invoke-Gpupdate -DryRun:$IsDryRun
                }
            }
            catch {
                $SyncHash.LogQueue.Enqueue("[ERROR] USB policy $Action failed: $($_.Exception.Message)")
            }
        } -OnDone {
            & $updateStatusLabel
            $btnBlock.IsEnabled = $true
            $btnAllow.IsEnabled = $true
            $btnRefresh.IsEnabled = $true
        }.GetNewClosure()
    }.GetNewClosure()

    $btnBlock.Add_Click({
        $isDryRun = [bool]$dryRunCheck.IsChecked
        & $applyUsbPolicy "block" $isDryRun
    }.GetNewClosure())

    $btnAllow.Add_Click({
        $isDryRun = [bool]$dryRunCheck.IsChecked
        & $applyUsbPolicy "allow" $isDryRun
    }.GetNewClosure())

    $tab.Content = $panel
    return $tab
}
