Unicode true

!include "LogicLib.nsh"
!include "MUI2.nsh"
!include "x64.nsh"

!ifndef APP_VERSION
!define APP_VERSION "1.0.0"
!endif

!ifndef TARGET_ARCHITECTURE
!error "TARGET_ARCHITECTURE must be defined as x64 or arm64."
!endif

!ifndef OUTPUT_FILE
!error "OUTPUT_FILE must be defined."
!endif

!if "${TARGET_ARCHITECTURE}" != "x64"
!if "${TARGET_ARCHITECTURE}" != "arm64"
!error "Unsupported TARGET_ARCHITECTURE. Expected x64 or arm64."
!endif
!endif

!define APP_NAME "WinTime"
!define APP_PUBLISHER "firebadnofire"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\WinTime"

Name "${APP_NAME}"
OutFile "${OUTPUT_FILE}"
InstallDir "$PROGRAMFILES64\${APP_NAME}"
InstallDirRegKey HKLM "${UNINSTALL_KEY}" "InstallLocation"
RequestExecutionLevel admin
ManifestSupportedOS all
SetCompressor /SOLID lzma
ShowInstDetails show
ShowUninstDetails show

VIProductVersion "${APP_VERSION}.0"
VIAddVersionKey /LANG=1033 "ProductName" "${APP_NAME}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1033 "FileVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1033 "CompanyName" "${APP_PUBLISHER}"
VIAddVersionKey /LANG=1033 "FileDescription" "WinTime installer (${TARGET_ARCHITECTURE})"
VIAddVersionKey /LANG=1033 "LegalCopyright" "Copyright (c) 2026 ${APP_PUBLISHER}"

!define MUI_ABORTWARNING
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\modern-install.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\modern-uninstall.ico"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "..\LICENSE"
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP|MB_OK "WinTime requires 64-bit Windows."
    Abort
  ${EndIf}

!if "${TARGET_ARCHITECTURE}" == "x64"
  ${IfNot} ${IsNativeAMD64}
    MessageBox MB_ICONSTOP|MB_OK "This installer is for x64 Windows. Use the ARM64 installer on Windows ARM64."
    Abort
  ${EndIf}
!else
  ${IfNot} ${IsNativeARM64}
    MessageBox MB_ICONSTOP|MB_OK "This installer is for Windows ARM64. Use the x64 installer on x64 Windows."
    Abort
  ${EndIf}
!endif
FunctionEnd

Section "Install"
  SetShellVarContext all
  SetRegView 64
  SetOutPath "$INSTDIR"

  File "..\scripts\sync-time.ps1"
  File "..\scripts\install-task.ps1"
  File "..\scripts\uninstall-task.ps1"

  ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "$INSTDIR\install-task.ps1" -InstallDirectory "$INSTDIR"' $0
  ${If} $0 != 0
    Delete "$INSTDIR\sync-time.ps1"
    Delete "$INSTDIR\install-task.ps1"
    Delete "$INSTDIR\uninstall-task.ps1"
    RMDir "$INSTDIR"
    MessageBox MB_ICONSTOP|MB_OK "Scheduled task registration failed with exit code $0. Installation was not completed."
    Abort
  ${EndIf}

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  SetShellVarContext all
  SetRegView 64

  ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "$INSTDIR\uninstall-task.ps1"' $0
  ${If} $0 != 0
    MessageBox MB_ICONSTOP|MB_OK "Scheduled task removal failed with exit code $0. Uninstallation was not completed."
    Abort
  ${EndIf}

  DeleteRegKey HKLM "${UNINSTALL_KEY}"
  Delete "$INSTDIR\sync-time.ps1"
  Delete "$INSTDIR\install-task.ps1"
  Delete "$INSTDIR\uninstall-task.ps1"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
