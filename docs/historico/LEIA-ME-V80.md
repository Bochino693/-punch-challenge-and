# Super Boxing — build 80

Gere o APK como sempre e instale por cima.

## Troca entre o 1º e o 2º soco sem corte
A faixa diagonal (cortina) não passa mais no meio da rodada. A arena, a
moldura e os cartões dos socos ficam parados; a plaqueta do placar encolhe,
o veredito sai pela esquerda e "AGORA O SEGUNDO!" entra pela direita — uma
luta só, de dois golpes.

A câmera da arena não pula mais: o empurrão do soco, a queda e o soco na
tela viram um alvo que ela persegue com mola amortecida. O tremor continua
seco, só dentro do quadro.

Nocaute no primeiro soco: ele cai, fica pouco na lona e já está de pé
quando o segundo soco é pedido.

## Torcida
Durante a luta a torcida EMPURRA quem bate: coro de "VAI! VAI!" com palmas
(som novo, `torcida_incentivo.wav`), quando o lutador desdenha, quando o
segundo soco é pedido e quando ele avança na câmera. Vaia só no fim, e só
se o jogador perdeu.

## Ranking
Só entra no Top 20 quem faz 5000 pontos ou mais. Abaixo disso a tela diz
"O TOP 20 COMEÇA EM 5000 PONTOS" e a foto é descartada. Marcas antigas
abaixo de 5000 que estavam gravadas saem da tabela na primeira abertura
(as fotos delas são apagadas pela faxina).

## Ícone novo
O ícone do aplicativo agora é a marca SUPER BOXING, inclusive o ícone
adaptável do Android (frente e fundo separados).

## Arena mais rápida e lutador mais nítido
- O corpo do lutador não anda mais em câmera lenta quando a TV Box cai
  para 15–20 quadros por segundo (o passo era cortado em 50 ms; agora o
  quadro longo é fatiado).
- Na TV Box a arena nunca renderiza acima de 1:1 (saídas 4K pediam 2,25x
  os pixels) e usa MSAA 2x.
- Contorno de luz em pele, luvas, botas, calção e cinturão, pele suada com
  relevo mais marcado e texturas com filtro anisotrópico.
- O logo SUPER BOXING na lona ficou maior e à frente do lutador, esticado
  para ler direito na perspectiva da câmera.
- No nocaute os pés escorregam para a frente enquanto ele tomba: o corpo
  inteiro deita dentro do ringue, nunca por baixo das cordas.

## Câmera (webcam) no Android
A janela de permissão de câmera/microfone era pedida de novo a cada busca
da webcam; cada janela pausava o jogo e derrubava a câmera que estava
abrindo. Agora é pedida uma vez por execução (o microfone, uma vez na vida
do aparelho). Esta correção está no plugin: rode
`PREPARAR_PLUGIN_USB_ANDROID.bat` antes de gerar o APK.
