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

rem APK DE RELEASE, e nao de depuracao. O de depuracao leva as bibliotecas
rem nativas sem otimizar e sem remover simbolos (era o que fazia o APK
rem passar de 200 MB) e roda o GDScript com as checagens de depuracao
rem ligadas -- mais lento justamente na TV Box.
rem
rem A assinatura usa a MESMA chave de sempre (a de depuracao do Godot), para
rem o APK novo instalar POR CIMA do antigo sem apagar ranking e ajustes.
set "CHAVE=%APPDATA%\Godot\keystores\debug.keystore"
if not exist "%CHAVE%" (
  echo ERRO: chave do Godot nao encontrada em %CHAVE%
  echo Abra o projeto no editor Godot uma vez e exporte qualquer APK de teste;
  echo o editor cria essa chave sozinho.
  exit /b 7
)
set "GODOT_ANDROID_KEYSTORE_RELEASE_PATH=%CHAVE%"
set "GODOT_ANDROID_KEYSTORE_RELEASE_USER=androiddebugkey"
set "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=android"

if not exist "build\android" mkdir "build\android"
"%~1" --headless --path "%CD%" --export-release "Android" "build\android\PunchChallenge.apk"
if errorlevel 1 exit /b 5
if not exist "build\android\PunchChallenge.apk" (
  echo ERRO: o Godot terminou sem criar o APK.
  exit /b 6
)
echo APK criado em build\android\PunchChallenge.apk
exit /b 0
