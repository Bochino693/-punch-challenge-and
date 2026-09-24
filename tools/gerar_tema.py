"""Gera a identidade SUPER BOXING do jogo (combina com o gabinete).

    python tools/gerar_tema.py

Tudo sai como IMAGEM pronta, e não como texto desenhado pelo jogo: numa
TV Box cada tamanho novo de letra é rasterizado na hora e pode engasgar
ou sair serrilhado. Uma imagem com mipmap é desenhada igual em qualquer
aparelho.

Saídas em assets/tema/:
  fundo.jpg            1080x1920  raios roxo/magenta/azul sobre azul-noite
  logo.png             estrela com SUPER BOXING, R vermelho e a luva no O
  fight.png            "FIGHT!" amarelo-laranja, pichado
  never_give_up.png    "NEVER GIVE UP!" branco, pincel
  ate_o_fim.png        "FIGHT TILL THE END"
  moldura_arena.png    faixa zebrada amarelo/preto com cantos chanfrados
                       (a mesma do vidro do gabinete) em volta da arena

Requer: numpy, scipy, pillow.
"""
from pathlib import Path
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
from scipy import ndimage as nd

RAIZ = Path(__file__).resolve().parents[1]
SAIDA = RAIZ / "assets" / "tema"
BUNGEE = str(RAIZ / "assets" / "fonts" / "Bungee-Regular.ttf")
SAIRA = str(RAIZ / "assets" / "fonts" / "SairaCondensed-ExtraBold.ttf")
rng = np.random.default_rng(20260924)

NOITE = (11, 6, 32)
ROXO = (122, 46, 255)
MAGENTA = (255, 38, 168)
AZUL = (40, 110, 255)
CIANO = (70, 220, 255)
AMARELO = (255, 208, 20)
VERMELHO = (232, 16, 42)
BRANCO = (255, 255, 255)


def cor(c, a=255):
    return tuple(c) + (a,)


# ----------------------------------------------------------------- fundo
def raio(d: ImageDraw.ImageDraw, x0, y0, x1, y1, largura, cor_, passos=9, desvio=38.0):
    """Relâmpago em zigue-zague de (x0,y0) até (x1,y1)."""
    pts = [(x0, y0)]
    for i in range(1, passos):
        t = i / passos
        x = x0 + (x1 - x0) * t + rng.uniform(-desvio, desvio)
        y = y0 + (y1 - y0) * t + rng.uniform(-desvio, desvio)
        pts.append((x, y))
    pts.append((x1, y1))
    d.line(pts, fill=cor_, width=largura, joint="curve")
    return pts


def fundo():
    W, H = 1080, 1920
    yy = np.linspace(0, 1, H)[:, None, None]
    base = np.array(NOITE, np.float32) / 255
    meio = np.array((34, 10, 70), np.float32) / 255
    img = base * (1 - np.abs(yy - 0.5) * 2)[..., :] * 0 + base
    img = np.broadcast_to(base, (H, W, 3)).copy()
    img = img * (1 - np.exp(-((yy - 0.45) / 0.35) ** 2)) + meio * np.exp(-((yy - 0.45) / 0.35) ** 2)

    # Riscos de velocidade: fachos finos saindo de um ponto fora da tela,
    # em magenta, roxo e azul — o desenho do gabinete.
    camada = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(camada)
    # Como no gabinete: feixes DIAGONAIS (de baixo-esquerda para
    # cima-direita), em maços, com alguns cruzando no sentido oposto.
    for _ in range(400):
        cruza = rng.random() < 0.22
        ang = math.radians(rng.normal(-38, 7) if not cruza else rng.normal(35, 6))
        x = rng.uniform(-400, W + 400)
        y = rng.uniform(-200, H + 200)
        comp = rng.uniform(120, 760)
        c = [MAGENTA, ROXO, AZUL, CIANO, (190, 60, 255), MAGENTA][rng.integers(6)]
        k = rng.uniform(0.25, 0.95)
        d.line([(x, y), (x + math.cos(ang) * comp, y + math.sin(ang) * comp)],
               fill=tuple(int(v * k) for v in c), width=int(rng.integers(2, 11)))
    riscos = np.asarray(camada, np.float32) / 255
    img += nd.gaussian_filter(riscos, (6, 6, 0)) * 0.9 + riscos * 0.55

    # Relâmpagos brancos com halo azul.
    luz = Image.new("RGB", (W, H), (0, 0, 0))
    dl = ImageDraw.Draw(luz)
    for x0, y0, x1, y1 in [(40, 260, 260, 760), (1060, 120, 820, 620), (60, 1420, 330, 1860),
                           (1040, 1300, 780, 1880), (500, 40, 610, 330)]:
        raio(dl, x0, y0, x1, y1, 5, (255, 255, 255))
    l = np.asarray(luz, np.float32) / 255
    img += nd.gaussian_filter(l, (14, 14, 0)) * np.array([0.35, 0.55, 1.6]) + l * 0.9

    # Respingos de tinta.
    resp = Image.new("RGB", (W, H), (0, 0, 0))
    dr = ImageDraw.Draw(resp)
    for _ in range(260):
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        r = rng.uniform(1.5, 7) * (1 + (rng.random() < 0.08) * 3)
        c = [MAGENTA, ROXO, AZUL, BRANCO][rng.integers(4)]
        k = rng.uniform(0.3, 0.8)
        dr.ellipse([x - r, y - r, x + r, y + r], fill=tuple(int(v * k) for v in c))
    img += np.asarray(resp, np.float32) / 255 * 0.7

    # O miolo mais calmo: é onde ficam a arena e o placar.
    y, x = np.mgrid[:H, :W].astype(np.float32)
    calmo = np.exp(-(((x - W / 2) / (W * 0.42)) ** 2 + ((y - H * 0.47) / (H * 0.36)) ** 2))
    img *= (1 - 0.72 * calmo)[..., None]
    # Mais escuro que o gabinete: aqui por cima vão letras e números, e
    # eles têm de ser lidos de longe.
    img *= 0.58
    img += rng.normal(0, 0.008, img.shape).astype(np.float32)
    img = np.clip(img, 0, 1)
    Image.fromarray((img * 255).astype(np.uint8)).save(SAIDA / "fundo.jpg", quality=92)
    print("ok fundo.jpg")


# -------------------------------------------------------------- letreiros
def texto_mascara(texto, fonte, tamanho, inclina=0.0):
    f = ImageFont.truetype(fonte, tamanho)
    caixa = f.getbbox(texto)
    w, h = caixa[2] - caixa[0] + tamanho, caixa[3] - caixa[1] + tamanho
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).text((tamanho / 2 - caixa[0], tamanho / 2 - caixa[1]), texto, font=f, fill=255)
    if inclina:
        m = m.transform(m.size, Image.AFFINE, (1, inclina, -inclina * h * 0.5, 0, 1, 0), Image.BICUBIC)
    return m


def contorno(m: Image.Image, px: int) -> Image.Image:
    return m.filter(ImageFilter.MaxFilter(px * 2 + 1)) if px > 0 else m


def degrade_vertical(tam, cima, baixo):
    w, h = tam
    t = np.linspace(0, 1, h)[:, None, None]
    a = np.array(cima, np.float32)[None, None, :3]
    b = np.array(baixo, np.float32)[None, None, :3]
    g = a * (1 - t) + b * t
    return Image.fromarray(np.broadcast_to(g, (h, w, 3)).astype(np.uint8))


def pintar(m, preenchimento, fundo=None):
    out = fundo or Image.new("RGBA", m.size, (0, 0, 0, 0))
    camada = preenchimento.convert("RGBA")
    camada.putalpha(m)
    out.alpha_composite(camada)
    return out


def letreiro(texto, fonte, tamanho, cima, baixo, borda_cor, borda_px, sombra_px=0, inclina=0.0,
             brilho=True):
    m = texto_mascara(texto, fonte, tamanho, inclina)
    pad = borda_px * 2 + sombra_px + 20
    big = Image.new("L", (m.width + pad * 2, m.height + pad * 2), 0)
    big.paste(m, (pad, pad))
    m = big
    img = Image.new("RGBA", m.size, (0, 0, 0, 0))
    if sombra_px:
        s = contorno(m, borda_px).transform(m.size, Image.AFFINE, (1, 0, -sombra_px * 0.6, 0, 1, -sombra_px), Image.BILINEAR)
        img = pintar(s, Image.new("RGB", m.size, (8, 3, 22)), img)
    img = pintar(contorno(m, borda_px), Image.new("RGB", m.size, borda_cor[:3]), img)
    img = pintar(m, degrade_vertical(m.size, cima, baixo), img)
    if brilho:
        # fio de luz na metade de cima de cada letra
        topo = np.asarray(m, np.float32) / 255
        desl = np.roll(topo, int(tamanho * 0.06), axis=0)
        fio = np.clip(topo - desl, 0, 1) * 0.55
        luz = Image.fromarray((fio * 255).astype(np.uint8))
        img = pintar(luz, Image.new("RGB", m.size, (255, 255, 255)), img)
    return img.crop(img.getbbox())


def estrela(w, h, pontas=16, fundo_int=0.62, seed=3):
    r = np.random.default_rng(seed)
    cx, cy = w / 2, h / 2
    pts = []
    for i in range(pontas * 2):
        a = i / (pontas * 2) * math.tau - math.pi / 2
        k = 1.0 if i % 2 == 0 else fundo_int
        k *= r.uniform(0.86, 1.08)
        pts.append((cx + math.cos(a) * w / 2 * k, cy + math.sin(a) * h / 2 * k))
    return pts


def luva(tam):
    """Luva vermelha de frente (o O de BOXING)."""
    s = tam
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([s * 0.08, s * 0.04, s * 0.92, s * 0.86], fill=cor((70, 4, 14)))
    d.ellipse([s * 0.12, s * 0.07, s * 0.88, s * 0.81], fill=cor(VERMELHO))
    d.ellipse([s * 0.02, s * 0.38, s * 0.34, s * 0.72], fill=cor((70, 4, 14)))
    d.ellipse([s * 0.05, s * 0.41, s * 0.31, s * 0.69], fill=cor((205, 14, 36)))
    d.rounded_rectangle([s * 0.26, s * 0.74, s * 0.74, s * 0.98], radius=s * 0.06, fill=cor((245, 245, 245)))
    d.rectangle([s * 0.26, s * 0.83, s * 0.74, s * 0.87], fill=cor(VERMELHO))
    d.ellipse([s * 0.30, s * 0.14, s * 0.56, s * 0.34], fill=(255, 140, 150, 170))
    return img.filter(ImageFilter.GaussianBlur(0.8))


def logo():
    W, H = 1400, 900
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # A estrela: contorno escuro, borda branca, miolo azul-roxo com riscos.
    for escala, c in ((1.00, (12, 6, 30, 255)), (0.965, (255, 255, 255, 255)), (0.925, None)):
        pts = estrela(W * 0.98 * escala, H * 0.96 * escala)
        pts = [(x + W * (1 - 0.98 * escala) / 2, y + H * (1 - 0.96 * escala) / 2) for x, y in pts]
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).polygon(pts, fill=255)
        if c is not None:
            img = pintar(m, Image.new("RGB", (W, H), c[:3]), img)
        else:
            miolo = degrade_vertical((W, H), (60, 120, 255), (86, 20, 170)).convert("RGBA")
            dm = ImageDraw.Draw(miolo)
            for _ in range(60):
                a = rng.uniform(0, math.tau)
                r0, r1 = rng.uniform(60, 250), rng.uniform(300, 700)
                dm.line([(W / 2 + math.cos(a) * r0, H / 2 + math.sin(a) * r0 * 0.65),
                         (W / 2 + math.cos(a) * r1, H / 2 + math.sin(a) * r1 * 0.65)],
                        fill=(180, 220, 255, 90), width=int(rng.integers(2, 6)))
            img = pintar(m, miolo.convert("RGB"), img)
    # SUPER (R vermelho) e BOXING (luva no O)
    su = letreiro("SUPE", BUNGEE, 230, (255, 255, 255), (170, 200, 255), (14, 8, 40), 16, 10, -0.12)
    rr = letreiro("R", BUNGEE, 260, (255, 90, 100), (190, 10, 30), (14, 8, 40), 16, 10, -0.12)
    y0 = 150
    x0 = (W - (su.width + rr.width - 30)) // 2
    img.alpha_composite(su, (x0, y0 + 20))
    img.alpha_composite(rr, (x0 + su.width - 30, y0 - 10))
    b = letreiro("B", BUNGEE, 210, (255, 255, 255), (170, 200, 255), (14, 8, 40), 15, 10, -0.12)
    xi = letreiro("XING", BUNGEE, 210, (255, 255, 255), (170, 200, 255), (14, 8, 40), 15, 10, -0.12)
    lv = luva(200)
    lv_borda = Image.new("RGBA", (lv.width + 30, lv.height + 30), (0, 0, 0, 0))
    a = lv.split()[3].filter(ImageFilter.MaxFilter(29))
    lv_borda = pintar(a.resize(lv_borda.size), Image.new("RGB", lv_borda.size, (14, 8, 40)), lv_borda)
    lv_borda.alpha_composite(lv, (15, 15))
    total = b.width + lv_borda.width + xi.width - 40
    x1 = (W - total) // 2
    y1 = 455
    img.alpha_composite(b, (x1, y1))
    img.alpha_composite(lv_borda, (x1 + b.width - 20, y1 + 5))
    img.alpha_composite(xi, (x1 + b.width + lv_borda.width - 40, y1))
    img = img.crop(img.getbbox())
    img.save(SAIDA / "logo.png", optimize=True)
    print("ok logo.png", img.size)


def fight():
    f = letreiro("FIGHT!", BUNGEE, 300, (255, 238, 60), (255, 96, 20), (30, 8, 50), 18, 18, -0.28)
    # respingos em volta
    base = Image.new("RGBA", (f.width + 80, f.height + 80), (0, 0, 0, 0))
    d = ImageDraw.Draw(base)
    for _ in range(40):
        x, y = rng.uniform(0, base.width), rng.uniform(0, base.height)
        r = rng.uniform(3, 12)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 150 + int(rng.uniform(0, 80)), 20, 200))
    base.alpha_composite(f, (40, 40))
    base.save(SAIDA / "fight.png", optimize=True)
    print("ok fight.png", base.size)


def never():
    n = letreiro("NEVER GIVE UP!", SAIRA, 190, (255, 255, 255), (214, 206, 255), (20, 8, 50), 12, 12, -0.22)
    n = n.rotate(7, resample=Image.BICUBIC, expand=True)
    n.save(SAIDA / "never_give_up.png", optimize=True)
    print("ok never_give_up.png", n.size)
    t = letreiro("FIGHT TILL THE END", SAIRA, 120, (255, 255, 255), (200, 210, 255), (20, 8, 50), 9, 0, -0.18, False)
    t.save(SAIDA / "ate_o_fim.png", optimize=True)
    print("ok ate_o_fim.png", t.size)


def moldura_arena():
    """Faixa zebrada em volta do quadro da arena (1024x1040 no jogo)."""
    fx, fy = 2, 2
    W, H = 1024 + 88, 1040 + 88
    W2, H2 = W * fx, H * fy
    img = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))
    faixa = 44 * fx
    corte = 70 * fx

    def octo(x0, y0, x1, y1, c):
        return [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1),
                (x0, y1 - c), (x0, y0 + c)]

    fora = Image.new("L", (W2, H2), 0)
    ImageDraw.Draw(fora).polygon(octo(0, 0, W2 - 1, H2 - 1, corte), fill=255)
    dentro = Image.new("L", (W2, H2), 0)
    ImageDraw.Draw(dentro).polygon(octo(faixa, faixa, W2 - 1 - faixa, H2 - 1 - faixa, corte - faixa * 0.4), fill=255)
    anel = ImageChops.subtract(fora, dentro)
    # listras diagonais
    y, x = np.mgrid[:H2, :W2]
    listra = (((x + y) // (34 * fx)) % 2 == 0)
    rgb = np.where(listra[..., None], np.array(AMARELO, np.uint8), np.array((16, 12, 18), np.uint8))
    # desgaste: arranhões pretos no amarelo
    gasto = nd.gaussian_filter(rng.normal(0, 1, (H2, W2)), 2.2)
    rgb = np.where((gasto > 0.55)[..., None] & listra[..., None], np.array((40, 30, 20), np.uint8), rgb)
    tinta = Image.fromarray(rgb.astype(np.uint8))
    img = pintar(anel, tinta, img)
    # fio de borda escuro dos dois lados
    d = ImageDraw.Draw(img)
    d.polygon(octo(0, 0, W2 - 1, H2 - 1, corte), outline=(10, 6, 24, 255), width=4 * fx)
    d.polygon(octo(faixa, faixa, W2 - 1 - faixa, H2 - 1 - faixa, corte - faixa * 0.4), outline=(10, 6, 24, 255), width=4 * fx)
    img = img.resize((W, H), Image.LANCZOS)
    img.save(SAIDA / "moldura_arena.png", optimize=True)
    print("ok moldura_arena.png", img.size)


if __name__ == "__main__":
    SAIDA.mkdir(parents=True, exist_ok=True)
    fundo()
    logo()
    fight()
    never()
    moldura_arena()
