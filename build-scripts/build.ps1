#requires -version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string] $IsccPath,

    [Parameter()]
    [ValidateSet('x64', 'arm64')]
    [string] $Architecture = 'x64',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputFileName = 'WinTimeSetup.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-InnoSetupCompiler {
    param(
        [Parameter()]
        [string] $ConfiguredPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        if (-not (Test-Path -LiteralPath $ConfiguredPath -PathType Leaf)) {
            throw "The configured Inno Setup compiler does not exist: '$ConfiguredPath'."
        }

        return (Resolve-Path -LiteralPath $ConfiguredPath).Path
    }

    if (-not [string]::IsNullOrWhiteSpace($env:ISCC_PATH)) {
        if (-not (Test-Path -LiteralPath $env:ISCC_PATH -PathType Leaf)) {
            throw "ISCC_PATH points to a file that does not exist: '$env:ISCC_PATH'."
        }

        return (Resolve-Path -LiteralPath $env:ISCC_PATH).Path
    }

    $pathCommand = Get-Command -Name 'ISCC.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $pathCommand) {
        return $pathCommand.Source
    }

    $candidates = @(
        (Join-Path -Path $env:ProgramFiles -ChildPath 'Inno Setup 6\ISCC.exe')
    )

    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $candidates += Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Inno Setup 6\ISCC.exe'
    }

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates += Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs\Inno Setup 6\ISCC.exe'
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw @'
Inno Setup 6 was not found. Install Inno Setup, then rerun this script.
For a nonstandard installation, use -IsccPath 'C:\path\to\ISCC.exe' or set the ISCC_PATH environment variable.
'@
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
$installerScript = Join-Path -Path $repositoryRoot -ChildPath 'installer\TimeSync.iss'
$outputDirectory = Join-Path -Path $repositoryRoot -ChildPath 'dist'
$finalInstaller = Join-Path -Path $outputDirectory -ChildPath $outputFileName
$stagingDirectory = Join-Path -Path $outputDirectory -ChildPath ('.build-{0}' -f [Guid]::NewGuid().ToString('N'))

try {
    if ([IO.Path]::GetFileName($OutputFileName) -ne $OutputFileName -or
        [IO.Path]::GetExtension($OutputFileName) -ne '.exe') {
        throw "OutputFileName must be an .exe filename without a directory. Received '$OutputFileName'."
    }

    if (-not (Test-Path -LiteralPath $installerScript -PathType Leaf)) {
        throw "The Inno Setup script was not found at '$installerScript'."
    }

    $compiler = Resolve-InnoSetupCompiler -ConfiguredPath $IsccPath

    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $stagingDirectory | Out-Null

    $outputBaseName = [IO.Path]::GetFileNameWithoutExtension($OutputFileName)
    & $compiler "/DTargetArchitecture=$Architecture" "/O$stagingDirectory" "/F$outputBaseName" $installerScript
    $compilerExitCode = $LASTEXITCODE

    if ($compilerExitCode -ne 0) {
        throw "Inno Setup compilation failed with exit code $compilerExitCode."
    }

    $stagedInstaller = Join-Path -Path $stagingDirectory -ChildPath $outputFileName
    if (-not (Test-Path -LiteralPath $stagedInstaller -PathType Leaf)) {
        throw "Inno Setup reported success but did not create '$stagedInstaller'."
    }

    Move-Item -LiteralPath $stagedInstaller -Destination $finalInstaller -Force
    Write-Output ([IO.Path]::GetFullPath($finalInstaller))
}
catch {
    [Console]::Error.WriteLine("WinTime build failed: $($_.Exception.Message)")
    exit 1
}
finally {
    if (Test-Path -LiteralPath $stagingDirectory -PathType Container) {
        Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
