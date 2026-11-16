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
 ClearErrors
 ExecWait '$"$INSTDIR\bin\chezweb-user-path.exe$" add $"$INSTDIR\command$"' $0
 IfErrors path_install_failed
 StrCmp $0 0 path_install_done
 path_install_failed:
   Abort "Cannot add the Chezweb command to your PATH."
 path_install_done:
SectionEnd
Section "Uninstall"
 ClearErrors
 ExecWait '$"$INSTDIR\bin\chezweb-user-path.exe$" remove $"$INSTDIR\command$"' $0
 IfErrors path_remove_failed
 StrCmp $0 0 path_remove_done
 path_remove_failed:
   Abort "Cannot remove the Chezweb command from your PATH."
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
