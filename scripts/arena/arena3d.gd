class_name Arena3D
extends SubViewport

## A ARENA: um mundo 3D pequeno, renderizado numa janela própria e colado
## na tela 2D pelo `main.gd` (ver `ArenaQuadro`).
##
## Feita para TV Box:
##   • fundo, lona e luzes são TEXTURAS prontas (`tools/gerar_arena.py`)
##     em materiais sem iluminação: cada superfície é um desenho só;
##   • cordas e postes são malhas redondas com luz de verdade, e a janela
##     usa MSAA 4x — contorno liso sem supersample;
##   • a janela tem o tamanho real, em pixels, do buraco da moldura na
##     tela (nada de esticar textura pequena);
##   • partículas com quantidade fixa (mudar `amount` realoca buffers e
##     engasga) e shaders compilados no arranque (`aquecer`).

const TELA_LOGICA := Vector2(688.0, 770.0)
## Degrau magro para quando o vigia de desempenho apertar.
const FATOR_MAGRO := 0.75
const DESCE_PARA_MAGRO := 0.50
const SOBE_PARA_CHEIO := 0.62
## Teto de resolução em telas 4K: acima disto o ganho não aparece e o
## custo na GPU da TV Box sim.
const FATOR_MAXIMO := 1.5

## Enquadramento: quanto da altura da janela o lutador em pé ocupa, e
## quanto a câmera fica acima da mira (a leve inclinação de transmissão).
const OCUPACAO_DO_LUTADOR := 0.79
const CAMERA_ACIMA_DA_MIRA := 0.21

## O ringue (metros). A meia largura põe os postes de trás nas bordas do
## quadro, que é o que faz a imagem ler como ringue.
const MEIO_RINGUE := 1.6
const ALTURAS_DAS_CORDAS := [0.42, 0.82, 1.22]
const PISO_DO_LUTADOR := 0.004

const TEX_FUNDO := "res://assets/arena/fundo.png"
const TEX_LONA := "res://assets/arena/lona.png"
const TEX_BRILHO := "res://assets/arena/brilho.png"
const TEX_FACHO := "res://assets/arena/facho.png"

const COR_FUNDO := Color("07060b")

var lutador: Lutador3D = null
var camera: Camera3D = null
## 1.0 = tudo; abaixo de `DESCE_PARA_MAGRO` a janela encolhe.
var qualidade := 1.0

var _mundo: Node3D = null
var _luz_chave: DirectionalLight3D = null
var _rim_quente: OmniLight3D = null
var _rim_frio: OmniLight3D = null
var _mat_fundo: StandardMaterial3D = null
var _mat_lona: StandardMaterial3D = null
var _flashes: MultiMeshInstance3D = null
var _flash_fase := PackedFloat32Array()
var _fachos: Array[MeshInstance3D] = []
var _impacto: GPUParticles3D = null
var _poeira: GPUParticles3D = null
var _sombra: MeshInstance3D = null
var _mat_sombra: StandardMaterial3D = null

var _distancia := 0.0
var _altura_da_camera := 0.0
var _altura_da_mira := 0.0

var _relogio := 0.0
var _tremor := 0.0
var _clarao := 0.0
var _empurrao := 0.0
var _publico := 0.0
var _ativa := false
var _magro := false
var _aquecendo := 0


func _ready() -> void:
	own_world_3d = true
	transparent_bg = false
	handle_input_locally = false
	screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	use_taa = false
	positional_shadow_atlas_size = 0
	_aplicar_tamanho()
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	_montar_mundo()


# ----------------------------------------------------------- montagem
func _montar_mundo() -> void:
	_mundo = Node3D.new()
	_mundo.name = "Mundo"
	add_child(_mundo)

	var ambiente := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = COR_FUNDO
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("39456a")
	env.ambient_light_energy = 0.55
	ambiente.environment = env
	_mundo.add_child(ambiente)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 44.0
	camera.near = 0.15
	camera.far = 30.0
	_mundo.add_child(camera)
	_calcular_enquadramento()
	camera.position = Vector3(0.0, _altura_da_camera, _distancia)
	camera.look_at_from_position(camera.position, Vector3(0.0, _altura_da_mira, 0.0), Vector3.UP)

	_luz_chave = DirectionalLight3D.new()
	_luz_chave.light_energy = 1.6
	_luz_chave.light_color = Color("fff1d8")
	_luz_chave.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(28.0), 0.0)
	_mundo.add_child(_luz_chave)
	_rim_quente = _luz_pontual(Color("ff2a48"), Vector3(-2.3, 1.9, -0.6))
	_rim_frio = _luz_pontual(Color("33d6ff"), Vector3(2.3, 1.8, -0.6))

	_montar_fundo()
	_montar_ringue()
	_montar_fachos()
	_montar_flashes()
	_montar_particulas()


func _luz_pontual(cor: Color, onde: Vector3) -> OmniLight3D:
	var luz := OmniLight3D.new()
	luz.light_color = cor
	luz.light_energy = 2.0
	luz.omni_range = 6.0
	luz.position = onde
	_mundo.add_child(luz)
	return luz


static func _material_plano(textura: Texture2D, aditivo := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = textura
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if aditivo:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _material_solido(cor: Color, rugosidade := 0.5, brilho := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = cor
	m.roughness = rugosidade
	m.metallic_specular = 0.6
	if brilho > 0.0:
		m.emission_enabled = true
		m.emission = cor
		m.emission_energy_multiplier = brilho
	return m


func _peca(malha: Mesh, material: Material, onde: Vector3, giro := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = malha
	mi.material_override = material
	mi.position = onde
	mi.rotation = giro
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mundo.add_child(mi)
	return mi


func _montar_fundo() -> void:
	# A plateia pintada: um plano grande bem atrás do ringue.
	_mat_fundo = _material_plano(load(TEX_FUNDO))
	var quadro := QuadMesh.new()
	quadro.size = Vector2(10.4, 7.8)
	_peca(quadro, _mat_fundo, Vector3(0.0, 1.9, -4.8))
	# O chão do ginásio entre o ringue e a plateia: escuro, só para o
	# tablado parecer suspenso.
	var chao := PlaneMesh.new()
	chao.size = Vector2(14.0, 8.0)
	_peca(chao, _material_solido(Color("0b0810"), 0.9), Vector3(0.0, -0.62, -2.6))


func _montar_ringue() -> void:
	var m := MEIO_RINGUE
	_mat_lona = _material_plano(load(TEX_LONA))
	var lona := PlaneMesh.new()
	lona.size = Vector2(m * 2.0, m * 2.0)
	_peca(lona, _mat_lona, Vector3.ZERO)
	# A borda do tablado: faixa escura sob a lona.
	var tablado := BoxMesh.new()
	tablado.size = Vector3(m * 2.0 + 0.12, 0.6, m * 2.0 + 0.12)
	_peca(tablado, _material_solido(Color("120a12"), 0.8), Vector3(0.0, -0.302, 0.0))

	# Postes de trás: vermelho à esquerda, azul à direita, com protetor.
	var poste := CylinderMesh.new()
	poste.top_radius = 0.055
	poste.bottom_radius = 0.055
	poste.height = 1.5
	poste.radial_segments = 16
	var protetor := CylinderMesh.new()
	protetor.top_radius = 0.10
	protetor.bottom_radius = 0.10
	protetor.height = 1.02
	protetor.radial_segments = 20
	var metal := _material_solido(Color("9aa3b5"), 0.28)
	metal.metallic = 0.8
	for lado in [-1.0, 1.0]:
		var cor := Color("d3162f") if lado < 0.0 else Color("1f4fd1")
		_peca(poste, metal, Vector3(lado * m, 0.75, -m))
		_peca(protetor, _material_solido(cor, 0.45, 0.12), Vector3(lado * m, 0.86, -m))

	# Cordas: tubos redondos. Só as de trás e as laterais — nada cruza a
	# frente do lutador.
	var corda := CylinderMesh.new()
	corda.top_radius = 0.024
	corda.bottom_radius = 0.024
	corda.height = m * 2.0
	corda.radial_segments = 12
	corda.rings = 1
	var tintas := [
		_material_solido(Color("e8e9ee"), 0.35, 0.08),
		_material_solido(Color("d8142e"), 0.35, 0.18),
		_material_solido(Color("e8e9ee"), 0.35, 0.08),
	]
	for i in range(ALTURAS_DAS_CORDAS.size()):
		var y: float = ALTURAS_DAS_CORDAS[i]
		_peca(corda, tintas[i], Vector3(0.0, y, -m), Vector3(0.0, 0.0, PI * 0.5))
		for lado in [-1.0, 1.0]:
			_peca(corda, tintas[i], Vector3(lado * m, y, 0.0), Vector3(PI * 0.5, 0.0, 0.0))


func _montar_fachos() -> void:
	# Fachos de refletor varrendo a plateia, aditivos e baratos.
	var textura: Texture2D = load(TEX_FACHO)
	var malha := QuadMesh.new()
	malha.size = Vector2(1.5, 6.0)
	for i in range(3):
		var mat := _material_plano(textura, true)
		mat.albedo_color = [Color("ff4a6a"), Color("fff3dc"), Color("48d6ff")][i]
		var f := _peca(malha, mat, Vector3(-2.4 + 2.4 * float(i), 3.2, -4.3))
		_fachos.append(f)


func _montar_flashes() -> void:
	# Flashes de câmera na plateia: estrela com halo (nunca quadrado).
	var quantos := 16
	var malha := QuadMesh.new()
	malha.size = Vector2(0.42, 0.42)
	var tinta := _material_plano(load(TEX_BRILHO), true)
	tinta.vertex_color_use_as_albedo = true
	tinta.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = malha
	mm.instance_count = quantos
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260923
	_flash_fase.resize(quantos)
	for i in range(quantos):
		var t := Transform3D()
		t.origin = Vector3(rng.randf_range(-3.6, 3.6), rng.randf_range(0.2, 2.6), rng.randf_range(-4.6, -4.3))
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, Color(0, 0, 0, 0))
		_flash_fase[i] = rng.randf() * TAU
	_flashes = MultiMeshInstance3D.new()
	_flashes.multimesh = mm
	_flashes.material_override = tinta
	_flashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mundo.add_child(_flashes)


func _montar_particulas() -> void:
	var brilho := _material_plano(load(TEX_BRILHO), true)
	brilho.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	brilho.vertex_color_use_as_albedo = true
	var estrela := QuadMesh.new()
	estrela.size = Vector2(0.13, 0.13)
	estrela.material = brilho
	var processo := ParticleProcessMaterial.new()
	processo.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	processo.emission_sphere_radius = 0.14
	processo.direction = Vector3(0.0, 0.2, 1.0)
	processo.spread = 80.0
	processo.initial_velocity_min = 2.4
	processo.initial_velocity_max = 6.8
	processo.gravity = Vector3(0.0, -5.5, 0.0)
	processo.damping_min = 1.5
	processo.damping_max = 3.0
	processo.scale_min = 0.35
	processo.scale_max = 1.0
	processo.color = Color("ffe7a8")
	var some := Gradient.new()
	some.set_color(0, Color(1, 1, 1, 1))
	some.set_color(1, Color(1, 0.5, 0.2, 0))
	var rampa := GradientTexture1D.new()
	rampa.gradient = some
	processo.color_ramp = rampa
	_impacto = _particulas("ParticulasImpacto", 96, 0.75, 0.96, processo, estrela, Vector3(0.0, 1.34, 0.36))

	var po := _material_plano(_mancha_redonda(), true)
	po.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	po.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	po.vertex_color_use_as_albedo = true
	var disco := QuadMesh.new()
	disco.size = Vector2(0.34, 0.34)
	disco.material = po
	var po_proc := ParticleProcessMaterial.new()
	po_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	po_proc.emission_box_extents = Vector3(0.7, 0.04, 0.38)
	po_proc.direction = Vector3(0.0, 1.0, 0.0)
	po_proc.spread = 65.0
	po_proc.initial_velocity_min = 0.45
	po_proc.initial_velocity_max = 1.3
	po_proc.gravity = Vector3(0.0, -0.6, 0.0)
	po_proc.scale_min = 0.6
	po_proc.scale_max = 1.6
	po_proc.color = Color(0.62, 0.68, 0.85, 0.30)
	var desvanece := Gradient.new()
	desvanece.set_color(0, Color(1, 1, 1, 1))
	desvanece.set_color(1, Color(1, 1, 1, 0))
	var rampa_po := GradientTexture1D.new()
	rampa_po.gradient = desvanece
	po_proc.color_ramp = rampa_po
	_poeira = _particulas("PoeiraDaLona", 36, 1.35, 0.88, po_proc, disco, Vector3(0.0, 0.08, -0.35))


func _particulas(
	nome: String, quantidade: int, vida: float, explosao: float,
	processo: ParticleProcessMaterial, malha: Mesh, onde: Vector3
) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = nome
	# A quantidade é FIXA. A força do golpe muda `amount_ratio`, que não
	# realoca nada; mudar `amount` refazia os buffers a cada soco.
	p.amount = quantidade
	p.lifetime = vida
	p.one_shot = true
	p.explosiveness = explosao
	p.process_material = processo
	p.draw_pass_1 = malha
	p.position = onde
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 6, 8))
	_mundo.add_child(p)
	return p


## Mancha redonda e macia (branco no centro, transparente na borda),
## feita pela própria GPU: sombra de contato e poeira.
static func _mancha_redonda() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 128
	t.height = 128
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


func instalar() -> bool:
	lutador = Lutador3D.new()
	lutador.name = "Lutador"
	lutador.position.y = PISO_DO_LUTADOR
	_mundo.add_child(lutador)
	lutador.montar()
	_montar_sombra()
	return lutador.completo()


func _montar_sombra() -> void:
	var malha := PlaneMesh.new()
	malha.size = Vector2(1.0, 0.52)
	_mat_sombra = StandardMaterial3D.new()
	_mat_sombra.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_sombra.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_sombra.albedo_texture = _mancha_redonda()
	_mat_sombra.albedo_color = Color(0.0, 0.0, 0.02, 0.9)
	_mat_sombra.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_sombra = _peca(malha, _mat_sombra, Vector3(0.0, 0.002, 0.0))


# -------------------------------------------------------- tamanho/MSAA
func _fator_da_tela() -> float:
	# Pixels reais por pixel lógico: 1 numa saída 1080p, 2 numa 4K.
	var raiz := get_tree().root if is_inside_tree() else null
	if raiz == null or raiz.content_scale_size.x <= 0:
		return 1.0
	var real := Vector2(raiz.size)
	var logico := Vector2(raiz.content_scale_size)
	return clampf(minf(real.x / logico.x, real.y / logico.y), 1.0, FATOR_MAXIMO)


func _aplicar_tamanho() -> void:
	var fator := _fator_da_tela() * (FATOR_MAGRO if _magro else 1.0)
	var novo := Vector2i((TELA_LOGICA * fator).round())
	if size != novo:
		size = novo
	msaa_3d = Viewport.MSAA_2X if _magro else Viewport.MSAA_4X


func _ajustar_tamanho() -> void:
	var magro := _magro
	if not _magro and qualidade < DESCE_PARA_MAGRO:
		magro = true
	elif _magro and qualidade >= SOBE_PARA_CHEIO:
		magro = false
	if magro != _magro:
		_magro = magro
		_aplicar_tamanho()


# ---------------------------------------------------------- interface
func modelo_avancado() -> bool:
	return lutador != null and lutador.completo()


func ligar(ativa: bool) -> void:
	if _ativa == ativa:
		return
	_ativa = ativa
	if ativa:
		_aplicar_tamanho()
	elif _aquecendo <= 0:
		render_target_update_mode = SubViewport.UPDATE_DISABLED


func ativa() -> bool:
	return _ativa


## PRÉ-AQUECIMENTO. Renderiza a arena fora da tela por alguns quadros
## com todas as poses e as partículas no ar: shaders compilam e texturas
## sobem para a GPU no arranque, e não no primeiro soco da noite.
func aquecer(quadros := 24) -> void:
	_aquecendo = quadros
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _impacto != null:
		_impacto.restart()
	if _poeira != null:
		_poeira.restart()


func golpe(forca: float, derruba := false, pontos := -1) -> Dictionary:
	_tremor = clampf(0.35 + forca, 0.0, 1.35)
	_clarao = clampf(0.4 + forca * 0.6, 0.0, 1.0)
	_empurrao = forca
	_publico = maxf(_publico, clampf(0.08 + forca * (1.15 if derruba else 0.85), 0.0, 1.0))
	var economia := 1.0 if qualidade >= 0.55 else 0.55
	if _impacto != null:
		_impacto.amount_ratio = clampf(lerpf(0.22, 1.0, forca) * economia, 0.05, 1.0)
		_impacto.restart()
	if derruba and _poeira != null:
		_poeira.amount_ratio = economia
		_poeira.restart()
	if lutador == null:
		return {"nocaute": false, "dano": 0.0, "reacao": "", "desdenhou": false}
	var resposta := lutador.bater(forca, derruba, pontos)
	if bool(resposta.get("desdenhou", false)):
		_publico = maxf(_publico, 0.66)
		_clarao = maxf(_clarao, 0.28)
	return resposta


func preparar() -> void:
	if lutador != null:
		lutador.preparar()
	_tremor = 0.0
	_clarao = 0.0
	_publico = 0.0


func guardar(ativo: bool) -> void:
	if lutador != null:
		lutador.guardar(ativo)


func dano() -> float:
	return lutador.dano if lutador != null else 0.0


func na_lona() -> bool:
	return lutador != null and lutador.queda > 0.35


func avancar(delta: float) -> void:
	if _aquecendo > 0:
		_passo_do_aquecimento()
		if not _ativa:
			return
	if not _ativa:
		return
	_relogio += delta
	_tremor = maxf(0.0, _tremor - delta * 2.2)
	_clarao = maxf(0.0, _clarao - delta * 2.4)
	_empurrao = maxf(0.0, _empurrao - delta * 1.6)
	_publico = maxf(0.0, _publico - delta * 0.72)
	if lutador != null:
		lutador.atualizar(delta)
	_sombra_de_contato()
	_camera()
	_luzes()
	_piscar()
	render_target_update_mode = SubViewport.UPDATE_ONCE
	_ajustar_tamanho()


func _passo_do_aquecimento() -> void:
	_aquecendo -= 1
	if lutador != null:
		var poses := lutador.poses()
		if not poses.is_empty():
			lutador.mostrar_pose(StringName(poses[_aquecendo % poses.size()]))
	if _aquecendo <= 0:
		if lutador != null:
			lutador.preparar()
		render_target_update_mode = SubViewport.UPDATE_ONCE if _ativa else SubViewport.UPDATE_DISABLED


# ------------------------------------------------------------ a cena
func _calcular_enquadramento() -> void:
	var figura := Lutador3D.ALTURA_DA_FIGURA
	var janela := figura / OCUPACAO_DO_LUTADOR
	var meia := deg_to_rad(camera.fov) * 0.5
	_distancia = janela / (2.0 * tan(meia))
	var base := PISO_DO_LUTADOR - (janela - figura) * 0.5
	var inclinacao := atan(CAMERA_ACIMA_DA_MIRA / _distancia)
	_altura_da_camera = base + _distancia * tan(inclinacao + meia)
	_altura_da_mira = _altura_da_camera - CAMERA_ACIMA_DA_MIRA


func _camera() -> void:
	var passeio := sin(_relogio * 0.33) * 0.16
	var sacode := Vector3.ZERO
	if _tremor > 0.02:
		sacode = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-0.4, 0.4)) * _tremor * 0.05
	var pos := Vector3(passeio, _altura_da_camera + sin(_relogio * 0.21) * 0.05, _distancia - _empurrao * 0.30)
	var mira := Vector3(0.0, _altura_da_mira + _empurrao * 0.06, 0.0)
	var caido := lutador.queda if lutador != null else 0.0
	if caido > 0.001:
		# No nocaute a câmera afasta e desce: um corpo caído é largo.
		var t := ease(caido, 0.5)
		pos = pos.lerp(Vector3(0.0, _altura_da_camera * 0.54, _distancia * 1.07), t)
		mira = mira.lerp(Vector3(0.0, _altura_da_mira * 0.58, 0.0), t)
	camera.position = pos + sacode
	camera.look_at(mira, Vector3.UP)


func _luzes() -> void:
	if lutador != null:
		lutador.clarao(_clarao)
	var extra := _clarao * 5.0
	_rim_quente.light_energy = 2.0 + extra
	_rim_frio.light_energy = 2.0 + extra
	_luz_chave.light_energy = 1.6 + _clarao * 1.0
	# Materiais sem luz acendem pelo albedo: o salão inteiro pisca junto.
	var acende := 1.0 + _clarao * 0.55
	_mat_fundo.albedo_color = Color(acende, acende, acende)
	_mat_lona.albedo_color = Color(acende, acende, acende)
	for i in range(_fachos.size()):
		var f := _fachos[i]
		f.rotation.z = sin(_relogio * (0.35 + 0.1 * float(i)) + float(i) * 2.1) * 0.35
		var mat := f.material_override as StandardMaterial3D
		mat.albedo_color.a = 0.20 + _publico * 0.35 + _clarao * 0.25


func _piscar() -> void:
	var mm := _flashes.multimesh
	for i in range(mm.instance_count):
		var fase: float = _flash_fase[i]
		var base := maxf(0.0, sin(_relogio * 1.7 + fase) - 0.93) * 12.0
		var festa := (_clarao + _publico * 0.6) * maxf(0.0, sin(fase * 3.1 + _relogio * 22.0))
		var a := clampf(base + festa, 0.0, 1.0)
		mm.set_instance_color(i, Color(a, a * 0.97, a * 0.92, a))


func _sombra_de_contato() -> void:
	if _sombra == null or lutador == null:
		return
	var desloc := lutador.deslocamento()
	var caido := clampf(lutador.queda, 0.0, 1.0)
	_sombra.position = Vector3(desloc.x, 0.002, desloc.z * 0.6)
	_sombra.scale = Vector3(lerpf(1.0, 1.5, caido), 1.0, lerpf(1.0, 1.3, caido))
	_mat_sombra.albedo_color.a = lerpf(0.9, 0.6, caido)
