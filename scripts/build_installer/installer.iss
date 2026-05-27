; scripts/build_installer/installer.iss
;
; Genshin Impact Wish Gacha Analyzer — Inno Setup 安裝檔
;
; 編譯方式：
;   ISCC.exe /DMyAppVersion=1.0.0 scripts\build_installer\installer.iss
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
VersionInfoVersion={#MyAppVersion}
VersionInfoProductVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppCopyright=Copyright (C) 2020-{#GetDateTimeString('yyyy','','')} {#MyAppPublisher}
DefaultDirName={commonpf}\Genshin_Impact_Wish_Gacha_Analyzer
DefaultGroupName={#MyAppName}
DisableDirPage=no
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
Compression=lzma2/ultra
SolidCompression=yes
WizardStyle=modern
OutputDir=..\..\build\installer
OutputBaseFilename=Genshin_Impact_Wish_Gacha_Analyzer-Setup-{#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "armenian"; MessagesFile: "compiler:Languages\Armenian.isl"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "bulgarian"; MessagesFile: "compiler:Languages\Bulgarian.isl"
Name: "catalan"; MessagesFile: "compiler:Languages\Catalan.isl"
Name: "corsican"; MessagesFile: "compiler:Languages\Corsican.isl"
Name: "czech"; MessagesFile: "compiler:Languages\Czech.isl"
Name: "danish"; MessagesFile: "compiler:Languages\Danish.isl"
Name: "dutch"; MessagesFile: "compiler:Languages\Dutch.isl"
Name: "finnish"; MessagesFile: "compiler:Languages\Finnish.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "hebrew"; MessagesFile: "compiler:Languages\Hebrew.isl"
Name: "hungarian"; MessagesFile: "compiler:Languages\Hungarian.isl"
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
Name: "norwegian"; MessagesFile: "compiler:Languages\Norwegian.isl"
Name: "polish"; MessagesFile: "compiler:Languages\Polish.isl"
Name: "portuguese"; MessagesFile: "compiler:Languages\Portuguese.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "slovak"; MessagesFile: "compiler:Languages\Slovak.isl"
Name: "slovenian"; MessagesFile: "compiler:Languages\Slovenian.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "swedish"; MessagesFile: "compiler:Languages\Swedish.isl"
Name: "tamil"; MessagesFile: "compiler:Languages\Tamil.isl"
Name: "thai"; MessagesFile: "compiler:Languages\Thai.isl"
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "ukrainian"; MessagesFile: "compiler:Languages\Ukrainian.isl"
Name: "simpchinese"; MessagesFile: "ChineseSimplified.isl"
Name: "tradchinese"; MessagesFile: "ChineseTraditional.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
    Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; \
    Flags: nowait postinstall skipifsilent

[CustomMessages]
UninstallRemoveDataBody=Also remove user data?%n%nThis will permanently delete the contents of:%n%1%n%nincluding banner records, settings, caches and logs. This cannot be undone.
tradchinese.UninstallRemoveDataBody=是否要同時移除使用者資料？%n%n將永久刪除位於以下目錄的所有內容：%n%1%n%n包含卡池記錄、設定、快取與 log。此操作無法復原。
simpchinese.UninstallRemoveDataBody=是否要同时移除用户数据？%n%n将永久删除位于以下目录的所有内容：%n%1%n%n包含卡池记录、设定、缓存与 log。此操作无法复原。

[Code]
const
  UninstallPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';
  DisplayNameNeedle = 'Genshin Impact Wish Gacha Analyzer';
  // 新版自己的 Inno Setup 卸載 key 名稱（用於排除），格式固定為 "{AppId}_is1"
  SelfUninstKey = '{#MyAppId}_is1';

var
  // 解除安裝期間記錄使用者是否選擇連同移除 %APPDATA% 內的使用者資料。
  // usUninstall 階段由 MsgBox 設定，usPostUninstall 階段讀取以決定是否 DelTree。
  // Inno Setup 啟動 uninstaller process 時 Pascal Boolean 預設為 False，符合「預設不刪」語意。
  ShouldRemoveUserData: Boolean;

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
    else if ActiveLanguage() = 'simpchinese' then
      Msg := '检测到已安装的旧版本 (Electron 版)，是否要先卸载旧版本再继续安装新版本？' + #13#10#13#10 +
             '单击“否”将取消安装。'
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

// 解除安裝流程：usUninstall 階段詢問使用者是否同時移除使用者資料，
// usPostUninstall 階段依旗標執行 DelTree（主程式檔已被卸載，避免 file lock）。
// silent 模式（/VERYSILENT、/SILENT）下 MsgBox 自動回傳預設按鈕值 = IDNO，
// 結果與「預設不勾」一致。
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  UserDataDir: String;
begin
  UserDataDir := ExpandConstant('{userappdata}\tw.reh\genshin_impact_wish_gacha_analyzer');
  case CurUninstallStep of
    usUninstall:
      begin
        ShouldRemoveUserData :=
          MsgBox(
            FmtMessage(CustomMessage('UninstallRemoveDataBody'), [UserDataDir]),
            mbConfirmation,
            MB_YESNO or MB_DEFBUTTON2
          ) = IDYES;
      end;
    usPostUninstall:
      begin
        if ShouldRemoveUserData then
        begin
          if not DelTree(UserDataDir, True, True, True) then
            Log('uninstall: DelTree failed for ' + UserDataDir);
        end;
      end;
  end;
end;
