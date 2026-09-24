class_name LutadorMixamo3D
extends Lutador3D
## LUTADOR EXTERNO: qualquer personagem com esqueleto Mixamo e animações
## prontas, trocado sem mexer em código.
##
## Coloque em `assets/lutador_mixamo/`:
##   personagem.fbx (ou .glb)  — o personagem, com pele ("With Skin")
##   e uma animação por papel, com estes nomes (FBX "Without Skin", ou GLB):
##     guarda       idle de boxe (obrigatória)
##     golpe_leve   levou um soco leve
##     golpe_forte  levou um soco forte
##     cordas       cambaleia para trás (vai às cordas)
##     nocaute      cai nocauteado
##     levantar     levanta da lona
##     comemora     vitória
##     deboche      provocação
##     soco_tela    soco de direita (vem para a câmera)
##     tonto        zonzo
## Só `guarda` é obrigatória; faltando alguma, o papel usa a mais parecida.
## Marque "In Place" na Mixamo (senão o corpo anda pelo ringue sozinho).
##
## Se a pasta não tiver personagem, este lutador não entra e o boxeador
## gerado (`LutadorBoxeador3D`) continua sendo o da arena.

const PASTA := "res://assets/lutador_mixamo/"
const MESCLA := 0.16

## papel -> [arquivo, repete, velocidade, reservas...]
const RECEITA := {
	"idle": ["guarda", true, 1.0],
	"guard": ["guarda", true, 1.15],
	"taunt_weak": ["deboche", false, 1.3, "golpe_leve"],
	"hit_light": ["golpe_leve", false, 1.3],
	"hit_medium": ["golpe_leve", false, 1.1],
	"hit_heavy": ["golpe_forte", false, 1.1, "golpe_leve"],
	"stagger": ["golpe_forte", false, 0.9, "golpe_leve"],
	"cordas": ["cordas", false, 1.0, "golpe_forte", "golpe_leve"],
	"knockout": ["nocaute", false, 1.0, "golpe_forte"],
	"get_up": ["levantar", false, 1.0, "guarda"],
	"celebra": ["comemora", true, 1.0, "deboche", "guarda"],
	"deboche": ["deboche", true, 1.1, "comemora", "guarda"],
	"tonto": ["tonto", true, 1.0, "golpe_forte", "guarda"],
	"soco_tela": ["soco_tela", false, 1.2, "deboche", "guarda"],
}

var _modelo: Node3D = null
var _anim: AnimationPlayer = null
var _caminho_esqueleto := ""
var _sk: Skeleton3D = null
var _nomes: Dictionary = {}   # papel -> nome da animação na biblioteca
var _tocando := ""
var _pronto := false
var _mat_clarao: StandardMaterial3D = null
var _malhas: Array[MeshInstance3D] = []
var _tela_ok := false
var _tela_bateu := false


static func arquivo(nome: String) -> String:
	for ext in ["glb", "fbx", "gltf"]:
		var p: String = PASTA + nome + "." + str(ext)
		if ResourceLoader.exists(p):
			return p
	return ""


func montar() -> void:
	super.montar()
	var fonte := arquivo("personagem")
	if fonte.is_empty() or arquivo("guarda").is_empty():
		return
	var cena := load(fonte) as PackedScene
	if cena == null:
		return
	_modelo = cena.instantiate() as Node3D
	_corpo.add_child(_modelo)
	var esqueleto := _modelo.find_children("*", "Skeleton3D", true, false)
	if esqueleto.is_empty():
		return
	var sk := esqueleto[0] as Skeleton3D
	_sk = sk
	_caminho_esqueleto = str(_modelo.get_path_to(sk))
	var achados := _modelo.find_children("*", "AnimationPlayer", true, false)
	if achados.is_empty():
		_anim = AnimationPlayer.new()
		_modelo.add_child(_anim)
		_anim.root_node = _anim.get_path_to(_modelo)
	else:
		_anim = achados[0] as AnimationPlayer
	var biblioteca := AnimationLibrary.new()
	var carregadas := {}
	for papel in RECEITA:
		var receita: Array = RECEITA[papel]
		for k in range(receita.size()):
			if k == 1 or k == 2:
				continue
			var nome: String = receita[k]
			if not carregadas.has(nome):
				carregadas[nome] = _carregar_animacao(nome)
			if carregadas[nome] != null:
				var a: Animation = carregadas[nome]
				if not biblioteca.has_animation(nome):
					biblioteca.add_animation(nome, a)
				_nomes[papel] = "lutador/" + nome
				break
	if not _nomes.has("guard"):
		return
	if _anim.has_animation_library("lutador"):
		_anim.remove_animation_library("lutador")
	_anim.add_animation_library("lutador", biblioteca)
	for papel in RECEITA:
		if _nomes.has(papel) and bool(RECEITA[papel][1]):
			_anim.get_animation(_nomes[papel]).loop_mode = Animation.LOOP_LINEAR
	_escalar(sk)
	_luvas(sk)
	_mat_clarao = StandardMaterial3D.new()
	_mat_clarao.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_clarao.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_clarao.albedo_color = Color.BLACK
	for m in _modelo.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_malhas.append(mi)
	_pronto = true
	_tocar("idle")


## A primeira animação do arquivo, com as trilhas apontando para o
## esqueleto DESTE personagem (os caminhos de dentro de cada arquivo da
## Mixamo mudam; o nome do osso não).
func _carregar_animacao(nome: String) -> Animation:
	var p := arquivo(nome)
	if p.is_empty():
		return null
	var cena := load(p) as PackedScene
	if cena == null:
		return null
	var raiz := cena.instantiate()
	var tocadores := raiz.find_children("*", "AnimationPlayer", true, false)
	var resultado: Animation = null
	if not tocadores.is_empty():
		var ap := tocadores[0] as AnimationPlayer
		for lista in ap.get_animation_library_list():
			var lib := ap.get_animation_library(lista)
			for n in lib.get_animation_list():
				if str(n).to_lower() == "reset":
					continue
				resultado = (lib.get_animation(n) as Animation).duplicate(true)
				break
			if resultado != null:
				break
	raiz.free()
	if resultado == null:
		return null
	for t in range(resultado.get_track_count() - 1, -1, -1):
		var caminho := str(resultado.track_get_path(t))
		var dois := caminho.rfind(":")
		if dois < 0:
			resultado.remove_track(t)
			continue
		var osso := caminho.substr(dois + 1)
		resultado.track_set_path(t, NodePath(_caminho_esqueleto + ":" + osso))
		if resultado.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var i_osso := _sk.find_bone(osso) if _sk != null else -1
		if i_osso < 0:
			continue
		var repouso: Vector3 = _sk.get_bone_rest(i_osso).origin
		if not osso.to_lower().ends_with("hips"):
			# Só o quadril se move; os outros ossos ficam no comprimento
			# do personagem (arquivos de animação de outro corpo esticariam).
			resultado.remove_track(t)
			continue
		# "IN PLACE" E NA ESCALA DESTE CORPO: o quadril fica na posição de
		# repouso do personagem e herda da animação só o sobe-e-desce
		# (na proporção certa, mesmo com a animação em outra unidade).
		var n_chaves := resultado.track_get_key_count(t)
		if n_chaves == 0:
			continue
		var v0: Vector3 = resultado.track_get_key_value(t, 0)
		var k_escala := repouso.y / v0.y if absf(v0.y) > 0.0001 else 1.0
		for k in n_chaves:
			var v: Vector3 = resultado.track_get_key_value(t, k)
			resultado.track_set_key_value(t, k, Vector3(repouso.x, repouso.y + (v.y - v0.y) * k_escala, repouso.z))
	return resultado


## Altura e frente pelo ESQUELETO (a caixa de uma malha com pele não é
## confiável: vem na escala do arquivo, às vezes em centímetros).
func _escalar(sk: Skeleton3D) -> void:
	var topo := -INF
	var base := INF
	var esq := Vector3.ZERO
	var dir := Vector3.ZERO
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		var p := sk.global_transform * sk.get_bone_global_rest(i).origin
		if n.ends_with("HeadTop_End"):
			topo = maxf(topo, p.y)
		elif n.ends_with("Head") and topo == -INF:
			topo = p.y + 0.12 * absf(p.y)
		if n.ends_with("Foot") or n.ends_with("ToeBase") or n.ends_with("Toe_End"):
			base = minf(base, p.y)
		if n.ends_with("LeftArm"):
			esq = p
		elif n.ends_with("RightArm"):
			dir = p
	if topo > -INF and base < INF and topo - base > 0.0001:
		_modelo.scale *= ALTURA_DA_FIGURA / ((topo - base) * 1.04)
	# De frente para a câmera (+Z): o braço ESQUERDO dele fica à DIREITA
	# de quem olha (+X). Ao contrário, o arquivo está de costas: meia volta.
	if esq != Vector3.ZERO and dir != Vector3.ZERO and esq.x < dir.x:
		_modelo.rotate_y(PI)
	# Pés no chão.
	var chao := INF
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if n.ends_with("Toe_End") or n.ends_with("ToeBase") or n.ends_with("Foot"):
			chao = minf(chao, (sk.global_transform * sk.get_bone_global_rest(i).origin).y)
	if chao < INF:
		_modelo.position.y -= chao - 0.02


## Luvas de boxe presas às mãos (a Mixamo não tem boxeador de luva).
func _luvas(sk: Skeleton3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("c8101c")
	mat.roughness = 0.25
	mat.rim_enabled = true
	mat.rim = 0.5
	var branco := StandardMaterial3D.new()
	branco.albedo_color = Color("f2f2f0")
	branco.roughness = 0.4
	for lado in ["Left", "Right"]:
		var osso := -1
		for i in sk.get_bone_count():
			var n := sk.get_bone_name(i)
			if n.ends_with(lado + "Hand"):
				osso = i
				break
		if osso < 0:
			continue
		var presa := BoneAttachment3D.new()
		presa.bone_idx = osso
		sk.add_child(presa)
		var escala := 1.0 / maxf(sk.global_transform.basis.get_scale().x, 0.00001)
		var corpo := MeshInstance3D.new()
		var bola := SphereMesh.new()
		bola.radius = 0.075
		bola.height = 0.15
		bola.material = mat
		corpo.mesh = bola
		corpo.scale = Vector3(1.05, 1.25, 1.0) * escala
		corpo.position = Vector3(0.0, 0.07, 0.015) * escala
		presa.add_child(corpo)
		var punho := MeshInstance3D.new()
		var cano := CylinderMesh.new()
		cano.top_radius = 0.052
		cano.bottom_radius = 0.058
		cano.height = 0.07
		cano.material = branco
		punho.mesh = cano
		punho.scale = Vector3.ONE * escala
		punho.position = Vector3(0.0, -0.01, 0.0) * escala
		presa.add_child(punho)


func completo() -> bool:
	return _pronto


func poses() -> PackedStringArray:
	return PackedStringArray(["guard", "hit_heavy", "knockout", "celebra"])


func soco_na_tela() -> bool:
	if not _pronto or _caindo or _papel in PAPEIS_DE_FESTA:
		return false
	_tela_ok = true
	_tela_bateu = false
	_tempo_reacao = 1.6
	_tocar("soco_tela")
	return true


func soco_final() -> bool:
	if not _pronto or _caindo:
		return false
	_tela_ok = true
	_tela_bateu = false
	_tempo_reacao = 1.6
	_papel = ""
	_tocar("soco_tela")
	return true


func tela_atingida() -> bool:
	if _tela_bateu:
		_tela_bateu = false
		return true
	return false


func _mover_o_corpo() -> void:
	if not _pronto:
		return
	if _papel != _tocando:
		_tocando = _papel
		var nome: String = _nomes.get(_papel, _nomes["guard"])
		var velocidade: float = float(RECEITA.get(_papel, RECEITA["guard"])[2])
		if _papel == "get_up":
			velocidade = _anim.get_animation(nome).length / TEMPO_LEVANTAR
		_anim.play(nome, MESCLA, velocidade)
	if _papel == "soco_tela" and _tela_ok and _tempo_no_papel >= 0.55:
		_tela_ok = false
		_tela_bateu = true
	var t := Transform3D.IDENTITY
	var receita_recuo: Dictionary = RECUO.get(_papel, {})
	if not receita_recuo.is_empty() and _recuo > 0.001 and _papel != "taunt_weak":
		var impacto := ease(_recuo, 0.35) * (0.55 + _forca_do_recuo * 0.65)
		t.origin.z -= float(receita_recuo["tras"]) * impacto
		t.origin.x += _lado * float(receita_recuo["lado"]) * impacto
	if _papel == "soco_tela":
		# vem para a câmera e volta
		t.origin.z += sin(clampf(_tempo_no_papel / 1.2, 0.0, 1.0) * PI) * 0.9
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
