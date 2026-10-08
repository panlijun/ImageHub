param([string]$Executable = '')
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Executable)) {
  $Executable = Join-Path $PSScriptRoot '../build/windows/x64/runner/Release/imagehub.exe'
}
$Executable = (Resolve-Path -LiteralPath $Executable).Path

# Uses only the process started below. The Windows runner can be hidden, so
# Process.MainWindowHandle is not an appropriate existence check.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class ImageHostOwnedRunnerSmoke {
  public delegate bool Callback(IntPtr window, IntPtr state);
  [DllImport("user32.dll")] static extern bool EnumWindows(Callback callback, IntPtr state);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int count);
  [DllImport("user32.dll", EntryPoint="PostMessageW")] static extern bool PostMessage(IntPtr window, uint message, IntPtr wparam, IntPtr lparam);
  public static int Runners(uint processId, bool close) {
    int count = 0;
    EnumWindows((window, state) => {
      uint owner; GetWindowThreadProcessId(window, out owner);
      if (owner == processId) {
        var name = new StringBuilder(256); GetClassName(window, name, 256);
        if (name.ToString() == "FLUTTER_RUNNER_WIN32_WINDOW") {
          if (!close || PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero)) count++;
        }
      }
      return true;
    }, IntPtr.Zero);
    return count;
  }
}
'@

$runtime = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path -Parent $Executable) -WindowStyle Hidden -PassThru
try {
  # Retain the original process handle before it exits, so ExitCode stays
  # readable. Re-fetching Get-Process after start does not provide this evidence.
  $ownedHandle = $runtime.Handle
  if ($ownedHandle -eq [IntPtr]::Zero) { throw 'Cannot retain the owned process handle.' }
  $found = $false
  for ($attempt = 0; $attempt -lt 50; $attempt++) {
    if ($runtime.HasExited) { throw "Release exited during startup: $($runtime.ExitCode)" }
    if ([ImageHostOwnedRunnerSmoke]::Runners([uint32]$runtime.Id, $false) -gt 0) {
      $found = $true
      break
    }
    Start-Sleep -Milliseconds 200
  }
  if (-not $found) { throw 'The owned Flutter runner window was not created.' }
  Start-Sleep -Seconds 3
  if ($runtime.HasExited) { throw 'Release exited before normal close.' }
  if ([ImageHostOwnedRunnerSmoke]::Runners([uint32]$runtime.Id, $true) -lt 1) {
    throw 'Could not request normal WM_CLOSE on the owned runner.'
  }
  if (-not $runtime.WaitForExit(15000)) { throw 'Normal Release window close timed out.' }
  if ($runtime.ExitCode -ne 0) { throw "Normal Release exit code: $($runtime.ExitCode)" }
  'PASS Windows Release native runner creation and normal WM_CLOSE, exit 0'
} finally {
  if (-not $runtime.HasExited) {
    # Retry graceful close only for this owned PID; never force-kill other apps.
    [void][ImageHostOwnedRunnerSmoke]::Runners([uint32]$runtime.Id, $true)
    [void]$runtime.WaitForExit(15000)
  }
  $runtime.Dispose()
}
