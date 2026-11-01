<#
.SYNOPSIS
    Main entry point. Downloaded and executed by bootstrap.ps1 via Invoke-Expression.
    Builds the WPF GUI shell, then pulls tab modules from manifest.json.
    All policy changes go through LGPO.exe (.pol files downloaded at runtime).
    No direct registry edits are made by this tool.
#>

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# Dot-source shared libraries
. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'lgpo-helpers.ps1')

if (-not $Global:BaseRepoUrl) {
    $Global:BaseRepoUrl = "https://raw.githubusercontent.com/asup20cs/winscript/main"
}

# ---------------------------------------------------------------------------
# Local-first repo loader
# ---------------------------------------------------------------------------
if (-not $Global:LocalRepoPath) {
    if ($env:WINTOOL_LOCAL_REPO -and (Test-Path (Join-Path $env:WINTOOL_LOCAL_REPO 'manifest.json'))) {
        $Global:LocalRepoPath = $env:WINTOOL_LOCAL_REPO
    }
    else {
        $candidate = $null
        if ($PSScriptRoot)                    { $candidate = $PSScriptRoot }
        elseif ($MyInvocation.MyCommand.Path) { $candidate = Split-Path -Parent $MyInvocation.MyCommand.Path }
        if ($candidate -and (Test-Path (Join-Path $candidate 'manifest.json'))) {
            $Global:LocalRepoPath = $candidate
        }
        elseif (Test-Path (Join-Path (Get-Location).Path 'manifest.json')) {
            $Global:LocalRepoPath = (Get-Location).Path
        }
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
    if (-not $BaseRepoUrl) { throw "No local copy of '$RelativePath' and no BaseRepoUrl configured." }
    $resp = Invoke-WebRequest -Uri "$BaseRepoUrl/$RelativePath" -UseBasicParsing
    return [string]$resp.Content
}

function Global:Get-RepoJson {
    param([Parameter(Mandatory)][string]$RelativePath)
    $text = Get-RepoText -RelativePath $RelativePath
    return ($text | ConvertFrom-Json)
}

# ---------------------------------------------------------------------------
# Window skeleton (XAML) -- Catppuccin Mocha theme
# Colors defined as XAML resources (Color + SolidColorBrush) for maximum
# compatibility with .NET Framework / PowerShell 5.1 WPF.
# No PowerShell variable interpolation inside XAML.
# ---------------------------------------------------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinScript - NMC-IT" Height="600" Width="1000"
        WindowStartupLocation="CenterScreen"
        Background="{StaticResource WindowBaseBrush}">
    <Window.Resources>
        <!-- Catppuccin Mocha colors -->
        <Color x:Key="ColorBase">#FF1e1e2e</Color>
        <Color x:Key="ColorMantle">#FF181825</Color>
        <Color x:Key="ColorCrust">#FF11111b</Color>
        <Color x:Key="ColorSurface0">#FF313244</Color>
        <Color x:Key="ColorSurface1">#FF45475a</Color>
        <Color x:Key="ColorSurface2">#FF585b70</Color>
        <Color x:Key="ColorOverlay0">#FF6c7086</Color>
        <Color x:Key="ColorOverlay1">#FF7f849c</Color>
        <Color x:Key="ColorOverlay2">#FF9399b2</Color>
        <Color x:Key="ColorSubtext0">#FFa6adc8</Color>
        <Color x:Key="ColorSubtext1">#FFbac2de</Color>
        <Color x:Key="ColorText">#FFcdd6f4</Color>
        <Color x:Key="ColorRed">#FFf38ba8</Color>
        <Color x:Key="ColorGreen">#FFa6e3a1</Color>
        <Color x:Key="ColorBlue">#FF89b4fa</Color>
        <Color x:Key="ColorMauve">#FFcba6f7</Color>

        <SolidColorBrush x:Key="WindowBaseBrush" Color="{StaticResource ColorBase}"/>
        <SolidColorBrush x:Key="WindowMantleBrush" Color="{StaticResource ColorMantle}"/>
        <SolidColorBrush x:Key="WindowSurface0Brush" Color="{StaticResource ColorSurface0}"/>
        <SolidColorBrush x:Key="WindowSurface1Brush" Color="{StaticResource ColorSurface1}"/>
        <SolidColorBrush x:Key="WindowSurface2Brush" Color="{StaticResource ColorSurface2}"/>
        <SolidColorBrush x:Key="WindowTextBrush" Color="{StaticResource ColorText}"/>
        <SolidColorBrush x:Key="WindowSubtext1Brush" Color="{StaticResource ColorSubtext1}"/>
        <SolidColorBrush x:Key="WindowSubtext0Brush" Color="{StaticResource ColorSubtext0}"/>
        <SolidColorBrush x:Key="WindowRedBrush" Color="{StaticResource ColorRed}"/>
        <SolidColorBrush x:Key="WindowGreenBrush" Color="{StaticResource ColorGreen}"/>
        <SolidColorBrush x:Key="WindowBlueBrush" Color="{StaticResource ColorBlue}"/>

        <Style TargetType="Button">
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Background" Value="{StaticResource WindowSurface1Brush}"/>
            <Setter Property="Foreground" Value="{StaticResource WindowTextBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource WindowSurface2Brush}"/>
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
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource WindowSurface2Brush}"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource WindowBlueBrush}"/>
                                <Setter Property="Foreground" Value="{StaticResource WindowTextBrush}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource WindowBlueBrush}"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource WindowBlueBrush}"/>
                                <Setter Property="Foreground" Value="{StaticResource ColorCrust}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource WindowMantleBrush}"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource WindowSurface0Brush}"/>
                                <Setter Property="Foreground" Value="{StaticResource WindowSubtext0Brush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{StaticResource WindowTextBrush}"/>
            <Setter Property="Margin" Value="6"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource WindowTextBrush}"/>
        </Style>
        <Style x:Key="SidebarTabItem" TargetType="TabItem">
            <Setter Property="Foreground" Value="{StaticResource WindowSubtext1Brush}"/>
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
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource WindowSurface0Brush}"/>
                                <Setter Property="Foreground" Value="{StaticResource WindowTextBrush}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource WindowMantleBrush}"/>
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
                            <Border Grid.Column="0" Background="{StaticResource WindowMantleBrush}" CornerRadius="10" BorderBrush="{StaticResource WindowSurface0Brush}" BorderThickness="1" Padding="10">
                                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                                    <TabPanel IsItemsHost="True" Background="Transparent"/>
                                </ScrollViewer>
                            </Border>
                            <Border Grid.Column="2" Background="{StaticResource WindowBaseBrush}" CornerRadius="10" BorderBrush="{StaticResource WindowSurface0Brush}" BorderThickness="1" Padding="20">
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

        <Border Grid.Row="0" Background="{StaticResource WindowMantleBrush}" Padding="14,18" BorderBrush="{StaticResource WindowSurface0Brush}" BorderThickness="0,0,0,1">
            <TextBlock Name="BannerText" FontFamily="Consolas" FontSize="12"
                       HorizontalAlignment="Center" TextAlignment="Center"/>
        </Border>

        <TabControl Grid.Row="1" Name="TabControl" Background="{StaticResource WindowBaseBrush}" Margin="10"
                    ItemContainerStyle="{StaticResource SidebarTabItem}"/>

        <StatusBar Grid.Row="2" Background="{StaticResource WindowMantleBrush}">
            <StatusBarItem>
                <TextBlock Name="StatusText" Text="Ready" Foreground="{StaticResource WindowSubtext1Brush}"/>
            </StatusBarItem>
        </StatusBar>

        <Border Grid.Row="3" Background="{StaticResource WindowMantleBrush}" Padding="8" BorderBrush="{StaticResource WindowSurface0Brush}" BorderThickness="0,1,0,0">
            <TextBlock Text="Made with *love* by Ashutosh" FontStyle="Italic" FontSize="11"
                       Foreground="{StaticResource WindowSubtext0Brush}" HorizontalAlignment="Center"/>
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
______      _             _       
| ___ \    | |           | |      
| |_/ / __ | | ___   ___ | | __   
|  __/ / _ \| |/ _ \ / _ \| |/ /  
| |  | (_) | | (_) | (_) |   <   
\_|   \___/|_|\___/ \___/|_|\_\  
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
