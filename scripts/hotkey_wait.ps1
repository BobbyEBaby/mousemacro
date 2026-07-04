param(
    [Parameter(Mandatory=$true)]
    [int]$VK
)

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class HotkeyWait {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
}
"@

# Wait for the key to be released first so a held key can't retrigger instantly
while (([HotkeyWait]::GetAsyncKeyState($VK) -band 0x8000) -ne 0) {
    [System.Threading.Thread]::Sleep(30)
}

# Clear stale key state
[HotkeyWait]::GetAsyncKeyState($VK) | Out-Null

# Exit as soon as the hotkey is pressed; Godot notices the exit and plays the macro
while (([HotkeyWait]::GetAsyncKeyState($VK) -band 0x8000) -eq 0) {
    [System.Threading.Thread]::Sleep(30)
}
