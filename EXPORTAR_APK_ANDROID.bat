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

rem SEGUNDO ARGUMENTO: "release" ou "debug". O padrao continua debug,
rem porque o release exige uma chave de assinatura configurada -- quem a
rem prepara e o GERAR_APK_COMPLETO.ps1.
rem
rem A DIFERENCA NAO E BUROCRATICA, E VELOCIDADE. O modelo debug do Godot
rem carrega o interpretador de GDScript instrumentado: cada linha
rem executada passa por verificacao de ponto de parada e contabilidade de
rem perfil. Num PC isso se perde no ruido; numa TV box, num jogo que e
rem quase todo GDScript, e uma fatia do quadro que some de graca ao
rem trocar para release.
set "MODO=--export-debug"
if /i "%~2"=="release" set "MODO=--export-release"

if not exist "build\android" mkdir "build\android"
"%~1" --headless --verbose --path "%CD%" %MODO% "Android" "build\android\PunchChallenge.apk"
if errorlevel 1 exit /b 5
if not exist "build\android\PunchChallenge.apk" (
  echo ERRO: o Godot terminou sem criar o APK.
  exit /b 6
)
echo APK criado em build\android\PunchChallenge.apk
exit /b 0
