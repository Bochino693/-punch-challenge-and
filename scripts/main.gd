extends Control

## Punch Challenge — a máquina de soco da Lazer & Sport.
##
## TELA EM PÉ, 1080 × 1920, LIDA EM BANDAS. Quem joga está a dois ou três
## metros do gabinete e olha para cima. A tela é dividida em faixas
## horizontais fixas (`BANDA_*`), e cada coisa desenhada mora dentro da
## sua: cabeçalho, alvo do soco, leitura (número e veredito),
## cartões e rodapé. Enquanto tudo respeitar a sua banda, nada se
## sobrepõe — que é a diferença entre um placar que se lê de longe e um
## amontoado de texto por cima de texto.
##
## O nó raiz desenha textos, placar e a Central Técnica; o cenário vivo
## fica nos filhos: `PunchBackground` (fundo), `LedFrame` (moldura de LEDs) e
## `AudioBank` (sons). O que voa — confete, faísca, estilhaço — mora em
## `fx.gd`.
##
## O CAMINHO DE QUEM JOGA:
##
##   ABERTURA → (START) → 3, 2, 1 → SENSOR ARMADO → IMPACTO → RESULTADO
##
## O soco só existe de um jeito: o MPU-6050 do alvo manda HIT pela
## serial (protocolo V2, ver docs/PROTOCOLO_SERIAL.md). Não há tecla
## nem simulação de bancada — só o sensor de verdade marca ponto.

const TELA := Vector2(1080.0, 1920.0)
const ArcadeStage = preload("res://scripts/presentation/arcade_stage.gd")

# ======================================================================
# AS BANDAS DA TELA
# ======================================================================
## Cabeçalho: marca do jogo e modo de operação.
const BANDA_TOPO := 150.0
## Alvo do soco: de onde saem ondas, faíscas e clarão.
const PALCO_TOPO := 162.0
const PALCO_BASE := 1032.0
## O MEDALHÃO: o visor da máquina. Uma máquina de fliperama tem UM
## painel de placar, e é ele que a pessoa olha em todo momento do jogo —
## na contagem, na carga, no impacto e no resultado. Por isso o medalhão
## não é "a tela do resultado": é o visor, e cada estado só troca o que
## está escrito dentro dele.
const MEDALHAO_CENTRO := Vector2(540.0, 1245.0)
const MEDALHAO_RAIO := 186.0
## Leitura: o veredito e o convite, embaixo do visor.
const LEITURA_TOPO := 1450.0
const LEITURA_BASE := 1600.0
## Cartões de recorde/partidas/créditos.
const CARTOES_Y := 1622.0
const CARTOES_ALTURA := 122.0
## Rodapé: assinatura da casa e, só na bancada, as teclas de teste.
const RODAPE_Y := 1876.0
## Margem lateral livre de moldura de LED.
const MARGEM := 60.0
## O ALVO NA TELA. É o centro do visor — o mesmo lugar em que o farol
## chama o soco e em que o número nasce logo depois.
## O CENTRO DO QUADRO DA ARENA, e é ele que manda no espetáculo inteiro:
## é aqui que o zoom do impacto cresce, é daqui que as faíscas saem, é
## nisto que o farol mira. Nesta versão o alvo não é mais um desenho no
## meio do vazio — é o lutador dentro da moldura, e por isso o ponto saiu
## de 930 para o centro de `ArenaQuadro.TELA`. Mexer num sem mexer no
## outro faria as faíscas do soco explodirem ao lado de quem apanhou.
const ALVO_DO_SOCO := Vector2(540.0, 810.0)
const LARGURA_UTIL := TELA.x - MARGEM * 2.0

## As cores que voam. Saem da paleta porque confete branco, que num
## fundo preto era o mais vistoso, é justamente o que some num fundo claro.
const CORES_FESTA := Paleta.FESTA

## Quantas marcas a máquina guarda.
const RANKING_TAMANHO := 20

# ======================================================================
# A CENTRAL TÉCNICA, DESCRITA UMA VEZ SÓ
# ======================================================================
## A CENTRAL TEM PÁGINAS.
##
## Ela cabia numa tela só enquanto tinha modo, faixas e sensor. Com o
## mapeamento dos botões do gabinete, a calibração, a câmera e a mesa de
## som, passou a caber empilhando coisa por cima de coisa — e uma tela de
## configuração com controle escondido atrás de outro é onde o técnico
## clica errado e some com a regulagem da casa.
##
## Quatro páginas, cada uma com um assunto: como a máquina opera, como
## ela mede o golpe, o que ela vê e ouve, e o que ela guardou.
## A PÁGINA DO MOTOR ENTRA POR ÚLTIMO, DE PROPÓSITO.
##
## `PAGINA_DO_CONTROLE` guarda o número da página de cada botão. Uma aba
## nova no MEIO renumeraria todas as de baixo, e um botão que acredita
## estar em outra página responde a clique sem estar desenhado — a pior
## espécie de defeito, porque só aparece na mão de quem estiver usando.
const PAGINAS := ["OPERAÇÃO", "GOLPE", "CÂMERA E SOM", "DADOS", "SACO"]

## Os retângulos dos botões NÃO são escritos à mão. Um par de − / + com o
## valor no meio é um "passo" (`_passo`), e é ele que decide onde ficam
## os dois botões e onde sobra espaço para o número. Foi um número
## escrito por cima de um botão que motivou isso: com a conta num lugar
## só, o texto não tem como invadir a área de clique.
const LADO_BOTAO := 64.0
## Passos: chave -> retângulo total (botões nas pontas, valor no meio).
## NENHUM RETÂNGULO PODE ENCOSTAR NO OUTRO **DENTRO DA MESMA PÁGINA**.
const PASSOS := {
	"vmin": Rect2(110, 404, 400, LADO_BOTAO),
	"vmax": Rect2(570, 404, 400, LADO_BOTAO),
	# O SOCO DE REFERÊNCIA FICA LOGO ABAIXO DO PISO E DO TETO: ele é a
	# terceira âncora da mesma escala, e lê-lo longe das outras duas era
	# o que fazia a dificuldade parecer um ajuste à parte em vez do meio
	# da régua que ela é.
	"referencia": Rect2(110, 526, 400, 58),
	"curva": Rect2(570, 526, 400, 58),
	"porta": Rect2(110, 1470, 400, LADO_BOTAO),
	"raio": Rect2(110, 1566, 400, LADO_BOTAO),
	"vol_musica": Rect2(110, 1386, 400, LADO_BOTAO),
	"vol_efeitos": Rect2(570, 1386, 400, LADO_BOTAO),
	# --- página SACO
	"curso_motor": Rect2(110, 700, 400, LADO_BOTAO),
	"pausa_motor": Rect2(570, 700, 400, LADO_BOTAO),
}
## Botões simples: chave -> retângulo.
## AS TRÊS MOLDURAS DA PÁGINA DADOS, EM UM LUGAR SÓ.
##
## Os retângulos dos botões são `const` e as molduras são desenhadas a
## cada quadro: sem uma âncora comum, mover uma seção deixava os botões
## dela para trás — foi assim que o RITMO passou a desenhar as linhas
## acima da própria moldura.
## As mesmas âncoras para a página SACO. O botão TENTAR DE NOVO já
## nasceu 246 px acima da moldura a que pertence, por cima da linha que
## diz onde o saco está — o mesmo defeito, no mesmo dia.
const SACO_ESTADO_Y := 1120.0
const SACO_ESTADO_H := 282.0
const SACO_SOCORRO_Y := SACO_ESTADO_Y + SACO_ESTADO_H + 24.0

const DADOS_DIAG_Y := 600.0
const DADOS_RITMO_Y := 1194.0
const DADOS_APAGAR_Y := 1490.0

const BOTOES_SIMPLES := {
	"fechar": Rect2(920, 140, 68, 64),
	# --- página OPERAÇÃO
	"modo_livre": Rect2(110, 406, 400, 68),
	"modo_ficha": Rect2(570, 406, 400, 68),
	"mapear_start": Rect2(110, 620, 400, 68),
	"mapear_credito": Rect2(570, 620, 400, 68),
	# --- página GOLPE
	# OS TRÊS BOTÕES QUE REGULAM A MÁQUINA EM UM SOCO.
	#
	# O assistente pede dez golpes e quatro passos. Ele continua sendo o
	# jeito certo de calibrar do zero, mas não é o que se quer com a fila
	# esperando e a máquina pagando mil pontos para todo mundo: aí se quer
	# bater UMA vez e dizer "este é o máximo". É isso, e é imediato.
	"usar_min": Rect2(110, 708, 275, 56),
	"usar_ref": Rect2(402, 708, 276, 56),
	"usar_max": Rect2(695, 708, 275, 56),
	"auto_escala": Rect2(110, 876, 400, 60),
	"esquecer_escala": Rect2(570, 876, 400, 60),
	"calibrar": Rect2(300, 1302, 480, 56),
	"eixo": Rect2(620, 1470, 280, LADO_BOTAO),
	"enviar_config": Rect2(110, 1782, 400, 56),
	"testar": Rect2(570, 1782, 400, 56),
	# --- página CÂMERA
	"camera": Rect2(110, 410, 260, 60),
	"trocar_camera": Rect2(390, 410, 260, 60),
	"foto_teste": Rect2(670, 410, 300, 60),
	# Três na mesma linha: a exigência da câmera nasceu aqui e não cabia
	# numa faixa nova sem empurrar a prévia para cima do diagnóstico.
	"espelhar_camera": Rect2(110, 484, 280, 56),
	"sondar_camera": Rect2(400, 484, 280, 56),
	"camera_obrigatoria": Rect2(690, 484, 280, 56),
	"diagnosticar": Rect2(110, 920, 400, 56),
	"instalar_camera": Rect2(570, 920, 400, 56),
	"testar_som": Rect2(300, 1498, 480, 60),
	# --- página DADOS
	"zerar": Rect2(110, DADOS_APAGAR_Y + 70.0, 207, 60),
	"zerar_stats": Rect2(327, DADOS_APAGAR_Y + 70.0, 207, 60),
	"zerar_ranking": Rect2(544, DADOS_APAGAR_Y + 70.0, 207, 60),
	"reconectar": Rect2(761, DADOS_APAGAR_Y + 70.0, 209, 60),
	"teto_efeitos": Rect2(110, DADOS_RITMO_Y + 196.0, 400, 56),
	# --- página SACO
	"motor_ligado": Rect2(110, 400, 400, 64),
	"motor_fim_curso": Rect2(570, 400, 400, 64),
	"motor_desce": Rect2(110, 950, 275, 64),
	"motor_sobe": Rect2(402, 950, 275, 64),
	"motor_para": Rect2(695, 950, 275, 64),
	"motor_destrava": Rect2(110, SACO_SOCORRO_Y + 66.0, 400, 60),
	# --- sempre visíveis
	"padroes": Rect2(110, 1782, 400, 68),
	"salvar": Rect2(570, 1782, 400, 68),
}
## Em que página cada controle vive. `-1` quer dizer "em todas".
##
## Sem esta tabela, um clique numa página acertaria o botão de outra —
## os retângulos continuam existindo mesmo quando não estão desenhados, e
## um botão invisível que responde é a pior espécie de defeito.
const PAGINA_DO_CONTROLE := {
	"fechar": -1, "padroes": -1, "salvar": -1,
	"modo_livre": 0, "modo_ficha": 0, "mapear_start": 0, "mapear_credito": 0,
	"vmin": 1, "vmax": 1, "referencia": 1, "curva": 1,
	"usar_min": 1, "usar_ref": 1, "usar_max": 1, "auto_escala": 1,
	"esquecer_escala": 1,
	"porta": 1, "eixo": 1, "raio": 1, "enviar_config": 1, "testar": 1,
	"calibrar": 1,
	"camera": 2, "trocar_camera": 2, "foto_teste": 2,
	"espelhar_camera": 2, "sondar_camera": 2, "instalar_camera": 2, "diagnosticar": 2,
	"camera_obrigatoria": 2,
	"vol_musica": 2, "vol_efeitos": 2, "testar_som": 2,
	"zerar": 3, "zerar_stats": 3, "zerar_ranking": 3, "reconectar": 3,
	"teto_efeitos": 3,
	"motor_ligado": 4, "motor_fim_curso": 4, "curso_motor": 4, "pausa_motor": 4,
	"motor_desce": 4, "motor_sobe": 4, "motor_para": 4, "motor_destrava": 4,
}
## As abas, no topo da caixa.
const ABA_LARGURA := 184.0
const ABA_RECT := Rect2(80, 250, 920, 62)

var state: GameDef.State = GameDef.State.IDLE
var central_aberta := false
var game_mode := "credit"
var credits := 0
var plays := 0
## AS CINCO MELHORES MARCAS, em ordem decrescente.
##
## Guardar cinco em vez de uma só não é enfeite: com um recorde único,
## quem não bate o recorde não ganha nada, e o recorde de uma máquina
## movimentada fica inalcançável em uma semana. Com uma lista, entrar em
## quinto ainda é entrar — e é essa pequena vitória que faz a pessoa
## pagar a segunda ficha.
var ranking: Array[Dictionary] = []
## Faixa de velocidade (m/s) que vira pontos no placar.
var hit_min_speed := ScoreCurve.DEFAULT_MIN_SPEED
var hit_max_speed := ScoreCurve.DEFAULT_MAX_SPEED
## O SOCO DE REFERÊNCIA — o botão de dificuldade da casa.
##
## É a velocidade que paga exatamente 5000 pontos, metade do placar. Os
## oito níveis têm faixas FIXAS, então é aqui — e só aqui — que se decide
## quanta gente chega a cada um deles. Subir este número é dizer "aqui
## tem de bater mais forte para tirar meio placar", que é uma frase
## defensável na frente do cliente; o expoente que ocupava este lugar
## não era. Ver `ScoreCurve`.
var score_ref_speed := ScoreCurve.REFERENCIA_AUTOMATICA
## Quanto a nota se espalha ENTRE as três âncoras. Não mexe em nenhuma
## delas: um soco de referência paga 5000 com qualquer contraste.
var score_contraste := ScoreCurve.DEFAULT_CONTRASTE
var score_dead_zone := ScoreCurve.DEFAULT_DEAD_ZONE
## A RÉGUA QUE A MÁQUINA APRENDE SOZINHA. Ver `AutoEscala` — é a resposta
## ao "não consigo passar de mil", e a razão de a faixa de fábrica ter
## deixado de ser um palpite que precisa estar certo.
var auto_escala := AutoEscala.new()
## A última velocidade aceita, em m/s. Fica à vista na Central: sem ela,
## quem opera não tem como saber se o problema é o soco ou a régua.
var ultima_velocidade := 0.0
var ultima_nota := 0
## Configuração enviada ao firmware (CONFIG,eixo,raio,vmin,pulso_ms).
var sensor_eixo := "A"
var sensor_raio := 0.020
## O PISO QUE O JOGO MANDA À PLACA É O MESMO PISO DA PONTUAÇÃO.
##
## Estava 0,8 aqui contra 0,30 no `ScoreCurve.DEFAULT_MIN_SPEED`, e a
## diferença não era cosmética: o jogo manda este número à placa no
## `CONFIG`, e a placa DESCARTA tudo abaixo dele. A faixa de 0,30 a 0,80
## existia na curva de pontuação e nunca chegava a ser pontuada — golpe
## fraco legítimo sumia antes de virar linha na serial, e o "RESTAURAR
## PADRÕES" da Central já gravava 0,30, então a mesma máquina media
## diferente antes e depois de alguém tocar naquele botão.
##
## Os dois vêm da mesma fonte agora. O gatilho de 3,0 g é o mesmo com que
## o firmware V9 foi medido na bancada.
## O QUE A PLACA DIZ DA PRÓPRIA DETECÇÃO. Ver `STATUS` no firmware.
##
## `sensor_pronto` falso com a máquina PARADA é a resposta inteira para
## "o sensor não faz nada": a montagem nunca fica quieta o bastante, a
## autorização de soco nunca acende, e NENHUM golpe será aceito. Sem este
## número, isso é indistinguível de sensor desligado.
## A FORÇA QUE A PLACA ESTÁ VENDO AGORA, em g e já sem a gravidade.
## Parada, fica perto de zero. Um soco passa de 3. É o número que se
## confere a olho, e o que responde "o sensor está vivo?" sem que
## ninguém precise interpretar nada.
var sensor_forca := 0.0
var sensor_forca_maxima := 0.0
var sensor_gatilho := 0.0
## A última recusa da placa, em palavras de gente. Ver `_recusa_da_placa`.
var ultima_recusa := ""
## Os ajustes do sensor foram descartados por serem de outra escala.
var ajustes_do_sensor_zerados := false

## A ESCALA DE MEDIDA DO FIRMWARE, gravada junto dos ajustes.
##
## Os limiares do sensor e a curva de pontuação são calibrados CONTRA UM
## FIRMWARE. Quando a placa muda de escala — a V9 mudou —, os números
## guardados no disco deixam de querer dizer o que queriam, e continuam
## sendo enviados à placa no `CONFIG`: um `sensor_vmin` de 0,8 medido na
## escala antiga manda a V9 descartar tudo abaixo disso, e a máquina volta
## a não pontuar por um motivo que ninguém consegue ver.
##
## O arquivo de ajustes sobrevive à atualização do jogo — é para isso que
## ele existe —, então a defesa tem de estar aqui: ajuste de escala
## anterior é DESCARTADO e volta ao padrão desta versão. Quem tinha
## calibração fina refaz o assistente, o que é minutos; quem não tinha
## ganha uma máquina que funciona.
const ESCALA_DO_SENSOR := 10
## Evolui a dificuldade sem apagar eixo, raio e gatilho físicos já
## calibrados no gabinete.
##
## O 5 torna o padrão pesado e a autoescala usa o percentil 70. O 4 era
## a curva ancorada equilibrada. A 3 guardava um `score_exponent` de 1,5 a 4,5,
## que nesta versão não quer dizer mais nada: o campo de mesmo espírito
## agora é o contraste, de 0,70 a 1,80, e a dificuldade virou uma
## VELOCIDADE. Ler o número antigo como se fosse o novo entregaria uma
## máquina saturada no contraste máximo sem ninguém ter pedido, então a
## migração descarta os dois e recalcula a partir da faixa medida — que
## essa sim continua válida, porque foi medida no gabinete.
const ESQUEMA_DA_PONTUACAO := 5

var sensor_vmin := ScoreCurve.DEFAULT_MIN_SPEED
## O PULSO MÍNIMO EM MILISSEGUNDOS que a placa recebe no CONFIG.
##
## Ele NÃO é escolhido: sai da largura da palheta e do teto calibrado,
## em `_aplicar_faixas`. Ver `ArduinoProtocol.pulso_minimo_ms` para o
## estrago que a escolha à mão causava.
var sensor_pulso_ms := ArduinoProtocol.pulso_minimo_ms(0.020, ScoreCurve.DEFAULT_MAX_SPEED)
## Porta serial configurada; "" = automática (primeira disponível).
var porta_configurada := ""
## O par que efetivamente chegou ao MPU neste computador. É preferência,
## nunca cadeado: se mudar a COM ou o backend falhar, a busca inteira
## continua. Ao religar a máquina, evita começar do zero sem sacrificar
## a portabilidade do pacote para outro Windows.
var porta_serial_conhecida := ""
var caminho_serial_conhecido := ""

var countdown_left := 3.0
var last_count := 3
var espera_left := GameDef.ESPERA_DO_SOCO
## Se a rodada em curso debitou uma ficha. É o que autoriza a devolução
## quando a espera acaba sem soco — e, sendo consumido na devolução,
## impede que a mesma ficha volte duas vezes.
var credito_gasto := false
## DOIS SOCOS POR JOGADOR, e cada um aparece sozinho na tela.
##
## A rodada deixou de ser um golpe só. São dois, um depois do outro, e a
## interface mostra os dois SEPARADAMENTE — quem está jogando precisa ver
## o que fez o primeiro antes de armar o segundo, senão a segunda tentativa
## vira chute.
##
## A NOTA DA RODADA É O MELHOR DOS DOIS, e não a soma. A soma passaria de
## 9999, e 9999 é o teto de que dependem os oito níveis do `ScoreTier`, a
## cor da moldura de LED, a coluna das fitas, o ranking e o histórico das
## estatísticas. Somar obrigaria a mexer em todos eles e a invalidar o
## ranking que já está gravado. Com o melhor dos dois, a escala fica
## exatamente onde estava — e a segunda tentativa continua valendo a pena,
## porque ela pode substituir a primeira.
const SOCOS_POR_RODADA := 2
## Verdade quando uma queda do sensor encerrou a rodada depois do
## primeiro golpe. A nota já conquistada vale, mas a máquina não rearma
## uma segunda tentativa impossível.
var rodada_encerrada_antecipadamente := false

## ------------------------------------------------------------------
## O MOTOR QUE BAIXA E LEVANTA O SACO.
##
## O jogo nunca liga o motor: ele diz ONDE o saco deve estar, e
## `SacoMotor` cuida do resto — sem esperar, sem repetir e desistindo
## quando a placa não responde. Ver `scripts/saco_motor.gd`, que é curto
## de propósito: tudo o que pode ligar um motor cabe numa página.
var saco := SacoMotor.new()

## A FAXINA DAS FOTOS, correndo por fora do clique que a pediu.
## Ver scripts/faxina.gd: apagar centenas de arquivos dentro do clique
## congela a tela com a fila esperando.
var faxina := Faxina.new()
## QUANTO O RESULTADO DE UM SOCO FICA À VISTA ANTES DE PEDIR O PRÓXIMO.
##
## Contado a partir do VEREDITO, não do golpe: o placar já subiu e o nome
## do nível já apareceu quando este relógio começa. Dois segundos e meio é
## o tempo de ler o número e voltar a posição.
##
## E ele cobre, de sobra, o intervalo em que a placa ainda não aceita
## outro golpe (1,2 s de tempo morto mais 200 ms de repouso). Isto é de
## propósito: quando a tela diz "SOQUE", a placa já está pronta. Pedir um
## soco que seria descartado é a pior coisa que esta máquina pode fazer.
const ESPERA_PARA_O_PROXIMO_SOCO := 2.5

## QUANTO O VEREDITO FICA SOZINHO ANTES DE A TABELA ENTRAR.
##
## Eram 2,5 s ESCRITOS QUATRO VEZES, em quatro lugares que precisam
## concordar: o que solta o som do ranking, o que desliga a arena 3D, o
## que troca o desenho da tela e o que dá partida no relógio dos atos.
## Quatro cópias do mesmo número é como três delas acabam mudando e uma
## não — e nesse dia a arena continua sendo desenhada por baixo da
## tabela, ou o som do ranking toca meio segundo antes da tabela existir.
##
## O valor também encolheu, junto com os três atos abaixo. Ver lá.
const ESPERA_DO_RANKING := 1.15
## Os socos desta rodada, na ordem em que aconteceram.
## Cada item preserva pontos e também as medidas cruas que os explicam.
var socos: Array = []
## Quando o último soco entrou, em `animation_time`. É o relógio da
## animação do cartão — o cartão do soco que acabou de acontecer nasce
## grande e brilhando e assenta em meio segundo, que é o que faz a pessoa
## olhar para ELE e não varrer a tela procurando o que mudou.
var ultimo_soco_em := -100.0

## O GOLPE DESTA TENTATIVA JÁ FOI. O saco balança depois do impacto e o
## MPU-6050 vê esse balanço como um segundo evento; esta trava vale por
## tentativa, e é rearmada quando a próxima começa.
var golpe_registrado := false
## Instante do último golpe ACEITO, para o tempo morto entre eventos.
##
## Começa em NUNCA, e não em zero. `Time.get_ticks_msec()` conta desde o
## start do processo: com zero, "faz quanto tempo desde o último golpe"
## dava menos que o tempo morto durante o primeiro segundo de máquina
## ligada, e o primeiro soco da manhã era recusado em silêncio.
const NUNCA_MS := -1000000
var ultimo_golpe_ms := NUNCA_MS
## O firmware avisou que o acelerômetro saturou. Fica registrado para a
## Central; um golpe saturado NÃO vira 9999 artificial, porque a máquina
## não sabe quanto ele valeu de verdade.
var saturacao_recente := ""

## OS DOIS BOTÕES DO GABINETE, mapeados e guardados.
##
## A placa Zero Delay se apresenta ao sistema como um controle USB
## genérico, e o índice de cada botão muda conforme a porta, o cabo e o
## modelo da placa. Um índice fixo no código funciona numa máquina e erra
## na seguinte — por isso o mapeamento é feito na Central, apertando o
## botão de verdade, e o que fica gravado é o que aquela máquina viu.
##
## `guid` identifica o controle; `index` é o botão; `nome` é o que o
## sistema chama aquele controle, para o técnico reconhecer a placa.
var botao_start := {"guid": "", "index": 6, "nome": ""}
var botao_credito := {"guid": "", "index": 4, "nome": ""}
## "" | "start" | "credito" — o que a Central está esperando capturar.
var mapeando := ""
## Contadores de teste: sobem a cada aperto reconhecido. São a prova de
## que o mapeamento pegou; sem eles o técnico aperta o botão e não sabe
## se o problema é a placa, o índice ou o jogo.
var contador_start := 0
var contador_credito := 0
## ANTIRREPIQUE. Botão de arcade é chave mecânica e treme ao fechar: um
## aperto vira dois ou três eventos em poucos milissegundos, e o segundo
## viraria um crédito a mais ou um START engolindo a rodada recém-criada.
const REPIQUE_MS := 250
var ultimo_start_ms := NUNCA_MS
var ultimo_credito_ms := NUNCA_MS
## Qual página da Central está aberta.
var central_pagina := 0
## Volume das duas mesas que o operador regula, em dB. Vão do silêncio
## prático (-40) a um pouco acima do nominal (+6): um salão barulhento
## precisa de mais, e uma loja de shopping precisa de bem menos.
var volume_musica := 0.0
var volume_efeitos := 0.0
## Quanto tempo faz que alguém apertou START sem saldo. Enquanto é curto,
## o lugar do crédito pisca na abertura: apontar para onde a ficha entra
## resolve mais do que qualquer frase.
var aviso_de_credito := -1.0
## Marcado quando `_carregar` converteu marcas da escala antiga. `_ready`
## grava logo em seguida, e é isso que torna a conversão de uma vez só.
var _converteu_esquema := false
## A ESTRELA DE PANCADA: quanto tempo desde o golpe, com que força e de
## qual nível. Negativo quer dizer que não há pancada no ar.
var pancada_tempo := -1.0
var pancada_forca := 0.0
var pancada_nivel: Dictionary = {}
## HIT-STOP: o congelamento curto que dá peso ao golpe. Enquanto ele
## corre, o relógio do jogo PARA — animação, contagem e máquina de
## estados — e só a tela continua sendo desenhada. É o que faz um
## nocaute parecer que acertou alguma coisa sólida.
var hitstop_left := 0.0
## ZOOM DE IMPACTO: a tela inteira cresce um pouco e volta. Fica no
## desenho, não na câmera, porque não há câmera — o jogo é um `_draw`.
var zoom_impacto := 1.0
var zoom_alvo := 1.0
## A CORTINA ENTRE UMA TELA E OUTRA.
##
## Antes as telas trocavam no meio de um quadro: a foto virava o alvo, o
## alvo virava o placar, tudo de um pixel para o outro. Num monitor de
## fliperama isso não lê como "mudou de tela", lê como falha de imagem.
##
## Agora uma faixa diagonal atravessa a tela a cada troca, na cor da
## marca, com o alvo do jogo montado nela. Meio segundo, o tempo de a
## pessoa entender que a máquina avançou.
var transicao := -1.0
const TRANSICAO_DURACAO := 0.38
var result_score := 0
var result_speed := 0.0
var result_simulado := false
## Posição conquistada no ranking (1 a 20), ou 0 se o golpe não entrou.
var posicao_no_ranking := 0
var displayed_score := 0.0
var animation_time := 0.0
var state_time := 0.0
var result_time := 0.0
var verdict_time := -1.0
var proximo_tique := 0
var proximo_fogo := 0.0
var tremor := 0.0
var clarao := 0.0
var notice := ""
var notice_left := 0.0
var confirm_action := ""
var confirm_until := 0.0

## Serial.
var link: SerialLink
var serial_status := "INICIANDO"
var porta_atual := ""
var ultimo_sinal_ms := -1
var proxima_tentativa := 0.0

## ------------------------------------------------------------------
## A BUSCA PELO ARDUINO NÃO PODE ENGASGAR O JOGO.
##
## MEDIDO: `_tentar_conectar` custa 26 ms — 6 ms para enumerar as portas
## e 20 ms para o sistema recusar uma que não existe. Enquanto a placa
## não responde, isso se repete a cada 0,15 a 1,5 segundo, no MEIO do
## laço do jogo. Com o quadro inteiro tendo 16,7 ms de orçamento, cada
## tentativa é um quadro perdido, e o pior caso medido foi de 124 ms —
## sete quadros seguidos parados.
##
## Rodando o jogo sem nenhuma tentativa, o quadro fica em 6,9 ms do
## primeiro ao último, com p95 de 7,1. Com elas, a mediana sobe para 9,1
## e o p95 para 33,5. Era a maior fonte de engasgo do jogo — e a que
## nenhum teste pegava, porque só aparece na máquina em que o Arduino
## ainda não respondeu: ou seja, em toda máquina, nos primeiros segundos,
## e a noite inteira naquela em que o cabo está solto.
##
## Duas medidas, e nenhuma delas desiste de reconectar:

## 1) A LISTA DE PORTAS SAI DO LAÇO DO JOGO.
##
##    Enumerar as seriais do sistema custa 5 ms no caso comum e, medido,
##    105 ms em duas de cada doze vezes — o sistema operacional às vezes
##    para para conversar com um driver (no Windows, tipicamente uma
##    porta Bluetooth). Cento e cinco milissegundos é SEIS QUADROS
##    perdidos de uma vez, e nenhuma quantidade de cache resolve um
##    engasgo desse tamanho: só tira dele a frequência.
##
##    Então a enumeração acontece numa thread, e o laço do jogo usa
##    sempre a última lista conhecida. A busca continua tão agressiva
##    quanto era; o que mudou é quem espera por ela.
##
##    E AS CHAMADAS AO `link` NUNCA SE CRUZAM. Enquanto a thread está
##    enumerando, o laço principal não tenta abrir porta nenhuma — em vez
##    de trancar (o que devolveria a espera ao jogo), ele simplesmente
##    deixa esta volta passar. A próxima vem em um décimo de segundo.
const ESPERA_DA_LISTA := 2.0
## NA CENTRAL A LISTA É VIGIADA DE PERTO.
##
## É lá que o técnico está com a placa na mão, espetando o cabo e
## olhando para a tela. Dois segundos de intervalo, somados à volta da
## fila, faziam a máquina levar dez ou quinze segundos para reagir a um
## cabo que já estava no lugar — e nesse intervalo a tela dizia
## "DESCONECTADO", que é a frase mais errada possível para a situação:
## a placa ESTÁ conectada, quem ainda não sabe é o jogo.
const ESPERA_DA_LISTA_NA_CENTRAL := 0.6
var _lista_pedida_em := -99.0
var _lista_ja_veio := false
## A primeira lista não tem com o que ser comparada: sem esta bandeira,
## toda porta que o PC já tinha seria anunciada como recém-chegada no
## arranque.
var _lista_comparavel := false
## A PORTA QUE ACABOU DE APARECER NO SISTEMA — ou seja, o cabo que
## alguém acabou de espetar. Ela fura a fila: é, de longe, o lugar mais
## provável de estar a placa.
var _porta_recem_chegada := ""
## QUANDO A PLACA FALOU PELA PRIMEIRA VEZ. Só serve para a Central
## comemorar por um instante — ver `_seletor_porta_refinado`.
var _placa_achada_em := -99.0

## 2) DURANTE O SOCO, A BUSCA ESPERA. Quando a porta não está aberta, o
##    golpe não vai ser lido de qualquer jeito — reconectar meio segundo
##    depois não muda nada para quem joga, e não travar a tela no meio do
##    golpe muda tudo. A espera tem teto: se uma rodada atrás da outra
##    segurasse a busca para sempre, a máquina nunca mais acharia a placa.
const TETO_DA_ESPERA_DO_SOCO := 4.0
var _busca_adiada_desde := -1.0
var proximo_ping := 0.0
## Última telemetria, exibida na Central Técnica.
var telemetria := ""
var portas_visiveis: PackedStringArray = []
## Quantos apertos de botão chegaram PELA SERIAL nesta sessão. Separados
## dos do Zero Delay de propósito: são dois caminhos diferentes, e saber
## qual dos dois está mudo é metade do conserto.
## O MPU-6050 se apresentou nesta sessão? Separado de "a placa
## respondeu": desde que o firmware deixou de travar sem sensor, as duas
## coisas passaram a ser independentes.
## O estado CRU dos dois pinos, como a placa os lê agora. Não é "o jogo
## aceitou o aperto": é o fio.
var pino_start := false
var pino_credito := false
var sensor_presente := false
var firmware_optico_identificado := false
## Assim que o firmware se identifica, esta COM deixa de ser uma candidata:
## ela e a placa. Durante a calibracao o jogo pode esperar ou reabrir essa
## mesma porta, mas nunca volta a passear por Bluetooth e portas virtuais.
var porta_arduino_identificada := ""
var placa_calibrando := false
var progresso_calibracao := 0
var mensagem_sensor_publica := ""
var serial_start := 0
var serial_credito := 0
## Quando a porta atual foi CONFIRMADA aberta. Serve para desistir dela.
var _porta_aberta_em := 0.0
## Quando a abertura foi PEDIDA. Não é a mesma coisa, e a diferença é o
## defeito: pela ponte por processo o pedido atravessa um cano, um
## PowerShell e um driver antes de a porta abrir de verdade. Contar a
## paciência a partir do pedido é descontar dela o tempo do encanamento —
## e num PC lento o encanamento come a paciência inteira antes de a placa
## ter chance de falar. Ver `ESPERA_DA_CONFIRMACAO`.
var _porta_pedida_em := 0.0
var _porta_confirmada := false
## A fila de portas desta volta, e onde a volta está.
var _fila_de_portas: PackedStringArray = []
## Quantas voltas completas já foram dadas na fila. Vai para a tela: uma
## busca que mostra o número da volta é uma busca que se vê acontecendo,
## e não uma que "nunca termina".
var _varreduras := 0
## Quantas vezes a porta FIXADA na Central falhou seguidas.
var _falhas_da_porta_fixa := 0
## Quando o caminho atual até a placa entrou em uso, e quantas vezes o
## jogo já trocou de caminho nesta sessão.
var _caminho_desde := 0.0
var _trocas_de_caminho := 0
var _proxima_escolha_de_caminho := 0.0
## A VARREDURA CEGA, UMA VEZ LIBERADA, NÃO VOLTA A SER TRANCADA.
##
## Ela entra depois da primeira volta sem sucesso — e a partir daí vale
## para o resto da sessão, inclusive depois de uma troca de caminho.
## Amarrá-la a `_varreduras`, que zera a cada troca de caminho, faria a
## troca de caminho DESLIGAR a varredura cega justamente na máquina onde
## as duas são necessárias.
## ESTE CAMINHO JÁ ENTREGOU UMA LINHA DE VERDADE NESTA MÁQUINA?
##
## Uma linha impede troca por simples demora de descoberta. Quedas
## repetidas, porém, revogam essa prova pelo disjuntor abaixo: "funcionou
## uma vez" não pode condenar a máquina a oscilar a noite inteira.
var _caminho_provado := false
## Um caminho que entrega uma linha e cai sem parar não está provado.
## Três quedas em dois minutos abrem o disjuntor e fazem o jogo tentar o
## outro backend, sem reiniciar o programa nem consumir partida.
var _quedas_do_caminho: Array[int] = []
var _troca_de_caminho_pendente := false
const QUEDAS_ATE_TROCAR_CAMINHO := 3
const JANELA_DE_QUEDAS_MS := 120000
## A PLACA JÁ FALOU NESTA PORTA? Substitui a pergunta antiga, que era
## `"CONECTADO" in serial_status` — e além de frágil ela estava errada:
## "DESCONECTADO" contém "CONECTADO", então a frase que diz que a placa
## caiu respondia que a placa estava lá.
var placa_respondeu := false

## Câmera e dados locais do proprietário. Nenhum deles depende da rede.
var camera_service: CameraService
var camera_enabled := true
## A CÂMERA É CONDIÇÃO PARA JOGAR, e não um enfeite da partida.
##
## Ligada (o padrão), a rodada não começa e a ficha não é gasta enquanto
## não houver imagem ao vivo. Desligada, a máquina volta ao
## comportamento antigo — espera a webcam por alguns segundos e joga
## assim mesmo. A chave existe para a bancada e para a manutenção: uma
## máquina que não deixa nem abrir a tela de teste sem webcam é pior do
## que uma que joga sem foto.
var camera_obrigatoria := false
## O ÍNDICE E O BACK-END QUE JÁ FUNCIONARAM NESTA MÁQUINA.
##
## Descobrir a câmera é a parte cara: no Windows, varrer dez índices em
## três back-ends leva a melhor parte de um minuto, e é isso que a
## máquina fazia toda vez que ligava. Guardado, o gabinete abre a webcam
## na primeira tentativa — e a foto da primeira partida da noite sai
## igual à da centésima.
var camera_index := 0
## O teto de efeitos escolhido na Central, guardado entre sessões.
var teto_efeitos := "AUTO"
var camera_mirrored := false
## Na Central, TESTAR FOTO congela somente o retrato capturado por um breve
## instante. Fora desse intervalo a prévia permanece ao vivo.
var foto_teste_texture: ImageTexture = null
var foto_teste_ate_ms := 0
## Quem roda os comandos de diagnóstico e publica a resposta na tela.
var medico: CameraDoctor
var statistics: Dictionary = {}
var result_photo_path := ""
var pose_finished := false
## A CONTAGEM SEGURA ENQUANTO A CÂMERA NÃO ACENDE.
##
## E segura com HORA MARCADA. Uma máquina sem webcam, com o cabo solto ou
## com o Python faltando não pode ficar sem jogar: quem pôs a ficha tem
## direito à partida, com foto ou sem. Passados estes segundos a rodada
## começa assim mesmo, e a tela diz por quê.
const ESPERA_MAXIMA_DA_CAMERA := 12.0
var aguardando_camera := false
var espera_da_camera := 0.0
## Esta rodada já desistiu da câmera e segue sem foto. Só é possível com
## a exigência desligada na Central — ver `camera_obrigatoria`.
var pose_sem_camera := false
## A FOTO É DA POSE FINAL, NÃO DE QUALQUER MOMENTO DA CONTAGEM.
##
## Ver o comentário grande em `_processar_contagem`. O obturador só abre
## dentro desta janela final, em segundos antes de a contagem zerar.
const JANELA_TARDIA_OBTURADOR_SEGUNDOS := 0.5
var _obturador_tardio_aberto := false
var photo_retained := false
var ranking_announced := false
## Instante em que a tabela realmente começou. Uma comemoração longa
## pode adiar a classificação sem fazer a animação correr escondida.
var ranking_started_at := -1.0
var intro_active := true
var intro_time := 0.0
## O CARREGADOR SEGURA A ENTRADA. Enquanto a tela de carregamento cobre o
## jogo (shaders compilando, texturas subindo), a entrada fica parada no
## primeiro quadro e o vigia de desempenho não mede nada: os quadros
## lentos do arranque não são a máquina, são o arranque. Ver
## `scripts/carregador.gd`.
var entrada_segurada := false
## O QUANTO A ABERTURA JÁ CHEGOU, de 0 a 1.
##
## A entrada termina pousando o emblema e o letreiro exatamente onde a
## abertura os desenha, e por isso esses dois não podem esmaecer de novo.
## Mas o resto da abertura — o cabeçalho, o convite, os créditos — não
## existe na entrada e apareceria de um quadro para o outro. Este número
## faz só essa mobília entrar suave, sem tocar no que já estava na tela.
var abertura_chegada := 1.0
## Quanto tempo a tela de espera está no ar sem repetir a apresentação.
var atracao_relogio := 0.0
var _photo_cache: Dictionary = {}
## O CACHE DE FOTOS NÃO PODE SER DECODIFICADO NA LINHA DO JOGO.
##
## `_photo_texture` lê o arquivo e decodifica o JPEG na hora — barato UMA
## vez, mas o Top 20 mostra até cinco fotos por quadro durante a entrada
## animada da tabela, e toda foto ainda não vista custa isso de novo. É
## esse o travamento "ao apresentar o ranking": não é um travamento só,
## é um por foto nova que aparece rolando.
##
## A decodificação agora roda no pool de linhas do Godot — o mesmo
## esquema já usado para o quadro da câmera em `camera_service.gd` — e
## a linha do jogo só cria a textura (rápido) quando a imagem já está
## pronta. Chamado assim que o placar entra no ranking, isso dá vários
## segundos de folga antes de a tabela precisar de fato mostrar a foto.
var _mutex_fotos := Mutex.new()
var _fotos_decodificadas: Dictionary = {}

## O QUE A ARENA DEIXOU DO ÚLTIMO GOLPE, guardado para a tela ler.
##
## `_draw` roda sessenta vezes por segundo e não pode sortear frase nem
## perguntar "houve nocaute?" a cada passagem: a frase trocaria de texto
## no meio da leitura. O golpe decide uma vez, aqui, e a tela só mostra.
var arena_frase := ""
var arena_nocaute := false
## Quantos socos já foram dados — a semente das frases. Ver `ArenaFrases`.
var arena_semente := 0

var fx := PunchFX.new()
## O RELÓGIO DO JOGO. Ver `Ritmo` para o que ele conserta e por quê.
var ritmo := Ritmo.new()
## O VIGIA DO RITMO. Mede o quadro e, quando a máquina não dá conta,
## manda os efeitos gastarem menos — sozinho, sem ninguém configurar.
var desempenho := Desempenho.new()
## Deslocamento do tremor no quadro atual. Fica guardado porque o texto
## curvo troca a transformação do canvas e precisa devolvê-la exatamente
## como estava — senão o tremor some do resto da tela a partir dali.
var _deslocamento := Vector2.ZERO
## AS DUAS LETRAS DA MÁQUINA — e o motivo de serem duas.
##
## A Bungee é uma fonte de CARTAZ: letra larga, caixa alta, feita para
## ser lida atravessando a rua. É a letra certa para PUNCH CHALLENGE, para
## a pontuação e para o nome da faixa do golpe, e é ela que combina com o
## logotipo da casa.
##
## O erro era usar a mesma Bungee nos rótulos de 22 px. Nesse corpo ela
## fecha os contra-formas — o buraco do "a", do "e", do "o" —, os acentos
## grudam na letra e a linha vira uma barra cinza: exatamente o "feio e
## embaçado" que se vê na tela. Nenhum ajuste de renderização conserta
## isso, porque não é falta de nitidez, é a fonte errada para o tamanho.
##
## A Saira Condensed entra só onde se LÊ: rótulos, instruções, Central
## Técnica, rodapés. É estreita (cabe "PRESSIONE START" sem encolher),
## tem acentuação completa do português e mantém o buraco da letra aberto
## a 20 px. O cartaz continua Bungee, então a identidade não muda — muda
## só o lugar em que a letra tinha de trabalhar e não conseguia.
var fonte: Font        ## Bungee: o cartaz.
var fonte_texto: Font  ## Saira Condensed: a leitura.
var logo: Texture2D = null

@onready var letreiro_do_nome: Letreiro = $Letreiro
@onready var fundo: PunchBackground = $Fundo
@onready var moldura: LedFrame = $Moldura
@onready var sons: AudioBank = $Audio
## A janela 3D. Ver `scripts/arena/arena3d.gd`.
@onready var arena: Arena3D = $Arena

func _enter_tree() -> void:
	# O pai entra antes dos filhos. Definir aqui o retângulo vertical garante
	# que Fundo, Moldura, Arena e demais Controls já nasçam em 1080x1920.
	if OS.get_name() == "Android":
		anchor_left = 0.0
		anchor_top = 0.0
		anchor_right = 0.0
		anchor_bottom = 0.0
		size = TELA
		pivot_offset = Vector2.ZERO
		rotation = -PI * 0.5
		position = Vector2(0.0, 1080.0)

func _ready() -> void:
	_configurar_enquadramento_universal()
	# TV Boxes modestas nao devem descobrir o teto de efeitos no primeiro
	# impacto. O Android nasce em MEDIO e ainda pode reduzir automaticamente.
	if OS.get_name() == "Android":
		desempenho.qualidade = 0.78
		desempenho.teto = "MEDIO"
	fonte = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/Bungee-Regular.ttf"):
		fonte = load("res://assets/fonts/Bungee-Regular.ttf")
	# A letra de leitura cai para a de cartaz se o arquivo faltar: uma
	# tela com a fonte errada ainda é uma tela; uma tela sem fonte não é.
	fonte_texto = fonte
	if ResourceLoader.exists("res://assets/fonts/SairaCondensed-ExtraBold.ttf"):
		fonte_texto = load("res://assets/fonts/SairaCondensed-ExtraBold.ttf")
	letreiro_do_nome.fonte = fonte
	fx.vigia = desempenho
	fx.montar(self)
	fx.aquecer()
	if ResourceLoader.exists("res://assets/logo_lazersport.png"):
		logo = load("res://assets/logo_lazersport.png")
	_carregar()
	# Na edicao da TV Box a webcam faz parte do gabinete. Uma preferencia
	# antiga salva como desligada nao pode impedir a solicitacao no arranque.
	if OS.get_name() == "Android":
		camera_enabled = true
	# AQUECE O CACHE DE FOTOS ANTES DE PRECISAR DELE. A primeira vez que
	# o Top 20 aparece depois de a máquina ligar era exatamente a pior
	# hora para decodificar vinte JPEGs na linha do jogo -- é quando
	# menos se espera um travamento, logo na primeira rodada do dia.
	_prewarm_fotos_do_ranking()
	camera_service = CameraService.new()
	camera_service.enabled = camera_enabled
	camera_service.selected_index = camera_index
	camera_service.mirrored = camera_mirrored
	add_child(camera_service)
	medico = CameraDoctor.new()
	medico.terminou.connect(_fim_do_exame)
	add_child(medico)
	sons.set_volumes(volume_musica, volume_efeitos)
	_aplicar_faixas()
	if ajustes_do_sensor_zerados:
		ajustes_do_sensor_zerados = false
		_show_notice("FIRMWARE NOVO: AJUSTES DO SENSOR VOLTARAM AO PADRÃO")
		_salvar()
	if _converteu_esquema:
		_converteu_esquema = false
		_salvar()
		_show_notice("CONFIGURAÇÃO DE PONTUAÇÃO ATUALIZADA")
	_montar_arena()
	_iniciar_serial()
	_entrar_em_abertura()
	# A música entra baixa por baixo da entrada e sobe na virada para a
	# abertura: a trilha crescendo é o que faz a entrada terminar em vez
	# de simplesmente parar. As deixas da entrada tocam por cima.
	sons.music(-30.0)
	set_process(true)

## Mantém o quadro lógico em 1080x1920 e deixa o Godot calcular a escala
## final. Não aplicamos margem nem reduzimos o nó raiz: em uma tela 9:16 o
## jogo ocupa todos os pixels, sem a moldura que a primeira correção criou.
## Em outra proporção, `KEEP` preserva o desenho sem zoom, corte ou deformação.
func _configurar_enquadramento_universal() -> void:
	# Na Smart Pro o jogo vive num SubViewport vertical e a cena externa gira
	# o quadro inteiro. Alterar a Window aqui recolocaria o Android no modo de
	# compatibilidade pequeno que este adaptador existe para evitar.
	if get_viewport() is SubViewport:
		pivot_offset = Vector2.ZERO
		scale = Vector2.ONE
		position = Vector2.ZERO
		return
	var janela := get_window()
	if janela != null:
		if OS.get_name() == "Android":
			# A Smart Pro recusa um framebuffer 1080x1920 e o reduz no centro.
			# Mantemos a Window em 1920x1080 e giramos esta cena 1080x1920.
			janela.content_scale_size = Vector2i(1920, 1080)
		else:
			janela.content_scale_size = Vector2i(int(TELA.x), int(TELA.y))
		janela.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		janela.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		janela.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	pivot_offset = Vector2.ZERO
	scale = Vector2.ONE
	if OS.get_name() == "Android":
		# 1080x1920 rotacionado -90 graus ocupa exatamente 1920x1080.
		anchor_left = 0.0
		anchor_top = 0.0
		anchor_right = 0.0
		anchor_bottom = 0.0
		size = TELA
		rotation = -PI * 0.5
		position = Vector2(0.0, 1080.0)
	else:
		rotation = 0.0
		position = Vector2.ZERO

func _ponto_da_tela_para_o_jogo(ponto: Vector2) -> Vector2:
	if OS.get_name() == "Android":
		# Inversa de: tela = (jogo.y, 1080 - jogo.x).
		return Vector2(TELA.x - ponto.y, ponto.x)
	return ponto

## PÕE O LUTADOR NA ARENA.
##
## O CORPO É CONSTRUÍDO UMA VEZ, no arranque, e nunca no meio de uma
## rodada: montar malha durante o jogo é engasgo garantido, e é
## justamente no primeiro soco que ele apareceria.
##
## O LUTADOR É UMA FOLHA DE NOVE POSES DESENHADAS. Ela viaja no pacote
## como qualquer outro recurso e é carregada uma vez aqui; o que a
## transforma num lutador que se mexe é o movimento procedural de
## `Lutador3D` — recuo, cambaleio, tombo, respiração — e não uma
## animação gravada. Ver `docs/ARENA.md`.
func _montar_arena() -> void:
	if arena == null:
		return
	arena.qualidade = desempenho.qualidade
	if arena.instalar():
		arena.preparar()
		# Compila shaders e sobe as texturas agora, fora da vista, e não
		# no primeiro soco.
		arena.aquecer()
	else:
		push_warning("Arena: o lutador subiu sem todas as poses.")

## A ARENA SÓ EXISTE NAS TELAS EM QUE APARECE.
##
## Fora daqui o `SubViewport` fica com o desenho DESLIGADO — não é uma
## imagem escondida, é uma imagem que não chega a ser calculada. Numa TV
## Box isso é a diferença entre o mundo 3D custar o dia inteiro e custar
## só os segundos em que alguém está olhando para ele. A tabela de
## recordes (`ESPERA_DO_RANKING`) e a Central também não o querem: ali
## a moldura já saiu da tela.
func _arena_no_ar() -> bool:
	if central_aberta or intro_active:
		return false
	if _tabela_no_ar():
		return false
	return state in [GameDef.State.COUNTDOWN, GameDef.State.ARMED, GameDef.State.MEASURING, GameDef.State.RESULT]

func _exit_tree() -> void:
	# A THREAD DA ENUMERAÇÃO FECHA PRIMEIRO, e antes de o `link` sumir:
	# ela está falando com ele. Aqui — e só aqui — vale esperar, porque
	# não há mais quadro para estragar.
	if link != null:
		link.close_port()
		# A ponte por processo tem um ajudante do lado de fora: fechar a
		# porta nao basta, o processo precisa ir junto. Sem isto o jogo
		# fecha e deixa um PowerShell segurando a COM -- e a proxima
		# partida nao consegue abrir a porta da propria maquina.
		link.encerrar()
	# A ÚLTIMA GRAVAÇÃO NÃO PODE FICAR NO AR. Mexer num ajuste e fechar a
	# máquina em seguida perderia a mudança se ninguém esperasse o disco.
	SettingsStore.encerrar()
	_photo_cache.clear()

## Um lugar só onde os parâmetros da curva são saneados.
##
## Os oito níveis têm faixas fixas, então não há mais limite ajustável
## para arrumar: o que precisa de saneamento é a curva, e ela é a mesma
## que a Central desenha, que o placar usa e que o firmware recebe. Uma
## passagem só por `ScoreCurve.sanitize` mantém as três concordando.
func _aplicar_faixas() -> void:
	var cfg := ScoreCurve.sanitize(
		hit_min_speed, hit_max_speed, score_contraste, score_dead_zone, score_ref_speed
	)
	hit_min_speed = cfg["min_speed"]
	hit_max_speed = cfg["max_speed"]
	score_contraste = cfg["contraste"]
	score_dead_zone = cfg["dead_zone"]
	score_ref_speed = cfg["ref_speed"]
	# O PULSO MÍNIMO É CONSEQUÊNCIA, NÃO ESCOLHA.
	#
	# Ele é o único ajuste do sensor que não descreve a montagem: descreve
	# o que a montagem IMPLICA. Largura da palheta e teto de velocidade
	# são medidos; o pulso sai deles por divisão. Deixá-lo como um passo
	# de − e + ao lado dos outros foi o que permitiu que a calibração
	# escrevesse gravidades num campo de milissegundos e estrangulasse a
	# máquina em silêncio — ver `Calibracao`.
	#
	# Recalculando aqui, junto de toda mudança de faixa ou de palheta, o
	# número nunca mais pode ficar para trás do resto da configuração.
	sensor_pulso_ms = ArduinoProtocol.pulso_minimo_ms(sensor_raio, hit_max_speed)

## O SOCO DE REFERÊNCIA EM m/s, sempre — nunca o zero que quer dizer
## "automático".
##
## `score_ref_speed` guarda 0 enquanto ninguém escolheu, e nesse caso é a
## curva que decide onde a âncora cai. Mas a tela precisa de um número
## para desenhar, e o passo de − e + precisa de um número de onde partir:
## os dois perguntam aqui e recebem exatamente o valor que a pontuação
## vai usar. Uma fonte só evita a discórdia clássica — a Central
## mostrando um número e o placar usando outro.
func _referencia_efetiva() -> float:
	return float(ScoreCurve.sanitize(
		hit_min_speed, hit_max_speed, score_contraste, score_dead_zone, score_ref_speed
	)["ref_speed"])

## A melhor marca da casa. Sai do topo do ranking, e não de uma variável
## paralela — duas fontes para o mesmo número é como elas divergem.
func _melhor() -> int:
	return RankingStore.best(ranking)

## Insere uma pontuação e devolve a posição conquistada (1 a 5), ou 0 se
## ela não foi boa o bastante para entrar na lista.
func _entrar_no_ranking(pontos: int, foto := "", origem := "SENSOR") -> int:
	var inserted := RankingStore.insert(ranking, pontos, foto, origem)
	ranking.assign(inserted["entries"])
	for path in inserted["dropped_photos"]:
		RankingStore.delete_photo(path)
	return int(inserted["position"])

## ONDE O SOCO ATERRISSA NA TELA.
##
## Antes era o saco de pancadas desenhado que dizia o ponto. Sem ele, o
## alvo é o próprio visor: é dele que saem as ondas, as faíscas e o
## clarão, e é para ele que a tela de espera chama o punho. Um lugar só,
## para que efeito e imagem nunca discordem.
func _alvo() -> Vector2:
	return ALVO_DO_SOCO

# ======================================================================
# CICLO
# ======================================================================
func _process(delta: float) -> void:
	# O impacto não suspende mais a UI, partículas e relógios da rodada.
	# O clarão/tremor já comunicam a pancada sem congelar a tela inteira.
	hitstop_left = maxf(0.0, hitstop_left - delta)
	# A gravação pendente sai assim que a anterior termina, e nunca no
	# quadro em que ela foi pedida. Ver `SettingsStore.save_data_async`.
	SettingsStore.bombear()
	# Algumas fotos por quadro, se houver faxina aberta. Sem faxina, não
	# custa nada; com faxina, o jogo continua aceitando soco e START.
	faxina.passo()
	_colher_fotos_decodificadas()
	if not entrada_segurada:
		desempenho.medir(delta)
	# O PASSO DO JOGO NÃO É MAIS O TEMPO CRU DO QUADRO.
	#
	# Havia aqui um teto e mais nada: `minf(delta, 0.1)`. Ele resolvia o
	# caso do soluço isolado — um quadro de meio segundo não vira meio
	# segundo de jogo de uma vez — e não resolvia o caso que a queixa
	# descrevia, que é outro e é o comum: o tempo do quadro CHACOALHA
	# alguns décimos de milissegundo para cima e para baixo mesmo numa
	# máquina folgada, e com vsync numa máquina apertada chacoalha entre
	# 16,7 e 33,3 ms. Um teto não vê nada disso passar. O olho vê tudo,
	# e chama de "movimento não natural".
	#
	# `Ritmo` faz as três coisas: descarta o soluço, encaixa o quadro no
	# múltiplo do relógio da tela e suaviza o que sobrou com uma dívida
	# limitada, para o jogo ficar liso SEM atrasar. A explicação inteira
	# está lá, incluindo por que a média sozinha seria uma armadilha.
	#
	# `desempenho.medir` continua recebendo o delta CRU, logo acima: um
	# vigia que olhasse para o tempo já suavizado não enxergaria o
	# engasgo que ele existe para combater.
	var passo := ritmo.passo(delta)
	# A serial recebe prioridade no começo do quadro. A câmera e a arena
	# podem custar milissegundos; o evento físico não deve esperar por elas.
	animation_time += passo
	state_time += passo
	_poll_serial(passo)
	# O cenário é a camada mais cara do jogo; quando a máquina aperta, ela
	# encolhe junto com os efeitos.
	ArcadeStage.enfeite = desempenho.qualidade
	# A MOLDURA DE LED NÃO ENCOLHIA NUNCA. Cem e tantas lâmpadas, três
	# desenhos cada, em toda tela do jogo, do início ao fim — o único
	# enfeite que ficava de fora do vigia de desempenho.
	moldura.qualidade = desempenho.qualidade
	# E OS ARCOS TAMBÉM. Eram a última camada cara que nunca encolhia:
	# 96 segmentos com borda lisa, do anel de 1300 pixels ao de 90, em
	# todo quadro do impacto. Ver `Traco.arco`.
	Traco.qualidade = desempenho.qualidade
	if arena != null:
		arena.qualidade = desempenho.qualidade
		arena.ligar(_arena_no_ar())
		arena.avancar(passo)
	_socorro_da_camera(passo)
	if camera_service != null:
		camera_service.definir_ritmo(_ritmo_da_camera())
	_laco_de_atracao(passo)
	zoom_impacto = lerpf(zoom_impacto, zoom_alvo, clampf(passo * 7.0, 0.0, 1.0))
	if absf(zoom_impacto - 1.0) < 0.002 and is_equal_approx(zoom_alvo, 1.0):
		zoom_impacto = 1.0
	fx.atualizar(passo)
	# Poeira dourada subindo do rodapé, só na tela de espera.
	fx.brisa(
		"abertura", Rect2(120.0, TELA.y + 10.0, 840.0, 40.0), Color(Paleta.AMBAR, 0.30), 4.0,
		state == GameDef.State.IDLE and not intro_active and not central_aberta
	)
	# O FUNDO ANDA NO RELÓGIO DO JOGO, e não num relógio próprio.
	#
	# Ele tinha o seu `_process`, com a sua conta de delta e o seu teto.
	# Dois relógios para a mesma cena é como eles divergem: bastava um
	# quadro engasgado cair de um lado e não do outro para a poeira do
	# fundo andar um tanto e o resto da tela outro — e é justamente no
	# fundo, com coisa se movendo devagar e em linha reta, que essa
	# diferença aparece mais. Agora é um relógio só, o suavizado.
	fundo.avancar(passo)
	moldura.avancar(passo)
	letreiro_do_nome.avancar(passo)
	tremor = maxf(0.0, tremor - passo * 26.0)
	clarao = maxf(0.0, clarao - passo * 2.6)
	if transicao >= 0.0:
		transicao += passo
		if transicao > TRANSICAO_DURACAO:
			transicao = -1.0
	if pancada_tempo >= 0.0:
		pancada_tempo += passo
		# O zoom volta ao normal assim que o estrelão passa da metade.
		if pancada_tempo > ImpactDirector.PANCADA_DURACAO * 0.5:
			zoom_alvo = 1.0
		if pancada_tempo > ImpactDirector.PANCADA_DURACAO:
			pancada_tempo = -1.0

	if notice_left > 0.0:
		notice_left -= passo
	else:
		notice = ""
	if not confirm_action.is_empty() and animation_time > confirm_until:
		confirm_action = ""

	if central_aberta:
		_processar_calibracao(passo)
	if not central_aberta:
		match state:
			GameDef.State.IDLE:
				_processar_abertura(passo)
			GameDef.State.COUNTDOWN:
				_processar_contagem(passo)
			GameDef.State.ARMED:
				_processar_armado(passo)
			GameDef.State.MEASURING:
				if state_time >= GameDef.IMPACTO_DURACAO:
					# UM CAMINHO SÓ: todo soco vai para o resultado.
					# Quem decide se ainda há outro é o próprio resultado,
					# depois de mostrar este. Ver `_processar_resultado`.
					_entrar_em_resultado()
			GameDef.State.RESULT:
				_processar_resultado(passo)
	# Segunda coleta, barata e sem avançar relógios: pega o HIT que chegou
	# enquanto câmera/arena eram atualizadas. É especialmente importante
	# no quadro em que a contagem muda para ARMED; o golpe posterior ao
	# sino já encontra o estado correto, sem esperar o próximo desenho.
	_poll_serial(0.0)
	queue_redraw()

## Milissegundos entre quadros da webcam, conforme o que está na tela.
func _ritmo_da_camera() -> int:
	if central_aberta or state == GameDef.State.COUNTDOWN:
		return 90
	if state == GameDef.State.IDLE:
		return 700
	return 2500

func soltar_entrada() -> void:
	entrada_segurada = false
	intro_time = 0.0
	ritmo = Ritmo.new()

func _processar_abertura(delta: float) -> void:
	if intro_active and entrada_segurada:
		return
	if intro_active:
		var antes := intro_time
		intro_time += delta
		# As deixas sonoras vêm da mesma tabela que desenha a entrada.
		# Ler o intervalo (antes, agora] em vez de "passou de" é o que
		# impede uma deixa de sumir num quadro longo ou tocar duas vezes.
		for marca in ArcadeStage.intro_cues(antes, intro_time):
			sons.play(marca["cue"], marca["db"])
		# O soco da entrada sacode a máquina e cospe faíscas de verdade,
		# com o mesmo sistema do soco do jogador: uma entrada que promete
		# um impacto tem de entregar o impacto.
		if antes < ArcadeStage.T_SOCO and intro_time >= ArcadeStage.T_SOCO:
			tremor = 34.0
			clarao = 0.60
			fx.faiscas(ArcadeStage.SOCO, 26, Paleta.AMBAR, 1250.0)
			fx.onda(ArcadeStage.SOCO, 60.0, 620.0, Paleta.CREME, 12.0, 0.55)
			fx.poeira(ArcadeStage.SOCO + Vector2(0.0, 180.0), 14, Color(Paleta.AMBAR, 0.35), 380.0)
		if antes < ArcadeStage.T_MORPH and intro_time >= ArcadeStage.T_MORPH:
			sons.music(-16.0)
		if intro_time >= ArcadeStage.INTRO_SECONDS:
			intro_active = false
			# A abertura ENTRA JÁ NO AR, e não esmaecendo do zero. A
			# entrada acaba de pousar o emblema e o letreiro exatamente
			# onde a abertura os desenha; se ela ainda por cima começasse
			# com o seu próprio esmaecer, o quadro seguinte à entrada
			# seria um piscar — a única emenda visível do filme.
			state_time = 0.5
			# A vinheta já pousou o emblema e o nome nas coordenadas finais.
			# Uma segunda animação de montagem fazia todos os elementos serem
			# reposicionados e rasterizados juntos no quadro mais caro da
			# abertura. A tela principal nasce pronta nessa mesma posição.
			abertura_chegada = 1.0
		return
	abertura_chegada = minf(1.0, abertura_chegada + delta * 2.2)
	if aviso_de_credito >= 0.0:
		aviso_de_credito += delta
		if aviso_de_credito > 2.6:
			aviso_de_credito = -1.0

func _processar_contagem(delta: float) -> void:
	# A POSE INTEIRA ACONTECE SOBRE IMAGEM AO VIVO — OU NÃO ACONTECE.
	#
	# A câmera estar viva no instante do START não garante que ela
	# continue viva três segundos depois: a webcam engasga trocando a
	# exposição, o cabo dá um tranco, a ponte religa. Quando isso
	# acontecia no meio da contagem, o relógio seguia correndo em cima da
	# última imagem que existiu — a pessoa via a própria cara PARADA na
	# tela até a foto sair, e a foto era daquele quadro velho.
	#
	# Agora o relógio da pose PARA junto com a imagem e volta a andar
	# quando ela volta. A contagem não pula números, a pose não é gasta
	# esperando, e a foto é sempre de um quadro de agora.
	# A câmera nunca segura o relógio da partida. Se o quadro estiver vivo,
	# a foto entra; se não estiver, o ranking usa o avatar e todo o restante
	# do jogo segue no mesmo tempo, sem aviso de erro para o jogador.
	aguardando_camera = false
	pose_sem_camera = not (
		camera_enabled and camera_service != null and camera_service.pronta()
	)
	countdown_left -= delta
	# O OBTURADOR ABRE NA RETA FINAL, NÃO NA CONTAGEM INTEIRA.
	#
	# Antes `abrir_obturador()` era chamado lá no INÍCIO da contagem (nos
	# três segundos inteiros de "3-2-1"), com uma janela de 3,2 s — e o
	# obturador guarda o quadro de MAIOR CONTRASTE visto na janela toda,
	# não o mais recente. Isso significa que uma foto tirada no instante
	# em que a pessoa ainda está se ajeitando na frente da câmera — mal
	# chegou, luz de fundo mudando — podia vencer a pose final só por ter
	# mais contraste, mesmo a pessoa tendo se aprumado direito no segundo
	# seguinte. É exatamente "não capta se mudou depois do segundo 2".
	#
	# A pose que importa é a de QUANDO A CONTAGEM ACABA, e só ela. Abrindo
	# o obturador só na JANELA_TARDIA_OBTURADOR_SEGUNDOS final — meio
	# segundo antes de zerar —, o "melhor quadro" só pode vir de dentro
	# desse meio segundo: o suficiente para não perder a foto por um
	# único quadro escuro bem na hora, pouco o bastante para nunca mais
	# escolher uma pose de segundos atrás.
	if not pose_finished and not _obturador_tardio_aberto and camera_service != null \
			and countdown_left <= JANELA_TARDIA_OBTURADOR_SEGUNDOS:
		_obturador_tardio_aberto = true
		camera_service.abrir_obturador(int(JANELA_TARDIA_OBTURADOR_SEGUNDOS * 1000.0) + 250)
	if not pose_finished and countdown_left <= 0.0:
		pose_finished = true
		result_photo_path = camera_service.capture_photo() if camera_service != null else ""
		if not result_photo_path.is_empty() and camera_service.ultima_foto != null:
			# A textura sai da imagem que a câmera acabou de entregar, e
			# não do arquivo recém-gravado: ler o disco de volta no mesmo
			# quadro é o que fazia a imagem sumir e voltar no obturador.
			_photo_cache[result_photo_path] = ImageTexture.create_from_image(
				camera_service.ultima_foto
			)
		clarao = 0.65
		sons.play("shutter", -5.0)
		return
	var atual := maxi(0, int(ceil(countdown_left)))
	if atual > 0 and atual < last_count:
		last_count = atual
		sons.play("count")
		sons.duck(8.0, 0.5)
	if countdown_left <= -1.2:
		state = GameDef.State.ARMED
		_armar_sensor_optico()
		_iniciar_transicao()
		state_time = 0.0
		espera_left = GameDef.ESPERA_DO_SOCO
		# A rodada nova começa sem golpe e sem saturação pendente.
		golpe_registrado = false
		socos.clear()
		saturacao_recente = ""
		sons.play("round_bell", -2.0)
		sons.play("go")
		sons.music(-19.0)
		moldura.set_estado(LedFrame.ARMADA)

func _processar_armado(delta: float) -> void:
	espera_left -= delta
	if espera_left <= 0.0:
		# A ESPERA ACABOU SEM SOCO — E A FICHA VOLTA.
		#
		# Antes a rodada simplesmente morria, com o crédito já debitado:
		# quem hesitou oito segundos pagou e não jogou, e é isso que
		# fazia o saldo evaporar sozinho. O limite continua existindo,
		# senão a máquina passa a tarde armada se a pessoa foi embora,
		# mas agora ele devolve em vez de cobrar.
		# QUEM JÁ SOCOU NÃO TEM FICHA A RECEBER DE VOLTA.
		#
		# Com dois socos por rodada, a espera pode acabar no MEIO da
		# rodada — o primeiro soco saiu, o segundo não. Devolver a ficha
		# aí seria pagar de volta uma partida que aconteceu, e bastaria
		# socar uma vez e esperar para jogar de graça a noite inteira.
		# Quem já socou vai para o resultado com o que fez; só quem não
		# socou nenhuma vez recebe a ficha de volta.
		if socos.is_empty():
			sons.play("error", -4.0)
			_devolver_credito()
			_entrar_em_abertura()
		else:
			_entrar_em_resultado()

## O SEGUNDO SOCO DA RODADA.
##
## Entre um soco e outro a máquina NÃO volta ao resultado nem à abertura:
## ela rearma. O que muda em relação ao primeiro é só o relógio da espera
## e o aviso na tela — o resto do caminho do golpe é exatamente o mesmo,
## de propósito, para não haver dois jeitos de um soco ser aceito.
##
## SOBRE O TEMPO MORTO E O SEGUNDO SOCO: o firmware exige 1,2 s desde o
## fim do golpe anterior MAIS 200 ms de repouso antes de aceitar outro, e
## o jogo exige os seus 900 ms. Somado, o segundo soco só passa a valer
## cerca de 1,4 s depois do primeiro. Isso é DE PROPÓSITO: é o que impede
## o balanço do saco de gastar a segunda tentativa. Nenhuma pessoa recua o
## braço e acerta de novo em menos que isso, mas o aviso na tela existe
## para que a pausa seja lida como parte do jogo, e não como travamento.
func _armar_proximo_soco() -> void:
	# O QUE O RESULTADO DEIXOU NA TELA SAI AGORA. Sem isto, o segundo soco
	# seria pedido por cima da festa do primeiro: moldura na cor do nível,
	# fundo tingido, contagem do placar ainda rodando.
	sons.stop("score_loop")
	displayed_score = 0.0
	verdict_time = -1.0
	result_time = 0.0
	ranking_announced = false
	ranking_started_at = -1.0
	fundo.matiz = Color(0, 0, 0, 0)
	state = GameDef.State.ARMED
	_armar_sensor_optico()
	_iniciar_transicao()
	state_time = 0.0
	espera_left = GameDef.ESPERA_DO_SOCO
	golpe_registrado = false
	sons.play("round_bell", -2.0)
	sons.play("go")
	moldura.set_estado(LedFrame.ARMADA)
	if arena != null:
		arena.guardar(true)
	_show_notice("SOCO %d DE %d" % [socos.size() + 1, SOCOS_POR_RODADA])

## FECHA A RODADA E DECIDE A NOTA.
##
## Aqui, e só aqui, a rodada vira ranking, estatística e disco. Enquanto
## isso ficou dentro de `_registrar_impacto`, cada soco entrava no Top 20
## sozinho: dois socos da mesma pessoa disputavam duas linhas da tabela,
## e a estatística contava duas partidas onde houve uma.
func _fechar_rodada() -> void:
	# E O SACO SOBE. A rodada acabou: os dois socos foram dados (ou a
	# rodada foi encerrada), e daqui em diante a tela é placar e ranking.
	# Subir agora deixa o motor terminar o curso enquanto o jogador lê a
	# nota, em vez de fazer a próxima pessoa esperar por ele.
	saco.quero(SacoMotor.Onde.EM_CIMA)
	var melhor := 0
	var melhor_v := 0.0
	var simulado := false
	for soco in socos:
		if int(soco["pontos"]) >= melhor:
			melhor = int(soco["pontos"])
			melhor_v = float(soco["velocidade"])
		if bool(soco["simulado"]):
			simulado = true
	result_score = clampi(melhor, 0, GameDef.SCORE_MAX)
	result_speed = melhor_v
	result_simulado = simulado

	plays += 1
	var origem := "SIMULAÇÃO" if result_simulado else "ÓPTICO LM393"
	posicao_no_ranking = _entrar_no_ranking(result_score, result_photo_path, origem)
	photo_retained = posicao_no_ranking > 0
	# A TABELA SÓ APARECE 2,5 s (NO MÍNIMO) DEPOIS DAQUI. Tempo de sobra
	# para o pool de linhas decodificar qualquer foto do Top 20 que ainda
	# não estava em cache, antes de a tela precisar dela de verdade.
	_prewarm_fotos_do_ranking()
	statistics = StatisticsStore.record(
		statistics, result_score,
		GameDef.faixa_de(result_score),
		posicao_no_ranking > 0
	)
	_aprender_a_regua()
	_salvar()

## A RÉGUA ANDA UM PASSO EM DIREÇÃO AO QUE ESTA MÁQUINA REALMENTE MEDE.
##
## Uma vez por rodada, e nunca no meio dela: os dois socos de uma mesma
## rodada precisam ser medidos pela mesma régua, ou a pessoa vê dois
## números que não dá para comparar e a máquina perde a razão de existir.
##
## O passo é pequeno de propósito (ver `AutoEscala`). Não é para a régua
## reagir à rodada que acabou: é para ela, ao longo de algumas dezenas de
## socos, parar de descrever a bancada e passar a descrever o gabinete.
func _aprender_a_regua() -> void:
	var novo := auto_escala.passo(hit_min_speed, _referencia_efetiva(), hit_max_speed)
	if novo.is_empty():
		return
	hit_min_speed = float(novo["vmin"])
	hit_max_speed = float(novo["vmax"])
	score_ref_speed = float(novo["vref"])
	_aplicar_faixas()
	# O firmware também precisa saber: é ele que descarta abaixo de
	# `vmin` e que enche a coluna de LED até `vmax`. Uma régua nova no
	# jogo com a antiga na placa é a discordância clássica.
	_enviar_config()

## O RESULTADO É DE CADA SOCO, e não só do fim da rodada.
##
## Era assim: soco 1 → rearma calado → soco 2 → resultado. Quem jogava via
## o primeiro golpe sumir num cartãozinho e a máquina pedir outro sem
## dizer o que o primeiro valeu. O número é a razão de bater; escondê-lo
## até o fim tira metade da graça e faz a segunda tentativa virar chute.
##
## Agora o caminho é UM SÓ e se repete igual para os dois socos:
##
##     soco → impacto → PLACAR SOBE → veredito → (próximo soco | fim)
##
## A única diferença entre o primeiro e o último é o que vem depois do
## veredito: rearmar ou encerrar. Nada mais muda — mesma animação, mesma
## contagem, mesmo som. Um caminho só é o que faz a máquina ser previsível
## e o que impede um dos dois socos de ter um defeito que o outro não tem.
func _entrar_em_resultado(encerrar_rodada := false) -> void:
	if encerrar_rodada:
		rodada_encerrada_antecipadamente = true
	# A nota mostrada é a DESTE soco. A rodada só é fechada — ranking,
	# estatística, disco — quando o último golpe já foi dado.
	if socos.is_empty():
		result_score = 0
		result_speed = 0.0
	else:
		var ultimo: Dictionary = socos[socos.size() - 1]
		result_score = int(ultimo["pontos"])
		result_speed = float(ultimo["velocidade"])
	if _rodada_terminou():
		_fechar_rodada()
	else:
		# COLOCAÇÃO NO RANKING SÓ EXISTE NO FIM DA RODADA. Sem zerar aqui,
		# o resultado do primeiro soco herdaria a colocação da rodada
		# ANTERIOR e comemoraria um recorde que não aconteceu.
		posicao_no_ranking = 0
	sons.start_score_loop()
	state = GameDef.State.RESULT
	state_time = 0.0
	result_time = 0.0
	displayed_score = 0.0
	proximo_tique = 0
	proximo_fogo = 0.0
	verdict_time = -1.0

## A RODADA TERMINOU? Vale para os dois jeitos de ela acabar: os dois
## socos dados, ou a espera estourada com um soco já na conta.
func _rodada_terminou() -> bool:
	return socos.size() >= SOCOS_POR_RODADA or rodada_encerrada_antecipadamente

## "BOM" acompanha a classificação visual, sem repetir aqui o limite
## numérico que já pertence ao ScoreTier.
func _soco_foi_bom(soco: Dictionary) -> bool:
	return str(ScoreTier.de(int(soco["pontos"]))["id"]) != "LEVE"

func _dois_socos_bons() -> bool:
	return (
		socos.size() >= SOCOS_POR_RODADA
		and _soco_foi_bom(socos[0])
		and _soco_foi_bom(socos[1])
	)

## A TABELA DE RECORDES ESTÁ NA TELA?
##
## Duas condições, e a segunda foi esquecida por muito tempo porque dois
## relógios sem relação nenhuma vinham, por acaso, dando no mesmo número:
## a tabela entrava 2,5 s depois do veredito e o segundo soco era armado
## 2,5 s depois do veredito, então a tabela nunca chegava a aparecer
## ENTRE os dois socos. Encurtar a revelação desfez a coincidência — e o
## Top 20 passaria a piscar por um segundo no meio da rodada, com a
## colocação zerada, antes de a máquina pedir o segundo soco.
##
## O acaso vira regra escrita aqui: a tabela é o fim da rodada. Quem
## ainda tem soco a dar não a vê.
func _tabela_no_ar() -> bool:
	if state != GameDef.State.RESULT or not _rodada_terminou():
		return false
	if _dois_socos_bons() and sons.playing("good_player"):
		return false
	return verdict_time >= ESPERA_DO_RANKING

const SONS_RANKING_NEUTROS := [
	"ranking_neutral_1", "ranking_neutral_2", "ranking_neutral_3",
]

func _som_ranking_neutro() -> String:
	var semente := maxi(0, plays + posicao_no_ranking)
	return str(SONS_RANKING_NEUTROS[semente % SONS_RANKING_NEUTROS.size()])

func _processar_resultado(delta: float) -> void:
	result_time += delta
	var avanco := clampf(result_time / GameDef.CONTAGEM_DURACAO, 0.0, 1.0)
	# O número dispara e vai freando — o suspense que um placar de
	# arcade precisa ter. O veredito só entra quando a contagem termina.
	# Curva cúbica: ganha velocidade de imediato e assenta suavemente no
	# valor exato. O jogador vê resposta rápida sem perder a leitura final.
	# A CURVA DO NÚMERO É MAIS DIANTEIRA DO QUE ERA.
	#
	# Era cúbica (`1 - (1-t)³`), que gasta a segunda metade do tempo
	# andando os últimos dez por cento — legível, mas é ali que nasce a
	# sensação de "ele está demorando para parar". Na quarta potência o
	# número dispara, chega perto do valor quase imediatamente e só
	# assenta os últimos dígitos; a leitura é a mesma e a espera some.
	var suave := 1.0 - pow(1.0 - avanco, 4.0)
	displayed_score = float(result_score) * suave

	sons.score_progress(avanco)
	_mandar_fitas(displayed_score / float(GameDef.SCORE_MAX))

	if verdict_time < 0.0 and avanco >= 1.0:
		_disparar_veredito()
	elif verdict_time >= 0.0:
		verdict_time += delta
		_manter_festa(delta)
		# O ANÚNCIO DO RANKING TAMBÉM É DO FIM DA RODADA. Tocar o som do
		# Top 20 entre o primeiro e o segundo soco anunciaria uma
		# colocação que ainda não existe.
		if _tabela_no_ar() and not ranking_announced:
			ranking_announced = true
			ranking_started_at = verdict_time
			sons.play(_som_ranking_neutro(), -3.0)
			sons.music(-24.0)
		# Os atos têm deixas diferentes (tabela, assentamento e confete),
		# portanto precisam ser conferidos a cada quadro. Antes esta função
		# era chamada só no instante t=0 da revelação: nenhuma deixa futura
		# chegava a disparar, explicando a festa ausente ou inconsistente.
		if ranking_announced:
			_marcar_atos_do_ranking()

	# AINDA HÁ SOCO A DAR? O resultado deste fica à vista o tempo de ser
	# lido, e a máquina rearma. É o mesmo caminho do último soco até aqui;
	# só o que vem depois do veredito é diferente.
	if not _rodada_terminou():
		if verdict_time >= ESPERA_PARA_O_PROXIMO_SOCO:
			_armar_proximo_soco()
		return

	if posicao_no_ranking > 0:
		if ranking_announced and _tempo_do_ranking() > 7.0:
			_entrar_em_abertura()
	elif result_time > GameDef.RESULTADO_TIMEOUT and not sons.playing("good_player"):
		_entrar_em_abertura()

## AS DEIXAS DOS QUATRO ATOS DA ENTRADA NO RANKING.
##
## Som e confete pendurados no mesmo relógio que o desenho, e cada um
## disparado UMA VEZ. É o que faz a batida da linha e o estouro do
## confete caírem no mesmo quadro do movimento que os justifica — e não
## meio segundo antes, que é quando a festa parece solta da tela.
var _ato_assentou := false
var _ato_festejou := false
var _festa_ranking_decorrido := 0.0
var _festa_ranking_proximo := 0.0
var _festa_ranking_canhao := 0

func _marcar_atos_do_ranking() -> void:
	if posicao_no_ranking <= 0:
		return
	var celebracao := RankingCelebration.para(posicao_no_ranking)
	if celebracao.is_empty():
		return
	var t := _tempo_do_ranking()
	# A LINHA ACENDE: só o som. Tremer a tela aqui sacudia a tabela
	# inteira justamente quando a pessoa tenta ler a posição dela.
	if not _ato_assentou and t >= ATO_ANUNCIO + ATO_TABELA:
		_ato_assentou = true
		sons.play("hit", -8.0)
	# E SÓ ENTÃO O CONFETE. Durante o movimento ele vira sujeira por cima
	# da informação; depois dele, vira festa.
	if not _ato_festejou and t >= ATO_ANUNCIO + ATO_TABELA + ATO_ASSENTA:
		_ato_festejou = true
		# Um único estouro instrumental substitui as duas vozes sobrepostas.
		sons.play("ranking_burst", -1.5)
		sons.duck(10.0, 4.5)
		# O papel não nasce todo neste quadro. A festa sustentada abaixo
		# entrega mais confete sem o pico de CPU que congelava a tabela.
		_festa_ranking_decorrido = 0.0
		_festa_ranking_proximo = 0.0
		_festa_ranking_canhao = 0
		# Um tranco leve só: a festa é o confete, não a tela chacoalhando.
		tremor = maxf(tremor, float(celebracao["tremor"]) * 0.25)

func _manter_festa(delta: float) -> void:
	_manter_festa_do_ranking(delta)
	## A COMEMORAÇÃO QUE CONTINUA é do nível, e o intervalo entre os
	## estouros também. Um impacto leve tem intervalo zero e não comemora
	## nada: dizer "mandou bem" a quem não mandou é o jeito mais rápido
	## de a máquina perder a credibilidade.
	var nivel := ScoreTier.de(result_score)
	var intervalo := float(nivel["festa_intervalo"])
	# A FESTA DURA O VEREDITO INTEIRO, e não cinco segundos.
	#
	# Ela parava em 5 s, bem no meio da revelação do ranking — e a tela
	# mais importante da partida acontecia no silêncio visual que sobrava.
	# Agora acompanha o veredito até o fim, e os fogos entram no intervalo
	# do nível, que é mais espaçado do que era.
	# Os fogos param quando a tabela entra: nada explode por cima dela.
	if intervalo <= 0.0 or verdict_time >= 9.0 or verdict_time < proximo_fogo or _tabela_no_ar():
		return
	proximo_fogo = verdict_time + intervalo
	ImpactDirector.festa(fx, _alvo(), nivel, CORES_FESTA)
	# CADA FOGO TEM O SEU ESTOURO. Festa muda no som antes de mudar na
	# imagem: fogo mudo lê como enfeite de tela, não como comemoração.
	sons.play("subgrave", -14.0)

func _manter_festa_do_ranking(delta: float) -> void:
	if not _ato_festejou or posicao_no_ranking <= 0:
		return
	var celebracao := RankingCelebration.para(posicao_no_ranking)
	if celebracao.is_empty():
		return
	_festa_ranking_decorrido += delta
	var duracao := float(celebracao["confete_duracao"])
	if _festa_ranking_decorrido > duracao:
		return
	if _festa_ranking_decorrido >= _festa_ranking_proximo:
		_festa_ranking_proximo += float(celebracao["confete_intervalo"])
		var intensidade := float(celebracao["forca"]) / 700.0
		fx.chuva_de_confete(1080.0, int(celebracao["confete_lote"]), CORES_FESTA, intensidade)
	var canhoes := int(celebracao["canhoes"])
	# Canhões alternados, nunca no mesmo quadro: impacto visual maior e
	# custo distribuído. Campeão ganha centro + dois lados; pódio, lados.
	var instante_canhao := 0.18 + float(_festa_ranking_canhao) * 0.42
	if _festa_ranking_canhao < canhoes and _festa_ranking_decorrido >= instante_canhao:
		var pontos := [Vector2(120.0, 1880.0), Vector2(960.0, 1880.0), Vector2(540.0, 1920.0)]
		var ordem := [2, 0, 1] if posicao_no_ranking == 1 else [0, 1, 2]
		fx.confete(pontos[ordem[_festa_ranking_canhao]], 28, CORES_FESTA, float(celebracao["forca"]))
		_festa_ranking_canhao += 1

# ======================================================================
# ENTRADA DE COMANDOS
# ======================================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F9:
			_toggle_central()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE:
			if central_aberta:
				_fechar_central()
			elif state != GameDef.State.IDLE:
				_entrar_em_abertura()
				_show_notice("RODADA CANCELADA")
			get_viewport().set_input_as_handled()
			return
		if central_aberta:
			if event.keycode == KEY_T:
				_teste_de_golpe()
			# Setas e Page Up/Down rolam a página. O gabinete não tem
			# mouse; o teclado que o técnico pluga para configurar tem.
			elif event.keycode == KEY_DOWN:
				_rolar(ROLA_SETA)
			elif event.keycode == KEY_UP:
				_rolar(-ROLA_SETA)
			elif event.keycode == KEY_PAGEDOWN:
				_rolar(CENTRAL_JANELA * 0.8)
			elif event.keycode == KEY_PAGEUP:
				_rolar(-CENTRAL_JANELA * 0.8)
			elif event.keycode == KEY_HOME:
				central_rolagem = 0.0
			elif event.keycode == KEY_END:
				central_rolagem = _rolagem_maxima()
			get_viewport().set_input_as_handled()
			return
		# TECLADO É BANCADA. Num salão os comandos entram pelos botões do
		# gabinete ou pela serial; deixar 5/C e 1/Enter valendo sempre é
		# deixar um teclado esquecido no armário virar crédito de graça.
		if event.keycode in [KEY_5, KEY_C]:
			if _simulador_liberado():
				_add_credit()
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_1, KEY_ENTER, KEY_KP_ENTER]:
			if _simulador_liberado():
				_pressionou_start()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventJoypadButton:
		_botao_do_gabinete(event as InputEventJoypadButton)
		return

	if central_aberta and not calib_ativo and event is InputEventMouseButton and event.pressed:
		var roda := event as InputEventMouseButton
		if roda.button_index == MOUSE_BUTTON_WHEEL_UP:
			_rolar(-ROLA_RODA)
			return
		if roda.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_rolar(ROLA_RODA)
			return

	if central_aberta and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if calib_ativo:
			_click_calibracao(_ponto_da_tela_para_o_jogo(event.position))
		else:
			_click_central(_ponto_da_tela_para_o_jogo(event.position))

## OS ATALHOS DE TECLADO (5/C PARA CRÉDITO, 1/ENTER PARA START) SÃO
## FERRAMENTA DE TÉCNICO, NUNCA DE SALÃO.
##
## Só respondem com a Central aberta na frente de quem mexe na máquina.
## Fora dela, START e CRÉDITO só chegam pelos botões do gabinete ou pela
## serial — um teclado esquecido no armário não pode virar crédito de
## graça, e o soco em si só existe vindo do MPU-6050.
func _simulador_liberado() -> bool:
	return central_aberta

## UM APERTO NA PLACA ZERO DELAY.
##
## Três coisas acontecem aqui, nesta ordem: capturar um mapeamento em
## curso, recusar repique, e só então agir. Soltar o botão nunca faz
## nada — processar solta e aperta dobraria todo comando.
func _botao_do_gabinete(evento: InputEventJoypadButton) -> void:
	if not evento.pressed:
		return
	var nome := Input.get_joy_name(evento.device)
	var guid := Input.get_joy_guid(evento.device)

	# 1) A CENTRAL ESTÁ ESPERANDO ESTE APERTO?
	if central_aberta and not mapeando.is_empty():
		_gravar_botao(evento.button_index, guid, nome)
		return
	if central_aberta:
		return

	var agora := Time.get_ticks_msec()
	if _combina(botao_start, evento.button_index, guid):
		if agora - ultimo_start_ms < REPIQUE_MS:
			return
		ultimo_start_ms = agora
		contador_start += 1
		_pressionou_start()
	elif _combina(botao_credito, evento.button_index, guid):
		if agora - ultimo_credito_ms < REPIQUE_MS:
			return
		ultimo_credito_ms = agora
		contador_credito += 1
		_add_credit()

## Grava o botão capturado no papel que a Central pediu.
##
## O MESMO BOTÃO NÃO PODE ASSUMIR OS DOIS PAPÉIS. Numa máquina em que
## START e CRÉDITO fossem o mesmo aperto, cada partida consumiria uma
## ficha e começaria junto — ou nenhuma das duas coisas aconteceria na
## hora certa. Recusar é melhor do que aceitar e deixar a máquina
## indefinida.
func _gravar_botao(indice: int, guid: String, nome: String) -> void:
	var outro := botao_credito if mapeando == "start" else botao_start
	if _combina(outro, indice, guid):
		_show_notice("ESSE BOTÃO JÁ É O OUTRO COMANDO — ESCOLHA OUTRO")
		sons.play("error", -6.0)
		return
	var mapa := {"guid": guid, "index": indice, "nome": nome}
	if mapeando == "start":
		botao_start = mapa
		contador_start = 0
	else:
		botao_credito = mapa
		contador_credito = 0
	mapeando = ""
	sons.play("menu", -8.0)
	_show_notice("BOTÃO %d GRAVADO EM %s" % [indice, "START" if mapa == botao_start else "CRÉDITO"])
	_salvar()

## Um aperto combina com um mapeamento quando o índice bate e o controle
## também — ou quando ainda não há controle gravado, caso em que o índice
## sozinho decide. É esse "ou" que faz os padrões de fábrica servirem de
## rede antes de alguém mapear qualquer coisa.
func _combina(mapa: Dictionary, indice: int, guid: String) -> bool:
	if int(mapa.get("index", -1)) != indice:
		return false
	var esperado := str(mapa.get("guid", ""))
	return esperado.is_empty() or esperado == guid

func _mapa_de_botao(bruto: Variant, indice_padrao: int) -> Dictionary:
	var d: Dictionary = bruto if bruto is Dictionary else {}
	return {
		"guid": str(d.get("guid", "")),
		"index": int(d.get("index", indice_padrao)),
		"nome": str(d.get("nome", "")),
	}

func _pressionou_start() -> void:
	## START faz uma coisa só em cada tela, e é sempre "seguir em frente".
	match state:
		GameDef.State.IDLE:
			_iniciar_rodada()
		GameDef.State.RESULT:
			# Só depois do veredito: apertar no meio da contagem cortaria
			# justamente o momento pelo qual o cliente pagou.
			if verdict_time >= 0.0:
				_iniciar_rodada()

## A CÂMERA TEM UMA JANELA DE PREPARO, MAS NUNCA TRAVA A MÁQUINA.
##
## Esta é a regra nova, e ela substitui a espera com hora marcada. Antes
## a máquina esperava seis segundos pela webcam e, passados eles, jogava
## assim mesmo: a pessoa fazia a pose, a contagem zerava e o ranking
## registrava o nome sem cara nenhuma. Num jogo cuja graça é aparecer com
## a própria foto no quadro de recordes, uma partida sem foto é uma
## partida entregue pela metade -- e a ficha já tinha sido cobrada.
##
## Agora a ordem se inverte: enquanto não há imagem AO VIVO, a rodada não
## começa, a ficha não é consumida e a tela diz o que está faltando. Quem
## precisa mexer na máquina sem webcam nenhuma (bancada, manutenção,
## feira sem o cabo) desliga a exigência na Central, e aí volta o
## comportamento antigo -- inclusive a espera com teto.
##
## A pergunta é `pronta()`, e ela é sobre a IMAGEM ESTAR MUDANDO, não
## sobre o processo estar de pé: era essa confusão que deixava a contagem
## correr em cima de um quadro congelado. Ver `CameraService.ao_vivo()`.
func camera_liberou_a_rodada() -> bool:
	# A UVC continua tentando em segundo plano. Após a tolerância inicial o jogo
	# funciona mesmo num firmware que ainda não publicou pixels, em vez de ficar
	# preso para sempre na tela de busca.
	if not camera_enabled:
		return true
	if camera_service != null and camera_service.pronta():
		return true
	return Time.get_ticks_msec() >= int(ESPERA_MAXIMA_DA_CAMERA * 1000.0)

## A placa, e não o estado de descoberta/calibração do sensor, libera START.
## Uma linha válida do protocolo identifica que a porta aberta é realmente o
## Arduino do gabinete. O sensor continua sendo procurado e armado em segundo
## plano para medir o golpe, mas sua preparação nunca mais prende o jogador na
## abertura.
func _arduino_conectado() -> bool:
	return link != null and link.is_open() and placa_respondeu

## EM QUE PÉ ESTÁ A LIGAÇÃO COM A PLACA — lido do ESTADO, não do texto.
##
## A Central escolhia a cor e a animação do seletor procurando pedaços
## de palavra dentro de `serial_status`: `"PROCURANDO" in serial_status
## or "CONECTANDO" in ... or "AGUARDANDO" in ...`. É a mesma fragilidade
## que já custou caro neste arquivo, quando `"CONECTADO" in
## serial_status` respondia SIM para "DESCONECTADO". E ela tem um
## sintoma feio: qualquer frase nova em qualquer ponto do encanamento —
## e há vinte e cinco delas — deixa o indicador apagado, parado, dizendo
## a cor errada enquanto a máquina trabalha.
##
## Estas cinco fases saem das variáveis que mandam de verdade. Texto é
## para a pessoa ler; a luz do painel vem do estado.
enum FaseSerial { SEM_CAMINHO, PROCURANDO, OUVINDO, CALIBRANDO, LIGADA }

func fase_serial() -> FaseSerial:
	if link == null or not link.available():
		return FaseSerial.SEM_CAMINHO
	if not link.is_open():
		return FaseSerial.PROCURANDO
	# Porta aberta e placa calada: é o estado que mais dura e o que menos
	# se explicava. Não é "desconectado" — é o jogo com o ouvido na porta.
	if not placa_respondeu:
		return FaseSerial.OUVINDO
	return FaseSerial.CALIBRANDO if placa_calibrando else FaseSerial.LIGADA

func rodada_liberada() -> bool:
	return _arduino_conectado() and camera_liberou_a_rodada()

## O que dizer a quem apertou START e a máquina não começou.
func motivo_da_recusa() -> String:
	if not _arduino_conectado():
		return "AGUARDE — CONECTANDO O ARDUINO"
	if not camera_enabled:
		return "CÂMERA DESLIGADA"
	if camera_service == null:
		return "CÂMERA INDISPONÍVEL"
	return camera_service.estado_curto()

func _iniciar_rodada() -> void:
	# ARDUINO E CÂMERA VÊM ANTES DA FICHA. O sensor não bloqueia mais o
	# início: a busca e a calibração continuam paralelamente durante a rodada.
	if not rodada_liberada():
		_show_notice(motivo_da_recusa())
		sons.play("start_negado", -3.0)
		return
	if game_mode == "credit":
		if credits <= 0:
			# NEGADO TEM SOM PRÓPRIO, e não o de erro genérico: faltar
			# ficha não é defeito, e quem ouve tem de entender a
			# diferença sem ler a tela.
			_show_notice("INSIRA 1 CRÉDITO")
			sons.play("start_negado", -3.0)
			aviso_de_credito = 0.0
			return
		credits -= 1
		credito_gasto = true
	rodada_encerrada_antecipadamente = false
	# O SACO DESCE AGORA, no 3-2-1, e não no primeiro soco: o curso leva
	# três segundos e meio, que é exatamente o tempo da contagem. Quem
	# está na frente da máquina vê o saco baixando enquanto conta, e o
	# movimento vira parte da abertura em vez de uma espera.
	saco.quero(SacoMotor.Onde.EM_BAIXO)
	_discard_round_photo()
	intro_active = false
	sons.stop("score_loop")
	state = GameDef.State.COUNTDOWN
	_iniciar_transicao()
	posicao_no_ranking = 0
	state_time = 0.0
	countdown_left = 3.0
	last_count = 3
	result_score = 0
	result_photo_path = ""
	pose_finished = false
	# A CONTAGEM ESPERA A CÂMERA (mas o OBTURADOR NÃO ABRE AQUI MAIS —
	# ver o comentário grande em `_processar_contagem`, logo abaixo de
	# onde a contagem entra na reta final).
	#
	# Contar 3-2-1 enquanto a webcam ainda está subindo é gastar a pose
	# inteira esperando: quando a contagem zera, a ponte às vezes acabou
	# de entregar o primeiro quadro, e a foto sai do nada ou não sai. A
	# espera é o conserto óbvio, e é o que o operador pediu.
	espera_da_camera = 0.0
	pose_sem_camera = false
	aguardando_camera = camera_enabled and camera_service != null and not camera_service.pronta()
	_obturador_tardio_aberto = false
	photo_retained = false
	ranking_announced = false
	ranking_started_at = -1.0
	_ato_assentou = false
	_ato_festejou = false
	_festa_ranking_decorrido = 0.0
	_festa_ranking_proximo = 0.0
	_festa_ranking_canhao = 0
	displayed_score = 0.0
	fx.limpar()
	clarao = 1.0
	tremor = 14.0
	sons.play("start")
	sons.music(-24.0)
	moldura.set_estado(LedFrame.CONTAGEM)
	fundo.matiz = Color(0, 0, 0, 0)
	# CADA RODADA COMEÇA COM O ADVERSÁRIO INTEIRO. Herdar o dano da
	# rodada anterior faria a segunda pessoa da fila derrubar alguém que
	# já estava caindo — e as barras laterais mentiriam sobre o que ELA
	# fez.
	arena_frase = ""
	arena_nocaute = false
	arena_semente = 0
	if arena != null:
		arena.preparar()
		arena.guardar(true)
	_salvar()

## DEVOLVE A FICHA DA RODADA QUE NÃO ACONTECEU.
##
## Só em modo ficha, e só uma vez: quem jogou de graça não tem o que
## receber de volta, e devolver duas vezes seria fabricar crédito.
func _devolver_credito() -> void:
	if not credito_gasto:
		return
	credito_gasto = false
	if game_mode != "credit":
		return
	credits = mini(credits + 1, GameDef.CREDITOS_MAX)
	_salvar()
	_show_notice("TEMPO ESGOTADO — CRÉDITO DEVOLVIDO  •  SALDO %02d" % credits)

func _entrar_em_abertura() -> void:
	# A volta para a abertura também é uma troca de tela, e sem cortina
	# ela era a mais seca de todas: o Top 20 sumia e a marca aparecia.
	if not intro_active:
		_iniciar_transicao()
	_discard_round_photo()
	abertura_chegada = 1.0
	# Corta os efeitos da rodada e deixa a música da abertura no ar. Antes
	# aqui era `silence()`, que também matava a música: a tela que fica
	# ligada o dia inteiro chamando gente era a única muda do jogo.
	sons.attract(-16.0)
	state = GameDef.State.IDLE
	state_time = 0.0
	verdict_time = -1.0
	result_time = 0.0
	posicao_no_ranking = 0
	result_photo_path = ""
	# NÃO SE APAGA MAIS O CACHE INTEIRO AQUI.
	#
	# Isto rodava a cada volta para a abertura -- ou seja, depois de
	# CADA rodada jogada -- e jogava fora as fotos de TODO o Top 20,
	# não só a da rodada que terminou. O resultado: a tabela travava ao
	# aparecer não uma vez por dia, mas uma vez por partida, porque
	# tinha de decodificar de novo do zero as vinte fotos toda vez.
	# `_discard_round_photo()`, chamada uma linha acima, já cuida da
	# única foto que de fato precisa sumir -- a da própria rodada, e só
	# quando ela não entrou no ranking.
	fx.limpar()
	moldura.set_estado(LedFrame.PARADA)
	fundo.matiz = Color(0, 0, 0, 0)

func _discard_round_photo() -> void:
	if not photo_retained and not result_photo_path.is_empty():
		RankingStore.delete_photo(result_photo_path)
		# O ARQUIVO SOME DO DISCO: a textura em cache para ele vira lixo
		# que nunca mais vai ser pedido de novo (o caminho tem o
		# microssegundo da captura, nunca se repete). Tirando-a do
		# cache aqui, e só ela -- não a tabela inteira -- a memória não
		# cresce sem limite e o resto do Top 20 continua pronto na
		# tela seguinte.
		_photo_cache.erase(result_photo_path)
	result_photo_path = ""
	photo_retained = false

func _add_credit() -> void:
	credits = mini(credits + 1, GameDef.CREDITOS_MAX)
	sons.play("credit")
	fx.faiscas(Vector2(540, 1300), 22, Paleta.VERDE, 420.0)
	_show_notice("CRÉDITO ADICIONADO  •  SALDO %02d" % credits)
	_salvar()

# ======================================================================
# IMPACTO E VEREDITO
# ======================================================================
func _registrar_impacto(
	pontos: int, velocidade: float, simulado: bool,
	pico_g := 0.0, duracao_ms := 0.0
) -> void:
	## O soco aterrissou: meio segundo de impacto puro, e só então o
	## placar começa a subir. Sem esse intervalo o golpe e o número
	## chegam juntos e nenhum dos dois brilha.
	# A ficha foi usada de verdade: daqui em diante não há o que devolver.
	credito_gasto = false
	# O SOCO ENTRA NA RODADA. A nota da rodada sai em `_fechar_rodada`;
	# aqui o que importa é ESTE golpe, porque é ele que manda no
	# espetáculo do impacto — nível, tremor, clarão e som.
	socos.append({
		"pontos": clampi(pontos, 0, GameDef.SCORE_MAX),
		"velocidade": maxf(velocidade, 0.0),
		"pico_g": maxf(float(pico_g), 0.0),
		"duracao_ms": maxf(float(duracao_ms), 0.0),
		"simulado": simulado,
	})
	ultimo_soco_em = animation_time
	result_score = clampi(pontos, 0, GameDef.SCORE_MAX)
	result_speed = maxf(velocidade, 0.0)
	result_simulado = simulado
	state = GameDef.State.MEASURING
	state_time = 0.0
	var forca := float(result_score) / float(GameDef.SCORE_MAX)
	# A nota permanece exatamente na curva competitiva calibrada. A reação
	# física usa a posição REAL do golpe dentro da faixa do sensor; usar a
	# nota elevada ao expoente aqui comprimía quase todo soco em "fraco".
	var forca_visual := ScoreCurve.normalized(
		result_speed, hit_min_speed, hit_max_speed, score_dead_zone
	)
	var alvo := _alvo()
	moldura.impacto(0.4 + forca * 0.6)
	sons.play("hit", 1.5)
	sons.play("subgrave", -4.0)
	sons.stop("charge")
	# A TRILHA SAI DA FRENTE DO GOLPE. Não para — abaixa e volta sozinha,
	# porque parar e recomeçar a música a cada soco é o que faz uma
	# máquina parecer travada entre uma rodada e outra.
	sons.duck(14.0, 2.2)
	# O NÍVEL MANDA NO ESPETÁCULO. Um impacto leve e um soco perfeito não
	# podem sacudir a máquina do mesmo jeito, e é a receita do nível que
	# diz quanto de cada coisa entra.
	pancada_nivel = ScoreTier.de(result_score)
	var receita := ImpactDirector.golpe(fx, alvo, pancada_nivel, CORES_FESTA)
	tremor = float(receita["tremor"])
	clarao = float(receita["clarao"])
	hitstop_left = float(receita["hitstop"])
	zoom_alvo = float(receita["zoom"])
	zoom_impacto = float(receita["zoom"])
	pancada_tempo = 0.0
	pancada_forca = forca
	# O SOCO ATRAVESSA A TELA E ACERTA ALGUÉM.
	#
	# Esta é a linha que separa esta versão da original: antes o golpe
	# virava tremor, clarão e número; agora ele também é um corpo indo
	# para trás. A ordem importa — o nível já foi decidido acima, então a
	# arena recebe a MESMA força que o resto do espetáculo, e não uma
	# conta própria que poderia discordar da cor e do som.
	arena_semente = socos.size()
	arena_frase = ArenaFrases.de_golpe(str(pancada_nivel["id"]), arena_semente)
	arena_nocaute = false
	if arena != null:
		arena.guardar(false)
		# Os níveis que derrubam por si são os que já tinham hit-stop na
		# tabela: é a mesma linha que decide o soluço da imagem, e não um
		# segundo critério para a mesma ideia de "golpe que para tudo".
		var derruba := float(pancada_nivel["hitstop"]) > 0.0
		var reacao := arena.golpe(forca_visual, derruba, result_score)
		arena_nocaute = bool(reacao["nocaute"])
		if bool(reacao.get("desdenhou", false)):
			arena_frase = "ELE NEM SENTIU • TENTE MAIS FORTE"
			sons.play("torcida_desdenho", -1.0)
	# O BAQUE TEM DUAS CAMADAS AGORA: o couro do impacto e o corpo que
	# leva. Sem a segunda, o soco continuava soando como saco de areia
	# mesmo com um lutador na tela levando o golpe.
	sons.play("arena_corpo", -1.0 + forca_visual * 4.0)
	if result_score >= 6000 and forca_visual >= 0.36 and not arena_nocaute:
		sons.play("arena_publico", -11.0 + forca_visual * 8.0)
	if arena_nocaute:
		arena_frase = ArenaFrases.de_nocaute(arena_semente)
		sons.play("arena_queda", 0.0)
		sons.play("arena_publico", -2.0)
	# RANKING, ESTATÍSTICA E DISCO SAÍRAM DAQUI, e isso é a correção que
	# os dois socos exigem: enquanto estavam neste ponto, cada soco entrava
	# no Top 20 sozinho — dois socos da mesma pessoa disputando duas linhas
	# da tabela, e a estatística contando duas partidas onde houve uma.
	# Agora é `_fechar_rodada`, uma vez por rodada, com a nota final.

func _disparar_veredito() -> void:
	sons.stop("score_loop")
	sons.music(-28.0)
	## O momento em que a máquina diz quanto valeu o soco. Um por golpe.
	verdict_time = 0.0
	proximo_fogo = 0.0
	var classe := GameDef.classificar(result_score)
	var cor: Color = classe["cor_faixa"]
	moldura.set_estado(LedFrame.RESULTADO, cor)
	# A tela inteira toma a cor da faixa, de leve: o veredito chega ao
	# canto do olho antes de a pessoa terminar de ler a palavra.
	fundo.matiz = Color(cor, 0.10)
	var alvo := _alvo()

	# O SOM E A COMEMORAÇÃO SÃO DO NÍVEL, não da faixa grossa.
	#
	# Antes três faixas decidiam por oito níveis, e NOCAUTE, PESO-PESADO,
	# LENDÁRIO e SOCO PERFEITO caíam todos no mesmo bloco: mesma
	# explosão, mesmo som, só a palavra mudando. Era exatamente o que a
	# pessoa que joga duas vezes seguidas percebe.
	var nivel: Dictionary = classe["nivel"]
	var id_nivel := str(nivel["id"])
	if id_nivel == "LEVE":
		# Golpe fraco recebe a reação curta enviada pelo operador.
		sons.play("not_supress", -2.0)
	elif _dois_socos_bons():
		# A fala longa é reservada à conquista completa: dois bons golpes.
		sons.play("good_player", -2.0)
	else:
		sons.play(str(nivel["som"]), 0.5)
		# O primeiro bom golpe merece resposta, mas não a mesma festa
		# reservada a quem confirmou o desempenho no segundo.
		if socos.size() == 1:
			sons.play("win", -9.0)
	# O veredito é a fala da máquina: a trilha desce por todo o tempo em
	# que o nome do nível está sendo anunciado.
	sons.duck(16.0, 3.0)
	var receita := ImpactDirector.golpe(fx, alvo, nivel, CORES_FESTA)
	tremor = maxf(tremor, float(receita["tremor"]) * 0.8)
	clarao = maxf(clarao, float(receita["clarao"]) * 0.7)

	if posicao_no_ranking == 1:
		for sound in ["win", "medium", "lose", "legendary"]:
			sons.stop(sound)
		sons.play("record", -2.0)

# ======================================================================
# ASSISTENTE DE CALIBRAÇÃO
# ======================================================================
## CALIBRAR É MEDIR A MÁQUINA, NÃO ADIVINHAR NÚMEROS.
##
## Cada gabinete responde diferente: o saco, a mola, onde o sensor foi
## parafusado, o quanto o pé da máquina cede. Regular isso por tentativa
## e erro nos passos de − e + significa descobrir que errou depois de a
## fila reclamar. O assistente mede: quatro passos, cinco golpes fracos,
## cinco fortes, e a conta sai por percentis em `Calibracao`.
const CALIB_PASSOS := ["REPOUSO", "GOLPES FRACOS", "GOLPES FORTES", "SUGESTÃO"]
const CALIB_REPOUSO_S := 4.0
const CALIB_BOTOES := {
	"calib_avancar": Rect2(560, 1600, 400, 72),
	"calib_repetir": Rect2(120, 1600, 400, 72),
	"calib_salvar": Rect2(560, 1690, 400, 72),
	"calib_cancelar": Rect2(120, 1690, 400, 72),
}

var calib_ativo := false
var calib_passo := 0
var calib_repouso_left := 0.0
var calib_ruido := 0.0
var calib_fracos: Array[float] = []
var calib_fortes: Array[float] = []
## O NÍVEL DE SINAL VISTO EM CADA GOLPE — só para a tela mostrar.
##
## No firmware óptico este campo é a leitura de A0, de 0 a 1: um nível de
## luz, NÃO uma aceleração. Ele já entrou em conta como se fosse g, e foi
## assim que um "ruído" virou gatilho e a máquina se estrangulou. Agora
## ele é o que sempre foi — um número para conferir a olho se o sensor
## está enxergando — e `Calibracao.sugerir` não o recebe mais.
var calib_sinais: Array[float] = []
var calib_sugestao: Dictionary = {}

func _abrir_calibracao() -> void:
	calib_ativo = true
	calib_passo = 0
	calib_repouso_left = CALIB_REPOUSO_S
	calib_ruido = 0.0
	calib_fracos.clear()
	calib_fortes.clear()
	calib_sinais.clear()
	calib_sugestao = {}
	_show_notice("CALIBRAÇÃO: DEIXE O SACO PARADO")

func _fechar_calibracao() -> void:
	calib_ativo = false
	calib_sugestao = {}

## O relógio do passo de repouso. Só ele corre sozinho; os outros esperam
## golpe, e golpe não tem hora.
func _processar_calibracao(delta: float) -> void:
	if not calib_ativo or calib_passo != 0:
		return
	calib_repouso_left = maxf(0.0, calib_repouso_left - delta)
	if calib_repouso_left <= 0.0:
		calib_passo = 1
		sons.play("menu", -8.0)

## Um golpe chegou durante a calibração.
##
## Ele NÃO vira pontuação, não conta partida e não entra no ranking: a
## Central está aberta e a máquina está sendo medida, não jogada.
func _calibracao_recebeu(velocidade: float, pico: float) -> void:
	match calib_passo:
		0:
			# Em repouso, qualquer coisa que chegue é ruído — e o ruído é
			# justamente o que se quer medir.
			calib_ruido = maxf(calib_ruido, pico)
		1:
			calib_fracos.append(velocidade)
			calib_sinais.append(pico)
			sons.play("tick", -6.0)
			if calib_fracos.size() >= Calibracao.AMOSTRAS:
				calib_passo = 2
				sons.play("menu", -8.0)
		2:
			calib_fortes.append(velocidade)
			calib_sinais.append(pico)
			sons.play("tick", -3.0)
			if calib_fortes.size() >= Calibracao.AMOSTRAS:
				calib_passo = 3
				calib_sugestao = Calibracao.sugerir(calib_fracos, calib_fortes, calib_ruido, sensor_raio)
				sons.play("record", -6.0)

func _click_calibracao(p: Vector2) -> void:
	if CALIB_BOTOES["calib_cancelar"].has_point(p):
		_fechar_calibracao()
		_show_notice("CALIBRAÇÃO CANCELADA — NADA FOI MUDADO")
	elif CALIB_BOTOES["calib_repetir"].has_point(p):
		_abrir_calibracao()
	elif CALIB_BOTOES["calib_avancar"].has_point(p):
		# Pular à mão serve para quem já tem o número na cabeça e só quer
		# a parte seguinte. Nunca inventa amostra: pular deixa o passo com
		# o que colheu, e a sugestão sai do que existe.
		if calib_passo == 0:
			calib_repouso_left = 0.0
		elif calib_passo < 3:
			calib_passo += 1
			if calib_passo == 3:
				calib_sugestao = Calibracao.sugerir(calib_fracos, calib_fortes, calib_ruido, sensor_raio)
	elif CALIB_BOTOES["calib_salvar"].has_point(p):
		if calib_sugestao.is_empty():
			return
		hit_min_speed = float(calib_sugestao["vmin"])
		hit_max_speed = float(calib_sugestao["vmax"])
		# O SOCO DE REFERÊNCIA VEM DA MEDIÇÃO, e não de uma fração fixa
		# da faixa. É ele que decide quanto vale um soco comum NESTA
		# montagem, então é a parte da calibração que mais se sente na
		# fila — e a que mais depende de como este saco responde.
		score_ref_speed = float(calib_sugestao["vref"])
		sensor_vmin = hit_min_speed
		# O pulso não é escolhido: `_aplicar_faixas`, logo abaixo, o
		# recalcula com a mesma função que a sugestão usou. Copiar aqui
		# só mantém tela e disco em dia caso a ordem das chamadas mude.
		sensor_pulso_ms = float(calib_sugestao["pulso_ms"])
		_aplicar_faixas()
		_salvar()
		# O firmware precisa saber também: é ele que decide o que virar
		# HIT antes de qualquer coisa chegar ao jogo.
		_enviar_config()
		_fechar_calibracao()
		_show_notice("CALIBRAÇÃO SALVA E ENVIADA AO SENSOR")

func _draw_calibracao() -> void:
	var caixa := Rect2(60, 300, 960, 1500)
	_placa(caixa, 22.0, Paleta.CARTAO_BORDA)
	_placa(caixa.grow(-5.0), 19.0, Color("240810"))
	_texto_arcade("CALIBRAÇÃO", 396.0, 62, Paleta.AMBAR, LARGURA_UTIL)

	# A trilha dos quatro passos, com o atual aceso.
	for i in range(CALIB_PASSOS.size()):
		var r := Rect2(110.0 + float(i) * 220.0, 440.0, 200.0, 54.0)
		var feito := i < calib_passo
		var atual := i == calib_passo
		var cor: Color = Paleta.VERDE if feito else (Paleta.AMBAR if atual else Color("4a1420"))
		_cartao(r, cor if (feito or atual) else Color("1c060c"), Paleta.CARTAO_BORDA, 1.0, 2.0)
		_texto(
			str(CALIB_PASSOS[i]), r.position.y + 34.0, 15,
			Color("2b0a13") if (feito or atual) else Paleta.TINTA_LEVE,
			HORIZONTAL_ALIGNMENT_CENTER, r.position.x, r.size.x
		)

	match calib_passo:
		0:
			_texto_arcade("NÃO ENCOSTE NO SACO", 620.0, 56, Color.WHITE, LARGURA_UTIL)
			_rotulo("medindo o ruído de repouso do sensor", 690.0, Paleta.TINTA_FRACA)
			_texto_arcade("%.1f s" % calib_repouso_left, 820.0, 96, Paleta.AMBAR, LARGURA_UTIL)
			# O NÚMERO TEM DE DIZER A UNIDADE CERTA. Aqui ele vinha
			# escrito em "g", e no sensor óptico não é aceleração
			# nenhuma: é o nível de luz em A0, de 0 a 1. Rotular errado
			# é o começo de usar errado — foi assim que este valor foi
			# parar num campo de milissegundos.
			_rotulo("maior nível visto: %.3f (sinal de A0)" % calib_ruido, 900.0, Paleta.CIANO)
		1:
			_passo_de_golpes("CINCO GOLPES FRACOS", "bata de leve, como quem testa", calib_fracos)
		2:
			_passo_de_golpes("CINCO GOLPES FORTES", "bata com tudo, como o melhor cliente", calib_fortes)
		_:
			_resultado_da_calibracao()

	var pode_avancar := calib_passo < 3
	_botao(CALIB_BOTOES["calib_avancar"], "PULAR ESTE PASSO" if pode_avancar else "—", false, Paleta.CIANO, 19)
	_botao(CALIB_BOTOES["calib_repetir"], "COMEÇAR DE NOVO", false, Paleta.ROXO, 19)
	_botao(
		CALIB_BOTOES["calib_salvar"], "SALVAR E ENVIAR AO SENSOR",
		not calib_sugestao.is_empty(), Paleta.VERDE, 18
	)
	_botao(CALIB_BOTOES["calib_cancelar"], "CANCELAR", false, Paleta.VERMELHO, 19)

func _passo_de_golpes(titulo: String, dica: String, amostras: Array) -> void:
	_texto_arcade(titulo, 600.0, 52, Color.WHITE, LARGURA_UTIL)
	_rotulo(dica, 664.0, Paleta.TINTA_FRACA)
	# Uma casa por golpe: a pessoa que está batendo vê quantos faltam sem
	# precisar contar de cabeça enquanto bate.
	for i in range(Calibracao.AMOSTRAS):
		var r := Rect2(180.0 + float(i) * 148.0, 730.0, 128.0, 128.0)
		var tem := i < amostras.size()
		_cartao(r, Paleta.AMBAR if tem else Color("1c060c"), Paleta.CARTAO_BORDA, 1.0, 2.0)
		_texto(
			"%.1f" % float(amostras[i]) if tem else "—", r.position.y + 76.0, 26,
			Color("2b0a13") if tem else Paleta.TINTA_LEVE,
			HORIZONTAL_ALIGNMENT_CENTER, r.position.x, r.size.x
		)
	_rotulo("m/s medidos pelo sensor", 900.0, Paleta.CIANO)

func _resultado_da_calibracao() -> void:
	if calib_sugestao.is_empty():
		_texto_arcade("SEM AMOSTRAS SUFICIENTES", 620.0, 44, Paleta.VERMELHO, LARGURA_UTIL)
		_rotulo("volte e registre os golpes", 690.0, Paleta.TINTA_FRACA)
		return
	_texto_arcade("SUGESTÃO", 580.0, 52, Paleta.VERDE, LARGURA_UTIL)
	# AS QUATRO LINHAS, NA ORDEM EM QUE SE LÊ A MÁQUINA: onde começa a
	# pontuar, quanto vale um soco comum, onde está o topo — e só então o
	# número que é consequência dos outros três.
	var linhas := [
		["VELOCIDADE MÍNIMA", "%.1f m/s" % float(calib_sugestao["vmin"]), str(calib_sugestao["porque_vmin"])],
		[
			"SOCO DE REFERÊNCIA (%d)" % ScoreCurve.PONTOS_DE_REFERENCIA,
			"%.1f m/s" % float(calib_sugestao["vref"]), str(calib_sugestao["porque_vref"]),
		],
		["VELOCIDADE MÁXIMA", "%.1f m/s" % float(calib_sugestao["vmax"]), str(calib_sugestao["porque_vmax"])],
		# ESTA LINHA DIZIA "SENSIBILIDADE, %.1f g" — e o número ia para
		# um campo que o firmware lê em MILISSEGUNDOS. Ver `Calibracao`.
		["PULSO MÍNIMO", "%.2f ms" % float(calib_sugestao["pulso_ms"]), str(calib_sugestao["porque_pulso"])],
	]
	for i in range(linhas.size()):
		var y := 640.0 + float(i) * 104.0
		_cartao(Rect2(120, y - 38.0, 840, 92), Color("1c060c"), Paleta.CARTAO_BORDA, 1.0, 1.5)
		_texto(str(linhas[i][0]), y, 20, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_LEFT, 150.0, 430.0)
		_texto(str(linhas[i][1]), y, 30, Paleta.AMBAR, HORIZONTAL_ALIGNMENT_RIGHT, 150.0, 780.0)
		_texto(str(linhas[i][2]), y + 28.0, 14, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, 150.0, 780.0)

	# A CURVA QUE VAI VALER, desenhada antes de salvar. É o único jeito de
	# alguém discordar da sugestão com fundamento.
	_rotulo("A CURVA COM ESTES NÚMEROS", 1080.0, Paleta.CREME)
	var antes_min := hit_min_speed
	var antes_max := hit_max_speed
	var antes_ref := score_ref_speed
	hit_min_speed = float(calib_sugestao["vmin"])
	hit_max_speed = float(calib_sugestao["vmax"])
	score_ref_speed = float(calib_sugestao["vref"])
	_curva_desenhada(Rect2(120, 1110, 840, 170))
	hit_min_speed = antes_min
	hit_max_speed = antes_max
	score_ref_speed = antes_ref
	_apoio(
		"salvando, os valores vão para a máquina E para o firmware do sensor",
		1352.0, Paleta.TINTA_FRACA
	)

# ======================================================================
# SERIAL (MPU-6050 via GdSerial — protocolo V2)
# ======================================================================
func _iniciar_serial() -> void:
	_soltar_link()
	link = SerialLink.create_best()
	link.line_received.connect(_on_serial_line)
	link.opened.connect(_on_serial_opened)
	link.closed.connect(_on_serial_closed)
	# Cada caminho novo começa com a ficha limpa: fila do zero, porta
	# fixada com crédito de novo, e o relógio da vigilância zerado.
	porta_atual = ""
	ultimo_sinal_ms = -1
	placa_respondeu = false
	sensor_presente = false
	firmware_optico_identificado = false
	placa_calibrando = false
	progresso_calibracao = 0
	_porta_da_vez = 0
	_varreduras = 0
	_falhas_da_porta_fixa = 0
	_porta_confirmada = false
	_caminho_provado = false
	_fila_de_portas = PackedStringArray()
	_caminho_desde = animation_time
	_proxima_escolha_de_caminho = animation_time + SEGUNDOS_ATE_TROCAR_DE_CAMINHO
	if not link.available():
		# NEM A EXTENSÃO NATIVA, NEM A PONTE POR PROCESSO.
		#
		# Antes desta mensagem o jogo dizia apenas "SEM EXTENSÃO SERIAL" e
		# calava — e quem estava na frente da máquina não tinha como saber
		# se faltava um arquivo, se o Windows recusou o PowerShell ou se o
		# cabo estava solto. Agora a frase diz o que a tentativa devolveu.
		#
		# E não é mais o fim da linha: `_poll_serial` continua batendo, e
		# passado o prazo o jogo REFAZ a escolha do caminho. Uma máquina
		# em que o PowerShell demorou a subir, ou em que o cabo USB chegou
		# depois, se conserta sozinha em vez de esperar por alguém.
		var motivo := link.motivo_da_falta()
		serial_status = "SEM CAMINHO ATÉ O ARDUINO — PROCURANDO OUTRO…"
		if not motivo.is_empty():
			serial_status += " (%s)" % motivo
		proxima_tentativa = animation_time + 1.0
		return
	_tentar_conectar()

## Desliga o backend anterior antes de escolher outro. Sem isto os sinais
## do backend velho continuariam chegando no jogo depois da troca, e duas
## camadas seriais falariam ao mesmo tempo sobre portas diferentes.
func _soltar_link() -> void:
	if link == null:
		return
	if link.line_received.is_connected(_on_serial_line):
		link.line_received.disconnect(_on_serial_line)
	if link.opened.is_connected(_on_serial_opened):
		link.opened.disconnect(_on_serial_opened)
	if link.closed.is_connected(_on_serial_closed):
		link.closed.disconnect(_on_serial_closed)
	link.close_port()
	link.encerrar()
	link = null

## O sensor está falando com a máquina? Decide o que o cliente vê: com o
## Arduino ligado, a tela não mostra tecla nenhuma; na bancada, mostra.
func _sensor_ligado() -> bool:
	if link == null or not link.is_open() or not placa_respondeu or not sensor_presente:
		return false
	# STATUS/TELEMETRY chegam quatro vezes por segundo. Dois segundos sem
	# uma linha já não são conexão pronta para vender uma partida.
	return ultimo_sinal_ms >= 0 and Time.get_ticks_msec() - ultimo_sinal_ms <= 2000

## A PORTA CERTA SE DESCOBRE TENTANDO — não abrindo a primeira da lista.
##
## AQUI ESTAVA O "O ARDUINO NÃO FAZ NADA". O jogo pegava
## `portas_visiveis[0]`, abria, e ficava esperando. Num PC de gabinete
## quase nunca há uma porta só: o Windows inventa COM3 e COM4 para o
## Bluetooth, o leitor de cartão traz a dele. Abrindo a errada, o READY
## nunca chega — e o jogo NUNCA TENTAVA OUTRA. Ficava a noite inteira em
## "AGUARDANDO READY" numa porta que não tem placa nenhuma, com START e
## CRÉDITO mortos.
##
## Agora a lista é uma fila: abre, espera o tempo de a placa se
## apresentar, e se ela não se apresentar, passa para a próxima. A porta
## que responder fica.
##
## TRÊS SEGUNDOS VIROU CINCO, E CINCO VIROU OITO — E O RELÓGIO MUDOU DE
## LUGAR, que é a parte que importa.
##
## Abrir a porta RESETA o Arduino (é o DTR fazendo isso, não o jogo), e
## nem todo par placa/driver reseta e reinicia depressa: um bootloader
## clássico soma até dois segundos de espera própria antes de sequer
## começar o `setup()`, e um driver CH340 genérico pode demorar mais para
## o Windows terminar de enumerar a porta. Uma paciência curta cria um
## LAÇO: a porta reseta, o Arduino ainda está de pé quando o jogo desiste
## e fecha, o fechar-reabrir reseta de novo, e a placa NUNCA tem os dois
## segundos inteiros para chegar ao `Serial.println(F("READY..."))`.
##
## Mas o relógio estava contando a coisa errada. Ele começava quando o
## jogo PEDIA a abertura — e pela ponte por processo, entre o pedido e a
## porta aberta há um cano, um PowerShell e um driver. Num PC lento, ou
## com antivírus no meio, isso sozinho passa de cinco segundos: a
## paciência acabava ANTES de a porta existir, e a máquina varria a lista
## inteira sem nunca dar a nenhuma placa a chance de responder. É o
## retrato exato de "funciona no meu PC, não funciona no outro, com a
## mesma porta": a diferença não está na porta, está em quanto tempo
## aquela máquina leva para abrir uma.
##
## Agora são dois relógios. `ESPERA_DA_CONFIRMACAO` cobra o ENCANAMENTO:
## do pedido até a porta confirmar que abriu. `PORTA_PACIENCIA` cobra a
## PLACA: da porta aberta até a primeira linha válida. Nenhum dos dois
## desconta do outro.
## QUANTO SE ESPERA UMA PORTA FALAR, e por que o numero caiu.
##
## Oito segundos foram escolhidos quando o firmware so se apresentava
## DEPOIS de achar e calibrar o sensor -- dois segundos de bootloader mais
## dois de calibracao, e margem para um PC lento. Desde a V9 o `READY` sai
## como PRIMEIRA linha do `setup()`, antes do I2C e antes da calibracao:
## a placa se anuncia em pouco mais de dois segundos depois do reset do
## DTR, e a partir dai manda PINS quatro vezes por segundo.
##
## Quatro segundos e meio cobrem isso com o dobro de margem. E a conta que
## importa e a da FILA: com quatro portas antes da certa, oito segundos
## cada davam mais de meio minuto de "PROCURANDO ARDUINO..." com a placa
## espetada e falando. Era essa a demora.
const PORTA_PACIENCIA := 4.5
const ESPERA_DA_CONFIRMACAO := 15.0
## Uma ausência curta pode ser o Windows atendendo câmera e vídeo no mesmo
## controlador USB. Só reiniciamos a COM depois de silêncio realmente
## prolongado; durante COUNTDOWN/ARMED damos margem ainda maior para não
## resetar o Arduino exatamente quando o jogador vai socar.
const SERIAL_SILENCIO_NORMAL_MS := 20000
const SERIAL_SILENCIO_EM_JOGO_MS := 30000
## Calibrar e recuperar o barramento nunca deve fazer o jogo abandonar a
## COM que ja se identificou. O prazo grande e apenas uma rede de seguranca;
## o firmware V10 tem prazos internos de milissegundos em cada leitura.
const SERIAL_SILENCIO_CALIBRANDO_MS := 90000
## A PACIENCIA CURTA, para porta que o sistema NAO chama de placa.
##
## Bluetooth, leitor de cartao, porta virtual de impressora: elas ABREM
## normalmente e nunca dizem nada, e e nelas que a espera longa era
## desperdicada. Quando o gerenciador de dispositivos sabe distinguir (ver
## `SerialLink.portas_promissoras`), a porta anonima ganha um segundo e
## meio -- tempo de sobra para uma placa que ja estava ligada responder --
## e a fila anda.
##
## Se o sistema NAO souber distinguir nenhuma, a lista de promissoras vem
## vazia e TODAS ganham a paciencia inteira: "nao sei" nunca vira pressa.
const PORTA_PACIENCIA_ANONIMA := 1.5
## Depois de tantas falhas seguidas, a porta fixada na Central deixa de
## ser exclusiva e a varredura volta a incluir todas. Ver
## `_fila_de_tentativas`.
const FALHAS_ATE_SOLTAR_A_PORTA_FIXA := 2
## Tanto tempo sem uma única linha válida e o jogo TROCA DE CAMINHO até a
## placa. É o que faz a máquina funcionar num PC onde o caminho preferido
## não presta, sem ninguém para mexer em arquivo. Ver
## `SerialLink.create_best`.
const SEGUNDOS_ATE_TROCAR_DE_CAMINHO := 40.0
var _porta_da_vez := 0

## A PORTA FIXADA É PREFERÊNCIA, NÃO CADEADO — e este foi o "gato" que
## deixou a máquina presa numa porta que não existia.
##
## Fixar a porta na Central gravava o nome no disco, e a partir dali o
## jogo tentava SÓ AQUELA PORTA, para sempre, em qualquer máquina. Num PC
## onde o Nano aparece como COM3, um "COM5" gravado noutro dia é uma
## máquina morta com a placa espetada e funcionando do lado: a fila tinha
## um item só, e esse item estava errado. Pior: o arquivo de ajustes
## sobrevive à atualização do jogo, então o defeito atravessava versões.
##
## Agora a porta fixada vai na FRENTE da fila e ganha duas tentativas
## exclusivas — o bastante para ela vencer o sorteio quando está certa. Se
## não responder nessas duas, a varredura volta a incluir todas as portas
## e a máquina acha a placa onde ela estiver. A preferência continua
## valendo (ela é sempre a primeira tentada), mas deixou de ser um
## cadeado.
func _fila_de_tentativas() -> PackedStringArray:
	var fila := PackedStringArray()
	# Identificada nesta sessao vence qualquer preferencia antiga. Depois
	# de READY nao ha mais descoberta: esta e a placa que deve ser reaberta.
	if not porta_arduino_identificada.is_empty():
		fila.append(porta_arduino_identificada)
	# A PORTA QUE ACABOU DE APARECER entra antes da fixada — e por isso
	# sobrevive ao `return` da porta fixa logo abaixo. Um gabinete com a
	# porta travada na Central continua honrando a escolha do operador,
	# mas dá uma chance ao cabo que acabou de ser espetado, que é o gesto
	# que ele está fazendo enquanto olha para a tela.
	#
	# E ela só entra se AINDA estiver à vista: uma porta que apareceu e
	# sumiu no intervalo (o cabo que deu um mau contato) não pode
	# continuar furando a fila de uma busca que já seguiu em frente.
	if (
		not _porta_recem_chegada.is_empty()
		and portas_visiveis.has(_porta_recem_chegada)
		and not fila.has(_porta_recem_chegada)
	):
		fila.append(_porta_recem_chegada)
	if not porta_configurada.is_empty():
		if not fila.has(porta_configurada):
			fila.append(porta_configurada)
		if _falhas_da_porta_fixa < FALHAS_ATE_SOLTAR_A_PORTA_FIXA:
			return fila
	if not porta_serial_conhecida.is_empty() and not fila.has(porta_serial_conhecida):
		fila.append(porta_serial_conhecida)
	for porta in portas_visiveis:
		if not fila.has(porta):
			fila.append(porta)
	# A VARREDURA CEGA, o último recurso — e o que responde de vez a
	# "funcione em qualquer porta, em qualquer PC".
	#
	# Toda a fila acima depende de UMA coisa dar certo: o sistema
	# ENUMERAR as portas. E é exatamente essa a peça que falha de máquina
	# para máquina, sempre de um jeito diferente — que é por que o
	# diagnóstico não bate entre dois PCs com a mesma placa. O
	# `GetPortNames()` do Windows lê o registro e devolve vazio quando o
	# driver CH340 registrou a porta noutro lugar; a extensão nativa
	# devolve o dicionário num formato que a versão dela mudou; o
	# gerenciador de dispositivos está ocupado e a consulta volta seca.
	# Em todos esses casos a porta EXISTE, a placa está falando nela — e o
	# jogo nunca a tenta, porque ninguém lhe contou que ela está ali. Isso
	# é, ao pé da letra, a busca que nunca termina.
	#
	# A saída é não perguntar. Passada a primeira volta sem sucesso, o
	# jogo tenta os nomes de porta que EXISTEM NESTE SISTEMA POR
	# CONVENÇÃO, um por um, enumeração ou não. Porta que não existe recusa
	# na hora e sai da frente em fração de segundo, então a varredura
	# inteira custa poucos segundos — e ao fim dela não sobrou porta
	# nenhuma onde a placa pudesse estar escondida.
	return fila

## DÁ PARA PROCURAR AGORA SEM ATRAPALHAR QUEM ESTÁ JOGANDO?
##
## Só não dá enquanto o golpe está no ar — do 3-2-1 até o veredito sair.
## Ver o comentário de `TETO_DA_ESPERA_DO_SOCO`: a pausa é curta, tem
## teto, e nunca vira desistência.
## Pede a lista de portas. No Android ela vem do cache do plugin (a
## enumeração USB roda numa thread de lá), então não custa nada aqui.
func _pedir_a_lista() -> void:
	if link == null or not link.available():
		return
	if animation_time - _lista_pedida_em >= _espera_da_lista():
		_adotar_lista(link.list_ports())


## DE QUANTO EM QUANTO TEMPO SE OLHA PARA A LISTA DE PORTAS.
func _espera_da_lista() -> float:
	return ESPERA_DA_LISTA_NA_CENTRAL if central_aberta else ESPERA_DA_LISTA

## RECEBE A LISTA NOVA E REPARA NO QUE MUDOU.
##
## Trocar a lista em silêncio era o que fazia a máquina parecer burra: o
## cabo entrava, o sistema anunciava uma porta nova, o jogo guardava a
## porta nova numa variável e continuava a volta de onde estava — podia
## faltar meia fila até chegar nela, e até lá a tela dizia
## "DESCONECTADO". Uma porta que NASCE agora é a melhor pista que esta
## máquina vai ter, e agora ela fura a fila.
func _adotar_lista(novas: PackedStringArray) -> void:
	var antes := portas_visiveis
	portas_visiveis = novas
	_lista_ja_veio = true
	_lista_pedida_em = animation_time
	if not _lista_comparavel:
		# A primeira lista é o retrato de partida, não uma novidade.
		_lista_comparavel = true
		return
	# A porta que sumiu da lista não vai responder: dizer isso é melhor
	# do que continuar esperando por ela até a paciência acabar.
	if not porta_atual.is_empty() and antes.has(porta_atual) and not novas.has(porta_atual):
		serial_status = "%s SUMIU DA LISTA — O CABO SAIU?" % porta_atual
	# A porta que acabou de nascer fura a fila.
	for porta in novas:
		if antes.has(porta):
			continue
		_porta_recem_chegada = porta
		_porta_da_vez = 0
		# Largar a porta muda em que estávamos. Só a muda: se a placa já
		# está falando, uma porta nova é outro aparelho e não interessa.
		if link != null and link.is_open() and not placa_respondeu:
			link.close_port()
		serial_status = "PORTA NOVA: %s — ABRINDO AGORA" % porta
		proxima_tentativa = animation_time
		break

func _hora_de_procurar() -> bool:
	var no_meio_do_golpe := state in [
		GameDef.State.COUNTDOWN, GameDef.State.ARMED,
		GameDef.State.MEASURING, GameDef.State.RESULT,
	]
	if not no_meio_do_golpe:
		_busca_adiada_desde = -1.0
		return true
	if _busca_adiada_desde < 0.0:
		_busca_adiada_desde = animation_time
		return false
	return animation_time - _busca_adiada_desde >= TETO_DA_ESPERA_DO_SOCO

## O PASSO DO MOTOR, UMA VEZ POR QUADRO — e quase sempre sem dizer nada.
##
## `SacoMotor.passo()` devolve uma linha só quando há de fato algo novo a
## pedir: o saco não está onde deveria, o pedido ainda vale e já passou o
## intervalo mínimo desde a última vez. Na esmagadora maioria dos quadros
## ele devolve vazio e isto custa uma comparação.
##
## E ele vem ANTES de tudo o mais no `_poll_serial` de propósito: se a
## porta cair no meio de um curso, a placa desliga o motor sozinha pelo
## tempo, e este lado apenas para de pedir.
func _passo_do_motor() -> void:
	if link == null or not link.is_open():
		return
	var linha := saco.passo()
	if not linha.is_empty():
		link.send_line(linha)

func _tentar_conectar() -> void:
	# FALHA SILENCIOSA ERA O PIOR JEITO DE FALHAR.
	#
	# A conversa com o Arduino depende de uma extensão nativa (a
	# `gdserial`, um .dll ao lado do executável). Se ela não carregar —
	# arquivo faltando na exportação, arquitetura errada, antivírus que
	# apagou o .dll, ou o runtime do Visual C++ que ela precisa e que não
	# vem no Windows limpo —, `available()` volta falso e ESTA FUNÇÃO SAÍA
	# CALADA. O resultado é uma máquina em que START e CRÉDITO simplesmente
	# não existem, sem uma palavra na tela dizendo por quê: quem está do
	# outro lado procura fio solto durante horas por causa de um arquivo.
	#
	# É também o defeito que aparece SÓ NO COMPUTADOR NOVO, porque no PC
	# de quem desenvolve a extensão está sempre lá.
	if link == null or not link.available():
		# A FRASE PRECISA DIZER O QUE FAZER, e não só que deu errado.
		#
		# "SEM CAMINHO ATÉ O ARDUINO" é o estado em que NENHUM dos dois
		# caminhos subiu — nem a extensão nativa, nem a ponte por
		# processo. Num PC de destino a causa quase sempre é uma das duas
		# do arquivo docs/QUANDO_NAO_ACHA_O_ARDUINO.md, e as duas se
		# conferem em um minuto. Mandar a pessoa ler o protocolo serial
		# inteiro era mandá-la para o lugar errado.
		serial_status = "SEM CAMINHO ATÉ O ARDUINO — %s" % (
			link.motivo_da_falta() if link != null and not link.motivo_da_falta().is_empty()
			else "VEJA docs/QUANDO_NAO_ACHA_O_ARDUINO.md"
		)
		proxima_tentativa = animation_time + 1.0
		return
	# A PRIMEIRA LISTA É PEDIDA NA HORA, as seguintes no fundo. Na
	# primeira o jogo ainda está subindo e não há quadro para estragar; e
	# sem ela a fila nasceria vazia, o que ligaria a varredura cega antes
	# de a máquina ter olhado para as portas que o sistema anuncia.
	#
	# E O QUE MARCA "JÁ VEIO" É UMA BANDEIRA, NÃO A LISTA ESTAR VAZIA.
	# Numa máquina sem nenhuma serial ligada — que é o caso mais comum de
	# todos, e justamente aquele em que a busca roda a noite inteira — a
	# lista vazia É a resposta certa. Olhando para ela, o jogo concluía
	# que a lista nunca tinha chegado e refazia a enumeração no laço
	# principal a cada tentativa, que é exatamente o que esta thread veio
	# evitar.
	if not _lista_ja_veio:
		_adotar_lista(link.list_ports())
	else:
		_pedir_a_lista()
	_fila_de_portas = _fila_de_tentativas()
	if _fila_de_portas.is_empty():
		# PROCURAR TEM DE PARECER PROCURAR. A frase era só
		# "PROCURANDO ARDUINO…", parada, igual a si mesma minuto após
		# minuto — e para quem está na frente da máquina uma frase que não
		# muda é uma busca que travou. Com o caminho em uso e o número da
		# varredura à mostra, dá para ver a máquina trabalhando, e dá para
		# dizer ao telefone o que está escrito.
		_varreduras += 1
		# Sem porta nenhuma à vista já na primeira busca, a enumeração
		# desta máquina não está servindo: solta a varredura cega agora.
		serial_status = "PROCURANDO ARDUINO… (%s, busca %d, nenhuma porta à vista)" % [
			link.descricao(), _varreduras
		]
		proxima_tentativa = animation_time + 1.5
		_porta_da_vez = 0
		return
	# Dá a volta na lista: a placa pode ter sido espetada depois de a
	# máquina ligar, e a porta dela entra no fim.
	if _porta_da_vez >= _fila_de_portas.size():
		_porta_da_vez = 0
		_varreduras += 1
		_fila_de_portas = _fila_de_tentativas()
	var porta := _fila_de_portas[_porta_da_vez]
	_porta_da_vez += 1
	# Furar a fila vale UMA vez. Se a placa não estava ali, a porta nova
	# volta a ser uma porta como as outras e a fila segue normalmente —
	# senão um adaptador Bluetooth recém-pareado prenderia a busca.
	var acabou_de_chegar := porta == _porta_recem_chegada
	if acabou_de_chegar:
		_porta_recem_chegada = ""
	var marcada := link.portas_promissoras().has(porta)
	if acabou_de_chegar:
		serial_status = "ABRINDO %s — PORTA RECÉM-CONECTADA" % porta
	else:
		serial_status = "CONECTANDO %s%s (%d de %d, busca %d)" % [
			porta, " •" if marcada else "",
			_porta_da_vez, _fila_de_portas.size(), _varreduras + 1
		]
	_porta_confirmada = false
	_porta_pedida_em = animation_time
	_porta_aberta_em = animation_time
	if link.open_port(porta, GameDef.SERIAL_BAUD):
		porta_atual = porta
		ultimo_sinal_ms = -1
		proximo_ping = animation_time + 1.0
	else:
		serial_status = "FALHA AO ABRIR %s" % porta
		# Nome inventado pela varredura cega costuma recusar na hora; não
		# se paga quase um segundo por cada uma das 64 possibilidades.
		var era_conhecida := portas_visiveis.has(porta) \
			or porta == porta_configurada or porta == porta_serial_conhecida
		proxima_tentativa = animation_time + (0.8 if era_conhecida else 0.15)

## QUANTO ESPERAR ESTA PORTA, especificamente.
##
## A porta que o Windows chama de Arduino/CH340/FTDI ganha a paciência
## inteira. A que ele não sabe nomear ganha a curta — é quase sempre
## Bluetooth ou leitor de cartão, que abre e nunca diz nada.
##
## E a regra de ouro: quando o sistema não sabe distinguir NENHUMA (lista
## de promissoras vazia), todas ganham a paciência inteira. Falta de
## informação não pode virar pressa, senão a máquina passa a descartar a
## porta certa num PC onde a enumeração é cega — que é justamente o PC
## onde tudo isso já é mais difícil.
func _paciencia_da_porta() -> float:
	if link == null:
		return PORTA_PACIENCIA
	var promissoras := link.portas_promissoras()
	if promissoras.is_empty():
		return PORTA_PACIENCIA
	# A porta fixada pelo operador é escolha de gente: paciência inteira.
	if not porta_configurada.is_empty() and porta_atual == porta_configurada:
		return PORTA_PACIENCIA
	return PORTA_PACIENCIA if promissoras.has(porta_atual) else PORTA_PACIENCIA_ANONIMA

## DESISTIR DESTA PORTA E PASSAR PARA A PRÓXIMA, num lugar só.
##
## Eram dois trechos parecidos e um deles esquecia de contar a falha da
## porta fixada. Um lugar só é o que garante que desistir signifique
## sempre a mesma coisa, venha a desistência do encanamento ou da placa.
func _desistir_da_porta(motivo: String) -> void:
	if not porta_configurada.is_empty() and porta_atual == porta_configurada:
		_falhas_da_porta_fixa += 1
		if _falhas_da_porta_fixa == FALHAS_ATE_SOLTAR_A_PORTA_FIXA:
			_show_notice(
				"%s NÃO RESPONDE — VARRENDO TODAS AS PORTAS" % porta_configurada
			)
	var tem_outras := _fila_de_tentativas().size() > 1
	var recado := "%s EM %s%s" % [
		motivo, porta_atual, " — TENTANDO A PRÓXIMA" if tem_outras else ""
	]
	if link != null:
		# `close_port` emite `closed`, e `_on_serial_closed` escreve
		# "DESCONECTADO" por cima. A frase que explica é a que fica.
		link.close_port()
	serial_status = recado
	proxima_tentativa = animation_time + (0.3 if tem_outras else 2.0)

func _poll_serial(_delta: float) -> void:
	if link == null:
		return
	_passo_do_motor()
	# O BATIMENTO VEM ANTES DE QUALQUER PERGUNTA, E É INCONDICIONAL.
	#
	# AQUI ESTAVA O DEFEITO QUE MATAVA A MÁQUINA PARA SEMPRE. Estava
	# assim:
	#
	#     if link == null or not link.available():
	#         return
	#     link.poll()
	#
	# `poll()` é o único batimento do backend — é DENTRO dele que a ponte
	# por processo ressuscita o ajudante que morreu. E `available()` da
	# ponte responde falso exatamente no intervalo em que ela está caída.
	# Ou seja: no instante em que o batimento passava a ser necessário,
	# ele parava. Um ajudante que caísse uma única vez (o PowerShell
	# morrendo, o cabo USB dando uma soluçada, a troca de receita) nunca
	# mais voltava, e a tela ficava congelada em "PROCURANDO ARDUINO…" até
	# alguém reiniciar o jogo. O código de ressurreição existia, estava
	# certo, e era inalcançável.
	link.poll()
	if _troca_de_caminho_pendente:
		_troca_de_caminho_pendente = false
		_trocar_de_caminho("conexão oscilou %d vezes em dois minutos" % QUEDAS_ATE_TROCAR_CAMINHO)
		return
	if not link.available():
		_sem_caminho_ate_a_placa()
		return
	# NA CENTRAL, A LISTA É VIGIADA MESMO COM UMA PORTA JÁ ABERTA.
	#
	# Abaixo, a lista só é pedida no ramo em que NENHUMA porta está
	# aberta. Mas o caso do técnico é o contrário: o jogo está sentado
	# numa porta muda, esperando os quatro segundos e meio de paciência,
	# e é bem nesse intervalo que o cabo entra. Sem isto, a porta nova só
	# seria notada depois de a paciência acabar — e a tela ficava parada
	# dizendo que não havia nada. Só enquanto a placa não respondeu: com
	# a placa falando, mexer na lista não serve para nada.
	if central_aberta and not placa_respondeu:
		_pedir_a_lista()
	if not link.is_open():
		if animation_time >= proxima_tentativa and _hora_de_procurar():
			_tentar_conectar()
		return
	if not _porta_confirmada and animation_time - _porta_pedida_em > ESPERA_DA_CONFIRMACAO:
		# O PEDIDO DE ABERTURA SUMIU NO ENCANAMENTO. Não é a placa: é o
		# ajudante, o cano ou o driver. Ver `ESPERA_DA_CONFIRMACAO`.
		_desistir_da_porta("NÃO ABRIU")
		return
	if _porta_confirmada and ultimo_sinal_ms < 0 and animation_time - _porta_aberta_em > _paciencia_da_porta():
		# CALADA DESDE QUE ABRIU: NÃO É O ENCANAMENTO. Ver o comentário de
		# `PORTA_PACIENCIA`, acima, para o motivo do número.
		_desistir_da_porta("SEM RESPOSTA")
		return
	if not _porta_confirmada:
		return
	if ultimo_sinal_ms < 0 and animation_time >= proximo_ping:
		# Ainda não vimos o READY: cutuca a placa.
		link.send_line("PING")
		proximo_ping = animation_time + 1.0
	elif ultimo_sinal_ms >= 0 and animation_time >= proximo_ping:
		link.send_line("PING")
		proximo_ping = animation_time + 5.0
	var limite_silencio := SERIAL_SILENCIO_NORMAL_MS
	if placa_calibrando:
		limite_silencio = SERIAL_SILENCIO_CALIBRANDO_MS
	elif state in [GameDef.State.COUNTDOWN, GameDef.State.ARMED]:
		limite_silencio = SERIAL_SILENCIO_EM_JOGO_MS
	var silencio_ms := Time.get_ticks_msec() - ultimo_sinal_ms if ultimo_sinal_ms >= 0 else 0
	if ultimo_sinal_ms >= 0 and silencio_ms > 6000 and animation_time >= proximo_ping:
		# Antes de tocar na porta, confirma com pings rápidos. A ponte segue
		# lendo em paralelo e qualquer resposta cancela naturalmente o prazo.
		link.send_line("PING")
		proximo_ping = animation_time + 1.0
		serial_status = "VERIFICANDO SINAL — %s" % porta_atual
	if ultimo_sinal_ms >= 0 and silencio_ms > limite_silencio:
		# SILÊNCIO PROLONGADO NÃO PODE SER SÓ UM AVISO NA TELA.
		#
		# Antes disto, "SEM RESPOSTA" era só texto: a porta continuava
		# aberta, o PING continuava saindo a cada cinco segundos, e se o
		# Arduino tivesse de fato travado ou o cabo USB tivesse dado uma
		# soluçada, NADA nunca mais chegava — o jogo ficava com aquele
		# aviso na tela e o soco morto até alguém reiniciar a máquina. É
		# exatamente o "se demorar um pouco, ele não lê mais": não é o
		# firmware que esquece de responder, é o jogo que nunca tenta de
		# novo depois de perceber o silêncio.
		#
		# Agora o silêncio fecha a porta e entra na MESMA fila de conexão
		# do início — reabre a mesma porta (ou a próxima, se houver mais
		# de uma), do zero, com toda a lógica de PORTA_PACIENCIA de novo.
		# Uma reconexão automática devolve a máquina sem intervenção;
		# não reconectar nunca é que perde a máquina a noite inteira.
		serial_status = "SEM RESPOSTA HÁ %d s — %s — RECONECTANDO" % [int(silencio_ms / 1000), porta_atual]
		var recado := serial_status
		link.close_port()
		serial_status = recado
		return

## Sem plugin USB (APK gerado sem o addon, ou fora do Android): diz o
## motivo e tenta montar o caminho de novo a cada tanto.
func _sem_caminho_ate_a_placa() -> void:
	porta_atual = ""
	_porta_confirmada = false
	serial_status = "SEM CAMINHO ATÉ O ARDUINO"
	var motivo := link.motivo_da_falta()
	if not motivo.is_empty():
		serial_status += " (%s)" % motivo
	if animation_time >= _proxima_escolha_de_caminho:
		_trocar_de_caminho("nenhum caminho respondeu")

func _trocar_de_caminho(motivo: String) -> void:
	_trocas_de_caminho += 1
	_iniciar_serial()
	var agora := link.descricao() if link != null else "nenhum"
	serial_status = "TROCANDO DE CAMINHO — %s → %s" % [motivo, agora]

func _on_serial_opened(porta: String) -> void:
	porta_atual = porta
	placa_calibrando = false
	progresso_calibracao = 0
	# A PORTA CONFIRMOU. É daqui que a paciência com a PLACA começa a
	# contar, e não de quando o jogo pediu. Ver `PORTA_PACIENCIA`.
	_porta_confirmada = true
	_porta_aberta_em = animation_time
	serial_status = "AGUARDANDO READY — %s" % porta

func _on_serial_closed(_porta: String) -> void:
	# PORTA QUE NUNCA FALOU NÃO MERECE ESPERA. A fila só anda quando esta
	# pausa termina: três segundos por porta (o valor antigo) numa máquina
	# com seis portas COM é meio minuto de máquina morta em cada volta, e
	# com a varredura cega seria minutos. Uma porta que recusou ou que
	# nunca disse nada sai da frente em um terço de segundo; só a que
	# ESTAVA falando e caiu ganha o segundo inteiro, porque nesse caso a
	# pausa é para o driver soltar a porta antes de reabri-la.
	var estava_falando := ultimo_sinal_ms >= 0
	if estava_falando:
		var agora_ms := Time.get_ticks_msec()
		var recentes: Array[int] = []
		for instante in _quedas_do_caminho:
			if agora_ms - instante <= JANELA_DE_QUEDAS_MS:
				recentes.append(instante)
		_quedas_do_caminho = recentes
		_quedas_do_caminho.append(agora_ms)
		if _quedas_do_caminho.size() >= QUEDAS_ATE_TROCAR_CAMINHO:
			_caminho_provado = false
			_troca_de_caminho_pendente = true
			_quedas_do_caminho.clear()
	# "DESCONECTADO" ERA A FRASE ERRADA, E ERA A QUE MAIS SE VIA.
	#
	# Ela é um veredito — soa como fim de linha, como se não houvesse
	# nada acontecendo — e era o que a Central mostrava justamente nos
	# segundos em que a máquina mais trabalha: logo depois de a porta
	# cair, com a reconexão já marcada para daqui a um décimo de
	# segundo. Quem estava com o cabo na mão lia "desconectado" e
	# concluía que o jogo tinha desistido.
	#
	# Estas duas dizem o que aconteceu e o que vem a seguir, que é a
	# única coisa que alguém na frente do gabinete quer saber.
	if _porta.is_empty():
		serial_status = "PROCURANDO A PLACA…"
	elif estava_falando:
		serial_status = "A PLACA CAIU EM %s — RECONECTANDO" % _porta
	else:
		serial_status = "%s FECHOU — SEGUINDO A BUSCA" % _porta
	# Se esta porta ja disse READY,PUNCH_MPU6050, o problema nao e
	# descoberta. Reabre a mesma COM primeiro, sem reiniciar a varredura em
	# portas que sabemos nao serem a placa.
	if not _porta.is_empty() and _porta == porta_arduino_identificada:
		porta_serial_conhecida = _porta
		_porta_da_vez = 0
	porta_atual = ""
	ultimo_sinal_ms = -1
	_porta_confirmada = false
	placa_respondeu = false
	sensor_presente = false
	firmware_optico_identificado = false
	placa_calibrando = false
	progresso_calibracao = 0
	proxima_tentativa = animation_time + (1.0 if estava_falando else 0.18)
	if estava_falando:
		sons.play("disconnect_alert", -4.0)
	# Sem sensor não há rodada honesta. Antes do primeiro golpe, devolve a
	# ficha; entre as duas tentativas, preserva o resultado já conquistado.
	if not central_aberta and state in [GameDef.State.COUNTDOWN, GameDef.State.ARMED]:
		if socos.is_empty():
			_devolver_credito()
			_entrar_em_abertura()
		else:
			_entrar_em_resultado(true)
		_show_notice("SENSOR DESCONECTADO — RECONECTANDO")

func _on_serial_line(line: String) -> void:
	var msg := ArduinoProtocol.parse(line)
	if msg.is_empty() or str(msg.get("type", "")) == "":
		return
	ultimo_sinal_ms = Time.get_ticks_msec()
	# Uma linha válida prova que este caminho funciona.
	_caminho_desde = animation_time
	_caminho_provado = true
	# QUALQUER LINHA VÁLIDA JÁ PROVA A PORTA — não só o `READY`.
	#
	# O jogo esperava o `READY` para dizer "CONECTADO", e o `READY` sai
	# UMA vez, no arranque da placa. Quando o jogo reinicia e o Arduino
	# não — a máquina ligada, o operador fechando e abrindo o jogo, ou o
	# driver que não reseta a placa ao abrir a porta — esse `READY` já
	# passou há muito. A porta certa ficava então em "AGUARDANDO READY"
	# para sempre, mesmo com a placa despejando TELEMETRY e PINS quatro
	# vezes por segundo naquela mesma porta: a máquina estava vendo os
	# dados e dizendo que não havia ninguém.
	#
	# Uma linha que o protocolo entendeu só pode ter vindo do firmware.
	# Isso é a prova, e é o bastante.
	if not placa_respondeu:
		placa_respondeu = true
		serial_status = "CONECTADO %s" % porta_atual
		# O MOMENTO EM QUE A PLACA FALA MERECE SER VISTO E OUVIDO.
		#
		# É o instante que o técnico está esperando de olho na tela, e
		# até aqui ele era uma linha de status trocando em corpo 14 —
		# invisível se a pessoa estava olhando para o conector, que é
		# exatamente onde ela está olhando. `_show_notice` não serve:
		# a faixa de aviso foi removida da tela do jogo a pedido, e a
		# chamada não desenha mais nada.
		#
		# O que serve é marcar a HORA e deixar o seletor da Central
		# comemorar por um segundo e meio (ver `_seletor_porta_refinado`),
		# com um toque curto para quem não estava olhando.
		#
		# E é honesto: nada disso sai antes daqui, porque antes daqui não
		# há prova nenhuma de que o que está na porta seja a placa.
		_placa_achada_em = animation_time
		sons.play("menu", -10.0)
	match str(msg["type"]):
		"READY":
			serial_status = "CONECTADO %s" % porta_atual
			var ja_identificado := firmware_optico_identificado
			var dispositivo := str(msg.get("device", "")).strip_edges().to_upper()
			# Aceita as identificações das revisões do firmware MH/LM393. O
			# hardware óptico não deve ser rejeitado apenas porque a etiqueta
			# mudou entre PUNCH_OPTICAL, PUNCH_MH e PUNCH_LM393.
			firmware_optico_identificado = dispositivo in ["PUNCH_OPTICAL", "PUNCH_MH", "PUNCH_LM393"] \
				or "OPTICAL" in dispositivo or "LM393" in dispositivo
			# O firmware responde READY também a cada PING. Só o PRIMEIRO
			# READY põe a máquina em "calibrando"; os seguintes só marcam a
			# hora, e viram religamento se um CALIBRATING vier logo atrás
			# (ver "CALIBRATING"). Antes, cada PING deixava o jogo preso em
			# "calibrando" até a próxima calibração, que nunca vinha.
			if firmware_optico_identificado and ja_identificado:
				_ready_repetido_em = animation_time
			elif firmware_optico_identificado:
				porta_arduino_identificada = porta_atual
				placa_calibrando = true
				progresso_calibracao = 0
				mensagem_sensor_publica = "MANTENHA O ALVO PARADO"
				# Grava a COM assim que a PLACA se identifica. Esperar o sensor
				# terminar de calibrar era o que fazia o jogo esquecer a COM
				# certa justamente quando ela travava aos 70%.
				var rota_mudou := false
				if not porta_atual.is_empty() and porta_serial_conhecida != porta_atual:
					porta_serial_conhecida = porta_atual
					rota_mudou = true
				if link != null and caminho_serial_conhecido != link.nome_do_caminho():
					caminho_serial_conhecido = link.nome_do_caminho()
					rota_mudou = true
				if rota_mudou:
					_salvar()
			# PLACA ENCONTRADA NÃO É SENSOR ENCONTRADO.
			#
			# O firmware passou a mandar o `READY` ANTES de procurar o
			# MPU-6050, para que a máquina se apresente mesmo com o sensor
			# solto — foi assim que os botões voltaram a funcionar sem
			# sensor. Mas a chave da bancada não pode mais desligar aqui:
			# desligaria a barra de espaço numa máquina em que NÃO HÁ como
			# socar, e aí não sobraria jeito nenhum de jogar.
			#
			# Quem desliga a bancada agora é a prova de que o sensor
			# existe: o `OK,MPU` do firmware, ou o primeiro golpe medido.
			if firmware_optico_identificado and not ja_identificado:
				sensor_presente = false
				_enviar_config()
			elif not firmware_optico_identificado:
				sensor_presente = false
				placa_calibrando = false
				serial_status = "FIRMWARE INCOMPATÍVEL — USE O ÓPTICO"
		"PINS":
			pino_start = bool(msg["start"])
			pino_credito = bool(msg["credit"])
		"MOTOR":
			# A PLACA É QUEM SABE ONDE O SACO ESTÁ. O jogo só pede; quem
			# conta o curso, lê o fim de curso e desliga o motor é o
			# firmware — inclusive se este programa fechar no meio.
			saco.receber(msg)
		"PONG":
			if not porta_atual.is_empty() and not serial_status.begins_with("CONECTADO"):
				serial_status = "CONECTADO %s" % porta_atual
		"CALIBRATING":
			if not firmware_optico_identificado:
				return
			# READY seguido de calibração = a placa religou sozinha (queda
			# de energia, reset). Ela voltou com a configuração de fábrica:
			# a nossa é reenviada assim que a calibração terminar.
			if animation_time - _ready_repetido_em < 1.5 and animation_time - _config_enviada_em > 3.0:
				_reenviar_config = true
			_ready_repetido_em = -99.0
			placa_calibrando = true
			progresso_calibracao = int(msg["percent"])
			mensagem_sensor_publica = "MANTENHA O ALVO PARADO"
			serial_status = "CALIBRANDO %d%%" % int(msg["percent"])
		"CALIBRATED":
			if not firmware_optico_identificado:
				return
			# Só existe calibração concluída se o MPU respondeu e forneceu
			# amostras; isto também reconhece firmwares V9 anteriores, que
			# ainda não mandavam OK,MPU no primeiro arranque.
			placa_calibrando = false
			progresso_calibracao = 100
			mensagem_sensor_publica = ""
			if _reenviar_config:
				_reenviar_config = false
				_enviar_config()
			_sensor_apareceu()
			serial_status = "CONECTADO %s" % porta_atual
			if state == GameDef.State.ARMED and not central_aberta:
				_armar_sensor_optico()
			_show_notice("SENSOR CALIBRADO")
		"BUTTON":
			var nome_botao := str(msg["button"])
			# CONFIG e o F9 fisico: funciona tanto com a Central aberta quanto
			# fechada e nunca consome credito nem inicia partida.
			if nome_botao == "CONFIG":
				_toggle_central()
				return
			# O CONTADOR SOBE SEMPRE, inclusive com a Central aberta.
			#
			# É ele que prova ao técnico que o fio está certo: aperta o
			# botão, o número sobe. Sem isso, "o botão não funciona" pode
			# ser fio solto, pino errado, placa muda ou o jogo ignorando —
			# quatro problemas com o mesmo sintoma. Com o contador, dois
			# deles se descartam em um segundo.
			if nome_botao == "CREDIT":
				serial_credito += 1
			else:
				serial_start += 1
			if central_aberta:
				return
			if nome_botao == "CREDIT":
				_add_credit()
			else:
				_pressionou_start()
		"HIT":
			if firmware_optico_identificado:
				_receber_hit(msg)
		"TELEMETRY":
			if not firmware_optico_identificado:
				return
			_sensor_apareceu()
			telemetria = "feixe %s  •  A0 %.0f%%  •  última %.2f m/s" % [
				"INTERROMPIDO" if msg["accel"].x > 0.5 else "LIVRE",
				msg["accel"].y * 100.0, msg["velocity"],
			]
		"REJECT":
			_recusa_da_placa(msg)
		"NOISE":
			_sensor_apareceu()
		"STATUS":
			sensor_forca = float(msg["force_g"])
			sensor_gatilho = float(msg["trigger_g"])
			if sensor_forca > sensor_forca_maxima:
				sensor_forca_maxima = sensor_forca
		"SATURATION":
			# SATURAÇÃO NÃO VIRA 9999. O sensor chegou ao fim da escala e
			# parou de medir: a máquina não sabe quanto aquele golpe valeu,
			# e chutar o teto seria inventar. Fica registrado para a
			# Central, que é onde alguém pode aumentar a faixa do MPU.
			saturacao_recente = "%s às %s" % [
				str(msg["source"]), Time.get_time_string_from_system(true)
			]
			_show_notice("SATURAÇÃO NO %s — AUMENTE A FAIXA DO SENSOR" % str(msg["source"]))
		"OK":
			# OK,MPU prova que o componente respondeu, mas START so e
			# liberado por CALIBRATED/TELEMETRY. Firmwares antigos podiam
			# enviar OK mesmo quando a calibracao acabava de falhar.
			if str(msg.get("detail", "")) == "OPTICAL" and not sensor_presente:
				serial_status = "SENSOR ENCONTRADO — PREPARANDO"
		"ERROR":
			if str(msg["code"]) in ["NO_MPU", "MPU_LEITURA"]:
				# SEM SENSOR A MÁQUINA CONTINUA DE PÉ: botões e crédito
				# seguem funcionando pela serial; só o soco depende do
				# MPU-6050. Dizer isso é melhor do que dizer "erro".
				sensor_presente = false
				placa_calibrando = false
				mensagem_sensor_publica = "SENSOR DE SOCO INDISPONÍVEL"
				serial_status = "PLACA OK, SEM SENSOR — CONFIRA SDA/SCL"
				_show_notice("SENSOR DE SOCO INDISPONÍVEL")
			elif str(msg["code"]) == "CALIB_MOVIMENTO":
				sensor_presente = false
				placa_calibrando = true
				progresso_calibracao = 0
				mensagem_sensor_publica = "MANTENHA O ALVO PARADO"
				serial_status = "CALIBRAÇÃO INTERROMPIDA POR MOVIMENTO"
				_show_notice("MANTENHA O ALVO PARADO")
			elif str(msg["code"]) == "CALIB_LEITURA":
				sensor_presente = false
				placa_calibrando = true
				progresso_calibracao = 0
				mensagem_sensor_publica = "PREPARANDO O SENSOR — AGUARDE"
				serial_status = "FALHA DE LEITURA DURANTE A CALIBRAÇÃO"
			else:
				_show_notice("NÃO FOI POSSÍVEL PREPARAR O SENSOR")
			sons.play("error", -8.0)

## TEMPO MORTO ENTRE DOIS GOLPES ACEITOS, em milissegundos.
##
## Depois do impacto o saco balança, e o MPU-6050 vê o balanço como uma
## sequência de eventos menores. Sem tempo morto, um soco vira três — e o
## segundo, mais fraco, seria o que ficaria no placar.
const TEMPO_MORTO_MS := 900
## Um soco de verdade dura dezenas de milissegundos. Um toque, um esbarrão
## ou um tranco no gabinete duram muito menos.
const DURACAO_MINIMA_MS := 12.0

## O SENSOR SE ANUNCIOU. É o único momento em que a máquina sabe, sozinha,
## que saiu da montagem e entrou em operação.
func _sensor_apareceu() -> void:
	if not firmware_optico_identificado:
		return
	if sensor_presente:
		return
	sensor_presente = true
	serial_status = "CONECTADO %s" % porta_atual
	# Só guardamos uma rota depois de chegar até o sensor de verdade. Uma
	# porta Bluetooth que respondeu lixo ou uma placa sem MPU não contamina
	# a próxima inicialização. O valor é preferência e pode ser abandonado.
	var mudou := false
	if not porta_atual.is_empty() and porta_serial_conhecida != porta_atual:
		porta_serial_conhecida = porta_atual
		mudou = true
	if link != null and caminho_serial_conhecido != link.nome_do_caminho():
		caminho_serial_conhecido = link.nome_do_caminho()
		mudou = true
	if mudou:
		_salvar()

## A PLACA VIU ALGO E DESCARTOU — E AGORA ISSO APARECE NA TELA.
##
## Este é o buraco que fez este projeto andar em círculos. Quando a
## máquina não marcava o soco, não havia como saber SE a placa tinha
## visto alguma coisa nem POR QUE descartou: "nada acontece" é o mesmo
## sintoma para sensor sem sinal, evento abaixo do gatilho, forma
## recusada, giro de menos e velocidade abaixo do piso. Sem distinguir
## entre elas, só resta adivinhar um limiar por vez — que é exatamente o
## que se fez, versão após versão.
##
## Cada motivo aponta um ajuste diferente, e a frase diz qual:
const RECUSAS := {
	"CURTO": "EVENTO CURTO DEMAIS — VIBRAÇÃO, NÃO SOCO",
	"LENTO": "SUBIDA LENTA — EMPURRÃO, NÃO IMPACTO",
	"SUSTENTADO": "FORÇA SUSTENTADA — O SINAL NÃO CAIU",
	"GIRO": "O ALVO NÃO SE MOVEU — BAIXE O GIRO MÍNIMO",
	"FRACO": "ABAIXO DO PISO DE VELOCIDADE",
}

func _recusa_da_placa(msg: Dictionary) -> void:
	# Golpe recusado ainda é prova de que o sensor está vivo e medindo.
	_sensor_apareceu()
	var motivo := str(msg["reason"])
	ultima_recusa = "%s  •  %.1f g, %.0f ms, %.0f °/s, %.2f m/s" % [
		motivo, float(msg["peak_g"]), float(msg["duration_ms"]),
		float(msg["gyro_dps"]), float(msg["speed"]),
	]
	telemetria = "RECUSADO: %s" % ultima_recusa
	# Só incomoda quem está jogando quando ele está esperando um soco —
	# fora daí a informação fica na Central, que é onde se regula.
	if state == GameDef.State.ARMED and not central_aberta:
		_show_notice(str(RECUSAS.get(motivo, "GOLPE RECUSADO: %s" % motivo)))

func _receber_hit(msg: Dictionary) -> void:
	# Golpe medido é a prova definitiva de que o sensor está lá, mesmo que
	# o `OK,MPU` tenha se perdido no cabo.
	_sensor_apareceu()
	var speed := float(msg["speed"])
	var pico := float(msg.get("accel", 0.0))
	var duracao := float(msg.get("duration_ms", 0.0))
	telemetria = "último evento: %.2f m/s, %.1fg, %.0f ms, eixo %s" % [
		speed, pico, duracao, str(msg.get("axis", "?"))
	]
	# 0) CALIBRANDO: o golpe vira AMOSTRA, e não pontuação. Não conta
	#    partida, não entra no ranking, não gasta ficha.
	#
	#    E A CALIBRAÇÃO SÓ EXISTE COM A CENTRAL ABERTA. Esta segunda
	#    condição é cinto e suspensório: a calibração acontece dentro da
	#    Central e em lugar nenhum mais, então um `calib_ativo` ligado com
	#    a Central FECHADA é, por definição, estado inconsistente — e não
	#    pode ser o motivo de uma partida inteira não pontuar. Sem ela, um
	#    único caminho esquecido (foi o F9) mata a máquina em silêncio.
	if calib_ativo and central_aberta:
		_calibracao_recebeu(speed, pico)
		return
	# AS TRAVAS ABAIXO DEIXAM RASTRO, e isso não é luxo de diagnóstico.
	#
	# Elas eram quatro `return` mudos. Quando uma delas prendia um soco
	# legítimo — e uma prendeu, por meses —, não havia NADA, em lugar
	# nenhum, dizendo que o golpe tinha chegado e sido descartado. O
	# sintoma era idêntico ao de sensor quebrado, e mandou procurar defeito
	# na placa, no cabo e no firmware, que estavam certos.
	#
	# Agora cada uma escreve por que recusou. Fica na Central, que é onde
	# se olha quando a máquina não faz o que devia.
	# 1) FORA DE ARMED NÃO PONTUA. Nem na abertura, nem na foto, nem no
	#    resultado, nem com a Central aberta.
	if state != GameDef.State.ARMED or central_aberta:
		ultima_recusa = "o jogo ignorou: %s" % (
			"a Central está aberta" if central_aberta
			else "a máquina não está esperando soco (estado %d)" % state
		)
		return
	# 2) UM GOLPE POR RODADA.
	if golpe_registrado:
		ultima_recusa = "o jogo ignorou: esta tentativa já teve o golpe dela"
		return
	# 3) TEMPO MORTO: o balanço do saco depois do impacto não é um golpe.
	var desde := Time.get_ticks_msec() - ultimo_golpe_ms
	if desde < TEMPO_MORTO_MS:
		ultima_recusa = "o jogo ignorou: tempo morto (%d ms de %d)" % [desde, TEMPO_MORTO_MS]
		return
	# 4) A FÍSICA DO SOCO NÃO SE JULGA AQUI. Ver abaixo.
	#
	# AS TRAVAS DE FÍSICA SAÍRAM DESTE PONTO, e é isso que torna o caminho
	# único de verdade.
	#
	# O jogo repetia, com números próprios, a mesma validação que o
	# firmware já faz: duração mínima e pico mínimo. Dois juízes para o
	# mesmo julgamento — e o segundo com valores GRAVADOS NO DISCO,
	# portanto capazes de sobreviver a uma atualização e de discordar do
	# primeiro para sempre.
	#
	# Era por aí que a máquina morria de vez: um pulso mínimo envenenado
	# por uma calibração ruim recusava, em silêncio, golpes que a placa
	# tinha acabado de aprovar. Do lado de fora, "o sensor parou de
	# funcionar" — e nenhuma reinstalação resolvia, porque o número estava
	# no arquivo de ajustes e não no programa. Hoje ele nem é mais
	# escolhido: sai da geometria, em `_aplicar_faixas`.
	#
	# Agora há um dono só para cada coisa:
	#   A PLACA decide SE FOI UM SOCO — ela tem os 250 Hz, a linha de base
	#   viva e a forma do impacto.
	#   O JOGO decide SE ESTE SOCO CONTA AGORA — que é regra de jogo, não
	#   de física.
	#
	# `sensor_pulso_ms` continua existindo, mas só como o que sempre
	# deveria ter sido: um número que o jogo MANDA à placa no CONFIG,
	# nunca um segundo filtro deste lado.
	golpe_registrado = true
	ultimo_golpe_ms = Time.get_ticks_msec()
	# O SOCO ENTRA NA MEMÓRIA DA RÉGUA ANTES DE VIRAR NOTA, mas a régua
	# só é recalculada no fim da rodada. Um soco nunca muda a régua que
	# ele mesmo está usando — senão dois socos iguais na mesma rodada
	# pagariam diferente, e é impossível explicar isso a quem jogou.
	auto_escala.registrar(speed)
	_processar_golpe(speed, false, pico, duracao)

## Sensor e teclado passam obrigatoriamente por esta única porta. Assim a
## régua mostrada na Central é a mesma que decide o resultado real.
func _processar_golpe(
	speed: float, simulado: bool, pico_g := 0.0, duracao_ms := 0.0
) -> void:
	var pontos := ScoreCurve.points_from_speed(
		speed, hit_min_speed, hit_max_speed, score_contraste, score_dead_zone,
		score_ref_speed
	)
	# O teclado de manutenção conserva o 9999 para testar toda a cerimônia.
	# No sensor real, só golpes que JÁ chegaram ao teto participam; um em
	# mil recebe a perfeição e os demais ficam em 9998.
	if not simulado:
		pontos = ScoreCurve.aplicar_perfeito_raro(
			pontos, randi_range(0, ScoreCurve.CHANCE_PERFEITA - 1)
		)
	ultima_velocidade = speed
	ultima_nota = pontos
	if pontos <= 0:
		_show_notice("MOVIMENTO ABAIXO DA ZONA DE PONTUAÇÃO")
		return
	_registrar_impacto(pontos, speed, simulado, pico_g, duracao_ms)

## AS FITAS DA MÁQUINA ACOMPANHANDO O PLACAR.
##
## Vinte mensagens por segundo entupiriam a serial e atrasariam o que
## importa, que é a linha do próximo golpe. Doze é o bastante: a coluna
## sobe suave porque a própria placa interpola entre um comando e o
## seguinte.
const FITAS_INTERVALO := 0.08
var _fitas_relogio := 0.0
var _fitas_ultimo := -1.0

func _mandar_fitas(fracao: float, agora := true) -> void:
	if link == null or not link.is_open():
		return
	var f := clampf(fracao, 0.0, 1.0)
	# Sem repetir o mesmo valor: com o placar parado no fim da contagem,
	# repetir gasta serial para não dizer nada.
	if not agora and is_equal_approx(f, _fitas_ultimo):
		return
	var t := float(Time.get_ticks_msec()) / 1000.0
	if t - _fitas_relogio < FITAS_INTERVALO:
		return
	_fitas_relogio = t
	_fitas_ultimo = f
	link.send_line(ArduinoProtocol.build_leds(f))

var _ready_repetido_em := -99.0
var _config_enviada_em := -99.0
var _reenviar_config := false

func _enviar_config() -> void:
	_config_enviada_em = animation_time
	if link != null and link.is_open():
		link.send_line(ArduinoProtocol.build_config(
			sensor_eixo, sensor_raio, hit_min_speed, sensor_pulso_ms, hit_max_speed
		))
		# O AJUSTE DO MOTOR VIAJA JUNTO. Ele é do mesmo tipo de coisa que
		# a largura da palheta: um número que o operador regula uma vez e
		# a placa precisa conhecer. Mandar junto garante que a placa
		# nunca fica com um curso antigo depois de uma reconexão.
		link.send_line(ArduinoProtocol.build_motor_config(
			saco.curso_ms, saco.pausa_ms, saco.fim_de_curso
		))
		link.send_line(ArduinoProtocol.build_motor("ESTADO"))

## SÓ O AJUSTE DO MOTOR, sem arrastar junto a config do sensor.
##
## Mexer no tempo de curso não pode reenviar a calibração do golpe: a
## placa reabre a janela de medida ao receber CONFIG, e fazer isso no
## meio de uma partida perderia o soco de quem está batendo.
func _mandar_config_do_motor() -> void:
	if link != null and link.is_open():
		link.send_line(ArduinoProtocol.build_motor_config(
			saco.curso_ms, saco.pausa_ms, saco.fim_de_curso
		))

## O MANDO À MÃO, para montar a máquina e para o conserto.
##
## `SacoMotor` trabalha por INTENÇÃO — o jogo diz onde o saco deve
## estar, não "liga o motor" —, e é isso que impede o laço infinito. O
## botão da Central usa a mesma porta: ele muda a intenção, e o passo de
## sempre é que fala com a placa. Não há um segundo caminho até o motor,
## e por isso não há um segundo jeito de deixá-lo ligado.
func _mando_do_motor(onde: int) -> void:
	if not saco.ligado:
		_show_notice("LIGUE O MOTOR NESTA PÁGINA ANTES")
		return
	if link == null or not link.is_open():
		_show_notice("SEM PLACA — O MOTOR NÃO RESPONDE")
		return
	saco.quero(onde)
	_show_notice("DESCENDO O SACO" if onde == SacoMotor.Onde.EM_BAIXO else "SUBINDO O SACO")

## Cada tentativa abre uma janela nova também na placa. Isto elimina estado
## residual do retorno da palheta e garante o mesmo caminho para soco 1 e 2.
func _armar_sensor_optico() -> void:
	if link != null and link.is_open() and firmware_optico_identificado:
		link.send_line("ARM")

func _teste_de_golpe() -> void:
	## Na Central Técnica (tecla T ou botão TESTAR): se a placa está
	## ligada, pede um golpe sintético a ela; senão, simula um aqui.
	if link != null and link.is_open():
		link.send_line("TEST")
		_show_notice("TESTE SOLICITADO AO ARDUINO")
	else:
		# O GOLPE SIMULADO TEM DE CAIR DENTRO DA FAIXA CALIBRADA.
		#
		# Era `randf_range(vmin + 1,0, vmax * 0,9)`, e o `+ 1,0` é um
		# metro por segundo fixo num número que pode valer 1,2 no total:
		# numa montagem lenta o piso do sorteio passava do teto, e o
		# botão de testar da Central mostrava um soco fora da escala da
		# própria máquina. Em fração da faixa, ele cai sempre onde deve —
		# de um golpe médio a um golpe forte.
		var speed := lerpf(hit_min_speed, hit_max_speed, randf_range(0.45, 0.88))
		_show_notice("GOLPE SIMULADO — %.1f m/s" % speed)
		if state == GameDef.State.ARMED:
			_receber_hit({
				"speed": speed, "accel": 0.5,
				"duration_ms": 45.0, "axis": sensor_eixo,
			})

# ======================================================================
# CENTRAL TÉCNICA (F9)
# ======================================================================
func _toggle_central() -> void:
	if central_aberta:
		_fechar_central()
	else:
		if state != GameDef.State.IDLE and state != GameDef.State.RESULT:
			_entrar_em_abertura()
		central_aberta = true
		sons.silence()
		if link != null and link.available():
			portas_visiveis = link.list_ports()
		sons.play("menu", -4.0)

func _fechar_central() -> void:
	central_aberta = false
	# O F9 FECHA O ASSISTENTE DE CALIBRAÇÃO JUNTO, e a falta disto era o
	# defeito que fazia a máquina parecer saudável e não pontuar nada.
	#
	# `_fechar_calibracao` só era chamado pelos botões do próprio
	# assistente. Quem abrisse a calibração e saísse pelo F9 — em vez de
	# percorrer os quatro passos — deixava `calib_ativo` ligado para
	# sempre. E `_receber_hit` decide, ANTES de qualquer outra coisa, que
	# golpe recebido durante a calibração vira AMOSTRA e não pontuação.
	#
	# Resultado: a placa media, a serial entregava, a Central mostrava os
	# números subindo, e no jogo NENHUM soco pontuava. Em silêncio, até
	# alguém reiniciar o jogo. Era indistinguível de "o sensor não
	# funciona", e foi por isso que se procurou tanto tempo no lugar
	# errado — na placa, no cabo, no firmware.
	_fechar_calibracao()
	if state == GameDef.State.RESULT:
		sons.music(-28.0)
		if verdict_time < 0.0:
			sons.start_score_loop()
	_aplicar_faixas()
	_salvar()
	_enviar_config()
	sons.play("menu", -8.0)

## Retângulo do botão "−" de um passo.
func _passo_menos(chave: String) -> Rect2:
	var r: Rect2 = PASSOS[chave]
	return Rect2(r.position, Vector2(LADO_BOTAO, r.size.y))

## Retângulo do botão "+" de um passo.
func _passo_mais(chave: String) -> Rect2:
	var r: Rect2 = PASSOS[chave]
	return Rect2(Vector2(r.end.x - LADO_BOTAO, r.position.y), Vector2(LADO_BOTAO, r.size.y))

## Espaço livre entre os dois botões — onde o valor cabe sem encostar.
func _passo_visor(chave: String) -> Rect2:
	var r: Rect2 = PASSOS[chave]
	return Rect2(
		Vector2(r.position.x + LADO_BOTAO + 8.0, r.position.y),
		Vector2(r.size.x - LADO_BOTAO * 2.0 - 16.0, r.size.y)
	)

## Um controle só responde se estiver NA PÁGINA ABERTA. Os retângulos
## continuam existindo mesmo quando não estão desenhados, e um botão
## invisível que responde é a pior espécie de defeito: o técnico clica
## num lugar vazio e a máquina muda de comportamento.
func _visivel_na_pagina(chave: String) -> bool:
	var pagina := int(PAGINA_DO_CONTROLE.get(chave, -1))
	return pagina < 0 or pagina == central_pagina

## A JANELA QUE ROLA, dentro da Central.
##
## O cabeçalho (título, abas) e o rodapé (RESTAURAR, SALVAR, carimbo da
## build) ficam PARADOS; o miolo entre os dois é que anda. É assim que um
## aplicativo se comporta, e é a única forma de a página caber quando a
## letra cresce: sem rolagem, cada rótulo maior empurra a última seção
## para fora do painel — que é exatamente a sobreposição que se via.
const CENTRAL_TOPO := 332.0
const CENTRAL_BASE := 1762.0
const CENTRAL_JANELA := CENTRAL_BASE - CENTRAL_TOPO
## Quanto anda um giro da roda, uma seta, uma página.
const ROLA_RODA := 90.0
const ROLA_SETA := 60.0

var central_rolagem := 0.0
## A base da última seção desenhada. Medida durante o desenho, e não
## anotada numa tabela: uma tabela de alturas por página envelhece na
## primeira seção que alguém mover, e envelhece em silêncio.
var central_fundo := 0.0

## Quanto ainda há para rolar na página atual.
func _rolagem_maxima() -> float:
	return maxf(0.0, central_fundo + 30.0 - CENTRAL_BASE)

func _rolar(quanto: float) -> void:
	central_rolagem = clampf(central_rolagem + quanto, 0.0, _rolagem_maxima())

## O ponto do clique NO ESPAÇO DA PÁGINA.
##
## Controles de página vivem num papel que rolou; os três de fora
## (fechar, restaurar, salvar) estão colados na moldura. Sem esta
## distinção, rolar a página faria o clique acertar o botão de cima.
func _ponto_do_controle(chave: String, p: Vector2) -> Vector2:
	if int(PAGINA_DO_CONTROLE.get(chave, -1)) < 0:
		return p
	return p + Vector2(0.0, central_rolagem)

## Um clique acertou este controle? Junta as três perguntas que sempre
## andavam juntas: está nesta página, o papel rolou, e o ponto caiu dentro.
func _tocou(chave: String, p: Vector2) -> bool:
	if not _visivel_na_pagina(chave):
		return false
	var r: Rect2 = BOTOES_SIMPLES[chave]
	return r.has_point(_ponto_do_controle(chave, p))

func _click_central(p: Vector2) -> void:
	# As abas primeiro: elas ficam por cima de tudo.
	if ABA_RECT.has_point(p):
		central_pagina = clampi(int((p.x - ABA_RECT.position.x) / ABA_LARGURA), 0, PAGINAS.size() - 1)
		# Cada aba começa do começo. Chegar numa página nova já rolada até
		# o meio é o tipo de coisa que faz o técnico achar que faltou
		# conteúdo em cima.
		central_rolagem = 0.0
		mapeando = ""
		return
	# Passos depois: são a maioria dos cliques.
	for chave in PASSOS:
		if not _visivel_na_pagina(chave):
			continue
		if _passo_menos(chave).has_point(_ponto_do_controle(chave, p)):
			_ajustar(chave, -1)
			_salvar()
			return
		if _passo_mais(chave).has_point(_ponto_do_controle(chave, p)):
			_ajustar(chave, 1)
			_salvar()
			return

	# Um clique fora de qualquer botão cancela um mapeamento em curso:
	# quem desistiu não fica com a máquina esperando um aperto para sempre.
	var acertou := false
	for chave in BOTOES_SIMPLES:
		if _tocou(str(chave), p):
			acertou = true
			break
	if not acertou:
		mapeando = ""
		return

	if _tocou("fechar", p) or _tocou("salvar", p):
		_fechar_central()
		return
	elif _tocou("mapear_start", p):
		mapeando = "" if mapeando == "start" else "start"
		return
	elif _tocou("mapear_credito", p):
		mapeando = "" if mapeando == "credito" else "credito"
		return
	elif _tocou("motor_ligado", p):
		saco.ligado = not saco.ligado
		if not saco.ligado:
			# DESLIGAR TEM DE PARAR O MOTOR, e não só o jogo de falar com
			# ele. Um motor descendo quando o operador desliga a função e
			# vai embora é a correia no chão de manhã.
			var freio := saco.parar()
			if link != null and link.is_open() and not freio.is_empty():
				link.send_line(freio)
		_salvar()
		_show_notice("MOTOR DO SACO LIGADO" if saco.ligado else "MOTOR DO SACO DESLIGADO")
	elif _tocou("motor_fim_curso", p):
		saco.fim_de_curso = not saco.fim_de_curso
		_mandar_config_do_motor()
		_salvar()
		_show_notice(
			"USANDO OS FINS DE CURSO" if saco.fim_de_curso
			else "SÓ POR TEMPO — SEM FIM DE CURSO"
		)
	elif _tocou("motor_desce", p):
		_mando_do_motor(SacoMotor.Onde.EM_BAIXO)
	elif _tocou("motor_sobe", p):
		_mando_do_motor(SacoMotor.Onde.EM_CIMA)
	elif _tocou("motor_para", p):
		# PARAR VALE MESMO COM A FUNÇÃO DESLIGADA e mesmo sem intenção
		# aberta: é o botão de emergência da página, e um botão de
		# emergência que às vezes não responde não é botão de emergência.
		var freio := saco.parar()
		if link != null and link.is_open() and not freio.is_empty():
			link.send_line(freio)
		_show_notice("MOTOR PARADO")
	elif _tocou("motor_destrava", p):
		# DESISTIU não é um defeito a esconder: é a placa não tendo
		# confirmado o curso. Destravar é o operador dizendo "arrumei o
		# fio, pode tentar de novo" — e sem isso a única saída seria
		# fechar o jogo.
		saco.destravar()
		_show_notice("MOTOR LIBERADO PARA TENTAR DE NOVO")
	elif _tocou("modo_livre", p):
		game_mode = "free"
	elif _tocou("modo_ficha", p):
		game_mode = "credit"
	elif _tocou("eixo", p):
		var eixos := ["A", "H", "L"]
		sensor_eixo = eixos[(eixos.find(sensor_eixo) + 1) % 3]
	elif _tocou("enviar_config", p):
		_enviar_config()
		_show_notice("CONFIG ENVIADA AO ARDUINO")
	elif _tocou("calibrar", p):
		_abrir_calibracao()
		return
	elif _tocou("testar", p):
		_teste_de_golpe()
	elif _tocou("camera", p):
		camera_enabled = not camera_enabled
		camera_service.set_enabled(camera_enabled)
		_show_notice(camera_service.status)
	elif _tocou("camera_obrigatoria", p):
		camera_obrigatoria = false
		_show_notice("FOTO AUTOMÁTICA QUANDO A CÂMERA ESTIVER DISPONÍVEL")
	elif _tocou("espelhar_camera", p):
		camera_mirrored = not camera_mirrored
		camera_service.mirrored = camera_mirrored
		_salvar()
		_show_notice("PRÉVIA ESPELHADA" if camera_mirrored else "PRÉVIA SEM ESPELHO")
	elif _tocou("diagnosticar", p):
		_examinar_camera(false)
	elif _tocou("instalar_camera", p):
		_examinar_camera(true)
	elif _tocou("sondar_camera", p):
		# PROCURAR DE NOVO, e não só religar: `refresh` zera a desistência
		# e refaz a enumeração inteira. É o botão de quem acabou de
		# espetar a webcam com o jogo já aberto.
		camera_service.procurar_de_novo()
		_show_notice(camera_service.estado_curto())
	elif _tocou("trocar_camera", p):
		camera_service.cycle_camera()
		# A escolha do técnico também é descoberta e também fica guardada:
		# senão o próximo boot volta ao índice antigo e ele troca de novo.
		camera_index = camera_service.selected_index
		_salvar()
		_show_notice(camera_service.status)
	elif _tocou("testar_som", p):
		# O SOCO DE TESTE DA MESA toca o impacto e o nível mais alto por
		# cima da trilha: é o pior caso de mistura, e é nele que se regula.
		sons.play("hit", 1.5)
		sons.play("subgrave", -4.0)
		sons.play("nivel_peso", 0.5)
		sons.duck(16.0, 2.5)
		_show_notice("SOCO DE TESTE — CONFIRA A MISTURA")
	elif _tocou("foto_teste", p):
		var test_path := camera_service.capture_photo()
		if test_path.is_empty():
			_show_notice(camera_service.status)
		else:
			if camera_service.ultima_foto != null:
				foto_teste_texture = ImageTexture.create_from_image(camera_service.ultima_foto)
				foto_teste_ate_ms = Time.get_ticks_msec() + 650
			RankingStore.delete_photo(test_path)
			_show_notice("CAPTURA DA CÂMERA APROVADA")
	elif _tocou("zerar", p):
		if not _confirmar("contadores"):
			return
		credits = 0
		plays = 0
		_show_notice("CONTADORES ZERADOS")
	elif _tocou("zerar_stats", p):
		if not _confirmar("estatisticas"):
			return
		statistics = {}
		_show_notice("ESTATÍSTICAS ZERADAS")
	elif _tocou("zerar_ranking", p):
		if not _confirmar("ranking"):
			return
		if faxina.rodando:
			_show_notice("A FAXINA ANTERIOR AINDA ESTÁ CORRENDO")
			return
		# A ORDEM AQUI É O QUE IMPEDE O RESET DE QUEBRAR O JOGO.
		#
		# Primeiro a pasta é LIDA (as vinte da lista e todas as órfãs que
		# ninguém apagava), depois a lista some e o arquivo é gravado, e
		# só então os arquivos começam a sair — algumas por quadro, por
		# fora deste clique.
		#
		# Gravar antes de apagar é deliberado: se a energia cair no meio
		# da faxina, sobra foto órfã na pasta, que a próxima faxina leva.
		# Ao contrário, sobraria um ranking apontando para fotos que não
		# existem mais — e aí a tela de recordes quebra de verdade.
		var fotos := RankingStore.listar_fotos()
		ranking.clear()
		_photo_cache.clear()
		_salvar()
		faxina.comecar(fotos)
		_show_notice(
			"RANKING ZERADO — APAGANDO %d FOTOS AO FUNDO" % fotos.size()
			if fotos.size() > 0 else "RANKING ZERADO — NÃO HAVIA FOTOS"
		)
	elif _tocou("usar_min", p) or _tocou("usar_ref", p) or _tocou("usar_max", p):
		# REGULAR A MÁQUINA COM UM SOCO E UM TOQUE.
		#
		# O assistente pede dez golpes e quatro passos, e continua sendo o
		# jeito certo de calibrar do zero. Mas quando a queixa é "todo
		# mundo tira mil pontos", o conserto é de um número só: o teto
		# está longe demais do que esta máquina mede. Bater uma vez e
		# dizer "este é o máximo" resolve na hora, com a fila esperando.
		if ultima_velocidade <= 0.0:
			_show_notice("BATA UMA VEZ PRIMEIRO — OU USE TESTAR SENSOR")
			return
		if _tocou("usar_min", p):
			hit_min_speed = ultima_velocidade
			_show_notice("MÍNIMO = %.2f m/s" % ultima_velocidade)
		elif _tocou("usar_ref", p):
			score_ref_speed = ultima_velocidade
			_show_notice("SOCO MÉDIO = %.2f m/s  •  vale %d pontos" % [
				ultima_velocidade, ScoreCurve.PONTOS_DE_REFERENCIA
			])
		else:
			# O TETO FICA UM POUCO ACIMA DO SOCO DADO, e não em cima dele.
			# Com o teto exatamente no soco, quem acabou de bater tiraria
			# 9999 — e um teto que a primeira pessoa encosta deixa de ser
			# teto. Doze por cento é o bastante para 9999 continuar sendo
			# conquistado por quem bate melhor do que este soco.
			hit_max_speed = ultima_velocidade * 1.12
			_show_notice("MÁXIMO = %.2f m/s  •  este soco vale quase 9999" % hit_max_speed)
		# Mexer à mão manda na máquina: o aprendizado recomeça a partir
		# do que acabou de ser dito, em vez de puxar de volta para a
		# média antiga e desfazer o ajuste em algumas rodadas.
		auto_escala.esquecer()
		_aplicar_faixas()
		_enviar_config()
		# A nota do soco mostrado é recalculada na régua nova: sem isto a
		# leitura ao lado continuaria mostrando o número velho, e quem
		# regulou não veria o efeito do próprio toque.
		ultima_nota = ScoreCurve.points_from_speed(
			ultima_velocidade, hit_min_speed, hit_max_speed, score_contraste,
			score_dead_zone, score_ref_speed
		)
	elif _tocou("auto_escala", p):
		auto_escala.ligada = not auto_escala.ligada
		_show_notice(
			"APRENDIZADO LIGADO — A RÉGUA SE AJUSTA SOZINHA" if auto_escala.ligada
			else "APRENDIZADO DESLIGADO — A RÉGUA FICA COMO ESTÁ"
		)
	elif _tocou("esquecer_escala", p):
		auto_escala.esquecer()
		_show_notice("MEMÓRIA DA RÉGUA APAGADA — APRENDENDO DO ZERO")
	elif _tocou("teto_efeitos", p):
		desempenho.teto = desempenho.proximo_teto()
		desempenho.aplicar_teto()
		teto_efeitos = desempenho.teto
		_show_notice("TETO DE EFEITOS: %s" % desempenho.teto)
	elif _tocou("reconectar", p):
		# RECONECTAR REFAZ A ESCOLHA INTEIRA, e não só reabre a porta.
		#
		# Era só um `close_port` seguido de `_tentar_conectar`: reabria a
		# MESMA porta pelo MESMO caminho, que é justamente o par que
		# acabou de não funcionar. Para o técnico que apertou o botão, o
		# pedido é "esquece tudo e procura de novo" — e agora é isso que
		# acontece: caminho escolhido do zero (extensão nativa ou ponte),
		# porta fixada com crédito de novo, fila inteira revarrida.
		_iniciar_serial()
		_show_notice("PROCURANDO O ARDUINO DE NOVO, DO ZERO")
	elif _tocou("padroes", p):
		game_mode = "credit"
		porta_configurada = ""
		hit_min_speed = ScoreCurve.DEFAULT_MIN_SPEED
		hit_max_speed = ScoreCurve.DEFAULT_MAX_SPEED
		score_contraste = ScoreCurve.DEFAULT_CONTRASTE
		score_ref_speed = ScoreCurve.REFERENCIA_AUTOMATICA
		score_dead_zone = ScoreCurve.DEFAULT_DEAD_ZONE
		sensor_eixo = "A"
		sensor_raio = 0.020
		sensor_vmin = ScoreCurve.DEFAULT_MIN_SPEED
		# O pulso mínimo não aparece aqui porque não é um padrão: é uma
		# conta. `_aplicar_faixas`, no fim desta função, o refaz a partir
		# da palheta e do teto que acabaram de voltar ao padrão.
		_show_notice("PADRÕES RESTAURADOS")
	else:
		return
	_aplicar_faixas()
	_salvar()

## Um clique num − ou + . Cada valor tem o seu passo e os seus limites,
## e o saneamento fica com `ScoreCurve.sanitize`, chamado por
## `_aplicar_faixas` logo depois de qualquer ajuste.
func _ajustar(chave: String, direcao: int) -> void:
	match chave:
		"vmin":
			hit_min_speed = clampf(
				hit_min_speed + direcao * 0.1,
				ScoreCurve.MIN_SPEED_MIN, minf(ScoreCurve.MIN_SPEED_MAX, hit_max_speed - 0.5)
			)
		"vmax":
			hit_max_speed = clampf(
				hit_max_speed + direcao * 0.5,
				maxf(ScoreCurve.MAX_SPEED_MIN, hit_min_speed + 0.5), ScoreCurve.MAX_SPEED_MAX
			)
		"curva":
			score_contraste = clampf(
				score_contraste + direcao * 0.05,
				ScoreCurve.CONTRASTE_MIN, ScoreCurve.CONTRASTE_MAX
			)
		"referencia":
			# O SOCO DE REFERÊNCIA ANDA EM m/s, como tudo mais nesta
			# página. Um passo de 0,1 é o mesmo do piso: quem regula
			# compara os três números na mesma unidade e na mesma escala.
			score_ref_speed = clampf(
				_referencia_efetiva() + direcao * 0.1,
				hit_min_speed + (hit_max_speed - hit_min_speed) * ScoreCurve.REFERENCIA_MIN,
				hit_min_speed + (hit_max_speed - hit_min_speed) * ScoreCurve.REFERENCIA_MAX
			)
		# "zona" não tem mais passo na Central — ver `_central_golpe`. O
		# ajuste continua no arquivo e continua valendo na curva; o que
		# saiu foi a segunda maneira de dizer o que a VELOCIDADE MÍNIMA
		# já diz.
		"vol_musica":
			volume_musica = clampf(volume_musica + direcao, -40.0, 6.0)
			sons.set_volumes(volume_musica, volume_efeitos)
		"vol_efeitos":
			volume_efeitos = clampf(volume_efeitos + direcao, -40.0, 6.0)
			sons.set_volumes(volume_musica, volume_efeitos)
		"porta":
			_girar_porta(direcao)
		"raio":
			sensor_raio = clampf(sensor_raio + direcao * 0.001, 0.005, 0.100)
		# O TEMPO DE CURSO É O FREIO DE SEGURANÇA DO MOTOR, não um gosto.
		#
		# É ele que a placa usa para desligar sozinha quando o fim de
		# curso não responde: passou do tempo, para. O teto de 15 s vem
		# do firmware (MOTOR_CURSO_MAX_MS) e é repetido aqui porque um
		# número maior na Central viraria uma promessa que a placa não
		# cumpre — e o operador confiaria nela.
		"curso_motor":
			saco.curso_ms = clampi(saco.curso_ms + direcao * 250, 500, 15000)
			_mandar_config_do_motor()
		"pausa_motor":
			saco.pausa_ms = clampi(saco.pausa_ms + direcao * 50, 100, 2000)
			_mandar_config_do_motor()

	_aplicar_faixas()

## AS PORTAS QUE SE PODE FIXAR — e não só as que estão à vista.
##
## A lista era só `portas_visiveis`, e isso tornava a opção inútil
## justamente quando ela é mais necessária: com a placa desligada ou o
## driver ainda sem carregar, a COM do Nano não aparece, e não havia como
## deixá-la escolhida ESPERANDO a placa chegar. Fixar uma porta é dizer
## "é aqui que ela vai estar" — uma decisão sobre o futuro, não sobre o
## presente.
##
## No Windows entram COM1 a COM12 sempre; no Linux e no macOS a
## enumeração é confiável e a lista real basta.
func _opcoes_de_porta() -> PackedStringArray:
	var opcoes := PackedStringArray(["AUTO"])
	for porta in portas_visiveis:
		if not opcoes.has(porta):
			opcoes.append(porta)
	# A porta guardada entra na lista mesmo que hoje ninguém a veja: sem
	# isso, abrir a Central com a placa fora do ar apagaria a escolha.
	if not porta_configurada.is_empty() and not opcoes.has(porta_configurada):
		opcoes.append(porta_configurada)
	return opcoes

func _girar_porta(direcao: int) -> void:
	var opcoes := _opcoes_de_porta()
	var atual := opcoes.find(porta_configurada if not porta_configurada.is_empty() else "AUTO")
	if atual < 0:
		atual = 0
	atual = (atual + direcao + opcoes.size()) % opcoes.size()
	var escolha := opcoes[atual]
	porta_configurada = "" if escolha == "AUTO" else escolha
	# Trocar a porta à mão vale agora, não na próxima varredura.
	if link != null and link.is_open():
		link.close_port()
	proxima_tentativa = animation_time
	_porta_da_vez = 0

func _show_notice(message: String) -> void:
	notice = message
	notice_left = 2.8

func _confirmar(action: String) -> bool:
	if confirm_action == action and animation_time <= confirm_until:
		confirm_action = ""
		return true
	confirm_action = action
	confirm_until = animation_time + 4.0
	_show_notice("CONFIRME: CLIQUE NOVAMENTE EM ATÉ 4 SEGUNDOS")
	return false

# ======================================================================
# ESTADO EM DISCO
# ======================================================================
func _carregar() -> void:
	var data := SettingsStore.load_data()
	if data.is_empty():
		return
	game_mode = str(data.get("mode", game_mode))
	saco.carregar(data.get("saco_motor", {}))
	credits = int(data.get("credits", credits))
	plays = int(data.get("plays", plays))
	# MIGRAÇÃO: instalações antigas guardavam um recorde só. Ele vira a
	# primeira linha do ranking, para o dono não perder a marca da casa
	# ao atualizar o software.
	var antigo := int(data.get("best_score", 0))
	# A versão gravada decide se as marcas ainda estão na escala antiga.
	# Ausente quer dizer "arquivo de antes de existir versão", ou seja,
	# escala 0 a 999 — e é essa a única vez que a conversão acontece.
	var esquema := int(data.get("ranking_schema", RankingStore.ESQUEMA_LEGADO))
	ranking = RankingStore.migrate(data.get("ranking", []), antigo, esquema)
	if esquema < RankingStore.ESQUEMA:
		# Grava a nova versão já, e não só no próximo `_salvar`: uma queda
		# de energia entre a conversão e o primeiro salvamento converteria
		# tudo de novo no religar.
		# Grava a versão nova AGORA, e não só no próximo `_salvar`: uma
		# queda de energia entre a conversão e o primeiro salvamento
		# converteria tudo outra vez no religar.
		_converteu_esquema = true
	porta_configurada = str(data.get("port", porta_configurada))
	porta_serial_conhecida = str(data.get("serial_last_good_port", porta_serial_conhecida))
	caminho_serial_conhecido = str(data.get("serial_last_good_backend", caminho_serial_conhecido))
	if caminho_serial_conhecido != SerialLink.CAMINHO_ANDROID_USB:
		caminho_serial_conhecido = ""
	# OS AJUSTES DO SENSOR SÓ VALEM NA ESCALA EM QUE FORAM MEDIDOS.
	# Ver `ESCALA_DO_SENSOR`. Fora dela, ficam os padrões desta versão.
	var escala_salva := int(data.get("sensor_escala", 0))
	if escala_salva >= ESCALA_DO_SENSOR:
		hit_min_speed = float(data.get("hit_min_speed", hit_min_speed))
		hit_max_speed = float(data.get("hit_max_speed", hit_max_speed))
		if int(data.get("score_schema", 0)) >= ESQUEMA_DA_PONTUACAO:
			score_contraste = float(data.get("score_contraste", score_contraste))
			score_ref_speed = float(data.get("score_ref_speed", score_ref_speed))
			score_dead_zone = float(data.get("score_dead_zone", score_dead_zone))
		else:
			# Atualiza a curva sem elevar o teto medido nem alterar a montagem.
			# ESQUEMA ANTIGO: a dificuldade era um expoente de 1,5 a 4,5 e
			# o campo de mesmo espírito agora vai de 0,70 a 1,80. Ler um
			# pelo outro entregaria a máquina no contraste máximo sem
			# ninguém ter pedido. A faixa medida no gabinete continua
			# valendo, então a âncora volta para o automático e é
			# recalculada a partir dela.
			score_contraste = ScoreCurve.DEFAULT_CONTRASTE
			score_ref_speed = ScoreCurve.REFERENCIA_AUTOMATICA
			score_dead_zone = ScoreCurve.DEFAULT_DEAD_ZONE
			_converteu_esquema = true
		sensor_eixo = str(data.get("sensor_eixo", sensor_eixo))
		sensor_raio = float(data.get("sensor_raio", sensor_raio))
		# A MEMÓRIA DA RÉGUA SOBREVIVE AO DESLIGAR. Sem isto a máquina
		# reaprenderia do zero toda manhã, e a primeira meia hora de cada
		# dia teria a escala errada — justamente o horário em que menos
		# gente está olhando para consertar.
		auto_escala.carregar(data.get("auto_escala", {}))
		sensor_vmin = float(data.get("sensor_vmin", sensor_vmin))
		# O PULSO MÍNIMO NÃO É LIDO DO DISCO, e isto é de propósito.
		#
		# Ele é consequência da largura da palheta e do teto de
		# velocidade, e as duas acabaram de ser carregadas: `_aplicar_faixas`
		# o recalcula em seguida. Ler um valor gravado seria justamente o
		# que fez a máquina se estrangular e permanecer estrangulada —
		# um número errado, salvo em disco, sobrevivendo a reinstalação.
		# O `sensor_amin` de versões antigas fica no arquivo e é ignorado.
	else:
		# Valores antigos do MPU nao servem para o sensor optico.
		sensor_eixo = "A"
		sensor_raio = 0.020
		ajustes_do_sensor_zerados = not data.is_empty()
	volume_musica = float(data.get("volume_musica", volume_musica))
	volume_efeitos = float(data.get("volume_efeitos", volume_efeitos))
	botao_start = _mapa_de_botao(data.get("botao_start", {}), 6)
	botao_credito = _mapa_de_botao(data.get("botao_credito", {}), 4)
	camera_enabled = bool(data.get("camera_enabled", camera_enabled))
	# Migração deliberada: versões antigas podiam salvar `true` e bloquear
	# todas as partidas seguintes. A câmera agora é sempre não bloqueante.
	camera_obrigatoria = false
	camera_index = int(data.get("camera_index", camera_index))
	teto_efeitos = str(data.get("teto_efeitos", teto_efeitos))
	desempenho.teto = teto_efeitos
	desempenho.aplicar_teto()
	# Nova preferencia: a versao anterior espelhava a previa e a foto parecia
	# trocar de lado no clique. O padrao agora e orientacao normal; a chave v2
	# impede um `true` antigo de reintroduzir o defeito apos a atualizacao.
	camera_mirrored = bool(data.get("camera_preview_mirrored_v2", false))
	statistics = StatisticsStore.sanitize(data.get("statistics", {}))

## O DISCO SAIU DA LINHA DO JOGO — ver `SettingsStore.save_data_async`.
##
## Este método é chamado ao fechar a rodada, no mesmo quadro em que o
## número começa a subir. Escrever o arquivo ali era um engasgo garantido
## em qualquer aparelho com memória lenta, e o TV box é exatamente isso.
func _salvar() -> void:
	SettingsStore.save_data_async({
		"mode": game_mode,
		"credits": credits,
		"plays": plays,
		"ranking": ranking,
		"ranking_schema": RankingStore.ESQUEMA,
		"sensor_escala": ESCALA_DO_SENSOR,
		"score_schema": ESQUEMA_DA_PONTUACAO,
		# Mantido para uma eventual volta a uma versão anterior do jogo.
		"best_score": _melhor(),
		"port": porta_configurada,
		"serial_last_good_port": porta_serial_conhecida,
		"serial_last_good_backend": caminho_serial_conhecido,
		"hit_min_speed": hit_min_speed,
		"hit_max_speed": hit_max_speed,
		"score_contraste": score_contraste,
		"score_ref_speed": score_ref_speed,
		"score_dead_zone": score_dead_zone,
		"sensor_eixo": sensor_eixo,
		"sensor_raio": sensor_raio,
		"sensor_vmin": sensor_vmin,
		"sensor_pulso_ms": sensor_pulso_ms,
		"auto_escala": auto_escala.para_salvar(),
		"saco_motor": saco.para_salvar(),
		"volume_musica": volume_musica,
		"volume_efeitos": volume_efeitos,
		"botao_start": botao_start,
		"botao_credito": botao_credito,
		"camera_enabled": camera_enabled,
		"camera_obrigatoria": false,
		"camera_index": camera_index,
		"teto_efeitos": teto_efeitos,
		"camera_preview_mirrored_v2": camera_mirrored,
		"statistics": statistics,
	})

# ======================================================================
# DESENHO
# ======================================================================
## Chama a cortina. `_process` cuida do resto.
func _iniciar_transicao() -> void:
	transicao = 0.0

func _draw() -> void:
	fundo.visible = true
	moldura.visible = false
	# Fora da tela de atração o letreiro não participa. Na própria abertura
	# `_nome_do_jogo` decide quando mostrar/esconder; não o limpamos todo
	# quadro porque isso anulava o cache do CanvasItem e rasterizava as
	# letras grandes de novo 60 vezes por segundo.
	if not _titulo_da_abertura_visivel():
		letreiro_do_nome.esconder()
	# TREMOR E ZOOM SACODEM A TELA INTEIRA: uma transformação só, antes de
	# tudo. O zoom cresce a partir do PONTO DO SOCO e não do centro da
	# tela — crescer pelo centro afastaria a imagem justamente do lugar
	# onde a pessoa está olhando.
	_deslocamento = Vector2.ZERO
	if tremor > 0.1:
		_deslocamento = Vector2(randf_range(-tremor, tremor), randf_range(-tremor, tremor))
	var escala := Vector2.ONE * zoom_impacto
	var origem := _deslocamento + ALVO_DO_SOCO - ALVO_DO_SOCO * zoom_impacto
	if tremor > 0.1 or zoom_impacto != 1.0:
		draw_set_transform(origem, 0.0, escala)
		fx.seguir(origem, escala)
	else:
		fx.seguir(Vector2.ZERO, Vector2.ONE)

	if state == GameDef.State.IDLE:
		if intro_active:
			ArcadeStage.intro(self, intro_time)
		else:
			_draw_show_idle()
	elif _tabela_no_ar():
		_draw_ranking_reveal()
	else:
		_draw_partida()

	fx.desenhar(self)
	_draw_pancada()
	_draw_clarao()
	_draw_alertas_graves()
	_draw_transicao()

	# A FAIXA DE AVISO SAIU DA TELA DO JOGO. Pedido explícito: um cartão
	# de "CÂMERA CONECTADA" ou "CRÉDITO ADICIONADO" surgindo por cima da
	# partida é informação de bancada, não de vitrine — quem joga não
	# precisa ler isso, e numa máquina de salão de verdade não deveria
	# ver texto de diagnóstico nenhum. `_show_notice` continua existindo
	# (a Central Técnica e o rodapé de alertas graves, logo acima, ainda
	# falam quando algo realmente importante precisa ser dito), só o
	# cartão avulso no meio da tela é que não aparece mais.

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if central_aberta:
		_draw_central()
		# O ASSISTENTE COBRE A CENTRAL. Enquanto ele está no ar, mexer nos
		# passos por baixo mudaria justamente os números que ele está
		# medindo — e o técnico veria a sugestão brigar com o que ele
		# acabou de ajustar.
		if calib_ativo:
			_draw_calibracao()

## O IMPACTO NA TELA, entregue ao diretor de efeitos.
##
## Cada nível tem o seu desenho — estrelão, rachaduras, túnel de luz,
## palco reagindo — e a receita mora em `ScoreTier`. Aqui só se decide
## QUANDO desenhar; o QUE desenhar é do diretor.
func _draw_pancada() -> void:
	if pancada_tempo < 0.0 or pancada_nivel.is_empty():
		return
	ImpactDirector.desenhar(
		self, pancada_nivel,
		clampf(pancada_tempo / ImpactDirector.PANCADA_DURACAO, 0.0, 1.0),
		_alvo(), pancada_forca
	)

## A CORTINA: uma faixa diagonal cruzando a tela, com o alvo montado nela.
##
## POR QUE DIAGONAL E POR QUE ATRAVESSANDO. Um esmaecer para o preto
## esconde a troca, mas também esconde meio segundo de máquina — e numa
## fila de fliperama meio segundo de tela preta parece travamento. Uma
## faixa que ENTRA por um lado e SAI pelo outro cobre a troca e ainda diz
## para que lado o jogo está indo.
##
## O corte é oblíquo porque o fundo do jogo já é feito de faixas
## oblíquas: a cortina passa a parecer uma peça do cenário se movendo, e
## não um retângulo estranho aparecendo por cima.
func _draw_transicao() -> void:
	if transicao < 0.0:
		return
	var t := clampf(transicao / TRANSICAO_DURACAO, 0.0, 1.0)
	var avanco := ease(t, 0.55)
	# A faixa é mais larga que a tela para cobrir o corte inteiro no meio
	# do caminho; sem isso apareceria uma fresta do jogo antigo.
	var largura := 1500.0
	var x := lerpf(-largura, TELA.x + largura, avanco)
	var inclinacao := 260.0
	var faixa := PackedVector2Array([
		Vector2(x - largura * 0.5 + inclinacao, -20.0),
		Vector2(x + largura * 0.5 + inclinacao, -20.0),
		Vector2(x + largura * 0.5 - inclinacao, TELA.y + 20.0),
		Vector2(x - largura * 0.5 - inclinacao, TELA.y + 20.0),
	])
	Traco.poligono(self, faixa, Color("b21029"))
	# Um fio de ouro na borda de ataque: é ele que dá velocidade ao gesto.
	draw_line(
		Vector2(x + largura * 0.5 + inclinacao, -20.0),
		Vector2(x + largura * 0.5 - inclinacao, TELA.y + 20.0),
		Paleta.AMBAR, 8.0, true
	)
	draw_line(
		Vector2(x - largura * 0.5 + inclinacao, -20.0),
		Vector2(x - largura * 0.5 - inclinacao, TELA.y + 20.0),
		Color(Paleta.AMBAR, 0.55), 4.0, true
	)
	# O alvo viaja montado na faixa. É a mesma marca do jogo, e é o que
	# faz a cortina pertencer a ESTA máquina e não a qualquer uma.
	var centro := Vector2(x, TELA.y * 0.5)
	if centro.x > -200.0 and centro.x < TELA.x + 200.0:
		Icones.alvo(self, centro, 108.0, Paleta.AMBAR)

## O CLARÃO DO SOCO NUM FUNDO CLARO. Lavar a tela de branco não funciona
## aqui — branco sobre quase-branco não é clarão, é nada. O golpe acende
## em ÂMBAR e escurece as bordas ao mesmo tempo: é o contraste que o olho
## lê como flash, não o brilho absoluto.
func _draw_clarao() -> void:
	if clarao <= 0.01:
		return
	draw_rect(Rect2(Vector2.ZERO, TELA), Color(Paleta.LUZ, clarao * 0.45))
	var borda := 150.0 * clarao
	var escuro := Color(Paleta.MARINHO, clarao * 0.30)
	draw_rect(Rect2(0.0, 0.0, TELA.x, borda), escuro)
	draw_rect(Rect2(0.0, TELA.y - borda, TELA.x, borda), escuro)
	draw_rect(Rect2(0.0, 0.0, borda, TELA.y), escuro)
	draw_rect(Rect2(TELA.x - borda, 0.0, borda, TELA.y), escuro)
	# Dois ecos deslocados por poucos pixels criam a separação cromática
	# curta do impacto sem exigir shader ou deixar o placar ilegível.
	if clarao > 0.18 and state == GameDef.State.MEASURING:
		var alvo := _alvo()
		var raio := 100.0 + (1.0 - clarao) * 120.0
		draw_arc(alvo + Vector2(-9.0, 0.0), raio, 0.0, TAU, Traco.segmentos(raio), Color(Paleta.CIANO, clarao * 0.65), 7.0, true)
		draw_arc(alvo + Vector2(9.0, 0.0), raio, 0.0, TAU, Traco.segmentos(raio), Color(Paleta.VERMELHO, clarao * 0.60), 7.0, true)

# ---------------------------------------------------------------- abertura
## A ABERTURA NÃO É UMA TELA SÓ.
##
## Uma máquina de fliperama parada não fica repetindo o mesmo cartaz: ela
## conta o jogo em capítulos, e é o rodízio que segura quem está passando
## no corredor por tempo suficiente para a pessoa decidir jogar. Três
## páginas alternando sozinhas — a marca, os melhores da casa e como
## jogar — e, fixos em todas, o convite e os números da máquina, porque
## esses dois não podem depender de a pessoa ter chegado na página certa.
const ABERTURA_PAGINAS := 4
const ABERTURA_SEGUNDOS := 7.0

## Página 2 — as cinco melhores marcas.
func _pagina_recordes(alpha: float) -> void:
	_texto_arcade("TOP 20 • MELHORES", 392.0, 62, Color(Paleta.CIANO, alpha), LARGURA_UTIL)
	if ranking.is_empty():
		_texto("AINDA NINGUÉM SOCOU ESTA MÁQUINA", 780.0, 32, Color(Paleta.TINTA_FRACA, alpha))
		_texto("O PRIMEIRO NOME DA LISTA PODE SER O SEU", 832.0, 24, Color(Paleta.TINTA_LEVE, alpha))
		return
	var page := int(state_time / 16.0) % 4
	for row in range(5):
		var i := page * 5 + row
		var y := 466.0 + row * 116.0
		var cor := _cor_da_posicao(i + 1)
		var linha := Rect2(MARGEM + 40.0, y, LARGURA_UTIL - 80.0, 98.0)
		var vazia := i >= ranking.size()
		_cartao(linha, Paleta.CARTAO if not vazia else Paleta.VAZIO, Paleta.CARTAO_BORDA, alpha, 2.0)
		# Tarja lateral colorida: identifica a posição sem pintar a linha.
		draw_rect(Rect2(linha.position, Vector2(9.0, linha.size.y)), Color(cor, alpha))
		var meio := linha.position.y + 64.0
		_texto("%dº" % (i + 1), meio, 34, Color(cor, alpha), HORIZONTAL_ALIGNMENT_CENTER, linha.position.x + 30.0, 90.0)
		if i < 3:
			Icones.trofeu(self, Vector2(linha.position.x + 168.0, meio - 11.0), 19.0, Color(cor, alpha))
		if vazia:
			_texto("—", meio, 34, Color(Paleta.TINTA_LEVE, alpha), HORIZONTAL_ALIGNMENT_RIGHT, linha.position.x, linha.size.x - 40.0)
		else:
			_draw_player_photo(Rect2(linha.position + Vector2(210.0, 11.0), Vector2(76.0, 76.0)), str(ranking[i].get("photo_path", "")), alpha)
			_texto("%04d" % RankingStore.score_at(ranking, i), meio, 44, Color(Paleta.TINTA, alpha), HORIZONTAL_ALIGNMENT_RIGHT, linha.position.x, linha.size.x - 40.0)
			_texto("PONTOS", meio, 18, Color(Paleta.TINTA_LEVE, alpha), HORIZONTAL_ALIGNMENT_RIGHT, linha.position.x, linha.size.x - 190.0)
	_texto("POSIÇÕES %02d–%02d" % [page * 5 + 1, page * 5 + 5], 1152.0, 26, Color(Paleta.CIANO, alpha))

## Página 3 — os três passos, do tamanho de quem lê de longe.
func _pagina_como_jogar(alpha: float) -> void:
	_texto_arcade("COMO JOGAR", 392.0, 62, Color(Paleta.CIANO, alpha), LARGURA_UTIL)
	var passos := [
		["ficha", "INSIRA A FICHA" if game_mode == "credit" else "MÁQUINA LIBERADA", Paleta.ROSA],
		["botao", "APERTE START", Paleta.VERDE],
		["alvo", "SOQUE O ALVO COM FORÇA", Paleta.VERMELHO],
	]
	for i in range(passos.size()):
		var y := 428.0 + i * 236.0
		var cor: Color = passos[i][2]
		var centro := Vector2(MARGEM + 110.0, y + 60.0)
		draw_circle(centro, 62.0, Paleta.tinta_clara(cor, 0.20), true, -1.0, true)
		draw_arc(centro, 62.0, 0.0, TAU, Traco.segmentos(62.0), Color(cor, 0.55 * alpha), 4.0, true)
		_icone(str(passos[i][0]), centro, 38.0, Color(Paleta.para_texto(cor), alpha))
		_texto(
			"%d." % (i + 1), centro.y - 4.0, 26, Color(cor, alpha),
			HORIZONTAL_ALIGNMENT_LEFT, MARGEM + 210.0, 80.0
		)
		# Alinhados à ESQUERDA e não centrados: três frases de comprimentos
		# diferentes, centradas cada uma na sua caixa, não formam uma
		# coluna — e é a coluna que faz a lista ser lida como três passos.
		var texto := str(passos[i][1])
		_texto(
			texto, centro.y + 14.0, _tamanho_que_cabe(texto, 44, LARGURA_UTIL - 340.0),
			Color(Paleta.TINTA, alpha), HORIZONTAL_ALIGNMENT_LEFT,
			MARGEM + 270.0, LARGURA_UTIL - 340.0
		)

# ---------------------------------------------------------------- partida
## Todos os momentos da partida compartilham o mesmo visor. O que muda é
## o que está escrito nele, a cor do anel e quanto do anel está aceso.
func _draw_partida() -> void:
	# O cabeçalho da rodada é o MESMO letreiro do cabeçalho da abertura,
	# no mesmo corpo: são a mesma máquina, e a pessoa não deve sentir que
	# trocou de programa ao apertar START.
	_letreiro_centrado("PUNCH CHALLENGE", 145.0, 32, Paleta.CREME)
	# A marca acompanha a rodada inteira, à direita e discreta — menos na
	# contagem, onde ela é desenhada ao lado do visor da foto.
	if state != GameDef.State.COUNTDOWN:
		# A marca desceu 60 px em relação à versão original: os cartões dos
		# socos e a colocação no ranking passaram a terminar mais embaixo
		# depois que a arena tomou o meio da tela.
		_marca_lateral(1828.0, 0.70, 66.0)
	match state:
		GameDef.State.COUNTDOWN:
			_texto_arcade("FAÇA SUA POSE", 340.0, 72, Paleta.CIANO, LARGURA_UTIL)
			var rect := Rect2(180, 470, 720, 720)
			_cartao(Rect2(170, 460, 740, 740), Color("330c16"), Paleta.CIANO, 1.0, 4.0)
			# A MARCA DA CASA LOGO ABAIXO DO VISOR, à direita e grande o
			# bastante para se ler de pé na frente da máquina. Fora da
			# foto: dentro dela o carimbo some na miniatura do ranking e
			# atrapalha no retrato grande.
			_marca_lateral(1218.0)
			if pose_finished:
				# SEM FOTO, A CÂMERA CONTINUA À VISTA. Cair no boneco
				# desenhado com a webcam acesa na frente da pessoa é o
				# que dá a impressão de a câmera ter desligado justamente
				# na hora de fotografar.
				if result_photo_path.is_empty() and camera_service != null and camera_service.tem_imagem():
					_draw_texture_cover(camera_service.preview_texture(), rect, 1.0, camera_mirrored)
					draw_rect(rect, Color(Paleta.CIANO, 1.0), false, 3.0)
				else:
					_draw_player_photo(rect, result_photo_path, 1.0)
			elif camera_service != null and camera_service.tem_imagem():
				# `tem_imagem`, e não `available`: a segunda pergunta se a
				# imagem é DESTE instante, e um atraso de meio segundo na
				# ponte fazia a prévia voltar a ser o boneco com a webcam
				# acesa na frente da pessoa.
				_draw_texture_cover(camera_service.preview_texture(), rect, 1.0, camera_mirrored)
			else:
				_draw_avatar(rect, 1.0)
				# A CÂMERA PODE ESTAR SÓ ABRINDO. O boneco desenhado
				# sozinho diz "não há câmera"; com o anel girando por
				# cima ele diz "espera, estou chegando", que é a verdade
				# nos primeiros segundos de qualquer rodada.
				if camera_enabled:
					_carregando(rect.get_center() + Vector2(0.0, 210.0), 30.0, Paleta.CIANO)
			if aguardando_camera:
				# Enquanto a câmera sobe, a tela diz o que está esperando
				# — e o anel girando prova que a máquina não travou.
				_carregando(Vector2(540.0, 1400.0), 40.0, Paleta.CIANO)
				_rotulo(
					camera_service.estado_curto() if camera_service != null else "LIGANDO A CÂMERA…",
					1490.0, Paleta.CIANO
				)
			elif not pose_finished:
				_texto_arcade(str(clampi(int(ceil(countdown_left)), 1, 3)), 1400.0, 150, Color.WHITE, LARGURA_UTIL)
				_rotulo("OLHE PARA A CÂMERA", 1490.0, Paleta.AMBAR)
			else:
				# O MOTIVO DE VERDADE, e não "SEM CÂMERA" para tudo. A
				# mesma frase servia para câmera desligada na Central,
				# privacidade bloqueada, webcam ocupada e dispositivo ausente —
				# e quem estava na frente da máquina não tinha como saber
				# qual das quatro era.
				var recado := "FOTO PRONTA"
				var cor_recado := Paleta.AMBAR
				if result_photo_path.is_empty():
					recado = camera_service.motivo_curto() if camera_service != null else "SEM CÂMERA"
					cor_recado = Paleta.VERMELHO
				_rotulo(recado, 1390.0, cor_recado)
				_texto_arcade("PREPARE O SOCO", 1480.0, 56, Color.WHITE, LARGURA_UTIL)
		GameDef.State.ARMED:
			_draw_espera_do_soco()
		GameDef.State.MEASURING, GameDef.State.RESULT:
			_draw_score_hero()

## O QUADRO NA PAREDE: a arena 3D, a moldura e as barras de dano.
##
## Tudo o que vem do mundo 3D entra na tela por AQUI, numa chamada só, e
## é de propósito: se a imagem da arena pudesse ser desenhada de três
## lugares diferentes, um deles acabaria desenhando sem a moldura ou com
## as barras trocadas. Um caminho só, usado pelas duas telas do soco.
var _vida_fantasma := 1.0

func _draw_arena() -> void:
	ArenaQuadro.fundo(self)
	if arena != null and arena.ativa():
		ArenaQuadro.imagem(self, arena.get_texture())
	# A MOLDURA ACENDE COM O GOLPE. `clarao` já é o clarão do impacto
	# caindo de 1 a 0 — reaproveitá-lo faz a moldura piscar exatamente no
	# compasso do resto da tela, em vez de ter um relógio só dela que
	# poderia sair de sincronia.
	ArenaQuadro.moldura(self, ScoreTier.cor_de(result_score), clarao)
	var dano := arena.dano() if arena != null else 0.0
	# A VIDA NO LUGAR DAS COLUNAS. A barra real cai na hora; o rastro
	# branco desce devagar atrás dela, mostrando o tamanho do estrago.
	var vida_real := 1.0 - clampf(dano, 0.0, 1.0)
	if vida_real > _vida_fantasma:
		_vida_fantasma = vida_real
	_vida_fantasma = move_toward(_vida_fantasma, vida_real, get_process_delta_time() * 0.45)
	# A PLAQUETA DE CIMA DIZ O QUE AS BARRAS MEDEM. Duas colunas
	# coloridas sem legenda são bonitas e mudas: quem está na frente da
	# máquina não tem como saber se aquilo é tempo, força ou vida.
	# NA LONA, A PERCENTAGEM NÃO É MAIS A NOTÍCIA. Um nível alto derruba
	# por si, sem encher o medidor — e ler "CAMBALEANDO 61%" ao lado de um
	# corpo deitado no chão é a plaqueta discordando da imagem.
	var estado := ArenaFrases.de_dano(dano)
	if arena != null and arena.na_lona():
		estado = "NA LONA"
	ArenaQuadro.vida(self, fonte, vida_real, _vida_fantasma, animation_time, "ADVERSÁRIO  •  %s" % estado)

## A TELA QUE ESPERA O SOCO.
##
## Não há saco desenhado, não há barra de tempo e — desde a escala de
## quatro dígitos — não há mais CÍRCULO DE PLACAR aqui. O círculo é o
## objeto que revela a nota; mostrá-lo antes do golpe, mesmo vazio,
## promete um número que ainda não existe e ensina a pessoa a olhar para
## o lugar errado justamente quando ela deveria estar olhando para o saco
## de verdade.
##
## O que fica é um ALVO: anéis concêntricos respirando no ponto onde o
## soco aterrissa, com o farol mandando anéis para fora. Chamada, e não
## instrumento.
func _draw_espera_do_soco() -> void:
	_draw_farol(Paleta.AMBAR)
	_draw_arena()
	# O ROUND, na barra de baixo da moldura. É a única informação que
	# cabe ali e a única que a pessoa quer no instante anterior ao soco.
	_letreiro_centrado(
		"ROUND %d DE %d" % [socos.size() + 1, SOCOS_POR_RODADA],
		ArenaQuadro.MOLDURA.end.y - 14.0, _corpo(24), Paleta.TINTA_FRACA, fonte_texto
	)
	var piscada := 0.78 + 0.22 * sin(animation_time * 4.4)
	var chamada := "SOQUE AGORA!" if socos.is_empty() else "AGORA O SEGUNDO!"
	_texto_arcade(chamada, 1412.0, 88, Color(Color.WHITE, piscada), LARGURA_UTIL)
	_rotulo("ACERTE O ALVO COM TODA A FORÇA", 1470.0, Color.WHITE)
	# A PROVOCAÇÃO DA ARENA. Ela não repete a instrução de cima: a
	# instrução diz o que fazer, esta diz por que vale a pena. É a voz do
	# jogo, e é o que um cartaz de console antigo teria aqui.
	_texto_cabendo(
		ArenaFrases.de_espera(socos.size() + int(plays)), 1528.0, 40,
		Paleta.AMBAR, LARGURA_UTIL
	)
	_rotulo("RECORDE DA CASA  %04d" % _melhor(), 1580.0, Paleta.TINTA_FRACA)
	# Os dois socos ficam à vista DURANTE a espera: é enquanto se prepara
	# para bater que saber o que o primeiro valeu muda alguma coisa.
	_draw_cartoes_dos_socos(1612.0, false)

	# O RELÓGIO SÓ APARECE NO FIM, e vem acompanhado da promessa.
	#
	# Nos primeiros setenta e cinco segundos não há relógio nenhum: a
	# máquina espera calada, que é o que se pediu. Só quando ela vai mesmo
	# desistir é que avisa — e avisa dizendo que a ficha volta, senão o
	# aviso vira ameaça.
	if espera_left <= GameDef.AVISO_DE_VOLTA:
		var segundos := maxi(0, int(ceil(espera_left)))
		_apoio("VOLTANDO EM %02d  •  O CRÉDITO É DEVOLVIDO" % segundos, 1800.0, Color.WHITE)

## O FAROL E O ALVO: anéis saindo do ponto do soco, em batidas.
##
## Três anéis defasados, sempre no mesmo compasso, e o alvo respirando no
## meio. Tudo se move para FORA — na direção de quem está olhando,
## chamando o punho. Anéis entrando leriam como contagem regressiva, que
## é exatamente o que esta tela deixou de ter.
func _draw_farol(cor: Color) -> void:
	var centro := ALVO_DO_SOCO
	var compasso := 1.15
	# OS ANÉIS SAEM DE TRÁS DO QUADRO.
	#
	# Na versão original eles nasciam pequenos, no meio do alvo desenhado.
	# Aqui o meio é ocupado pela arena, e um anel cruzando a imagem do
	# lutador leria como falha de desenho. Começando FORA da moldura eles
	# viram o que sempre quiseram ser: luz escapando por trás do quadro.
	for i in range(3):
		var fase := fmod(animation_time / compasso + float(i) / 3.0, 1.0)
		var raio := lerpf(470.0, 760.0, ease(fase, 0.45))
		Traco.arco(self, centro, raio, Color(cor, (1.0 - fase) * 0.50), 10.0)
	# OS CANTOS DE MIRA AGORA ABRAÇAM A MOLDURA. Dizem "é AQUI que o soco
	# acerta" apontando para a arena, e não para um ponto no vazio — e
	# respiram, para não virarem um enfeite parado.
	var respiro := 0.5 + 0.5 * sin(animation_time * 2.2)
	var folga := lerpf(16.0, 30.0, respiro)
	var m := ArenaQuadro.MOLDURA.grow(folga)
	for sx in [0.0, 1.0]:
		for sy in [0.0, 1.0]:
			var canto := Vector2(lerpf(m.position.x, m.end.x, sx), lerpf(m.position.y, m.end.y, sy))
			var dx := 72.0 * (1.0 if sx < 0.5 else -1.0)
			# O BRAÇO DE BAIXO É MAIS CURTO. Com 78 px ele descia até a
			# linha do "SOQUE AGORA!" e cortava a primeira letra — e um
			# enfeite que atravessa a chamada principal é um enfeite que
			# está atrapalhando o trabalho da tela.
			var dy := (72.0 if sy < 0.5 else -44.0)
			draw_line(canto, canto + Vector2(dx, 0.0), Color(cor, 0.85), 9.0, true)
			draw_line(canto, canto + Vector2(0.0, dy), Color(cor, 0.85), 9.0, true)

## A ABERTURA GIRA EM TRÊS CAPÍTULOS.
##
## Uma máquina de fliperama parada não fica repetindo o mesmo cartaz: ela
## conta o jogo em partes, e é o rodízio que segura quem passa no
## corredor por tempo suficiente para decidir jogar. A marca, os melhores
## da casa e como jogar — e, FIXOS nos três, o convite e os créditos,
## porque um botão que muda de lugar a cada oito segundos é um botão que
## ninguém acha.
const ABERTURA_CAPITULOS := 3
const ABERTURA_DURACAO := 8.0

## O LAÇO DE ATRAÇÃO: a apresentação volta sozinha.
##
## Uma máquina de salão passa a maior parte da noite sem ninguém na
## frente, e o que ela mostra nessas horas é o que trás gente. O rodízio
## de capítulos (marca, recordes, como jogar) prende quem já parou; quem
## está passando a dez metros só olha se alguma coisa MEXER — e a cut
## scene do soco é o que a máquina tem de mais chamativo.
##
## Um minuto e vinte é o intervalo: curto o bastante para pegar quem
## passa duas vezes pelo corredor, longo o bastante para os três
## capítulos rodarem inteiros antes de a entrada recomeçar.
const ATRACAO_INTERVALO := 80.0

func _laco_de_atracao(delta: float) -> void:
	# Só na tela de espera, e nunca com a Central aberta: reiniciar a
	# entrada por baixo do técnico que está configurando é o tipo de
	# surpresa que faz ele perder o que estava fazendo.
	if state != GameDef.State.IDLE or intro_active or central_aberta or calib_ativo:
		atracao_relogio = 0.0
		return
	atracao_relogio += delta
	if atracao_relogio < ATRACAO_INTERVALO:
		return
	atracao_relogio = 0.0
	# A ENTRADA DE NOVO, do primeiro quadro: o selo da casa, os facões de
	# luz, o soco chegando de lado e a montagem do letreiro.
	intro_active = true
	intro_time = 0.0
	abertura_chegada = 1.0
	fx.limpar()
	sons.music(-18.0)

func _titulo_da_abertura_visivel() -> bool:
	return state == GameDef.State.IDLE and not intro_active \
		and int(state_time / ABERTURA_DURACAO) % ABERTURA_CAPITULOS == 0 \
		and not central_aberta and not calib_ativo and transicao < 0.0

func _draw_show_idle() -> void:
	var chegada := ease(abertura_chegada, 0.4)
	_marca_da_casa(146.0, 132.0, chegada)
	var capitulo := int(state_time / ABERTURA_DURACAO) % ABERTURA_CAPITULOS
	# Cada capítulo entra com o seu próprio esmaecer; sem isso só o
	# primeiro teria entrada e os outros dariam um salto seco.
	var entrada := ease(clampf(fmod(state_time, ABERTURA_DURACAO) / 0.5, 0.0, 1.0), 0.35)
	match capitulo:
		1:
			_pagina_recordes(entrada)
		2:
			_pagina_como_jogar(entrada)
		_:
			_capitulo_da_marca(entrada)
	_pontos_do_capitulo(capitulo, chegada)
	var pulse := 0.8 + 0.2 * sin(animation_time * 2.6)
	# A MÁQUINA NÃO CONVIDA PARA O QUE ELA NÃO PODE FAZER.
	#
	# Enquanto a câmera não está entregando imagem, "PRESSIONE START" é
	# uma promessa que a máquina vai negar no toque seguinte — e quem
	# está na frente dela conclui que o botão quebrou. O convite só
	# aparece quando a rodada pode mesmo começar; até lá, o mesmo cartão
	# diz o que está faltando, com o anel girando para provar que a
	# máquina está trabalhando nisso e não travada.
	var liberado := rodada_liberada()
	_cartao(
		Rect2(140, 1560, 800, 112), Color("d9122d") if liberado else Color("3a1b06"),
		Color(Paleta.AMBAR if liberado else Paleta.CIANO, pulse), chegada, 3.0
	)
	if liberado:
		_texto("PRESSIONE START", 1635.0, 46, Color(Color.WHITE, chegada))
	else:
		_texto("PREPARANDO O JOGO", 1608.0, 34, Color(Paleta.CIANO, chegada))
		_texto(motivo_da_recusa(), 1652.0, 18, Color(Color.WHITE, 0.85 * chegada))
		_carregando(Vector2(880.0, 1616.0), 22.0, Paleta.CIANO)
	# O LUGAR DO CRÉDITO PISCA quando alguém aperta START sem saldo.
	var cor_credito := Color(Paleta.CIANO, chegada)
	if aviso_de_credito >= 0.0:
		var bate := 0.5 + 0.5 * sin(aviso_de_credito * 16.0)
		cor_credito = Color(Paleta.VERMELHO.lerp(Paleta.AMBAR, bate), chegada)
		_cartao(
			Rect2(300, 1700, 480, 62), Color(Paleta.VERMELHO, 0.20 * bate),
			Color(Paleta.AMBAR, bate), chegada, 3.0
		)
	_draw_placa_de_creditos(cor_credito, chegada)

## A PLACA DE CRÉDITOS. Era uma linha amarela miúda solta sobre a faixa
## vermelha do rodapé — cor quente em cima de cor quente, e pequena: de
## longe virava um borrão. Agora é uma placa escura com a ficha desenhada,
## o rótulo em branco e o número grande na letra do placar.
func _draw_placa_de_creditos(cor: Color, alpha: float) -> void:
	var caixa := Rect2(330.0, 1690.0, 420.0, 76.0)
	_cartao(caixa, Color("12040a", 0.92), Color(cor, 0.9), alpha, 3.0)
	var meio_y := caixa.position.y + caixa.size.y * 0.5
	if game_mode == "free":
		_letreiro_centrado("JOGO LIVRE", meio_y + 15.0, 40, Color(cor, alpha))
		return
	Icones.ficha(self, Vector2(caixa.position.x + 44.0, meio_y), 24.0, Color(Paleta.AMBAR, alpha))
	draw_string(
		fonte_texto, Vector2(caixa.position.x + 84.0, meio_y + 13.0), "CRÉDITOS",
		HORIZONTAL_ALIGNMENT_LEFT, 200.0, _corpo(36), Color(Color.WHITE, alpha)
	)
	var numero := "%02d" % credits
	draw_string_outline(
		fonte, Vector2(caixa.position.x, meio_y + 20.0), numero,
		HORIZONTAL_ALIGNMENT_RIGHT, caixa.size.x - 26.0, 52, 8, Color(Paleta.CONTORNO, alpha)
	)
	draw_string(
		fonte, Vector2(caixa.position.x, meio_y + 20.0), numero,
		HORIZONTAL_ALIGNMENT_RIGHT, caixa.size.x - 26.0, 52, Color(cor, alpha)
	)

func _capitulo_da_marca(alpha: float) -> void:
	var flutuar := smoothstep(0.5, 1.3, state_time)
	ArcadeStage.emblem(self, Vector2(540, 560 + sin(animation_time * 1.4) * 8 * flutuar), 440.0, alpha)
	# O NOME É DESENHADO PELO NÓ DO SHADER, e não aqui. Ele continua no
	# mesmo lugar, no mesmo corpo e com a mesma entrada esmaecida — o que
	# muda é quem passa a tinta, porque só um nó pode carregar material.
	_nome_do_jogo(alpha)
	_texto("QUAL É A SUA FORÇA?", 1120.0, 32, Color(Color.WHITE, alpha))
	_texto("RECORDE DA CASA", 1270.0, 24, Color(Color("d8b6a6"), alpha))
	_texto("%04d" % _melhor(), 1400.0, 98, Color(Paleta.AMBAR, alpha))

## ENTREGA O NOME AO NÓ QUE TEM O SHADER.
##
## O reflexo que corre dentro das letras precisa de um material, material
## é propriedade do nó, e o resto da tela é desenhado à mão num Control
## só — pôr o shader ali aplicaria o brilho ao fundo, aos cartões e ao
## placar. Então o nome mora num nó próprio, e esta função é a ponte:
## a tela continua mandando quando, onde e com que opacidade.
func _nome_do_jogo(alpha: float) -> void:
	# O NÓ FICA ACIMA DO DESENHO PRINCIPAL — é o que faz o reflexo passar
	# por cima do letreiro em vez de ficar embaixo do fundo. O preço é
	# que a Central, a calibração e a cortina de transição, desenhadas
	# pelo nó de baixo, NÃO cobrem o nome: sem esta guarda, o
	# "PUNCH CHALLENGE" aparecia atravessado no meio da Central Técnica.
	if alpha <= 0.01 or central_aberta or calib_ativo or transicao >= 0.0:
		letreiro_do_nome.esconder()
		return
	letreiro_do_nome.mostrar(
		[
			{"texto": "PUNCH", "x": 540.0, "y": 910.0, "tamanho": 144, "cor": Color(Color.WHITE, alpha)},
			{"texto": "CHALLENGE", "x": 540.0, "y": 1010.0, "tamanho": 80, "cor": Color(Paleta.AMBAR, alpha)},
		],
		# A faixa atravessa a LARGURA DO NOME, e não a da tela: medida na
		# tela, o reflexo levaria o mesmo tempo cruzando as letras e o
		# vazio dos dois lados, e a passagem pareceria travar no meio.
		190.0, 700.0
	)

## Quantos capítulos existem e em qual estamos. Sem isso o rodízio parece
## a tela trocando sozinha por defeito.
func _pontos_do_capitulo(capitulo: int, alpha := 1.0) -> void:
	var largura := float(ABERTURA_CAPITULOS) * 30.0
	for i in range(ABERTURA_CAPITULOS):
		var atual := i == capitulo
		var centro := Vector2(540.0 - largura * 0.5 + 15.0 + i * 30.0, 1500.0)
		var cor: Color = Paleta.AMBAR if atual else Color("6d2835")
		draw_circle(centro, 8.0 if atual else 5.0, Color(cor, alpha), true, -1.0, true)

## A PLAQUETA DO PLACAR, montada a cavaleiro na borda de baixo da moldura.
const PLACA_DO_PLACAR := Rect2(268.0, 1232.0, 544.0, 186.0)
const PLACAR_NA_ARENA := 128

func _draw_score_hero() -> void:
	var measuring := state == GameDef.State.MEASURING
	# O ANEL MEDE A FORÇA, NÃO O RELÓGIO — e nesta versão ele deixou de
	# ser anel.
	#
	# O medalhão redondo de 326 px de raio ocupava exatamente o lugar que
	# a arena ocupa agora, e as duas coisas não cabem: ou se vê o número
	# ou se vê quem levou o soco. A leitura da força não se perdeu, ela
	# MUDOU DE OBJETO — quem conta agora são as barras de dano na lateral
	# (quanto o adversário aguentou) e o trilho dentro da plaqueta (quanto
	# este soco valeu na escala). Dois instrumentos honestos no lugar de
	# um redondo que disputava espaço com a cena.
	var progresso_contagem := clampf(result_time / GameDef.CONTAGEM_DURACAO, 0.0, 1.0)
	var progresso := 0.0 if measuring else clampf(displayed_score / float(GameDef.SCORE_MAX), 0.0, 1.0)
	var cor_final: Color = GameDef.classificar(result_score)["cor_faixa"] as Color
	# A cor também chega, em vez de saltar no último quadro: ciano de
	# leitura durante a análise, cor da faixa conforme o valor assenta.
	var cor := Paleta.CIANO.lerp(cor_final, progresso_contagem * 0.82)
	if verdict_time >= 0.0:
		cor = cor_final
	_draw_campo_de_forca(ALVO_DO_SOCO, cor, progresso, measuring)
	_draw_arena()

	# A plaqueta: metade sobre a moldura, metade fora. É o que a faz
	# parecer pregada no quadro em vez de flutuando embaixo dele.
	_cartao(PLACA_DO_PLACAR, Color("1d0810"), cor, 1.0, 4.0)
	_placar(
		"– – – –" if measuring else "%04d" % int(round(displayed_score)),
		Vector2(540.0, 1296.0), cor if measuring else Color.WHITE, PLACAR_NA_ARENA
	)
	_draw_barra_de_pontuacao(progresso, progresso_contagem, cor, measuring)

	if verdict_time >= 0.0:
		# O NOME DO NÍVEL VEM ANTES DA COLOCAÇÃO. A pessoa quer saber o
		# que ela fez — "NOCAUTE" — e só depois onde isso a coloca. A
		# ordem inversa transformava o veredito numa tabela.
		_texto_arcade(ScoreTier.nome_de(result_score), 1490.0, 78, cor, LARGURA_UTIL)
		# E A FRASE VEM DEPOIS DO NOME. O nome é a nota; a frase é o
		# locutor. Sem ela o veredito volta a ser uma etiqueta — com ela
		# a máquina parece ter visto o soco acontecer.
		if not arena_frase.is_empty():
			_texto_cabendo(arena_frase, 1556.0, 44, Paleta.AMBAR, LARGURA_UTIL)
		# OS DOIS SOCOS CONTINUAM À VISTA NO RESULTADO, com o que deu a
		# nota marcado. MELHOR só existe quando há com quem comparar: no
		# resultado do primeiro soco ele é o melhor porque é o único.
		_draw_cartoes_dos_socos(1600.0, socos.size() >= SOCOS_POR_RODADA)
		if posicao_no_ranking > 0:
			_apoio("%dº LUGAR NO TOP 20" % posicao_no_ranking, 1800.0, Paleta.AMBAR)

## Barra segmentada de leitura instantânea. Segmentos são mais fáceis de
## comparar à distância que um retângulo contínuo e não criam partículas,
## shaders ou nós novos por quadro.
func _draw_barra_de_pontuacao(valor: float, contagem: float, cor: Color, medindo: bool) -> void:
	var trilho := Rect2(304.0, 1352.0, 472.0, 26.0)
	_cartao(trilho.grow(6.0), Color("15070d"), Color(cor, 0.34), 1.0, 2.0)
	var segmentos := 24
	var vao := 3.0
	var largura := (trilho.size.x - vao * float(segmentos - 1)) / float(segmentos)
	for i in range(segmentos):
		var caixa := Rect2(trilho.position.x + float(i) * (largura + vao), trilho.position.y, largura, trilho.size.y)
		var aceso := float(i + 1) / float(segmentos) <= valor
		var tinta := Color("35131d")
		if medindo:
			var scanner := int(animation_time * 22.0) % segmentos
			var distancia := posmod(i - scanner, segmentos)
			if distancia <= 4:
				tinta = Color(Paleta.CIANO, 0.30 + (4.0 - float(distancia)) * 0.14)
		elif aceso:
			tinta = cor
		draw_rect(caixa, tinta)
	# Um cursor branco curto dá precisão ao ponto que ainda está subindo.
	if not medindo and valor > 0.0 and valor < 1.0:
		var cursor_x := trilho.position.x + trilho.size.x * valor
		draw_rect(Rect2(cursor_x - 2.0, trilho.position.y - 4.0, 4.0, trilho.size.y + 8.0), Color.WHITE)
	var rotulo := "LENDO SENSOR" if medindo else ("PONTOS CONFIRMADOS" if verdict_time >= 0.0 else "ANALISANDO • %02d%%" % int(contagem * 100.0))
	_apoio(rotulo, 1412.0, cor)

## O CARREGANDO: UM ANEL QUE GIRA E UMA FRASE DO QUE ESTÁ ACONTECENDO.
##
## Toda espera desta máquina era silenciosa. O diagnóstico da câmera podia
## consultar o Windows e a tela ficava idêntica à de antes de apertar; a
## câmera podia estar subindo enquanto a tela da pose já mostrava o boneco
## desenhado, como se não houvesse câmera nenhuma.
## Espera sem sinal é indistinguível de defeito — e quem está na frente
## do gabinete conclui, sempre, que apertou e não aconteceu nada.
##
## O anel não é enfeite: ele GIRA, e é o giro que prova que o programa
## está vivo. Uma barra parada em 40% diria menos do que este anel.
func _carregando(centro: Vector2, raio: float, cor: Color, texto := "") -> void:
	Traco.arco(self, centro, raio, Color(cor, 0.16), 5.0)
	var comeco := animation_time * 3.4
	Traco.setor(self, centro, raio, comeco, comeco + 1.5, cor, 5.0)
	# Um segundo arco, mais lento e no sentido contrário: com um só, em
	# giro constante, o olho perde a referência e o anel parece parado.
	Traco.setor(self, centro, raio * 0.62, -comeco * 0.7, -comeco * 0.7 + 0.9, Color(cor, 0.55), 4.0)
	if not texto.is_empty():
		_texto(texto, centro.y + raio + 40.0, 18, cor, HORIZONTAL_ALIGNMENT_CENTER, centro.x - 300.0, 600.0)

## O PLACAR: QUATRO ALGARISMOS, E NADA DISPUTANDO COM ELES.
##
## Aqui havia um visor de sete segmentos desenhado traço a traço. A ideia
## era boa no papel — num fliperama o placar é um painel de LED atrás de
## um vidro, e o que denuncia isso é o segmento APAGADO atrás do número.
## Na tela ela não fecha: sete traços com catorze junções em bisel, mais
## os apagados por baixo, produzem uma grade, e a três metros a grade
## ganha do algarismo. Foram três desenhos diferentes e os três leram
## como grade.
##
## Então o placar é tipográfico, na letra do cartaz — a mesma do
## logotipo, a mesma do PUNCH CHALLENGE. Um número é uma forma que a
## pessoa reconhece antes de ler, e é isso que um placar precisa ser.
## O tratamento é o de fliperama, em quatro passadas:
##
##   1. um halo largo na cor da faixa, que é o vidro espalhando a luz;
##   2. um contorno grosso quase preto, que segura o número sobre o anel
##      aceso e sobre o clarão do soco;
##   3. uma cópia clara alguns pixels acima, que vira o brilho do topo;
##   4. o número.
##
## `tabular` importa: sem ele, cada algarismo tem a sua largura e o
## placar DANÇA de lado enquanto sobe de 0000 a 9999.
const PLACAR_CORPO := 190

## OS DOIS SOCOS, LADO A LADO E CADA UM COM O SEU NÚMERO.
##
## Este é o pedido "dois socos apresentados individualmente", e ele é uma
## exigência de JOGO antes de ser de tela: entre o primeiro e o segundo
## golpe a pessoa precisa saber o que já fez para decidir como bater de
## novo. Um total sozinho não diz isso — some com a informação que a
## segunda tentativa existe para usar.
##
## Três estados por cartão, e os três se leem de longe:
##   • VAZIO   — ainda não aconteceu: contorno apagado e travessão.
##   • À ESPERA— é este que a máquina está esperando agora: borda âmbar
##               pulsando, no mesmo compasso do "SOQUE AGORA!".
##   • FEITO   — pontos em quatro dígitos e a velocidade crua embaixo.
##
## No resultado, o cartão que deu a nota da rodada ganha a cor do nível e
## a palavra MELHOR. É o que explica, sem texto de ajuda, por que a nota
## final é aquela.
func _draw_cartoes_dos_socos(y: float, marcar_melhor: bool) -> void:
	const ALTURA := 140.0
	const VAO := 24.0
	var largura := (LARGURA_UTIL - VAO) * 0.5
	# Qual soco vale a nota da rodada: o primeiro dos empatados, para a
	# marca não pular de um cartão para o outro entre dois quadros.
	var melhor_i := -1
	var melhor_p := -1
	for i in socos.size():
		if int(socos[i]["pontos"]) > melhor_p:
			melhor_p = int(socos[i]["pontos"])
			melhor_i = i

	for i in SOCOS_POR_RODADA:
		var rect := Rect2(MARGEM + float(i) * (largura + VAO), y, largura, ALTURA)
		var feito := i < socos.size()
		var esperando := (not feito) and i == socos.size() and state == GameDef.State.ARMED
		var eh_melhor := marcar_melhor and feito and i == melhor_i

		var cor := Paleta.TINTA_LEVE
		if eh_melhor:
			cor = GameDef.classificar(int(socos[i]["pontos"]))["cor_faixa"]
		elif feito:
			cor = Paleta.TINTA_FRACA
		elif esperando:
			cor = Paleta.AMBAR

		# O cartão do soco recém-chegado nasce maior e volta ao tamanho.
		var crescer := 0.0
		if feito and i == socos.size() - 1:
			var idade := animation_time - ultimo_soco_em
			if idade >= 0.0 and idade < 0.5:
				crescer = (1.0 - idade / 0.5) * 10.0
		var caixa := rect.grow(crescer)

		var pulso := 1.0
		if esperando:
			pulso = 0.62 + 0.38 * sin(animation_time * 4.4)

		_cartao(
			caixa,
			Paleta.CARTAO if feito or esperando else Paleta.VAZIO,
			Color(cor, pulso),
			1.0,
			3.0 if (esperando or eh_melhor) else 2.0
		)
		# TUDO AQUI DENTRO SE CENTRA NO CARTÃO, E NÃO NA TELA.
		#
		# `_letreiro_centrado` centra na LARGURA INTEIRA do visor — foi o
		# que colocou "SOCO 2" e "2.1 m/s" no meio da tela, por cima do
		# cartão da esquerda, em vez de dentro do seu. Para caixa, o
		# ajudante certo é `_texto_cabendo`, que recebe x e largura.
		var dentro := caixa.size.x - 16.0
		var esq := caixa.position.x + 8.0
		_texto_cabendo(
			"SOCO %d" % (i + 1), caixa.position.y + 32.0,
			CORPO_APOIO, Color(cor, 0.95), dentro, esq
		)
		if feito:
			_texto_arcade(
				"%04d" % int(socos[i]["pontos"]), caixa.position.y + 92.0, 54,
				Color.WHITE if not eh_melhor else cor, dentro, esq
			)
			# O MPU-6050 não mede massa em kg; inventar "peso" seria falso.
			# Mostramos as duas leituras exatas disponíveis: pico em g e
			# velocidade integrada, sempre ligadas ao cartão deste soco.
			var medida := "%.2f m/s" % float(socos[i]["velocidade"])
			var pico_g := float(socos[i].get("pico_g", 0.0))
			if pico_g > 0.0:
				medida = "PICO %.1f g  •  %s" % [pico_g, medida]
			_texto_cabendo(
				medida, caixa.position.y + 126.0,
				CORPO_APOIO, Paleta.TINTA_LEVE, dentro, esq
			)
			if eh_melhor:
				# A faixa MELHOR mora ACIMA do cartão: dentro dele ela
				# brigaria com o rótulo do soco por 32 pixels de altura.
				_texto_cabendo(
					"MELHOR", caixa.position.y - 12.0,
					CORPO_APOIO, cor, dentro, esq
				)
		else:
			_texto_arcade(
				"– – – –" if not esperando else "AGORA",
				caixa.position.y + 92.0, 42, Color(cor, pulso), dentro, esq
			)

## O PLACAR ACEITA UM CORPO DE LETRA porque agora há dois tamanhos: a
## plaqueta da arena (menor, porque a arena ficou com o meio da tela) e o
## corpo cheio de antes. Um número escrito duas vezes por dois códigos
## diferentes é como os dois deixam de ter o mesmo contorno.
func _placar(texto: String, centro: Vector2, cor: Color, corpo := PLACAR_CORPO) -> void:
	var medida := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, corpo)
	var pos := Vector2(centro.x - medida.x * 0.5, centro.y + corpo * 0.36)
	# Um halo, em vez de três atlas de contorno sobrepostos a cada número.
	draw_string_outline(
		fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, corpo,
		int(corpo * 0.25), Color(cor, 0.22)
	)
	draw_string_outline(
		fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, corpo,
		int(corpo * 0.085), Color(Paleta.CONTORNO, 0.95)
	)
	draw_string(
		fonte, pos - Vector2(0.0, corpo * 0.045), texto,
		HORIZONTAL_ALIGNMENT_LEFT, -1, corpo, cor.lightened(0.5)
	)
	draw_string(fonte, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, corpo, cor)

## O VAZIO ATRÁS DO PLACAR ERA O MAIOR PEDAÇO DA TELA.
##
## O medalhão ocupa o meio e o painel é alto: sobrava um retângulo preto
## de mais de mil pixels em volta, justamente nos dois segundos em que
## todo mundo está olhando. Agora o placar irradia — e irradia NA MEDIDA
## DA PONTUAÇÃO, para que a tela inteira, e não só o número, diga se o
## soco foi forte.
func _draw_campo_de_forca(centro: Vector2, cor: Color, progresso: float, no_impacto: bool) -> void:
	# No meio segundo do impacto ainda não há pontuação nenhuma para
	# mostrar, então quem manda é o próprio golpe: começa no talo e
	# desinfla enquanto a máquina "calcula".
	var forca := progresso
	if no_impacto:
		forca = 1.0 - clampf(state_time / GameDef.IMPACTO_DURACAO, 0.0, 1.0)
	# DOIS DISCOS, E OS DOIS MAIORES QUE O QUADRO. Eles tingem a tela
	# inteira com a cor do nível; o miolo fica escondido atrás da arena,
	# então o que se vê é o halo escapando em volta da moldura — que é
	# exatamente o efeito que se quer, luz saindo de trás do quadro.
	for i in range(2):
		draw_circle(centro, 600.0 + float(i) * 190.0, Color(cor, 0.040 * forca), true, -1.0, true)
	# E OS RAIOS COMEÇAM FORA DA MOLDURA. Nascendo no centro eles
	# cruzariam a imagem do lutador; nascendo na borda, viram o brilho de
	# um telão empurrando luz para os cantos da tela.
	for i in range(36):
		var ang := float(i) * TAU / 36.0 + animation_time * 0.22
		var onda := 0.5 + 0.5 * sin(float(i) * 1.7 - animation_time * 4.0)
		var perto := 500.0
		var longe := perto + lerpf(24.0, 260.0, forca * onda)
		draw_line(
			centro + Vector2.from_angle(ang) * perto,
			centro + Vector2.from_angle(ang) * longe,
			Color(cor, 0.08 + 0.34 * forca * onda), 6.0, true
		)

## AS DUAS COLUNAS DE PONTUAÇÃO SAÍRAM DAQUI E VIRARAM AS BARRAS DE DANO.
##
## Elas mediam a pontuação do soco, uma de cada lado do painel; a posição
## é a mesma e o desenho é o mesmo — o que mudou foi o que elas contam.
## Agora contam o estado do adversário, que é um número que só esta
## versão do jogo produz. Ver `ArenaQuadro.barras`, onde elas moram desde
## então, e `Lutador3D.DANO_POR_GOLPE`, que é quem alimenta o número.

## Ouro, prata e bronze nos três primeiros; azul da casa nos demais. É a
## convenção que todo mundo já lê sem legenda.
func _cor_da_posicao(posicao: int) -> Color:
	match posicao:
		1:
			return Paleta.AMBAR
		2:
			return Color("8fa3bd")
		3:
			return Color("c1783a")
	return Paleta.CIANO

## A TABELA DE RECORDES, EM TRÊS ATOS.
##
##   1. O ANÚNCIO (só para quem entrou): o selo com a posição, sozinho.
##   2. A TABELA: as linhas entram em cascata curta, deslizando pouco e
##      sem quique — uma montagem rápida, e não vinte animações.
##   3. O DESTAQUE: a linha de quem jogou acende no próprio lugar (não
##      cai por cima das outras) e o confete começa, POR TRÁS dos cartões.
##
## Nada é desenhado por cima da tabela depois que ela aparece: os fogos
## do resultado param (ver `_manter_festa`) e o confete mora na camada
## de fundo dos efeitos.
const LINHA_ALTURA := 126.0
const LISTA_TOPO := 336.0
const LINHAS_VISIVEIS := 8
const LISTA_RECORTE_TOPO := 330.0
const LISTA_RECORTE_BASE := 1350.0
const LINHA_CASCATA := 0.035
const LINHA_ENTRADA := 0.24
const LINHA_DESLIZE := 36.0

const ATO_ANUNCIO := 0.95
const ATO_TABELA := 0.60
const ATO_ASSENTA := 0.35

func _tempo_do_ranking() -> float:
	if not ranking_announced or ranking_started_at < 0.0:
		return 0.0
	return maxf(0.0, verdict_time - ranking_started_at)

## Saída suave, sem passar do ponto: é o que tira o "tranco" das linhas.
static func _suave(t: float) -> float:
	var u := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - u * u * u

func _draw_ranking_reveal() -> void:
	var t := _tempo_do_ranking()
	var entrou := posicao_no_ranking > 0
	var anuncio := ATO_ANUNCIO if entrou else 0.0
	if entrou and t < anuncio:
		_ranking_anuncio(t / anuncio)
		return

	var tabela := t - anuncio
	var destaque := clampf((tabela - ATO_TABELA) / ATO_ASSENTA, 0.0, 1.0)
	var celebracao := RankingCelebration.para(posicao_no_ranking)
	_ranking_cabecalho(entrou, celebracao, tabela)

	# A janela já chega rolada para a vizinhança da posição conquistada,
	# com a linha dela na quinta posição visível (do 1º ao 5º lugar a
	# tabela aparece desde o topo).
	var foco := clampi(posicao_no_ranking - 5, 0, maxi(RANKING_TAMANHO - LINHAS_VISIVEIS, 0))
	var offset := float(foco) * LINHA_ALTURA
	for i in range(RANKING_TAMANHO):
		var y := LISTA_TOPO + float(i) * LINHA_ALTURA - offset
		if y < LISTA_RECORTE_TOPO or y + LINHA_ALTURA - 18.0 > LISTA_RECORTE_BASE:
			continue
		var atraso := float(i - foco) * LINHA_CASCATA
		var entrada := clampf((tabela - atraso) / LINHA_ENTRADA, 0.0, 1.0)
		if entrada <= 0.0:
			continue
		var do_jogador := posicao_no_ranking == i + 1
		_ranking_linha(i, y, entrada, do_jogador, destaque if do_jogador else 0.0)
	_ranking_rodape()

## O cabeçalho: título, faixa da colocação e o fio.
func _ranking_cabecalho(entrou: bool, celebracao: Dictionary, tabela: float) -> void:
	var chegada := _suave(tabela / 0.30)
	var a := chegada
	_texto_arcade("TOP 20", 206.0 - (1.0 - chegada) * 16.0, 104, Color(Paleta.CIANO, a), LARGURA_UTIL)
	draw_rect(Rect2(MARGEM + 40.0, 236.0, LARGURA_UTIL - 80.0, 3.0), Color(Paleta.CIANO, 0.5 * a))
	if not entrou:
		_texto_cabendo("TENTE SUPERAR ESSAS MARCAS", 296.0, 34, Color(Paleta.TINTA_FRACA, a), LARGURA_UTIL)
		return
	var cor: Color = celebracao.get("cor", Paleta.AMBAR)
	var faixa := Rect2(MARGEM + 150.0, 258.0, LARGURA_UTIL - 300.0, 56.0)
	_placa(faixa, 12.0, Color("1a0509", 0.92 * a))
	draw_rect(faixa, Color(cor, 0.85 * a), false, 2.0)
	draw_rect(Rect2(faixa.position, Vector2(7.0, faixa.size.y)), Color(cor, a))
	_texto(
		str(celebracao.get("subtitulo", "%dº LUGAR" % posicao_no_ranking)),
		faixa.position.y + 38.0, 30, Color(cor, a),
		HORIZONTAL_ALIGNMENT_CENTER, faixa.position.x, faixa.size.x
	)

## "23/09 • 14:32" a partir do `created_at` gravado (ISO do sistema).
static func _data_curta(iso: String) -> String:
	if iso.length() < 16 or iso[4] != "-":
		return ""
	return "%s/%s  •  %s" % [iso.substr(8, 2), iso.substr(5, 2), iso.substr(11, 5)]

## UMA LINHA DA TABELA. `entrada` (0–1) é a chegada dela; `destaque`
## (0–1) acende a linha de quem acabou de jogar.
##
## O texto de cada linha diz algo DE VERDADE sobre a marca: o nível
## alcançado (na cor do nível) e quando ela foi feita. "JOGADOR" em todas
## as linhas não dizia nada.
func _ranking_linha(i: int, y: float, entrada: float, e_do_jogador: bool, destaque := 0.0) -> void:
	var vazia := i >= ranking.size()
	var posicao := i + 1
	var cor := _cor_da_posicao(posicao)
	var passo := _suave(entrada)
	var tinta := passo
	var card := Rect2(78.0 - (1.0 - passo) * LINHA_DESLIZE, y, 924.0, LINHA_ALTURA - 16.0)

	if vazia:
		_placa(card, 10.0, Color("170509", tinta * 0.85))
		draw_rect(card, Color("3d1019", tinta * 0.8), false, 1.5)
		_texto("%02d" % posicao, y + 66.0, 34, Color(Paleta.TINTA_LEVE, tinta), HORIZONTAL_ALIGNMENT_CENTER, card.position.x + 24.0, 82.0)
		_texto("VAGA ABERTA", y + 64.0, 26, Color(Paleta.TINTA_FRACA, tinta * 0.8), HORIZONTAL_ALIGNMENT_LEFT, card.position.x + 232.0)
		return

	var alta := posicao <= 3
	var nota := RankingStore.score_at(ranking, i)
	var fundo := Color("3a0d1a") if alta else Color("240810")
	if e_do_jogador:
		# A linha de quem jogou ACENDE no lugar: brilho que chega e fica
		# num tom quente, e um halo que só pulsa uma vez.
		fundo = fundo.lerp(Color("b21029"), destaque)
		if destaque > 0.0 and destaque < 1.0:
			var halo := sin(destaque * PI)
			_placa(card.grow(6.0 + 10.0 * halo), 16.0, Color(Paleta.AMBAR, 0.16 * halo))
	_placa(card, 10.0, Color(fundo, tinta))
	var borda := 3.0 if alta or e_do_jogador else 1.5
	var borda_cor := Paleta.AMBAR if e_do_jogador and destaque > 0.0 else cor
	draw_rect(card, Color(borda_cor, tinta * (0.95 if alta or e_do_jogador else 0.45)), false, borda)
	draw_rect(Rect2(card.position, Vector2(8.0, card.size.y)), Color(cor, tinta))

	# A ficha do número: no pódio é a medalha cheia; abaixo, neutra.
	var ficha := Rect2(card.position.x + 24.0, y + 14.0, 82.0, 82.0)
	_placa(ficha, 10.0, Color(cor, tinta) if alta else Color("140309", tinta * 0.92))
	if not alta:
		draw_rect(ficha, Color(cor, tinta * 0.35), false, 1.5)
	_texto(
		"%02d" % posicao, ficha.position.y + 56.0, 36,
		Color(Color("1a0409") if alta else cor, tinta),
		HORIZONTAL_ALIGNMENT_CENTER, ficha.position.x, ficha.size.x
	)
	_draw_player_photo(Rect2(card.position + Vector2(126.0, 14.0), Vector2(82.0, 82.0)), str(ranking[i].get("photo_path", "")), tinta)

	var x_texto := card.position.x + 232.0
	var nivel := ScoreTier.nome_de(nota)
	var cor_nivel := Paleta.texto_sobre(fundo, ScoreTier.cor_de(nota))
	if e_do_jogador:
		_texto("VOCÊ", y + 50.0, 31, Color(Paleta.CREME, tinta), HORIZONTAL_ALIGNMENT_LEFT, x_texto, 300.0)
		_texto(nivel, y + 84.0, 20, Color(cor_nivel, tinta), HORIZONTAL_ALIGNMENT_LEFT, x_texto, 320.0)
	else:
		_texto(nivel, y + 50.0, 25, Color(cor_nivel, tinta), HORIZONTAL_ALIGNMENT_LEFT, x_texto, 320.0)
		var quando := _data_curta(str(ranking[i].get("created_at", "")))
		if not quando.is_empty():
			_texto(quando, y + 84.0, 20, Color(Paleta.TINTA_LEVE, tinta), HORIZONTAL_ALIGNMENT_LEFT, x_texto, 320.0)
	_texto(
		"%04d" % nota, y + 78.0, 56 if (alta or e_do_jogador) else 48,
		Color(Paleta.TINTA, tinta), HORIZONTAL_ALIGNMENT_RIGHT,
		card.position.x, card.size.x - 32.0
	)

## O rodapé: a nota da rodada e o convite para jogar de novo.
func _ranking_rodape() -> void:
	_rotulo("SEU SOCO", 1428.0, Paleta.TINTA_FRACA)
	_texto_arcade("%04d" % result_score, 1546.0, 100, ScoreTier.cor_de(result_score), LARGURA_UTIL)
	_rotulo("START • JOGAR NOVAMENTE", 1706.0, Paleta.AMBAR)
	_marca_lateral(1770.0, 0.95, 104.0)

## Chegada com batida (passa do ponto e volta). Só o selo do anúncio usa.
func _passo_com_batida(t: float) -> float:
	if t >= 1.0:
		return 1.0
	var p := t - 1.0
	return p * p * ((1.6 + 1.0) * p + 1.6) + 1.0

## ATO 1 — O ANÚNCIO: o selo com o número da posição, sozinho na tela.
func _ranking_anuncio(t: float) -> void:
	var centro := Vector2(540.0, 810.0)
	var celebracao := RankingCelebration.para(posicao_no_ranking)
	var abre := clampf(t * 2.2, 0.0, 1.0)
	var escala := _passo_com_batida(abre)
	var raio := float(celebracao.get("raio_selo", 280.0)) * escala
	var cor_selo: Color = celebracao.get("cor", Paleta.AMBAR)

	var quantidade_raios := int(celebracao.get("raios", 12))
	for i in range(quantidade_raios):
		var ang := float(i) * TAU / float(quantidade_raios) + animation_time * 0.35
		var perto := raio * 1.12
		draw_line(
			centro + Vector2.from_angle(ang) * perto,
			centro + Vector2.from_angle(ang) * (perto + lerpf(30.0, 150.0, abre)),
			Color(cor_selo, 0.26 * abre), 6.0 if posicao_no_ranking <= 3 else 4.0, true
		)
	draw_circle(centro, raio, Color(Paleta.VERMELHO, 0.92), true, -1.0, true)
	Traco.arco(self, centro, raio, cor_selo, 10.0 if posicao_no_ranking == 1 else 7.0)
	for anel in range(int(celebracao.get("aneis", 1))):
		Traco.arco(self, centro, raio * (0.86 - float(anel) * 0.075), Color(Paleta.CREME, 0.40 - float(anel) * 0.09), 3.0)
	if posicao_no_ranking == 1:
		Icones.cinturao(self, centro + Vector2(0.0, -raio * 0.57), raio * 0.23, cor_selo)
	else:
		Icones.trofeu(self, centro + Vector2(0.0, -raio * 0.57), raio * 0.16, cor_selo)
	# Todos os textos usam uma caixa centrada no próprio selo. Antes a
	# caixa começava em x=230 e terminava fora da tela; por isso palavras
	# escapavam do círculo e a composição parecia desmontada.
	var texto_largura := raio * 1.52
	var texto_x := centro.x - texto_largura * 0.5
	_texto_arcade(str(celebracao.get("titulo", "VOCÊ ENTROU")), centro.y - raio * 0.20, 62, Paleta.CREME, texto_largura, texto_x)
	# O número ocupa o centro óptico e não a borda inferior.
	_texto_arcade("%dº" % posicao_no_ranking, centro.y + raio * 0.25, 126, Paleta.CREME, texto_largura, texto_x)
	_texto_arcade(str(celebracao.get("subtitulo", "NO TOP 20")), centro.y + raio * 0.56, 43, cor_selo, texto_largura, texto_x)

# ---------------------------------------------------------------- central
const CENTRAL_FUNDO := Color("2b0a13")

func _draw_central() -> void:
	var caixa := Rect2(40, 96, 1000, 1790)
	_placa(caixa, 22.0, Paleta.CARTAO_BORDA)
	_placa(caixa.grow(-5.0), 19.0, CENTRAL_FUNDO)
	# A AUDITORIA COMEÇA AQUI, e não antes.
	#
	# Tudo o que foi desenhado até esta linha está ATRÁS de um painel
	# opaco — o letreiro da abertura, o placar, o ringue. Contar aquilo
	# como "texto que tapa outro texto" seria acusar a tela de um defeito
	# que ninguém vê: o painel já cobriu. A auditoria mede o que está por
	# cima dele, que é o que o operador lê.
	if auditoria_de_layout:
		auditoria.clear()
		_auditando_o_miolo = true

	# ---- O MIOLO, deslocado pela rolagem.
	#
	# O Godot não recorta o que um `_draw` desenha, então a página inteira
	# é desenhada e as duas faixas — cabeçalho e rodapé — são REPINTADAS
	# por cima logo depois. O efeito é o de uma janela com rolagem, sem
	# precisar de um SubViewport só para isso.
	central_fundo = 0.0
	draw_set_transform(_deslocamento - Vector2(0.0, central_rolagem), 0.0, Vector2.ONE)
	match central_pagina:
		1:
			_central_golpe()
		2:
			_central_camera()
		3:
			_central_dados()
		4:
			_central_maquina()
		_:
			_central_operacao()
	draw_set_transform(_deslocamento, 0.0, Vector2.ONE)
	_auditando_o_miolo = false

	# ---- As faixas paradas, cobrindo o que a página passou por baixo.
	draw_rect(Rect2(45, 101, 990, CENTRAL_TOPO - 101.0), CENTRAL_FUNDO)
	draw_rect(Rect2(45, CENTRAL_BASE, 990, 1881.0 - CENTRAL_BASE), CENTRAL_FUNDO)
	_letreiro("CENTRAL TÉCNICA", Vector2(110.0, 204.0), 44, Paleta.CREME)
	_texto("Configuração, diagnóstico e calibração", 240.0, 18, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_LEFT, 110.0)
	_botao(BOTOES_SIMPLES["fechar"], "×", false, Paleta.VERMELHO, 32)
	_abas_da_central()
	_barra_de_rolagem()

	_botao(BOTOES_SIMPLES["padroes"], "RESTAURAR PADRÕES", false, Paleta.AMBAR, 19)
	_botao(BOTOES_SIMPLES["salvar"], "SALVAR E FECHAR", true, Paleta.VERDE, 21)
	_texto(
		"Tecla T: testar sensor  •  Roda/setas: rolar a página",
		1872.0, 14, Paleta.TINTA_LEVE
	)

## A BARRA DE ROLAGEM, à direita do miolo.
##
## Ela não é enfeite: sem ela ninguém sabe que a página continua abaixo
## do que está à vista, e a informação que sobrou embaixo é exatamente a
## que faz falta — o diagnóstico da câmera, o saldo, as ações do
## firmware. Some sozinha quando a página cabe inteira.
func _barra_de_rolagem() -> void:
	var maxima := _rolagem_maxima()
	if maxima <= 1.0:
		return
	var trilho := Rect2(1014, CENTRAL_TOPO + 6.0, 8, CENTRAL_JANELA - 12.0)
	draw_rect(trilho, Color(Paleta.CREME, 0.10))
	var proporcao := CENTRAL_JANELA / (CENTRAL_JANELA + maxima)
	var altura := maxf(60.0, trilho.size.y * proporcao)
	var topo := trilho.position.y + (trilho.size.y - altura) * (central_rolagem / maxima)
	draw_rect(Rect2(trilho.position.x, topo, trilho.size.x, altura), Color(Paleta.AMBAR, 0.85))

func _abas_da_central() -> void:
	for i in range(PAGINAS.size()):
		var r := Rect2(
			ABA_RECT.position + Vector2(float(i) * ABA_LARGURA, 0.0),
			Vector2(ABA_LARGURA - 6.0, ABA_RECT.size.y)
		)
		var atual := i == central_pagina
		_cartao(r, Paleta.AMBAR if atual else Color("330c16"), Paleta.CARTAO_BORDA, 1.0, 2.0)
		# `_texto_cabendo`, e não `_texto`: com cinco abas em 920 px o
		# rótulo mais longo não cabe em corpo 20, e letra transbordando
		# a aba ao lado é exatamente o que esta revisão foi caçar.
		_texto_cabendo(
			str(PAGINAS[i]), r.position.y + 40.0, 20,
			Color("2b0a13") if atual else Paleta.TINTA_FRACA,
			r.size.x - 16.0, r.position.x + 8.0
		)

# ---------------------------------------------------------- OPERAÇÃO
func _central_operacao() -> void:
	_secao(Rect2(80, 350, 920, 138), "MODO DE OPERAÇÃO", Paleta.ROSA)
	_botao(BOTOES_SIMPLES["modo_livre"], "LIVRE", game_mode == "free", Paleta.CIANO, 22)
	_botao(BOTOES_SIMPLES["modo_ficha"], "1 FICHA", game_mode == "credit", Paleta.ROSA, 22)

	# ---- os dois botões físicos do gabinete
	_secao(Rect2(80, 504, 920, 400), "BOTÕES DO GABINETE (ZERO DELAY)", Paleta.CIANO)
	_texto(
		"A placa aparece como controle USB e o índice muda de porta para porta. Mapeie aqui.",
		578.0, 15, Paleta.TINTA_FRACA
	)
	_botao(
		BOTOES_SIMPLES["mapear_start"],
		"AGUARDANDO START" if mapeando == "start" else "MAPEAR START",
		mapeando == "start", Paleta.VERDE, 19
	)
	_botao(
		BOTOES_SIMPLES["mapear_credito"],
		"AGUARDANDO CRÉDITO" if mapeando == "credito" else "MAPEAR CRÉDITO",
		mapeando == "credito", Paleta.AMBAR, 19
	)
	_ficha_do_botao(botao_start, "START", Rect2(110, 706, 400, 150), contador_start)
	_ficha_do_botao(botao_credito, "CRÉDITO", Rect2(570, 706, 400, 150), contador_credito)

	_secao(Rect2(80, 920, 920, 225), "PERSONAGEM DA ARENA", Paleta.VERDE)
	var avancado := arena != null and arena.modelo_avancado()
	_texto(
		"LUTADOR HD • NOVE POSES" if avancado else "FALTAM POSES NA FOLHA",
		1000.0, 24, Paleta.VERDE if avancado else Paleta.AMBAR
	)
	_texto(
		"Pronto para o salão" if avancado else "Confira assets/personagem/sprites",
		1045.0, 17, Paleta.CREME
	)
	_texto(
		"Nove ilustrações e o movimento por cima delas — sem modelo 3D para faltar.",
		1086.0, 14, Paleta.TINTA_FRACA
	)

	_secao(Rect2(80, 1170, 920, 130), "SALDO", Paleta.AMBAR)
	_texto(
		"Créditos %02d  •  partidas contadas %d  •  modo %s" % [
			credits, plays, "livre" if game_mode == "free" else "1 ficha"
		],
		1244.0, 20, Paleta.CREME
	)

## A ficha de um botão mapeado: qual controle, qual índice, e um contador
## que sobe a cada aperto. O contador é o que prova que o mapeamento
## pegou — sem ele, o técnico aperta o botão e não sabe se o problema é a
## placa, o índice ou o jogo.
func _ficha_do_botao(mapa: Dictionary, titulo: String, rect: Rect2, contador: int) -> void:
	_cartao(rect, Color("240810"), Paleta.CARTAO_BORDA, 1.0, 2.0)
	_texto(titulo, rect.position.y + 34.0, 20, Paleta.CREME, HORIZONTAL_ALIGNMENT_CENTER, rect.position.x, rect.size.x)
	var indice := int(mapa.get("index", -1))
	_texto(
		"BOTÃO %d" % indice if indice >= 0 else "NÃO MAPEADO",
		rect.position.y + 68.0, 18,
		Paleta.AMBAR if indice >= 0 else Paleta.VERMELHO,
		HORIZONTAL_ALIGNMENT_CENTER, rect.position.x, rect.size.x
	)
	var nome := str(mapa.get("nome", ""))
	_texto(
		nome if not nome.is_empty() else "controle não identificado",
		rect.position.y + 98.0, 14, Paleta.TINTA_LEVE,
		HORIZONTAL_ALIGNMENT_CENTER, rect.position.x + 8.0, rect.size.x - 16.0
	)
	_texto(
		"apertado %d ×" % contador, rect.position.y + 128.0, 16, Paleta.VERDE,
		HORIZONTAL_ALIGNMENT_CENTER, rect.position.x, rect.size.x
	)

# ------------------------------------------------------------- GOLPE
func _central_golpe() -> void:
	# AS TRÊS ÂNCORAS, NA MESMA UNIDADE E NA MESMA CAIXA.
	#
	# Piso, soco médio e teto são a régua inteira, em m/s. Quem regula lê
	# os três de uma vez e sabe o que a máquina vai pagar — era isso que
	# faltava enquanto a dificuldade era um expoente adimensional numa
	# caixa ao lado, que só dizia alguma coisa a quem já sabia a conta.
	# Ver `ScoreCurve`.
	_secao(Rect2(80, 350, 920, 452), "A RÉGUA DO SOCO", Paleta.CIANO)
	_stepper("vmin", "%.1f m/s" % hit_min_speed, "MÍNIMA  =  0000 PONTOS", Paleta.CIANO)
	_stepper("vmax", "%.1f m/s" % hit_max_speed, "MÁXIMA  =  9999 PONTOS", Paleta.CIANO)
	_stepper(
		"referencia", "%.1f m/s" % _referencia_efetiva(),
		"SOCO MÉDIO = %04d  •  %s" % [
			ScoreCurve.PONTOS_DE_REFERENCIA,
			ScoreCurve.difficulty_name(hit_min_speed, hit_max_speed, score_ref_speed),
		],
		Paleta.AMBAR
	)
	_stepper(
		"curva", "%.2f ×" % score_contraste,
		"CONTRASTE — não mexe nas âncoras", Paleta.ROXO
	)
	# A ZONA MORTA SAIU DESTA PÁGINA, e não é economia de espaço.
	#
	# Ela era um segundo jeito de dizer a mesma coisa que a VELOCIDADE
	# MÍNIMA já diz: "abaixo disto não pontua". Uma em fração da faixa, a
	# outra em m/s, cada uma com o seu passo, as duas somando. Dois
	# controles para uma ideia só é como eles acabam discordando — e quem
	# regula não tinha como saber qual dos dois estava recusando o golpe
	# fraco que ele acabou de dar.
	#
	# O ajuste continua existindo no arquivo de configuração e continua
	# sendo respeitado pela curva, para não mudar de comportamento numa
	# máquina que já tinha um valor gravado. O que saiu foi a segunda
	# maneira de mexer nele.

	# A LEITURA AO VIVO — E POR QUE ELA FALTAVA TANTO.
	#
	# A tela nunca mostrou a velocidade. Quando a régua está errada para
	# o gabinete, o sintoma é "todo mundo tira mil pontos" e não há como
	# descobrir por quê: a nota baixa parece dificuldade, não escala
	# errada. Com o número em m/s ao lado da nota, uma batida responde a
	# pergunta inteira — e os três botões abaixo consertam na mesma hora.
	_leitura_do_ultimo_soco(666.0)
	_botao(BOTOES_SIMPLES["usar_min"], "É O MÍNIMO", false, Paleta.CIANO, 17)
	_botao(BOTOES_SIMPLES["usar_ref"], "É O SOCO MÉDIO", false, Paleta.AMBAR, 17)
	_botao(BOTOES_SIMPLES["usar_max"], "É O MÁXIMO", false, Paleta.VERMELHO, 17)
	_texto(
		"bata uma vez e toque no que aquele soco deve valer — a régua se ajusta na hora",
		790.0, 15, Paleta.TINTA_FRACA
	)

	# ------------------------------------------------- aprende sozinha
	_secao(Rect2(80, 826, 920, 190), "A RÉGUA APRENDE SOZINHA", Paleta.VERDE)
	_botao(
		BOTOES_SIMPLES["auto_escala"],
		"APRENDIZADO: LIGADO" if auto_escala.ligada else "APRENDIZADO: DESLIGADO",
		auto_escala.ligada, Paleta.VERDE, 18
	)
	_botao(BOTOES_SIMPLES["esquecer_escala"], "ESQUECER E RECOMEÇAR", false, Paleta.ROXO, 18)
	var memoria := auto_escala.quantos()
	var estado := "aprendendo — %d socos na memória (precisa de %d)" % [
		memoria, AutoEscala.MINIMO_PARA_VALER
	]
	if not auto_escala.ligada:
		estado = "desligado — a régua fica exatamente onde você deixou"
	elif auto_escala.pronta():
		estado = "ativo — %d socos na memória, ajustando aos poucos" % memoria
	_texto(estado, 968.0, 16, Paleta.CREME if auto_escala.pronta() else Paleta.TINTA_FRACA)
	var destino := auto_escala.alvo()
	if destino.is_empty():
		_texto(
			"só os 30%% mais fortes passam de %d pontos, em qualquer gabinete" % (
				ScoreCurve.PONTOS_DE_REFERENCIA
			),
			996.0, 14, Paleta.TINTA_LEVE
		)
	else:
		_texto(
			"indo para  %.2f  /  %.2f  /  %.2f m/s   (mínimo / médio / máximo)" % [
				float(destino["vmin"]), float(destino["vref"]), float(destino["vmax"])
			],
			996.0, 14, Paleta.CIANO
		)

	_secao(Rect2(80, 1042, 920, 240), "OS OITO NÍVEIS (0000 – 9999)", Paleta.AMBAR)
	# A régua engordou e a legenda desceu: com a letra no corpo novo, o
	# nome do nível dentro da faixa e a legenda logo abaixo escreviam um
	# por cima do outro.
	_regua_dos_niveis(Rect2(110, 1092, 860, 46))
	_texto(
		"As faixas são fixas. Quem decide quanta gente chega a cada uma é o soco médio.",
		1166.0, 15, Paleta.TINTA_FRACA
	)
	_curva_desenhada(Rect2(110, 1180, 860, 56))
	_botao(BOTOES_SIMPLES["calibrar"], "ASSISTENTE DE CALIBRAÇÃO", false, Paleta.VERDE, 20)

	_secao(Rect2(80, 1386, 920, 324), "SENSOR ÓPTICO DE FENDA (LM393)", Paleta.ROXO)
	_seletor_porta_refinado()
	var nome_polaridade: String = str({"A":"AUTO", "H":"ALTO", "L":"BAIXO"}.get(sensor_eixo, "AUTO"))
	_botao(BOTOES_SIMPLES["eixo"], "SINAL  %s" % nome_polaridade, false, Paleta.ROXO, 20)
	_texto("POLARIDADE DO BLOQUEIO", 1562.0, 15, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_CENTER, BOTOES_SIMPLES["eixo"].position.x, BOTOES_SIMPLES["eixo"].size.x)
	_stepper("raio", "%.0f mm" % (sensor_raio * 1000.0), "LARGURA DA PALHETA", Paleta.CIANO)
	# O PULSO MÍNIMO PERDEU O − E O +, E ISSO É O CONSERTO.
	#
	# Ele é um teto de velocidade escrito ao contrário: aumentá-lo
	# ESTREITA o que a máquina aceita. Foi por ser um passo como os
	# outros que uma calibração conseguiu gravar gravidades num campo de
	# milissegundos e a máquina passou a recusar justamente os socos
	# fortes, em silêncio. Agora é leitura — sai da palheta e do teto
	# calibrado — e ao lado vem a única frase que o torna conferível a
	# olho: até que velocidade esta montagem enxerga, e se a régua cabe
	# dentro disso.
	var janela := ArduinoProtocol.janela_medivel(sensor_raio, sensor_pulso_ms)
	# OS DOIS SUBIRAM VINTE PIXELS. A legenda "LARGURA DA PALHETA" e a
	# frase que confere a janela do sensor estavam na mesma faixa de
	# altura, uma centrada na coluna da esquerda e a outra na largura
	# inteira: elas se cruzavam no meio. Subindo o par de visores, a
	# frase ganha a linha inteira para ela.
	var caixa_pulso := Rect2(570, 1566, 400, LADO_BOTAO)
	_cartao(caixa_pulso, Color("1c060c"), Paleta.CARTAO_BORDA, 1.0, 1.5)
	_texto(
		"%.2f ms" % sensor_pulso_ms, caixa_pulso.position.y + 42.0, 26, Paleta.CIANO,
		HORIZONTAL_ALIGNMENT_CENTER, caixa_pulso.position.x, caixa_pulso.size.x
	)
	_texto(
		"PULSO MÍNIMO — CALCULADO", caixa_pulso.end.y + 20.0, 15, Paleta.TINTA_FRACA,
		HORIZONTAL_ALIGNMENT_CENTER, caixa_pulso.position.x, caixa_pulso.size.x
	)
	_texto(
		"o sensor mede de %.2f a %.1f m/s  •  a régua vai até %.1f" % [
			janela.x, janela.y, hit_max_speed
		],
		1700.0, 15,
		Paleta.VERMELHO if janela.y < hit_max_speed else Paleta.TINTA_LEVE,
		HORIZONTAL_ALIGNMENT_CENTER, 120.0, 840.0
	)

	_secao(Rect2(80, 1734, 920, 124), "AÇÕES NO FIRMWARE", Paleta.VERDE)
	_botao(BOTOES_SIMPLES["enviar_config"], "ENVIAR CONFIG", false, Paleta.VERDE, 19)
	_botao(BOTOES_SIMPLES["testar"], "TESTAR SENSOR", false, Paleta.AMBAR, 19)

	_texto(
		telemetria if telemetria != "" else "sem telemetria ainda",
		1890.0, 15, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	if not saturacao_recente.is_empty():
		_texto(
			"SATURAÇÃO DO SENSOR: %s" % saturacao_recente,
			1922.0, 15, Paleta.VERMELHO, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
		)

## A ÚLTIMA BATIDA, EM VELOCIDADE E EM PONTOS, LADO A LADO.
##
## Duas informações e uma conclusão. A velocidade diz o que o sensor
## entregou; a nota diz o que a régua fez com ela; e a barra embaixo
## mostra ONDE aquele soco caiu dentro da régua. Quando todo mundo tira
## mil pontos, a barra fica colada na esquerda — e aí a resposta deixa de
## ser "o pessoal bate fraco" e passa a ser "o máximo da régua está longe
## demais do que esta máquina mede", que é o que de fato acontecia.
func _leitura_do_ultimo_soco(y: float) -> void:
	var caixa := Rect2(110, y - 26.0, 860, 62)
	_cartao(caixa, Color("14040a"), Paleta.CARTAO_BORDA, 1.0, 1.5)
	if ultima_velocidade <= 0.0:
		_texto(
			"nenhum soco ainda — bata uma vez, ou use TESTAR SENSOR",
			y + 12.0, 16, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_CENTER, caixa.position.x, caixa.size.x
		)
		return
	_texto(
		"ÚLTIMO SOCO", y - 2.0, 14, Paleta.TINTA_FRACA,
		HORIZONTAL_ALIGNMENT_LEFT, caixa.position.x + 18.0, 200.0
	)
	_texto(
		"%.2f m/s" % ultima_velocidade, y + 24.0, 26, Paleta.CIANO,
		HORIZONTAL_ALIGNMENT_LEFT, caixa.position.x + 18.0, 240.0
	)
	_texto(
		"%04d" % ultima_nota, y + 24.0, 30, ScoreTier.cor_de(ultima_nota),
		HORIZONTAL_ALIGNMENT_RIGHT, caixa.position.x, caixa.size.x - 20.0
	)
	_texto(
		ScoreTier.nome_de(ultima_nota), y - 2.0, 14, Paleta.TINTA_FRACA,
		HORIZONTAL_ALIGNMENT_RIGHT, caixa.position.x, caixa.size.x - 20.0
	)
	# ONDE AQUELE SOCO CAIU NA RÉGUA. É a linha que denuncia a escala.
	var trilho := Rect2(caixa.position.x + 300.0, y + 6.0, 260.0, 10.0)
	draw_rect(trilho, Color("3a1018"))
	var fracao := ScoreCurve.normalized(
		ultima_velocidade, hit_min_speed, hit_max_speed, score_dead_zone
	)
	draw_rect(
		Rect2(trilho.position, Vector2(maxf(trilho.size.x * fracao, 3.0), trilho.size.y)),
		ScoreTier.cor_de(ultima_nota)
	)
	_texto(
		"%d%% da régua" % int(round(fracao * 100.0)), y + 34.0, 13, Paleta.TINTA_LEVE,
		HORIZONTAL_ALIGNMENT_CENTER, trilho.position.x, trilho.size.x
	)

## A CURVA DESENHADA, do jeito que ela vai pagar.
##
## Um expoente é um número abstrato: a diferença entre 2,80 e 3,20 só
## existe no traço. Quem regula precisa VER o que a mudança faz antes de
## salvar, senão regula por tentativa e erro em cima da fila do salão.
func _curva_desenhada(rect: Rect2) -> void:
	_cartao(rect, Color("1c060c"), Paleta.CARTAO_BORDA, 1.0, 1.5)
	var amostras := ScoreCurve.amostrar(
		hit_min_speed, hit_max_speed, score_contraste, score_dead_zone, 64, score_ref_speed
	)
	if amostras.is_empty():
		return
	var v_max: float = (amostras[amostras.size() - 1] as Vector2).x
	var pontos := PackedVector2Array()
	for a in amostras:
		var p: Vector2 = a
		pontos.append(Vector2(
			rect.position.x + rect.size.x * clampf(p.x / maxf(v_max, 0.01), 0.0, 1.0),
			rect.end.y - rect.size.y * clampf(p.y / float(GameDef.SCORE_MAX), 0.0, 1.0)
		))
	draw_polyline(pontos, Paleta.AMBAR, 3.0, true)
	_texto("0 m/s", rect.end.y + 20.0, 13, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, rect.position.x, rect.size.x)
	_texto("%.0f m/s" % v_max, rect.end.y + 20.0, 13, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_RIGHT, rect.position.x, rect.size.x)

# ------------------------------------------------------------ CÂMERA
func _central_camera() -> void:
	_secao(Rect2(80, 350, 920, 500), "CÂMERA DAS FOTOS DO RANKING", Paleta.ROSA)
	_botao(BOTOES_SIMPLES["camera"], "CÂMERA ON" if camera_enabled else "CÂMERA OFF", camera_enabled, Paleta.ROXO, 16)
	_botao(BOTOES_SIMPLES["trocar_camera"], "TROCAR CÂMERA", false, Paleta.CIANO, 16)
	_botao(BOTOES_SIMPLES["foto_teste"], "TESTAR FOTO", false, Paleta.ROSA, 16)
	_botao(
		BOTOES_SIMPLES["espelhar_camera"],
		"ESPELHO: SIM" if camera_mirrored else "ESPELHO: NÃO",
		camera_mirrored, Paleta.VERDE, 15
	)
	_botao(BOTOES_SIMPLES["sondar_camera"], "PROCURAR DE NOVO", false, Paleta.CIANO, 15)
	# A REGRA QUE DECIDE SE A MÁQUINA JOGA SEM WEBCAM — ver
	# `camera_liberou_a_rodada` em `_iniciar_rodada`.
	_botao(
		BOTOES_SIMPLES["camera_obrigatoria"],
		"FOTO AUTOMÁTICA",
		false, Paleta.AMBAR, 15
	)
	var previa := Rect2(340, 556, 400, 220)
	_cartao(previa, Color("1c060c"), Paleta.CARTAO_BORDA, 1.0, 2.0)
	if camera_service != null and camera_service.estado == CameraService.Estado.EXAME:
		# DURANTE O EXAME A PRÉVIA FICA VAZIA DE PROPÓSITO — a webcam é do
		# diagnóstico, e só um programa por vez a abre. Sem dizer isso na
		# tela, o vazio lê como a câmera tendo caído de novo.
		_draw_avatar(previa, 1.0)
		_carregando(previa.get_center(), 34.0, Paleta.CIANO)
		_texto(
			"EXAMINANDO — A CÂMERA VOLTA NO FIM", previa.end.y + 34.0, 17,
			Paleta.CIANO, HORIZONTAL_ALIGNMENT_CENTER, previa.position.x - 100.0, previa.size.x + 200.0
		)
	elif foto_teste_texture != null and Time.get_ticks_msec() < foto_teste_ate_ms:
		_draw_texture_cover(foto_teste_texture, previa, 1.0, camera_mirrored)
	elif camera_service != null and camera_service.tem_imagem():
		_draw_texture_cover(camera_service.preview_texture(), previa, 1.0, camera_mirrored)
	else:
		_texto("SEM IMAGEM", previa.position.y + previa.size.y * 0.5, 22, Paleta.TINTA_LEVE)
	var cam_status := camera_service.status if camera_service != null else "SEM SERVIÇO"
	# DUAS FRASES, DUAS LINHAS. As duas eram desenhadas na MESMA linha de
	# base — uma centrada e a outra à esquerda —, então elas se cruzavam
	# no meio da tela e ninguém conseguia ler nenhuma das duas. É o tipo
	# de defeito que passa despercebido enquanto as duas estão curtas.
	_texto(cam_status, 806.0, 16, Paleta.TINTA_FRACA)
	if camera_service != null:
		_texto(
			camera_service.ficha_da_ponte(), 840.0, 16, Paleta.CIANO,
			HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
		)
	# ---- o relatório, na tela, e não numa janela que abre atrás do jogo
	_secao(Rect2(80, 866, 920, 420), "DIAGNÓSTICO DA CÂMERA", Paleta.AMBAR)
	var ocupado := medico != null and medico.rodando
	_botao(BOTOES_SIMPLES["diagnosticar"], "AGUARDE…" if ocupado else "DIAGNOSTICAR", ocupado, Paleta.CIANO, 18)
	_botao(BOTOES_SIMPLES["instalar_camera"], "RESOLVER ACESSO", false, Paleta.VERDE, 18)
	if ocupado:
		# O exame roda numa linha à parte e pode levar dois minutos. Sem
		# este anel, os dois minutos são indistinguíveis de um botão que
		# não fez nada — que foi exatamente a queixa que trouxe até aqui.
		_carregando(Vector2(540.0, 1010.0), 26.0, Paleta.CIANO)
	if medico == null or medico.linhas.is_empty():
		_texto(
			"Webcam USB/UVC aberta direto pelo plugin Android do jogo.",
			1018.0, 15, Paleta.CIANO
		)
		# TRINTA E QUATRO PIXELS ENTRE LINHAS, e não vinte e quatro. O
		# piso de corpo de letra subiu para 20 quando a tipografia foi
		# unificada, e estas três linhas continuaram com o espaçamento de
		# quando o corpo era 15: cada uma invadia a de baixo por oito
		# pixels, e o texto de ajuda da câmera virou um borrão.
		_texto(
			"Conecte a câmera USB: o jogo reconhece, mantém o vídeo ao vivo e só congela a foto.",
			1052.0, 15, Paleta.TINTA_FRACA
		)
		_texto(
			"DIAGNOSTICAR só consulta. RESOLVER ACESSO libera a privacidade do usuário.",
			1086.0, 15, Paleta.TINTA_FRACA
		)
	else:
		for i in range(medico.linhas.size()):
			var linha := str(medico.linhas[i])
			# Aviso em vermelho, resposta comum em creme: quem olha de
			# relance precisa achar o problema sem ler tudo.
			var grave := linha == linha.to_upper() and linha.length() > 12
			_texto(
				linha, 1000.0 + float(i) * 22.0, 15,
				Paleta.VERMELHO if grave else Paleta.CREME,
				HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
			)
	if medico != null and not medico.indices.is_empty():
		_texto(
			"CÂMERAS ENCONTRADAS NOS ÍNDICES: %s" % _lista_de_indices(medico.indices),
			1256.0, 17, Paleta.VERDE
		)

	_secao(Rect2(80, 1302, 920, 290), "MESA DE SOM", Paleta.VERDE)
	_stepper("vol_musica", "%+.0f dB" % volume_musica, "TRILHA", Paleta.CIANO)
	_stepper("vol_efeitos", "%+.0f dB" % volume_efeitos, "EFEITOS E VOZ", Paleta.AMBAR)
	_botao(BOTOES_SIMPLES["testar_som"], "TOCAR SOCO DE TESTE", false, Paleta.VERDE, 19)

# ------------------------------------------------------------- DADOS
func _central_dados() -> void:
	_secao(Rect2(80, 350, 920, 220), "MELHORES DA CASA", Paleta.VERMELHO)
	# O CARTÃO TINHA 42 PX e guardava duas linhas de texto que somam 74.
	# A nota era desenhada com a linha de base ABAIXO da borda de baixo do
	# cartão, por cima da colocação — "1º" e "9999" no mesmo pixel nas
	# cinco células. Medido pela auditoria de layout, não por acaso.
	_lista_do_ranking(Rect2(110, 410, 860, 74))
	var resumo := StatisticsStore.summary(statistics)
	_texto(
		"Hoje %d  •  7 dias %d  •  média %04d  •  Top 5: %d" % [resumo["today"], resumo["last7"], resumo["average"], resumo["top5_entries"]],
		502.0, 16, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)
	_texto("Recorde da casa: %04d" % _melhor(), 532.0, 18, Paleta.AMBAR, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0)

	# A SEÇÃO CRESCEU PORQUE AS LINHAS NÃO CABIAM — e não caber não era
	# um detalhe de estética: as três últimas linhas do diagnóstico
	# ("portas vistas", "sensor" e "caminho até a placa") eram desenhadas
	# em 832, 860 e 888, dentro de uma caixa que terminava em 780. Elas
	# caíam POR CIMA das linhas da seção seguinte, que começa em 796 e
	# escreve em 858 e 888. Duas frases no mesmo pixel, e qual das duas
	# fica por cima depende da fonte e da escala da tela — que é
	# exatamente por que o diagnóstico saía DIFERENTE em cada PC, com a
	# mesma placa e o mesmo jogo. Quem lê a tela para contar ao telefone
	# o que está escrito estava lendo duas frases embaralhadas.
	# A CENTRAL DEIXOU DE TRAZER O `y` DE CADA LINHA ESCRITO À MÃO.
	#
	# Enquanto trouxe, esta página escondia cinco sobreposições de uma vez
	# — e a pior delas era invisível para quem só olhava o código: as
	# quatro linhas do RITMO eram desenhadas em 1152…1242, ACIMA da
	# moldura que as devia conter (1186). Alguém mexeu na moldura, as
	# linhas ficaram onde estavam, e a seção passou a escrever por cima da
	# seção de cima. Nenhuma das duas frases some — elas se misturam, e
	# qual fica por cima muda com a fonte e a escala da TV. É por isso que
	# o diagnóstico saía DIFERENTE em cada PC com a mesma placa.
	#
	# Agora a linha seguinte nasce da anterior (`_linha`) e a moldura
	# nasce da contagem (`_altura_da_pilha`). Não sobrou número para
	# errar, e o teste tests/test_central_legivel.gd mede o resultado.
	var caixa_diag := Rect2(80, DADOS_DIAG_Y, 920, _altura_da_pilha(15))
	_secao(caixa_diag, "DIAGNÓSTICO DA PLACA", Paleta.CIANO)
	_pilha(caixa_diag)
	_linha(serial_status, 16, Paleta.TINTA_FRACA)
	_linha(telemetria if telemetria != "" else "sem telemetria ainda", 15, Paleta.TINTA_LEVE)
	_linha(
		"Zero Delay:  START %d apertos  •  CRÉDITO %d apertos" % [contador_start, contador_credito],
		15, Paleta.TINTA_LEVE
	)
	# APERTE O BOTÃO E OLHE ESTES DOIS NÚMEROS.
	#
	# O primeiro é o pino CRU, como a placa o lê agora — o fio. O segundo
	# é quantos apertos o jogo aceitou. "O botão não funciona" tem quatro
	# causas com o mesmo sintoma: fio solto, pino errado, placa muda, ou o
	# jogo ignorando. Estas duas linhas separam as quatro em dez segundos:
	# pino que não muda é problema ANTES do firmware, e aí não adianta
	# mexer em código.
	_linha(
		"pinos agora:  D2 START %s  •  D3 CRÉDITO %s" % [
			"APERTADO" if pino_start else "solto",
			"APERTADO" if pino_credito else "solto",
		],
		17, Paleta.VERDE if (pino_start or pino_credito) else Paleta.TINTA_LEVE
	)
	_linha(
		"Arduino (D2/D3):  START %d apertos  •  CRÉDITO %d apertos" % [serial_start, serial_credito],
		17, Paleta.VERDE if (serial_start + serial_credito) > 0 else Paleta.TINTA_LEVE
	)
	_linha(
		"portas vistas: %s" % (", ".join(portas_visiveis) if not portas_visiveis.is_empty() else "nenhuma"),
		15, Paleta.TINTA_LEVE
	)
	# POR ONDE O JOGO ESTÁ FALANDO COM A PLACA.
	#
	# Deixou de ser uma pergunta de sim ou não quando a ponte por processo
	# entrou: hoje há dois caminhos, e saber QUAL está em uso é o que
	# separa "o .dll não veio" de "o PowerShell recusou".
	var tem_serial := link != null and link.available()
	var recado_serial := link.descricao() if tem_serial else "NENHUM"
	if link != null and not link.motivo_da_falta().is_empty():
		recado_serial += " — %s" % link.motivo_da_falta()
	_linha(
		"caminho até a placa: %s" % recado_serial,
		17, Paleta.VERDE if tem_serial else Paleta.VERMELHO
	)
	# AS DUAS PERGUNTAS, SEPARADAS. "A placa respondeu" e "o sensor
	# respondeu" deixaram de ser a mesma coisa quando o firmware parou de
	# travar sem sensor — e é justamente essa separação que diz ao técnico
	# se ele deve olhar o cabo USB ou os fios do I2C.
	var sensor_online := _sensor_ligado()
	_linha(
		"sensor óptico: %s" % (
			"PRONTO — sinal atual" if sensor_online
			else ("SEM SINAL RECENTE — reconectando" if sensor_presente
			else "NÃO ENCONTRADO — confira D0=D4, A0=A0, VCC e GND")
		),
		17, Paleta.VERDE if sensor_online else Paleta.AMBAR
	)
	# O NÚMERO QUE RESPONDE "O SENSOR ESTÁ VIVO?" SEM INTERPRETAR NADA.
	#
	# Parado, perto de 0,00. Batendo no alvo, passa de 3. Se o MAIOR
	# nunca sobe quando alguém soca, o problema está antes do jogo — é
	# sensor ou fio, e nenhuma regulagem aqui resolve.
	_linha(
		"força agora: %.2f g   •   maior já visto: %.2f g   •   conta acima de %.2f g" % [
			sensor_forca, sensor_forca_maxima, sensor_gatilho
		],
		17,
		Paleta.VERDE if sensor_forca_maxima >= sensor_gatilho and sensor_gatilho > 0.0 else Paleta.AMBAR
	)
	# A ÚLTIMA RECUSA, COM OS NÚMEROS DO EVENTO. É o que diz QUAL limiar
	# está errado nesta montagem, em vez de deixar adivinhar um por vez.
	#
	# A linha aparece SEMPRE, mesmo sem recusa nenhuma. Aparecer só às
	# vezes fazia a moldura e todas as linhas abaixo dela subirem e
	# descerem 34 px sozinhas, na frente do técnico, no instante em que
	# ele lê — e uma tela que se mexe enquanto se lê é uma tela em que não
	# se confia.
	_linha(
		"última recusa: %s" % (ultima_recusa if not ultima_recusa.is_empty() else "nenhuma nesta sessão"),
		15, Paleta.AMBAR if not ultima_recusa.is_empty() else Paleta.TINTA_LEVE
	)
	# A EXTENSÃO NATIVA CARREGOU? A PERGUNTA QUE FALTAVA, e a que explica
	# o "funciona no meu PC" inteiro.
	#
	# A `gdserial` é um .dll que viaja AO LADO do executável, não dentro
	# dele — copiar só o .exe para outra máquina deixa a extensão para
	# trás. E, mesmo indo junto, ela precisa do runtime do Visual C++
	# 2015-2022 (o VCRUNTIME140.dll), que NÃO vem numa instalação limpa do
	# Windows: no PC de quem desenvolve ele está sempre lá, no PC do
	# cliente quase nunca. Nos dois casos o Windows recusa o .dll em
	# silêncio, sem erro nenhum na tela.
	#
	# Isso não derruba mais a máquina — a ponte assume e o jogo trabalha
	# igual. Mas o técnico precisa poder LER isso, porque é a diferença
	# entre "esta máquina está usando o plano B" e "esta máquina está
	# quebrada".
	# O ANDAMENTO DA BUSCA, EM NÚMEROS.
	#
	# "PROCURANDO ARDUINO…" parado na tela não diz se a máquina está
	# procurando ou travada — e essa dúvida sozinha já custou noites de
	# gabinete. O número da volta subindo é a prova de que a busca está
	# viva, e é o que se lê ao telefone.
	_linha(
		"busca: volta %d  •  porta %d de %d" % [
			_varreduras + 1, _porta_da_vez, _fila_de_portas.size(),
		],
		15, Paleta.TINTA_LEVE
	)
	# O backend Android e unico; quedas repetidas indicam cabo, hub ou fonte.
	var religadas_da_ponte: int = _quedas_do_caminho.size()
	_linha(
		"quedas USB %d ×  •  backend recriado %d ×" % [religadas_da_ponte, _trocas_de_caminho],
		15, Paleta.TINTA_LEVE if (religadas_da_ponte + _trocas_de_caminho) < 4 else Paleta.AMBAR
	)
	# A PORTA FIXADA, E QUANTO CRÉDITO AINDA RESTA A ELA. Fixar uma porta
	# errada era o jeito mais fácil de matar a máquina, e não havia como
	# ver isso em lugar nenhum.
	_linha(
		"porta escolhida: %s" % (
			"automática (varre todas)" if porta_configurada.is_empty()
			else "%s — %d falha(s); %s" % [
				porta_configurada, _falhas_da_porta_fixa,
				"ainda exclusiva" if _falhas_da_porta_fixa < FALHAS_ATE_SOLTAR_A_PORTA_FIXA
				else "liberada, varrendo todas"
			]
		),
		15, Paleta.TINTA_LEVE if porta_configurada.is_empty() else Paleta.CIANO
	)
	_linha(
		"sistema: %s  •  velocidade %d bauds" % [OS.get_name(), GameDef.SERIAL_BAUD],
		15, Paleta.TINTA_LEVE
	)

	# ---- O QUE A MÁQUINA ESTÁ ENTREGANDO DE VERDADE
	#
	# "A animação está travada" é a queixa mais difícil de consertar,
	# porque quem programa nunca vê: aqui roda liso, e o gabinete tem
	# outro vídeo, outra TV, outra resolução. Sem número, o conserto vira
	# palpite. Estas quatro linhas são o número — e é o que se manda para
	# quem for consertar, em vez de "está travado".
	var caixa_ritmo := Rect2(80, DADOS_RITMO_Y, 920, _altura_da_pilha(4) + 76.0)
	_secao(caixa_ritmo, "RITMO DA MÁQUINA", Paleta.VERDE)
	_pilha(caixa_ritmo)
	var fps := desempenho.fps()
	var cor_fps := Paleta.VERDE if fps >= 55.0 else (Paleta.AMBAR if fps >= 40.0 else Paleta.VERMELHO)
	_linha(
		"%.0f quadros por segundo  •  pior quadro %.1f ms  •  efeitos em %d%%" % [
			fps, desempenho.pior_ms(), int(round(desempenho.qualidade * 100.0))
		],
		20, cor_fps
	)
	_linha(
		"%d chamadas de desenho  •  %d primitivas por quadro" % [
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		],
		17, Paleta.TINTA_LEVE
	)
	# A ESCALA DENUNCIA A TELA DEITADA.
	#
	# O jogo é 1080x1920 em pé. Numa TV deitada, o Godot encolhe tudo
	# para caber na altura e sobra tarja preta dos dois lados: a letra
	# fica com metade dos pixels e a máquina parece de baixa qualidade
	# sem nada estar errado no jogo. Escala 1,00 é a TV girada certo.
	var escala := get_window().get_final_transform().get_scale()
	var aviso := "" if absf(escala.y - 1.0) < 0.02 else "  ← GIRE A TELA PARA 1080x1920"
	_linha(
		"janela %dx%d  •  escala %.2f%s" % [
			DisplayServer.window_get_size().x, DisplayServer.window_get_size().y, escala.y, aviso
		],
		17, Paleta.TINTA_LEVE if aviso.is_empty() else Paleta.AMBAR
	)
	_linha(
		"câmera: %s" % (camera_service.status if camera_service != null else "—"),
		17, Paleta.CIANO
	)
	# O TETO À MÃO, para quando o automático errar. Ele acerta na maioria
	# das máquinas e erra em duas: num PC que oscila, ficando subindo e
	# descendo a qualidade o tempo todo, e num PC bom em que o operador
	# prefere menos efeito por gosto.
	_botao(
		BOTOES_SIMPLES["teto_efeitos"], "EFEITOS: %s" % desempenho.teto,
		desempenho.teto != "AUTO", Paleta.ROXO, 17
	)

	# APAGAR MOSTRA O QUE ESTÁ FAZENDO.
	#
	# O clique sumia com o ranking e devolvia a tela; as fotos saíam de
	# fininho (ou nem saíam). Sem número na tela, "apagou tudo?" só tinha
	# uma resposta possível: abrir a pasta pelo Windows. Agora a linha e
	# a barra contam a faxina inteira, e continuam contando se o operador
	# sair da Central e voltar.
	_secao(Rect2(80, DADOS_APAGAR_Y, 920, 218), "APAGAR (PEDE CONFIRMAÇÃO)", Paleta.VERMELHO)
	_botao(BOTOES_SIMPLES["zerar"], "CONTADORES", false, Paleta.VERMELHO, 14)
	_botao(BOTOES_SIMPLES["zerar_stats"], "ESTATÍSTICAS", false, Paleta.ROXO, 14)
	_botao(
		BOTOES_SIMPLES["zerar_ranking"],
		"APAGANDO…" if faxina.rodando else "RANKING + FOTOS",
		false, Paleta.VERMELHO, 13, faxina.rodando
	)
	_botao(BOTOES_SIMPLES["reconectar"], "RECONECTAR", false, Paleta.CIANO, 14)
	var base_faxina := DADOS_APAGAR_Y + 166.0
	_andamento(
		Rect2(110, base_faxina - 16.0, 860, 10), faxina.progresso(),
		Paleta.AMBAR if faxina.rodando else Paleta.VERDE
	)
	_texto(
		faxina.ficha() if faxina.total > 0 else "a pasta guarda a foto de quem já saiu do ranking; o RANKING + FOTOS leva todas",
		base_faxina + 24.0, 15,
		Paleta.AMBAR if faxina.rodando else Paleta.TINTA_LEVE,
		HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)

## UMA PILHA DE LINHAS DENTRO DE UMA SEÇÃO DA CENTRAL.
##
## Enquanto cada linha trouxe o seu `y` escrito à mão, esta tela escondeu
## sobreposições que ninguém via lendo o código: duas frases na mesma
## linha de base desenham UMA POR CIMA DA OUTRA, e qual delas fica por
## cima muda com a fonte e a escala da TV. O técnico lê duas frases
## embaralhadas e não tem como desconfiar da tela.
##
## Com a pilha, a linha seguinte nasce da anterior e a moldura nasce da
## contagem. `tests/test_central_legivel.gd` mede o resultado desenhando
## a Central de verdade e cruzando os retângulos de cada texto.
const PILHA_PASSO := 34.0    # de uma linha de base à seguinte
const PILHA_TOPO := 40.0     # do topo da moldura até o título da seção
const PILHA_RODAPE := 20.0   # da última linha até o fim da moldura

## Altura de uma moldura que vai guardar `linhas` linhas além do título.
func _altura_da_pilha(linhas: int, extra := 0.0) -> float:
	return PILHA_TOPO + PILHA_PASSO * float(linhas) + PILHA_RODAPE + extra

var _pilha_y := 0.0

## Abre a pilha no título da seção; a primeira `_linha` cai logo abaixo.
func _pilha(rect: Rect2) -> void:
	_pilha_y = rect.position.y + PILHA_TOPO

## Mais uma linha da pilha. Devolve a linha de base usada.
func _linha(texto: String, tamanho: int, cor: Color) -> float:
	_pilha_y += PILHA_PASSO
	_texto(texto, _pilha_y, tamanho, cor, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0)
	return _pilha_y

# ------------------------------------------------------- SACO E MOTOR
## A PÁGINA DO MOTOR QUE BAIXA E LEVANTA O SACO.
##
## Ela existe porque um motor não é um LED. Um LED aceso por engano é um
## LED aceso; um motor ligado por engano é uma correia arrebentada, um
## saco no chão ou um fim de curso destruído — e isso acontece longe de
## quem programou, numa festa, às onze da noite, com o operador olhando
## uma tela que não conta nada.
##
## Então esta página conta tudo: se a função está ligada, onde o saco
## está AGORA, quanto falta do curso em uma barra que anda, o que a
## placa respondeu por último, e os três botões de mando à mão para quem
## está montando a máquina. O botão PARAR responde sempre, inclusive com
## a função desligada.
func _central_maquina() -> void:
	# ---- LIGAR, E DIZER O QUE ISSO MUDA
	_secao(Rect2(80, 350, 920, 200), "MOTOR DO SACO", Paleta.ROXO)
	_botao(
		BOTOES_SIMPLES["motor_ligado"],
		"LIGADO" if saco.ligado else "DESLIGADO",
		saco.ligado, Paleta.VERDE if saco.ligado else Paleta.TINTA_FRACA, 22
	)
	# O FIM DE CURSO É UMA ESCOLHA DE MONTAGEM, não um gosto.
	#
	# Com as duas chaves instaladas, a placa para no instante em que o
	# saco chega — é o certo. Sem elas (montagem mais simples, ou uma
	# chave que quebrou no meio da festa), sobra o tempo de curso, e a
	# máquina continua funcionando enquanto a peça não chega.
	_botao(
		BOTOES_SIMPLES["motor_fim_curso"],
		"FINS DE CURSO: SIM" if saco.fim_de_curso else "FINS DE CURSO: NÃO",
		saco.fim_de_curso, Paleta.CIANO, 18
	)
	_texto(
		"O saco desce no START e sobe quando os dois socos terminam. Sem motor, o jogo é exatamente o mesmo.",
		522.0, 15, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)

	# ---- OS DOIS NÚMEROS QUE A PLACA PRECISA CONHECER
	_secao(Rect2(80, 590, 920, 266), "TEMPOS DO CURSO", Paleta.AMBAR)
	_stepper("curso_motor", "%.1f s" % (saco.curso_ms / 1000.0), "TEMPO DE CURSO", Paleta.AMBAR)
	_stepper("pausa_motor", "%d ms" % saco.pausa_ms, "PAUSA AO INVERTER", Paleta.CIANO)
	# ESTE É O FREIO DE SEGURANÇA, e o técnico precisa ler isso na tela.
	# Quem regula um "tempo" sem saber que ele DESLIGA o motor o encurta
	# achando que está acelerando a descida — e passa a ter um saco que
	# para no meio do caminho toda vez.
	_texto(
		"Passado o tempo de curso, a placa DESLIGA o motor sozinha, mesmo sem fim de curso.",
		826.0, 15, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)

	# ---- MANDAR À MÃO, PARA MONTAR E PARA CONSERTAR
	_secao(Rect2(80, 890, 920, 190), "MANDO À MÃO", Paleta.CIANO)
	var pode := saco.ligado and link != null and link.is_open()
	_botao(BOTOES_SIMPLES["motor_desce"], "DESCER", false, Paleta.CIANO, 20, not pode)
	_botao(BOTOES_SIMPLES["motor_sobe"], "SUBIR", false, Paleta.CIANO, 20, not pode)
	# PARAR NUNCA FICA DESBOTADO. É o botão de emergência da página, e um
	# botão de emergência que às vezes não responde não é botão de
	# emergência — ele vale com a função desligada e sem curso em
	# andamento.
	_botao(BOTOES_SIMPLES["motor_para"], "PARAR", false, Paleta.VERMELHO, 20)
	_texto(
		"Use com o gabinete aberto para acertar a altura do saco e conferir os fins de curso.",
		1052.0, 15, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)

	# ---- O QUE ESTÁ ACONTECENDO AGORA
	var caixa_estado := Rect2(80, SACO_ESTADO_Y, 920, SACO_ESTADO_H)
	_secao(caixa_estado, "ONDE O SACO ESTÁ", Paleta.VERDE)
	var cor_estado := Paleta.TINTA_LEVE
	if saco.desistiu():
		cor_estado = Paleta.VERMELHO
	elif saco.andando():
		cor_estado = Paleta.AMBAR
	elif saco.ligado:
		cor_estado = Paleta.VERDE
	# A BARRA ANDA DE VERDADE: ela vem do `resta_ms` que a própria placa
	# manda a cada relatório, não de um relógio daqui. Uma barra animada
	# por conta própria continuaria andando com o cabo arrancado, e é
	# justamente aí que ela precisa parar.
	# A BARRA CHEIA SÓ QUANDO O SACO ESTÁ ONDE SE SABE QUE ELE ESTÁ.
	#
	# `progresso()` devolve 1 com o motor parado, o que é certo para o
	# fim de um curso e MENTIRA com a função desligada: uma barra cheia
	# embaixo de "MOTOR DESLIGADO" se lê como "pronto, chegou", quando o
	# jogo não faz ideia de onde o saco está.
	var quanto := 0.0
	if saco.andando():
		quanto = saco.progresso()
	elif saco.ligado and saco.posicao != ArduinoProtocol.POS_DESCONHECIDA:
		quanto = 1.0
	_andamento(Rect2(110, 1176, 860, 12), quanto, cor_estado)
	_pilha(caixa_estado)
	_pilha_y += 34.0
	_linha(saco.ficha(), 20, cor_estado)
	_linha(
		"placa diz: %s  •  %s" % [
			ArduinoProtocol.nome_do_estado(saco.estado),
			ArduinoProtocol.nome_da_posicao(saco.posicao),
		],
		16, Paleta.TINTA_LEVE
	)
	_linha(
		"resta do curso: %d ms  •  curso ajustado: %d ms" % [saco.resta_ms, saco.curso_ms],
		15, Paleta.TINTA_LEVE
	)
	_linha(
		"caminho até a placa: %s" % (
			link.descricao() if link != null and link.is_open() else "NENHUM — o motor não responde"
		),
		15, Paleta.VERDE if link != null and link.is_open() else Paleta.VERMELHO
	)

	# ---- QUANDO A PLACA NÃO CONFIRMA
	#
	# `SacoMotor` desiste depois de um tempo sem confirmação, de
	# propósito: insistir para sempre É o laço infinito com outro nome, e
	# foi exatamente o que se pediu para não existir aqui. Desistir, por
	# outro lado, não pode ser definitivo — senão um fio que alguém
	# reencaixa em dez segundos deixa o saco parado até alguém fechar o
	# jogo.
	_secao(Rect2(80, SACO_SOCORRO_Y, 920, 176), "SE O MOTOR NÃO RESPONDER", Paleta.VERMELHO)
	_botao(BOTOES_SIMPLES["motor_destrava"], "TENTAR DE NOVO", false, Paleta.AMBAR, 18, not saco.desistiu())
	_texto(
		"O jogo desiste depois de %.0f s sem confirmação, em vez de insistir para sempre." % (
			SacoMotor.FOLGA_DA_CONFIRMACAO_MS / 1000.0
		),
		SACO_SOCORRO_Y + 158.0, 15, Paleta.TINTA_LEVE, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 860.0
	)

## Os índices achados, em uma linha. Escrito à mão porque um `map` com
## lambda aqui não deixa o GDScript inferir o tipo, e tipo inferido é o
## que faz este arquivo compilar rápido.
func _lista_de_indices(valores: Array) -> String:
	var partes := PackedStringArray()
	for v in valores:
		partes.append(str(v))
	return ", ".join(partes)

## Manda examinar a instalação da câmera. `instalar` autoriza mexer no
## sistema; sem ele o exame só olha e conta.
## O SOCORRO: A MÁQUINA SE EXAMINA SOZINHA.
##
## Até aqui o diagnóstico era um botão, e um botão só serve para quem
## sabe que ele existe, sabe abrir a Central e está na frente do
## gabinete. Quem liga a máquina no salão às oito da noite não é essa
## pessoa — e uma câmera que não sobe ficava sem imagem a noite inteira
## sem ninguém saber por quê.
##
## Doze segundos depois de ligar, se ainda não veio quadro nenhum, a
## máquina roda o exame por conta própria e ADOTA o que descobrir: o
## índice, o back-end e o interpretador. Uma vez por sessão — se o exame
## não resolveu, repeti-lo de minuto em minuto não resolve também, e
## ainda ocupa a linha de execução no meio das partidas.
const SOCORRO_ESPERA := 12.0
var _socorro_relogio := 0.0
var _socorro_feito := false

func _socorro_da_camera(delta: float) -> void:
	if _socorro_feito or camera_service == null or medico == null:
		return
	if not camera_enabled or camera_service.available():
		# Já veio imagem: não há o que socorrer, e a contagem não recomeça
		# — uma câmera que caiu depois de funcionar é caso da religação
		# automática da ponte, não do exame.
		_socorro_feito = camera_service.available()
		return
	_socorro_relogio += delta
	if _socorro_relogio < SOCORRO_ESPERA or medico.rodando:
		return
	_socorro_feito = true
	_examinar_camera(false)

func _examinar_camera(resolver: bool) -> void:
	if medico == null or medico.rodando:
		return
	# A consulta PowerShell não abre o fluxo de vídeo; a prévia permanece
	# ligada durante o diagnóstico e não há disputa pelo dispositivo.
	medico.diagnosticar(resolver, "", camera_service.caminho_do_inspetor())
	_show_notice("EXAMINANDO — A RESPOSTA APARECE NA TELA")

## Terminado o exame, a máquina AGE com o que descobriu: se achou câmera
## num índice, passa a usar aquele índice e reabre. Um relatório que
## exige o técnico repetir à mão o que a máquina acabou de descobrir é
## meio relatório.
func _fim_do_exame() -> void:
	if medico.indices.is_empty():
		if camera_enabled and not medico.linhas.is_empty():
			_show_notice(str(medico.linhas[medico.linhas.size() - 1]))
		return
	camera_index = int(medico.indices[0])
	camera_service.selected_index = camera_index
	camera_enabled = true
	camera_service.enabled = true
	camera_service.procurar_de_novo()
	_salvar()
	_show_notice("CÂMERA USB SELECIONADA")

## As cinco marcas em uma linha só: o técnico precisa VER o que vai
## apagar antes de apertar ZERAR RANKING.
func _lista_do_ranking(rect: Rect2) -> void:
	var largura := (rect.size.x - 4.0 * 10.0) / 5.0
	for i in range(5):
		var celula := Rect2(rect.position + Vector2(i * (largura + 10.0), 0.0), Vector2(largura, rect.size.y))
		var cor := _cor_da_posicao(i + 1)
		var tem := i < ranking.size()
		_cartao(celula, Paleta.tinta_clara(cor, 0.14) if tem else Paleta.VAZIO, Paleta.CARTAO_BORDA, 1.0, 0.0)
		_texto("%dº" % (i + 1), celula.position.y + 26.0, 13, Color(Paleta.para_texto(cor)), HORIZONTAL_ALIGNMENT_CENTER, celula.position.x, celula.size.x)
		_texto(
			"%04d" % RankingStore.score_at(ranking, i) if tem else "—", celula.position.y + 62.0, 22,
			Paleta.TINTA if tem else Paleta.TINTA_LEVE,
			HORIZONTAL_ALIGNMENT_CENTER, celula.position.x, celula.size.x
		)

## Uma seção da Central: moldura e título, sempre no mesmo lugar em
## relação à caixa. Nenhuma seção precisa saber onde fica o seu rótulo.
func _secao(rect: Rect2, titulo: String, cor := Paleta.MARINHO) -> void:
	# A seção mais baixa da página é o que define até onde a rolagem vai.
	# Medir aqui, e não numa tabela de alturas, é o que faz a rolagem
	# continuar certa quando alguém mover uma seção daqui a seis meses.
	central_fundo = maxf(central_fundo, rect.end.y)
	_cartao(rect, Paleta.tinta_clara(Paleta.MARINHO, 0.045), Paleta.CARTAO_BORDA, 1.0, 0.0)
	# Tarja colorida na lateral: com sete seções empilhadas, é o que deixa
	# o técnico achar a que procura sem ler todos os títulos.
	draw_rect(Rect2(rect.position, Vector2(8.0, rect.size.y)), cor)
	_texto(titulo, rect.position.y + 40.0, 16, Paleta.para_texto(cor), HORIZONTAL_ALIGNMENT_LEFT, rect.position.x + 40.0, rect.size.x - 80.0)

## Um par − / + com o valor no meio e a legenda embaixo. Os retângulos
## saem de `PASSOS`, os mesmos que o clique consulta — texto e área de
## toque não têm como divergir.
func _stepper(chave: String, valor: String, legenda: String, accent: Color) -> void:
	var visor := _passo_visor(chave)
	_cartao(visor, Paleta.CARTAO, Paleta.CARTAO_BORDA, 1.0, 0.0)
	_botao(_passo_menos(chave), "−", false, accent, 26)
	_botao(_passo_mais(chave), "+", false, accent, 26)
	_texto_cabendo(valor, visor.position.y + visor.size.y * 0.68, 30, Paleta.TINTA, visor.size.x - 12.0, visor.position.x + 6.0)
	var r: Rect2 = PASSOS[chave]
	_texto(legenda, r.end.y + 28.0, 15, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_CENTER, r.position.x, r.size.x)

## O seletor do Arduino mostra porta, modo e busca como um único componente.
## A lógica e as áreas de toque continuam sendo exatamente as do stepper.
func _seletor_porta_refinado() -> void:
	var r: Rect2 = PASSOS["porta"]
	var visor := _passo_visor("porta")
	# A COR E A ANIMAÇÃO VÊM DA FASE, e não de procurar palavras dentro
	# do texto da tela. Ver `fase_serial`.
	var fase := fase_serial()
	var procurando := fase in [FaseSerial.PROCURANDO, FaseSerial.OUVINDO]
	var cor := Paleta.AMBAR
	match fase:
		FaseSerial.LIGADA:
			cor = Paleta.VERDE if _sensor_ligado() else Paleta.CIANO
		FaseSerial.CALIBRANDO:
			cor = Paleta.AMBAR
		FaseSerial.PROCURANDO, FaseSerial.OUVINDO:
			cor = Paleta.CIANO
		FaseSerial.SEM_CAMINHO:
			cor = Paleta.VERMELHO

	_cartao(r.grow(7.0), Color("12070d"), Color(cor, 0.42), 1.0, 1.5)
	draw_rect(Rect2(r.position.x - 7.0, r.position.y + 10.0, 3.0, r.size.y - 20.0), Color(cor, 0.90))
	_botao(_passo_menos("porta"), "‹", false, cor, 27)
	_botao(_passo_mais("porta"), "›", false, cor, 27)
	_cartao(visor, Color("190b12"), Color(cor, 0.22), 1.0, 0.0)

	var centro := Vector2(visor.position.x + 27.0, visor.get_center().y)
	# A COMEMORAÇÃO: um anel que abre a partir da lâmpada no instante em
	# que a placa responde. Dura um segundo e meio e serve a uma coisa
	# só — quem estava olhando para o conector, e não para a tela, vê
	# pelo canto do olho que a máquina achou.
	var festa := clampf(1.0 - (animation_time - _placa_achada_em) / 1.5, 0.0, 1.0)
	if festa > 0.0:
		var onda := ease(1.0 - festa, 0.4)
		draw_arc(centro, 9.0 + onda * 18.0, 0.0, TAU, 28,
			Color(Paleta.VERDE, festa * 0.75), 2.0 + festa * 1.5, true)
	draw_circle(centro, 5.0 + festa * 3.0, Color(cor, 0.20 + festa * 0.5), true, -1.0, true)
	draw_circle(centro, 2.4, cor, true, -1.0, true)
	if procurando:
		var inicio := fmod(animation_time * 3.2, TAU)
		draw_arc(centro, 9.0, inicio, inicio + 1.75, 16, Color(cor, 0.82), 1.2, true)

	var porta := porta_configurada if not porta_configurada.is_empty() else "AUTO"
	# O NOME DA PORTA E A LEGENDA DIVIDIAM UM VISOR DE 64 PX, a 16 px um
	# do outro, com o nome em corpo 25: a legenda entrava pela barriga
	# das letras de cima e nenhuma das duas se lia. Não era questão de
	# afastar mais — as duas linhas não cabem nessa altura, e insistir
	# nisso só trocaria a sobreposição por um rodapé colado na borda.
	#
	# A legenda desceu para a linha de ajuda, onde havia espaço e onde
	# ela ainda diz o que precisa dizer. O visor ficou com o nome da
	# porta, centrado, que é o que se lê de longe.
	#
	# Só apareceu quando a auditoria passou a enxergar `_texto_cabendo`:
	# até então, todo rótulo de botão e todo valor de visor eram um ponto
	# cego do teste.
	_texto_cabendo(porta, visor.position.y + 43.0, 25, Paleta.TINTA, visor.size.x - 72.0, visor.position.x + 46.0)

	draw_circle(Vector2(126.0, 1431.0), 4.0, cor, true, -1.0, true)
	_texto_cabendo(serial_status, 1437.0, 14, Paleta.para_texto(cor), 822.0, 140.0)
	_texto(
		(
			"BUSCA AUTOMÁTICA — o jogo continua aberto e reconecta sozinho"
			if porta_configurada.is_empty()
			else "PORTA PREFERENCIAL — o jogo continua aberto e reconecta sozinho"
		),
		r.end.y + 27.0, 13, Paleta.TINTA_FRACA,
		HORIZONTAL_ALIGNMENT_CENTER, r.position.x, r.size.x
	)

## A RÉGUA DOS OITO NÍVEIS, na largura de cada um.
##
## Ela é de LEITURA: as faixas são fixas e não há o que arrastar aqui. O
## que ela mostra é a desproporção — os quatro níveis de cima ocupam um
## quinto da escala, e é vendo isso que o técnico entende por que quase
## ninguém chega ao topo, em vez de achar que a máquina está quebrada.
func _regua_dos_niveis(rect: Rect2) -> void:
	var teto := float(GameDef.SCORE_MAX + 1)
	for nivel in ScoreTier.NIVEIS:
		var x0 := rect.position.x + rect.size.x * (float(nivel["min"]) / teto)
		var x1 := rect.position.x + rect.size.x * (float(int(nivel["max"]) + 1) / teto)
		draw_rect(Rect2(x0, rect.position.y, x1 - x0, rect.size.y), nivel["cor"] as Color)
		if x1 - x0 > 96.0:
			# Preto sobre cor clara, branco sobre cor escura. A cor do
			# nível é dado de projeto e vai de creme a azul-acinzentado:
			# um contraste fixo apagaria metade dos nomes.
			var cor: Color = nivel["cor"]
			var tinta := Color.BLACK if cor.get_luminance() > 0.55 else Color.WHITE
			_texto(
				str(nivel["nome"]), rect.position.y + rect.size.y * 0.70, 14, tinta,
				HORIZONTAL_ALIGNMENT_CENTER, x0, x1 - x0
			)
	draw_rect(rect, Paleta.CARTAO_BORDA, false, 2.0)
	# O teto da escala fica marcado à direita: é o único ponto da régua
	# que uma pessoa pode alcançar e não é uma faixa, é um alvo.
	_texto("9999", rect.end.y + 22.0, 15, Paleta.CREME, HORIZONTAL_ALIGNMENT_RIGHT, rect.position.x, rect.size.x)
	_texto("0000", rect.end.y + 22.0, 15, Paleta.TINTA_FRACA, HORIZONTAL_ALIGNMENT_LEFT, rect.position.x, rect.size.x)

## Retângulo de cantos redondos. O Godot só desenha retângulo de canto
## vivo, e canto vivo em peça grande destoa do resto da tela — a placa,
## os cartões e os botões todos precisam da mesma família de formas.
func _placa(rect: Rect2, raio: float, cor: Color) -> void:
	Traco.poligono(self, _contorno_arredondado(rect, raio), cor)

func _contorno_arredondado(rect: Rect2, raio: float) -> PackedVector2Array:
	var r := minf(raio, minf(rect.size.x, rect.size.y) * 0.5)
	var pontos := PackedVector2Array()
	var cantos := [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
	]
	for c in cantos:
		var meio: Vector2 = c[0]
		var a0: float = c[1]
		for i in range(9):
			var a := a0 + float(i) / 8.0 * PI * 0.5
			pontos.append(meio + Vector2(cos(a), sin(a)) * r)
	return pontos

func _photo_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _photo_cache.has(path):
		return _photo_cache[path] as Texture2D
	if not FileAccess.file_exists(path):
		return null
	# NÃO DECODIFICADA AINDA: melhor um quadro sem foto (o contorno de
	# `_draw_avatar`) do que travar o quadro atual para decodificar na
	# hora. `_agendar_decodificacao` já deve ter posto isto a caminho;
	# se ainda não pôs (foto criada agora mesmo, fora do prewarm), põe.
	_agendar_decodificacao(path)
	return null

## Roda FORA da linha do jogo -- ver o comentário de `_fotos_decodificadas`.
##
## PODE CHEGAR CEDO DEMAIS: a foto do ranking agora é gravada em segundo
## plano por `camera_service.gd` (ver o comentário lá), e o prewarm daqui
## pode rodar antes de o arquivo existir. Por isso o "não encontrei"
## também é reportado -- com `false` em vez de uma imagem -- para
## `_colher_fotos_decodificadas` liberar uma NOVA tentativa, em vez de
## marcar este caminho como "em andamento" para sempre e nunca mais
## tentar de novo.
func _decodificar_foto(path: String) -> void:
	var imagem: Variant = false
	if FileAccess.file_exists(path):
		var candidata := Image.new()
		if candidata.load(ProjectSettings.globalize_path(path)) == OK and not candidata.is_empty():
			# As fotos são miniaturas na tabela. Limita o upload e a memória
			# sem alterar o arquivo original; o resize ocorre no worker.
			var maior := maxi(candidata.get_width(), candidata.get_height())
			if maior > 384:
				var fator := 384.0 / float(maior)
				candidata.resize(maxi(1, int(candidata.get_width() * fator)),
					maxi(1, int(candidata.get_height() * fator)), Image.INTERPOLATE_BILINEAR)
			imagem = candidata
	_mutex_fotos.lock()
	_fotos_decodificadas[path] = imagem
	_mutex_fotos.unlock()

## Põe uma foto na fila de decodificação, uma vez só por caminho.
var _fotos_em_andamento: Dictionary = {}
func _agendar_decodificacao(path: String) -> void:
	if path.is_empty() or _photo_cache.has(path) or _fotos_em_andamento.has(path):
		return
	_fotos_em_andamento[path] = true
	WorkerThreadPool.add_task(_decodificar_foto.bind(path))

## Chamada assim que uma pontuação entra no ranking: põe as fotos que
## ainda faltam no cache a caminho, com vários segundos de folga antes
## de a tabela do Top 20 precisar mostrá-las de verdade.
func _prewarm_fotos_do_ranking() -> void:
	for entry in ranking:
		_agendar_decodificacao(str(entry.get("photo_path", "")))

## Chamada todo quadro (barata: só olha se algo terminou). Cria a
## textura -- isso sim precisa ser na linha do jogo -- a partir da
## imagem que o pool de linhas já deixou pronta. Um `false` (arquivo
## ainda não gravado, ou corrompido) só libera o caminho para uma nova
## tentativa depois -- `_photo_texture` reagenda sozinho quando alguém
## pedir essa foto de novo.
func _colher_fotos_decodificadas() -> void:
	_mutex_fotos.lock()
	if _fotos_decodificadas.is_empty():
		_mutex_fotos.unlock()
		return
	# A decodificação já acontece fora da linha principal; criar todas as
	# texturas prontas no mesmo quadro apenas transferia a travada para a
	# GPU. Publica uma por quadro e mantém as demais na fila.
	var path := str(_fotos_decodificadas.keys()[0])
	var imagem = _fotos_decodificadas[path]
	_fotos_decodificadas.erase(path)
	_mutex_fotos.unlock()
	_fotos_em_andamento.erase(path)
	if imagem is Image:
		_photo_cache[path] = ImageTexture.create_from_image(imagem)

func _draw_texture_cover(texture: Texture2D, rect: Rect2, alpha: float, mirror := false) -> void:
	if texture == null:
		return
	var source_size := texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	var source := Rect2(Vector2.ZERO, source_size)
	var source_aspect := source_size.x / source_size.y
	var target_aspect := rect.size.x / rect.size.y
	if source_aspect > target_aspect:
		var wanted_width := source_size.y * target_aspect
		source.position.x = (source_size.x - wanted_width) * 0.5
		source.size.x = wanted_width
	else:
		var wanted_height := source_size.x / target_aspect
		source.position.y = (source_size.y - wanted_height) * 0.5
		source.size.y = wanted_height
	if mirror:
		draw_set_transform(_deslocamento + Vector2(rect.end.x, rect.position.y), 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect_region(texture, Rect2(Vector2.ZERO, rect.size), source, Color(1, 1, 1, alpha))
		draw_set_transform(_deslocamento, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(texture, rect, source, Color(1, 1, 1, alpha))

## O LUGAR DA FOTO QUE AINDA NÃO EXISTE.
##
## Um círculo amarelo sobre um trapézio roxo não lê como pessoa: lê como
## erro de desenho, e ainda por cima em duas cores que não são do tema.
## Aqui é uma silhueta de ombros e cabeça, na cor da moldura, com a
## mira de enquadramento por cima — a mesma que uma câmera mostra.
## Assim o quadro vazio diz "é aqui que o seu rosto vai aparecer".
## O LUGAR DA FOTO QUE AINDA NÃO EXISTE.
##
## Ele era um boneco de massa cheia num vinho forte, e vinte deles
## empilhados na tabela do Top 20 leem como uma parede marrom na frente
## do ranking — foi essa a queixa. O que a vaga precisa dizer é "aqui vai
## uma foto", e para isso basta um contorno: linha fina, sem miolo, na
## mesma cor do resto da moldura. Presente o bastante para não virar
## buraco, discreto o bastante para não competir com nada.
func _draw_avatar(rect: Rect2, alpha: float) -> void:
	draw_rect(rect, Color("1c060c", 0.70 * alpha))
	var center := rect.get_center()
	var unit := minf(rect.size.x, rect.size.y)
	var tom := Color("6d2835", 0.55 * alpha)

	# Só o traço: cabeça e ombros em linha, sem massa.
	draw_arc(center + Vector2(0.0, -unit * 0.10), unit * 0.13, 0.0, TAU, 28, tom, unit * 0.035, true)
	draw_arc(
		center + Vector2(0.0, unit * 0.30), unit * 0.25,
		PI * 1.08, PI * 1.92, 26, tom, unit * 0.035, true
	)

	# Cantoneiras de enquadramento, como as de um visor de câmera.
	var margem := unit * 0.10
	var braco := unit * 0.14
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var canto := center + Vector2(sx * (rect.size.x * 0.5 - margem), sy * (rect.size.y * 0.5 - margem))
			draw_line(canto, canto - Vector2(sx * braco, 0.0), Color(Paleta.AMBAR, 0.55 * alpha), 4.0, true)
			draw_line(canto, canto - Vector2(0.0, sy * braco), Color(Paleta.AMBAR, 0.55 * alpha), 4.0, true)

func _draw_player_photo(rect: Rect2, path: String, alpha: float) -> void:
	var texture := _photo_texture(path)
	if texture == null:
		_draw_avatar(rect, alpha)
	else:
		_draw_texture_cover(texture, rect, alpha)
	draw_rect(rect, Color(Paleta.CIANO, alpha), false, 3.0)

## O aviso de operação ocupa o rodapé, e não o topo: no topo ele cairia
## em cima do cabeçalho, e no meio disputaria com o número.
## OS DOIS AVISOS QUE PRECISAM APARECER NA TELA DO JOGO, e não só na
## Central: sem eles a máquina não faz o que foi comprada para fazer, e
## quem está na frente dela não tem como saber por quê.
##
##   * a extensão da serial não carregou — sem ela NÃO HÁ Arduino: nem
##     botão, nem crédito, nem sensor. É o defeito que aparece só no
##     computador novo, porque no PC de quem desenvolve o .dll está
##     sempre lá;
##   * os acentos vieram duplicados — o arquivo foi corrompido na cópia,
##     e quem vê a tela procura o defeito na fonte durante horas.
##
## No rodapé, discretos, e só quando há o que dizer. Uma máquina em
## operação normal nunca os vê.
func _draw_alertas_graves() -> void:
	var recados: Array[String] = []
	if not Versao.acentos_inteiros():
		recados.append(Versao.recado_do_estrago())
	if link != null and not link.available():
		recados.append("SEM CAMINHO ATÉ O ARDUINO — START, CRÉDITO E SENSOR MORTOS")
	# Câmera é tratada na tela da pose com linguagem comum. O rodapé do jogo
	# nunca expõe DLL, pacote, backend ou instruções de manutenção ao jogador.
	if recados.is_empty():
		return
	var altura := 34.0 * float(recados.size()) + 16.0
	var caixa := Rect2(40.0, 1920.0 - altura - 8.0, 1000.0, altura)
	# Placa escura com letra âmbar: vermelho em cima do rodapé vermelho
	# some — o aviso tem de saltar do fundo, não se misturar a ele.
	draw_rect(caixa, Color("12040a", 0.94))
	draw_rect(caixa, Paleta.AMBAR, false, 2.0)
	for i in range(recados.size()):
		_texto(
			recados[i], caixa.position.y + 26.0 + float(i) * 34.0, 17, Paleta.AMBAR,
			HORIZONTAL_ALIGNMENT_CENTER, caixa.position.x, caixa.size.x
		)

## UMA BARRA DE ANDAMENTO. `quanto` vai de 0 a 1.
##
## Existe porque "está fazendo alguma coisa" e "travou" são a mesma
## imagem numa tela parada — e a diferença entre as duas é o que decide
## se o operador espera ou desliga a máquina no botão.
func _andamento(rect: Rect2, quanto: float, accent: Color) -> void:
	_cartao(rect, Paleta.VAZIO, Paleta.CARTAO_BORDA, 1.0, 0.0)
	var cheio := clampf(quanto, 0.0, 1.0) * rect.size.x
	if cheio > 1.0:
		draw_rect(Rect2(rect.position, Vector2(cheio, rect.size.y)), accent)

## A peça padrão da tela: retângulo branco com sombra e borda. Todo painel
## do jogo passa por aqui, então a "altura" das peças é a mesma em toda
## parte — e mudar a sombra do jogo inteiro é mudar uma função.
func _cartao(rect: Rect2, fundo_c: Color, borda: Color, alpha := 1.0, largura_borda := 2.0) -> void:
	draw_rect(Rect2(rect.position + Vector2(0, 4.0), rect.size), Color(Paleta.SOMBRA, Paleta.SOMBRA.a * alpha))
	draw_rect(rect, Color(fundo_c, fundo_c.a * alpha))
	if largura_borda > 0.0:
		draw_rect(rect, Color(borda, borda.a * alpha), false, largura_borda)

## Botão: colorido e cheio quando ativo, branco com borda colorida quando
## não. Num tema claro é o PREENCHIMENTO que marca o estado ligado —
## borda mais grossa sozinha não se lê de longe.
##
## `desligado` desbota o botão enquanto ele não aceita clique. Um botão
## que não responde precisa PARECER que não responde: se continuar com a
## cara de sempre, o operador clica de novo, e de novo, e conclui que a
## máquina travou — bem na hora em que ela está trabalhando.
func _botao(rect: Rect2, texto: String, ativo: bool, accent: Color, tamanho: int, desligado := false) -> void:
	var cor := Paleta.tinta_clara(accent, 0.45) if desligado else accent
	var fundo_c := cor if ativo else Paleta.CARTAO
	var tinta := Paleta.texto_sobre(fundo_c, Paleta.CARTAO if ativo else Paleta.para_texto(cor))
	if desligado:
		tinta = Paleta.TINTA_LEVE
	draw_rect(Rect2(rect.position + Vector2(0, 3.0), rect.size), Paleta.SOMBRA)
	draw_rect(rect, fundo_c)
	draw_rect(rect, Color(cor, 0.9), false, 2.0)
	_texto_cabendo(
		texto, rect.position.y + rect.size.y * 0.68, tamanho, tinta,
		rect.size.x - 20.0, rect.position.x + 10.0
	)

## Despacha o ícone pelo nome. Um `match` num lugar só evita que cada
## chamada precise saber de qual arquivo o desenho vem.
func _icone(nome: String, centro: Vector2, raio: float, cor: Color) -> void:
	match nome:
		"trofeu":
			Icones.trofeu(self, centro, raio, cor)
		"luva":
			Icones.luva(self, centro, raio, cor)
		"ficha":
			Icones.ficha(self, centro, raio, cor)
		"raio":
			Icones.raio_eletrico(self, centro, raio, cor)
		"alvo":
			Icones.alvo(self, centro, raio, cor)
		"botao":
			Icones.botao(self, centro, raio, cor)
		"estrela":
			Icones.estrela(self, centro, raio, cor)

# ---------------------------------------------------------------- texto
## Todo texto da tela passa por aqui. `y` é a LINHA DE BASE, que é como o
## Godot desenha — e é por isso que as bandas do topo do arquivo falam em
## linha de base e não em topo de caixa.
## ------------------------------------------------------------------
## A AUDITORIA DE LAYOUT.
##
## "Nenhum texto pode tapar o outro" não é uma regra que se cumpre
## olhando: são quatro páginas de Central, dezenas de rótulos, e basta
## alguém acrescentar uma linha para empurrar outra por baixo de um
## cartão. Já aconteceu duas vezes neste arquivo, e nas duas o defeito só
## apareceu numa foto da tela.
##
## Ligando esta bandeira, todo texto desenhado registra o RETÂNGULO que
## ocupa de fato — largura medida na fonte, altura do topo da maiúscula à
## barriga da minúscula. `tests/test_central_legivel.gd` percorre as
## páginas, liga isto e falha se dois retângulos se cruzarem.
##
## Ela fica DESLIGADA no jogo e não custa nada: uma comparação por texto.
var auditoria_de_layout := false
## Liga enquanto o MIOLO que rola está sendo desenhado. O cabeçalho e o
## rodapé da Central são repintados opacos por cima dele: uma linha que
## caia fora da janela não é lida por ninguém, e acusá-la seria apontar
## um defeito que não existe — ao mesmo tempo em que os botões do rodapé,
## esses sim sempre visíveis, precisam continuar sendo medidos.
var _auditando_o_miolo := false
var auditoria: Array[Dictionary] = []

func _anotar_texto(
	texto: String, y: float, corpo: int, alinhamento: int, x: float, largura: float
) -> void:
	if texto.strip_edges().is_empty():
		return
	var medida := fonte_texto.get_string_size(texto, alinhamento, largura, corpo)
	var esquerda := x
	if alinhamento == HORIZONTAL_ALIGNMENT_CENTER:
		esquerda = x + (largura - medida.x) * 0.5
	elif alinhamento == HORIZONTAL_ALIGNMENT_RIGHT:
		esquerda = x + largura - medida.x
	# `y` é a LINHA DE BASE, e não o topo: o retângulo sobe pelo ascendente
	# e desce pelo descendente. Tratar `y` como topo — o erro natural —
	# daria uma caixa deslocada para baixo por quase um corpo inteiro, e a
	# auditoria acusaria sobreposições que não existem enquanto deixaria
	# passar as que existem.
	var acima := fonte_texto.get_ascent(corpo)
	var abaixo := fonte_texto.get_descent(corpo)
	if _auditando_o_miolo and (y - acima < CENTRAL_TOPO or y + abaixo > CENTRAL_BASE):
		# Fora da janela que rola: as faixas opacas cobrem esta linha
		# inteira. Ela volta à vista quando o operador rolar a página, e
		# aí já não há faixa nenhuma sobre ela.
		return
	auditoria.append({
		"rect": Rect2(esquerda, y - acima, medida.x, acima + abaixo),
		"texto": texto, "corpo": corpo,
	})

func _texto(
	texto: String, y: float, tamanho: int, cor: Color,
	alinhamento := HORIZONTAL_ALIGNMENT_CENTER, x := MARGEM, largura := LARGURA_UTIL
) -> void:
	var corpo := _corpo(tamanho)
	if auditoria_de_layout:
		_anotar_texto(texto, y, corpo, alinhamento, x, largura)
	draw_string(fonte_texto, Vector2(x, y), texto, alinhamento, largura, corpo, cor)

## COMPENSAÇÃO DE ALTURA ENTRE AS DUAS LETRAS.
##
## "Tamanho 26" no Godot é a altura da CAIXA da fonte, não a altura da
## letra. A maiúscula da Bungee ocupa 0,720 dessa caixa; a da Saira
## Condensed, 0,688 (medido nas próprias tabelas dos arquivos). Pedir 26
## nas duas desenharia letras de alturas diferentes, e todas as posições
## desta tela foram acertadas com a altura da Bungee.
##
## Este fator devolve a altura: 0,720 / 0,688. Ele NÃO é um "deixa maior
## porque ficou pequeno" — é a conta que faz 26 continuar valendo 26.
const CAIXA_LEITURA := 1.047

## O PISO DO CORPO DE LETRA.
##
## Havia texto a 14 e a 15 px numa tela de 1080 de largura, vista de pé,
## a um metro e meio de distância. Isso não é letra miúda: é letra que
## não se lê, e a pessoa desiste antes de tentar. Dezoito é o menor corpo
## em que a Saira Condensed ainda separa o "0" do "O" nessa distância —
## abaixo disso não adianta melhorar o desenho, tem de crescer.
##
## Quem pede menos que o piso recebe o piso. É por isso que existe um
## piso e não uma revisão de cada chamada: com quarenta lugares pedindo
## tamanho, a próxima linha escrita com 14 voltaria a ser ilegível.
const CORPO_MINIMO := 20

## A ESCALA TIPOGRÁFICA — E POR QUE ELA PRECISA EXISTIR.
##
## Contados, havia TRINTA corpos de letra diferentes pedidos pela tela:
## 13, 14, 15, 16, 18, 20, 22, 24, 25, 26, 28, 30, 32, 34, 36, 38, 42, 44,
## 46, 50, 52, 54, 56, 58, 62, 72, 88, 96, 100, 104… Nenhum deles se
## relaciona com o vizinho; cada um nasceu de um ajuste solto num dia
## diferente. É exatamente isso que dá a impressão de "coisas novas que
## não estão uniformes": 15 e 16 são o MESMO tamanho para o olho, mas os
## dois juntos na mesma tela leem como desalinho, não como hierarquia.
##
## Uma escala resolve com poucos degraus, cada um claramente diferente do
## anterior. Esta cresce a cerca de 1,25× por passo — o intervalo em que
## dois tamanhos vizinhos se distinguem sem brigar:
##
##   MIÚDO 20 · APOIO 25 · RÓTULO 31 · CORPO 39 · DESTAQUE 48
##   TÍTULO 60 · CARTAZ 75 · PLACAR 94 · HERÓI 118
##
## COMO ELA É APLICADA SEM REESCREVER CENTO E CINQUENTA CHAMADAS. Todo
## texto do jogo passa por `_corpo`, e é aqui que o tamanho pedido é
## ENCAIXADO no degrau mais próximo. Um 15 e um 16 viram os dois 20; um 34
## e um 36 viram os dois 39. A tela inteira passa a falar em nove
## tamanhos, e uma linha nova escrita com um número solto continua caindo
## na escala sozinha — que é o único jeito de isto não se desfazer na
## próxima alteração.
const ESCALA := [20, 25, 31, 39, 48, 60, 75, 94, 118]

func _corpo(tamanho: int) -> int:
	var pedido := tamanho if fonte_texto == fonte else int(round(float(tamanho) * CAIXA_LEITURA))
	return _encaixar_na_escala(maxi(CORPO_MINIMO, pedido))

## O degrau mais próximo, por distância relativa — em tipografia o que o
## olho compara é a RAZÃO entre dois tamanhos, não a diferença: de 20 para
## 25 é o mesmo salto que de 75 para 94.
func _encaixar_na_escala(tamanho: int) -> int:
	var melhor: int = ESCALA[0]
	var menor_erro := 1.0e30
	for degrau in ESCALA:
		var erro: float = absf(log(float(tamanho) / float(degrau)))
		if erro < menor_erro:
			menor_erro = erro
			melhor = degrau
	# Acima do maior degrau a escala não manda: o placar herói e os
	# números gigantes do impacto são desenhados no tamanho que couber na
	# largura da tela, e encaixá-los aqui os encolheria à toa.
	return maxi(melhor, tamanho) if tamanho > int(ESCALA[ESCALA.size() - 1]) else melhor

## O CACHE DE `_tamanho_que_cabe`.
##
## Esta tela inteira é desenhada à mão, num `_draw()` só, chamado TODO
## quadro — e antes disso aqui era recalculado todo quadro também, para
## todo texto que encolhe: até a palavra "CALIBRAÇÃO", que nunca muda de
## letra nem de largura entre um quadro e o outro, media de novo a cada
## quadro. Cada medição é uma busca linear que pode chegar a quarenta e
## poucas chamadas a `get_string_size`, e a primeira vez que a fonte vê um
## tamanho novo ela ainda desenha o glifo (rasteriza), o que custa muito
## mais que uma medição comum. Era exatamente esse custo, repetido sem
## necessidade a cada quadro, que travava a entrada da tabela de
## classificação e a montagem do letreiro na abertura.
##
## A chave inclui o texto, o teto de tamanho, a largura disponível e a
## fonte usada: as quatro coisas de que o resultado da busca depende. Só
## se elas mudarem — outro placar, outra frase — o cálculo roda de novo.
## Um teto de entradas evita que a máquina, ligada o dia inteiro, acumule
## uma entrada por número de placar diferente para sempre: numa arcada o
## conjunto de textos é pequeno e se repete, então limpar de vez em quando
## custa perto de nada.
const CACHE_TAMANHO_TETO := 400
var _cache_tamanho: Dictionary = {}

## O maior corpo, até `tamanho_max`, em que o texto ainda cabe na
## largura. Sem isso, "PESO-PESADO" a 96 px sai pelos dois lados da tela
## e "FRACO!" fica pequeno demais no mesmo lugar.
func _tamanho_que_cabe(texto: String, tamanho_max: int, largura: float, letra: Font = null) -> int:
	var usada: Font = letra if letra != null else fonte
	var chave := [texto, tamanho_max, largura, usada]
	var em_cache = _cache_tamanho.get(chave)
	if em_cache != null:
		return em_cache

	# A MAIORIA DOS TEXTOS JÁ CABE NO TETO PEDIDO — um rótulo curto como
	# "PONTOS" a 30 px nunca precisou encolher, e pedia a mesma busca de
	# quem precisa. Medir uma vez no teto e só então decidir resolve o
	# caso comum com UMA chamada, não quarenta.
	var tamanho := tamanho_max
	var medido := usada.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho).x
	if medido > largura and medido > 0.0:
		# NÃO COUBE: em vez de descer de dois em dois a partir do teto, a
		# largura medida dá uma ESTIMATIVA direta de quanto encolher — a
		# largura do texto cresce quase linearmente com o corpo da letra.
		# Um chute perto do alvo mais um ajuste fino substitui a busca
		# inteira por poucas chamadas, e o efeito é o mesmo de sempre:
		# encolhido só o necessário para caber.
		tamanho = int(floor(float(tamanho_max) * largura / medido))
		tamanho = clampi(tamanho, 10, tamanho_max)
		tamanho -= tamanho % 2
		# O chute pode errar para os dois lados (a fonte não é
		# perfeitamente linear), então o ajuste fino cobre os dois: sobe
		# se o chute encolheu demais, desce se ainda não coube.
		while tamanho < tamanho_max and usada.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho + 2).x <= largura:
			tamanho += 2
		while tamanho > 10 and usada.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho).x > largura:
			tamanho -= 2

	if _cache_tamanho.size() >= CACHE_TAMANHO_TETO:
		_cache_tamanho.erase(_cache_tamanho.keys()[0])
	_cache_tamanho[chave] = tamanho
	return tamanho

## LETRA DE FLIPERAMA. Três passadas sobre a mesma palavra:
##
##   1. um contorno MUITO grosso, quase preto — é ele que segura a letra
##      sobre qualquer fundo, e é o que separa um letreiro de arcade de
##      um texto colorido qualquer;
##   2. a mesma palavra alguns pixels ACIMA, num tom claro: o que sobra
##      aparecendo por cima da borda vira o brilho do topo da letra, o
##      truque que dá volume sem precisar de degradê (o Godot desenha
##      texto de uma cor só);
##   3. o preenchimento, na cor da vez.
##
## Com `halo`, entra antes de tudo um contorno largo e transparente na
## cor de destaque — a luz que a letra joga no que está atrás dela.
func _letreiro(
	texto: String, pos: Vector2, tamanho: int, cor: Color,
	halo := Color(0, 0, 0, 0), letra: Font = null
) -> void:
	var usada: Font = letra if letra != null else fonte
	if halo.a > 0.001:
		draw_string_outline(usada, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, int(tamanho * 0.34), halo)
	# O CONTORNO ACOMPANHA O CORPO DA LETRA, e não o tamanho pedido.
	#
	# Um contorno de 17% do corpo é o que dá presença a PUNCH a 144 px.
	# Nos 22 px de um rótulo esse mesmo 17% engorda quatro pixels em cada
	# lado de um traço que tem três de largura: o contorno come a letra e
	# sobra a mancha. Abaixo de 34 px o contorno passa a ser fino e fixo,
	# apenas o bastante para descolar a letra do fundo.
	var grossura := maxi(6, int(tamanho * 0.17)) if tamanho >= 34 else maxi(3, int(tamanho * 0.11))
	draw_string_outline(
		usada, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho,
		grossura, Color(Paleta.CONTORNO, cor.a)
	)
	# O realce de topo também é coisa de letra grande: a 22 px ele vira
	# uma segunda cópia deslocada meio pixel, que é a definição de borrão.
	if tamanho >= 34:
		var realce := Color(cor.lightened(0.42), cor.a)
		draw_string(usada, pos - Vector2(0.0, tamanho * 0.055), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, realce)
	draw_string(usada, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho, cor)

## OS TRÊS PAPÉIS DE TEXTO DA TELA DE JOGO.
##
## Antes cada linha escolhia o seu corpo na hora — 25, 26, 30, 32, 34, 46
## — e metade delas era `draw_string` cru, sem contorno, sobre um painel
## que muda de cor a cada faixa. O resultado era uma tela com sete
## tamanhos e dois acabamentos diferentes, e é isso que faz uma tela
## parecer amadora, mesmo quando cada peça sozinha está certa.
##
## Agora há três papéis e nada mais:
##
##   TÍTULO  o que a pessoa lê de longe. Letreiro com contorno e halo,
##           igual ao da abertura — é a mesma tipografia do cartaz.
##   RÓTULO  o que nomeia um número: "CALCULANDO", "PONTOS". Sempre 26,
##           sempre com contorno, porque ele cai sobre o painel escuro,
##           sobre a faixa vermelha e sobre o clarão do soco.
##   APOIO   a letra miúda de quem quiser conferir. Sempre 22.
##
## Todos com o mesmo contorno da abertura: é isso que "uniformiza com as
## iniciais" de verdade, e não só igualar o corpo da letra.
## A Saira Condensed é um terço mais estreita que a Bungee (0,474 contra
## 0,712 de largura média na maiúscula). Essa largura devolvida é o que
## permite subir o corpo dos dois papéis sem que nada estoure a linha: a
## tela ganha letra maior E linha mais curta ao mesmo tempo, que é o que
## faltava para ler de longe.
const CORPO_ROTULO := 31
const CORPO_APOIO := 25

func _rotulo(texto: String, y: float, cor: Color) -> void:
	_letreiro_centrado(texto, y, _corpo(CORPO_ROTULO), cor, fonte_texto)

func _apoio(texto: String, y: float, cor: Color) -> void:
	_letreiro_centrado(texto, y, _corpo(CORPO_APOIO), cor, fonte_texto)

## A MARCA DA CASA, DESENHADA E NÃO ESCRITA.
##
## Escrever "LAZER & SPORT GAMES" com a fonte do jogo não é a marca: é
## uma frase com o nome da marca. O alvo com o dardo é o que se reconhece
## a três metros, antes de conseguir ler qualquer coisa — e é ele que
## está no adesivo do gabinete, no cartão e na fachada.
##
## `y` é o TOPO do logotipo, e não a linha de base: aqui não há linha de
## base, há uma imagem com altura própria.
func _marca_da_casa(y: float, altura: float, alpha := 1.0) -> void:
	if logo == null:
		# Sem o arquivo, a frase volta — uma abertura sem marca nenhuma
		# seria pior do que uma abertura com a marca escrita.
		_texto("LAZER & SPORT GAMES", y + altura * 0.72, 28, Color(Paleta.CIANO, alpha))
		return
	var proporcao := logo.get_width() / float(logo.get_height())
	var largura := altura * proporcao
	draw_texture_rect(
		logo, Rect2(Vector2(540.0 - largura * 0.5, y), Vector2(largura, altura)),
		false, Color(1, 1, 1, alpha)
	)

## A MARCA DA CASA À DIREITA, discreta, na linha `y`.
##
## Ela NÃO entra na tela de contagem com o número grande: ali a atenção
## tem de ir para o 3-2-1 e para a câmera, e uma marca ao lado é uma
## segunda coisa pedindo o olho no segundo em que a pessoa está se
## ajeitando para a foto.
func _marca_lateral(y: float, alpha := 0.85, altura := 96.0) -> void:
	if logo == null:
		return
	var largura := altura * logo.get_width() / float(logo.get_height())
	draw_texture_rect(
		logo, Rect2(Vector2(1000.0 - largura, y), Vector2(largura, altura)),
		false, Color(1, 1, 1, alpha)
	)

## Letreiro centrado na largura útil, sem encolher: o corpo dos rótulos é
## fixo de propósito, e um rótulo que não cabe é um rótulo comprido
## demais, não um rótulo que precisa diminuir.
func _letreiro_centrado(texto: String, y: float, tamanho: int, cor: Color, letra: Font = null) -> void:
	var usada: Font = letra if letra != null else fonte
	var medida := usada.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho)
	_letreiro(texto, Vector2(540.0 - medida.x * 0.5, y), tamanho, cor, Color(0, 0, 0, 0), usada)

## Letreiro centrado numa largura, encolhendo até caber.
func _texto_intro(texto: String, y: float, tamanho_visual: float, corpo_fixo: int, cor: Color, x := 60.0) -> void:
	# Rasteriza sempre o mesmo corpo. Só os vértices mudam durante o pouso.
	var fator := tamanho_visual / float(corpo_fixo)
	var base := Transform2D(0.0, Vector2.ONE * zoom_impacto, 0.0,
		_deslocamento + ALVO_DO_SOCO - ALVO_DO_SOCO * zoom_impacto)
	var local := Transform2D(0.0, Vector2.ONE * fator, 0.0, Vector2(x + 480.0, y))
	draw_set_transform_matrix(base * local)
	var medida := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, corpo_fixo)
	_letreiro(texto, Vector2(-medida.x * 0.5, 0.0), corpo_fixo, cor, Color(cor, cor.a * 0.28))
	draw_set_transform_matrix(base)

func _texto_arcade(texto: String, y: float, tamanho_max: int, cor: Color, largura: float, x := MARGEM) -> void:
	var tamanho := _tamanho_que_cabe(texto, tamanho_max, largura * 0.94)
	var medida := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tamanho)
	_letreiro(texto, Vector2(x + (largura - medida.x) * 0.5, y), tamanho, cor, Color(cor, 0.28))

## A AUDITORIA PRECISA VER ESTA FUNÇÃO TAMBÉM.
##
## Enquanto ela desenhou direto, o teste de legibilidade tinha um ponto
## cego do tamanho da Central: TODO rótulo de botão e TODO valor de
## stepper sai por aqui, e nenhum deles passava por `_texto`. O primeiro
## defeito que isso escondeu foi na página nova — o botão TENTAR DE NOVO
## cobrindo, por inteiro, a linha que diz onde o saco está.
func _texto_cabendo(texto: String, y: float, tamanho_max: int, cor: Color, largura: float, x := MARGEM) -> void:
	var corpo := _tamanho_que_cabe(texto, _corpo(tamanho_max), largura, fonte_texto)
	draw_string(
		fonte_texto, Vector2(x, y), texto, HORIZONTAL_ALIGNMENT_CENTER, largura, corpo, cor
	)
	if auditoria_de_layout:
		_anotar_texto(texto, y, corpo, HORIZONTAL_ALIGNMENT_CENTER, x, largura)
