#requires -version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$eventSource = 'WinTime'
$eventLog = 'Application'
$serviceName = 'W32Time'
$w32tmPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\w32tm.exe'

function Write-TimeSyncFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    try {
        Write-EventLog -LogName $eventLog -Source $eventSource -EntryType Error -EventId 1001 -Message $Message
    }
    catch {
        [Console]::Error.WriteLine(
            "Unable to write the WinTime failure to the Windows Application log: $($_.Exception.Message)"
        )
    }
}

try {
    if (-not (Test-Path -LiteralPath $w32tmPath -PathType Leaf)) {
        throw "Windows Time command not found at '$w32tmPath'."
    }

    $timeService = Get-Service -Name $serviceName
    if ($timeService.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
        Start-Service -Name $serviceName
        $timeService.WaitForStatus(
            [System.ServiceProcess.ServiceControllerStatus]::Running,
            [TimeSpan]::FromSeconds(20)
        )
    }

    $resyncOutput = (& $w32tmPath /resync 2>&1 | Out-String).Trim()
    $resyncExitCode = $LASTEXITCODE

    if ($resyncExitCode -ne 0) {
        throw "w32tm.exe /resync exited with code $resyncExitCode. Output: $resyncOutput"
    }
}
catch {
    $failureMessage = "Time synchronization failed. $($_.Exception.Message)"
    Write-TimeSyncFailure -Message $failureMessage
    [Console]::Error.WriteLine($failureMessage)
    exit 1
}

exit 0
