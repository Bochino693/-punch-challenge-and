class_name Icones
extends RefCounted

## Ícones desenhados em código.
##
## SEM ARQUIVO DE IMAGEM. São cinco formas simples, e um PNG de cada uma
## traria três problemas que o desenho não tem: some se o arquivo faltar,
## serrilha quando a tela muda de tamanho, e não muda de cor junto com a
## faixa do golpe. Aqui cada ícone é uma função que recebe centro, raio e
## cor — o mesmo troféu serve dourado no cartão e cinza na Central.
##
## Todos desenham CENTRADOS em `centro` e cabem numa caixa de `2 * raio`,
## então trocar um ícone por outro no mesmo lugar nunca desalinha nada.

## Troféu — o recorde da casa.
static func trofeu(ci: CanvasItem, centro: Vector2, raio: float, cor: Color) -> void:
	var r := raio
	var taca := PackedVector2Array([
		centro + Vector2(-r * 0.52, -r * 0.80),
		centro + Vector2(r * 0.52, -r * 0.80),
		centro + Vector2(r * 0.40, -r * 0.06),
		centro + Vector2(0.0, r * 0.26),
		centro + Vector2(-r * 0.40, -r * 0.06),
	])
	Traco.poligono(ci, taca, cor)
	# Alças dos dois lados, abertas para fora.
	for lado in [-1.0, 1.0]:
		ci.draw_arc(
			centro + Vector2(lado * r * 0.62, -r * 0.50), r * 0.30,
			-PI * 0.5 if lado > 0.0 else PI * 0.5,
			PI * 0.5 if lado > 0.0 else PI * 1.5,
			18, cor, r * 0.15, true
		)
	# Haste e base.
	ci.draw_rect(Rect2(centro.x - r * 0.12, centro.y + r * 0.22, r * 0.24, r * 0.34), cor)
	ci.draw_rect(Rect2(centro.x - r * 0.46, centro.y + r * 0.54, r * 0.92, r * 0.22), cor)

## Cinturão de campeão — a conquista máxima da luta.
static func cinturao(ci: CanvasItem, centro: Vector2, raio: float, cor: Color) -> void:
	var r := raio
	var couro := cor.darkened(0.72)
	var faixa := PackedVector2Array([
		centro + Vector2(-r, -r * 0.28), centro + Vector2(-r * 0.46, -r * 0.42),
		centro + Vector2(-r * 0.30, -r * 0.30), centro + Vector2(r * 0.30, -r * 0.30),
		centro + Vector2(r * 0.46, -r * 0.42), centro + Vector2(r, -r * 0.28),
		centro + Vector2(r, r * 0.28), centro + Vector2(r * 0.46, r * 0.42),
		centro + Vector2(r * 0.30, r * 0.30), centro + Vector2(-r * 0.30, r * 0.30),
		centro + Vector2(-r * 0.46, r * 0.42), centro + Vector2(-r, r * 0.28),
	])
	Traco.poligono(ci, faixa, couro)
	ci.draw_circle(centro, r * 0.50, cor.darkened(0.20), true, -1.0, true)
	ci.draw_arc(centro, r * 0.50, 0.0, TAU, 36, cor, r * 0.10, true)
	ci.draw_circle(centro, r * 0.30, cor, true, -1.0, true)
	# Luva em relevo no centro deixa inequívoco que é prêmio de luta.
	luva_vulto(ci, centro, r * 0.22, couro)

## Luva de boxe — as partidas jogadas. A MESMA forma do ícone do
## aplicativo (`tools/gerar_icone.py`), para a luva da barra de tarefas e
## a luva do cartão serem reconhecidamente a mesma coisa.
##
## A silhueta é a UNIÃO de quatro formas redondas, e o contorno sai de
## desenhar as mesmas quatro DILATADAS por baixo — assim a borda continua
## redonda. Duas tentativas anteriores falharam por motivos opostos:
## círculos encostados sem contorno leem como cogumelo, e um polígono de
## poucos vértices escalado para virar contorno ganha bicos. Os dois
## riscos brancos (vinco dos dedos e faixa do punho) terminam a leitura.
static func luva(ci: CanvasItem, centro: Vector2, raio: float, cor: Color) -> void:
	var r := raio
	_massa_da_luva(ci, centro, r, r * 0.10, cor.darkened(0.45))
	_massa_da_luva(ci, centro, r, 0.0, cor)
	ci.draw_line(
		centro + Vector2(-r * 0.24, -r * 0.22), centro + Vector2(r * 0.58, -r * 0.26),
		Color(1, 1, 1, 0.92), r * 0.11, true
	)
	ci.draw_line(
		centro + Vector2(-r * 0.20, r * 0.42), centro + Vector2(r * 0.38, r * 0.42),
		Color(1, 1, 1, 0.92), r * 0.12, true
	)

## A LUVA SEM OS BRILHOS: só o vulto, na cor pedida.
##
## Os riscos brancos de `luva()` são fixos e opacos de propósito, para o
## ícone ler bem em qualquer fundo. Num rastro de movimento eles viram
## listras de tinta atrás da luva — cada fantasma do rastro precisa ser
## uma mancha só, e é isso que esta função entrega.
static func luva_vulto(ci: CanvasItem, centro: Vector2, raio: float, cor: Color) -> void:
	_massa_da_luva(ci, centro, raio, 0.0, cor)

## Punho, palma, dedão e cano da luva, todos crescidos de `folga`.
static func _massa_da_luva(ci: CanvasItem, centro: Vector2, r: float, folga: float, cor: Color) -> void:
	ci.draw_circle(centro + Vector2(r * 0.10, -r * 0.26), r * 0.64 + folga, cor, true, -1.0, true)
	ci.draw_circle(centro + Vector2(-r * 0.58, r * 0.02), r * 0.30 + folga, cor, true, -1.0, true)
	_caixa_redonda(ci, Rect2(
		centro + Vector2(-r * 0.54 - folga, -r * 0.30 - folga),
		Vector2(r * 1.12 + folga * 2.0, r * 0.56 + folga * 2.0)
	), r * 0.16, cor)
	_caixa_redonda(ci, Rect2(
		centro + Vector2(-r * 0.30 - folga, r * 0.24 - folga),
		Vector2(r * 0.80 + folga * 2.0, r * 0.60 + folga * 2.0)
	), r * 0.16, cor)

static func _caixa_redonda(ci: CanvasItem, rect: Rect2, raio: float, cor: Color) -> void:
	var r := minf(raio, minf(rect.size.x, rect.size.y) * 0.5)
	var pontos := PackedVector2Array()
	for c in [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5],
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
		[Vector2(rect.position.x + r, rect.position.y + r), PI],
	]:
		var meio: Vector2 = c[0]
		var a0: float = c[1]
		for i in range(7):
			var a := a0 + float(i) / 6.0 * PI * 0.5
			pontos.append(meio + Vector2(cos(a), sin(a)) * r)
	Traco.poligono(ci, pontos, cor)

## Ficha — os créditos.
##
## Os ENTALHES da borda existem para diferenciá-la do alvo: sem eles,
## dois anéis concêntricos com um miolo são a mesma figura, e a tela
## acaba com dois ícones idênticos dizendo coisas diferentes.
static func ficha(ci: CanvasItem, centro: Vector2, raio: float, cor: Color) -> void:
	var r := raio
	ci.draw_circle(centro, r * 0.88, cor, true, -1.0, true)
	for i in range(8):
		var a := float(i) / 8.0 * TAU + PI / 8.0
		ci.draw_line(
			centro + Vector2(cos(a), sin(a)) * r * 0.66,
			centro + Vector2(cos(a), sin(a)) * r * 0.95,
			Color(1, 1, 1, 0.9), r * 0.18, true
		)
	ci.draw_arc(centro, r * 0.58, 0.0, TAU, 40, Color(1, 1, 1, 0.85), r * 0.10, true)
	estrela(ci, centro, r * 0.34, Color(1, 1, 1, 0.95))

## Raio — potência e o passo do soco.
static func raio_eletrico(ci: CanvasItem, centro: Vector2, raio: float, cor: Color) -> void:
	var r := raio
	Traco.poligono(
		ci,
		PackedVector2Array([
			centro + Vector2(r * 0.20, -r * 0.90),
			centro + Vector2(-r * 0.55, r * 0.14),
			centro + Vector2(-r * 0.05, r * 0.14),
			centro + Vector2(-r * 0.22, r * 0.90),
			centro + Vector2(r * 0.58, -r * 0.16),
			centro + Vector2(r * 0.06, -r * 0.16),
		]),
		cor
	)

## Estrela de cinco pontas — recorde novo, destaque.
static func estrela(ci: CanvasItem, centro: Vector2, raio: float, cor: Color) -> void:
	var pontos := PackedVector2Array()
	for i in range(10):
		var a := -PI * 0.5 + float(i) * PI / 5.0
		var r := raio if i % 2 == 0 else raio * 0.45
		pontos.append(centro + Vector2(cos(a), sin(a)) * r)
	Traco.poligono(ci, pontos, cor)

## Boneco — o lugar da foto de quem ainda não foi fotografado. Sem ele o
## quadro sem foto vira um buraco, e buraco parece defeito, não "vaga".
static func avatar(ci: CanvasItem, centro: Vector2, raio: float, cor: Color) -> void:
	var r := raio
	ci.draw_circle(centro + Vector2(0.0, -r * 0.40), r * 0.40, cor, true, -1.0, true)
	# Ombros: meia elipse cortada na altura do queixo.
	var ombros := PackedVector2Array()
	for i in range(21):
		var a := PI + float(i) / 20.0 * PI
		ombros.append(centro + Vector2(cos(a) * r * 0.80, r * 0.66 + sin(a) * r * 0.56))
	ombros.append(centro + Vector2(r * 0.80, r * 0.80))
	ombros.append(centro + Vector2(-r * 0.80, r * 0.80))
	Traco.poligono(ci, ombros, cor)

## Alvo — onde o soco tem de chegar.
static func alvo(ci: CanvasItem, centro: Vector2, raio: float, cor: Color) -> void:
	ci.draw_arc(centro, raio * 0.82, 0.0, TAU, 44, cor, raio * 0.18, true)
	ci.draw_arc(centro, raio * 0.44, 0.0, TAU, 32, cor, raio * 0.16, true)
	ci.draw_circle(centro, raio * 0.14, cor, true, -1.0, true)

## Botão de arcade visto de cima — o passo do START.
##
## O aro é BEM mais escuro que a calota de propósito: dois discos de
## tons parecidos, um dentro do outro, leem como uma bolha só. É o
## degrau de tom que faz o olho enxergar um botão de apertar.
static func botao(ci: CanvasItem, centro: Vector2, raio: float, cor: Color) -> void:
	var r := raio
	ci.draw_circle(centro, r * 0.95, cor.darkened(0.45), true, -1.0, true)
	ci.draw_arc(centro, r * 0.95, 0.0, TAU, 44, cor.darkened(0.65), r * 0.10, true)
	ci.draw_circle(centro - Vector2(0.0, r * 0.05), r * 0.64, cor, true, -1.0, true)
	ci.draw_arc(
		centro - Vector2(0.0, r * 0.05), r * 0.40,
		PI * 1.08, PI * 1.78, 20, Color(1, 1, 1, 0.75), r * 0.16, true
	)
