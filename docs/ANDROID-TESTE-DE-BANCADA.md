# Teste de bancada Android

1. Com motor e fita desconectados da potencia, ligue TV Box, hub e Nano.
2. Aceite a permissao USB. A Central deve mostrar `USB ANDROID` e depois
   `READY`/`CONECTADO`.
3. Aperte CREDITO e START dez vezes; confira contadores e ausencia de duplo
   clique. Aperte CONFIG (D9/GND) e confirme que a Central abre e fecha.
4. Interrompa o feixe/sensor e confirme mensagens `HIT` coerentes.
5. Retire e recoloque o USB durante a tela inicial; a busca deve reconectar.
6. Autorize CAMERA e a janela USB/UVC da webcam. Confira previa e tire vinte
   fotos consecutivas.
7. Ligue a fonte dos LEDs e teste cada animacao.
8. Ligue a potencia do motor somente depois; teste fim de curso, timeout e
   botao de emergencia antes de instalar o saco.
9. Rode cem partidas e monitore temperatura da TV Box, fonte, driver IBT-2 e
   motor. Nao aceite reinicio, perda de USB nem travamento visual.

Se a serial nao aparecer, confirme USB Host/OTG e use hub alimentado. Se a
camera nao aparecer nem num aplicativo UVC, troque o firmware ou a TV Box.
