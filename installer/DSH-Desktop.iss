#ifndef AppVersion
  #error AppVersion must be supplied with /DAppVersion=x.y.z
#endif
#ifndef BundleDir
  #error BundleDir must be supplied with /DBundleDir=absolute-path
#endif
#ifndef OutputDir
  #error OutputDir must be supplied with /DOutputDir=absolute-path
#endif
#ifndef Architecture
  #define Architecture "win-x64"
#endif

#define AppIdValue "{4F7C99E8-61F5-4D6D-B44D-AC78038BEF84}"
#define AppMutexValue "Local\DeepSeekHarnessOfficialDesktopLauncher"
#define AppExeName "DSH-Desktop.exe"

[Setup]
AppId={{#AppIdValue}
AppName=DSH Desktop
AppVersion={#AppVersion}
AppVerName=DSH Desktop {#AppVersion}
AppPublisher=DSH Desktop contributors
AppPublisherURL=https://github.com/followTheWind223/dsh-Desktop
AppSupportURL=https://github.com/followTheWind223/dsh-Desktop/issues
AppUpdatesURL=https://github.com/followTheWind223/dsh-Desktop/releases
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany=DSH Desktop contributors
VersionInfoDescription=DSH Desktop bundled installer
VersionInfoProductName=DSH Desktop
DefaultDirName={localappdata}\Programs\DSH Desktop
DefaultGroupName=DSH Desktop
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=DSH-Desktop-Setup-v{#AppVersion}-{#Architecture}
SetupIconFile={#BundleDir}\assets\deepseek-harness.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2/fast
SolidCompression=yes
LZMAUseSeparateProcess=yes
WizardStyle=modern
ShowLanguageDialog=auto
CloseApplications=yes
RestartApplications=no
AppMutex={#AppMutexValue}
SetupLogging=yes
UsePreviousAppDir=yes
UsePreviousLanguage=yes
UsePreviousTasks=yes
ChangesAssociations=no
ChangesEnvironment=no
#if Architecture == "win-arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif

[Languages]
Name: "zhcn"; MessagesFile: "compiler:Default.isl,ChineseSimplified.partial.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
zhcn.DesktopTask=创建桌面快捷方式
en.DesktopTask=Create a desktop shortcut
zhcn.UnsafeSourceDirectory=所选目录看起来是一个源代码仓库。为防止覆盖项目文件，请选择一个新的或专用的安装目录。
en.UnsafeSourceDirectory=The selected directory appears to be a source checkout. Choose a new or dedicated installation directory so project files are not overwritten.
zhcn.RemoveUserData=DSH Desktop、内置 DeepSeek Harness 和内置 Node.js 将被删除。%n%n是否同时永久删除用户数据和会话？%n%n选择“否”会保留：%n%1
en.RemoveUserData=DSH Desktop, its bundled DeepSeek Harness, and its private Node.js runtime will be removed.%n%nAlso permanently delete user data and sessions?%n%nChoose No to keep:%n%1
zhcn.DataDeleteFailed=用户数据未能完全删除，请手动检查：%n%1
en.DataDeleteFailed=User data could not be removed completely. Check this location manually:%n%1
zhcn.WebViewInstallFailed=Microsoft Edge WebView2 Runtime 安装失败。DSH Desktop 可能无法启动；可稍后重新运行本安装程序进行修复。
en.WebViewInstallFailed=Microsoft Edge WebView2 Runtime installation failed. DSH Desktop may not start; rerun this installer later to repair it.

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopTask}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Excludes: "runtime-manifest.json"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#BundleDir}\runtime-manifest.json"; DestDir: "{app}"; Flags: ignoreversion; AfterInstall: WriteLauncherConfiguration

[Dirs]
Name: "{app}\data"; Flags: uninsneveruninstall

[Icons]
Name: "{group}\DSH Desktop"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{group}\卸载 DSH Desktop"; Filename: "{uninstallexe}"; Check: IsChinese
Name: "{group}\Uninstall DSH Desktop"; Filename: "{uninstallexe}"; Check: IsEnglish
Name: "{autodesktop}\DSH Desktop"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\redist\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; StatusMsg: "Installing Microsoft Edge WebView2 Runtime..."; Flags: runhidden waituntilterminated; Check: WebView2NeedsInstall; AfterInstall: VerifyWebView2Install
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,DSH Desktop}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: files; Name: "{app}\launcher.config.json"
Type: files; Name: "{app}\launcher.config.json.tmp"

[Code]
const
  WebView2ClientGuid = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';
  FileAttributeReparsePoint = $400;
  InvalidFileAttributes = $FFFFFFFF;

var
  DeleteUserData: Boolean;

function GetFileAttributes(FileName: String): Cardinal;
  external 'GetFileAttributesW@kernel32.dll stdcall';

function IsChinese: Boolean;
begin
  Result := ActiveLanguage = 'zhcn';
end;

function IsEnglish: Boolean;
begin
  Result := not IsChinese;
end;

function JsonEscape(Value: String): String;
begin
  Result := Value;
  StringChangeEx(Result, '\', '\\', True);
  StringChangeEx(Result, '"', '\"', True);
  StringChangeEx(Result, #13, '\r', True);
  StringChangeEx(Result, #10, '\n', True);
  StringChangeEx(Result, #9, '\t', True);
end;

function IsSourceCheckout(Path: String): Boolean;
begin
  Result :=
    DirExists(AddBackslash(Path) + '.git') or
    DirExists(AddBackslash(Path) + '.github') or
    (DirExists(AddBackslash(Path) + 'src') and
      (FileExists(AddBackslash(Path) + 'package.json') or
       FileExists(AddBackslash(Path) + 'Build-Exe.ps1')));
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = wpSelectDir) and IsSourceCheckout(WizardDirValue) then
  begin
    MsgBox(ExpandConstant('{cm:UnsafeSourceDirectory}'), mbError, MB_OK);
    Result := False;
  end;
end;

procedure WriteLauncherConfiguration;
var
  ConfigPath: String;
  TempPath: String;
  LanguageValue: String;
  Json: String;
begin
  if IsChinese then
    LanguageValue := 'zh-CN'
  else
    LanguageValue := 'en-US';

  ConfigPath := ExpandConstant('{app}\launcher.config.json');
  TempPath := ConfigPath + '.tmp';
  Json :=
    '{' + #13#10 +
    '  "SchemaVersion": 2,' + #13#10 +
    '  "HarnessDir": "' + JsonEscape(ExpandConstant('{app}\runtime\harness')) + '",' + #13#10 +
    '  "DataDir": "' + JsonEscape(ExpandConstant('{app}\data')) + '",' + #13#10 +
    '  "NodePath": "' + JsonEscape(ExpandConstant('{app}\runtime\node\node.exe')) + '",' + #13#10 +
    '  "Language": "' + LanguageValue + '",' + #13#10 +
    '  "HarnessManaged": true,' + #13#10 +
    '  "DataManaged": true,' + #13#10 +
    '  "NodeManaged": true' + #13#10 +
    '}' + #13#10;

  DeleteFile(TempPath);
  if not SaveStringToFile(TempPath, Json, False) then
    RaiseException('Unable to write launcher.config.json.tmp.');
  DeleteFile(ConfigPath);
  if not RenameFile(TempPath, ConfigPath) then
    RaiseException('Unable to activate launcher.config.json.');
end;

function WebView2VersionInRoot(RootKey: Integer): String;
var
  Key: String;
begin
  Key := 'Software\Microsoft\EdgeUpdate\Clients\' + WebView2ClientGuid;
  RegQueryStringValue(RootKey, Key, 'pv', Result);
end;

function IsUsableWebView2Version(Version: String): Boolean;
begin
  Result := (Version <> '') and (Version <> '0.0.0.0');
end;

function WebView2Installed: Boolean;
begin
  Result :=
    IsUsableWebView2Version(WebView2VersionInRoot(HKLM64)) or
    IsUsableWebView2Version(WebView2VersionInRoot(HKLM32)) or
    IsUsableWebView2Version(WebView2VersionInRoot(HKCU64)) or
    IsUsableWebView2Version(WebView2VersionInRoot(HKCU32));
end;

function WebView2NeedsInstall: Boolean;
begin
  Result := not WebView2Installed;
end;

procedure VerifyWebView2Install;
begin
  if not WebView2Installed then
  begin
    if WizardSilent then
      Log(ExpandConstant('{cm:WebViewInstallFailed}'))
    else
      MsgBox(ExpandConstant('{cm:WebViewInstallFailed}'), mbError, MB_OK);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataPath: String;
  Attributes: Cardinal;
begin
  DataPath := ExpandConstant('{app}\data');
  if CurUninstallStep = usUninstall then
  begin
    if UninstallSilent then
      DeleteUserData := False
    else
      DeleteUserData := MsgBox(
        FmtMessage(ExpandConstant('{cm:RemoveUserData}'), [DataPath]),
        mbConfirmation,
        MB_YESNO or MB_DEFBUTTON2) = IDYES;
  end;

  if (CurUninstallStep = usPostUninstall) and DeleteUserData and DirExists(DataPath) then
  begin
    Attributes := GetFileAttributes(DataPath);
    if (Attributes <> InvalidFileAttributes) and
       ((Attributes and FileAttributeReparsePoint) = 0) and
       (CompareText(RemoveBackslashUnlessRoot(DataPath),
         RemoveBackslashUnlessRoot(ExpandConstant('{app}\data'))) = 0) then
    begin
      if (not DelTree(DataPath, True, True, True)) and DirExists(DataPath) then
        MsgBox(FmtMessage(ExpandConstant('{cm:DataDeleteFailed}'), [DataPath]), mbError, MB_OK);
    end;
  end;
end;
