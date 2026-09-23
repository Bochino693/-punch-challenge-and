class_name LutadorAnimado3D
extends Lutador3D

## O ADVERSÁRIO HUMANO: um guerreiro com textura e ANIMAÇÕES DE VERDADE.
##
## O modelo é o Bárbaro do "KayKit Adventurers" (Kay Lousberg, CC0 — uso
## livre, inclusive comercial), em `assets/lutador3d/barbaro.glb`. Ele já
## vem com dezenas de animações feitas à mão; aqui cada papel do combate
## (`Lutador3D`) escolhe a sua: guarda de punhos erguidos, os dois tipos
## de golpe recebido, a queda, o levantar da lona e a comemoração.
##
## As armas, o escudo e a caneca que o pacote pendura nas mãos ficam
## escondidos: no lugar deles entram as luvas vermelhas de boxe.

const MODELO := "res://assets/lutador3d/barbaro.glb"
const COR_LUVA := Color("d0101c")
const MESCLA := 0.18
## O guerreiro tem cabeça grande (estilo do pacote): um pouco menor que a
## figura de referência, para caber inteiro no quadro com folga em cima.
const ALTURA := ALTURA_DA_FIGURA * 0.84

## papel -> [animação, repete, velocidade]
const ANIMACOES := {
	"idle": ["Idle", true, 1.0],
	"guard": ["Unarmed_Idle", true, 1.15],
	"taunt_weak": ["Unarmed_Melee_Attack_Punch_A", false, 1.25],
	"hit_light": ["Hit_A", false, 1.25],
	"hit_medium": ["Hit_A", false, 1.0],
	"hit_heavy": ["Hit_B", false, 1.0],
	"stagger": ["Hit_B", false, 0.7],
	"knockout": ["Death_A", false, 1.0],
	"get_up": ["Lie_StandUp", false, 1.0],
	"celebra": ["Cheer", true, 1.0],
}

var _modelo: Node3D = null
var _anim: AnimationPlayer = null
var _tocando := ""
var _pronto := false
var _mat_clarao: StandardMaterial3D = null
var _malhas: Array[MeshInstance3D] = []


func montar() -> void:
	super.montar()
	if not ResourceLoader.exists(MODELO):
		return
	var cena := load(MODELO) as PackedScene
	if cena == null:
		return
	_modelo = cena.instantiate() as Node3D
	_corpo.add_child(_modelo)
	var achados := _modelo.find_children("*", "AnimationPlayer", true, false)
	var esqueleto := _modelo.find_child("Skeleton3D", true, false) as Skeleton3D
	if achados.is_empty() or esqueleto == null:
		return
	_anim = achados[0] as AnimationPlayer
	for papel in ANIMACOES:
		var nome: String = ANIMACOES[papel][0]
		if not _anim.has_animation(nome):
			return
		if bool(ANIMACOES[papel][1]):
			_anim.get_animation(nome).loop_mode = Animation.LOOP_LINEAR
	# Nada nas mãos: armas, escudo e caneca vivem presos aos "handslots".
	for presa in _modelo.find_children("*", "BoneAttachment3D", true, false):
		if "handslot" in str(presa.name).to_lower():
			(presa as Node3D).visible = false
	_escalar(esqueleto)
	_calcar_luvas(esqueleto)
	_mat_clarao = StandardMaterial3D.new()
	_mat_clarao.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_clarao.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_clarao.albedo_color = Color.BLACK
	for m in _modelo.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).is_visible_in_tree():
			_malhas.append(m as MeshInstance3D)
	_pronto = true
	_tocar("idle")


func completo() -> bool:
	return _pronto


## Altura igual à do desenho antigo, para o enquadramento da câmera valer.
func _escalar(esqueleto: Skeleton3D) -> void:
	var topo := 0.0
	for m in _modelo.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var caixa := mi.get_aabb()
		topo = maxf(topo, caixa.end.y)
	if topo <= 0.01:
		var cabeca := esqueleto.find_bone("head")
		topo = esqueleto.get_bone_global_rest(cabeca).origin.y * 1.6 if cabeca >= 0 else 1.0
	_modelo.scale = Vector3.ONE * (ALTURA / topo)


func _calcar_luvas(esqueleto: Skeleton3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COR_LUVA
	mat.roughness = 0.28
	mat.metallic = 0.1
	mat.rim_enabled = true
	mat.rim = 0.4
	for lado in ["l", "r"]:
		var osso := esqueleto.find_bone("hand." + lado)
		if osso < 0:
			continue
		var presa := BoneAttachment3D.new()
		presa.bone_idx = osso
		esqueleto.add_child(presa)
		var bola := SphereMesh.new()
		bola.radius = 0.19
		bola.height = 0.38
		bola.radial_segments = 20
		bola.rings = 10
		bola.material = mat
		var luva := MeshInstance3D.new()
		luva.mesh = bola
		luva.scale = Vector3(1.0, 1.15, 1.1)
		luva.position = Vector3(0.0, 0.06, 0.0)
		presa.add_child(luva)


func _mover_o_corpo() -> void:
	if not _pronto:
		return
	if _papel != _tocando:
		_tocando = _papel
		var receita: Array = ANIMACOES.get(_papel, ANIMACOES["idle"])
		var nome: String = receita[0]
		var velocidade: float = receita[2]
		if _papel == "get_up":
			# O levantar dura exatamente o tempo que a lógica espera.
			velocidade = _anim.get_animation(nome).length / TEMPO_LEVANTAR
		_anim.play(nome, MESCLA, velocidade)

	# O corpo inteiro por cima da animação: a ginga lateral na guarda e o
	# recuo do golpe, proporcional à força.
	var t := Transform3D.IDENTITY
	var calma := 1.0 - clampf(_recuo * 1.4, 0.0, 1.0)
	if _papel == "guard" or _papel == "idle":
		var fase := _relogio * TAU * 0.75
		t.origin.x += sin(fase) * 0.07 * calma
		t.origin.z += sin(fase * 0.5) * 0.05 * calma
	var receita_recuo: Dictionary = RECUO.get(_papel, {})
	if not receita_recuo.is_empty() and _recuo > 0.001 and _papel != "taunt_weak":
		var impacto := ease(_recuo, 0.35) * (0.55 + _forca_do_recuo * 0.65)
		t.origin.z -= float(receita_recuo["tras"]) * impacto
		t.origin.x += _lado * float(receita_recuo["lado"]) * impacto
		if _papel == "stagger":
			t.basis = t.basis.rotated(Vector3.FORWARD, sin(_tempo_no_papel * 9.0) * 0.12 * impacto)
	_corpo.transform = t


func _pintar() -> void:
	if _mat_clarao == null:
		return
	var brilho := clampf(_clarao, 0.0, 1.0) * 0.55
	_mat_clarao.albedo_color = Color(1.0, 0.75, 0.6) * brilho
	var ligado := brilho > 0.01
	for mi in _malhas:
		if (mi.material_overlay != null) != ligado:
			mi.material_overlay = _mat_clarao if ligado else null
