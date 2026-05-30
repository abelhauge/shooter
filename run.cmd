@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~dp0"
set "PROJECT_FILE=%ROOT_DIR%project.godot"
set "EDITOR_START_SCENE=res://scenes/maps/art/arena_downtown_01_art.tscn"

if not exist "%PROJECT_FILE%" (
  echo Godot project not initialized yet. Expected %PROJECT_FILE% 1>&2
  exit /b 1
)

call :sync_github_before_run
if errorlevel 1 exit /b !errorlevel!

call :resolve_godot
if errorlevel 1 exit /b !errorlevel!

set "IS_EDITOR=0"
set "BOOTSTRAP_CACHE=1"
if not "%~1"=="" (
  for %%A in (%*) do call :parse_run_arg "%%~A"
)

if "%SHOOTER_SKIP_IMPORT_BOOTSTRAP%"=="1" set "BOOTSTRAP_CACHE=0"

if "%BOOTSTRAP_CACHE%"=="1" (
  if "%IS_EDITOR%"=="1" (
    echo Importing Godot assets before opening the editor... 1>&2
    "%GODOT_BIN_RESOLVED%" --headless --import --path "%ROOT_DIR%"
    if errorlevel 1 exit /b !errorlevel!
    if "%SHOOTER_EDITOR_START_SCENE%"=="" set "SHOOTER_EDITOR_START_SCENE=%EDITOR_START_SCENE%"
    call :configure_editor_start_scene "!SHOOTER_EDITOR_START_SCENE!"
    if errorlevel 1 exit /b !errorlevel!
  ) else (
    if not exist "%ROOT_DIR%.godot\global_script_class_cache.cfg" (
      echo Bootstrapping Godot import/class cache... 1>&2
      "%GODOT_BIN_RESOLVED%" --headless --import --path "%ROOT_DIR%"
      if errorlevel 1 exit /b !errorlevel!
    )
  )
)

"%GODOT_BIN_RESOLVED%" --path "%ROOT_DIR%" %*
exit /b !errorlevel!

:parse_run_arg
if /I "%~1"=="--editor" set "IS_EDITOR=1"
if /I "%~1"=="-e" set "IS_EDITOR=1"
if /I "%~1"=="--version" set "BOOTSTRAP_CACHE=0"
if /I "%~1"=="--help" set "BOOTSTRAP_CACHE=0"
if /I "%~1"=="-h" set "BOOTSTRAP_CACHE=0"
exit /b 0

:sync_github_before_run
if "%SHOOTER_SKIP_GIT_SYNC%"=="1" (
  echo Skipping GitHub sync because SHOOTER_SKIP_GIT_SYNC=1. 1>&2
  exit /b 0
)
where git >nul 2>nul
if errorlevel 1 (
  echo GitHub sync skipped: git was not found in PATH. 1>&2
  exit /b 0
)
git -C "%ROOT_DIR%" rev-parse --is-inside-work-tree >nul 2>nul
if errorlevel 1 (
  echo GitHub sync skipped: %ROOT_DIR% is not a git worktree. 1>&2
  exit /b 0
)

for /f "usebackq delims=" %%B in (`git -C "%ROOT_DIR%" rev-parse --abbrev-ref HEAD`) do set "BRANCH=%%B"
if "%BRANCH%"=="HEAD" (
  echo GitHub sync skipped: detached HEAD has no upstream branch. 1>&2
  exit /b 0
)

set "UPSTREAM="
for /f "usebackq delims=" %%U in (`git -C "%ROOT_DIR%" rev-parse --abbrev-ref --symbolic-full-name @{u} 2^>nul`) do set "UPSTREAM=%%U"
if "%UPSTREAM%"=="" (
  echo GitHub sync skipped: branch '%BRANCH%' has no upstream. 1>&2
  exit /b 0
)

echo Pulling latest changes for '%BRANCH%' from '%UPSTREAM%'... 1>&2
git -C "%ROOT_DIR%" pull --ff-only --autostash
exit /b !errorlevel!

:resolve_godot
if not "%GODOT_BIN%"=="" (
  if exist "%GODOT_BIN%" (
    set "GODOT_BIN_RESOLVED=%GODOT_BIN%"
    exit /b 0
  )
  where "%GODOT_BIN%" >nul 2>nul
  if not errorlevel 1 (
    for /f "usebackq delims=" %%G in (`where "%GODOT_BIN%"`) do (
      set "GODOT_BIN_RESOLVED=%%G"
      exit /b 0
    )
  )
  echo GODOT_BIN is set but was not found: %GODOT_BIN% 1>&2
  exit /b 1
)

where godot4 >nul 2>nul
if not errorlevel 1 (
  for /f "usebackq delims=" %%G in (`where godot4`) do (
    set "GODOT_BIN_RESOLVED=%%G"
    exit /b 0
  )
)
where godot >nul 2>nul
if not errorlevel 1 (
  for /f "usebackq delims=" %%G in (`where godot`) do (
    set "GODOT_BIN_RESOLVED=%%G"
    exit /b 0
  )
)
if exist "%ROOT_DIR%.bin\godot.exe" (
  set "GODOT_BIN_RESOLVED=%ROOT_DIR%.bin\godot.exe"
  exit /b 0
)
call :find_godot_under "%ROOT_DIR%.bin"
if not errorlevel 1 exit /b 0
if exist "%ProgramFiles%\Godot\Godot.exe" (
  set "GODOT_BIN_RESOLVED=%ProgramFiles%\Godot\Godot.exe"
  exit /b 0
)
call :find_godot_under "%ProgramFiles%\Godot"
if not errorlevel 1 exit /b 0
call :find_godot_under "%ProgramFiles%\GodotEngine"
if not errorlevel 1 exit /b 0
call :find_godot_under "%LOCALAPPDATA%\Microsoft\WinGet\Links"
if not errorlevel 1 exit /b 0
call :find_godot_under "%LOCALAPPDATA%\Microsoft\WinGet\Packages"
if not errorlevel 1 exit /b 0
call :find_godot_under "%LOCALAPPDATA%\Programs\Godot"
if not errorlevel 1 exit /b 0

echo Could not find a Godot executable in PATH. Install Godot 4 or set GODOT_BIN=C:\path\to\Godot.exe. 1>&2
exit /b 1

:find_godot_under
if "%~1"=="" exit /b 1
if not exist "%~1" exit /b 1
for /f "delims=" %%G in ('dir /b /s "%~1\Godot*.exe" 2^>nul') do (
  set "GODOT_BIN_RESOLVED=%%G"
  exit /b 0
)
exit /b 1

:configure_editor_start_scene
set "LAYOUT_FILE=%ROOT_DIR%.godot\editor\editor_layout.cfg"
if not exist "%ROOT_DIR%.godot\editor" mkdir "%ROOT_DIR%.godot\editor"
(
  echo [EditorNode]
  echo.
  echo open_scenes=PackedStringArray("%~1"^)
  echo current_scene="%~1"
  echo selected_main_editor_idx=1
) > "%LAYOUT_FILE%"
exit /b 0
