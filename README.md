# WinTime

WinTime is a minimal Windows installer that asks the existing Windows Time service to synchronize the system clock after any user logs in. It installs no service, tray icon, or continuously running process.

The installer creates the root Task Scheduler task `TimeSyncAtLogon`. The task:

- runs as `NT AUTHORITY\SYSTEM` with highest privileges;
- triggers at every user logon after a native 30-second delay;
- starts the Windows Time service if it is stopped, without changing its startup type;
- runs the system command `w32tm.exe /resync` and then exits;
- retries a failed run up to three times at one-minute intervals; and
- records synchronization failures in the Windows **Application** event log with source `WinTime`.

WinTime does not change the configured NTP servers, Windows Time policy, service startup type, or other time preferences.

## Build

Building requires Windows PowerShell 5.1 or later and [Inno Setup 6](https://jrsoftware.org/isinfo.php). Inno Setup is a build-time dependency only.

From any working directory, run the canonical build script:

```powershell
C:\path\to\WinTime\build-scripts\build.ps1
```

From the repository root, the equivalent command is:

```powershell
.\build-scripts\build.ps1
```

For a nonstandard Inno Setup installation, pass the compiler path or set `ISCC_PATH`:

```powershell
.\build-scripts\build.ps1 -IsccPath 'D:\Tools\Inno Setup 6\ISCC.exe'
```

On success, the script prints the absolute path to `dist\WinTimeSetup.exe`. Compilation happens in a temporary staging directory, so a failed build does not replace an existing installer in `dist`.

To build an installer restricted to a specific 64-bit Windows architecture, use `-Architecture x64` (the default) or `-Architecture arm64`. A custom output name must be an `.exe` filename without a directory:

```powershell
.\build-scripts\build.ps1 -Architecture x64 -OutputFileName 'WinTime-1.0.0-windows-x64-setup.exe'
.\build-scripts\build.ps1 -Architecture arm64 -OutputFileName 'WinTime-1.0.0-windows-arm64-setup.exe'
```

The Forgejo workflow cross-compiles the release installers on Ubuntu instead. Install the distribution-provided NSIS compiler, then run the Linux build script on a host whose CPU matches the requested target:

```bash
sudo apt-get install nsis
bash build-scripts/build-linux.sh x64 WinTime-1.0.0-windows-x64-setup.exe
# On an aarch64 Ubuntu host:
bash build-scripts/build-linux.sh arm64 WinTime-1.0.0-windows-arm64-setup.exe
```

The script rejects non-Ubuntu systems and mismatched host CPUs. Both packages contain architecture-neutral PowerShell payloads, but each installer checks the native Windows architecture and refuses the wrong target.

## Release workflow

Every pushed commit runs `.forgejo/workflows/build.yml`. Windows x64 packages are cross-compiled on `ubuntu-22.04`; Windows ARM64 packages are cross-compiled on `arm-ubuntu-22.04`. Before checkout, each build installs Git, CA certificates, and Ubuntu's `nsis` package, then uploads its installer as a short-lived Forgejo Actions artifact.

To protect signing and publication credentials, only trusted pushes to `main` and `v*` tags aggregate and sign both installers. A trusted `main` push also mirrors Forgejo branches and tags to GitHub. A version tag matching the installer version, such as `v1.0.0`, additionally creates or updates the Forgejo and GitHub releases. Manual runs and other branches build both installers without receiving signing or GitHub credentials.

The workflow requires these repository secrets:

- `CI_KEY_B64`: a base64-encoded GPG secret key containing exactly one primary secret key;
- `CI_KEY_PASSPHRASE`: the passphrase for that key; and
- `GH_KEY`: a GitHub token able to push branches and tags and create releases in `firebadnofire/WinTime`.

For each release, Forgejo and GitHub receive x64 and ARM64 installers, a detached `.sig` for each installer, a `SHA256SUMS` file containing both installer hashes, and `SHA256SUMS.sig`. The release notes record the signing-key fingerprint and verification commands. The workflow uses Forgejo's job token to update the Forgejo release and replaces same-name assets on reruns. GitHub is treated as an exact mirror: its branches and tags are force-reconciled and refs removed from Forgejo are pruned from GitHub.

## Install and uninstall

Double-click `WinTimeSetup.exe`, approve the UAC prompt, and complete Setup. No command line, PowerShell policy change, or additional runtime is required.

To uninstall, open **Settings > Apps > Installed apps**, find **WinTime**, and choose **Uninstall**. The elevated uninstaller removes the scheduled task and the `WinTime` event source before removing the installed scripts. It does not stop, disable, reconfigure, or remove the Windows Time service.

Installing the same or a newer version updates the single stable task instead of creating a duplicate. If task registration fails during an upgrade, the registration script attempts to restore the previous task definition and Setup reports the failure.

## Verify

After installation, open an elevated Windows PowerShell window and inspect the task:

```powershell
$task = Get-ScheduledTask -TaskName 'TimeSyncAtLogon' -TaskPath '\'
$task | Select-Object TaskName, TaskPath, State
$task.Principal | Select-Object UserId, LogonType, RunLevel
$task.Triggers | Select-Object UserId, Delay, Enabled
$task.Settings | Select-Object RestartCount, RestartInterval, ExecutionTimeLimit
```

Expected values include the SYSTEM identity (`SYSTEM` or SID `S-1-5-18`), `ServiceAccount`, `Highest`, an empty trigger `UserId` (meaning every user), delay `PT30S`, restart count `3`, and restart interval `PT1M`.

To request a test run and inspect its result:

```powershell
Start-ScheduledTask -TaskName 'TimeSyncAtLogon' -TaskPath '\'
Start-Sleep -Seconds 5
Get-ScheduledTaskInfo -TaskName 'TimeSyncAtLogon' -TaskPath '\' |
    Select-Object LastRunTime, LastTaskResult, NextRunTime
```

`LastTaskResult` is `0` after a successful completed run. `Start-ScheduledTask` returns before the task necessarily finishes, so wait longer if the task is still running. For failures, open **Event Viewer > Windows Logs > Application** and filter by event source `WinTime` and event ID `1001`.

## Project layout

```text
installer/TimeSync.iss       Windows/Inno Setup definition
installer/TimeSync.nsi       Ubuntu/NSIS cross-build definition
scripts/install-task.ps1     Idempotent task registration and upgrade rollback
scripts/sync-time.ps1        One-shot time synchronization action
scripts/uninstall-task.ps1   Idempotent task and event-source removal
build-scripts/build.ps1      Windows/Inno Setup build entry point
build-scripts/build-linux.sh Ubuntu/NSIS cross-build entry point
dist/                        Generated installer output
```

## Runtime requirements

The installed utility uses only Windows PowerShell 5.1, Task Scheduler, the Windows Event Log, the Windows Time service, and `w32tm.exe`, all included with supported Windows 10 and Windows 11 systems. Inno Setup and NSIS are not required on end-user computers.
