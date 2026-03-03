param(
    [Parameter(Mandatory=$true)]
    [string]$OutputFile
)

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class MouseRecorder {
    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X;
        public int Y;
    }

    public const int VK_LBUTTON = 0x01;
    public const int VK_RBUTTON = 0x02;
    public const int VK_MBUTTON = 0x04;
    public const int VK_E = 0x45;
}
"@

$events = [System.Collections.Generic.List[string]]::new()
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$prevX = -1
$prevY = -1
$prevLeft = $false
$prevRight = $false
$prevMiddle = $false

# Clear any stale key state
[MouseRecorder]::GetAsyncKeyState([MouseRecorder]::VK_E) | Out-Null

while ($true) {
    # Check for E key to stop
    $eState = [MouseRecorder]::GetAsyncKeyState([MouseRecorder]::VK_E)
    if ($eState -band 0x8000) { break }

    $point = New-Object MouseRecorder+POINT
    [MouseRecorder]::GetCursorPos([ref]$point) | Out-Null

    $time = $sw.ElapsedMilliseconds
    $x = $point.X
    $y = $point.Y

    $leftDown = ([MouseRecorder]::GetAsyncKeyState([MouseRecorder]::VK_LBUTTON) -band 0x8000) -ne 0
    $rightDown = ([MouseRecorder]::GetAsyncKeyState([MouseRecorder]::VK_RBUTTON) -band 0x8000) -ne 0
    $middleDown = ([MouseRecorder]::GetAsyncKeyState([MouseRecorder]::VK_MBUTTON) -band 0x8000) -ne 0

    # Record position only when it changes
    if ($x -ne $prevX -or $y -ne $prevY) {
        $events.Add("$time,move,$x,$y")
        $prevX = $x
        $prevY = $y
    }

    # Record button press/release transitions
    if ($leftDown -and -not $prevLeft)    { $events.Add("$time,left_down,$x,$y") }
    if (-not $leftDown -and $prevLeft)    { $events.Add("$time,left_up,$x,$y") }
    if ($rightDown -and -not $prevRight)  { $events.Add("$time,right_down,$x,$y") }
    if (-not $rightDown -and $prevRight)  { $events.Add("$time,right_up,$x,$y") }
    if ($middleDown -and -not $prevMiddle){ $events.Add("$time,middle_down,$x,$y") }
    if (-not $middleDown -and $prevMiddle){ $events.Add("$time,middle_up,$x,$y") }

    $prevLeft = $leftDown
    $prevRight = $rightDown
    $prevMiddle = $middleDown

    [System.Threading.Thread]::Sleep(10)
}

$sw.Stop()
[System.IO.File]::WriteAllLines($OutputFile, $events.ToArray())
