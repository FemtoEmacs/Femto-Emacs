; sbemacs.nsi -- the SBEmacs setup program for Windows
;
; Built by windows/build-installer.sh, which defines VERSION, STAGE (the
; folder with sbemacs.exe and its files) and OUTDIR.
;
; What the user sees: Welcome, Next; the folder, Install; Finish, with
; "Run SBEmacs" and "Put a shortcut on the desktop" already ticked.
; No administrator rights: everything goes to the user's own programs
; folder and the user's part of the registry (HKCU), as with VS Code or
; Python's per-user installers.

Unicode true
; A 64-bit setup where NSIS has 64-bit stubs (the Linux package does);
; the official Windows NSIS has only 32-bit ones, and build-installer.sh
; passes -DTARGET=x86-unicode there.  Either runs on 64-bit Windows.
!ifndef TARGET
  !define TARGET amd64-unicode
!endif
Target ${TARGET}
SetCompressor /SOLID lzma
ManifestDPIAware true

!ifndef VERSION
  !error "VERSION is not defined: run windows/build-installer.sh"
!endif

!define PRODUCT "SBEmacs"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\SBEmacs"

Name "${PRODUCT} ${VERSION}"
Caption "${PRODUCT} ${VERSION} Setup"
OutFile "${OUTDIR}\SBEmacs-${VERSION}-Windows-x86_64-Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\SBEmacs"
InstallDirRegKey HKCU "${UNINSTALL_KEY}" "InstallLocation"
RequestExecutionLevel user
BrandingText "${PRODUCT} ${VERSION}, Steel Bank Emacs"

VIProductVersion "${VERSION}.0.0"
VIAddVersionKey "ProductName" "${PRODUCT}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "${PRODUCT} Setup"
VIAddVersionKey "LegalCopyright" "Public domain"

!include "MUI2.nsh"

!define MUI_ICON "${__FILEDIR__}\sbemacs.ico"
!define MUI_UNICON "${__FILEDIR__}\sbemacs.ico"
!define MUI_ABORTWARNING
!define MUI_WELCOMEFINISHPAGE_BITMAP "${__FILEDIR__}\welcome.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "${__FILEDIR__}\welcome.bmp"

; The texts are in English and Brazilian Portuguese; Windows picks the
; one of its own language (LangString, after MUI_LANGUAGE below).
!define MUI_WELCOMEPAGE_TITLE "$(WelcomeTitle)"
!define MUI_WELCOMEPAGE_TEXT "$(WelcomeText)"
!insertmacro MUI_PAGE_WELCOME

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_RUN "$INSTDIR\sbemacs.exe"
!define MUI_FINISHPAGE_RUN_TEXT "$(RunNow)"
; the second check box of the finish page, used for the desktop shortcut
!define MUI_FINISHPAGE_SHOWREADME ""
!define MUI_FINISHPAGE_SHOWREADME_TEXT "$(DesktopIcon)"
!define MUI_FINISHPAGE_SHOWREADME_FUNCTION DesktopShortcut
!define MUI_FINISHPAGE_LINK "$(Manual)"
!define MUI_FINISHPAGE_LINK_LOCATION "$INSTDIR\docs\sbemacs.pdf"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "PortugueseBR"

LangString WelcomeTitle ${LANG_ENGLISH} "Welcome to SBEmacs ${VERSION}"
LangString WelcomeTitle ${LANG_PORTUGUESEBR} "Bem-vindo ao SBEmacs ${VERSION}"
LangString WelcomeText ${LANG_ENGLISH} "SBEmacs (Steel Bank Emacs) is a small Emacs-like editor, extended in Common Lisp.$\r$\n$\r$\nIt will be installed for you alone. No administrator rights are needed, and no SBCL: SBCL comes inside SBEmacs.$\r$\n$\r$\nClick Next to continue."
LangString WelcomeText ${LANG_PORTUGUESEBR} "SBEmacs (Steel Bank Emacs) é um pequeno editor no estilo do Emacs, extensível em Common Lisp.$\r$\n$\r$\nEle será instalado só para você. Não são necessários direitos de administrador, nem o SBCL: o SBCL vem dentro do SBEmacs.$\r$\n$\r$\nClique em Próximo para continuar."
LangString RunNow ${LANG_ENGLISH} "Run SBEmacs now"
LangString RunNow ${LANG_PORTUGUESEBR} "Abrir o SBEmacs agora"
LangString DesktopIcon ${LANG_ENGLISH} "Put a shortcut on the desktop"
LangString DesktopIcon ${LANG_PORTUGUESEBR} "Criar um atalho na área de trabalho"
LangString Needs64 ${LANG_ENGLISH} "SBEmacs needs 64-bit Windows."
LangString Needs64 ${LANG_PORTUGUESEBR} "O SBEmacs precisa do Windows de 64 bits."
LangString Manual ${LANG_ENGLISH} "The SBEmacs manual"
LangString Manual ${LANG_PORTUGUESEBR} "O manual do SBEmacs"

!if ${TARGET} == x86-unicode
!include "x64.nsh"
Function .onInit
  ; a 32-bit setup also starts on 32-bit Windows, where SBEmacs cannot run
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "$(Needs64)"
    Abort
  ${EndIf}
FunctionEnd
!endif

Function DesktopShortcut
  SetOutPath "$PROFILE"
  CreateShortCut "$DESKTOP\SBEmacs.lnk" "$INSTDIR\sbemacs.exe" "" "$INSTDIR\sbemacs.ico"
FunctionEnd

Section "SBEmacs" SecMain
  SectionIn RO
  SetOutPath "$INSTDIR"
  ; files of an older version that this one no longer has
  RMDir /r "$INSTDIR\lisp"

  File "${STAGE}\sbemacs.exe"
  File "${STAGE}\libsbemacs-gui.dll"
  File "${STAGE}\SDL2.dll"
  File "${STAGE}\SDL2_ttf.dll"
  File "${STAGE}\README.md"
  File "${STAGE}\CHANGE.LOG.md"
  File "${__FILEDIR__}\sbemacs.ico"
  File /r "${STAGE}\lisp"
  File /r "${STAGE}\fonts"
  File /r "${STAGE}\docs"
  File /r "${STAGE}\samples"

  WriteUninstaller "$INSTDIR\Uninstall SBEmacs.exe"

  ; Start menu; SBEmacs starts in the user's folder, as Emacs starts in ~
  SetOutPath "$PROFILE"
  CreateShortCut "$SMPROGRAMS\SBEmacs.lnk" "$INSTDIR\sbemacs.exe" "" "$INSTDIR\sbemacs.ico"
  CreateShortCut "$SMPROGRAMS\SBEmacs manual.lnk" "$INSTDIR\docs\sbemacs.pdf"

  ; Settings > Apps lists it, and can remove it
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "SBEmacs ${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "SBEmacs"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "URLInfoAbout" "https://github.com/FemtoEmacs/Femto-Emacs"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\sbemacs.ico"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall SBEmacs.exe"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall SBEmacs.exe" /S'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "EstimatedSize" 80000

  ; "Open with > SBEmacs" for any text file; no file type is taken over
  WriteRegStr HKCU "Software\Classes\Applications\sbemacs.exe" "FriendlyAppName" "SBEmacs"
  WriteRegStr HKCU "Software\Classes\Applications\sbemacs.exe\DefaultIcon" "" "$INSTDIR\sbemacs.ico"
  WriteRegStr HKCU "Software\Classes\Applications\sbemacs.exe\shell\open\command" "" '"$INSTDIR\sbemacs.exe" "%1"'
  WriteRegStr HKCU "Software\Classes\.txt\OpenWithList\sbemacs.exe" "" ""
  WriteRegStr HKCU "Software\Classes\.md\OpenWithList\sbemacs.exe" "" ""
  WriteRegStr HKCU "Software\Classes\.lisp\OpenWithList\sbemacs.exe" "" ""
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\SBEmacs.lnk"
  Delete "$SMPROGRAMS\SBEmacs manual.lnk"
  Delete "$DESKTOP\SBEmacs.lnk"

  ; only what setup put there: the folder may have been chosen by hand
  Delete "$INSTDIR\sbemacs.exe"
  Delete "$INSTDIR\libsbemacs-gui.dll"
  Delete "$INSTDIR\SDL2.dll"
  Delete "$INSTDIR\SDL2_ttf.dll"
  Delete "$INSTDIR\README.md"
  Delete "$INSTDIR\CHANGE.LOG.md"
  Delete "$INSTDIR\sbemacs.ico"
  RMDir /r "$INSTDIR\lisp"
  RMDir /r "$INSTDIR\fonts"
  RMDir /r "$INSTDIR\docs"
  RMDir /r "$INSTDIR\samples"
  Delete "$INSTDIR\Uninstall SBEmacs.exe"
  RMDir "$INSTDIR"

  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  DeleteRegKey HKCU "Software\Classes\Applications\sbemacs.exe"
  DeleteRegKey HKCU "Software\Classes\.txt\OpenWithList\sbemacs.exe"
  DeleteRegKey HKCU "Software\Classes\.md\OpenWithList\sbemacs.exe"
  DeleteRegKey HKCU "Software\Classes\.lisp\OpenWithList\sbemacs.exe"
  ; the user's own ~/.sbemacs (init.lisp, extensions) is theirs: kept
SectionEnd
