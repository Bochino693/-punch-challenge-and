# Protocolo USB Android

O Nano aparece ao APK como uma porta USB Host. A configuracao e 115200 baud,
8 bits, sem paridade, um stop bit. Cada mensagem e ASCII e termina em `\n`.

Placa para jogo: `READY`, `STATUS`, `TELEMETRY`, `HIT`, `BUTTON`, `LIMIT` e
`ERROR`. Jogo para placa: `PING`, comandos do motor, LEDs e configuracao do
sensor. O plugin nao interpreta a mecanica: apenas transporta as mesmas linhas
usadas pelo firmware optico existente.

Os botoes enviam `BUTTON,START`, `BUTTON,CREDIT` e `BUTTON,CONFIG`. CONFIG
abre/fecha a Central Tecnica e equivale ao F9. No firmware completo ele usa D9
com `INPUT_PULLUP`; o botao normalmente aberto deve ligar D9 ao GND.

Adaptadores reconhecidos: CDC/ACM, FTDI, CP210x, PL2303 e CH340/CH341. A
permissao USB e solicitada pelo Android quando a porta e aberta pela primeira
vez. O mesmo plugin detecta interfaces UVC e solicita separadamente a permissao
da webcam USB. A leitura serial fica em thread nativa e `poll()` entrega apenas
linhas completas ao Godot.
