class_name FolhaDoLutador
extends RefCounted

## A RÉGUA DA FOLHA DE POSES.
##
## Uma função só, usada por dois lugares que precisam concordar: a
## ferramenta que mede a arte (`tools/medir_folha.gd`) e o teste que
## reprova a build quando a arte deixa de bater com as constantes
## declaradas (`tests/test_folha_lutador.gd`). Se cada um medisse do seu
## jeito, os dois poderiam estar certos ao mesmo tempo e discordar.
##
## Ela mede ALFA, e não cor: o que interessa é onde há desenho e onde há
## nada — é isso que decide onde fica o topo da cabeça, onde fica a sola
## e se o desenho foi cortado pela borda da célula.

## A folha é 3 × 3 e cada célula tem este tamanho. Os números saem das
## regiões declaradas no `.tres`; ficam aqui só como conferência.
const LADO_X := 410.0
const LADO_Y := 426.0

## Abaixo deste alfa é halo, não desenho.
const LIMIAR := 32

## AS POSES EM PÉ, que são as que definem a escala. `preparado` fica de
## fora de propósito: o desenho dela é o corpo agachando, e a cabeça
## dele está mais baixa — medir a escala por ela esticaria o lutador.
const POSES_EM_PE := ["guarda", "idle"]

## AS POSES EM QUE O LUTADOR ESTÁ COM OS DOIS PÉS NO CHÃO.
##
## Todas elas têm de alcançar a última linha da célula, porque é ali que
## a arte desenhou a sola do pé da frente. Uma que não alcance está
## flutuando — e uma que a arte desenhe mais baixa não existe, porque
## não há mais célula.
const POSES_QUE_PISAM := [
	"guarda", "idle", "preparado", "jab", "direto", "impacto_corpo",
]

## Mede cada pose de uma `SpriteFrames`. Devolve, por nome de pose:
##   topo, base, esquerda, direita — a caixa do desenho DENTRO da célula;
##   sola — a mesma coisa que `base`, e está aqui com este nome porque é
##          ela que encosta no chão: a figura pousa pelo PONTO MAIS
##          BAIXO;
##   pe_de_tras — a última linha com tinta na metade esquerda. Informa,
##          mas NÃO serve de chão: o lutador está em guarda, um pé à
##          frente do outro, e o de trás aparece mais alto por
##          perspectiva. Foi confundir um com o outro que deixou a bota
##          da frente enterrada oito pixels no tapete;
##   bordas — quais bordas da célula o desenho encosta.
## Devolve vazio quando a folha não pôde ser lida.
static func medir(caminho: String) -> Dictionary:
	if not ResourceLoader.exists(caminho):
		return {}
	var frames := ResourceLoader.load(caminho) as SpriteFrames
	if frames == null:
		return {}
	# A folha é uma só para as nove poses: lê-se UMA vez. `get_data()`
	# devolve uma cópia de seis megabytes — pedir uma por pose seria
	# copiar cinquenta e quatro à toa.
	var bytes := PackedByteArray()
	var largura := 0
	var resultado := {}
	for nome in frames.get_animation_names():
		if frames.get_frame_count(nome) <= 0:
			continue
		var recorte := frames.get_frame_texture(nome, 0) as AtlasTexture
		if recorte == null or recorte.atlas == null:
			continue
		if bytes.is_empty():
			var folha := recorte.atlas.get_image()
			if folha == null:
				return {}
			if folha.get_format() != Image.FORMAT_RGBA8:
				folha.convert(Image.FORMAT_RGBA8)
			bytes = folha.get_data()
			largura = folha.get_width()
		resultado[str(nome)] = _medir_regiao(bytes, largura, recorte.region)
	return resultado

## Mede uma célula. Índice à mão sobre os bytes crus: `get_pixel` pixel a
## pixel em um milhão e meio de pixels transforma um teste de segundos
## em um de quase um minuto.
static func _medir_regiao(bytes: PackedByteArray, largura: int, regiao: Rect2) -> Dictionary:
	var x0 := int(regiao.position.x)
	var y0 := int(regiao.position.y)
	var x1 := x0 + int(regiao.size.x)
	var y1 := y0 + int(regiao.size.y)
	var meio := x0 + int(regiao.size.x) * 0.5

	var topo := y1
	var base := y0 - 1
	var esquerda := x1
	var direita := x0 - 1
	var pe_de_tras := -1
	for y in range(y0, y1):
		var linha := y * largura * 4
		var achou_na_esquerda := false
		for x in range(x0, x1):
			if bytes[linha + x * 4 + 3] <= LIMIAR:
				continue
			if y < topo:
				topo = y
			if y > base:
				base = y
			if x < esquerda:
				esquerda = x
			if x > direita:
				direita = x
			if x < meio:
				achou_na_esquerda = true
		if achou_na_esquerda:
			pe_de_tras = y

	var bordas := PackedStringArray()
	if base < y0:
		# célula vazia: nada a dizer sobre bordas
		return {
			"topo": 0, "base": -1, "esquerda": 0, "direita": -1,
			"sola": -1, "pe_de_tras": -1, "bordas": bordas, "vazia": true,
		}
	if topo <= y0:
		bordas.append("CIMA")
	if base >= y1 - 1:
		bordas.append("BAIXO")
	if esquerda <= x0:
		bordas.append("ESQUERDA")
	if direita >= x1 - 1:
		bordas.append("DIREITA")
	return {
		"topo": topo - y0,
		"base": base - y0,
		"esquerda": esquerda - x0,
		"direita": direita - x0,
		# A SOLA É A BASE. A figura encosta no chão pelo ponto mais baixo
		# dela, e não pelo pé que por acaso está mais à esquerda.
		"sola": base - y0,
		"pe_de_tras": (pe_de_tras - y0) if pe_de_tras >= 0 else -1,
		"bordas": bordas,
		"vazia": false,
	}
