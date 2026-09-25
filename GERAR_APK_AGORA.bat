@echo off
setlocal
title Punch Challenge - Gerar APK Android
cd /d "%~dp0"

echo ============================================================
echo   SUPER BOXING - BUILD 90
echo   GERA O APK COMPLETO (PLUGIN USB + JOGO)
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\gerar_apk\GERAR_APK_COMPLETO.ps1"
if errorlevel 1 (
  echo.
  echo FALHA: o APK nao foi criado. Fotografe esta janela inteira.
  echo Nao copie os sinais PS, ^>^> ou mensagens de erro como comandos.
  pause
  exit /b 1
)

echo.
echo SUCESSO. APK criado em:
echo %~dp0build\android\PunchChallenge.apk
echo.
echo Agora conecte a TV Box e use INSTALAR_NA_TVBOX.bat.
pause
exit /b 0
