; LLMCleaner - Inno Setup installer
; Built by GitHub Actions (.github/workflows/release.yml):
;   ISCC.exe /DAppVersion=1.0.0 installer\LLMCleaner.iss

#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif

#define AppName "LLMCleaner"
#define AppPublisher "Banzamel"
#define AppURL "https://github.com/Banzamel/LLMCleaner"

[Setup]
AppId={{6F3C2B1E-8A4D-4E7B-9C51-2D7E0F4A9B63}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Per-user install by default (no admin needed); the dialog lets the user pick "all users"
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
LicenseFile=..\LICENSE
SetupIconFile=..\LLMCleaner.ico
UninstallDisplayIcon={app}\LLMCleaner.ico
UninstallDisplayName={#AppName}
OutputDir=..\dist
OutputBaseFilename=LLMCleaner-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=auto
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "polish"; MessagesFile: "compiler:Languages\Polish.isl"

[CustomMessages]
english.AiGroup=AI assistant (optional):
english.AiTask=Install the AI assistant into the program folder (downloads about 4-7 GB)
english.ModelTitle=AI model
english.ModelDesc=Choose the local model used by the assistant.
english.ModelSub=The AI engine (Ollama, 1.4 GB) and the model are stored in the program folder and removed on uninstall. The assistant only explains leftovers and answers questions - cleaning works without it.
english.Model4b=qwen3:4b-instruct - recommended, fast, fits GPUs with 6 GB VRAM (2.5 GB download)
english.Model8b=qwen3:8b - smarter, needs about 8 GB VRAM, slower on smaller GPUs (5.2 GB download)
english.RunAi=Setting up the AI assistant (Ollama + model)...
english.Launch=Launch LLMCleaner in preview mode (nothing is deleted)
english.Docs=Read the documentation
english.ShortPreview=preview
english.ShortConsole=console

polish.AiGroup=Asystent AI (opcjonalnie):
polish.AiTask=Zainstaluj asystenta AI w folderze programu (pobiera ok. 4-7 GB)
polish.ModelTitle=Model AI
polish.ModelDesc=Wybierz lokalny model używany przez asystenta.
polish.ModelSub=Silnik AI (Ollama, 1,4 GB) i model trafiają do folderu programu i są usuwane przy odinstalowaniu. Asystent tylko wyjaśnia pozostałości i odpowiada na pytania - czyszczenie działa bez niego.
polish.Model4b=qwen3:4b-instruct - zalecany, szybki, mieści się w kartach z 6 GB VRAM (2,5 GB)
polish.Model8b=qwen3:8b - mądrzejszy, potrzebuje ok. 8 GB VRAM, wolniejszy na słabszych kartach (5,2 GB)
polish.RunAi=Instaluję asystenta AI (Ollama + model)...
polish.Launch=Uruchom LLMCleaner w trybie podglądu (nic nie zostanie usunięte)
polish.Docs=Otwórz dokumentację
polish.ShortPreview=podgląd
polish.ShortConsole=konsola

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "ai"; Description: "{cm:AiTask}"; GroupDescription: "{cm:AiGroup}"

[Files]
Source: "..\LLMCleaner.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LLMCleaner.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LLMCleaner.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "Install-AI.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\lib\*.ps1"; DestDir: "{app}\lib"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\LLMCleaner.ps1"""; \
  WorkingDir: "{app}"; IconFilename: "{app}\LLMCleaner.ico"
Name: "{group}\{#AppName} ({cm:ShortPreview})"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\LLMCleaner.ps1"" -Podglad"; \
  WorkingDir: "{app}"; IconFilename: "{app}\LLMCleaner.ico"
Name: "{group}\{#AppName} ({cm:ShortConsole})"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\LLMCleaner.ps1"" -Konsola"; \
  WorkingDir: "{app}"; IconFilename: "{app}\LLMCleaner.ico"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\LLMCleaner.ps1"""; \
  WorkingDir: "{app}"; IconFilename: "{app}\LLMCleaner.ico"; Tasks: desktopicon

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Install-AI.ps1"" -Model ""{code:GetModel}"" -Lang {code:GetLang}"; \
  StatusMsg: "{cm:RunAi}"; Tasks: ai; Flags: waituntilterminated
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\LLMCleaner.ps1"" -Podglad"; \
  WorkingDir: "{app}"; Description: "{cm:Launch}"; Flags: postinstall nowait skipifsilent unchecked
Filename: "{#AppURL}#readme"; Description: "{cm:Docs}"; Flags: postinstall shellexec nowait skipifsilent unchecked

[UninstallRun]
; Stop the private AI server if LLMCleaner is still running, so the ai folder can be removed
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -Command ""Get-Process ollama -ErrorAction SilentlyContinue | Where-Object Path -like '{app}\ai\*' | Stop-Process -Force"""; \
  Flags: runhidden waituntilterminated; RunOnceId: "StopAiServer"

[UninstallDelete]
; Created by Install-AI.ps1: the AI engine, the models and the chosen model
Type: filesandordirs; Name: "{app}\ai"
Type: files; Name: "{app}\config.json"

[Code]
var
  ModelPage: TInputOptionWizardPage;

procedure InitializeWizard;
begin
  ModelPage := CreateInputOptionPage(wpSelectTasks,
    CustomMessage('ModelTitle'), CustomMessage('ModelDesc'), CustomMessage('ModelSub'), True, False);
  ModelPage.Add(CustomMessage('Model4b'));
  ModelPage.Add(CustomMessage('Model8b'));
  ModelPage.SelectedValueIndex := 0;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = ModelPage.ID then
    Result := not WizardIsTaskSelected('ai');
end;

function GetModel(Param: String): String;
begin
  if ModelPage.SelectedValueIndex = 1 then
    Result := 'qwen3:8b'
  else
    Result := 'qwen3:4b-instruct';
end;

function GetLang(Param: String): String;
begin
  if ActiveLanguage = 'polish' then
    Result := 'pl'
  else
    Result := 'en';
end;
