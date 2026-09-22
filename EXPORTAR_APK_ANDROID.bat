@echo off
setlocal
cd /d "%~dp0"

if "%~1"=="" (
  echo USO: EXPORTAR_APK_ANDROID.bat "C:\caminho\Godot_v4.6.1-stable_win64_console.exe"
  exit /b 2
)
if not exist "%~1" (
  echo ERRO: executavel do Godot nao encontrado: %~1
  exit /b 2
)
if not exist "addons\PunchUsbSerial\bin\release\PunchUsbSerial-release.aar" (
  echo ERRO: execute PREPARAR_PLUGIN_USB_ANDROID.bat primeiro.
  exit /b 3
)
if not exist "android\build\build.gradle" if not exist "android\build.gradle" (
  echo ERRO: no Godot, use Projeto ^> Instalar modelo de compilacao Android.
  exit /b 4
)

if not exist "build\android" mkdir "build\android"
"%~1" --headless --verbose --path "%CD%" --export-debug "Android" "build\android\PunchChallenge.apk"
if errorlevel 1 exit /b 5
if not exist "build\android\PunchChallenge.apk" (
  echo ERRO: o Godot terminou sem criar o APK.
  exit /b 6
)
echo APK criado em build\android\PunchChallenge.apk
exit /b 0
