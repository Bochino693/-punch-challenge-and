@echo off
setlocal
cd /d "%~dp0"
title Punch Challenge - Instalar na TV Box

rem Instala o APK por cima do atual (-r): ranking, fotos e ajustes ficam.
rem Com a TV Box na rede, passe o IP:  INSTALAR_NA_TVBOX.bat 192.168.0.50
set "ADB=C:\AndroidSdk\platform-tools\adb.exe"
if not exist "%ADB%" (
  echo ERRO: adb nao encontrado em %ADB%
  pause
  exit /b 1
)
if not exist "build\android\PunchChallenge.apk" (
  echo ERRO: gere o APK antes com GERAR_APK_AGORA.bat
  pause
  exit /b 1
)
if not "%~1"=="" "%ADB%" connect %~1:5555
"%ADB%" install -r "build\android\PunchChallenge.apk"
if errorlevel 1 (
  echo.
  echo FALHA NA INSTALACAO. Se a mensagem falar de assinatura diferente,
  echo desinstale o jogo antigo da TV Box uma vez e rode de novo.
  pause
  exit /b 1
)
rem Camera liberada pela linha de comando: o jogo nao pergunta nunca.
"%ADB%" shell pm grant com.lazersport.punchchallenge android.permission.CAMERA
echo.
echo INSTALADO. Abra o Punch Challenge na TV Box.
pause
exit /b 0
