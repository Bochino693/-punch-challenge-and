class_name Logos
extends RefCounted

## AS LOGOS NO TAMANHO CERTO.
##
## Cada logo existe pronta em vários tamanhos (`tools/gerar_logos.py`). Para
## desenhar numa altura, escolhe-se a versão IMEDIATAMENTE MAIOR: a placa de
## vídeo só reduz um pouquinho (no máximo 1,3x) e os traços finos não se
## quebram — era reduzir 1280 px para 66 px na hora que pixelava a marca.

const ALTURAS := [48, 64, 80, 96, 128, 160, 200, 256, 320, 400, 512]
const PASTA := "res://assets/logos/"
static var _cache := {}

static func textura(nome: String, altura: float) -> Texture2D:
	var h: int = ALTURAS[ALTURAS.size() - 1]
	for a in ALTURAS:
		if float(a) >= altura - 0.5:
			h = a
			break
	var chave := "%s_%d" % [nome, h]
	if not _cache.has(chave):
		var caminho := PASTA + chave.replace("_%d" % h, "_h%d" % h) + ".png"
		_cache[chave] = load(caminho) if ResourceLoader.exists(caminho) else null
	return _cache[chave]

## Desenha a logo com a altura pedida, em pixels inteiros (nítida).
## `ancora` é o ponto de referência; `alinhamento` 0 = centro, 1 = direita
## (a ancora é o canto direito de cima).
static func desenhar(ci: CanvasItem, nome: String, ancora: Vector2, altura: float, alpha := 1.0, alinhamento := 0) -> Rect2:
	var tex := textura(nome, altura)
	if tex == null:
		return Rect2()
	var h := roundf(altura)
	var w := roundf(h * float(tex.get_width()) / float(tex.get_height()))
	var pos := Vector2(ancora.x - w * 0.5, ancora.y - h * 0.5) if alinhamento == 0 else Vector2(ancora.x - w, ancora.y)
	var caixa := Rect2(pos.round(), Vector2(w, h))
	ci.draw_texture_rect(tex, caixa, false, Color(1, 1, 1, alpha))
	return caixa
