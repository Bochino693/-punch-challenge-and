class_name Arena3D
extends SubViewport

## A ARENA: UM MUNDO 3D DE VERDADE, DENTRO DE UMA JANELA DA TELA 2D.
##
## O jogo inteiro é desenhado à mão, em 2D, por `main.gd`. A arena não:
## ela é uma cena 3D com câmera, luz e perspectiva, renderizada num
## `SubViewport` e depois COLADA na tela como se fosse um quadro pendurado
## na parede do salão. É daí que vem a impressão de profundidade que um
## desenho 2D não dá por mais sombra que leve — a perspectiva é real, o
## lutador realmente recua para o fundo quando apanha.
##
## POR QUE UM SUBVIEWPORT E NÃO 3D NA CENA PRINCIPAL. Misturar um mundo
## 3D com a tela 2D existente exigiria reorganizar todas as camadas de
## desenho do jogo — e a moldura de LED, o placar e os efeitos passariam
## a disputar ordem com a câmera 3D. Numa janela separada, a arena é só
## mais uma TEXTURA que o `_draw` desenha onde quiser, na ordem que
## quiser. O resto do jogo continua exatamente como era.
##
## O PREÇO ESTÁ CONTROLADO, porque isto vai para uma TV Box:
##
##   • a janela é pequena (a textura é ampliada na hora de desenhar; num
##     quadro com moldura ninguém conta pixel);
##   • sem antisserrilhado, sem sombra, sem brilho — três luzes e pronto;
##   • toda a arena (lona, postes, cordas, fundo) é UMA malha só, com
##     cor por vértice: um desenho, e não trinta;
##   • quando o vigia de desempenho aperta, a janela encolhe, mas continua
##     acompanhando cada quadro do jogo — movimento não vira apresentação
##     de slides para economizar pixels;
##   • ela só liga nas telas em que aparece. Fica viva do 3–2–1 ao
##     resultado e desliga na abertura e na tabela de recordes.

## A JANELA TEM O TAMANHO EXATO DO BURACO DA MOLDURA — e isso é novo.
##
## Ela era 640 × 717 e era desenhada num buraco de 688 × 770
## (`ArenaQuadro.TELA`). A proporção batia, então nada parecia errado;
## o que havia era um ESTICÃO de 1,075× em cima da arena inteira, toda
## vez, antes de ela chegar à tela. Um esticão fracionário não realinha
## pixel com pixel: cada um vira mistura de dois, e o que some nessa
## mistura são justamente os detalhes de um ou dois pixels — a ponta da
## bota, o fio de luz na luva, o contorno ciano.
##
## Em 688 × 770 o desenho da arena cai no buraco um para um e o esticão
## deixa de existir. Custa 15% mais pixels; o vigia de desempenho
## continua tendo a janela magra para quando a máquina apertar.
const TAMANHO_CHEIO := Vector2i(688, 770)
const TAMANHO_MAGRO := Vector2i(482, 539)

## A JANELA NÍTIDA: O DOBRO, REDUZIDO NA HORA DE DESENHAR.
##
## Por que isto melhora a definição de TUDO, e não só de um detalhe.
## A arena não tem antisserrilhado nenhum (`msaa_3d` desligado, e o
## recorte do lutador é por limiar de alfa, que é decisão de tudo-ou-
## nada: a silhueta sai em degraus de um bit). Num quadro de 688 × 770
## esses degraus têm o tamanho de um pixel e se veem — é a "resolução
## fraca": não é falta de pixels na tela, é falta de amostras por pixel.
##
## Desenhar a 1376 × 1540 e reduzir para o buraco de 688 × 770 é uma
## redução de exatamente 2:1, então cada pixel final é a MÉDIA DE
## QUATRO amostras. Isso antisserrilha o ringue, as cordas, as faíscas
## e — o que mais importa aqui — o contorno do lutador, sem precisar de
## MSAA nem de recurso que a TV Box possa não ter.
##
## Custa quatro vezes mais pixels. A cena é barata (uma malha, três
## luzes sem sombra, um sprite), mas isto não é promessa: é por isso
## que existe a escada em `_ajustar_tamanho`, e é o vigia de desempenho
## quem decide em qual degrau a máquina fica.
const TAMANHO_NITIDO := Vector2i(1376, 1540)

## A ESCADA, COM HISTERESE. Subir e descer no mesmo número faria a
## janela piscar entre dois tamanhos toda vez que a qualidade
## encostasse no limiar — e trocar o tamanho de um `SubViewport`
## realoca a textura, que é justamente o que não pode acontecer a cada
## quadro.
const SOBE_PARA_NITIDO := 0.95
const DESCE_DO_NITIDO := 0.85
const SOBE_PARA_CHEIO := 0.60
const DESCE_DO_CHEIO := 0.50

## O ENQUADRAMENTO DA CÂMERA, EM DUAS CONSTANTES (ver `_calcular_enquadramento`).
##
## Quanto da altura da janela o lutador EM PÉ ocupa. Em 0,79 sobram uns
## 24 cm de tapete embaixo e 26 cm de ar em cima: o bastante para a lona
## aparecer sob os pés e a corda de cima cruzar o quadro — que é o que
## faz a imagem ler como ringue e não como recorte —, sem devolver o
## rosto ao tamanho de moeda que a versão afastada tinha.
const OCUPACAO_DO_LUTADOR := 0.79
## Quanto a câmera fica ACIMA da mira, em metros. É o que dá a leve
## inclinação de transmissão; zero deixaria a imagem chapada de frente.
const CAMERA_ACIMA_DA_MIRA := 0.21

## ------------------------------------------------------ o chão do ringue
##
## ONDE O LUTADOR PISA, EM METROS — e por que isto precisou virar uma
## constante com nome.
##
## A lona grande (4,6 × 4,6) tem o topo em y = 0, e foi nesse zero que o
## lutador foi posto a pisar. Só que EM CIMA dela há um miolo mais claro
## de 3 × 3 que sobe até **y = 0,015** — um centímetro e meio —, e é ele
## que está debaixo do lutador. Ou seja: o chão de verdade nunca esteve
## em zero, e a bota ficava um centímetro e meio DENTRO do miolo.
##
## E isso não se vê como pé enterrado: o miolo é desenhado na frente do
## plano do desenho, então o que se vê é a BOTA CORTADA, comida pelo
## tapete.
##
## Agora o miolo é construído a partir desta constante e o lutador é
## pousado nela, então os dois não têm como divergir de novo. E, com a
## linha do chão do desenho corrigida (ver `Lutador3D.SOLA_DO_PE_PX`),
## o desenho INTEIRO fica acima deste plano: não há mais nada que o
## tapete possa cortar.
const ALTURA_DA_LONA := 0.015
## A FOLGA ENTRE A SOLA E O TAPETE, EM PIXELS DA FOLHA.
##
## Em pixels, e não em metros, porque é em pixel que o problema se
## manifesta: coplanares — ou a menos de um pixel — a borda de baixo da
## bota e o topo do tapete caem na MESMA linha de pixel da tela, e qual
## das duas ganha vira sorteio do teste de profundidade. O resultado é
## um corte reto atravessando a bota, que não some e não se explica: a
## "linha invisível".
##
## AGORA ELA É SÓ ESTÉTICA, e por isso encolheu de dois pixels para um.
## Quem impede o corte passou a ser `no_depth_test` no desenho do
## lutador (ver `Lutador3D.montar`): nenhum plano tem mais poder de
## cortá-lo, então a folga não precisa mais ser uma margem de
## segurança. Um pixel basta para a sombra de contato caber embaixo da
## sola, e um pixel não se vê.
const FOLGA_DA_SOLA_PX := 1.0

## A MANCHA DE CONTATO FICA ABAIXO DA SOLA, E ISSO É UMA CORREÇÃO.
##
## Ela estava em y = 0,022, ou seja, ACIMA da bota. Uma mancha é um
## plano horizontal; posta acima da sola, ela ATRAVESSA o desenho e
## escurece tudo o que fica abaixo da altura dela. Era um segundo corte
## na bota, do mesmo tipo do primeiro e pela mesma razão — só que este
## tinha sido posto aqui por mim, para esconder o primeiro.
##
## Logo acima do tapete e logo ABAIXO da sola, ela não cruza desenho
## nenhum: aparece só no tapete, em volta e à frente dos pés, que é onde
## uma sombra de contato mora.
const ALTURA_DA_SOMBRA := ALTURA_DA_LONA + 0.001

## A altura, no mundo, em que a BORDA DE BAIXO da bota encosta.
##
## Não é constante porque depende do tamanho do pixel da folha, que sai
## da arte medida (`Lutador3D.PIXEL_NO_MUNDO`). Trocar a arte por outra
## de resolução diferente reajusta a folga sozinho.
static func piso_do_lutador() -> float:
	return ALTURA_DA_LONA + Lutador3D.PIXEL_NO_MUNDO * FOLGA_DA_SOLA_PX

## Cores da arena. O salão é claro no 2D; aqui dentro é escuro de
## propósito — o quadro tem de ler como uma JANELA para outro lugar, e
## não como um pedaço da mesma parede.
const COR_LONA := Color("1b2436")
const COR_LONA_CENTRO := Color("232e45")
const COR_BORDA := Color("0e1520")
const COR_POSTE := Color("d81226")
const COR_CORDA := Color("f2f2f0")
const COR_FUNDO := Color("0a0d15")

var lutador: Lutador3D = null
var camera: Camera3D = null
var _mundo: Node3D = null
var _luz_chave: DirectionalLight3D = null
var _rim_quente: OmniLight3D = null
var _rim_frio: OmniLight3D = null
var _flashes: MultiMeshInstance3D = null
var _flash_fase: PackedFloat32Array = PackedFloat32Array()
var _torcida: MultiMeshInstance3D = null
var _torcida_base: Array[Vector3] = []
var _impacto_particulas: GPUParticles3D = null
var _poeira_particulas: GPUParticles3D = null
var _sombra: MeshInstance3D = null

## O ENQUADRAMENTO CALCULADO NO ARRANQUE. Distância, altura da câmera e
## altura da mira saem da figura medida (ver `_calcular_enquadramento`), e não de
## três números escritos à mão que precisavam ser reajustados toda vez
## que a arte mudava de tamanho.
var _distancia := 0.0
var _altura_da_camera := 0.0
var _altura_da_mira := 0.0

var _relogio := 0.0
var _tremor := 0.0
var _clarao := 0.0
var _empurrao := 0.0
var _publico := 0.0
var _ativa := false

## 1.0 = tudo; abaixo de 0,55 a janela encolhe, preservando a taxa de quadros.
var qualidade := 1.0

func _ready() -> void:
	own_world_3d = true
	transparent_bg = false
	handle_input_locally = false
	msaa_3d = Viewport.MSAA_DISABLED
	screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	use_taa = false
	positional_shadow_atlas_size = 0
	size = TAMANHO_CHEIO
	_degrau = 1
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	_montar_mundo()

# ----------------------------------------------------------------- mundo
func _montar_mundo() -> void:
	_mundo = Node3D.new()
	_mundo.name = "Mundo"
	add_child(_mundo)

	var ambiente := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = COR_FUNDO
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("3a4a6b")
	env.ambient_light_energy = 0.42
	ambiente.environment = env
	_mundo.add_child(ambiente)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 44.0
	camera.near = 0.15
	camera.far = 24.0
	_mundo.add_child(camera)
	_calcular_enquadramento()
	camera.position = Vector3(0.0, _altura_da_camera, _distancia)
	camera.look_at_from_position(
		camera.position, Vector3(0.0, _altura_da_mira, 0.0), Vector3.UP
	)

	# A LUZ PRINCIPAL vem de cima e da frente: é o refletor do ginásio, o
	# mesmo que o fundo 2D já desenha caindo sobre o saco.
	_luz_chave = DirectionalLight3D.new()
	_luz_chave.name = "Refletor"
	_luz_chave.light_energy = 2.10
	_luz_chave.light_color = Color("fff1d8")
	_luz_chave.shadow_enabled = false
	_luz_chave.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(28.0), 0.0)
	_mundo.add_child(_luz_chave)

	# AS DUAS LUZES DE CONTORNO SÃO A REFERÊNCIA QUE O OPERADOR MANDOU:
	# magenta de um lado, ciano do outro, recortando a silhueta contra o
	# fundo escuro. Não é enfeite — é o que impede o lutador preto e
	# vermelho de sumir dentro de um fundo preto e azul, e é o que dá ao
	# quadro o ar de pôster de jogo de luta em vez de maquete.
	_rim_quente = OmniLight3D.new()
	_rim_quente.name = "ContornoVermelho"
	_rim_quente.light_color = Color("ff1835")
	_rim_quente.light_energy = 2.15
	_rim_quente.omni_range = 7.5
	_rim_quente.shadow_enabled = false
	_rim_quente.position = Vector3(-2.1, 1.9, -1.5)
	_mundo.add_child(_rim_quente)

	_rim_frio = OmniLight3D.new()
	_rim_frio.name = "ContornoCiano"
	_rim_frio.light_color = Color("2fd8ff")
	_rim_frio.light_energy = 2.00
	_rim_frio.omni_range = 7.5
	_rim_frio.shadow_enabled = false
	_rim_frio.position = Vector3(2.2, 1.8, -1.4)
	_mundo.add_child(_rim_frio)

	var ringue := MeshInstance3D.new()
	ringue.name = "Ringue"
	ringue.mesh = _malha_do_ringue()
	var tinta := StandardMaterial3D.new()
	tinta.vertex_color_use_as_albedo = true
	tinta.roughness = 0.85
	tinta.metallic = 0.0
	ringue.material_override = tinta
	ringue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mundo.add_child(ringue)

	_montar_flashes()
	_montar_torcida()
	_montar_particulas_de_impacto()

## TODA A ARENA NUMA MALHA SÓ.
##
## Lona, borda, quatro postes, nove cordas e o painel do fundo são
## trinta e poucas caixas. Trinta `MeshInstance3D` seriam trinta
## chamadas de desenho por quadro, e chamada de desenho é justamente o
## que uma TV Box tem pouco. Costuradas numa malha com cor por vértice,
## viram UMA.
func _malha_do_ringue() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# fundo do ginásio: um painel escuro e um chão abaixo da lona
	_caixa(st, Vector3(0.0, 2.2, -4.2), Vector3(14.0, 7.0, 0.3), COR_FUNDO)
	# Três degraus luminosos separam arquibancada, parede e teto. Além de
	# dar profundidade ao fundo, fornecem linhas de perspectiva estáveis
	# para o personagem não parecer flutuar num painel plano.
	_caixa(st, Vector3(0.0, 0.48, -3.92), Vector3(9.4, 0.18, 0.42), Color("18243b"))
	_caixa(st, Vector3(0.0, 1.05, -4.02), Vector3(10.4, 0.16, 0.38), Color("361426"))
	_caixa(st, Vector3(0.0, 1.62, -4.10), Vector3(11.4, 0.14, 0.32), Color("153246"))
	_caixa(st, Vector3(0.0, 2.65, -4.00), Vector3(5.8, 0.07, 0.18), Color("e43845"))
	_caixa(st, Vector3(0.0, 2.82, -4.00), Vector3(3.7, 0.05, 0.17), Color("35ccec"))
	_caixa(st, Vector3(0.0, -0.9, -0.4), Vector3(14.0, 0.3, 9.0), Color("060810"))
	# a lona e a saia do ringue
	_caixa(st, Vector3(0.0, -0.06, 0.0), Vector3(4.6, 0.12, 4.6), COR_LONA)
	# O MIOLO CLARO, e a altura dele agora É `ALTURA_DA_LONA`. Os números
	# soltos que estavam aqui (centro 0,005 e espessura 0,02, ou seja topo
	# em 0,015) eram o chão real do ringue sem que nada no código dissesse
	# isso — e era contra esse chão que a bota do lutador batia.
	_caixa(
		st, Vector3(0.0, ALTURA_DA_LONA - 0.01, 0.0),
		Vector3(3.0, 0.02, 3.0), COR_LONA_CENTRO
	)
	_caixa(st, Vector3(0.0, -0.36, 0.0), Vector3(4.9, 0.50, 4.9), COR_BORDA)
	# quatro postes; os da frente ficam fora do enquadramento de propósito
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_caixa(st, Vector3(sx * 2.15, 0.78, sz * 2.15), Vector3(0.16, 1.72, 0.16), COR_POSTE)
			_caixa(st, Vector3(sx * 2.15, 1.68, sz * 2.15), Vector3(0.22, 0.10, 0.22), Color("f5c542"))
	# as cordas: só as do fundo e as laterais. As da frente cruzariam o
	# lutador na altura do peito e esconderiam justamente o que se quer
	# ver — num ringue de verdade a câmera também escolhe um lado.
	for i in range(3):
		var y := 0.42 + float(i) * 0.42
		_caixa(st, Vector3(0.0, y, -2.15), Vector3(4.34, 0.055, 0.055), COR_CORDA)
		_caixa(st, Vector3(-2.15, y, 0.0), Vector3(0.055, 0.055, 4.34), COR_CORDA)
		_caixa(st, Vector3(2.15, y, 0.0), Vector3(0.055, 0.055, 4.34), COR_CORDA)
	st.generate_normals()
	return st.commit()

func _caixa(st: SurfaceTool, centro: Vector3, tamanho: Vector3, cor: Color) -> void:
	var h := tamanho * 0.5
	var c := [
		centro + Vector3(-h.x, -h.y, h.z), centro + Vector3(h.x, -h.y, h.z),
		centro + Vector3(h.x, -h.y, -h.z), centro + Vector3(-h.x, -h.y, -h.z),
		centro + Vector3(-h.x, h.y, h.z), centro + Vector3(h.x, h.y, h.z),
		centro + Vector3(h.x, h.y, -h.z), centro + Vector3(-h.x, h.y, -h.z),
	]
	var faces := [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7], [3, 2, 1, 0]]
	for face in faces:
		# O topo recebe um fio de luz a mais: sem isso a caixa vista de
		# cima some no fundo escuro e o ringue vira uma mancha.
		var tom := cor.lightened(0.16) if face[0] == 4 else cor
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri:
				st.set_color(tom)
				st.add_vertex(c[face[k]])

## OS FLASHES DA PLATEIA. Dezoito pontinhos brancos piscando no escuro,
## atrás das cordas — é o clichê que diz "há gente ali fora" sem desenhar
## uma única pessoa. Num `MultiMesh` eles custam um desenho só, e é o que
## permite haver dezoito em vez de três.
func _montar_flashes() -> void:
	var quantos := 18
	var malha := QuadMesh.new()
	malha.size = Vector2(0.11, 0.11)
	var tinta := StandardMaterial3D.new()
	tinta.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tinta.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tinta.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tinta.vertex_color_use_as_albedo = true
	tinta.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	tinta.albedo_color = Color.WHITE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = malha
	mm.instance_count = quantos
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260915
	_flash_fase.resize(quantos)
	for i in range(quantos):
		var t := Transform3D()
		t.origin = Vector3(
			rng.randf_range(-3.4, 3.4), rng.randf_range(0.9, 2.9), rng.randf_range(-3.9, -2.6)
		)
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, Color(0, 0, 0, 1))
		_flash_fase[i] = rng.randf() * TAU
	_flashes = MultiMeshInstance3D.new()
	_flashes.name = "Flashes"
	_flashes.multimesh = mm
	_flashes.material_override = tinta
	_flashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mundo.add_child(_flashes)

## Silhuetas baratas dão corpo à arquibancada. Todas compartilham a mesma
## malha e reagem ao impacto sem criar dezenas de nós ou chamadas de desenho.
func _montar_torcida() -> void:
	var quantos := 30
	var malha := _malha_silhueta_torcida()
	var tinta := StandardMaterial3D.new()
	tinta.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tinta.vertex_color_use_as_albedo = true
	tinta.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = malha
	mm.instance_count = quantos
	var rng := RandomNumberGenerator.new()
	rng.seed = 6932026
	for i in range(quantos):
		var fila := i % 3
		var base := Vector3(
			rng.randf_range(-3.6, 3.6),
			0.72 + float(fila) * 0.42 + rng.randf_range(-0.06, 0.06),
			-3.82 + float(fila) * 0.28
		)
		_torcida_base.append(base)
		var t := Transform3D()
		t.origin = base
		mm.set_instance_transform(i, t)
		var paleta := [Color("28324b"), Color("591f32"), Color("1d4650"), Color("59421f")]
		mm.set_instance_color(i, paleta[i % paleta.size()])
	_torcida = MultiMeshInstance3D.new()
	_torcida.name = "Torcida"
	_torcida.multimesh = mm
	_torcida.material_override = tinta
	_torcida.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mundo.add_child(_torcida)

## Cabeça + ombros em uma única malha plana. O retângulo antigo fazia a
## arquibancada parecer uma grade; esta forma continua custando um único
## MultiMesh e é reconhecida como pessoa até na resolução reduzida.
func _malha_silhueta_torcida() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pontos := [
		Vector3(-0.16, -0.27, 0.0), Vector3(0.16, -0.27, 0.0),
		Vector3(0.13, 0.04, 0.0), Vector3(0.075, 0.12, 0.0),
		Vector3(0.07, 0.24, 0.0), Vector3(0.0, 0.30, 0.0),
		Vector3(-0.07, 0.24, 0.0), Vector3(-0.075, 0.12, 0.0),
		Vector3(-0.13, 0.04, 0.0),
	]
	for tri in [[0, 1, 2], [0, 2, 8], [8, 2, 3], [8, 3, 7], [7, 3, 4], [7, 4, 6], [6, 4, 5]]:
		for indice in tri:
			st.set_color(Color.WHITE)
			st.add_vertex(pontos[indice])
	return st.commit()

## Partículas 3D ficam dentro do quadro da arena e usam poucos emissores.
## A resolução visual vem do material aditivo e da variação de escala, não de
## centenas de nós. Em qualidade baixa a quantidade cai automaticamente.
## UMA FAÍSCA SUAVE, DESENHADA NA HORA.
##
## As partículas eram QUADS SEM TEXTURA: um retângulo de cor chapada com
## quatro quinas vivas. Enquanto a câmera estava a 2,7 m e cada faísca
## tinha oito pixels, ninguém via; com o enquadramento mais perto que a
## ilustração pediu, elas apareceram como tijolos amarelos flutuando na
## frente do lutador.
##
## Uma textura com queda suave nas bordas resolve, e ela não precisa vir
## de arquivo nenhum: são 32 × 64 pixels calculados no arranque, uma vez.
## O perfil é uma elipse com o brilho caindo ao quadrado do centro para
## fora — que é o desenho de uma faísca vista de longe.
static func _textura_de_faisca(largura: int, altura: int, dureza: float) -> ImageTexture:
	var img := Image.create_empty(largura, altura, false, Image.FORMAT_RGBA8)
	for y in range(altura):
		for x in range(largura):
			var dx := (float(x) + 0.5) / float(largura) * 2.0 - 1.0
			var dy := (float(y) + 0.5) / float(altura) * 2.0 - 1.0
			var d := sqrt(dx * dx + dy * dy)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), dureza)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

func _montar_particulas_de_impacto() -> void:
	var brilho := StandardMaterial3D.new()
	brilho.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	brilho.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	brilho.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	brilho.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	brilho.albedo_color = Color("ffdc8a")
	brilho.albedo_texture = _textura_de_faisca(24, 64, 1.7)
	var estrela := QuadMesh.new()
	estrela.size = Vector2(0.055, 0.16)
	estrela.material = brilho
	var processo := ParticleProcessMaterial.new()
	processo.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	processo.emission_sphere_radius = 0.16
	processo.direction = Vector3(0.0, 0.15, 1.0)
	processo.spread = 78.0
	processo.initial_velocity_min = 2.8
	processo.initial_velocity_max = 7.2
	processo.gravity = Vector3(0.0, -5.5, 0.0)
	processo.scale_min = 0.40
	processo.scale_max = 1.05
	processo.color = Color("fff0bd")
	_impacto_particulas = GPUParticles3D.new()
	_impacto_particulas.name = "ParticulasImpacto"
	_impacto_particulas.amount = 72
	_impacto_particulas.lifetime = 0.72
	_impacto_particulas.one_shot = true
	_impacto_particulas.explosiveness = 0.96
	_impacto_particulas.process_material = processo
	_impacto_particulas.draw_pass_1 = estrela
	_impacto_particulas.position = Vector3(0.0, 1.34, 0.36)
	_impacto_particulas.emitting = false
	_mundo.add_child(_impacto_particulas)

	var po_mat := StandardMaterial3D.new()
	po_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	po_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	po_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	po_mat.albedo_color = Color(0.45, 0.52, 0.68, 0.32)
	# A poeira da lona leva a mesma textura da faísca, mais macia: sem
	# ela, uma nuvem de pó era um punhado de retângulos escuros.
	po_mat.albedo_texture = _textura_de_faisca(48, 32, 2.6)
	var disco := QuadMesh.new()
	disco.size = Vector2(0.30, 0.17)
	disco.material = po_mat
	var po_processo := ParticleProcessMaterial.new()
	po_processo.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	po_processo.emission_box_extents = Vector3(0.70, 0.04, 0.38)
	po_processo.direction = Vector3(0.0, 1.0, 0.0)
	po_processo.spread = 65.0
	po_processo.initial_velocity_min = 0.45
	po_processo.initial_velocity_max = 1.35
	po_processo.gravity = Vector3(0.0, -0.7, 0.0)
	po_processo.scale_min = 0.55
	po_processo.scale_max = 1.65
	_poeira_particulas = GPUParticles3D.new()
	_poeira_particulas.name = "PoeiraDaLona"
	_poeira_particulas.amount = 34
	_poeira_particulas.lifetime = 1.35
	_poeira_particulas.one_shot = true
	_poeira_particulas.explosiveness = 0.88
	_poeira_particulas.process_material = po_processo
	_poeira_particulas.draw_pass_1 = disco
	_poeira_particulas.position = Vector3(0.0, 0.08, -0.35)
	_poeira_particulas.emitting = false
	_mundo.add_child(_poeira_particulas)

# ------------------------------------------------------------- o lutador
## PÕE O LUTADOR NA LONA.
##
## Antes isto recebia um `PackedScene` vindo de `lutador.glb`, que por sua
## vez era gerado por um script em Python. Três coisas melhoraram ao
## mesmo tempo quando o corpo virou código (ver `LutadorNativo`): sumiu a
## dependência de Python, sumiu a chance de a máquina chegar ao salão sem
## o modelo dentro, e sumiu o ciclo de ajuste que passava pelo Blender.
##
## Não há mais o caso "o arquivo não estava lá": o lutador existe sempre
## que o jogo existe.
func instalar() -> bool:
	lutador = Lutador3D.new()
	lutador.name = "Lutador"
	# QUEM SABE ONDE FICA O CHÃO É A ARENA, NÃO O LUTADOR.
	#
	# `Lutador3D` põe o ponto mais baixo do desenho no y = 0 DELE e não
	# tem como saber que o ringue tem um miolo levantado. Erguer o nó
	# inteiro até `piso_do_lutador()` é o que faz o desenho pousar EM
	# CIMA do tapete em vez de ser atravessado por ele.
	lutador.position.y = piso_do_lutador()
	_mundo.add_child(lutador)
	lutador.montar()
	_montar_sombra_de_contato()
	return true

## A SOMBRA DE CONTATO: a mancha escura onde o pé encontra a lona.
##
## POR QUE ELA PRECISA EXISTIR. O lutador é um DESENHO PLANO em pé num
## mundo 3D, e um plano não projeta sombra nenhuma (as luzes da arena
## têm sombra desligada, e teriam de ficar assim: sombra de verdade num
## cartaz sai como um risco). Sem nada embaixo, a figura não POUSA no
## tapete — ela fica encostada nele, e o olho lê isso como recorte
## colado mesmo sem saber dizer por quê. É o mesmo motivo pelo qual todo
## jogo que põe sprite em cena 3D desenha uma mancha embaixo.
##
## E ELA FECHA O VÃO DA FOLGA. Entre a sola e o tapete há dois pixels
## de propósito (ver `FOLGA_DA_SOLA_PX`): sem eles as duas superfícies
## caem na mesma linha de pixel da tela e o tapete corta a bota. Dois
## pixels de vão, porém, também se veem — e é a mancha, logo embaixo,
## que os fecha.
func _montar_sombra_de_contato() -> void:
	var malha := PlaneMesh.new()
	malha.size = Vector2(0.94, 0.50)
	var tinta := StandardMaterial3D.new()
	tinta.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tinta.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tinta.cull_mode = BaseMaterial3D.CULL_DISABLED
	# A mesma textura de queda suave das faíscas, com o brilho virando
	# opacidade: no meio ela é opaca, na borda some. Um retângulo de cor
	# chapada aqui seria um tapete dentro do tapete.
	tinta.albedo_texture = _textura_de_faisca(64, 40, 1.9)
	tinta.albedo_color = Color(0.02, 0.03, 0.06, 0.62)
	_sombra = MeshInstance3D.new()
	_sombra.name = "SombraDeContato"
	_sombra.mesh = malha
	_sombra.material_override = tinta
	_sombra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Entre o tapete e a sola. Ver `ALTURA_DA_SOMBRA`: acima da sola ela
	# atravessava o desenho e virava mais um corte na bota.
	_sombra.position = Vector3(0.0, ALTURA_DA_SOMBRA, 0.0)
	_mundo.add_child(_sombra)

## A MANCHA ACOMPANHA O CORPO — e SOME NO TOMBO.
##
## Ela anda com a respiração e com o recuo do golpe, que é o que impede
## o corpo de deslizar por cima de uma mancha parada. Mas no tombo ela
## tem de sair de cena, e não só clarear.
##
## O motivo é o mesmo corte de sempre. A mancha é um PLANO HORIZONTAL a
## dois milímetros do tapete; enquanto o lutador está de pé, todo o
## desenho fica acima dela e os dois não se tocam. No tombo o corpo
## desce trinta e quatro centímetros, e aí o plano da mancha passa a
## ATRAVESSAR a ilustração: tudo o que fica abaixo da altura dela
## escurece de uma vez, numa linha reta. Um corpo caído já está no
## tapete e não precisa de mancha nenhuma para dizer que encostou.
##
## O sumiço é rápido de propósito — some antes de o corpo ter descido
## metade do caminho, para não haver um instante em que a linha apareça.
func _sombra_de_contato() -> void:
	if _sombra == null or lutador == null:
		return
	var desloc := lutador.deslocamento()
	var caido := clampf(lutador.queda, 0.0, 1.0)
	var some := clampf(caido * 2.5, 0.0, 1.0)
	_sombra.visible = some < 1.0
	if not _sombra.visible:
		return
	_sombra.position = Vector3(desloc.x, ALTURA_DA_SOMBRA, desloc.z * 0.6)
	_sombra.scale = Vector3(lerpf(1.0, 1.35, caido), 1.0, lerpf(1.0, 1.2, caido))
	var tinta := _sombra.material_override as StandardMaterial3D
	if tinta != null:
		tinta.albedo_color.a = lerpf(0.62, 0.0, some)

## O LUTADOR NÃO É MAIS PINTADO AQUI, e o bloco que fazia isso — cento e
## poucas linhas de sombreador de desenho, contorno por casca invertida e
## cor por vértice — saiu inteiro junto com o corpo procedural.
##
## Ele existia para transformar um modelo de plástico em algo que
## parecesse desenhado. Com uma ILUSTRAÇÃO no lugar do modelo, o desenho
## já vem desenhado: sombra, contorno, brilho do couro e a luz ciano e
## magenta na borda estão pintados na arte. Continuar sombreando por cima
## seria iluminar duas vezes.
##
## O que a arena ainda faz pelo lutador é o que só ela pode fazer: o
## clarão do soco (ver `_luzes`), o tremor, a câmera e as partículas.


func modelo_avancado() -> bool:
	return lutador != null and lutador.completo()

# ---------------------------------------------------------------- ritmo
func ligar(ativa: bool) -> void:
	if _ativa == ativa:
		return
	_ativa = ativa
	if not ativa:
		render_target_update_mode = SubViewport.UPDATE_DISABLED

func ativa() -> bool:
	return _ativa

## O SOCO CHEGOU NA ARENA. Devolve o que o corpo fez com ele.
func golpe(forca: float, derruba := false, pontos := -1) -> Dictionary:
	_tremor = clampf(0.35 + forca, 0.0, 1.35)
	_clarao = clampf(0.4 + forca * 0.6, 0.0, 1.0)
	_empurrao = forca
	_publico = maxf(_publico, clampf(0.08 + forca * (1.15 if derruba else 0.85), 0.0, 1.0))
	if _impacto_particulas != null:
		_impacto_particulas.amount = int(lerpf(18.0, 86.0, forca) * (1.0 if qualidade >= 0.55 else 0.55))
		_impacto_particulas.restart()
		_impacto_particulas.emitting = true
	if derruba and _poeira_particulas != null:
		_poeira_particulas.amount = 34 if qualidade >= 0.55 else 18
		_poeira_particulas.restart()
		_poeira_particulas.emitting = true
	if lutador == null:
		return {"nocaute": false, "dano": 0.0, "reacao": "", "desdenhou": false}
	var resposta := lutador.bater(forca, derruba, pontos)
	if bool(resposta.get("desdenhou", false)):
		# Uma onda curta na arquibancada acompanha o gesto do lutador. É
		# uma reação legível, mas menor que a explosão de um nocaute.
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
	_animar_torcida()
	# A resolução ainda se adapta ao PC, mas a arena recebe um quadro em
	# cada quadro do jogo. Cortá-la artificialmente para 30 Hz fazia o
	# personagem parecer travado mesmo quando a interface seguia lisa.
	render_target_update_mode = SubViewport.UPDATE_ONCE
	_ajustar_tamanho()

## Em qual degrau a janela está: 0 magra, 1 cheia, 2 nítida.
var _degrau := 1

func _ajustar_tamanho() -> void:
	var alvo := _degrau
	# Descer é urgente (a máquina já está sofrendo); subir é opcional.
	if _degrau == 2 and qualidade < DESCE_DO_NITIDO:
		alvo = 1
	elif _degrau <= 1 and qualidade >= SOBE_PARA_NITIDO:
		alvo = 2
	if alvo == 1 and qualidade < DESCE_DO_CHEIO:
		alvo = 0
	elif alvo == 0 and qualidade >= SOBE_PARA_CHEIO:
		alvo = 1
	if alvo == _degrau:
		return
	_degrau = alvo
	# `match` e não uma lista indexada: a lista seria construída a cada
	# quadro, e isto roda em `avancar`.
	match _degrau:
		0: size = TAMANHO_MAGRO
		2: size = TAMANHO_NITIDO
		_: size = TAMANHO_CHEIO

## ------------------------------------------------------- o enquadramento
##
## POR QUE ISTO É CONTA E NÃO MAIS TRÊS NÚMEROS À MÃO.
##
## O enquadramento já foi refeito quatro vezes — "afastou para caber",
## "chegou perto porque o corpo ganhou relevo", "afastou de novo porque
## a ilustração estourava". Cada vez que a arte mudava de tamanho,
## alguém reajustava distância e mira no olho e escrevia um parágrafo
## explicando. E a causa nunca esteve na câmera: estava na escala do
## desenho, que dizia 1,80 m e entregava 2,03 (ver `lutador.gd`).
##
## Com a escala medida, o enquadramento vira uma conta de três linhas:
## o lutador ocupa uma fração declarada da altura da janela, e a sobra
## se reparte igualmente entre a lona embaixo e as cordas em cima. Trocar
## a arte por outra de proporção diferente não pede reajuste nenhum.

## Distância, altura da câmera e altura da mira para o lutador ocupar
## `OCUPACAO_DO_LUTADOR` da janela com a sobra repartida em partes iguais.
##
## A conta do topo e da base é feita NO PLANO DO DESENHO (z = 0), que é
## onde a figura está. Com a câmera inclinada de `t`, o raio de baixo sai
## a `t + meia_abertura` da horizontal e o de cima a `meia_abertura - t`;
## a altura em que cada um cruza z = 0 é `altura_da_camera ± distancia *
## tan(ângulo)`. Invertendo a de baixo sai a altura da câmera que põe a
## base da janela exatamente onde se quer.
func _calcular_enquadramento() -> void:
	var figura := Lutador3D.ALTURA_DA_FIGURA
	var janela := figura / OCUPACAO_DO_LUTADOR
	var meia := deg_to_rad(camera.fov) * 0.5
	_distancia = janela / (2.0 * tan(meia))
	# A sobra repartida: metade vira tapete embaixo, metade vira ar em
	# cima. E a conta parte do PISO, não de zero: o lutador está pousado
	# em cima do miolo da lona, e enquadrar a partir de zero deixaria a
	# folga de baixo um centímetro e meio menor do que a de cima.
	var base := piso_do_lutador() - (janela - figura) * 0.5
	var inclinacao := atan(CAMERA_ACIMA_DA_MIRA / _distancia)
	_altura_da_camera = base + _distancia * tan(inclinacao + meia)
	_altura_da_mira = _altura_da_camera - CAMERA_ACIMA_DA_MIRA

## A CÂMERA TAMBÉM APANHA. Ela recua no impacto, treme junto e volta
## sozinha — é o que transforma "o boneco se mexeu" em "a pancada foi
## sentida daqui". Um passeio lento e contínuo, por baixo, mantém a
## profundidade viva mesmo quando ninguém está batendo.
func _camera() -> void:
	if camera == null:
		return
	var passeio := sin(_relogio * 0.33) * 0.16
	var sacode := Vector3.ZERO
	if _tremor > 0.02:
		sacode = Vector3(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-0.4, 0.4)
		) * _tremor * 0.055
	# O ENQUADRAMENTO VEM DE `_calcular_enquadramento`, e o que sobra aqui
	# é só o que se MEXE: o passeio lateral, a respiração vertical e o
	# empurrão do impacto. Distância e mira deixaram de ser número
	# escrito à mão justamente porque foram reescritos à mão quatro
	# vezes, sempre para compensar uma escala errada do desenho.
	var pos := Vector3(
		passeio,
		_altura_da_camera + sin(_relogio * 0.21) * 0.05,
		_distancia - _empurrao * 0.30
	)
	var mira := Vector3(0.0, _altura_da_mira + _empurrao * 0.06, 0.0)
	# QUANDO ELE CAI, A CÂMERA VAI JUNTO. Ficar parada na altura do peito
	# depois do nocaute deixaria a moldura com um ringue vazio e o corpo
	# fora de quadro — que foi exatamente o que aconteceu na primeira
	# montagem. Subir e olhar para baixo é o que qualquer transmissão faz.
	var caido := lutador.queda if lutador != null else 0.0
	if caido > 0.001:
		# O NOCAUTE É O MELHOR MOMENTO DO JOGO, e a câmera desce para ver
		# o corpo na lona de perto — mas AGORA ELA CONTINUA DE FRENTE.
		#
		# Antes ela dava a volta para o lado, e isso era o certo para um
		# corpo modelado em três dimensões: de frente e de cima, um corpo
		# caído de costas é visto pela sola dos pés e a imagem não diz
		# "nocaute". Com uma ILUSTRAÇÃO, a regra se inverte: o desenho do
		# nocaute já mostra o corpo deitado do ângulo certo, e é um plano
		# — dar a volta nele o mostraria de perfil, ou seja, de canto,
		# uma lâmina. A câmera desce, chega perto e fica de frente.
		#
		# E ELA AFASTA, NÃO APROXIMA. Um corpo em pé é alto e estreito; um
		# corpo caído é BAIXO E LARGO, e o desenho do nocaute ocupa a
		# largura inteira do quadro. Chegando perto — que é o instinto —
		# a imagem corta os dois braços e sobra um torso gigante sem
		# contexto. Afastando e descendo até quase a altura da lona, o
		# corpo aparece inteiro e a câmera parece estar no tapete, que é
		# onde toda transmissão de boxe põe a dela.
		#
		# As duas alturas e a distância do nocaute são FRAÇÕES do
		# enquadramento em pé, e não números soltos: se o lutador mudar
		# de tamanho, a tomada da lona acompanha sozinha. Descer a
		# câmera a pouco mais da metade da altura e afastar 7% é o que
		# põe o olho quase no tapete com o corpo deitado inteiro dentro
		# do quadro.
		var t := ease(caido, 0.5)
		pos = pos.lerp(
			Vector3(0.0, _altura_da_camera * 0.54, _distancia * 1.07), t
		)
		mira = mira.lerp(Vector3(0.0, _altura_da_mira * 0.58, 0.0), t)
	camera.position = pos + sacode
	camera.look_at(mira, Vector3.UP)

func _luzes() -> void:
	# O CLARÃO TAMBÉM ACENDE A ILUSTRAÇÃO, e não só as luzes da arena.
	# Sem isso o lutador ficava calmo, na sua cor de sempre, enquanto tudo
	# em volta dele explodia — e o olho nota essa discordância antes de
	# saber explicá-la.
	if lutador != null:
		lutador.clarao(_clarao)
	# O golpe ACENDE a arena por um instante, pelas luzes de contorno. Um
	# clarão branco por cima lavaria a imagem; puxar o contorno mantém as
	# cores e ainda assim diz "explodiu".
	var extra := _clarao * 6.0
	if _rim_quente != null:
		_rim_quente.light_energy = 2.15 + extra
	if _rim_frio != null:
		_rim_frio.light_energy = 2.00 + extra
	if _luz_chave != null:
		_luz_chave.light_energy = 2.10 + _clarao * 1.1

func _piscar() -> void:
	if _flashes == null:
		return
	var mm := _flashes.multimesh
	# Na pancada a plateia inteira dispara ao mesmo tempo; parada, é um
	# ou outro piscando aqui e ali.
	var festa := _clarao
	for i in range(mm.instance_count):
		var fase: float = _flash_fase[i]
		var base := maxf(0.0, sin(_relogio * 1.7 + fase) - 0.93) * 9.0
		var a := clampf(base + festa * (0.35 + 0.65 * absf(sin(fase * 3.1 + _relogio * 22.0))), 0.0, 1.0)
		# O BRILHO VAI NO RGB, E NÃO NA TRANSPARÊNCIA. Em mistura aditiva
		# o alfa não apaga nada: um flash "invisível" com alfa 0 continuava
		# somando branco na tela e virava um quadrado cinza permanente
		# dentro da arena. Escurecendo a COR, apagado é preto, e preto
		# somado não muda pixel nenhum.
		mm.set_instance_color(i, Color(a, a * 0.96, a * 0.88, 1.0))

func _animar_torcida() -> void:
	if _torcida == null:
		return
	var mm := _torcida.multimesh
	for i in range(mm.instance_count):
		var t := Transform3D()
		var onda := maxf(0.0, sin(_relogio * (7.0 + _publico * 4.0) + float(i) * 1.73))
		var energia := _publico * (0.10 + 0.16 * onda)
		t.origin = _torcida_base[i] + Vector3(0.0, energia, 0.0)
		t.basis = Basis.from_euler(Vector3(0.0, 0.0, sin(_relogio * 5.0 + i) * _publico * 0.08))
		mm.set_instance_transform(i, t)
