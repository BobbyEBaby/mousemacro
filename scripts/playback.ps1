param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile,
    [switch]$Loop,
    [int]$LoopCount = 0
)

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class MousePlayer {
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    public const uint MOUSEEVENTF_LEFTDOWN   = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP     = 0x0004;
    public const uint MOUSEEVENTF_RIGHTDOWN  = 0x0008;
    public const uint MOUSEEVENTF_RIGHTUP    = 0x0010;
    public const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    public const uint MOUSEEVENTF_MIDDLEUP   = 0x0040;

    public const int VK_ESCAPE = 0x1B;
}
"@

$lines = [System.IO.File]::ReadAllLines($InputFile)
if ($lines.Count -eq 0) { exit }

# Clear stale key state
[MousePlayer]::GetAsyncKeyState([MousePlayer]::VK_ESCAPE) | Out-Null

$iteration = 0

do {
    $iteration++
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($line in $lines) {
        $parts = $line.Split(',')
        if ($parts.Count -lt 4) { continue }

        $targetTime = [long]$parts[0]
        $eventType  = $parts[1]
        $x          = [int]$parts[2]
        $y          = [int]$parts[3]

        # Wait until the target timestamp, checking for Escape
        while ($sw.ElapsedMilliseconds -lt $targetTime) {
            if ([MousePlayer]::GetAsyncKeyState([MousePlayer]::VK_ESCAPE) -band 0x8000) { exit }
            [System.Threading.Thread]::Sleep(1)
        }

        # Execute the event
        switch ($eventType) {
            "move" {
                [MousePlayer]::SetCursorPos($x, $y)
            }
            "left_down" {
                [MousePlayer]::SetCursorPos($x, $y)
                [MousePlayer]::mouse_event([MousePlayer]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
            }
            "left_up" {
                [MousePlayer]::SetCursorPos($x, $y)
                [MousePlayer]::mouse_event([MousePlayer]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
            }
            "right_down" {
                [MousePlayer]::SetCursorPos($x, $y)
                [MousePlayer]::mouse_event([MousePlayer]::MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, [UIntPtr]::Zero)
            }
            "right_up" {
                [MousePlayer]::SetCursorPos($x, $y)
                [MousePlayer]::mouse_event([MousePlayer]::MOUSEEVENTF_RIGHTUP, 0, 0, 0, [UIntPtr]::Zero)
            }
            "middle_down" {
                [MousePlayer]::SetCursorPos($x, $y)
                [MousePlayer]::mouse_event([MousePlayer]::MOUSEEVENTF_MIDDLEDOWN, 0, 0, 0, [UIntPtr]::Zero)
            }
            "middle_up" {
                [MousePlayer]::SetCursorPos($x, $y)
                [MousePlayer]::mouse_event([MousePlayer]::MOUSEEVENTF_MIDDLEUP, 0, 0, 0, [UIntPtr]::Zero)
            }
        }
    }

    $sw.Stop()

    # If a finite loop count is set, stop after that many iterations
    if ($LoopCount -gt 0 -and $iteration -ge $LoopCount) { break }
} while ($Loop)
