class_name LutadorModelo3D
extends Lutador3D

## O ADVERSÁRIO EM 3D DE VERDADE: malha com volume, esqueleto e golpes.
##
## O modelo é qualquer personagem com o esqueleto da Mixamo
## (`mixamorig:*`) em `assets/lutador3d/lutador.glb`. O que vem de fábrica
## é o "Vanguard" da Mixamo (uso livre em jogos), com textura própria:
## recebe só as luvas. O boneco liso "X Bot" (malhas `Beta_*`) ainda é
## reconhecido e vestido aqui mesmo (metal, capacete, calção e botas).
## Trocar o arquivo por outro personagem da Mixamo basta — a animação é feita em código em cima dos ossos, então não
## depende de o arquivo trazer animação nenhuma.
##
## A LÓGICA DO COMBATE É HERDADA de `Lutador3D` (papéis, recuo, dano,
## tombo, levantar). Aqui só muda COMO o corpo mostra cada papel: em vez
## de trocar de desenho, o esqueleto é posto em pose a cada quadro.
##
## COMO A POSE É FEITA. Para cada osso dos braços e das pernas diz-se
## PARA ONDE ELE APONTA (uma direção no espaço do personagem: +X é a
## esquerda dele, +Y cima, +Z para a frente, na direção de quem soca). O
## osso é girado da direção de descanso (pose T) até a direção pedida.
## Tronco e cabeça recebem inclinações. Depois, a bacia desce o quanto
## for preciso para os pés continuarem no chão.

const MODELO := "res://assets/lutador3d/lutador.glb"
## Quanto a mão encolhe para caber na luva.
const MAO := 0.4

## O BONECO DE FÁBRICA É ESGUIO; UM PESO-PESADO NÃO. Escala por osso
## (no eixo do próprio osso, Y ao longo dele): peito e ombros largos,
## braços e coxas grossos, bacia mais estreita.
const _PROPORCOES := {
	"Hips": Vector3(0.9, 1.0, 0.95),
	"Spine1": Vector3(1.12, 1.0, 1.08),
	"Spine2": Vector3(1.10, 1.0, 1.10),
	"Neck": Vector3(1.25, 1.0, 1.2),
	"LeftArm": Vector3(1.3, 1.0, 1.3), "RightArm": Vector3(1.3, 1.0, 1.3),
	"LeftForeArm": Vector3(1.15, 1.0, 1.15), "RightForeArm": Vector3(1.15, 1.0, 1.15),
	"LeftUpLeg": Vector3(1.12, 1.0, 1.12), "RightUpLeg": Vector3(1.12, 1.0, 1.12),
}

const COR_METAL := Color("2a2f3a")
const COR_JUNTA := Color("ff7a1a")
const COR_LUVA := Color("d0101c")
const COR_CALCAO := Color("111114")
const COR_FAIXA := Color("ffcc22")

var _modelo: Node3D = null
var _esqueleto: Skeleton3D = null
var _escala_do_armature := 1.0
var _ossos := {}                 ## nome curto -> índice
var _descanso_global := {}       ## índice -> Transform3D (espaço do esqueleto)
var _descanso_local := {}        ## índice -> Transform3D
var _direcao_de_descanso := {}   ## índice -> Vector3 (para o filho)
var _pe_de_descanso_y := 0.0
var _mat_corpo: StandardMaterial3D = null
var _mat_junta: StandardMaterial3D = null
## Clarão do golpe num personagem com textura própria: uma passada extra,
## aditiva, só nos quadros em que o clarão está aceso.
var _mat_clarao: StandardMaterial3D = null
var _malhas_com_textura: Array[MeshInstance3D] = []
var _pronto := false
var _de_fabrica := false
var _proporcoes := false
var _curto_por_indice := PackedStringArray()
## Do espaço do PERSONAGEM (+X esquerda dele, +Y cima, +Z frente) para o
## espaço do ESQUELETO. Cada exportação da Mixamo sai com eixos próprios
## (o X Bot em Y-cima olhando para +Z; o Vanguard em Z-cima olhando para
## trás), então os eixos são medidos nos próprios ossos.
var _vira := Basis.IDENTITY
var _cima := Vector3.UP
var _dedo := PackedByteArray()

## Os pedidos do quadro: direções para ossos e inclinações extras.
var _alvo := {}
var _extra := {}


func montar() -> void:
	super.montar()
	if not ResourceLoader.exists(MODELO):
		return
	var cena := load(MODELO) as PackedScene
	if cena == null:
		return
	_modelo = cena.instantiate() as Node3D
	_corpo.add_child(_modelo)
	_esqueleto = _modelo.find_child("Skeleton3D", true, false) as Skeleton3D
	if _esqueleto == null:
		return
	var pai := _esqueleto.get_parent() as Node3D
	_escala_do_armature = pai.scale.x if pai != null else 1.0
	_mapear_ossos()
	for osso in ["Hips", "Head", "LeftArm", "RightArm", "LeftForeArm", "LeftFoot", "RightFoot"]:
		if not _ossos.has(osso):
			return
	_medir_eixos()
	_pe_de_descanso_y = minf(
		_altura(_descanso_global[_ossos["LeftFoot"]].origin), _altura(_descanso_global[_ossos["RightFoot"]].origin)
	)
	# Altura igual à do desenho antigo, para o enquadramento da câmera valer.
	var topo := 0.0
	if _ossos.has("HeadTop_End"):
		topo = _altura(_descanso_global[_ossos["HeadTop_End"]].origin)
	else:
		topo = _altura(_descanso_global[_ossos["Head"]].origin) * 1.11
	topo *= _escala_do_armature
	if topo > 0.1:
		_modelo.scale = Vector3.ONE * (ALTURA_DA_FIGURA / topo)
	_vestir()
	_proporcoes = _de_fabrica
	_pronto = true
	_tocar("idle")


## Mede cima, esquerda e frente do personagem nos ossos em pose T e vira o
## modelo para olhar para a câmera (+Z), seja qual for a exportação.
func _medir_eixos() -> void:
	var g := func(n: String) -> Vector3: return (_descanso_global[_ossos[n]] as Transform3D).origin
	var cima: Vector3 = (g.call("Head") - g.call("Hips")).normalized()
	var esquerda: Vector3 = g.call("LeftArm") - g.call("RightArm")
	esquerda = (esquerda - cima * esquerda.dot(cima)).normalized()
	var frente := esquerda.cross(cima).normalized()
	_vira = Basis(esquerda, cima, frente)
	_cima = cima
	# Do esqueleto até a raiz do modelo (o Armature costuma vir girado).
	var t := Transform3D.IDENTITY
	var no: Node = _esqueleto
	while no != null and no != _modelo:
		if no is Node3D:
			t = (no as Node3D).transform * t
		no = no.get_parent()
	var f := t.basis * frente
	_modelo.rotation.y = -atan2(f.x, f.z) if Vector2(f.x, f.z).length() > 0.001 else 0.0


## Altura de um ponto do esqueleto, medida no "cima" do personagem.
func _altura(p: Vector3) -> float:
	return p.dot(_cima)


func completo() -> bool:
	return _pronto


# ---------------------------------------------------------------- ossos
func _mapear_ossos() -> void:
	var sk := _esqueleto
	_curto_por_indice.resize(sk.get_bone_count())
	_dedo.resize(sk.get_bone_count())
	for i in sk.get_bone_count():
		var nome := sk.get_bone_name(i)
		# "mixamorig:LeftArm", "mixamorig_LeftArm", "mixamorig1:LeftArm"...
		var curto := nome
		for sep in [":", "_"]:
			var p := nome.find(sep)
			if p >= 0 and nome.substr(0, p).to_lower().begins_with("mixamorig"):
				curto = nome.substr(p + 1)
				break
		_ossos[curto] = i
		_curto_por_indice[i] = curto
		# Só a primeira falange: as outras encolhem junto, por herança.
		_dedo[i] = 1 if (curto.contains("Hand") and curto.ends_with("1")) else 0
		if curto == "LeftHand" or curto == "RightHand":
			_dedo[i] = 2
		_descanso_global[i] = sk.get_bone_global_rest(i)
		_descanso_local[i] = sk.get_bone_rest(i)
	for curto in _ossos:
		var i: int = _ossos[curto]
		var filho := _filho_principal(curto)
		if filho != "" and _ossos.has(filho):
			var d: Vector3 = _descanso_global[_ossos[filho]].origin - _descanso_global[i].origin
			if d.length() > 0.0001:
				_direcao_de_descanso[i] = d.normalized()


static func _filho_principal(curto: String) -> String:
	match curto:
		"LeftArm": return "LeftForeArm"
		"LeftForeArm": return "LeftHand"
		"LeftHand": return "LeftHandMiddle1"
		"RightArm": return "RightForeArm"
		"RightForeArm": return "RightHand"
		"RightHand": return "RightHandMiddle1"
		"LeftUpLeg": return "LeftLeg"
		"LeftLeg": return "LeftFoot"
		"LeftFoot": return "LeftToeBase"
		"RightUpLeg": return "RightLeg"
		"RightLeg": return "RightFoot"
		"RightFoot": return "RightToeBase"
	return ""


# ------------------------------------------------------------- figurino
func _vestir() -> void:
	# Só o boneco de fábrica é repintado. Um personagem com textura própria
	# (trazido da Mixamo) fica como veio, ganhando apenas as luvas.
	var de_fabrica := false
	for m in _modelo.find_children("*", "MeshInstance3D", true, false):
		if str(m.name).begins_with("Beta_"):
			de_fabrica = true
	_de_fabrica = de_fabrica
	if de_fabrica:
		# O visor: a faixa acesa no lugar dos olhos dá rosto ao androide.
		var e := 1.0 / maxf(_escala_do_armature, 0.0001)
		var visor := _peca_no_osso("Head", _cilindro(0.082, 0.082, 0.028, Color("33e0ff"), 0.0), 1.0)
		if visor != null:
			var mat_v := (visor.mesh as CylinderMesh).material as StandardMaterial3D
			mat_v.emission_enabled = true
			mat_v.emission = Color("33e0ff")
			mat_v.emission_energy_multiplier = 2.2
			visor.position = Vector3(0.0, 0.075, 0.018) * e
			visor.scale = Vector3(1.05, 1.0, 1.08) * e
		# O CAPACETE DE TREINO: a cúpula vermelha
		# fazem do androide liso um boxeador de academia; o visor fica à mostra.
		var capacete := _peca_no_osso("Head", _esfera(0.128, COR_LUVA, 0.35, 0.05), 1.0)
		if capacete != null:
			capacete.position = Vector3(0.0, 0.122, -0.034) * e
			capacete.scale = Vector3(1.0, 0.9, 1.0) * e
		_mat_corpo = StandardMaterial3D.new()
		_mat_corpo.albedo_color = COR_METAL
		_mat_corpo.metallic = 0.75
		_mat_corpo.roughness = 0.32
		_mat_corpo.rim_enabled = true
		_mat_corpo.rim = 0.55
		_mat_corpo.rim_tint = 0.4
		_mat_corpo.emission_enabled = true
		_mat_corpo.emission = Color(1.0, 0.9, 0.8)
		_mat_corpo.emission_energy_multiplier = 0.0
		_mat_junta = StandardMaterial3D.new()
		_mat_junta.albedo_color = COR_JUNTA
		_mat_junta.emission_enabled = true
		_mat_junta.emission = COR_JUNTA
		_mat_junta.emission_energy_multiplier = 1.4
		for m in _modelo.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if not str(mi.name).begins_with("Beta_"):
				continue  # capacete e visor têm a cor própria
			var junta := "joint" in str(mi.name).to_lower()
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, _mat_junta if junta else _mat_corpo)
	var escala := 1.0 / maxf(_escala_do_armature, 0.0001)
	# As luvas: esferas achatadas presas às mãos.
	for lado in ["Left", "Right"]:
		var luva := _peca_no_osso(lado + "Hand", _esfera(0.072, COR_LUVA, 0.25, 0.1), escala)
		if luva != null:
			# Centro da luva sobre a mão fechada (os dedos são encolhidos
			# em `_PROPORCOES_DEDO`), cobrindo o punho inteiro.
			# A luva vive no espaço da mão ENCOLHIDA: compensa a escala dela.
			luva.position = Vector3(0.0, 0.045, 0.0) * escala / MAO
			luva.scale = Vector3(1.15, 1.35, 1.25) * escala / MAO
	if not de_fabrica:
		_mat_clarao = StandardMaterial3D.new()
		_mat_clarao.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_clarao.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat_clarao.albedo_color = Color(0.0, 0.0, 0.0)
		for m in _modelo.find_children("*", "MeshInstance3D", true, false):
			_malhas_com_textura.append(m as MeshInstance3D)
		return  # personagem com roupa própria: só as luvas
	# O calção: tronco de cone na bacia, dois tubos nas coxas e a faixa.
	var calcao := _peca_no_osso("Hips", _cilindro(0.150, 0.160, 0.15, COR_CALCAO), escala)
	if calcao != null:
		calcao.position = Vector3(0.0, -0.01, 0.0) * escala
		calcao.scale = Vector3.ONE * escala
	var faixa := _peca_no_osso("Hips", _cilindro(0.156, 0.154, 0.045, COR_FAIXA, 0.8), escala)
	if faixa != null:
		faixa.position = Vector3(0.0, 0.075, 0.0) * escala
		faixa.scale = Vector3.ONE * escala
	for lado in ["Left", "Right"]:
		var perna := _peca_no_osso(lado + "UpLeg", _cilindro(0.118, 0.108, 0.22, COR_CALCAO), escala)
		if perna != null:
			perna.position = Vector3(0.0, -0.10, 0.0) * escala
			perna.scale = Vector3.ONE * escala
	# As botas de cano alto: pretas, com o cano amarelo.
	for lado in ["Left", "Right"]:
		var bota := _peca_no_osso(lado + "Leg", _cilindro(0.058, 0.052, 0.13, COR_CALCAO), escala)
		if bota != null:
			bota.position = Vector3(0.0, -0.37, 0.0) * escala
			bota.scale = Vector3.ONE * escala
		var cano := _peca_no_osso(lado + "Leg", _cilindro(0.061, 0.060, 0.022, COR_FAIXA, 0.6), escala)
		if cano != null:
			cano.position = Vector3(0.0, -0.30, 0.0) * escala
			cano.scale = Vector3.ONE * escala


func _peca_no_osso(curto: String, malha: MeshInstance3D, _escala: float) -> MeshInstance3D:
	if not _ossos.has(curto):
		return null
	var presa := BoneAttachment3D.new()
	presa.bone_idx = _ossos[curto]
	_esqueleto.add_child(presa)
	presa.add_child(malha)
	return malha


static func _esfera(raio: float, cor: Color, aspereza: float, brilho: float) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = raio
	m.height = raio * 2.0
	m.radial_segments = 20
	m.rings = 12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = cor
	mat.roughness = aspereza
	mat.metallic = 0.1
	mat.rim_enabled = true
	mat.rim = 0.4
	mat.emission_enabled = brilho > 0.0
	mat.emission = cor
	mat.emission_energy_multiplier = brilho
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	return mi


static func _cilindro(r_topo: float, r_base: float, altura: float, cor: Color, metal := 0.0) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r_topo
	m.bottom_radius = r_base
	m.height = altura
	m.radial_segments = 20
	m.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = cor
	mat.roughness = 0.55 if metal <= 0.0 else 0.3
	mat.metallic = metal
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	return mi


# ------------------------------------------------------------ movimento
func _mover_o_corpo() -> void:
	if not _pronto:
		return
	_alvo.clear()
	_extra.clear()
	var armado := _papel == "guard"
	var festa := _papel == "celebra"
	var calma := 1.0 - clampf(_recuo * 1.4, 0.0, 1.0)
	if _caindo:
		calma = 0.0

	# A GINGA: quique, balanço lateral e o tronco acompanhando.
	var compasso := 1.55 if armado else 1.25
	var fase := _relogio * TAU * compasso * 0.5
	var lado := sin(fase)
	var quique := absf(sin(fase * 2.0))
	var amplo := (0.65 if armado else 1.0) * calma

	# TRONCO E CABEÇA: um pouco à frente, queixo recolhido.
	_inclinar("Spine", Vector3.RIGHT, deg_to_rad(6.0))
	_inclinar("Spine1", Vector3.RIGHT, deg_to_rad(5.0))
	_inclinar("Spine2", Vector3.FORWARD, deg_to_rad(4.0) * lado * amplo)
	_inclinar("Head", Vector3.RIGHT, deg_to_rad(10.0))

	# A GUARDA: cotovelos embaixo, luvas na altura do queixo.
	var fechada := 1.0 if armado else 0.7
	_apontar("LeftArm", Vector3(0.34, -0.55, 0.70 + 0.10 * fechada))
	_apontar("LeftForeArm", Vector3(-0.22 * fechada, 0.46, 0.86))
	_apontar("RightArm", Vector3(-0.36, -0.62, 0.55 + 0.08 * fechada))
	_apontar("RightForeArm", Vector3(0.24 * fechada, 0.56, 0.76))
	_apontar("LeftHand", Vector3(-0.1, 0.55, 0.8))
	_apontar("RightHand", Vector3(0.1, 0.6, 0.75))

	# BASE DE LUTA: pé esquerdo à frente, joelhos dobrados.
	_apontar("LeftUpLeg", Vector3(0.24, -0.90, 0.36))
	_apontar("LeftLeg", Vector3(0.06, -0.96, -0.22))
	_apontar("RightUpLeg", Vector3(-0.24, -0.92, -0.10))
	_apontar("RightLeg", Vector3(-0.06, -0.94, -0.34))
	_apontar("LeftFoot", Vector3(0.1, -0.35, 0.93))
	_apontar("RightFoot", Vector3(-0.2, -0.35, 0.91))

	# O JOGO DE PERNAS: um joelho sobe de cada vez, no ritmo da ginga.
	# A bacia desce até o pé mais baixo, então o outro pé sai do chão.
	var passo_e := maxf(0.0, lado) * amplo
	var passo_d := maxf(0.0, -lado) * amplo
	_misturar("LeftUpLeg", Vector3(0.22, -0.70, 0.70), passo_e * 0.55)
	_misturar("LeftLeg", Vector3(0.05, -0.80, -0.60), passo_e * 0.55)
	_misturar("RightUpLeg", Vector3(-0.22, -0.72, 0.45), passo_d * 0.55)
	_misturar("RightLeg", Vector3(-0.05, -0.80, -0.62), passo_d * 0.55)

	# A COMEMORAÇÃO: aguentou a rodada — braços para o alto com a torcida.
	if festa:
		var entra := clampf(_tempo_no_papel * 3.0, 0.0, 1.0)
		var soco := sin(_relogio * TAU * 1.6)
		_misturar("LeftArm", Vector3(0.45, 0.88, 0.10), entra)
		_misturar("RightArm", Vector3(-0.45, 0.88, 0.10), entra)
		_misturar("LeftForeArm", Vector3(0.15, 1.0, 0.10 + 0.25 * soco), entra)
		_misturar("RightForeArm", Vector3(-0.15, 1.0, 0.10 - 0.25 * soco), entra)
		_misturar("LeftHand", Vector3(0.0, 1.0, 0.1), entra)
		_misturar("RightHand", Vector3(0.0, 1.0, 0.1), entra)
		_inclinar("Head", Vector3.RIGHT, deg_to_rad(-26.0) * entra)
		_inclinar("Spine1", Vector3.RIGHT, deg_to_rad(-10.0) * entra)
		_inclinar("Spine2", Vector3.UP, deg_to_rad(18.0) * sin(_relogio * TAU * 0.4) * entra)

	# SOMBRA DE BOXE / PROVOCAÇÃO: jab, direto, jab.
	if _papel == "taunt_weak":
		var janela := 0.30
		var golpe := int(_tempo_no_papel / janela)
		var dentro := fmod(_tempo_no_papel, janela) / janela
		var estica := sin(clampf(dentro, 0.0, 1.0) * PI)
		if golpe == 0 or golpe == 2:
			_misturar("LeftArm", Vector3(0.12, 0.06, 1.0), estica)
			_misturar("LeftForeArm", Vector3(0.02, 0.05, 1.0), estica)
			_inclinar("Spine2", Vector3.UP, deg_to_rad(-12.0) * estica)
		elif golpe == 1:
			_misturar("RightArm", Vector3(-0.08, 0.06, 1.0), estica)
			_misturar("RightForeArm", Vector3(0.0, 0.05, 1.0), estica)
			_inclinar("Spine2", Vector3.UP, deg_to_rad(22.0) * estica)

	# O GOLPE RECEBIDO: cabeça para trás, tronco dobra, guarda abre.
	var receita: Dictionary = RECUO.get(_papel, {})
	if not receita.is_empty() and _recuo > 0.001 and _papel != "taunt_weak":
		var impacto := ease(_recuo, 0.35) * (0.55 + _forca_do_recuo * 0.65)
		var peso := clampf(float(receita["tombo"]) * 5.0, 0.3, 1.2) * impacto
		_inclinar("Head", Vector3.RIGHT, deg_to_rad(-38.0) * peso)
		_inclinar("Spine1", Vector3.RIGHT, deg_to_rad(-16.0) * peso)
		_inclinar("Spine2", Vector3.FORWARD, deg_to_rad(14.0) * _lado * peso)
		_misturar("LeftForeArm", Vector3(0.7, 0.5, 0.3), peso * 0.7)
		_misturar("RightForeArm", Vector3(-0.7, 0.5, 0.3), peso * 0.7)
		if _papel == "stagger":
			_inclinar("Hips", Vector3.FORWARD, sin(_tempo_no_papel * 11.0) * deg_to_rad(8.0) * impacto)

	# NA LONA: braços abertos, pernas soltas.
	if queda > 0.001:
		var q := ease(clampf(queda, 0.0, 1.0), 0.55)
		_misturar("LeftArm", Vector3(1.0, 0.25, -0.1), q)
		_misturar("RightArm", Vector3(-1.0, 0.25, -0.1), q)
		_misturar("LeftForeArm", Vector3(0.9, 0.4, -0.2), q)
		_misturar("RightForeArm", Vector3(-0.9, 0.4, -0.2), q)
		# As pernas esticam e se abrem: deitado, o corpo fica comprido na lona.
		_misturar("LeftUpLeg", Vector3(0.22, -0.97, 0.0), q)
		_misturar("RightUpLeg", Vector3(-0.22, -0.97, 0.0), q)
		_misturar("LeftLeg", Vector3(0.05, -1.0, 0.05), q)
		_misturar("RightLeg", Vector3(-0.05, -1.0, 0.05), q)
		_inclinar("Head", Vector3.FORWARD, deg_to_rad(25.0) * q)

	var pulo := 0.0
	if festa:
		pulo = absf(sin(_relogio * TAU * 1.1)) * 0.10
	_aplicar_pose(quique * 0.028 * amplo + pulo)

	# O CORPO INTEIRO: balanço, recuo do golpe e o tombo para trás.
	var t := Transform3D.IDENTITY
	t.origin.x += lado * 0.06 * amplo
	# Entra e sai da distância, como quem mede o adversário.
	t.origin.z += sin(fase * 0.5) * 0.05 * amplo
	if not receita.is_empty() and _recuo > 0.001 and _papel != "taunt_weak":
		var impacto2 := ease(_recuo, 0.35)
		t.origin.z -= float(receita["tras"]) * impacto2 * (0.55 + _forca_do_recuo * 0.65)
		t.origin.x += _lado * float(receita["lado"]) * impacto2
	if queda > 0.001:
		var q2 := ease(clampf(queda, 0.0, 1.0), 0.55)
		t.basis = t.basis.rotated(Vector3.RIGHT, -deg_to_rad(84.0) * q2)
		t.origin.z -= 0.35 * q2
		t.origin.y += 0.10 * q2
	_corpo.transform = t


## Aponta um osso numa direção (espaço do personagem).
func _apontar(curto: String, direcao: Vector3) -> void:
	_alvo[curto] = (_vira * direcao).normalized()


## Mistura a direção atual do osso com outra, pelo peso `w`.
func _misturar(curto: String, direcao: Vector3, w: float) -> void:
	if w <= 0.0:
		return
	var d := (_vira * direcao).normalized()
	var atual: Vector3 = _alvo.get(curto, d)
	_alvo[curto] = atual.lerp(d, clampf(w, 0.0, 1.0)).normalized()


## Inclinação extra (eixo e ângulo no espaço do personagem), acumulada.
func _inclinar(curto: String, eixo: Vector3, angulo: float) -> void:
	var q := Quaternion((_vira * eixo).normalized(), angulo)
	_extra[curto] = q * (_extra.get(curto, Quaternion.IDENTITY) as Quaternion)


func _aplicar_pose(subida: float) -> void:
	var sk := _esqueleto
	var global := {}
	var pe_min := INF
	for i in sk.get_bone_count():
		var pai := sk.get_bone_parent(i)
		var local: Transform3D = _descanso_local[i]
		var pai_global: Transform3D = global[pai] if pai >= 0 else Transform3D.IDENTITY
		var curto := _curto_por_indice[i]
		var g := pai_global * local
		if _alvo.has(curto) and _direcao_de_descanso.has(i):
			var de: Vector3 = _direcao_de_descanso[i]
			var para: Vector3 = _alvo[curto]
			var giro := _giro_entre(de, para)
			g.basis = Basis(giro) * (_descanso_global[i] as Transform3D).basis
		if _extra.has(curto):
			g.basis = Basis(_extra[curto] as Quaternion) * g.basis
		var nova_local := Transform3D(pai_global.basis.inverse() * g.basis, local.origin)
		if pai < 0:
			nova_local.origin = local.origin
		global[i] = pai_global * nova_local
		sk.set_bone_pose_rotation(i, nova_local.basis.get_rotation_quaternion())
		if _proporcoes:
			sk.set_bone_pose_scale(i, _PROPORCOES.get(curto, Vector3.ONE))
		if _dedo[i] == 1:
			# Mão fechada dentro da luva: o dedo encolhe até sumir nela.
			sk.set_bone_pose_scale(i, Vector3.ONE * 0.10)
		elif _dedo[i] == 2:
			# A própria mão encolhe para caber inteira na luva.
			sk.set_bone_pose_scale(i, Vector3.ONE * MAO)
		if curto == "LeftFoot" or curto == "RightFoot":
			pe_min = minf(pe_min, _altura((global[i] as Transform3D).origin))
	# OS PÉS NO CHÃO: a bacia desce o que os joelhos dobraram.
	var hips: int = _ossos["Hips"]
	var desce := 0.0 if pe_min == INF else (pe_min - _pe_de_descanso_y)
	var subida_local := subida / maxf(_escala_do_armature * _modelo.scale.y, 0.0001)
	sk.set_bone_pose_position(hips, (_descanso_local[hips] as Transform3D).origin - _cima * (desce - subida_local))


static func _giro_entre(de: Vector3, para: Vector3) -> Quaternion:
	var d := de.dot(para)
	if d > 0.9999:
		return Quaternion.IDENTITY
	if d < -0.9999:
		var eixo := de.cross(Vector3.UP)
		if eixo.length() < 0.001:
			eixo = de.cross(Vector3.RIGHT)
		return Quaternion(eixo.normalized(), PI)
	return Quaternion(de.cross(para).normalized(), acos(clampf(d, -1.0, 1.0)))


# ---------------------------------------------------------------- tinta
func _pintar() -> void:
	if _mat_clarao != null:
		var brilho := clampf(_clarao, 0.0, 1.0) * 0.55
		_mat_clarao.albedo_color = Color(1.0, 0.75, 0.6) * brilho
		var ligado := brilho > 0.01
		for mi in _malhas_com_textura:
			if (mi.material_overlay != null) != ligado:
				mi.material_overlay = _mat_clarao if ligado else null
	if _mat_corpo != null:
		_mat_corpo.emission_energy_multiplier = clampf(_clarao, 0.0, 1.0) * 0.9
	if _mat_junta != null:
		var castigo := clampf(dano, 0.0, 1.0)
		var cor := COR_JUNTA.lerp(Color("ff1030"), castigo)
		_mat_junta.emission = cor
		_mat_junta.albedo_color = cor
		_mat_junta.emission_energy_multiplier = 1.4 + castigo * 1.2 + _clarao * 2.0

