class_name Lutador3D
extends Node3D

## O ADVERSÁRIO: a LÓGICA do combate, sem desenho nenhum.
##
## Aqui moram o dano, o recuo do golpe, a escolha da reação pela força, o
## tombo na lona e o levantar, e a sombra de boxe na guarda. O corpo que
## mostra tudo isso é o boneco 3D com esqueleto de `LutadorModelo3D`, que
## herda desta classe e só implementa `montar`, `_mover_o_corpo` e
## `_pintar`.

## Altura do lutador em pé, em metros: é por ela que a câmera enquadra.
const ALTURA_DA_FIGURA := 1.80

const DANO_POR_GOLPE := 0.62
const DANO_MINIMO := 0.02
const TEMPO_NA_LONA := 3.35
const TEMPO_LEVANTAR := 1.25

const PAPEIS_CONTINUOS := ["idle", "guard"]
## Os papéis que o corpo sabe mostrar. Quem desenha cada um é a subclasse
## (`LutadorModelo3D`, o boneco 3D com esqueleto).
const PAPEIS := [
	"idle", "guard", "taunt_weak", "hit_light", "hit_medium", "hit_heavy",
	"stagger", "knockout", "get_up",
]
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

var _corpo: Node3D = null

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
var _sombra_em := 2.5




## Monta o corpo. A subclasse põe o modelo dentro de `_corpo`.
func montar() -> void:
	_corpo = Node3D.new()
	_corpo.name = "Corpo"
	add_child(_corpo)


func completo() -> bool:
	return false


## Papéis a exercitar no aquecimento da GPU.
func poses() -> PackedStringArray:
	return PackedStringArray(PAPEIS)


func mostrar_pose(nome: StringName) -> void:
	_tocar(str(nome))


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
	if _corpo == null:
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
	elif _papel == "guard" and _tempo_reacao <= 0.0:
		# SOMBRA NA GUARDA: esperando o soco, ele não fica só balançando.
		# De tempos em tempos solta um jab-direto no ar e volta à guarda —
		# é a provocação que chama o soco.
		_sombra_em -= delta
		if _sombra_em <= 0.0:
			_sombra_em = randf_range(3.5, 6.0)
			_tempo_reacao = 1.0
			_papel = ""
			_tocar("taunt_weak")

	_mover_o_corpo()
	_pintar()


func _tocar(papel: String) -> void:
	if not PAPEIS.has(papel):
		papel = "idle"
	if _papel == papel:
		return
	_papel = papel
	_tempo_no_papel = 0.0


## O desenho de cada quadro: a subclasse implementa.
func _mover_o_corpo() -> void:
	pass


func _pintar() -> void:
	pass


## Onde o corpo está agora (para a sombra de contato acompanhar).
func deslocamento() -> Vector3:
	return _corpo.position if _corpo != null else Vector3.ZERO
