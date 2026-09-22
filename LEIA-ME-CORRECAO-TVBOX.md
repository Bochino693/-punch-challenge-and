# Punch Challenge Android TV Box — revisão 1.0.49

## Gerar o APK

Abra o PowerShell nesta pasta e execute somente:

```powershell
powershell -ExecutionPolicy Bypass -File .\GERAR_APK_COMPLETO.ps1
```

O resultado correto termina com `APK GERADO E CONFERIDO` e cria:

`build\android\PunchChallenge.apk`

Se a pasta do modelo Android não existir, o próprio comando tenta instalá-la
usando os Export Templates 4.6.1 já instalados no Godot.

## Botões no Arduino Nano

- START: botão normalmente aberto entre D2 e GND.
- CRÉDITO: botão normalmente aberto entre D3 e GND.
- CONFIG: botão normalmente aberto entre D9 e GND. Substitui o F9 e abre ou
  fecha a Central Técnica.

Grave no Nano o firmware que corresponde ao sensor usado. Para o sensor de
feixe LM393, use:

`ARDUINO_SENSOR_DE_FEIXE_LM393\ARDUINO_SENSOR_DE_FEIXE_LM393.ino`

## Primeira abertura na TV Box

1. Conecte a webcam e o Nano a um hub USB alimentado.
2. Instale e abra o APK.
3. Aceite a permissão CAMERA.
4. Aceite também a permissão do dispositivo USB para a webcam UVC.
5. Aceite a permissão USB do Arduino.

O jogo repete a procura automaticamente quando câmera ou Nano forem
reconectados. A Central mostra separadamente se a webcam foi vista no USB, se
foi autorizada e se o Android publicou um fluxo de vídeo.

## Tela cheia

A Activity não força mais o modo retrato de telefone, pois Android TV pode
reduzir aplicativos assim para uma janela pequena. Ela respeita a rotação da
TV Box, habilita modo imersivo e mantém a tela ligada. Deixe a saída da box em
retrato/90 graus; o layout lógico continua 1080 x 1920.

## Desempenho e cores

No Android a qualidade visual começa em MÉDIO e continua adaptativa. Isso evita
que o primeiro impacto rode com o teto de partículas antes de o medidor de FPS
reagir. A câmera prefere 640 x 480, suficiente para a foto de ranking de 320 px
e muito mais leve para a USB/GPU. Sons, fontes e arena continuam aquecidos antes
da rodada. Textos sobre cartões coloridos agora escolhem automaticamente creme
ou vinho escuro quando a cor original não alcança contraste de leitura; o tema
vermelho, preto e dourado foi preservado.

## Limite físico da webcam

O APK solicita a webcam USB sempre. Para haver imagem, a TV Box ainda precisa
ter USB Host/OTG e publicar a webcam UVC pelo serviço de câmera do Android. Se a
Central disser que a UVC está autorizada mas não surgir fluxo, teste a mesma
webcam em um aplicativo UVC: isso distingue configuração do jogo de limitação
do firmware da box.
