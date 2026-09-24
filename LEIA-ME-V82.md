# Super Boxing — build 82

Antes do APK, rode `PREPARAR_PLUGIN_USB_ANDROID.bat` (o plugin mudou de
novo). Depois gere o APK como sempre.

## Sensor "fraco"
A régua automática colocava os 5000 pontos no soco do percentil 70: sete em
cada dez socos ficavam abaixo de 5000. E o piso que ela manda para o
Arduino subia com o tempo, então socos mais leves nem eram aceitos. Agora:
- os 5000 pontos ficam no soco do percentil 42 (um soco comum, bem dado,
  chega lá);
- o piso tem folga maior, então o sensor volta a aceitar socos mais leves;
- a curva padrão é mais generosa no meio e continua dura em cima
  (3 m/s ≈ 3500, 4 ≈ 5200, 5 ≈ 6900, 6 ≈ 8300, e acima de 8000 continua
  difícil);
- na primeira abertura desta versão, a régua salva na máquina é
  recalculada e o piso volta para no máximo 0,6 m/s.

## Câmera volta a abrir sozinha
A fila de permissões da build 81 esperava um aviso de foco do Android que
algumas TV Boxes não mandam: sem ele, a câmera nunca abria. Agora a câmera
abre assim que está autorizada. E o ciclo de "parar e ligar" de uma câmera
que ainda não tinha aberto (que zerava o plugin e não abria nunca) acabou.

## A janela do Arduino
O texto da caixa ("Usar por padrão" / "Sempre abrir o Punch Challenge
quando… for conectado") é do próprio Android e não dá para trocar. É essa
caixa que faz o Android lembrar da permissão. Sem ela, a janela volta a
cada vez que a TV Box liga. Marque uma vez e toque OK. Com o plugin novo
(build 81 em diante), o jogo não é aberto de novo quando o cabo é ligado:
a caixa só guarda a permissão.

## Mais leve e mais rápido
- Lutador: de 119 mil para 56 mil triângulos (corpo sem subdivisão,
  botas mais simples) e texturas de 2048 em vez de 4096. Menos para a
  placa de vídeo e menos para carregar.
- Na TV Box, a arena renderiza a 85% e é ampliada no quadro (72% quando a
  máquina aperta).
- Os discos translúcidos do tamanho da tela na hora do placar saíram na
  TV Box (pintavam a tela duas vezes a mais por quadro).
- O lutador se mexe 30% mais rápido (guarda, passos, reações).

## Lutador
- **Calção:** as duas faces agora são desenhadas; visto de baixo, ele não
  fica mais transparente.
- **Luvas:** apareciam como um recorte vermelho chapado (o vermelho muito
  saturado, com a luz de frente quase igual em toda a luva, apagava a
  forma). Agora têm sombra embutida na cor (dorso e nós dos dedos mais
  claros, laterais e palma mais escuras) e menos brilho estourado.

## Arena
- **Torcida sempre viva:** cada coluna balança no seu ritmo, braços sobem
  em ondas, luzes de celular piscam. Nos golpes, todo mundo pula.
- **Logo SUPER BOXING no centro da lona**, embaixo do lutador.

## Trocar o lutador por um profissional
Daqui eu só consigo baixar arquivos do GitHub, não de lojas de modelos
(Mixamo, Sketchfab). Por isso o jogo agora aceita um lutador externo sem
mexer no código: veja `assets/lutador_mixamo/LEIA-ME.txt`. Personagem e
animações da Mixamo (grátis) nessa pasta: o jogo ajusta a altura, vira o
personagem de frente, põe os pés no chão e veste as luvas. Testei o
caminho com um personagem da Mixamo e ele funcionou.
