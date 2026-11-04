Unicode true
!include "MUI2.nsh"
Name "Chezweb"
OutFile "Chezweb-Windows-x86_64-Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\Chezweb"
RequestExecutionLevel user
SetCompressor /SOLID lzma
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
Section "Chezweb"
 SetOutPath "$INSTDIR"
 File /r "stage\*.*"
 WriteUninstaller "$INSTDIR\Uninstall.exe"
 CreateDirectory "$SMPROGRAMS\Chezweb"
 CreateShortcut "$SMPROGRAMS\Chezweb\Chezweb.lnk" "$INSTDIR\bin\mintty.exe" '-t Chezweb /bin/bash --noprofile --norc /app/start.sh'
 CreateShortcut "$SMPROGRAMS\Chezweb\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
 CreateShortcut "$SMPROGRAMS\Chezweb\Chezweb GUI.lnk" "$INSTDIR\bin\chezweb-gui-launch.exe"
 WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Chezweb" "DisplayName" "Chezweb"
 WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Chezweb" "UninstallString" '$"$INSTDIR\Uninstall.exe$"'
 WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Chezweb" "InstallLocation" "$INSTDIR"
SectionEnd
Section "Uninstall"
 Delete "$SMPROGRAMS\Chezweb\Chezweb.lnk"
 Delete "$SMPROGRAMS\Chezweb\Chezweb GUI.lnk"
 Delete "$SMPROGRAMS\Chezweb\Uninstall.lnk"
 RMDir "$SMPROGRAMS\Chezweb"
 DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Chezweb"
 # Remove installed files only; never the user's .chezemax scripts or documents.
 RMDir /r "$INSTDIR\app"
 RMDir /r "$INSTDIR\bin"
 RMDir /r "$INSTDIR\usr"
 RMDir /r "$INSTDIR\etc"
 RMDir /r "$INSTDIR\licenses"
 RMDir /r "$INSTDIR\tmp"
 Delete "$INSTDIR\Uninstall.exe"
 RMDir "$INSTDIR"
SectionEnd
