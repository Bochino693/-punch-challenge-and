class_name LutadorBoxeador3D
extends Lutador3D

## O ADVERSÁRIO: UM BOXEADOR DE VERDADE, animado em código.
##
## O corpo é `assets/lutador3d/boxeador.glb`, gerado por
## `tools/gerar_boxeador.py` (corpo MakeHuman/Anny, livre para uso
## comercial): pele pintada em 4096 px, calção de cetim, botas, luvas e
## quatro expressões no rosto (deboche, dor, grito, apagado).
##
## A ANIMAÇÃO NÃO É GRAVADA. Cada quadro é montado assim:
##
##   1. A COREOGRAFIA diz onde cada coisa quer estar: o centro do corpo
##      no ringue, a altura e o giro da bacia, a inclinação do tronco e da
##      cabeça, e onde ficam as duas luvas (guarda, jab, direto, gancho,
##      cruzado de baixo, festa, deboche, soco na câmera).
##   2. OS PÉS SÃO PLANTADOS. Um pé só sai do chão quando o corpo se
##      afastou demais dele, e aí dá um PASSO de verdade (sobe em arco e
##      pousa noutro lugar). É isso que acaba com o pé deslizando na lona:
##      o recuo de um golpe forte vira dois ou três passos para trás, o
##      cambaleio vira passos tortos, e a ginga é um quicar na ponta dos
##      pés com os pés no lugar.
##   3. IK DE DOIS OSSOS nas pernas e nos braços: joelho e cotovelo saem da
##      conta, dobrando para onde devem (joelho sobre o pé, cotovelo para
##      baixo e para fora). Se a perna não alcança o pé, a bacia desce.
##   4. MOLAS para o que é reação: a cabeça que vai para trás no soco e
##      volta sozinha, o tronco que balança, a guarda que abre.

const MODELO := "res://assets/lutador3d/boxeador.glb"
const MESCLA_EXPR := 7.0

## Base de luta (espaço do esqueleto, metros do modelo): pé esquerdo à
## frente (guarda ortodoxa), direito atrás.
const PE_FRENTE := Vector2(0.15, 0.15)
const PE_TRAS := Vector2(-0.17, -0.17)
const GIRO_DA_BASE := -0.34
const LIMIAR_DO_PASSO := 0.055
const TEMPO_DO_PASSO := 0.22
const ALTURA_DO_PASSO := 0.055

## Os golpes: duração total e a fração em que o braço chega esticado.
const GOLPES := {
	"jab": {"dur": 0.30, "pico": 0.36},
	"direto": {"dur": 0.40, "pico": 0.40},
	"gancho": {"dur": 0.46, "pico": 0.42},
	"upper": {"dur": 0.46, "pico": 0.44},
}
const COMBOS := [
	[["jab", 0]],
	[["jab", 0], ["jab", 0], ["direto", 1]],
	[["jab", 0], ["direto", 1]],
	[["jab", 0], ["direto", 1], ["gancho", 0]],
	[["direto", 1], ["gancho", 0], ["direto", 1]],
	[["jab", 0], ["upper", 1], ["gancho", 0]],
	[["gancho", 0], ["direto", 1]],
	[["jab", 0], ["jab", 0]],
]

var _modelo: Node3D = null
var _sk: Skeleton3D = null
var _pronto := false
var _i := {}                     ## nome curto -> índice do osso
var _R := {}                     ## nome curto -> posição de repouso
var _nomes := PackedStringArray()
var _pais := PackedInt32Array()
var _secundario := {}            ## nome -> eixo secundário de repouso
var _l_braco := 0.0
var _l_ante := 0.0
var _l_coxa := 0.0
var _l_canela := 0.0
var _h0 := 0.0                   ## altura da bacia em pé
var _tornozelo := 0.0            ## altura do tornozelo com o pé no chão
var _desce_pe := 0.0             ## quanto o osso do pé aponta para baixo em repouso
var _desce_dedo := 0.0

var _pele: MeshInstance3D = null
var _mat_pele: StandardMaterial3D = null
var _expr := {}
var _expr_valor := {}
var _mat_clarao: StandardMaterial3D = null
var _malhas: Array[MeshInstance3D] = []

## --- o estado do corpo (suavizado)
var _dt := 1.0 / 60.0
var _centro := Vector2.ZERO          ## x, z do corpo no ringue
## Até onde, a partir do centro, a lona está livre das cordas (m).
const RINGUE_LIVRE := 1.40
var _centro_alvo := Vector2.ZERO
var _centro_vel := Vector2.ZERO
var _bacia := Vector3.ZERO           ## posição da bacia
var _bacia_rot := Vector3.ZERO       ## pitch, yaw, roll
var _tronco := Vector3.ZERO
var _cabeca := Vector3.ZERO
var _mao := [Vector3.ZERO, Vector3.ZERO]
var _mao_dir := [Vector3.UP, Vector3.UP]
var _polegar := [Vector3.BACK, Vector3.BACK]
var _cotovelo := [Vector3.DOWN, Vector3.DOWN]
var _ombro := [Vector2.ZERO, Vector2.ZERO]
## --- os alvos do quadro (a coreografia escreve aqui)
var a_bacia := Vector3.ZERO
var a_bacia_rot := Vector3.ZERO
var a_tronco := Vector3.ZERO
var a_cabeca := Vector3.ZERO
var a_mao := [Vector3.ZERO, Vector3.ZERO]
var a_mao_dir := [Vector3.UP, Vector3.UP]
var a_polegar := [Vector3.BACK, Vector3.BACK]
var a_cotovelo := [Vector3.DOWN, Vector3.DOWN]
var a_ombro := [Vector2.ZERO, Vector2.ZERO]
var a_calcanhar := [0.0, 0.0]
var a_expr := {}
var _rapidez := 18.0

## --- os pés
var _pe := [Vector3.ZERO, Vector3.ZERO]
var _pe_giro := [0.0, 0.0]
var _passo_t := [-1.0, -1.0]
var _passo_de := [Vector3.ZERO, Vector3.ZERO]
var _passo_para := [Vector3.ZERO, Vector3.ZERO]
var _passo_giro_de := [0.0, 0.0]
var _passo_giro_para := [0.0, 0.0]
var _calcanhar := [0.0, 0.0]
var _pe_ultimo := 1
var _pes_livres := 0.0               ## 1 = pernas soltas (deitado)

## --- molas das reações
var _mola_cab := Vector3.ZERO
var _mola_cab_v := Vector3.ZERO
var _mola_tronco := Vector3.ZERO
var _mola_tronco_v := Vector3.ZERO
var _guarda_aberta := 0.0
var _guarda_aberta_v := 0.0
var _joelho := 0.0                   ## quanto os joelhos cedem (0..1)
var _joelho_v := 0.0
var _tonto := 0.0                    ## sobra de cambaleio (s)

## --- golpes no ar
var _fila: Array = []                ## [{tipo, lado, t}]
var _proximo_combo := 2.5
var _vagar_em := 1.5

## --- soco na tela
var _tela_ok := false
var _tela_bateu := false
var _dolly := 0.0

## --- queda
var _queda_vis := 0.0
var _rng := RandomNumberGenerator.new()


# ===================================================================
# MONTAGEM
# ===================================================================
func montar() -> void:
	super.montar()
	_rng.randomize()
	if not ResourceLoader.exists(MODELO):
		return
	var cena := load(MODELO) as PackedScene
	if cena == null:
		return
	_modelo = cena.instantiate() as Node3D
	_corpo.add_child(_modelo)
	_sk = _modelo.find_child("Skeleton3D", true, false) as Skeleton3D
	if _sk == null:
		return
	_mapear()
	for n in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftArm", "LeftForeArm",
			"LeftHand", "LeftHandMiddle1", "LeftHandThumb1", "LeftUpLeg", "LeftLeg", "LeftFoot",
			"LeftToeBase", "LeftToe_End", "RightArm", "RightFoot", "HeadTop_End"]:
		if not _i.has(n):
			return
	var topo: float = (_R["HeadTop_End"] as Vector3).y
	_modelo.scale = Vector3.ONE * (ALTURA_DA_FIGURA / maxf(topo, 0.1))
	_l_braco = (_R["LeftForeArm"] - _R["LeftArm"]).length()
	_l_ante = (_R["LeftHand"] - _R["LeftForeArm"]).length()
	_l_coxa = (_R["LeftLeg"] - _R["LeftUpLeg"]).length()
	_l_canela = (_R["LeftFoot"] - _R["LeftLeg"]).length()
	_h0 = (_R["Hips"] as Vector3).y
	_tornozelo = (_R["LeftFoot"] as Vector3).y
	var dp: Vector3 = _R["LeftToeBase"] - _R["LeftFoot"]
	_desce_pe = atan2(-dp.y, Vector2(dp.x, dp.z).length())
	var dd: Vector3 = _R["LeftToe_End"] - _R["LeftToeBase"]
	_desce_dedo = atan2(-dd.y, Vector2(dd.x, dd.z).length())
	for m in _modelo.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		_malhas.append(mi)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.name == "Pele":
			_pele = mi
	if _pele != null:
		for k in _pele.mesh.get_blend_shape_count():
			var nome := str(_pele.mesh.get_blend_shape_name(k))
			_expr[nome] = k
			_expr_valor[nome] = 0.0
		var mat := _pele.mesh.surface_get_material(0) as StandardMaterial3D
		if mat != null:
			_mat_pele = mat.duplicate() as StandardMaterial3D
			_definir(_mat_pele, 0.50, 0.55)
			# Pele suada: menos áspera e com o relevo mais marcado — é o
			# brilho nos músculos que desenha o corpo de longe.
			_mat_pele.normal_scale = 1.15
			_pele.set_surface_override_material(0, _mat_pele)
			# A PELE DE VERDADE: shader próprio (luz que atravessa a borda,
			# suor quebrado por poros, relevo dos músculos). Sem os mapas,
			# fica o material padrão acima.
			var pele := _material_da_pele(mat)
			if pele != null:
				_pele.set_surface_override_material(0, pele)
	# O RESTO DA ROUPA TAMBÉM GANHA CONTORNO. Couro das luvas e das botas,
	# cetim do calção e o metal do cinturão pegam a luz de recorte: o
	# personagem se descola do fundo e parece mais nítido sem custar um
	# pixel a mais de resolução.
	var feitos := {}
	for mi in _malhas:
		if mi == _pele or mi.mesh == null:
			continue
		for k in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(k) as StandardMaterial3D
			if base == null:
				continue
			# Casca fina (calção, cinturão, friso): duas faces. Luvas e botas
			# são sólidos fechados e ficam com uma.
			var casca := mi.name in ["Calcao", "Cinturao", "Friso", "Placa"]
			var chave := [base, casca]
			if not feitos.has(chave):
				var novo := base.duplicate() as StandardMaterial3D
				var luva := mi.name.begins_with("Luva")
				# Couro da luva: menos recorte e menos espelho — com muito
				# dos dois ela estourava num vermelho chapado.
				_definir(novo, maxf(base.roughness, 0.42) if luva else base.roughness, 0.18 if luva else 0.45, casca)
				if luva:
					# o vermelho vivo da cor de vértice estourava no lado
					# iluminado: um pouco mais escuro, a forma aparece.
					novo.albedo_color = Color(0.72, 0.72, 0.72)
				feitos[chave] = novo
			mi.set_surface_override_material(k, feitos[chave])
	_mat_clarao = StandardMaterial3D.new()
	_mat_clarao.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_clarao.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_clarao.albedo_color = Color.BLACK
	_pronto = true
	_reiniciar_corpo()
	_tocar("idle")


const SHADER_PELE := "res://shaders/pele.gdshader"
const RELEVO_PELE := "res://assets/lutador3d/pele_relevo.png"
const POROS_PELE := "res://assets/lutador3d/pele_poros.png"
var _shader_pele: ShaderMaterial = null
var _dano_pintado := -1.0

func _material_da_pele(base: StandardMaterial3D) -> ShaderMaterial:
	if base.albedo_texture == null:
		return null
	for caminho in [SHADER_PELE, RELEVO_PELE, POROS_PELE]:
		if not ResourceLoader.exists(caminho):
			return null
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_PELE)
	m.set_shader_parameter("pintura", base.albedo_texture)
	m.set_shader_parameter("relevo", load(RELEVO_PELE))
	m.set_shader_parameter("poros", load(POROS_PELE))
	_shader_pele = m
	return m


func completo() -> bool:
	return _pronto


## Recorte de luz, textura filtrada de lado e brilho do material: o que faz
## o lutador "ler" em alta definição na imagem pequena da arena.
static func _definir(m: StandardMaterial3D, aspereza: float, recorte: float, dois_lados := false) -> void:
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Opaco SEMPRE, e as cascas (calção, cinturão, luvas, botas) com as
	# duas faces: vista por baixo ou pela perna, a face de dentro sumia e
	# o calção parecia transparente.
	m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	if dois_lados:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = aspereza
	m.rim_enabled = true
	m.rim = recorte
	m.rim_tint = 0.55


func _mapear() -> void:
	_nomes.resize(_sk.get_bone_count())
	_pais.resize(_sk.get_bone_count())
	for k in _sk.get_bone_count():
		var nome := _sk.get_bone_name(k)
		var curto := nome
		for sep in [":", "_"]:
			var p := nome.find(sep)
			if p >= 0 and nome.substr(0, p).to_lower().begins_with("mixamorig"):
				curto = nome.substr(p + 1)
				break
		_i[curto] = k
		_nomes[k] = curto
		_pais[k] = _sk.get_bone_parent(k)
	for k in _sk.get_bone_count():
		_R[_nomes[k]] = _sk.get_bone_global_rest(k).origin
	# Eixo secundário de repouso de cada osso de membro: é ele que decide
	# a torção (para onde aponta o bíceps, o joelho, o polegar).
	for s in ["Left", "Right"]:
		var polegar: Vector3 = _R[s + "HandThumb1"] - _R[s + "Hand"]
		# (+Z é a frente do lutador; em repouso o cotovelo aponta para trás
		# e o joelho para a frente.)
		_secundario[s + "Arm"] = Vector3(0, 0, -1)
		_secundario[s + "ForeArm"] = polegar
		_secundario[s + "Hand"] = polegar
		_secundario[s + "UpLeg"] = Vector3(0, 0, 1)
		_secundario[s + "Leg"] = Vector3(0, 0, 1)
		_secundario[s + "Foot"] = Vector3.UP
		_secundario[s + "ToeBase"] = Vector3.UP


func _reiniciar_corpo() -> void:
	_centro = Vector2.ZERO
	_centro_alvo = Vector2.ZERO
	_centro_vel = Vector2.ZERO
	for k in 2:
		var base := _base_do_pe(k)
		_pe[k] = Vector3(base.x, _tornozelo, base.y)
		_pe_giro[k] = _giro_do_pe(k)
		_passo_t[k] = -1.0
		_calcanhar[k] = 0.0
	_bacia = Vector3(0.0, _h0 - 0.05, 0.0)
	_bacia_rot = Vector3(0.0, GIRO_DA_BASE, 0.0)
	_tronco = Vector3.ZERO
	_cabeca = Vector3.ZERO
	_mola_cab = Vector3.ZERO
	_mola_cab_v = Vector3.ZERO
	_mola_tronco = Vector3.ZERO
	_mola_tronco_v = Vector3.ZERO
	_guarda_aberta = 0.0
	_guarda_aberta_v = 0.0
	_joelho = 0.0
	_joelho_v = 0.0
	_tonto = 0.0
	_fila.clear()
	_queda_vis = 0.0
	_pes_livres = 0.0
	_dolly = 0.0
	_tela_ok = false
	_tela_bateu = false
	for k in 2:
		_mao[k] = _no_tronco(_guarda_local(k, 1.0))
		_mao_dir[k] = Vector3(0, 0.8, 0.6).normalized()
		_polegar[k] = Vector3(0, 0.4, -1).normalized()
		_cotovelo[k] = Vector3(0.3 * _lado_s(k), -1, -0.3).normalized()


func preparar() -> void:
	super.preparar()
	if _pronto:
		_reiniciar_corpo()
		for nome in _expr_valor:
			_expr_valor[nome] = 0.0
			if _pele != null:
				_pele.set_blend_shape_value(int(_expr[nome]), 0.0)
		_pintar()


## AQUECIMENTO: a arena mostra cada pose por um quadro no arranque. Aqui
## também acendem as expressões e o clarão do golpe — cada um é um
## caminho de shader que, sem isso, compilaria no primeiro soco.
func mostrar_pose(nome: StringName) -> void:
	super.mostrar_pose(nome)
	if not _pronto:
		return
	for k in _expr:
		_pele.set_blend_shape_value(int(_expr[k]), 0.5)
	_clarao = 1.0
	_pintar()
	_resolver()


static func _lado_s(k: int) -> float:
	return 1.0 if k == 0 else -1.0


static func _lado_n(k: int) -> String:
	return "Left" if k == 0 else "Right"


func _base_do_pe(k: int) -> Vector2:
	var b := PE_FRENTE if k == 0 else PE_TRAS
	return _centro + b


func _giro_do_pe(k: int) -> float:
	return -0.10 if k == 0 else -0.38


# ===================================================================
# INTERFACE
# ===================================================================
func poses() -> PackedStringArray:
	return PackedStringArray(["guard", "celebra", "deboche", "hit_heavy", "knockout", "soco_tela", "idle"])


func _sombra_da_base() -> bool:
	return false


func bater(forca: float, derruba := false, pontos := -1, ultimo := false) -> Dictionary:
	var r := super.bater(forca, derruba, pontos, ultimo)
	if not _pronto:
		return r
	var f := clampf(forca, 0.0, 1.0)
	_fila.clear()
	_tela_ok = false
	var papel := str(r.get("reacao", ""))
	if papel == "taunt_weak":
		# Nem sentiu: o queixo mal mexe.
		_mola_cab_v += Vector3(-1.2, 0.8 * _lado, 0.0)
		_tempo_reacao = 2.3
		return r
	# O soco vem da câmera (de frente): a cabeça vai para trás e para o
	# lado, o tronco recua, a guarda abre e o corpo é empurrado — os pés
	# vão ter de dar passos para segurar o peso.
	var forte := 0.35 + f * 0.9
	_mola_cab_v += Vector3(-9.5 * forte, _lado * 5.5 * forte, _lado * 4.0 * forte)
	_mola_tronco_v += Vector3(-4.5 * forte, _lado * 2.2 * forte, _lado * 1.6 * forte)
	_guarda_aberta_v += 7.0 * forte
	_joelho_v += 3.5 * forte
	_centro_vel += Vector2(_lado * 0.35 * f, -(0.55 + 1.35 * f))
	if papel == "stagger" or bool(r.get("nocaute", false)):
		_tonto = 1.6
	return r


func soco_na_tela() -> bool:
	if not _pronto or _caindo or _papel in PAPEIS_DE_FESTA:
		return false
	if _papel != "guard" and _papel != "idle":
		return false
	_fila.clear()
	_tela_ok = true
	_tela_bateu = false
	_tempo_reacao = 2.9
	_tocar("soco_tela")
	return true


## O SOCO FINAL: quem perdeu leva o nocaute. É o mesmo direto na câmera,
## mas sai no fim da rodada (por cima da provocação), e depois dele o
## lutador vai para o deboche — a comemoração de quem ganhou a luta.
func soco_final() -> bool:
	if not _pronto or _caindo:
		return false
	_fila.clear()
	_tela_ok = true
	_tela_bateu = false
	_tempo_reacao = 2.4
	_papel = ""
	_tocar("soco_tela")
	return true


func tela_atingida() -> bool:
	if _tela_bateu:
		_tela_bateu = false
		return true
	return false


func camera_extra() -> Vector2:
	return Vector2(_dolly, _dolly * 0.08)


func deslocamento() -> Vector3:
	var s := _modelo.scale.x if _modelo != null else 1.0
	return Vector3(_centro.x * s, 0.0, _centro.y * s) + (_corpo.position if _corpo != null else Vector3.ZERO)


# ===================================================================
# O QUADRO
# ===================================================================
## O CORPO NÃO ANDA EM CÂMERA LENTA. O passo do corpo tinha teto de
## 50 ms: numa TV Box rodando a 15–20 quadros por segundo cada quadro
## perdia um terço do tempo, e a luta inteira ficava lenta. Agora o quadro
## longo é fatiado em passos de até 1/30 s — as molas continuam estáveis e
## o relógio da luta anda junto com o relógio do jogo.
const SUBPASSO := 1.0 / 30.0
## O RITMO DA LUTA: o corpo inteiro anda 30% mais rápido que o relógio —
## guarda, passos, reações e comemoração. No tempo "real" o boxeador
## parecia em câmera lenta na tela da máquina.
const VELOCIDADE := 1.3

func atualizar(delta: float) -> void:
	var resto := clampf(delta, 0.0, 0.15) * VELOCIDADE
	while true:
		var d := minf(resto, SUBPASSO)
		_dt = d
		super.atualizar(d)
		resto -= d
		if resto <= 0.0005:
			break


func _mover_o_corpo() -> void:
	if not _pronto:
		return
	var dt := _dt
	if _papel != "soco_tela":
		_dolly = lerpf(_dolly, 0.0, 1.0 - exp(-dt * 5.0))
	_molas(dt)
	_coreografia(dt)
	_suavizar(dt)
	_andar(dt)
	_resolver()
	_rosto(dt)
	_raiz()


func _molas(dt: float) -> void:
	# Mola amortecida: vai, passa um pouco e volta. É o "chacoalhar" que
	# faz um golpe parecer ter massa.
	var k := 95.0
	var c := 11.0
	_mola_cab_v += (-_mola_cab * k - _mola_cab_v * c) * dt
	_mola_cab += _mola_cab_v * dt
	_mola_tronco_v += (-_mola_tronco * 70.0 - _mola_tronco_v * 10.0) * dt
	_mola_tronco += _mola_tronco_v * dt
	_guarda_aberta_v += (-_guarda_aberta * 40.0 - _guarda_aberta_v * 9.0) * dt
	_guarda_aberta = clampf(_guarda_aberta + _guarda_aberta_v * dt, -0.2, 1.3)
	_joelho_v += (-_joelho * 45.0 - _joelho_v * 8.0) * dt
	_joelho = clampf(_joelho + _joelho_v * dt, -0.3, 1.2)
	_tonto = maxf(0.0, _tonto - dt)


# ===================================================================
# COREOGRAFIA
# ===================================================================
func _coreografia(dt: float) -> void:
	var t := _relogio
	var tp := _tempo_no_papel
	a_expr = {}
	_rapidez = 16.0
	for k in 2:
		a_calcanhar[k] = 0.0
		a_ombro[k] = Vector2.ZERO
	a_bacia_rot = Vector3(0.0, GIRO_DA_BASE, 0.0)
	a_tronco = Vector3(0.10, 0.0, 0.0)
	a_cabeca = Vector3(0.10, 0.0, 0.0)
	var guarda := 1.0

	# ---- a ginga: quique na ponta dos pés, peso indo e vindo.
	var compasso := 1.9 if _papel == "guard" else 1.35
	var fase := t * TAU * compasso * 0.5
	var quique := 0.5 - 0.5 * cos(fase * 2.0)
	var balanco := sin(fase)
	var ginga := 1.0
	var agacha := 0.075
	if _papel == "idle":
		agacha = 0.045
		guarda = 0.55
		ginga = 0.7
	a_bacia = Vector3(balanco * 0.018 * ginga, _h0 - agacha - quique * 0.022 * ginga, 0.0)
	a_bacia_rot.z = balanco * 0.035 * ginga
	a_tronco.z = -balanco * 0.03 * ginga
	a_tronco.x += quique * 0.02
	for k in 2:
		a_calcanhar[k] = quique * 0.35 * ginga
	# respiração
	a_tronco.x += sin(t * 2.4) * 0.012
	a_ombro[0].x = sin(t * 2.4) * 0.02
	a_ombro[1].x = sin(t * 2.4) * 0.02

	# ---- andar pelo ringue: um ponto novo de tempos em tempos.
	_vagar_em -= dt
	if _vagar_em <= 0.0 and (_papel == "guard" or _papel == "idle"):
		_vagar_em = _rng.randf_range(1.2, 2.8)
		_centro_alvo = Vector2(_rng.randf_range(-0.16, 0.16), _rng.randf_range(-0.12, 0.10))

	# ---- as luvas na guarda (no espaço do tronco)
	for k in 2:
		a_mao[k] = _guarda_local(k, guarda)
		a_mao_dir[k] = Vector3(0.12 * -_lado_s(k), 0.82, 0.55).normalized()
		a_polegar[k] = Vector3(-0.35 * _lado_s(k), 0.35, -0.85).normalized()
		a_cotovelo[k] = Vector3(0.35 * _lado_s(k), -1.0, -0.15).normalized()

	match _papel:
		"guard":
			_combos_no_ar(dt)
		"idle":
			# Solto, antes da luta: ombros girando, luvas batendo.
			if fmod(t, 7.0) < 1.2:
				var g := sin(fmod(t, 7.0) / 1.2 * PI)
				a_ombro[0].x += g * 0.12
				a_ombro[1].x += g * 0.12
				a_cabeca.z += sin(t * 5.0) * 0.18 * g
			if fmod(t + 3.0, 6.0) < 0.5:
				var g2 := sin(fmod(t + 3.0, 6.0) / 0.5 * PI)
				a_mao[0] += Vector3(-0.07, 0.0, 0.05) * g2
				a_mao[1] += Vector3(0.07, 0.0, 0.05) * g2
		"taunt_weak":
			_nem_sentiu(tp)
		"hit_light", "hit_medium", "hit_heavy":
			a_expr["dor"] = 1.0 if tp < 0.7 else 0.4
			_rapidez = 12.0
		"stagger":
			a_expr["dor"] = 1.0
			_rapidez = 9.0
		"celebra":
			_celebrar(tp)
		"deboche":
			_debochar(tp)
		"tonto":
			_zonzo(tp)
		"soco_tela":
			_socar_a_tela(tp)
		"cordas":
			_nas_cordas(tp)
		"knockout", "get_up":
			a_expr["apagado"] = 1.0 if _papel == "knockout" else 0.5
			if _papel == "get_up":
				a_tronco.x += 0.55 * sin(clampf(1.0 - _queda_vis, 0.0, 1.0) * PI)
				a_expr["dor"] = 0.8

	_golpes_em_andamento(dt)

	# ---- cambaleio: o corpo procura o equilíbrio em passos tortos.
	if _tonto > 0.0:
		var w := clampf(_tonto, 0.0, 1.0)
		_centro_alvo += Vector2(sin(t * 3.3) * 0.10, sin(t * 2.1) * 0.06) * w * dt * 4.0
		a_bacia_rot.z += sin(t * 4.1) * 0.10 * w
		a_tronco.z += sin(t * 3.2 + 1.0) * 0.12 * w
		a_cabeca += Vector3(sin(t * 2.7) * 0.15, sin(t * 1.9) * 0.2, sin(t * 3.1) * 0.2) * w
		for k in 2:
			a_mao[k] += Vector3(0.0, -0.16, -0.02) * w
		a_expr["dor"] = maxf(float(a_expr.get("dor", 0.0)), w)

	# ---- reações por cima de tudo (molas)
	var abre := clampf(_guarda_aberta, 0.0, 1.2)
	for k in 2:
		a_mao[k] += Vector3(0.10 * _lado_s(k), -0.18, -0.10) * abre
	a_bacia.y -= clampf(_joelho, -0.2, 1.0) * 0.09

	# ---- a cabeça olha para quem joga (compensa o giro da base)
	a_cabeca.y += -(a_bacia_rot.y + a_tronco.y) * 0.75

	# ---- o deslocamento do corpo: empurrão do golpe + vontade de andar
	_centro_vel *= exp(-dt * 3.2)
	var puxa := (_centro_alvo - _centro) * 2.2
	_centro += (_centro_vel + puxa) * dt
	_centro.x = clampf(_centro.x, -0.55, 0.55)
	# Nas cordas ele pode chegar até elas; fora disso, fica no miolo.
	_centro.y = clampf(_centro.y, -CORDAS_Z if _papel == "cordas" else -0.95, 1.05)
	# NA QUEDA, OS PÉS ESCORREGAM PARA A FRENTE. O corpo tomba para trás
	# em volta dos pés; caindo de onde o empurrão do soco o deixou, a
	# cabeça passava por baixo das cordas e ia parar FORA do ringue. Como
	# num nocaute de verdade, os pés deslizam para a frente enquanto o
	# tronco vai para trás — e o corpo inteiro deita dentro da lona.
	if _queda_vis > 0.0 and _modelo != null:
		var livre := (ALTURA_DA_FIGURA * 1.02 - RINGUE_LIVRE) / maxf(_modelo.scale.x, 0.01)
		var junto := clampf(_queda_vis * 1.6, 0.0, 1.0)
		_centro.y = maxf(_centro.y, lerpf(_centro.y, livre, junto))
		_centro.x = lerpf(_centro.x, clampf(_centro.x, -0.35, 0.35), junto)
		_centro_vel.y = maxf(_centro_vel.y, 0.0)
	a_bacia.x += _centro.x
	a_bacia.z += _centro.y


## Onde a luva fica na guarda, no espaço do mundo, a partir do tronco.
func _guarda_local(k: int, fechada: float) -> Vector3:
	var s := _lado_s(k)
	var frente := k == 0
	var alvo := Vector3(0.115 * s, -0.035, 0.29) if frente else Vector3(-0.10, -0.055, 0.22)
	var baixa := Vector3(0.17 * s, -0.20, 0.12)
	return baixa.lerp(alvo, clampf(fechada, 0.0, 1.0))


# ---------------------------------------------------------- os golpes
func _combos_no_ar(dt: float) -> void:
	_proximo_combo -= dt
	if _proximo_combo <= 0.0 and _fila.is_empty():
		_proximo_combo = _rng.randf_range(2.2, 4.8)
		var combo: Array = COMBOS[_rng.randi_range(0, COMBOS.size() - 1)]
		var atraso := 0.0
		for g in combo:
			_fila.append({"tipo": g[0], "lado": g[1], "t": -atraso})
			atraso += float(GOLPES[g[0]]["dur"]) * _rng.randf_range(0.62, 0.8)


func _golpes_em_andamento(dt: float) -> void:
	if _fila.is_empty():
		return
	var vivos: Array = []
	for g in _fila:
		g["t"] = float(g["t"]) + dt
		var receita: Dictionary = GOLPES[g["tipo"]]
		var dur: float = receita["dur"]
		var tt: float = g["t"] / dur
		if tt < 0.0:
			vivos.append(g)
			continue
		if tt > 1.0:
			continue
		vivos.append(g)
		_aplicar_golpe(str(g["tipo"]), int(g["lado"]), tt, float(receita["pico"]))
	_fila = vivos


## Envelope de um golpe: recolhe um pouco, estica rápido, segura um
## instante e volta.
static func _envelope(tt: float, pico: float) -> float:
	if tt < 0.12:
		return -0.12 * sin(tt / 0.12 * PI * 0.5)
	if tt < pico:
		var u := (tt - 0.12) / (pico - 0.12)
		return -0.12 + 1.12 * (1.0 - pow(1.0 - u, 3.0))
	if tt < pico + 0.08:
		return 1.0
	var v := (tt - pico - 0.08) / (1.0 - pico - 0.08)
	return 1.0 - v * v * (3.0 - 2.0 * v)


func _aplicar_golpe(tipo: String, k: int, tt: float, pico: float) -> void:
	var e := _envelope(tt, pico)
	var ep := maxf(e, 0.0)
	var s := _lado_s(k)
	_rapidez = maxf(_rapidez, 34.0)
	var ombro: Vector3 = _R[_lado_n(k) + "Arm"] + Vector3(_bacia.x, _bacia.y - _h0, _bacia.z)
	var alcance := (_l_braco + _l_ante) * 0.97
	match tipo:
		"jab", "direto":
			var mira := Vector3(-0.03 * s, 1.47, 1.2) + Vector3(_centro.x, 0.0, _centro.y)
			var d := (mira - ombro).normalized()
			var fim := _do_mundo(ombro + d * alcance)
			a_mao[k] = (a_mao[k] as Vector3).lerp(fim, ep)
			a_mao_dir[k] = (a_mao_dir[k] as Vector3).lerp(d, ep).normalized()
			a_polegar[k] = (a_polegar[k] as Vector3).lerp(Vector3(-s, 0.25, 0.0).normalized(), ep).normalized()
			a_cotovelo[k] = (a_cotovelo[k] as Vector3).lerp(Vector3(0.8 * s, -0.5, 0.0).normalized(), ep).normalized()
			a_ombro[k] += Vector2(0.10, 0.18) * ep
			if tipo == "direto":
				# O direto vem do chão: gira bacia e tronco, o calcanhar de
				# trás sobe e gira.
				a_bacia_rot.y += 0.55 * e
				a_tronco.y += 0.35 * e
				a_calcanhar[1] = maxf(a_calcanhar[1], ep)
				a_bacia.z += 0.04 * ep
			else:
				a_tronco.y += -0.14 * e
				a_bacia.z += 0.02 * ep
			a_cabeca.z += 0.06 * s * ep
		"gancho":
			var mira2 := _do_mundo(ombro + Vector3(-0.28 * s, 0.02, 0.36))
			a_mao[k] = (a_mao[k] as Vector3).lerp(mira2, ep)
			a_mao_dir[k] = (a_mao_dir[k] as Vector3).lerp(Vector3(-s, 0.1, 0.35).normalized(), ep).normalized()
			a_polegar[k] = (a_polegar[k] as Vector3).lerp(Vector3.UP, ep).normalized()
			a_cotovelo[k] = (a_cotovelo[k] as Vector3).lerp(Vector3(s, 0.35, -0.2).normalized(), ep).normalized()
			a_tronco.y += (-0.55 if k == 0 else 0.55) * e
			a_bacia_rot.y += (-0.30 if k == 0 else 0.30) * e
			a_calcanhar[k] = maxf(a_calcanhar[k], ep * 0.8)
		"upper":
			var baixo := ombro + Vector3(-0.05 * s, -0.30, 0.22)
			var alto := ombro + Vector3(-0.10 * s, 0.14, 0.36)
			var alvo := _do_mundo(baixo.lerp(alto, clampf(e, 0.0, 1.0)))
			a_mao[k] = (a_mao[k] as Vector3).lerp(alvo, clampf(absf(e) * 1.5, 0.0, 1.0))
			a_mao_dir[k] = (a_mao_dir[k] as Vector3).lerp(Vector3(0.0, 1.0, 0.25).normalized(), ep).normalized()
			a_polegar[k] = (a_polegar[k] as Vector3).lerp(Vector3(0, 0.2, -1).normalized(), ep).normalized()
			a_cotovelo[k] = (a_cotovelo[k] as Vector3).lerp(Vector3(0.2 * s, -1.0, 0.1).normalized(), ep).normalized()
			a_bacia.y -= 0.05 * sin(clampf(tt / pico, 0.0, 1.0) * PI * 0.5) * (1.0 - ep) + 0.02 * ep
			a_tronco.y += (0.40 if k == 1 else -0.40) * e
			a_tronco.x += -0.10 * ep
	a_expr["grito"] = maxf(float(a_expr.get("grito", 0.0)), ep * 0.35)


# ------------------------------------------------------- o que ele faz
## NAS CORDAS. 0–0,45 s: vai de costas até elas. 0,45–1,05 s: encosta,
## tronco para trás, braços abertos por cima da corda, as cordas cedem.
## Depois: as cordas o devolvem — um passo para a frente e a guarda volta.
const CORDAS_Z := 1.22
var _cordas_devolveu := false

func _nas_cordas(tp: float) -> void:
	var vai := clampf(tp / 0.45, 0.0, 1.0)
	var apoio := clampf((tp - 0.30) / 0.25, 0.0, 1.0) * (1.0 - clampf((tp - 1.05) / 0.35, 0.0, 1.0))
	if tp < 1.05:
		_cordas_devolveu = false
		_centro_alvo = Vector2(_centro.x * 0.6, lerpf(_centro.y, -CORDAS_Z, ease(vai, 0.5)))
		_vagar_em = 2.0
	elif not _cordas_devolveu:
		# o estilingue das cordas
		_cordas_devolveu = true
		_centro_vel += Vector2(0.0, 2.1)
		_centro_alvo = Vector2(_rng.randf_range(-0.08, 0.08), 0.02)
	a_tronco.x -= 0.34 * apoio
	a_cabeca.x -= 0.22 * apoio
	a_bacia.y -= 0.03 * apoio
	for k in 2:
		var sl := _lado_s(k)
		var na_corda := Vector3(0.46 * sl, -0.04, -0.20)
		a_mao[k] = (a_mao[k] as Vector3).lerp(na_corda, apoio)
		a_mao_dir[k] = (a_mao_dir[k] as Vector3).lerp(Vector3(sl, -0.2, -0.3).normalized(), apoio).normalized()
		a_cotovelo[k] = (a_cotovelo[k] as Vector3).lerp(Vector3(sl, -0.5, -0.3).normalized(), apoio).normalized()
	a_expr["dor"] = 1.0 if tp < 1.2 else 0.5
	_rapidez = 10.0


## Quanto o corpo está empurrando as cordas (0–1), para a arena vergá-las.
func pressao_nas_cordas() -> float:
	if _papel != "cordas":
		return 0.0
	var fundo := clampf((-_centro.y - (CORDAS_Z - 0.18)) / 0.18, 0.0, 1.0)
	return fundo


func _nem_sentiu(tp: float) -> void:
	# Nem sentiu. Balança a cabeça, sorri de lado e chama com a luva.
	a_expr["deboche"] = clampf(tp * 3.0, 0.0, 1.0)
	if tp > 0.25 and tp < 1.1:
		var u := (tp - 0.25) / 0.85
		a_cabeca.y += sin(u * TAU * 2.0) * 0.28 * sin(u * PI)
	if tp > 1.0:
		var u2 := fmod(tp - 1.0, 0.65) / 0.65
		var chama := sin(u2 * PI)
		# a luva da frente sai e volta, "vem"
		a_mao[0] += Vector3(0.04, 0.02, 0.14) * chama
		a_mao_dir[0] = Vector3(0.0, 0.3 + 0.7 * chama, 0.9 - 0.6 * chama).normalized()
		a_cabeca.x -= 0.10
		a_cabeca.z += 0.12


func _celebrar(tp: float) -> void:
	# Aguentou: braços para o alto, pula com a torcida.
	var entra := clampf(tp * 3.0, 0.0, 1.0)
	var pulo := absf(sin(_relogio * TAU * 1.1))
	a_bacia.y += pulo * 0.035 * entra
	for k in 2:
		var s := _lado_s(k)
		var alto := Vector3(0.28 * s, 0.42 + 0.05 * sin(_relogio * 6.0 + k), 0.06)
		a_mao[k] = (a_mao[k] as Vector3).lerp(alto, entra)
		a_mao_dir[k] = (a_mao_dir[k] as Vector3).lerp(Vector3(0.1 * s, 1, 0.1).normalized(), entra).normalized()
		a_cotovelo[k] = (a_cotovelo[k] as Vector3).lerp(Vector3(s, 0.1, -0.2).normalized(), entra).normalized()
		a_calcanhar[k] = maxf(a_calcanhar[k], pulo * entra)
	a_cabeca.x -= 0.25 * entra
	a_expr["grito"] = entra * (0.6 + 0.4 * sin(_relogio * 3.0))


func _debochar(tp: float) -> void:
	# A FESTA LONGA DE QUEM GANHOU DO JOGADOR. Oito segundos em cinco
	# atos, em laço: vitória, "Ali shuffle", aponta para a câmera e ri,
	# bate no queixo ("bate aqui"), mostra os bíceps.
	var ato := fmod(tp, 8.0)
	var entra := clampf(tp * 3.0, 0.0, 1.0)
	a_bacia_rot.y *= 0.4
	if ato < 1.5:
		_celebrar(ato + 0.4)
		return
	if ato < 3.4:
		# Ali shuffle: pés trocando rápido, luvas baixas balançando.
		var u := ato - 1.5
		var troca := sin(u * TAU * 3.2)
		_centro_alvo = Vector2(troca * 0.03, 0.0)
		for k in 2:
			var s := _lado_s(k)
			a_mao[k] = (a_mao[k] as Vector3).lerp(Vector3(0.20 * s, -0.12 + 0.05 * troca * s, 0.16), entra)
			a_calcanhar[k] = 0.6
		a_bacia.y += absf(troca) * 0.02
		a_cabeca.y += sin(u * 5.0) * 0.18
		a_expr["deboche"] = 1.0
		return
	if ato < 5.0:
		# Aponta para quem jogou e ri.
		var u2 := clampf((ato - 3.4) * 4.0, 0.0, 1.0)
		var ombro: Vector3 = _R["LeftArm"] + Vector3(_bacia.x, _bacia.y - _h0, _bacia.z)
		var d := (Vector3(_centro.x, 1.5, 2.0) - ombro).normalized()
		a_mao[0] = (a_mao[0] as Vector3).lerp(_do_mundo(ombro + d * (_l_braco + _l_ante) * 0.95), u2)
		a_mao_dir[0] = (a_mao_dir[0] as Vector3).lerp(d, u2).normalized()
		a_cotovelo[0] = Vector3(0.7, -0.6, 0.0).normalized()
		var ri := 0.5 + 0.5 * sin(_relogio * 18.0)
		a_tronco.x += -0.12 - 0.04 * ri
		a_cabeca.x += -0.28 - 0.05 * ri
		a_mao[1] = (a_mao[1] as Vector3).lerp(Vector3(-0.05, -0.12, 0.14), u2)
		a_expr["grito"] = 0.5 + 0.35 * ri
		a_expr["deboche"] = 0.6
		return
	if ato < 6.5:
		# "Bate aqui": a luva bate duas vezes no próprio queixo.
		var u3 := ato - 5.0
		var bate := absf(sin(u3 * TAU * 1.4))
		a_mao[0] = (a_mao[0] as Vector3).lerp(Vector3(0.02, 0.10 + 0.03 * bate, 0.12 + 0.05 * bate), 0.9)
		a_mao_dir[0] = Vector3(-0.3, 0.9, 0.2).normalized()
		a_cabeca.x -= 0.18
		a_cabeca.z += 0.10
		a_expr["deboche"] = 1.0
		return
	# Mostra os bíceps, gritando.
	var u4 := clampf((ato - 6.5) * 4.0, 0.0, 1.0)
	for k in 2:
		var s := _lado_s(k)
		a_mao[k] = (a_mao[k] as Vector3).lerp(Vector3(0.36 * s, 0.24, 0.04), u4)
		a_mao_dir[k] = (a_mao_dir[k] as Vector3).lerp(Vector3(-0.6 * s, 0.8, 0.0).normalized(), u4).normalized()
		a_cotovelo[k] = Vector3(s, -0.15, -0.2).normalized()
	a_tronco.x += 0.12 * u4
	a_expr["grito"] = u4


func _zonzo(tp: float) -> void:
	# Levou bonito e ficou de pé: zonzo, balança a cabeça, respeita.
	_tonto = maxf(_tonto, 0.8)
	var u := clampf(tp * 2.0, 0.0, 1.0)
	a_expr["dor"] = 0.7
	for k in 2:
		a_mao[k] = (a_mao[k] as Vector3).lerp(_guarda_local(k, 0.35), u)
	if tp > 2.0:
		# balança a cabeça: "que soco!"
		a_cabeca.y += sin(tp * 7.0) * 0.12
		a_cabeca.x += 0.12


func _socar_a_tela(tp: float) -> void:
	# QUEM DEMORA LEVA. Avança, arma, e solta o direto na câmera.
	if tp < 0.75:
		_centro_alvo = Vector2(0.02, 0.95)
		a_expr["deboche"] = 0.6
	elif tp < 1.55:
		_centro_alvo = Vector2(0.02, 0.95)
	else:
		_centro_alvo = Vector2(0.0, 0.0)
	var arma := clampf((tp - 0.72) / 0.28, 0.0, 1.0) * (1.0 - clampf((tp - 1.0) / 0.06, 0.0, 1.0))
	var solta := clampf((tp - 1.0) / 0.10, 0.0, 1.0)
	var volta := clampf((tp - 1.25) / 0.45, 0.0, 1.0)
	var e := solta * (1.0 - volta * volta * (3.0 - 2.0 * volta))
	# arma: recolhe o direito e gira o corpo para trás
	a_tronco.y += -0.35 * arma + 0.55 * e
	a_bacia_rot.y += -0.2 * arma + 0.6 * e
	a_calcanhar[1] = maxf(a_calcanhar[1], e)
	a_mao[1] = (a_mao[1] as Vector3) + Vector3(-0.04, 0.0, -0.06) * arma
	if e > 0.0:
		_rapidez = 40.0
		var cam := _camera_no_esqueleto()
		var ombro: Vector3 = _R["RightArm"] + Vector3(_bacia.x, _bacia.y - _h0, _bacia.z)
		var d := (cam - ombro).normalized()
		a_mao[1] = (a_mao[1] as Vector3).lerp(_do_mundo(ombro + d * (_l_braco + _l_ante)), e)
		a_mao_dir[1] = (a_mao_dir[1] as Vector3).lerp(d, e).normalized()
		a_polegar[1] = (a_polegar[1] as Vector3).lerp(Vector3(1, 0.3, 0).normalized(), e).normalized()
		a_cotovelo[1] = Vector3(-0.8, -0.5, 0.0).normalized()
		a_ombro[1] += Vector2(0.12, 0.28) * e
		a_bacia.z += 0.06 * e
	if _tela_ok and tp >= 1.09:
		_tela_ok = false
		_tela_bateu = true
	a_expr["grito"] = maxf(solta * (1.0 - volta), float(a_expr.get("grito", 0.0)))
	if tp > 1.6:
		a_expr["deboche"] = 1.0
	# a câmera vem ao encontro do soco e depois volta
	var alvo_dolly := 0.0
	if tp > 0.4 and tp < 1.7:
		alvo_dolly = 0.72 * clampf((tp - 0.4) / 0.6, 0.0, 1.0)
	_dolly = lerpf(_dolly, alvo_dolly, 1.0 - exp(-_dt * 6.0))


func _camera_no_esqueleto() -> Vector3:
	if _sk == null or not _sk.is_inside_tree():
		return Vector3(0.0, 1.5, 2.6)
	return _sk.global_transform.affine_inverse() * ponto_da_camera


# ===================================================================
# SUAVIZAÇÃO, PASSOS E IK
# ===================================================================
func _suavizar(dt: float) -> void:
	var a := 1.0 - exp(-dt * _rapidez)
	var lento := 1.0 - exp(-dt * 10.0)
	_bacia = _bacia.lerp(a_bacia, a)
	_bacia_rot = _bacia_rot.lerp(a_bacia_rot, lento)
	_tronco = _tronco.lerp(a_tronco, a)
	_cabeca = _cabeca.lerp(a_cabeca, lento)
	for k in 2:
		# As luvas da guarda são guardadas relativas ao centro do corpo.
		var alvo: Vector3 = _no_tronco(a_mao[k])
		_mao[k] = (_mao[k] as Vector3).lerp(alvo, a)
		_mao_dir[k] = (_mao_dir[k] as Vector3).slerp((a_mao_dir[k] as Vector3).normalized(), a).normalized()
		_polegar[k] = (_polegar[k] as Vector3).slerp((a_polegar[k] as Vector3).normalized(), a).normalized()
		_cotovelo[k] = (_cotovelo[k] as Vector3).lerp(a_cotovelo[k], a).normalized()
		_ombro[k] = (_ombro[k] as Vector2).lerp(a_ombro[k], a)
		_calcanhar[k] = lerpf(_calcanhar[k], a_calcanhar[k], a)


## Um ponto da guarda (medido a partir do peito) levado para o mundo,
## girando com o tronco: a guarda acompanha o corpo.
func _no_tronco(p: Vector3) -> Vector3:
	return _peito_base() + _peito_giro() * p


## O caminho inverso: um ponto do mundo (a câmera, o alvo de um golpe)
## no espaço da guarda.
func _do_mundo(p: Vector3) -> Vector3:
	return _peito_giro().inverse() * (p - _peito_base())


func _peito_giro() -> Basis:
	return Basis.from_euler(Vector3(_bacia_rot.x + _tronco.x * 0.7, _bacia_rot.y + _tronco.y, _bacia_rot.z + _tronco.z))


func _peito_base() -> Vector3:
	var peito: Vector3 = _R["Spine2"]
	return Vector3(_bacia.x, peito.y + (_bacia.y - _h0), _bacia.z)


func _andar(dt: float) -> void:
	var livre := _caindo or queda > 0.01
	if livre:
		return
	# Um pé de cada vez: o que está mais longe de onde devia estar.
	var pior := -1
	var maior := LIMIAR_DO_PASSO
	for k in 2:
		if _passo_t[k] >= 0.0:
			continue
		var b := _base_do_pe(k)
		var d := Vector2(_pe[k].x, _pe[k].z).distance_to(b)
		var giro_err := absf(_pe_giro[k] - _giro_do_pe(k))
		if d > maior or giro_err > 0.5:
			maior = d
			pior = k
	var algum_andando: bool = _passo_t[0] >= 0.0 or _passo_t[1] >= 0.0
	if pior >= 0 and not algum_andando:
		var alvo := _base_do_pe(pior)
		# passo um pouco além, para o corpo ter para onde ir
		var sobra := (alvo - Vector2(_pe[pior].x, _pe[pior].z)) * 0.15
		_passo_t[pior] = 0.0
		_passo_de[pior] = _pe[pior]
		_passo_para[pior] = Vector3(alvo.x + sobra.x, _tornozelo, alvo.y + sobra.y)
		_passo_giro_de[pior] = _pe_giro[pior]
		_passo_giro_para[pior] = _giro_do_pe(pior)
	var pressa := 1.0 + clampf(_centro_vel.length() * 1.2, 0.0, 1.2)
	for k in 2:
		if _passo_t[k] < 0.0:
			continue
		_passo_t[k] += dt * pressa / TEMPO_DO_PASSO
		var u := clampf(_passo_t[k], 0.0, 1.0)
		var liso := u * u * (3.0 - 2.0 * u)
		var p: Vector3 = (_passo_de[k] as Vector3).lerp(_passo_para[k], liso)
		p.y = _tornozelo + sin(u * PI) * ALTURA_DO_PASSO
		_pe[k] = p
		_pe_giro[k] = lerpf(_passo_giro_de[k], _passo_giro_para[k], liso)
		if _passo_t[k] >= 1.0:
			_passo_t[k] = -1.0
			_pe[k].y = _tornozelo


## A POSE: da coreografia até cada osso.
func _resolver() -> void:
	var G := {}   ## nome -> Basis global
	var O := {}   ## nome -> origem global
	var lying := _queda_vis > 0.001
	var deita := clampf(_queda_vis * 2.5, 0.0, 1.0)
	# ---- bacia: desce se alguma perna não alcança o chão.
	var rot_bacia := Basis.from_euler(_bacia_rot)
	var bacia := _bacia
	if not lying:
		var falta := 0.0
		for k in 2:
			var quadril: Vector3 = bacia + rot_bacia * (_R[_lado_n(k) + "UpLeg"] - _R["Hips"])
			var pe: Vector3 = _pe_com_calcanhar(k)
			var h := Vector2(quadril.x - pe.x, quadril.z - pe.z).length()
			var alcance := (_l_coxa + _l_canela) * 0.985
			var alto := pe.y + sqrt(maxf(alcance * alcance - h * h, 0.0))
			falta = maxf(falta, quadril.y - alto)
		bacia.y -= falta
	G["Hips"] = rot_bacia
	O["Hips"] = bacia
	# ---- coluna
	var partes := {"Spine": 0.3, "Spine1": 0.35, "Spine2": 0.35}
	var pai := "Hips"
	for n in ["Spine", "Spine1", "Spine2"]:
		var q := Basis.from_euler((_tronco + _mola_tronco) * float(partes[n]))
		G[n] = (G[pai] as Basis) * q
		O[n] = (O[pai] as Vector3) + (G[pai] as Basis) * (_R[n] - _R[pai])
		pai = n
	var cab := _cabeca + _mola_cab
	G["Neck"] = (G["Spine2"] as Basis) * Basis.from_euler(cab * 0.4)
	O["Neck"] = (O["Spine2"] as Vector3) + (G["Spine2"] as Basis) * (_R["Neck"] - _R["Spine2"])
	G["Head"] = (G["Neck"] as Basis) * Basis.from_euler(cab * 0.6)
	O["Head"] = (O["Neck"] as Vector3) + (G["Neck"] as Basis) * (_R["Head"] - _R["Neck"])
	# ---- braços
	for k in 2:
		var s := _lado_n(k)
		var sg := _lado_s(k)
		var cl := (G["Spine2"] as Basis) * Basis.from_euler(Vector3(0.0, -_ombro[k].y * sg * 0.6, _ombro[k].x * sg))
		G[s + "Shoulder"] = cl
		O[s + "Shoulder"] = (O["Spine2"] as Vector3) + (G["Spine2"] as Basis) * (_R[s + "Shoulder"] - _R["Spine2"])
		var raiz: Vector3 = (O[s + "Shoulder"] as Vector3) + cl * (_R[s + "Arm"] - _R[s + "Shoulder"])
		var mao: Vector3 = _mao[k]
		if lying:
			mao = mao.lerp(_mao_deitado(k, O, G), deita)
		var ik := _ik(raiz, mao, _l_braco, _l_ante, _cotovelo[k])
		var cot: Vector3 = ik[0]
		var pulso: Vector3 = ik[1]
		var dobra: Vector3 = ik[2]
		G[s + "Arm"] = _girar(s + "Arm", cot - raiz, dobra)
		O[s + "Arm"] = raiz
		var pol: Vector3 = _polegar[k]
		G[s + "ForeArm"] = _girar(s + "ForeArm", pulso - cot, pol)
		O[s + "ForeArm"] = cot
		# PUNHO RETO, como de boxeador: a luva segue o antebraço (é ele
		# que o punho da luva abraça). Só uma pitada da direção pedida,
		# para o gesto não ficar duro.
		var ante := (pulso - cot).normalized()
		var dir_mao: Vector3 = ante.slerp((_mao_dir[k] as Vector3).normalized(), 0.12).normalized()
		G[s + "Hand"] = _girar(s + "Hand", dir_mao, pol)
		O[s + "Hand"] = pulso
	# ---- pernas
	for k in 2:
		var s := _lado_n(k)
		var raiz: Vector3 = bacia + rot_bacia * (_R[s + "UpLeg"] - _R["Hips"])
		var pe := _pe_com_calcanhar(k)
		var frente_pe := Vector3(sin(_pe_giro[k]), 0.0, cos(_pe_giro[k]))
		var cima_pe := Vector3.UP
		if lying:
			# deitado as pernas ficam soltas; levantando, dobram para apoiar
			var dobra_perna := 0.0 if _papel != "get_up" else sin(clampf(1.0 - _queda_vis, 0.0, 1.0) * PI)
			var solto := raiz + rot_bacia * Vector3(0.03 * _lado_s(k), -(_l_coxa + _l_canela) * lerpf(0.93, 0.62, dobra_perna), lerpf(0.08, 0.30, dobra_perna))
			pe = pe.lerp(solto, deita)
			frente_pe = frente_pe.slerp(rot_bacia * Vector3(0.0, 0.25, 1.0).normalized(), deita).normalized()
			cima_pe = cima_pe.slerp(rot_bacia * Vector3(0.0, 0.3, -1.0).normalized(), deita).normalized()
		var polo := (frente_pe + Vector3(0.40 * _lado_s(k), 0.0, 0.0)).normalized()
		var ik := _ik(raiz, pe, _l_coxa, _l_canela, polo)
		var joelho: Vector3 = ik[0]
		var tornozelo: Vector3 = ik[1]
		var dobra: Vector3 = ik[2]
		G[s + "UpLeg"] = _girar(s + "UpLeg", joelho - raiz, dobra)
		O[s + "UpLeg"] = raiz
		G[s + "Leg"] = _girar(s + "Leg", tornozelo - joelho, dobra)
		O[s + "Leg"] = joelho
		# o calcanhar sobe: o pé gira sobre a ponta
		var inc := deg_to_rad(38.0) * clampf(_calcanhar[k], 0.0, 1.0) * (1.0 - deita)
		var frente := frente_pe * cos(inc) - cima_pe * sin(inc)
		var cima := cima_pe * cos(inc) + frente_pe * sin(inc)
		var dir_pe := frente * cos(_desce_pe) - cima * sin(_desce_pe)
		G[s + "Foot"] = _girar(s + "Foot", dir_pe, cima)
		O[s + "Foot"] = tornozelo
		# BOTA É DURA: a biqueira acompanha boa parte do giro do pé. Com os
		# dedos colados no chão e o calcanhar subindo 38°, a malha da bota
		# dobrava na junta e fazia um bico de pato na ponta.
		var inc_dedo := inc * 0.6
		var frente_d := frente_pe * cos(inc_dedo) - cima_pe * sin(inc_dedo)
		var cima_d := cima_pe * cos(inc_dedo) + frente_pe * sin(inc_dedo)
		var dir_dedo := frente_d * cos(_desce_dedo) - cima_d * sin(_desce_dedo)
		G[s + "ToeBase"] = _girar(s + "ToeBase", dir_dedo, cima_d)
	# ---- grava no esqueleto
	for k in _sk.get_bone_count():
		var n := _nomes[k]
		var p := _pais[k]
		var g: Basis = G.get(n, Basis.IDENTITY)
		if not G.has(n):
			# osso sem comando: segue o pai
			g = G.get(_nomes[p], Basis.IDENTITY) if p >= 0 else Basis.IDENTITY
			G[n] = g
		var local := g
		if p >= 0:
			local = (G.get(_nomes[p], Basis.IDENTITY) as Basis).inverse() * g
		_sk.set_bone_pose_rotation(k, local.get_rotation_quaternion())
	_sk.set_bone_pose_position(_i["Hips"], bacia)


func _pe_com_calcanhar(k: int) -> Vector3:
	var p: Vector3 = _pe[k]
	p.y += 0.035 * clampf(_calcanhar[k], 0.0, 1.0)
	return p


func _mao_deitado(k: int, O: Dictionary, G: Dictionary) -> Vector3:
	var s := _lado_s(k)
	var peito: Vector3 = O["Spine2"]
	var g: Basis = G["Spine2"]
	return peito + g * Vector3(0.50 * s, 0.10, -0.12)


## Base global de um osso: leva a direção de repouso (até o filho) para
## `dir` e o eixo secundário de repouso para `sec`.
func _girar(osso: String, dir: Vector3, sec: Vector3) -> Basis:
	var filho := _filho(osso)
	var dR: Vector3 = (_R[filho] - _R[osso]).normalized()
	var sR: Vector3 = _secundario.get(osso, Vector3.BACK)
	var a := _ortonormal(dR, sR)
	var b := _ortonormal(dir, sec)
	return b * a.transposed()


static func _ortonormal(d: Vector3, s: Vector3) -> Basis:
	var x := d.normalized()
	var y := s - x * s.dot(x)
	if y.length() < 0.0001:
		y = x.cross(Vector3.RIGHT if absf(x.x) < 0.9 else Vector3.UP)
	y = y.normalized()
	return Basis(x, y, x.cross(y))


static func _filho(osso: String) -> String:
	if osso.ends_with("ForeArm"):
		return osso.replace("ForeArm", "Hand")
	if osso.ends_with("Arm"):
		return osso.replace("Arm", "ForeArm")
	if osso.ends_with("Hand"):
		return osso + "Middle1"
	if osso.ends_with("UpLeg"):
		return osso.replace("UpLeg", "Leg")
	if osso.ends_with("Leg"):
		return osso.replace("Leg", "Foot")
	if osso.ends_with("Foot"):
		return osso.replace("Foot", "ToeBase")
	if osso.ends_with("ToeBase"):
		return osso.replace("ToeBase", "Toe_End")
	return osso


## IK de dois ossos. Devolve [junta, ponta, direção da dobra].
static func _ik(raiz: Vector3, alvo: Vector3, l1: float, l2: float, polo: Vector3) -> Array:
	var v := alvo - raiz
	var d := clampf(v.length(), absf(l1 - l2) + 0.001, (l1 + l2) * 0.9995)
	var dir := v.normalized() if v.length() > 0.0001 else Vector3.DOWN
	var ponta := raiz + dir * d
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var dobra := polo - dir * polo.dot(dir)
	if dobra.length() < 0.0001:
		dobra = dir.cross(Vector3.RIGHT)
	dobra = dobra.normalized()
	return [raiz + dir * a + dobra * h, ponta, dobra]


# ===================================================================
# ROSTO, QUEDA E TINTA
# ===================================================================
func _rosto(dt: float) -> void:
	if _pele == null:
		return
	var a := 1.0 - exp(-dt * MESCLA_EXPR)
	for nome in _expr:
		var alvo := clampf(float(a_expr.get(nome, 0.0)), 0.0, 1.0)
		var antes := float(_expr_valor[nome])
		var v := lerpf(antes, alvo, a)
		if v < 0.002 and alvo <= 0.0:
			v = 0.0
		# Só mexe no rosto quando mudou: cada troca de peso refaz a malha
		# deformada na GPU, e o rosto parado não precisa disso.
		if absf(v - antes) > 0.0005 or (v == 0.0 and antes != 0.0):
			_expr_valor[nome] = v
			_pele.set_blend_shape_value(int(_expr[nome]), v)


func _raiz() -> void:
	# A QUEDA: o corpo gira para trás em volta dos pés e bate na lona com
	# um quique curto. Levantar é o caminho de volta.
	var alvo := clampf(queda, 0.0, 1.0)
	if alvo > _queda_vis:
		_queda_vis = minf(alvo, _queda_vis + _dt * 2.4)
	else:
		_queda_vis = alvo
	var q := _queda_vis
	var angulo := 0.0
	if q > 0.0:
		var cai := ease(q, 2.2)
		var quique := sin(clampf((q - 0.86) / 0.14, 0.0, 1.0) * PI) * 0.06
		angulo = -deg_to_rad(84.0) * cai + quique
	var s := _modelo.scale.x
	var piv := Vector3(_centro.x * s, 0.0, (_centro.y - 0.05) * s)
	var t := Transform3D.IDENTITY
	if absf(angulo) > 0.0001:
		t = Transform3D(Basis(Vector3.RIGHT, angulo), Vector3.ZERO)
		t = Transform3D(Basis.IDENTITY, piv) * t * Transform3D(Basis.IDENTITY, -piv)
		t.origin.y += 0.10 * q
	_corpo.transform = t


func _pintar() -> void:
	if not _pronto:
		return
	var brilho := clampf(_clarao, 0.0, 1.0) * 0.5
	_mat_clarao.albedo_color = Color(1.0, 0.75, 0.6) * brilho
	var ligado := brilho > 0.01
	for mi in _malhas:
		if (mi.material_overlay != null) != ligado:
			mi.material_overlay = _mat_clarao if ligado else null
	if _mat_pele != null:
		# O estrago aparece: a pele fica mais vermelha com o dano.
		var d := clampf(dano, 0.0, 1.0)
		_mat_pele.albedo_color = Color(1.0, 1.0 - 0.10 * d, 1.0 - 0.14 * d)
		if _shader_pele != null and absf(d - _dano_pintado) > 0.01:
			_dano_pintado = d
			_shader_pele.set_shader_parameter("dano", d)
