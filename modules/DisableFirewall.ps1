<#
.SYNOPSIS
    Firewall module. Toggles Windows Firewall for Domain, Private, and Public
    profiles via Group Policy using LGPO.exe (.pol files). Supports dry-run mode.
#>

function Get-FirewallTab {
    $tab = New-Object System.Windows.Controls.TabItem
    $tab.Header = "Firewall"

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = 10

    $warn = New-Object System.Windows.Controls.TextBlock
    $warn.Text = "Disabling the firewall removes a layer of protection against network-based attacks. Only do this on trusted networks, and re-enable when done. Revert manually via gpedit.msc if needed."
    $warn.TextWrapping = 'Wrap'
    $warn.Foreground = $Global:CatBrush.Red
    $warn.FontWeight = 'Bold'
    $warn.Margin = "0,0,0,10"
    $panel.Children.Add($warn) | Out-Null

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
    $dryRunCheck.IsChecked = $false
    $dryRunCheck.Visibility = 'Collapsed'
    $dryRunCheck.Margin = "0,0,0,10"
    $panel.Children.Add($dryRunCheck) | Out-Null

    $updateStatusLabel = {
        try {
            $profiles = Get-NetFirewallProfile -Profile Domain, Private, Public -ErrorAction Stop
            $lines = foreach ($p in $profiles) { "$($p.Name): $(if ($p.Enabled) { 'ON' } else { 'OFF' })" }
            $statusText.Text = "Current state -- " + ($lines -join "   |   ")
            $allOn = $profiles | Where-Object { -not $_.Enabled }
            if ($allOn) {
                $statusText.Foreground = $Global:CatBrush.Red
            }
            else {
                $statusText.Foreground = $Global:CatBrush.Green
            }
        }
        catch {
            $statusText.Text = "Could not read firewall state: $($_.Exception.Message)"
            $statusText.Foreground = $Global:CatBrush.Subtext0
        }
    }.GetNewClosure()

    & $updateStatusLabel
    $btnRefresh.Add_Click({ & $updateStatusLabel }.GetNewClosure())

    $btnRow = New-Object System.Windows.Controls.StackPanel
    $btnRow.Orientation = 'Horizontal'

    $btnDisable = New-Object System.Windows.Controls.Button
    $btnDisable.Content = "Turn Off Firewall (All Profiles)"

    $btnEnable = New-Object System.Windows.Controls.Button
    $btnEnable.Content = "Turn On Firewall (All Profiles)"

    $btnRow.Children.Add($btnDisable) | Out-Null
    $btnRow.Children.Add($btnEnable) | Out-Null
    $panel.Children.Add($btnRow) | Out-Null

    $applyFirewallPolicy = {
        param($Action, $IsDryRun)
        $btnDisable.IsEnabled = $false
        $btnEnable.IsEnabled = $false
        $btnRefresh.IsEnabled = $false

        $moduleName = "firewall"
        $polPath = Get-PolicyPath -Module $moduleName -Action $Action

        Write-Log "Applying Firewall policy: $Action" "Info"

        Start-BackgroundTask -Work {
            param($SyncHash, $Action, $PolPath, $IsDryRun)
            try {
                $result = Invoke-LgpoApply -Scope "Machine" -PolPath $PolPath -DryRun:$IsDryRun
                if (-not $IsDryRun -and $result) {
                    Invoke-Gpupdate -DryRun:$IsDryRun
                }
            }
            catch {
                $SyncHash.LogQueue.Enqueue("[ERROR] Firewall policy $Action failed: $($_.Exception.Message)")
            }
        } -OnDone {
            & $updateStatusLabel
            $btnDisable.IsEnabled = $true
            $btnEnable.IsEnabled = $true
            $btnRefresh.IsEnabled = $true
        }.GetNewClosure()
    }.GetNewClosure()

    $btnDisable.Add_Click({
        $confirmMsg = "This will completely disable Windows Firewall for Domain, Private, and Public network profiles. Continue?"
        $result = [System.Windows.MessageBox]::Show($confirmMsg, "Confirm Firewall Change", 'YesNo', 'Warning')
        if ($result -ne 'Yes') { return }
        $isDryRun = [bool]$dryRunCheck.IsChecked
        & $applyFirewallPolicy "off" $isDryRun
    }.GetNewClosure())

    $btnEnable.Add_Click({
        $btnDisable.IsEnabled = $false; $btnEnable.IsEnabled = $false; $btnRefresh.IsEnabled = $false
        Write-Log "Enabling firewall for all profiles..."
        $isDryRun = [bool]$dryRunCheck.IsChecked
        & $applyFirewallPolicy "on" $isDryRun
    }.GetNewClosure())

    $tab.Content = $panel
    return $tab
}
