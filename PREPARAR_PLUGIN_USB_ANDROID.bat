@echo off
setlocal
cd /d "%~dp0"

if not exist "tools\android_usb_plugin\gradlew.bat" (
  echo ERRO: fonte do plugin USB nao encontrado.
  exit /b 1
)

set "ANDROID_HOME=C:\AndroidSdk"
set "ANDROID_SDK_ROOT=C:\AndroidSdk"
if not exist "%ANDROID_HOME%\platform-tools\adb.exe" (
  echo ERRO: SDK Android invalido em %ANDROID_HOME%.
  exit /b 1
)
set "ANDROID_SDK_GRADLE=%ANDROID_HOME:\=/%"
>"tools\android_usb_plugin\local.properties" echo sdk.dir=%ANDROID_SDK_GRADLE%

echo [1/3] Compilando driver USB Android...
if exist "tools\android_usb_plugin\plugin\demo" rmdir /s /q "tools\android_usb_plugin\plugin\demo"
pushd "tools\android_usb_plugin"
call gradlew.bat clean assemble --refresh-dependencies
if errorlevel 1 (
  popd
  echo ERRO: confira Java 17, Android SDK e a conexao com a internet.
  exit /b 1
)
popd

rem A tarefa Gradle cria uma copia de demonstracao com o mesmo UID do addon.
rem Ela nao pertence ao jogo e faria o Godot carregar o plugin duas vezes.
if exist "tools\android_usb_plugin\plugin\demo" rmdir /s /q "tools\android_usb_plugin\plugin\demo"
if exist "tools\android_usb_plugin\plugin\demo" (
  echo ERRO: nao consegui remover a copia temporaria do plugin.
  exit /b 1
)

echo [2/3] Instalando addon no projeto Godot...
if not exist "addons\PunchUsbSerial\bin\debug" mkdir "addons\PunchUsbSerial\bin\debug"
if not exist "addons\PunchUsbSerial\bin\release" mkdir "addons\PunchUsbSerial\bin\release"
copy /y "tools\android_usb_plugin\plugin\export_scripts_template\export_plugin.gd" "addons\PunchUsbSerial\export_plugin.gd" >nul
copy /y "tools\android_usb_plugin\plugin\export_scripts_template\plugin.cfg" "addons\PunchUsbSerial\plugin.cfg" >nul
copy /y "tools\android_usb_plugin\plugin\build\outputs\aar\PunchUsbSerial-debug.aar" "addons\PunchUsbSerial\bin\debug\PunchUsbSerial-debug.aar" >nul
copy /y "tools\android_usb_plugin\plugin\build\outputs\aar\PunchUsbSerial-release.aar" "addons\PunchUsbSerial\bin\release\PunchUsbSerial-release.aar" >nul

if not exist "addons\PunchUsbSerial\bin\release\PunchUsbSerial-release.aar" (
  echo ERRO: o AAR release nao foi gerado.
  exit /b 1
)

echo [3/3] Plugin pronto.
echo Abra o projeto no Godot 4.6.1, instale o modelo Android e exporte o preset Android.
exit /b 0
