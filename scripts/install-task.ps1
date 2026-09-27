#requires -version 5.1
#requires -modules ScheduledTasks

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $InstallDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'TimeSyncAtLogon'
$taskPath = '\'
$eventSource = 'WinTime'
$eventLog = 'Application'

if (-not [IO.Path]::IsPathRooted($InstallDirectory)) {
    throw "InstallDirectory must be an absolute path. Received '$InstallDirectory'."
}

$installPath = [IO.Path]::GetFullPath($InstallDirectory)
$syncScriptPath = [IO.Path]::GetFullPath((Join-Path -Path $installPath -ChildPath 'sync-time.ps1'))
$powerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
$createdEventSource = $false
$previousTaskXml = $null

if (-not (Test-Path -LiteralPath $syncScriptPath -PathType Leaf)) {
    throw "The synchronization script was not found at '$syncScriptPath'."
}

if (-not (Test-Path -LiteralPath $powerShellPath -PathType Leaf)) {
    throw "Windows PowerShell was not found at '$powerShellPath'."
}

try {
    $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    if ($null -ne $existingTask) {
        $previousTaskXml = Export-ScheduledTask -TaskName $taskName -TaskPath $taskPath
    }

    if (-not [Diagnostics.EventLog]::SourceExists($eventSource)) {
        New-EventLog -LogName $eventLog -Source $eventSource
        $createdEventSource = $true
    }

    $actionArguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $syncScriptPath
    $action = New-ScheduledTaskAction `
        -Execute $powerShellPath `
        -Argument $actionArguments `
        -WorkingDirectory $installPath

    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $trigger.Delay = 'PT30S'

    $principal = New-ScheduledTaskPrincipal `
        -UserId 'S-1-5-18' `
        -LogonType ServiceAccount `
        -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

    $task = New-ScheduledTask `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description 'Synchronizes the Windows system clock after any user logs in.'

    Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -InputObject $task -Force | Out-Null

    $registeredTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath
    $hasExpectedPrincipal =
        $registeredTask.Principal.UserId -in @('SYSTEM', 'S-1-5-18', 'NT AUTHORITY\SYSTEM') -and
        $registeredTask.Principal.LogonType -eq 'ServiceAccount' -and
        $registeredTask.Principal.RunLevel -eq 'Highest'
    $hasExpectedTrigger =
        $registeredTask.Triggers.Count -eq 1 -and
        $registeredTask.Triggers[0].CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' -and
        [string]::IsNullOrEmpty($registeredTask.Triggers[0].UserId) -and
        $registeredTask.Triggers[0].Delay -eq 'PT30S'
    $hasExpectedAction =
        $registeredTask.Actions.Count -eq 1 -and
        $registeredTask.Actions[0].Execute -eq $powerShellPath -and
        $registeredTask.Actions[0].Arguments -eq $actionArguments
    $hasExpectedRetries =
        $registeredTask.Settings.RestartCount -eq 3 -and
        $registeredTask.Settings.RestartInterval -eq 'PT1M'

    if (-not ($hasExpectedPrincipal -and $hasExpectedTrigger -and $hasExpectedAction -and $hasExpectedRetries)) {
        throw "The '$taskName' task was registered, but its stored definition did not match the required security, trigger, action, or retry settings."
    }
}
catch {
    $registrationError = $_

    if ($null -ne $previousTaskXml) {
        try {
            Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Xml $previousTaskXml -Force | Out-Null
        }
        catch {
            Write-Error -ErrorAction Continue "Task registration failed, and the previous '$taskName' task could not be restored: $($_.Exception.Message)"
        }
    }
    else {
        try {
            $partialTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
            if ($null -ne $partialTask) {
                Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
            }
        }
        catch {
            Write-Error -ErrorAction Continue "Task registration failed, and the partial '$taskName' task could not be removed: $($_.Exception.Message)"
        }
    }

    if ($createdEventSource) {
        try {
            Remove-EventLog -Source $eventSource
        }
        catch {
            Write-Error -ErrorAction Continue "Task registration failed, and the '$eventSource' event source could not be removed: $($_.Exception.Message)"
        }
    }

    throw $registrationError
}
