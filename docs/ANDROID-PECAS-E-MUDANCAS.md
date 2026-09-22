# Pecas e mudancas da versao Android

## Pecas recomendadas

| Item | Requisito |
|---|---|
| TV Box | Android 8+, arm64, 4 GB RAM, USB Host/OTG, OpenGL ES 3 |
| Hub USB | Hub alimentado externamente, de boa qualidade |
| Arduino | Nano original ou clone CH340, com o firmware optico atual |
| Cabo do Nano | Cabo de dados curto, com trava mecanica no gabinete |
| Camera | Camera Android integrada ou webcam UVC confirmada na TV Box |
| Fonte da TV Box | Fonte propria e estabilizada; nao alimentar motor por ela |
| Fonte do motor | Fonte separada dimensionada para o motor e o driver IBT-2 |
| Fita LED | Fonte separada de 5 V e corrente adequada; GND comum ao Nano |
| Protecao | Fusivel, chave geral, aterramento e botao de emergencia |

## O que muda drasticamente

| Windows | Android / TV Box |
|---|---|
| `gdserial.dll` ou processo auxiliar | USB Host nativo com plugin Android |
| `COM3`, `COM4` | Identificador USB VID/PID/device-id |
| Driver CH340 instalado no Windows | Driver CH340/CDC/FTDI/CP210x dentro do APK |
| DLL de camera Media Foundation | `CameraServer`/Camera2 fornecido pelo Android |
| Startup do Windows | Launcher/quiosque da TV Box |
| EXE + PCK + DLLs | Um APK arm64 |
| Teclado de manutencao | Controle remoto/USB ou ADB durante a bancada |

Motor, sensor, botoes e LEDs **nao migram para GPIO da TV Box**. Eles continuam
no Arduino, que e o controlador de tempo real e de seguranca. A TV Box manda
comandos de alto nivel pelo mesmo protocolo serial.

## Limitacoes que precisam de teste fisico

- Nem toda TV Box fornece corrente USB suficiente; use hub alimentado.
- Alguns firmwares nao oferecem webcam UVC ao Camera2.
- O pedido de permissao USB e por dispositivo; trocar o conversor pode abrir
  uma nova janela de autorizacao.
- O app nao consegue religar uma TV Box travada pelo fabricante; mantenha
  ventilacao e uma fonte confiavel.
