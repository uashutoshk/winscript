<#
.SYNOPSIS
    Debloat module. Removes selected in-box Windows apps.
    App removal is not a Group Policy setting, so this uses Remove-AppxPackage.
    Supports dry-run mode.
#>

function Get-DebloatTab {
    $tab = New-Object System.Windows.Controls.TabItem
    $tab.Header = "Debloat"

    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'

    $mainPanel = New-Object System.Windows.Controls.StackPanel
    $mainPanel.Margin = 10

    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = "Remove unwanted pre-installed Windows apps (AppX packages)."
    $desc.TextWrapping = 'Wrap'
    $desc.Margin = "0,0,0,10"
    $mainPanel.Children.Add($desc) | Out-Null

    # --- Toolbar: Select All / Select None ---------------------------------
    $toolbar = New-Object System.Windows.Controls.StackPanel
    $toolbar.Orientation = 'Horizontal'

    $btnAll = New-Object System.Windows.Controls.Button
    $btnAll.Content = "Select All"
    $btnNone = New-Object System.Windows.Controls.Button
    $btnNone.Content = "Select None"

    $toolbar.Children.Add($btnAll)  | Out-Null
    $toolbar.Children.Add($btnNone) | Out-Null
    $mainPanel.Children.Add($toolbar) | Out-Null

    $restoreCheck = New-Object System.Windows.Controls.CheckBox
    $restoreCheck.Content = "Create a System Restore Point first (recommended)"
    $restoreCheck.IsChecked = $true
    $restoreCheck.Margin = "4,10,4,10"
    $mainPanel.Children.Add($restoreCheck) | Out-Null

    # --- Dry run toggle ------------------------------------------------------
    $dryRunCheck = New-Object System.Windows.Controls.CheckBox
    $dryRunCheck.Content = "Dry run (show what would be removed, do not change anything)"
    $dryRunCheck.IsChecked = $false
    $dryRunCheck.Visibility = 'Collapsed'
    $dryRunCheck.Margin = "4,4,4,10"
    $mainPanel.Children.Add($dryRunCheck) | Out-Null

    # --- App checklist, loaded from config/debloat-list.json -----------------
    $appCheckboxes = New-Object System.Collections.Generic.List[object]

    try {
        $appList = Invoke-RestMethod -Uri "$BaseRepoUrl/config/debloat-list.json" -UseBasicParsing
    }
    catch {
        Write-Log "Failed to load debloat-list.json: $($_.Exception.Message)" "Error"
        $appList = @()
    }

    foreach ($app in $appList) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $app.Name
        $cb.Tag = $app.Package
        $cb.IsChecked = [bool]$app.Checked
        $mainPanel.Children.Add($cb) | Out-Null
        $appCheckboxes.Add($cb) | Out-Null
    }

    $btnAll.Add_Click({ foreach ($c in $appCheckboxes) { $c.IsChecked = $true } }.GetNewClosure())
    $btnNone.Add_Click({ foreach ($c in $appCheckboxes) { $c.IsChecked = $false } }.GetNewClosure())

    # --- Remove button -------------------------------------------------------
    $btnRemove = New-Object System.Windows.Controls.Button
    $btnRemove.Content = "Remove Selected Apps"
    $btnRemove.Margin = "4,16,4,4"
    $btnRemove.HorizontalAlignment = 'Left'
    $mainPanel.Children.Add($btnRemove) | Out-Null

    $btnRemove.Add_Click({
        $selected = @($appCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
        if ($selected.Count -eq 0) {
            Write-Log "No apps selected." "Warn"
            return
        }

        $makeRestorePoint = [bool]$restoreCheck.IsChecked
        $isDryRun = [bool]$dryRunCheck.IsChecked
        $btnRemove.IsEnabled = $false
        Write-Log "$([string]::Join(", ", $selected))" "Info"
        if ($isDryRun) {
            Write-Log "DRY RUN enabled -- no changes will be made." "Info"
        }

        Start-BackgroundTask -ArgumentList @($selected, $makeRestorePoint, $isDryRun) -Work {
            param($SyncHash, $Packages, $MakeRestorePoint, $IsDryRun)

            if ($MakeRestorePoint -and -not $IsDryRun) {
                try {
                    $SyncHash.LogQueue.Enqueue("Creating system restore point...")
                    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
                    Checkpoint-Computer -Description "WinScript Debloat" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
                    $SyncHash.LogQueue.Enqueue("Restore point created.")
                }
                catch {
                    $SyncHash.LogQueue.Enqueue("[WARN] Could not create restore point: $($_.Exception.Message)")
                }
            }

            foreach ($pkg in $Packages) {
                try {
                    $installed = Get-AppxPackage -AllUsers -Name $pkg -ErrorAction SilentlyContinue
                    if ($installed) {
                        if ($IsDryRun) {
                            $SyncHash.LogQueue.Enqueue("[DRY-RUN] Would remove: $pkg")
                        }
                        else {
                            $installed | Remove-AppxPackage -AllUsers -ErrorAction Stop
                            $SyncHash.LogQueue.Enqueue("Removed: $pkg")
                        }

                        # Also remove the provisioned package so it doesn't come back for new user profiles
                        if (-not $IsDryRun) {
                            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                                Where-Object { $_.DisplayName -eq $pkg } |
                                ForEach-Object {
                                    Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
                                }
                        }
                    }
                    else {
                        $SyncHash.LogQueue.Enqueue("Not installed, skipping: $pkg")
                    }
                }
                catch {
                    $SyncHash.LogQueue.Enqueue("[ERROR] Failed to remove $pkg`: $($_.Exception.Message)")
                }
            }

            if ($IsDryRun) {
                $SyncHash.LogQueue.Enqueue("DRY RUN finished. No changes were made.")
            }
            else {
                $SyncHash.LogQueue.Enqueue("Debloat run finished.")
            }
        } -OnDone {
            $btnRemove.IsEnabled = $true
        }.GetNewClosure()
    }.GetNewClosure())

    $scroll.Content = $mainPanel
    $tab.Content = $scroll
    return $tab
}
