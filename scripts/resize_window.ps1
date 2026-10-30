param(
    [Parameter(Position = 0)]
    [ValidateSet('phone', 'iphone', 'tablet', 'ipad', 'tv', 'window')]
    [string]$Device,
    [switch]$Rotate
)

$ErrorActionPreference = 'Stop'

$Presets = [ordered]@{
    phone  = 412, 915
    iphone = 393, 852
    tablet = 1280, 800
    ipad   = 1180, 820
    tv     = 960, 540
    window = 1280, 720
}
$Title = -join [char[]](0x771F, 0x679C, 0x9274)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class AppWindow {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindowW(string className, string windowName);

    [DllImport("user32.dll")]
    public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);

    [DllImport("user32.dll")]
    public static extern uint GetDpiForWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern int GetWindowLongW(IntPtr hwnd, int index);

    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool AdjustWindowRectExForDpi(ref RECT rect, int style, bool menu, int exStyle, uint dpi);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hwnd, int command);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);
}
'@

$PerMonitorAwareV2 = [IntPtr]-4
$GwlStyle = -16
$GwlExStyle = -20
$SwRestore = 9
$SwpNoMoveNoZOrderNoActivate = 0x0016

$null = [AppWindow]::SetThreadDpiAwarenessContext($PerMonitorAwareV2)

function Get-AppWindow {
    $hwnd = [AppWindow]::FindWindowW('FLUTTER_RUNNER_WIN32_WINDOW', $Title)
    if ($hwnd -eq [IntPtr]::Zero) {
        throw "Window '$Title' not found."
    }
    $null = [AppWindow]::ShowWindow($hwnd, $SwRestore)
    $hwnd
}

function Set-ClientSize([IntPtr]$Hwnd, [int]$Width, [int]$Height) {
    $dpi = [AppWindow]::GetDpiForWindow($Hwnd)
    $rect = New-Object AppWindow+RECT
    $rect.Right = $Width
    $rect.Bottom = $Height
    $style = [AppWindow]::GetWindowLongW($Hwnd, $GwlStyle)
    $exStyle = [AppWindow]::GetWindowLongW($Hwnd, $GwlExStyle)
    $null = [AppWindow]::AdjustWindowRectExForDpi([ref]$rect, $style, $false, $exStyle, $dpi)

    $null = [AppWindow]::SetWindowPos(
        $Hwnd, [IntPtr]::Zero, 0, 0,
        $rect.Right - $rect.Left, $rect.Bottom - $rect.Top,
        $SwpNoMoveNoZOrderNoActivate)

    Write-Host ('-> {0} x {1}' -f [math]::Round($Width * 96 / $dpi), [math]::Round($Height * 96 / $dpi))
}

function Resize-AppWindow([string]$Name, [bool]$Rotated) {
    $width, $height = $Presets[$Name]
    if ($Rotated) { $width, $height = $height, $width }
    $hwnd = Get-AppWindow
    $dpi = [AppWindow]::GetDpiForWindow($hwnd)
    Set-ClientSize $hwnd ([math]::Round($width * $dpi / 96)) ([math]::Round($height * $dpi / 96))
}

function Rotate-AppWindow {
    $hwnd = Get-AppWindow
    $rect = New-Object AppWindow+RECT
    $null = [AppWindow]::GetClientRect($hwnd, [ref]$rect)
    Set-ClientSize $hwnd $rect.Bottom $rect.Right
}

if ($Device) {
    Resize-AppWindow $Device $Rotate.IsPresent
    return
}

$names = @($Presets.Keys)
while ($true) {
    Write-Host ''
    for ($i = 0; $i -lt $names.Count; $i++) {
        $size = $Presets[$names[$i]]
        Write-Host ('  {0}  {1,-7} {2} x {3}' -f ($i + 1), $names[$i], $size[0], $size[1])
    }
    $choice = Read-Host 'Number (append r to rotate), r to rotate current, q to quit'
    try {
        if ($choice -eq 'q') {
            break
        } elseif ($choice -eq 'r') {
            Rotate-AppWindow
        } elseif ($choice -match '^\s*(\d+)\s*(r?)\s*$' -and [int]$Matches[1] -ge 1 -and [int]$Matches[1] -le $names.Count) {
            Resize-AppWindow $names[[int]$Matches[1] - 1] ($Matches[2] -eq 'r')
        } else {
            Write-Host 'Invalid choice.'
        }
    } catch {
        Write-Host $_.Exception.Message
    }
}
