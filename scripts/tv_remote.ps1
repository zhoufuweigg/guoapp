param(
    [Parameter(Position = 0)]
    [string]$Serial
)

$ErrorActionPreference = 'Stop'

$Keys = [ordered]@{
    UpArrow    = 'KEYCODE_DPAD_UP'
    DownArrow  = 'KEYCODE_DPAD_DOWN'
    LeftArrow  = 'KEYCODE_DPAD_LEFT'
    RightArrow = 'KEYCODE_DPAD_RIGHT'
    Enter      = 'KEYCODE_DPAD_CENTER'
    Escape     = 'KEYCODE_BACK'
    Backspace  = 'KEYCODE_BACK'
    Spacebar   = 'KEYCODE_MEDIA_PLAY_PAUSE'
    M          = 'KEYCODE_MENU'
    H          = 'KEYCODE_HOME'
}

$start = [System.Diagnostics.ProcessStartInfo]::new('adb')
if ($Serial) { $start.ArgumentList.Add('-s'); $start.ArgumentList.Add($Serial) }
$start.ArgumentList.Add('shell')
$start.UseShellExecute = $false
$start.RedirectStandardInput = $true
$adb = [System.Diagnostics.Process]::Start($start)
$adb.StandardInput.NewLine = "`n"
$adb.StandardInput.AutoFlush = $true

Write-Host ''
foreach ($key in $Keys.Keys) {
    Write-Host ('  {0,-11} {1}' -f $key, $Keys[$key])
}
Write-Host '  Q           quit'
Write-Host ''

try {
    while (-not $adb.HasExited) {
        $key = [Console]::ReadKey($true).Key.ToString()
        if ($key -eq 'Q') { break }
        $code = $Keys[$key]
        if (-not $code) { continue }
        $adb.StandardInput.WriteLine("input dpad keyevent $code")
        Write-Host $code
    }
} finally {
    if (-not $adb.HasExited) {
        $adb.StandardInput.Close()
        $adb.WaitForExit()
    }
}
