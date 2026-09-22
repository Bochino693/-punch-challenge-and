# A arena e o lutador

Esta é a única diferença entre `punch-challenge-animated` e
`punch-challenge`. O resto do jogo — sensor, ponte serial, câmera,
ranking, Central Técnica, exportação — é o mesmo código, e deve continuar
sendo: correção que entra num repositório precisa poder entrar no outro
sem tradução.

## O que mudou na tela do soco

Antes, o meio da tela do soco era um alvo desenhado (na espera) e um
medalhão redondo com o número (no resultado). Os dois ocupavam o mesmo
retângulo escuro que o fundo do jogo já reservava, e os dois eram
desenho 2D plano.

Agora esse retângulo é uma **janela 3D com moldura**: um ringue de
verdade, com câmera, luz e perspectiva, e um lutador dentro dele que
**recua na medida do soco** e vai à lona quando não aguenta mais.

    ┌──────────────────────────────────────┐
    │              PUNCH CHALLENGE         │
    │  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓    │
    │ █┃  ADVERSÁRIO · ABALADO 46%    ┃█   │  ← as colunas de dano
    │ █┃ ┌──────────────────────────┐ ┃█   │
    │ █┃ │                          │ ┃█   │
    │ █┃ │    a arena em 3D         │ ┃█   │  ← o SubViewport
    │ █┃ │                          │ ┃█   │
    │ █┃ └──────────────────────────┘ ┃█   │
    │  ┗━━━━━━━┏━━━━━━━━━━━━┓━━━━━━━━━┛    │
    │          ┃    8420    ┃              │  ← a plaqueta do placar
    │          ┗━━━━━━━━━━━━┛              │
    │              NOCAUTE                 │
    │        DIRETO NO QUEIXO!             │  ← a frase
    │   ┌───────────┐  ┌───────────┐       │
    │   │  SOCO 1   │  │  SOCO 2   │       │
    └──────────────────────────────────────┘

As medidas moram todas em `ArenaQuadro` (`scripts/arena/quadro.gd`),
como constantes públicas, porque três coisas dependem delas: o desenho,
o tamanho da janela 3D (que precisa da mesma proporção, senão a imagem
chega esticada) e os testes.

## As peças

| arquivo | o que faz |
|---|---|
| `assets/personagem/sprites/` | a folha de nove poses e o `SpriteFrames` |
| `scripts/arena/lutador.gd` | as poses, o movimento por cima delas e as reações |
| `scripts/arena/arena3d.gd` | o mundo 3D dentro do `SubViewport` |
| `scripts/arena/quadro.gd` | a moldura e as colunas de dano, em 2D |
| `scripts/arena/frases.gd` | o que a máquina grita a cada nível |
| `scripts/ranking_celebration.gd` | quatro cerimônias, conforme a colocação |
| `tests/test_arena.gd` | o que não pode voltar a quebrar |

## O lutador é desenhado, e o movimento é código

O adversário são **nove ilustrações** numa folha 3×3
(`assets/personagem/sprites/lutador_folha_3x3.png`, 410 × 426 px por
pose), montadas num `AnimatedSprite3D` **dentro** da arena 3D — e não
numa camada 2D por cima dela. A diferença importa: assim o lutador
continua no ringue, com a perspectiva real, a câmera que recua no
impacto, o tremor, as partículas, a luz ciano e magenta e o
enquadramento do nocaute. Nada disso precisou ser reescrito.

### Por que o corpo procedural saiu

Ele era construído em GDScript: anéis torneados, músculo modelado,
sombreador de desenho com brilho por material e contorno por casca
invertida. Tecnicamente funcionava e custava onze chamadas de desenho.
Visualmente nunca chegou onde precisava — a queixa final foi "grosso,
cabelo mal definido, sem profundidade, o antebraço parece colado ao
tórax", e as quatro estavam certas. **Geometria feita de elipsoides
somados tem um teto de qualidade, e esse teto fica bem abaixo de uma
ilustração.** Quem mantém isto depois de mim: não tente atravessar esse
teto outra vez.

### As nove poses, e o que cada uma faz

| pose | papel no jogo |
|---|---|
| `guarda`, `idle` | alternam na respiração e na guarda |
| `preparado` | o agachamento, segundo quadro da guarda |
| `jab`, `direto` | o **desdém**: ele devolve dois socos no ar |
| `impacto_corpo` | golpe leve e médio |
| `impacto_forte` | golpe pesado e cambaleio |
| `nocaute` | na lona |
| `recuperacao` | levantando |

Nove papéis e nove desenhos, mas a correspondência **não é um para um**,
e é de propósito: `hit_light` e `hit_medium` partilham a mesma
ilustração porque a diferença entre um e outro não está no desenho, está
no quanto o corpo recua e em quanto tempo volta.

### O movimento é tudo o que a folha não tem

Cada pose é UM desenho parado. O que transforma nove desenhos num
lutador é o movimento procedural de `scripts/arena/lutador.gd`:

* a **respiração**, um balanço de um centímetro e meio que nunca para —
  sem ela o desenho denuncia que é um desenho no primeiro segundo;
* o **recuo**, que anda para trás, tomba e desliza para o lado conforme
  a tabela `RECUO`, e volta com uma curva que sai depressa e assenta
  devagar, que é como um corpo que levou um soco se recompõe;
* o **cambaleio**, que balança de lado enquanto volta — é o que separa
  "levou um soco" de "perdeu a base";
* o **tombo**, que desce o corpo até a lona com um repique curtíssimo no
  fim, e é a única coisa que não volta sozinha: ela espera o `get_up`;
* o **clarão** do impacto e o tom que puxa para o vermelho conforme o
  dano acumula.

É a técnica de um jogo de luta 2D clássico — poucos quadros, muita
física por cima —, e é ela que faz um soco leve e um soco que derruba
parecerem coisas diferentes mesmo quando a ilustração de fundo é a
mesma. A escada entre as reações (`DURACAO` e `RECUO`) é conferida por
teste: uma reação mais forte tem de durar mais e empurrar mais.

### Duas armadilhas que o render ensinou

**O tamanho vem do `pixel_size`, e ele tem de sair de MEDIDA.** A folha
não sabe de metros: são 426 pixels de altura, e é `pixel_size` que
decide se aquilo vira um lutador de 1,80 m ou um gigante que estoura o
quadro. Estourou duas vezes. Na segunda o erro estava escondido numa
frase: "a figura ocupa cerca de 86% dos 426 px". Não ocupa — medindo o
alfa da folha, a figura em pé vai da linha 2 (topo da cabeça) à linha
418 (sola do pé da frente), 97,9% da célula. Com os 86% supostos o
lutador saía com **2,03 m** onde se pediu 1,80, e a câmera foi afastada
três vezes para compensar, cada vez com um parágrafo explicando o
porquê.

Agora a escala sai de `TOPO_DA_CABECA_PX` e `SOLA_DO_PE_PX`, que são
medidas, e duas ferramentas guardam isso:

| ferramenta | o que faz |
| --- | --- |
| `tools/medir_folha.gd` | mede qualquer folha e imprime as constantes prontas |
| `tests/test_folha_lutador.gd` | reprova quando a folha do disco e as constantes discordam |

**A linha do chão é a borda de baixo da célula.** Isto custou três
tentativas para ser entendido, e todas as três falharam pelo mesmo
motivo: uma régua errada.

O lutador está em guarda, um pé à frente do outro. No desenho, o pé
**de trás** aparece mais **alto** — é perspectiva, o chão sobe na tela
conforme se afasta — e o pé **da frente** encosta na borda de baixo da
célula. A medida procurava a sola na *metade esquerda* da folha,
encontrava o pé de trás (linha 418) e chamava aquilo de chão. A bota da
frente, oito pixels mais baixa, ficava enterrada no tapete — e como o
tapete é desenhado na frente do desenho, aparecia decepada.

Pior: `tests/test_folha_lutador.gd` media a mesma coisa errada, então
confirmava o defeito em vez de pegá-lo. Foi o corte que sobreviveu a
três correções seguidas.

A régua certa é a óbvia: **a figura encosta no chão pelo ponto mais
baixo dela**, que é a última linha com tinta da célula
(`Lutador3D.SOLA_DO_PE_PX = 425`). As duas botas estão inteiras na
arte. Com a sola ali, o desenho **inteiro** fica acima do plano do
tapete e não há mais nada que o tapete possa cortar — que era o pedido:
a imagem toda, sem cortes.

**O pé não pode entrar na lona — e o sintoma disso é CORTE, não
afundamento.** A lona é desenhada *na frente* do plano do lutador, então
tudo o que desce abaixo de `y = 0` some atrás do tapete. Um pé afundado
não parece afundado: parece decepado. Havia duas fontes, e as duas
passaram despercebidas por isso:

- a **respiração** era um seno em torno de zero, ou seja, puxava o corpo
  2 cm abaixo do repouso durante metade de cada ciclo — o tempo todo,
  parado, sem ninguém bater. Virou `(1 − cos)/2`: mesmo período, mesma
  amplitude, só que de 0 para cima;
- o **cambaleio** inclinava a figura 0,18 rad de lado. Num desenho
  RÍGIDO com 71 cm de meia-base, isso enterra um pé 12,7 cm. O ângulo
  agora sai do quanto se quer ver o pé LEVANTAR
  (`PE_LEVANTA_NO_CAMBALEIO`, 10 cm → 4°), e não o contrário.

Por cima dos dois, `_com_os_pes_na_lona` mede os cantos da base depois de
toda a conta de movimento e sobe o corpo se o mais baixo passou do chão —
o que, de quebra, faz o giro pivotar no pé de baixo, que é o que um corpo
que perde a base faz. `tests/test_arena.gd` roda todas as reações quadro
a quadro e cobra o pé mais baixo.

**O chão do ringue não está em `y = 0`.** Esta foi a última fatia do
mesmo defeito, e a mais difícil de ver. A lona grande (4,6 × 4,6) tem o
topo em zero, e era nesse zero que o lutador pisava — mas **em cima
dela** há um miolo mais claro de 3 × 3 que sobe até `y = 0,015`, e é
ele que fica debaixo do lutador. Um centímetro e meio, a 0,0043 m por
pixel, são as **quatro últimas linhas da bota**; e como o tapete é
desenhado na frente do plano do desenho, o que aparece não é pé
enterrado, é bota decepada.

Agora o chão é uma constante só — `Arena3D.ALTURA_DA_LONA` —, o miolo é
construído a partir dela e o lutador é pousado em
`Arena3D.piso_do_lutador()`.

**E a sola é a BORDA DE BAIXO da linha 418, não a linha 418.** Esta foi
a última fatia, e é um erro de um pixel. Uma linha de textura ocupa um
intervalo: num sprite centrado, a linha `r` vai de `v = r` a
`v = r + 1`. Pondo `v = 418` no chão, a última linha com tinta da bota
ficava *a cavaleiro* do plano do tapete — metade acima, metade abaixo —
e o tapete, desenhado na frente, cortava a bota ao meio. Quatro
milímetros. É a "linha invisível". `Lutador3D.SOLA_NO_QUADRO_PX` é a
borda certa.

**A folga é medida em pixels da folha, não em metros.** Dois
(`FOLGA_DA_SOLA_PX`), porque é em pixel que o defeito aparece: a menos
de um, a borda da bota e o topo do tapete caem na mesma linha de pixel
da tela e qual delas ganha vira sorteio do teste de profundidade — o
mesmo corte, só que intermitente, que é pior de diagnosticar. Mais de
três e o lutador começa a flutuar.

**A sombra de contato ficava ACIMA da bota, e era um segundo corte.**
Ela estava em `y = 0,022`. Uma mancha é um plano horizontal: posta
acima da sola, ela atravessa o desenho e escurece de uma vez tudo o que
fica abaixo da altura dela — outra linha reta na bota, do mesmo tipo da
primeira, e posta ali justamente para esconder a primeira. Agora ela
mora em `ALTURA_DA_SOMBRA`, entre o tapete e a sola, e **some no
tombo**: um corpo que desce 34 cm passa a ser atravessado por ela, e um
corpo caído já está no tapete — não precisa de mancha para dizer que
encostou.

**Nada pode cortar o lutador — e isso é uma propriedade, não um
ajuste.** Três correções seguidas tentaram acertar a distância entre o
desenho e o tapete: o miolo levantado da lona, a borda do texel, a
altura da sombra. Cada uma consertava um caso e sobrava um fio de
corte, porque o problema não era o número — era **haver um plano com
poder de cortar o lutador**.

O desenho agora tem `no_depth_test`: nenhum plano da arena é testado
contra ele. Não há nada que deva passar à frente dele (as cordas da
frente não são desenhadas de propósito, os postes da frente ficam fora
do enquadramento, o tapete está embaixo), então a classe inteira do
problema sai do caminho em vez de mais um caso dela.

O outro lado é garantido por `_com_o_desenho_na_lona`: **nenhuma parte
do desenho passa abaixo da lona, em pose nenhuma, em instante nenhum**.
A trava mede a base da *pose atual* — `BASE_DA_POSE`, nove números
medidos na folha — depois de toda a conta de movimento. Isso fechou o
último buraco: o tombo do nocaute pedia 34 cm de queda sem saber que o
desenho dele já começa 21 cm acima do chão, e os 12 cm que sobravam
iam para debaixo do tapete. Agora o corpo desce até **encostar** e para
ali.

**A definição sobe em degraus, e quem decide é o vigia de desempenho.**
A arena não tem antisserrilhado nenhum — MSAA desligado, e o recorte do
lutador é por limiar de alfa, que é decisão de tudo-ou-nada: a silhueta
sai em degraus de um bit. Num quadro de 688 × 770 esses degraus têm o
tamanho de um pixel e se veem. Não é falta de pixels na tela; é falta
de **amostras por pixel**.

| degrau | janela | custo |
| --- | --- | --- |
| nítido | 1376 × 1540 | 4× — cada pixel final é a média de quatro amostras |
| cheio | 688 × 770 | 1× — um para um com o buraco |
| magro | 482 × 539 | 0,49× |

A redução de 1376 para 688 é exatamente 2:1, então o filtro bilinear do
desenho vira um filtro de caixa de quatro amostras: antisserrilha o
ringue, as cordas, as faíscas e o contorno do lutador, sem depender de
MSAA nem de recurso que a TV Box possa não ter. A escada tem histerese
(sobe em 0,95, desce em 0,85) porque trocar o tamanho de um
`SubViewport` realoca a textura — não pode acontecer a cada quadro.

**A janela 3D tem o tamanho exato do buraco da moldura.** Ela era
640 × 717 e era desenhada num buraco de 688 × 770: a proporção batia,
então nada parecia errado, mas havia um esticão de 1,075× em cima da
arena inteira, toda vez. Um esticão fracionário não realinha pixel com
pixel — cada um vira mistura de dois —, e o que some nessa mistura são
justamente os detalhes de um ou dois pixels: a ponta da bota, o fio de
luz na luva, o contorno ciano. Em 688 × 770 o desenho cai no buraco um
para um. Custa 15% mais pixels, e a janela magra continua existindo para
quando o vigia de desempenho apertar.

**No nocaute a câmera AFASTA, não aproxima.** Um corpo em pé é alto e
estreito; um corpo caído é baixo e largo, e o desenho do nocaute ocupa a
largura inteira do quadro. Chegando perto — que é o instinto, e o que a
versão 3D fazia certo — a imagem corta os dois braços e sobra um torso
gigante sem contexto. E ela continua **de frente**: o desenho já mostra
o corpo do ângulo certo, e dar a volta nele mostraria um plano de
perfil, ou seja, uma lâmina.

### O custo

Uma chamada de desenho, contra as onze do corpo procedural. Medido com
o jogo rodando, o quadro fica em 6,92 ms de mediana e 7,14 no pior caso
— idêntico a antes da troca.

### Trocar a arte

Substitua a folha e o `lutador_sprite_frames.tres`, mantendo os nove
nomes de pose da tabela acima. `Lutador3D.PAPEIS` é o mapa entre papel
do jogo e desenho; `tests/test_arena.gd` falha se faltar qualquer um.

Depois de trocar, **meça**:

```
godot --headless --path . --script tools/medir_folha.gd
```

Ele imprime, pose por pose, a caixa do desenho dentro da célula, avisa
quais poses de pé não alcançam a linha do chão e devolve
`TOPO_DA_CABECA_PX` e `SOLA_DO_PE_PX` prontos para colar em
`scripts/arena/lutador.gd`. Ele também mostra o pé de trás em separado —
para ser lido, e não usado como chão. A
câmera não precisa de ajuste nenhum: ela se enquadra sozinha a partir
desses números (`Arena3D._calcular_enquadramento`).

E deixe as regiões do `.tres` com `filter_clip = true`. As nove poses se
tocam dentro da folha — `nocaute` chega na última coluna e
`recuperacao`, a vizinha, começa na primeira —, e sem isso o filtro
linear cola meio texel do desenho ao lado no contorno de cada pose.


## Premiação e torcida

A colocação escolhe uma receita própria em `RankingCelebration`:

- **1º lugar:** selo de campeão, três canhões, chuva cheia e torcida longa;
- **2º–3º:** cerimônia de pódio, dois canhões e torcida própria;
- **4º–10º:** entrada no Top 10, um canhão e comemoração média;
- **11º–20º:** reconhecimento curto, sem fingir que foi recorde.

Os quatro sons são estéreo e combinam massa vocal, canto de arquibancada,
palmas, assobios e reverberação de ginásio. O confete é atualizado no lugar
e desenhado como uma fita de uma chamada, evitando a alocação e a
triangulação que faziam a chuva engasgar.

Abaixo de **6.000 pontos**, o adversário baixa a guarda, nega com a cabeça
e desdenha, acompanhado por vaias e assobios próprios. Com 6.000 ou mais
ele reconhece o golpe e reage fisicamente; caído na lona, nunca desdenha.

## O dano

Cada soco tira `forca × 0,62` do adversário (`Lutador3D.DANO_POR_GOLPE`),
onde `forca` é a posição da velocidade real dentro da faixa calibrada.
A nota continua usando o expoente competitivo, mas ele não achata a
animação: golpe físico médio parece médio, mesmo com pontuação difícil.
Na prática:

- dois socos perfeitos derrubam;
- um soco leve quase não mexe no medidor (e abaixo de 2% não conta,
  senão o ruído do sensor encheria a barra sozinho ao longo da noite);
- os níveis com *hit-stop* na tabela do `ScoreTier` — NOCAUTE,
  PESO-PESADO, LENDÁRIO e SOCO PERFEITO — derrubam **no primeiro golpe**,
  independentemente do medidor.

Quem cai permanece visível na lona e completa queda/levantamento em cerca
de 5 s, com o medidor voltando a 72%: a
rodada tem dois socos, e o segundo precisa ter para onde ir.

**Cada rodada começa com o adversário inteiro.** Herdar o dano faria a
segunda pessoa da fila derrubar alguém que já estava caindo, e as
colunas laterais mentiriam sobre o que ela fez.

## O custo, que é o que interessa numa TV Box

Esta versão vai para o mesmo aparelho que a original, então a arena foi
construída para custar pouco, não para impressionar em benchmark:

- **uma malha só** para todo o ringue (lona, borda, quatro postes, nove
  cordas, fundo), com cor por vértice — um desenho em vez de trinta;
- **três luzes**, nenhuma com sombra;
- **flashes e silhuetas da plateia em `MultiMesh`** — dois desenhos, com
  reação proporcional à força;
- **dois emissores GPU reutilizados** para faíscas e poeira da lona;
- **sem antisserrilhado, sem brilho, sem TAA**;
- **a janela encolhe** quando o vigia de desempenho aperta
  (`Desempenho.qualidade < 0,55`), mas continua atualizando em todo quadro;
- **a janela só desenha nas telas da rodada.** Liga no 3–2–1, permanece
  até o resultado e desliga na abertura, na tabela e na Central
  (`main.gd::_arena_no_ar`).

Para medir na máquina de destino:

```
godot --path . --script tools/medir_arena.gd
```

Ele roda a mesma tela duas vezes, com e sem a janela 3D, e imprime a
diferença. Não use `--headless`: sem rasterizador o custo do 3D não
aparece. Num PC de desenvolvimento com vídeo por software (llvmpipe), a
arena custou **0,77 ms por quadro** — menos de 4% de um quadro que já
levava 21 ms só com o 2D. Com GPU de verdade a diferença é menor ainda.

## Conferir

```
godot --headless --path . --script tests/test_arena.gd
godot --path . --script tools/capturar_telas.gd   # PNG de cada tela
```

`tests/test_arena.gd` guarda, entre outras coisas, os dois erros que a
arena cometeu de verdade durante a construção:

- **o nocaute afundava o lutador.** A queda baixava o corpo 62 cm além
  de tombá-lo; como o nó raiz fica na altura da lona, o boneco saía por
  baixo do ringue e a moldura mostrava um ringue vazio no momento mais
  importante do jogo;
- **a janela 3D e o buraco da moldura tinham proporções diferentes**, e
  a imagem chegava esticada.

As capturas ficam em `.telas/` (ignorado pelo Git) e são o jeito mais
rápido de conferir a tela inteira sem montar o gabinete.
