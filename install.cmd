@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~dp0"
set "PROJECT_FILE=%ROOT_DIR%project.godot"
set "CHECK_ONLY=0"
set "BOOTSTRAP_IMPORT=1"

if not "%~1"=="" (
  for %%A in (%*) do (
    call :parse_install_arg "%%~A"
    if errorlevel 1 exit /b !errorlevel!
  )
)

if not exist "%PROJECT_FILE%" (
  echo ERROR: Godot project not initialized yet. Expected %PROJECT_FILE% 1>&2
  exit /b 1
)

if "%CHECK_ONLY%"=="0" call :install_dependencies
if errorlevel 1 exit /b !errorlevel!

call :resolve_python
if errorlevel 1 (
  echo ERROR: Python 3 is missing. Run install.cmd without --check to install it where supported. 1>&2
  exit /b 1
)

call :resolve_godot
if errorlevel 1 (
  echo ERROR: Godot 4 is missing. Run install.cmd without --check to install it where supported, or set GODOT_BIN=C:\path\to\Godot.exe. 1>&2
  exit /b 1
)

for /f "usebackq delims=" %%V in (`%PYTHON_CMD% --version 2^>nul`) do set "PYTHON_VERSION=%%V"
for /f "usebackq delims=" %%V in (`"%GODOT_BIN_RESOLVED%" --version 2^>nul`) do (
  set "GODOT_VERSION=%%V"
  goto :got_godot_version
)
:got_godot_version
if not "%GODOT_VERSION:~0,2%"=="4." (
  echo ERROR: Expected Godot 4, got '%GODOT_VERSION%' from %GODOT_BIN_RESOLVED% 1>&2
  exit /b 1
)

echo ==^> Python: %PYTHON_CMD% (%PYTHON_VERSION%)
echo ==^> Godot: %GODOT_BIN_RESOLVED% (%GODOT_VERSION%)

call :check_asset_baseline

if "%BOOTSTRAP_IMPORT%"=="1" (
  echo ==^> Bootstrapping Godot import/class cache
  "%GODOT_BIN_RESOLVED%" --headless --import --path "%ROOT_DIR%"
  if errorlevel 1 exit /b !errorlevel!
)

echo ==^> Running static validation
%PYTHON_CMD% "%ROOT_DIR%tools\validate_static.py"
if errorlevel 1 exit /b !errorlevel!

echo ==^> Install check complete. Start the game with run.cmd or the editor with run.cmd --editor
exit /b 0

:parse_install_arg
if /I "%~1"=="--check" (
  set "CHECK_ONLY=1"
  exit /b 0
)
if /I "%~1"=="--no-bootstrap" (
  set "BOOTSTRAP_IMPORT=0"
  exit /b 0
)
if /I "%~1"=="--help" goto :usage
if /I "%~1"=="-h" goto :usage
echo ERROR: Unknown option: %~1 1>&2
exit /b 1

:usage
echo Usage: install.cmd [--check] [--no-bootstrap]
echo.
echo Installs or verifies local dependencies for this Godot 4 project.
echo.
echo Options:
echo   --check         Verify dependencies only; do not install anything.
echo   --no-bootstrap Skip Godot headless import/cache bootstrap.
echo   -h, --help     Show this help.
exit /b 0

:install_dependencies
call :resolve_python >nul 2>nul
if errorlevel 1 (
  where winget >nul 2>nul
  if errorlevel 1 (
    echo WARN: Python 3 missing and winget was not found. Install Python 3 manually. 1>&2
  ) else (
    echo ==^> Installing Python 3 with winget
    winget install --exact --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements
  )
)

call :resolve_godot >nul 2>nul
if errorlevel 1 (
  where winget >nul 2>nul
  if errorlevel 1 (
    echo WARN: Godot 4 missing and winget was not found. Install Godot 4 manually. 1>&2
  ) else (
    echo ==^> Installing Godot 4 with winget
    winget install --exact --id GodotEngine.GodotEngine --accept-package-agreements --accept-source-agreements
  )
)
exit /b 0

:resolve_python
if not "%PYTHON_BIN%"=="" (
  if exist "%PYTHON_BIN%" (
    set "PYTHON_CMD="%PYTHON_BIN%""
    exit /b 0
  )
  where "%PYTHON_BIN%" >nul 2>nul
  if not errorlevel 1 (
    "%PYTHON_BIN%" --version >nul 2>nul
    if errorlevel 1 exit /b 1
    set "PYTHON_CMD=%PYTHON_BIN%"
    exit /b 0
  )
  exit /b 1
)

where py >nul 2>nul
if not errorlevel 1 (
  py -3 --version >nul 2>nul
  if not errorlevel 1 (
    set "PYTHON_CMD=py -3"
    exit /b 0
  )
)
where python3 >nul 2>nul
if not errorlevel 1 (
  python3 --version >nul 2>nul
  if not errorlevel 1 (
    set "PYTHON_CMD=python3"
    exit /b 0
  )
)
where python >nul 2>nul
if not errorlevel 1 (
  python --version >nul 2>nul
  if not errorlevel 1 (
    set "PYTHON_CMD=python"
    exit /b 0
  )
)
exit /b 1

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
exit /b 1

:find_godot_under
if "%~1"=="" exit /b 1
if not exist "%~1" exit /b 1
for /f "delims=" %%G in ('dir /b /s "%~1\Godot*.exe" 2^>nul') do (
  set "GODOT_BIN_RESOLVED=%%G"
  exit /b 0
)
exit /b 1

:check_asset_baseline
set "MISSING_ASSETS=0"
if not exist "%ROOT_DIR%assets\third_party\quaternius\downtown_city_megakit\Exports\glTF (Godot)\Building_Large_2.gltf" (
  echo WARN: Missing local asset baseline file: assets/third_party/quaternius/downtown_city_megakit/Exports/glTF (Godot)/Building_Large_2.gltf 1>&2
  set "MISSING_ASSETS=1"
)
if not exist "%ROOT_DIR%assets\third_party\quaternius\ultimate_modular_men_pack\Individual Characters\glTF\Swat.gltf" (
  echo WARN: Missing local asset baseline file: assets/third_party/quaternius/ultimate_modular_men_pack/Individual Characters/glTF/Swat.gltf 1>&2
  set "MISSING_ASSETS=1"
)
if not exist "%ROOT_DIR%assets\third_party\quaternius\animated_guns_pack\FBX\Rifle.fbx" (
  echo WARN: Missing local asset baseline file: assets/third_party/quaternius/animated_guns_pack/FBX/Rifle.fbx 1>&2
  set "MISSING_ASSETS=1"
)
if "%MISSING_ASSETS%"=="1" (
  echo WARN: Dependency install completed, but local Quaternius asset packs are incomplete. Restore assets/third_party/quaternius before opening the editor. 1>&2
)
exit /b 0
