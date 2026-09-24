# Punch Challenge 1.0.65 — refinamento

Gere o APK como sempre: dois cliques em `GERAR_APK_AGORA.bat`.
Depois instale com `INSTALAR_NA_TVBOX.bat` (instala por cima; ranking e
ajustes ficam).

## O que mudou

**APK de release.** O script exportava em modo *debug*: bibliotecas nativas
sem otimizar e com símbolos (daí os ~200 MB) e GDScript com checagens de
depuração ligadas. Agora é `--export-release`, assinado com a mesma chave de
antes (a de depuração do Godot), para atualizar por cima sem desinstalar.

**Sem engasgo depois do soco.**
- As fontes viraram MSDF e os caracteres do jogo vêm pré-desenhados dentro da
  própria fonte importada. Antes, cada tamanho novo de letra (o placar grande,
  os títulos com contorno) era rasterizado na hora do impacto: 7–50 ms num PC,
  bem mais na TV Box.
- As partículas saíram do laço em GDScript e passaram para emissores do motor
  (`CPUParticles2D`, em C++), com texturas próprias em alta definição
  (`assets/fx`). Ondas de choque viraram uma malha de anel (só pinta os pixels
  do anel).
- Partículas 3D com quantidade fixa (mudar `amount` realocava buffers a cada
  soco) e arena/efeitos pré-aquecidos no arranque: shaders compilam antes do
  primeiro soco.
- A webcam só é lida rápido quando aparece (contagem); durante o soco e o
  ranking a leitura quase para, e o plugin deixa de converter quadros.

**Arena nova.** Plateia desfocada com telão de LED, lona impressa com o
emblema, cordas e postes redondos, fachos de luz e flashes de verdade (não
mais quadradinhos). MSAA 4x e resolução do tamanho real do quadro na tela.
Texturas geradas por `tools/gerar_arena.py`.

**Lutador inteiro.** Cada pose virou um PNG próprio, recortado pelo desenho
(os pés passavam 6 px da célula da folha antiga e eram cortados), sem franja
do fundo, ampliado 1,5x e com borda suave (mistura por alfa em vez de recorte
serrilhado). Ferramenta: `tools/recortar_lutador.py`.

**Confete e ranking.** Confete de papel girando, atrás dos cartões. A tabela
entra sem quique, a linha de quem jogou acende no lugar (não cai por cima das
outras), os fogos param quando a tabela aparece, e cada linha mostra o nível e
a data da marca em vez de "JOGADOR".

**Arduino / USB.** Abrir, fechar e listar a USB rodam numa thread do plugin;
o jogo faz uma única chamada por quadro (`pollSerial`). Linhas montadas byte a
byte em ASCII, com limite de tamanho; fila de escrita limitada. Corrigido: o
`READY` que o firmware manda a cada `PING` deixava o jogo preso em
"calibrando"; e se a placa religar sozinha a configuração é reenviada.
Removidos os restos do Windows (varredura cega de COM1–COM64, thread de
enumeração, ponte PowerShell, DLL nativa).
