class_name Lutador3D
extends Node3D

## O ADVERSÁRIO: nove poses ilustradas num plano dentro da arena 3D.
##
## Cada pose é um PNG próprio (`assets/personagem/sprites/pose_*.png`),
## todos do MESMO tamanho e com o ponto mais baixo do desenho na MESMA
## linha (`LINHA_DO_CHAO_PX`). Por isso não há mais tabela de base por
## pose nem recorte de folha: o desenho é sempre inteiro e sempre pisa
## na lona. As imagens são geradas por `tools/recortar_lutador.py`.
##
## O movimento (respiração, recuo, cambaleio, tombo) é procedural e vive
## aqui; as poses são quadros parados.

const FOLHA := "res://assets/personagem/sprites/lutador_sprite_frames.tres"

## Medidas do quadro de cada pose, em pixels (saem do recorte).
const QUADRO_PX := Vector2(695.0, 657.0)
const TOPO_DA_CABECA_PX := 6.0
const LINHA_DO_CHAO_PX := 649.0
const ALTURA_DA_FIGURA := 1.80
const PIXEL_NO_MUNDO := ALTURA_DA_FIGURA / (LINHA_DO_CHAO_PX - TOPO_DA_CABECA_PX)
## Meia distância entre os pés na pose mais aberta. Limita o quanto o
## corpo pode inclinar sem um pé atravessar a lona.
const MEIA_BASE_DOS_PES := PIXEL_NO_MUNDO * 247.0
const PE_LEVANTA_NO_CAMBALEIO := 0.10

const DANO_POR_GOLPE := 0.62
const DANO_MINIMO := 0.02
const TEMPO_NA_LONA := 3.35
const TEMPO_LEVANTAR := 1.25

const PAPEIS_CONTINUOS := ["idle", "guard"]
const PAPEIS := {
	# PARADO É UMA POSE SÓ, E QUEM MEXE É O CORPO. Trocar de imagem a cada
	# segundo (idle ↔ guarda) fazia o lutador "piscar" entre dois desenhos
	# quase iguais — lia como slide, não como gente. A ginga abaixo
	# (`_ginga`) é que dá vida: quica, balança e inclina, sem corte.
	"idle": {"quadros": ["guarda"]},
	"guard": {"quadros": ["preparado"]},
	"taunt_weak": {"quadros": ["jab", "direto", "jab", "guarda"], "ciclo": 0.30},
	"hit_light": {"quadros": ["impacto_corpo"]},
	"hit_medium": {"quadros": ["impacto_corpo"]},
	"hit_heavy": {"quadros": ["impacto_forte"]},
	"stagger": {"quadros": ["impacto_forte", "impacto_corpo"], "ciclo": 0.42},
	"knockout": {"quadros": ["impacto_forte", "nocaute"], "ciclo": 0.22, "uma_vez": true},
	"get_up": {"quadros": ["recuperacao"]},
}
const DURACAO := {
	"taunt_weak": 1.20, "stagger": 1.30, "hit_heavy": 0.95,
	"hit_medium": 0.70, "hit_light": 0.46,
}
## Recuo de cada reação: para trás (m), tombo (rad) e lateral (m).
const RECUO := {
	"taunt_weak": {"tras": 0.00, "tombo": 0.00, "lado": 0.06},
	"hit_light": {"tras": 0.10, "tombo": 0.05, "lado": 0.04},
	"hit_medium": {"tras": 0.22, "tombo": 0.10, "lado": 0.08},
	"hit_heavy": {"tras": 0.36, "tombo": 0.16, "lado": 0.12},
	"stagger": {"tras": 0.52, "tombo": 0.24, "lado": 0.22},
}

var _figura: AnimatedSprite3D = null
var _corpo: Node3D = null
var _frames: SpriteFrames = null

var _relogio := 0.0
var _papel := ""
var _tempo_no_papel := 0.0
var _tempo_reacao := 0.0
var _recuo := 0.0
var _forca_do_recuo := 0.0
var _lado := 1.0
var _tempo_na_lona := 0.0
var _levantando := false
var _caindo := false
var _clarao := 0.0

var queda := 0.0
var dano := 0.0
var em_guarda := false


func montar() -> void:
	_frames = load(FOLHA) as SpriteFrames
	_corpo = Node3D.new()
	_corpo.name = "Corpo"
	add_child(_corpo)
	_figura = AnimatedSprite3D.new()
	_figura.name = "Figura"
	_figura.sprite_frames = _frames
	# A arte já vem iluminada; luz da cena por cima escureceria o desenho.
	_figura.shaded = false
	_figura.double_sided = false
	_figura.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# Mistura por alfa (e não recorte): o contorno sai liso, sem degraus
	# nem o halo que o recorte por limiar deixava.
	_figura.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_figura.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Nada na arena passa na frente do lutador; sem teste de profundidade
	# nenhum plano (lona, sombra) pode cortar a bota.
	_figura.no_depth_test = true
	_figura.render_priority = 1
	_figura.pixel_size = PIXEL_NO_MUNDO
	# Sprite centrado: sobe o quadro até a linha do chão cair em y = 0.
	_figura.position = Vector3(0.0, PIXEL_NO_MUNDO * (LINHA_DO_CHAO_PX - QUADRO_PX.y * 0.5), 0.0)
	_corpo.add_child(_figura)
	_tocar("idle")


func completo() -> bool:
	if _frames == null:
		return false
	for papel in PAPEIS:
		for nome in (PAPEIS[papel]["quadros"] as Array):
			if not _frames.has_animation(StringName(str(nome))):
				return false
	return true


## Nomes de todas as poses usadas, para o pré-carregamento.
func poses() -> PackedStringArray:
	return _frames.get_animation_names() if _frames != null else PackedStringArray()


## Mostra uma pose direto, sem papel. Usado só para aquecer a GPU.
func mostrar_pose(nome: StringName) -> void:
	if _figura != null and _frames != null and _frames.has_animation(nome):
		_figura.animation = nome


func preparar() -> void:
	dano = 0.0
	queda = 0.0
	_caindo = false
	_levantando = false
	_recuo = 0.0
	_tempo_reacao = 0.0
	_tempo_na_lona = 0.0
	_clarao = 0.0
	em_guarda = false
	if _corpo != null:
		_corpo.transform = Transform3D.IDENTITY
	_papel = ""
	_tocar("idle")


func guardar(ativo: bool) -> void:
	em_guarda = ativo
	if not _caindo:
		_tocar("guard" if ativo else "idle")


func bater(forca: float, derruba := false, pontos := -1) -> Dictionary:
	var f := clampf(forca, 0.0, 1.0)
	_recuo = 1.0
	_forca_do_recuo = f
	_lado *= -1.0
	_clarao = 1.0
	var antes := dano
	if f > DANO_MINIMO:
		dano = clampf(dano + f * DANO_POR_GOLPE, 0.0, 1.0)
	var nocaute := not _caindo and (derruba or (dano >= 1.0 and antes < 1.0))
	var papel := ""
	var desdenhou := false
	if nocaute:
		papel = "knockout"
		_caindo = true
		_levantando = false
		_tempo_na_lona = 0.0
		_tempo_reacao = TEMPO_NA_LONA + TEMPO_LEVANTAR
		_tocar("knockout")
	elif not _caindo:
		papel = reacao_para_pontos(pontos, f)
		desdenhou = papel == "taunt_weak" and pontos >= 0 and pontos < 6000
		_tempo_reacao = float(DURACAO.get(papel, 0.8))
		_tocar(papel)
	return {"nocaute": nocaute, "dano": dano, "reacao": papel, "desdenhou": desdenhou}


## Abaixo de 6000 pontos o adversário desdenha; acima, a força escolhe.
static func reacao_para_pontos(pontos: int, forca: float) -> String:
	if pontos >= 0 and pontos < 6000:
		return "taunt_weak"
	var reacao := reacao_para_forca(forca)
	return "hit_light" if reacao == "taunt_weak" else reacao


static func reacao_para_forca(forca: float) -> String:
	var f := clampf(forca, 0.0, 1.0)
	if f >= 0.82:
		return "stagger"
	if f >= 0.62:
		return "hit_heavy"
	if f >= 0.38:
		return "hit_medium"
	if f >= 0.18:
		return "hit_light"
	return "taunt_weak"


func clarao(valor: float) -> void:
	_clarao = maxf(_clarao, clampf(valor, 0.0, 1.0))


func atualizar(delta: float) -> void:
	if _figura == null:
		return
	_relogio += delta
	_tempo_no_papel += delta
	_recuo = maxf(0.0, _recuo - delta * 2.1)
	_clarao = maxf(0.0, _clarao - delta * 3.4)
	_tempo_reacao = maxf(0.0, _tempo_reacao - delta)

	if _caindo:
		_tempo_na_lona += delta
		queda = minf(1.0, queda + delta * 2.8)
		if _tempo_na_lona >= TEMPO_NA_LONA and not _levantando:
			_levantando = true
			_tocar("get_up")
		if _levantando:
			queda = maxf(0.0, 1.0 - (_tempo_na_lona - TEMPO_NA_LONA) / TEMPO_LEVANTAR)
		if _tempo_na_lona >= TEMPO_NA_LONA + TEMPO_LEVANTAR:
			_caindo = false
			_levantando = false
			queda = 0.0
			dano = minf(dano, 0.72)
			_tocar("guard" if em_guarda else "idle")
	elif _tempo_reacao <= 0.0 and not (_papel in PAPEIS_CONTINUOS):
		_tocar("guard" if em_guarda else "idle")

	_avancar_o_quadro()
	_mover_o_corpo()
	_pintar()


func _tocar(papel: String) -> void:
	if not PAPEIS.has(papel):
		papel = "idle"
	if _papel == papel:
		return
	_papel = papel
	_tempo_no_papel = 0.0
	_mostrar(0)


func _avancar_o_quadro() -> void:
	var receita: Dictionary = PAPEIS[_papel]
	var lista: Array = receita["quadros"]
	if lista.size() <= 1:
		return
	var passo := int(_tempo_no_papel / maxf(float(receita.get("ciclo", 0.5)), 0.01))
	if bool(receita.get("uma_vez", false)) or not (_papel in PAPEIS_CONTINUOS):
		_mostrar(mini(passo, lista.size() - 1))
	else:
		_mostrar(passo % lista.size())


func _mostrar(indice: int) -> void:
	var lista: Array = PAPEIS[_papel]["quadros"]
	var nome := StringName(str(lista[clampi(indice, 0, lista.size() - 1)]))
	if _figura.animation != nome and _frames != null and _frames.has_animation(nome):
		_figura.animation = nome


func _mover_o_corpo() -> void:
	var t := _ginga()

	var receita: Dictionary = RECUO.get(_papel, {})
	if not receita.is_empty() and _recuo > 0.001:
		var impacto := ease(_recuo, 0.35)
		t.origin.z -= float(receita["tras"]) * impacto * (0.55 + _forca_do_recuo * 0.65)
		t.origin.x += _lado * float(receita["lado"]) * impacto
		t.basis = t.basis.rotated(Vector3.RIGHT, -float(receita["tombo"]) * impacto)
		if _papel == "stagger":
			t.origin.x += sin(_tempo_no_papel * 11.0) * 0.06 * impacto
			var giro := asin(clampf(PE_LEVANTA_NO_CAMBALEIO / (2.0 * MEIA_BASE_DOS_PES), 0.0, 1.0))
			t.basis = t.basis.rotated(Vector3.FORWARD, _lado * giro * impacto)

	if queda > 0.001:
		# Descida do tombo; a trava abaixo para o corpo ao encostar na lona.
		t.origin.y -= 0.34 * ease(clampf(queda, 0.0, 1.0), 0.55)
		t.origin.y += sin(clampf((queda - 0.82) / 0.18, 0.0, 1.0) * PI) * 0.035

	_corpo.transform = _pousado_na_lona(t)


## A GINGA DO BOXEADOR.
##
## Um lutador de verdade nunca está parado: quica na ponta dos pés, pende
## o corpo de um lado para o outro e inclina o tronco junto. São três
## movimentos em compassos casados — o quique no dobro do balanço — para
## o corpo desenhar um "oito" e não um pêndulo mecânico.
##
## Na guarda armada (esperando o soco) a ginga fica mais curta e rápida:
## ele fecha a guarda e fica pronto. Durante uma reação a ginga some aos
## poucos, e o recuo do golpe é que manda.
func _ginga() -> Transform3D:
	var t := Transform3D.IDENTITY
	var armado := _papel == "guard"
	var compasso := 1.55 if armado else 1.25     # balanços por segundo
	var amplo := 0.62 if armado else 1.0
	var calma := 1.0 - clampf(_recuo * 1.4, 0.0, 1.0)
	if _caindo:
		calma = 0.0
	var fase := _relogio * TAU * compasso * 0.5
	# o quique: sobe e desce duas vezes por balanço, sempre acima da lona
	var quique := absf(sin(fase * 2.0))
	t.origin.y += quique * 0.030 * amplo * calma
	# o balanço lateral e a inclinação do tronco acompanhando
	var lado := sin(fase)
	t.origin.x += lado * 0.075 * amplo * calma
	t.basis = t.basis.rotated(Vector3.FORWARD, -lado * 0.045 * amplo * calma)
	# a respiração por baixo de tudo
	t.origin.y += (1.0 - cos(_relogio * 2.1)) * 0.004
	return t


## Nenhuma parte do desenho passa abaixo da lona, em pose nenhuma.
## Mede os dois cantos da base (a linha do chão, igual em todas as poses)
## e sobe o corpo o que faltar.
static func _pousado_na_lona(t: Transform3D) -> Transform3D:
	var mais_baixo := minf(
		(t * Vector3(-MEIA_BASE_DOS_PES, 0.0, 0.0)).y,
		(t * Vector3(MEIA_BASE_DOS_PES, 0.0, 0.0)).y
	)
	if mais_baixo < 0.0:
		t.origin.y -= mais_baixo
	return t


## Clarão do soco acende o desenho; o dano acumulado puxa para o vermelho.
func _pintar() -> void:
	var castigo := clampf(dano, 0.0, 1.0)
	var cor := Color(1.0, 1.0 - castigo * 0.16, 1.0 - castigo * 0.22)
	_figura.modulate = cor.lerp(Color(2.2, 2.0, 2.0), clampf(_clarao, 0.0, 1.0) * 0.5)


## Onde o corpo está agora (para a sombra de contato acompanhar).
func deslocamento() -> Vector3:
	return _corpo.position if _corpo != null else Vector3.ZERO
