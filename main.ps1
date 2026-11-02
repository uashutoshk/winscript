<#
.SYNOPSIS
    Main entry point. Downloaded and executed by bootstrap.ps1 via Invoke-Expression.
    Builds the WPF GUI shell, then pulls tab modules from manifest.json.
    All policy changes go through LGPO.exe (.pol files downloaded at runtime).
    No direct registry edits are made by this tool. Fully self-contained for
    remote execution (no dependency on $PSScriptRoot or local files).
#>

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

if (-not $Global:BaseRepoUrl) {
    $Global:BaseRepoUrl = "https://raw.githubusercontent.com/uashutoshk/winscript/main"
}

# ---------------------------------------------------------------------------
# Download LGPO.exe to temp folder (works over internet, no local file needed)
# ---------------------------------------------------------------------------
$Global:LgpoDir = Join-Path $env:TEMP "WinScript"
if (-not (Test-Path $Global:LgpoDir)) { $null = New-Item -ItemType Directory -Path $Global:LgpoDir -Force }
$Global:LgpoExe = Join-Path $Global:LgpoDir "LGPO.exe"
if (-not (Test-Path $Global:LgpoExe)) {
    Write-Host "Downloading LGPO.exe..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri "$BaseRepoUrl/LGPO.exe" -OutFile $Global:LgpoExe -UseBasicParsing
    } catch {
        Write-Host "Failed to download LGPO.exe: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ---------------------------------------------------------------------------
# Download and inline-execute lib.ps1 (SyncHash, Write-Log, Start-BackgroundTask)
# ---------------------------------------------------------------------------
$Global:LibScript = Invoke-RestMethod -Uri "$BaseRepoUrl/lib.ps1" -UseBasicParsing
Invoke-Expression $Global:LibScript

# ---------------------------------------------------------------------------
# Download lgpo-helpers.ps1 content for injection into background runspaces
# ---------------------------------------------------------------------------
$Global:LgpoHelperScript = Invoke-RestMethod -Uri "$BaseRepoUrl/lgpo-helpers.ps1" -UseBasicParsing
# Fix LGPO.exe path inside the helper script to point to our temp copy
$Global:LgpoHelperScript = $Global:LgpoHelperScript -replace 'Join-Path \(Split-Path -Parent \$MyInvocation\.MyCommand\.Path\) "LGPO.exe"', '"$Global:LgpoExe"'
Invoke-Expression $Global:LgpoHelperScript

# ---------------------------------------------------------------------------
# Local-first repo loader (network fallback)
# ---------------------------------------------------------------------------
if (-not $Global:LocalRepoPath) {
    if ($env:WINTOOL_LOCAL_REPO -and (Test-Path (Join-Path $env:WINTOOL_LOCAL_REPO 'manifest.json'))) {
        $Global:LocalRepoPath = $env:WINTOOL_LOCAL_REPO
    }
    elseif ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'manifest.json'))) {
        $Global:LocalRepoPath = $PSScriptRoot
    }
    elseif (Test-Path (Join-Path (Get-Location).Path 'manifest.json')) {
        $Global:LocalRepoPath = (Get-Location).Path
    }
    if ($Global:LocalRepoPath) {
        Write-Host "[local] Using repo at $($Global:LocalRepoPath)" -ForegroundColor Cyan
    }
}

function Global:Get-RepoText {
    param([Parameter(Mandatory)][string]$RelativePath)

    if ($Global:LocalRepoPath) {
        $local = Join-Path $Global:LocalRepoPath $RelativePath
        if (Test-Path $local) {
            return Get-Content -Path $local -Raw -ErrorAction Stop
        }
        Write-Host "[local] '$RelativePath' not found under $($Global:LocalRepoPath); falling back to network." -ForegroundColor Yellow
    }
    $resp = Invoke-WebRequest -Uri "$BaseRepoUrl/$RelativePath" -UseBasicParsing
    return [string]$resp.Content
}

function Global:Get-RepoJson {
    param([Parameter(Mandatory)][string]$RelativePath)
    $text = Get-RepoText -RelativePath $RelativePath
    return ($text | ConvertFrom-Json)
}

# ---------------------------------------------------------------------------
# Catppuccin Mocha colors (programmatic brushes)
# ---------------------------------------------------------------------------
$Cat = @{
    Base     = "30,30,46"
    Mantle   = "24,24,37"
    Crust    = "17,17,27"
    Surface0 = "49,50,68"
    Surface1 = "69,71,90"
    Surface2 = "88,91,112"
    Overlay0 = "108,112,134"
    Overlay1 = "127,132,156"
    Overlay2 = "147,153,178"
    Subtext0 = "166,173,200"
    Subtext1 = "186,194,222"
    Text     = "205,214,244"
    Rosewater= "245,224,220"
    Flamingo = "242,205,205"
    Pink     = "245,194,231"
    Mauve    = "203,166,247"
    Red      = "243,139,168"
    Maroon   = "235,160,172"
    Peach    = "250,179,135"
    Yellow   = "249,226,175"
    Green    = "166,227,161"
    Teal     = "148,226,213"
    Sky      = "137,220,235"
    Sapphire = "116,199,236"
    Blue     = "137,180,250"
    Lavender = "180,190,254"
}

function Global:CatColor {
    param([string]$Rgb)
    $parts = $Rgb.Split(',')
    [System.Windows.Media.Color]::FromRgb([byte]$parts[0], [byte]$parts[1], [byte]$parts[2])
}

$Global:CatBrush = @{}
foreach ($key in $Cat.Keys) {
    $Global:CatBrush[$key] = New-Object System.Windows.Media.SolidColorBrush (CatColor $Cat[$key])
}

# ---------------------------------------------------------------------------
# Window skeleton (XAML) -- Catppuccin Mocha theme
# Inline hex strings directly in XAML attributes (no variable interpolation).
# ---------------------------------------------------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinScript - NMC-IT" Height="600" Width="1000"
        WindowStartupLocation="CenterScreen"
        Background="#FF1e1e2e">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Background" Value="#FF45475a"/>
            <Setter Property="Foreground" Value="#FFcdd6f4"/>
            <Setter Property="BorderBrush" Value="#FF585b70"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Margin" Value="6"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="Bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="True"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#FF585b70"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#FF89b4fa"/>
                                <Setter Property="Foreground" Value="#FFcdd6f4"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#FF89b4fa"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#FF89b4fa"/>
                                <Setter Property="Foreground" Value="#FF11111b"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Background" Value="#FF181825"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#FF313244"/>
                                <Setter Property="Foreground" Value="#FF6c7086"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#FFcdd6f4"/>
            <Setter Property="Margin" Value="6"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#FFcdd6f4"/>
        </Style>
        <Style x:Key="SidebarTabItem" TargetType="TabItem">
            <Setter Property="Foreground" Value="#FFbac2de"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="Margin" Value="0,2"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border Name="Bd" Background="Transparent" CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter ContentSource="Header" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#FF313244"/>
                                <Setter Property="Foreground" Value="#FFcdd6f4"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#FF181825"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="TabControl">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabControl">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="180"/>
                                <ColumnDefinition Width="8"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Border Grid.Column="0" Background="#FF181825" CornerRadius="10" BorderBrush="#FF313244" BorderThickness="1" Padding="10">
                                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                                    <TabPanel IsItemsHost="True" Background="Transparent"/>
                                </ScrollViewer>
                            </Border>
                            <Border Grid.Column="2" Background="#FF1e1e2e" CornerRadius="10" BorderBrush="#FF313244" BorderThickness="1" Padding="20">
                                <ContentPresenter ContentSource="SelectedContent"/>
                            </Border>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="#FF181825" Padding="14,18" BorderBrush="#FF313244" BorderThickness="0,0,0,1">
            <TextBlock Name="BannerText" FontFamily="Consolas" FontSize="12"
                       HorizontalAlignment="Center" TextAlignment="Center"/>
        </Border>

        <TabControl Grid.Row="1" Name="TabControl" Background="#FF1e1e2e" Margin="10"
                    ItemContainerStyle="{StaticResource SidebarTabItem}"/>

        <StatusBar Grid.Row="2" Background="#FF181825">
            <StatusBarItem>
                <TextBlock Name="StatusText" Text="Ready" Foreground="#FFbac2de"/>
            </StatusBarItem>
        </StatusBar>

        <Border Grid.Row="3" Background="#FF181825" Padding="8" BorderBrush="#FF313244" BorderThickness="0,1,0,0">
            <TextBlock Text="Made with *love* by Ashutosh" FontStyle="Italic" FontSize="11"
                       Foreground="#FF6c7086" HorizontalAlignment="Center"/>
        </Border>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$TabControl = $window.FindName("TabControl")
$StatusText = $window.FindName("StatusText")
$BannerText = $window.FindName("BannerText")

# Safety net: unhandled exceptions in button handlers keep the window alive.
$window.Dispatcher.add_UnhandledException({
    param($senderObj, $e)
    try { $Global:SyncHash.LogQueue.Enqueue("[UI ERROR] $($e.Exception.Message)") } catch {}
    $e.Handled = $true
})

# NMC-IT solid ASCII banner
$BannerText.Text = @"
╒═══╗  ╒═╗ ╒═══════╗ ╒═════╗        ╒═══╗ ╒═════╗
│   ╚╗ │ ║ │ ╓┐ ╓┐ ║ │ ╓─┐ ║        └┐ ╓╜ └─┐ ╓─╜
│ ╟┐ ╚╗│ ║ │ ║│ ║│ ║ │ ║ └─╜ ╒════╗  │ ║    │ ║  
│ ║└┐ ╚╡ ║ │ ║└─╜│ ║ │ ║ ╒═╗ └────╜  │ ║    │ ║  
│ ║ └┐   ║ │ ║   │ ║ │ ╚═╛ ║        ╒╛ ╚╗   │ ║  
└─╜  └───╜ └─╜   └─╜ └─────╜        └───╜   └─╜  
"@

$bannerBrush = New-Object System.Windows.Media.LinearGradientBrush
$bannerBrush.StartPoint = New-Object System.Windows.Point(0,0)
$bannerBrush.EndPoint   = New-Object System.Windows.Point(1,0)
$bannerBrush.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.Color]::FromRgb(203,166,247), 0.0)))  # Mauve
$bannerBrush.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.Color]::FromRgb(137,180,250), 1.0)))  # Blue
$BannerText.Foreground = $bannerBrush

$bannerGlow = New-Object System.Windows.Media.Effects.DropShadowEffect
$bannerGlow.Color = [System.Windows.Media.Color]::FromRgb(203,166,247)
$bannerGlow.BlurRadius = 18
$bannerGlow.ShadowDepth = 2
$bannerGlow.Opacity = 0.7
$BannerText.Effect = $bannerGlow

# ---------------------------------------------------------------------------
# Flush queued log lines to the console window
# ---------------------------------------------------------------------------
$logTimer = New-Object System.Windows.Threading.DispatcherTimer
$logTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$logTimer.Add_Tick({
    while ($Global:SyncHash.LogQueue.Count -gt 0) {
        $line = $Global:SyncHash.LogQueue.Dequeue()
        $color = if ($line -match '\[ERROR\]') { 'Red' }
                 elseif ($line -match '\[WARN\]') { 'Yellow' }
                 elseif ($line -match '\[DRY-RUN\]') { 'Cyan' }
                 else { 'Gray' }
        Write-Host $line -ForegroundColor $color
    }
})
$logTimer.Start()

# ---------------------------------------------------------------------------
# Start-BackgroundTask override: inject lgpo-helpers into background runspace
# ---------------------------------------------------------------------------
$Global:OriginalStartBackgroundTask = Get-Command Global:Start-BackgroundTask -ErrorAction SilentlyContinue

function Global:Start-BackgroundTask {
    param(
        [Parameter(Mandatory)][scriptblock]$Work,
        [object[]]$ArgumentList = @(),
        [scriptblock]$OnDone
    )

    # Inject lgpo-helpers.ps1 content after param(...) block so Invoke-LgpoApply
    # and Invoke-Gpupdate are available inside the background runspace.
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
            $wrappedStr = $workStr.Substring(0, $paramEnd) + "`n" + $Global:LgpoHelperScript + $workStr.Substring($paramEnd)
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

# ---------------------------------------------------------------------------
# Load tab modules from manifest.json
# ---------------------------------------------------------------------------
$StatusText.Text = "Loading modules..."
try {
    $manifest = Get-RepoJson -RelativePath "manifest.json"
    foreach ($mod in $manifest.modules) {
        try {
            Write-Log "Loading module: $($mod.name)"
            $code = Get-RepoText -RelativePath $mod.file
            Invoke-Expression $code
            $tabItem = & $mod.function
            if ($tabItem) {
                if ($tabItem.Content -isnot [System.Windows.Controls.ScrollViewer]) {
                    $originalContent = $tabItem.Content
                    $scrollWrapper = New-Object System.Windows.Controls.ScrollViewer
                    $scrollWrapper.VerticalScrollBarVisibility = 'Auto'
                    $scrollWrapper.HorizontalScrollBarVisibility = 'Disabled'
                    $scrollWrapper.Content = $originalContent
                    $tabItem.Content = $scrollWrapper
                }
                $TabControl.Items.Add($tabItem) | Out-Null
            }
        }
        catch {
            Write-Log "Failed to load module '$($mod.name)': $($_.Exception.Message)" "Error"
        }
    }
    $StatusText.Text = "Ready"
}
catch {
    Write-Log "Failed to load manifest.json: $($_.Exception.Message)" "Error"
    $StatusText.Text = "Failed to load modules -- check log"
}

try {
    $null = $window.ShowDialog()
}
catch {
    Write-Host ""
    Write-Host "=== GUI exception ===" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
}
finally {
    Write-Host ""
    Write-Host "Window closed." -ForegroundColor Yellow
    if ($Error.Count -gt 0) { $Error[0] | Format-List * -Force }
    else { Write-Host "  (none)" }
}
