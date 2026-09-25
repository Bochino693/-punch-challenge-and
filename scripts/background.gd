class_name PunchBackground
extends Control

const ArcadeStage = preload("res://scripts/presentation/arcade_stage.gd")

## O salão onde a máquina fica: claro, com o piso em perspectiva e um
## refletor quente caindo sobre o saco.
##
## CLARO POR DECISÃO, NÃO POR DESCUIDO. A máquina trabalha num salão de
## festas iluminado. Fundo preto ali lê como monitor desligado, e o preto
## engole o vermelho da marca da casa, que é justamente o que precisa
## aparecer de longe. O céu é um degradê claro, o chão é mais quente que
## o topo, e o que dá profundidade é a perspectiva do piso — não a
## escuridão.
##
## O REFLETOR NÃO É ENFEITE. Sem ele o saco fica boiando num retângulo
## chapado; com ele há um cone de luz vindo do teto, uma poça quente no
## piso e uma sombra embaixo do saco — três pistas baratas que dizem ao
## olho onde a cena acontece. `FOCO` é a posição do refletor em fração do
## tamanho do controle, então acompanha o palco em qualquer resolução.
##
## ------------------------------------------------------------------
## DUAS CAMADAS, E UM RELÓGIO SÓ.
##
## Este nó desenhava tudo — cenário parado e enfeite em movimento — no
## mesmo `_draw`, chamado sessenta vezes por segundo, e adiantava o seu
## PRÓPRIO relógio num `_process` separado. Os dois eram problema:
##
##   O DESENHO. Repintar o chão, quatro polígonos de tela cheia e oito
##   barras de néon a cada quadro é o trabalho mais caro do jogo, e é
##   inútil: esses pixels são idênticos do início ao fim do expediente.
##   Agora a parte parada mora no filho `Parado`, que desenha uma vez e
##   fica; só o que se move é redesenhado. Ver `ArcadeStage.background`.
##
##   O RELÓGIO. Ter o seu próprio `_process` fazia o fundo andar por uma
##   conta de tempo e o resto do jogo por outra. Bastava um quadro
##   engasgado cair diferente nos dois para a fagulha do fundo deslizar
##   um tanto e a tela inteira outro — e é no fundo, com coisa se movendo
##   devagar e em linha reta, que essa diferença mais aparece. Agora
##   `main.gd` chama `avancar()` com o passo já suavizado, o mesmo que
##   move todo o resto. Ver `Ritmo`.

## Onde o refletor aponta, em fração da tela. Combina com o centro do
## saco definido em `scenes/main.tscn`.
const FOCO := Vector2(0.481, 0.29)
## Altura do piso, em fração da tela.
const HORIZONTE := 0.58

var tempo := 0.0
var fx := PunchFX.new()
## Tonalidade do veredito: tinge a tela inteira após o golpe.
var matiz := Color(0, 0, 0, 0)

## O cenário parado. Um `Control` filho, atrás deste, que só volta a
## desenhar quando o tamanho da tela muda.
var _parado: Control = null
var _tamanho_desenhado := Vector2.ZERO

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ESTE NÓ NÃO TEM MAIS `_process`. Quem o adianta é `main.gd`, no
	# mesmo passo do jogo inteiro.
	set_process(false)
	_montar_camada_parada()
	# As duas camadas de efeito ficam ACIMA do cenário (z relativo).
	fx.montar(self, 1, 1)

## O FUNDO SE MEXE NA PLACA DE VÍDEO (`fundo_vivo.gdshader`): a arte do
## gabinete respira, a luz corre pelos riscos e um relâmpago acende de vez
## em quando. Nenhum pixel é redesenhado pelo processador.
var _vivo: ShaderMaterial = null

func _montar_camada_parada() -> void:
	var arte := TextureRect.new()
	arte.name = "Parado"
	# Atrás de tudo o que este nó desenha, e sem receber clique: é
	# cenário, não interface.
	arte.z_index = -1
	arte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arte.set_anchors_preset(Control.PRESET_FULL_RECT)
	arte.texture = ArcadeStage.FUNDO
	arte.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arte.stretch_mode = TextureRect.STRETCH_SCALE
	_vivo = ShaderMaterial.new()
	_vivo.shader = load("res://shaders/fundo_vivo.gdshader")
	arte.material = _vivo
	_parado = arte
	add_child(_parado)

## Quanto o fundo se mexe: 1 na abertura, menos durante a luta.
func vida(valor: float) -> void:
	if _vivo != null:
		_vivo.set_shader_parameter("forca", valor)
	# NA LUTA O FUNDO FICA PARADO: ele está quase todo atrás da arena, e o
	# shader de tela cheia (1080x1920 pixels, todo quadro) era trabalho da
	# placa de vídeo que ninguém via. Na abertura ele volta a se mexer.
	if _parado != null:
		_parado.material = _vivo if valor >= 0.5 else null

## O PASSO VEM DE FORA. Ver o cabeçalho.
func avancar(passo: float) -> void:
	tempo += passo
	fx.atualizar(passo)
	# O cenário parado só é refeito quando a janela muda de tamanho — o
	# que, num gabinete, acontece zero vez por noite.
	if _parado != null and size != _tamanho_desenhado:
		_tamanho_desenhado = size
		# A poeira do palco é um emissor contínuo do motor, e não um
		# sorteio por quadro em script.
		fx.brisa(
			"palco", Rect2(size.x * 0.25, size.y * HORIZONTE - 10.0, size.x * 0.5, 20.0),
			Color(1.0, 0.86, 0.55, 0.40), 2.5
		)
	queue_redraw()

func _draw() -> void:
	# O CENÁRIO MORA AQUI, e não no nó raiz.
	#
	# Quando o cenário era pintado pelo `_draw` da raiz, ele saía DEPOIS
	# dos filhos e por cima deles — e foi por isso que o saco e o medidor
	# tiveram de ser escondidos para a tela não virar uma mancha. Só que
	# escondidos eles nunca mais voltaram, e a janela do soco virou texto
	# sobre um vazio preto. Pintando o cenário neste nó (z = -2), a ordem
	# volta a ser a natural: cenário, palco, texto, moldura.
	#
	# A parte parada dele saiu para o filho `Parado`, que já desenhou
	# antes deste `_draw` por estar em z menor. O que fica aqui é só o
	# que se mexe.
	ArcadeStage.background_animado(self, tempo)
	fx.desenhar(self)
	if matiz.a > 0.001:
		draw_rect(Rect2(Vector2.ZERO, size), matiz)
