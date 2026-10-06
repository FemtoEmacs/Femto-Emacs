#ifndef StagingDir
  #error StagingDir must name the directory produced by make dist
#endif

#ifndef OutputDir
  #define OutputDir "."
#endif

#define AppName "Femto Emacs"
#define AppVersion "2.0"
#define AppPublisher "FemtoEmacs contributors"
#define AppExeName "sbemacs.exe"

[Setup]
AppId={{D82573F6-39CE-469B-81DF-92F0DB42C256}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\Femto Emacs
DefaultGroupName=Femto Emacs
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=Femto-Emacs-{#AppVersion}-Windows-x86_64-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExeName}
VersionInfoVersion=2.0.0.0
VersionInfoDescription=Femto Emacs installer
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}

[Files]
; The release executable is deliberately omitted.  configure.ps1 creates it
; with the user's separately installed SBCL 2.6.9.
Source: "{#StagingDir}\*"; DestDir: "{app}"; Excludes: "sbemacs.exe"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Femto Emacs"; Filename: "{app}\{#AppExeName}"; Parameters: "--gui"; WorkingDir: "{userdocs}"
Name: "{autodesktop}\Femto Emacs"; Filename: "{app}\{#AppExeName}"; Parameters: "--gui"; WorkingDir: "{userdocs}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Run]
Filename: "{app}\{#AppExeName}"; Parameters: "--gui"; Description: "Launch Femto Emacs"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  PowerShell, Arguments: String;
begin
  if CurStep = ssPostInstall then
  begin
    PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
    Arguments := '-NoProfile -ExecutionPolicy Bypass -File "' +
      ExpandConstant('{app}\windows\configure.ps1') + '"';
    if not Exec(PowerShell, Arguments, ExpandConstant('{app}'),
      SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      RaiseException('Could not start SBCL configuration.');
    if ResultCode <> 0 then
      RaiseException('Femto Emacs could not be created with SBCL 2.6.9. ' +
        'Install the official 64-bit SBCL 2.6.9 release and run this installer again.');
  end;
end;
