# Punch Challenge — Android / TV Box

Esta pasta e uma variante Android independente. Ela nao usa PowerShell,
DLL, registro do Windows, porta COM nem processo auxiliar.

## O que funciona igual

- O mesmo firmware optico do Arduino Nano, a 115200 baud.
- Sensor de impacto, botoes START e CREDITO, motor e fita enderecavel
  continuam ligados e controlados pelo Nano.
- O protocolo `READY`, `STATUS`, `HIT`, `BUTTON`, `MOTOR` e `LED` nao muda.
- Pontuacao, ranking, audio, fotos e mecanica permanecem no Godot.

## Preparacao uma unica vez

1. Use uma TV Box Android com **USB Host/OTG real** e Android 8 ou mais novo.
   O preset inclui ARMv7 e ARM64 para atender tambem a SmartPro RK3229.
2. No computador, instale Godot 4.6.1, modelos de exportacao Android,
   Java 17 e Android SDK (platform 35/build-tools 35.0.1 ou mais novo).
3. Configure `Java SDK Path` e `Android SDK Path` no Godot.
4. Execute `PREPARAR_PLUGIN_USB_ANDROID.bat`. Nao ha script PowerShell.
   A primeira compilacao precisa de internet para baixar Gradle, a biblioteca
   do Godot e o driver USB; as seguintes usam o cache local.
5. Abra `project.godot` no Godot e use **Projeto > Instalar modelo de
   compilacao Android**.
6. Exporte o preset **Android**, ou rode:

   `EXPORTAR_APK_ANDROID.bat "C:\Godot\Godot_v4.6.1-stable_win64_console.exe"`

Na primeira conexao do Nano, aceite a janela "permitir que o aplicativo
acesse o dispositivo USB" e marque o uso padrao, quando essa opcao aparecer.
Aceite tambem a permissao da camera.

## Camera

O jogo usa `CameraServer` do Android. Camera integrada ou webcam UVC so
funciona quando a propria TV Box a publica para aplicativos Android. Alguns
firmwares baratos bloqueiam UVC ou expõem apenas a camera interna; nesse caso
nao existe ajuste no Godot que substitua um firmware com suporte Camera2/UVC.
Teste a TV Box com um aplicativo de camera UVC antes de fechar o gabinete.

## Tela e inicializacao

O layout original e vertical, 1080 x 1920. Configure a saida HDMI da TV Box em
modo retrato/rotacao de 90 graus. Em uma TV horizontal o Android colocara
barras ou reduzira a interface; uma versao horizontal exige redesenho das telas.

O APK aparece como aplicativo de TV e como launcher. Para ligar direto no
jogo, selecione Punch Challenge como launcher padrao ou use o modo quiosque do
fabricante. Android moderno pode bloquear aplicativos comuns iniciados em
segundo plano no boot, por isso nao foi incluido um receptor de boot fragil.

Leia tambem `docs/ANDROID-PECAS-E-MUDANCAS.md` e
`docs/ANDROID-TESTE-DE-BANCADA.md`.
