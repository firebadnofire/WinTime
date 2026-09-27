#requires -version 5.1
#requires -modules ScheduledTasks

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'TimeSyncAtLogon'
$taskPath = '\'
$eventSource = 'WinTime'

$existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
if ($null -ne $existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
}

if ([Diagnostics.EventLog]::SourceExists($eventSource)) {
    Remove-EventLog -Source $eventSource
}
