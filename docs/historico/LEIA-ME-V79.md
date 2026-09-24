# Super Boxing — build 79

Gere o APK como sempre e instale por cima.

## Carregamento sem travar em 87%
Os 87% eram o jogo subindo TUDO para a placa de vídeo no mesmo instante
(telas, arena, lutador, torcida, efeitos), por baixo do carregador. Numa
TV Box isso travava a tela por muitos segundos. Agora o aquecimento é em
etapas — uma coisa nova por quadro — e a barra acompanha cada etapa até
100%, sem parar.

A barra virou um shader: faixas diagonais e um brilho varrendo o trilho
inteiro (o fundo da barra), sempre em movimento.

## Permissão USB uma vez só
Na PRIMEIRA vez depois de instalar:
1. Aceite CÂMERA e MICROFONE (o microfone não é usado; sem ele o Android
   esconde a opção "Usar por padrão" na janela da webcam).
2. Na janela do Arduino (e na da webcam), MARQUE "Usar por padrão para
   este dispositivo USB" e toque OK. A tela do jogo lembra disso enquanto
   a janela estiver aberta.

Marcado, o Android guarda a escolha: não pergunta mais, nem depois de
desligar a TV Box — no boot ele mesmo dá a permissão ao jogo (e pode até
abrir o jogo sozinho quando o Arduino é detectado).

A lista de placas reconhecidas cresceu (CH340 antigo, SparkFun, Adafruit,
qualquer Arduino com USB nativo), para a opção "Usar por padrão" aparecer
em qualquer clone.
