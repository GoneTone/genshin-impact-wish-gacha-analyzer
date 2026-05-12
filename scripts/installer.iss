; scripts/installer.iss
;
; Genshin Impact Wish Gacha Analyzer — Inno Setup 安裝檔
;
; 編譯方式：
;   ISCC.exe /DMyAppVersion=1.0.0 scripts\installer.iss
;
; AppId 為固定 GUID，任何情況下不得變更（會破壞升級路徑）。

#define MyAppId       "{50C50DF7-CB14-4D51-9618-0E5116DDA065}"
#define MyAppName     "Genshin Impact Wish Gacha Analyzer"
#define MyAppExeName  "genshin_impact_wish_gacha_analyzer.exe"
#define MyAppPublisher "原神資訊站 Genshin Impact Info"
#define MyAppURL      "https://genshininfo.reh.tw/"

; MyAppVersion 透過 ISCC /DMyAppVersion=... 從外面傳入
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

[Setup]
AppId={{#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppCopyright=Copyright (C) 2020-{#GetDateTimeString('yyyy','','')} {#MyAppPublisher}
DefaultDirName={commonpf}\Genshin_Impact_Wish_Gacha_Analyzer
DefaultGroupName={#MyAppName}
DisableDirPage=no
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
Compression=lzma2/ultra
SolidCompression=yes
WizardStyle=modern
OutputDir=..\build\installer
OutputBaseFilename=Genshin_Impact_Wish_Gacha_Analyzer-Setup-{#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "tradchinese"; MessagesFile: "ChineseTraditional.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
    Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; \
    Flags: nowait postinstall skipifsilent

[Code]
const
  UninstallPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';
  DisplayNameNeedle = 'Genshin Impact Wish Gacha Analyzer';
  // 新版自己的 Inno Setup 卸載 key 名稱（用於排除），格式固定為 "{AppId}_is1"
  SelfUninstKey = '{#MyAppId}_is1';

// 收集所有判定為「舊版」的 UninstallString
procedure CollectOldUninstallers(RootKey: Integer; const SubPath: String; List: TStringList);
var
  SubKeys: TArrayOfString;
  i: Integer;
  KeyName, FullPath, DisplayName, UninstallString: String;
begin
  if not RegGetSubkeyNames(RootKey, SubPath, SubKeys) then
    Exit;
  for i := 0 to GetArrayLength(SubKeys) - 1 do
  begin
    KeyName := SubKeys[i];
    if SameText(KeyName, SelfUninstKey) then
      Continue;
    FullPath := SubPath + '\' + KeyName;
    if not RegQueryStringValue(RootKey, FullPath, 'DisplayName', DisplayName) then
      Continue;
    if Pos(DisplayNameNeedle, DisplayName) = 0 then
      Continue;
    if not RegQueryStringValue(RootKey, FullPath, 'UninstallString', UninstallString) then
      Continue;
    if Trim(UninstallString) = '' then
      Continue;
    List.Add(UninstallString);
  end;
end;

function GetOldUninstallers(): TStringList;
begin
  Result := TStringList.Create;
  Result.Duplicates := dupIgnore;
  Result.Sorted := True;
  CollectOldUninstallers(HKLM32, UninstallPath, Result);
  CollectOldUninstallers(HKLM64, UninstallPath, Result);
  CollectOldUninstallers(HKCU,   UninstallPath, Result);
end;

// 解析 UninstallString，拆出 exe 路徑與額外參數
procedure ParseUninstallCommand(const Cmd: String; var ExePath, ExtraArgs: String);
var
  Trimmed: String;
  EndQuote: Integer;
begin
  Trimmed := Trim(Cmd);
  ExtraArgs := '';
  if (Length(Trimmed) > 0) and (Trimmed[1] = '"') then
  begin
    EndQuote := Pos('"', Copy(Trimmed, 2, Length(Trimmed))) + 1;
    if EndQuote > 1 then
    begin
      ExePath := Copy(Trimmed, 2, EndQuote - 2);
      ExtraArgs := Trim(Copy(Trimmed, EndQuote + 1, Length(Trimmed)));
    end
    else
      ExePath := Trimmed;
  end
  else
  begin
    ExePath := Trimmed;
  end;
end;

function RunOldUninstaller(const UninstallString: String): Boolean;
var
  ExePath, ExtraArgs, Params: String;
  ResultCode: Integer;
begin
  ParseUninstallCommand(UninstallString, ExePath, ExtraArgs);
  // NSIS 靜默卸載 + 全機器；若舊版 uninstaller 不認得，參數會被忽略
  Params := '/S /allusers';
  if ExtraArgs <> '' then
    Params := ExtraArgs + ' ' + Params;
  // 新版本身已 admin，直接執行舊版 uninstaller 不需要再提權
  Result := ShellExec('', ExePath, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function InitializeSetup(): Boolean;
var
  Olds: TStringList;
  i: Integer;
  Msg: String;
begin
  Result := True;
  Olds := GetOldUninstallers();
  try
    if Olds.Count = 0 then
      Exit;

    if ActiveLanguage() = 'tradchinese' then
      Msg := '偵測到已安裝的舊版本 (Electron 版)，是否要先移除舊版本再繼續安裝新版本？' + #13#10#13#10 +
             '按「否」將取消安裝。'
    else
      Msg := 'An older version (Electron-based) was detected. Uninstall it before continuing?' + #13#10#13#10 +
             'Selecting No will cancel the installation.';

    if MsgBox(Msg, mbConfirmation, MB_YESNO) <> IDYES then
    begin
      Result := False;
      Exit;
    end;

    for i := 0 to Olds.Count - 1 do
      RunOldUninstaller(Olds[i]);
    // 不檢查每個 RunOldUninstaller 的回傳：
    // 若 uninstaller 不存在（殘留註冊表項）→ ShellExec 失敗，但舊版已壞，讓新版蓋過去
  finally
    Olds.Free;
  end;
end;
