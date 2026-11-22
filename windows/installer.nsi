Unicode true
!include "MUI2.nsh"
!ifndef CHEZWEB_VERSION
!error "Supply CHEZWEB_VERSION from src/header.h through build-installer.sh"
!endif
Name "Chezweb ${CHEZWEB_VERSION}"
VIProductVersion "${CHEZWEB_VERSION}.0.0"
VIAddVersionKey "ProductName" "Chezweb"
VIAddVersionKey "ProductVersion" "${CHEZWEB_VERSION}"
VIAddVersionKey "FileDescription" "Chezweb installer"
VIAddVersionKey "FileVersion" "${CHEZWEB_VERSION}.0.0"
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
 WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Chezweb" "DisplayName" "Chezweb ${CHEZWEB_VERSION}"
 WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Chezweb" "DisplayVersion" "${CHEZWEB_VERSION}"
 WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Chezweb" "UninstallString" '"$INSTDIR\Uninstall.exe"'
 WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Chezweb" "InstallLocation" "$INSTDIR"
 nsExec::ExecToLog '"$INSTDIR\bin\chezweb-user-path.exe" add "$INSTDIR\command"'
 Pop $0
 StrCmp $0 0 path_install_done
 DetailPrint "Could not add Chezweb to PATH (status $0). Open Chezweb from the Start menu."
 IfSilent path_install_done
 MessageBox MB_OK|MB_ICONEXCLAMATION "Chezweb was installed. Setup could not add the command to your PATH (status $0). Open Chezweb from the Start menu."
 path_install_done:
SectionEnd
Section "Uninstall"
 nsExec::ExecToLog '"$INSTDIR\bin\chezweb-user-path.exe" remove "$INSTDIR\command"'
 Pop $0
 StrCmp $0 0 path_remove_done
 DetailPrint "Could not remove $INSTDIR\command from PATH (status $0)."
 IfSilent path_remove_done
 MessageBox MB_OK|MB_ICONEXCLAMATION "The Chezweb PATH entry could not be removed (status $0). You can remove $INSTDIR\command from your user PATH."
 path_remove_done:
 Delete "$SMPROGRAMS\Chezweb\Chezweb.lnk"
 Delete "$SMPROGRAMS\Chezweb\Chezweb GUI.lnk"
 Delete "$SMPROGRAMS\Chezweb\Uninstall.lnk"
 RMDir "$SMPROGRAMS\Chezweb"
 DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Chezweb"
 # Remove installed files only; never the user's .chezemax scripts or documents.
 RMDir /r "$INSTDIR\app"
 RMDir /r "$INSTDIR\bin"
 Delete "$INSTDIR\command\chezweb.cmd"
 RMDir "$INSTDIR\command"
 RMDir /r "$INSTDIR\usr"
 RMDir /r "$INSTDIR\etc"
 RMDir /r "$INSTDIR\licenses"
 RMDir /r "$INSTDIR\tmp"
 Delete "$INSTDIR\Uninstall.exe"
 RMDir "$INSTDIR"
SectionEnd
