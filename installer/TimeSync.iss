#define AppName "WinTime"
#ifndef AppVersion
#define AppVersion "1.0.0"
#endif
#define AppPublisher "firebadnofire"

#ifndef TargetArchitecture
#define TargetArchitecture "x64"
#endif

#if TargetArchitecture == "x64"
#define AllowedArchitectures "x64compatible and not arm64"
#define InstallModeArchitectures "x64compatible"
#elif TargetArchitecture == "arm64"
#define AllowedArchitectures "arm64"
#define InstallModeArchitectures "arm64"
#else
#error Unsupported TargetArchitecture. Expected x64 or arm64.
#endif

[Setup]
AppId={{8E65DF7C-935E-4F6E-BF0C-A15161A6D2CB}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppCopyright=Copyright (c) 2026 {#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DisableDirPage=yes
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
MinVersion=10.0.14393
PrivilegesRequired=admin
ArchitecturesAllowed={#AllowedArchitectures}
ArchitecturesInstallIn64BitMode={#InstallModeArchitectures}
OutputDir=..\dist
OutputBaseFilename=WinTimeSetup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#AppName}
Uninstallable=yes
UsePreviousAppDir=yes
CloseApplications=no
RestartIfNeededByRun=no

[Files]
Source: "..\scripts\sync-time.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\scripts\install-task.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\scripts\uninstall-task.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Code]
function QuotePowerShellArgument(const Value: String): String;
begin
  Result := '"' + Value + '"';
end;

procedure RunTaskScript(const ScriptName, AdditionalArguments, OperationName: String);
var
  PowerShellPath: String;
  ScriptPath: String;
  Parameters: String;
  ResultCode: Integer;
begin
  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  ScriptPath := ExpandConstant('{app}\') + ScriptName;
  Parameters := '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' +
    QuotePowerShellArgument(ScriptPath);

  if AdditionalArguments <> '' then
    Parameters := Parameters + ' ' + AdditionalArguments;

  Log(Format('Starting %s with script %s.', [OperationName, ScriptPath]));

  if not Exec(
    PowerShellPath,
    Parameters,
    ExpandConstant('{app}'),
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then
  begin
    RaiseException(
      'Unable to start Windows PowerShell for ' + OperationName + ': ' +
      SysErrorMessage(ResultCode));
  end;

  if ResultCode <> 0 then
  begin
    RaiseException(
      OperationName + ' failed with exit code ' + IntToStr(ResultCode) +
      '. Review the Setup log for details.');
  end;

  Log(Format('%s completed successfully.', [OperationName]));
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  InstallArguments: String;
begin
  if CurStep = ssPostInstall then
  begin
    InstallArguments := '-InstallDirectory ' + QuotePowerShellArgument(ExpandConstant('{app}'));
    RunTaskScript('install-task.ps1', InstallArguments, 'scheduled task registration');
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RunTaskScript('uninstall-task.ps1', '', 'scheduled task removal');
end;
