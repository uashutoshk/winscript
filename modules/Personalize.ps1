<#
.SYNOPSIS
    Personalize module. Enforces or reverts wallpaper and lock screen policies
    via Group Policy using LGPO.exe (.pol files). Supports dry-run mode.
#>

function Get-DesktopCleanupTab {
    $tab = New-Object System.Windows.Controls.TabItem
    $tab.Header = "Desktop Cleanup"

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = 10

    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = "Enforce or revert wallpaper and lock screen Group Policies."
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
        $noWall = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop" -Name "NoChangingWallPaper" -ErrorAction SilentlyContinue).NoChangingWallPaper
        $noLock = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoChangingLockScreen" -ErrorAction SilentlyContinue).NoChangingLockScreen
        $wallPolicy = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "Wallpaper" -ErrorAction SilentlyContinue).Wallpaper

        if ($noWall -eq 1 -or $noLock -eq 1 -or $wallPolicy) {
            $statusText.Text = "Current state: POLICIES ENFORCED (Wallpaper/Lock Screen Locked)"
            $statusText.Foreground = $Cat.Red
        }
        else {
            $statusText.Text = "Current state: ALLOWED (Customization Unrestricted)"
            $statusText.Foreground = $Cat.Green
        }
    }.GetNewClosure()

    & $updateStatusLabel
    $btnRefresh.Add_Click({ & $updateStatusLabel }.GetNewClosure())

    $btnRow = New-Object System.Windows.Controls.StackPanel
    $btnRow.Orientation = 'Horizontal'
    $btnRow.Margin = "0,0,0,10"

    $btnApply = New-Object System.Windows.Controls.Button
    $btnApply.Content = "Apply Policies (Enforce Wallpaper + Lock Screen)"

    $btnRevert = New-Object System.Windows.Controls.Button
    $btnRevert.Content = "Revert Policies (Allow Changes)"

    $btnRow.Children.Add($btnApply) | Out-Null
    $btnRow.Children.Add($btnRevert) | Out-Null
    $panel.Children.Add($btnRow) | Out-Null

    $applyPersonalizePolicy = {
        param($IsDryRun)
        $btnApply.IsEnabled = $false
        $btnRevert.IsEnabled = $false
        $btnRefresh.IsEnabled = $false

        Write-Log "Applying Personalize policies..." "Info"

        Start-BackgroundTask -Work {
            param($SyncHash, $IsDryRun)
            try {
                $userPol = Get-PolicyPath -Module "personalize" -Action "enforce-user"
                $machinePol = Get-PolicyPath -Module "personalize" -Action "enforce-machine"

                $r1 = Invoke-LgpoApply -Scope "User" -PolPath $userPol -DryRun:$IsDryRun
                $r2 = Invoke-LgpoApply -Scope "Machine" -PolPath $machinePol -DryRun:$IsDryRun

                if (-not $IsDryRun -and $r1 -and $r2) {
                    Invoke-Gpupdate -DryRun:$IsDryRun
                }
            }
            catch {
                $SyncHash.LogQueue.Enqueue("[ERROR] Personalize apply failed: $($_.Exception.Message)")
            }
        } -OnDone {
            & $updateStatusLabel
            $btnApply.IsEnabled = $true
            $btnRevert.IsEnabled = $true
            $btnRefresh.IsEnabled = $true
        }.GetNewClosure()
    }.GetNewClosure()

    $revertPersonalizePolicy = {
        param($IsDryRun)
        $btnApply.IsEnabled = $false
        $btnRevert.IsEnabled = $false
        $btnRefresh.IsEnabled = $false

        Write-Log "Reverting Personalize policies..." "Info"

        Start-BackgroundTask -Work {
            param($SyncHash, $IsDryRun)
            try {
                $userPol = Get-PolicyPath -Module "personalize" -Action "revert-user"
                $machinePol = Get-PolicyPath -Module "personalize" -Action "revert-machine"

                $r1 = Invoke-LgpoApply -Scope "User" -PolPath $userPol -DryRun:$IsDryRun
                $r2 = Invoke-LgpoApply -Scope "Machine" -PolPath $machinePol -DryRun:$IsDryRun

                if (-not $IsDryRun -and $r1 -and $r2) {
                    Invoke-Gpupdate -DryRun:$IsDryRun
                }
            }
            catch {
                $SyncHash.LogQueue.Enqueue("[ERROR] Personalize revert failed: $($_.Exception.Message)")
            }
        } -OnDone {
            & $updateStatusLabel
            $btnApply.IsEnabled = $true
            $btnRevert.IsEnabled = $true
            $btnRefresh.IsEnabled = $true
        }.GetNewClosure()
    }.GetNewClosure()

    $btnApply.Add_Click({
        $isDryRun = [bool]$dryRunCheck.IsChecked
        & $applyPersonalizePolicy $isDryRun
    }.GetNewClosure())

    $btnRevert.Add_Click({
        $isDryRun = [bool]$dryRunCheck.IsChecked
        & $revertPersonalizePolicy $isDryRun
    }.GetNewClosure())

    $tab.Content = $panel
    return $tab
}
