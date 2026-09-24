"""Pintura das texturas do boxeador (usado por gerar_boxeador.py).

Tudo é pintado no espaço UV, mas DECIDIDO no espaço 3D: cada texel sabe
onde fica no corpo (posição e normal de repouso) e a cor sai daí. É o que
deixa o cabelo, a barba, a sobrancelha e o cós do calção no lugar certo
sem depender do desenho do mapa UV.
"""
from __future__ import annotations

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as nd


# ------------------------------------------------------------ rasterizar
def rasterizar(tam: int, uv_c: np.ndarray, val_c: np.ndarray):
    """uv_c: (T,3,2) em [0,1]; val_c: (T,3,C). Devolve (tam,tam,C), máscara."""
    C = val_c.shape[2]
    out = np.zeros((tam, tam, C), np.float32)
    mask = np.zeros((tam, tam), bool)
    px = uv_c * tam - 0.5
    for t in range(px.shape[0]):
        a, b, c = px[t]
        x0 = int(np.floor(min(a[0], b[0], c[0]))) - 1
        x1 = int(np.ceil(max(a[0], b[0], c[0]))) + 1
        y0 = int(np.floor(min(a[1], b[1], c[1]))) - 1
        y1 = int(np.ceil(max(a[1], b[1], c[1]))) + 1
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, tam - 1), min(y1, tam - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        l0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / d
        l1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / d
        l2 = 1.0 - l0 - l1
        e = -0.02
        dentro = (l0 >= e) & (l1 >= e) & (l2 >= e)
        if not dentro.any():
            continue
        yy, xx = ys[dentro], xs[dentro]
        w = np.stack([l0[dentro], l1[dentro], l2[dentro]], 1)
        out[yy, xx] = w @ val_c[t]
        mask[yy, xx] = True
    return out, mask


def dilatar(img: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Espalha as bordas das ilhas UV para fora (sem costura escura)."""
    _, (iy, ix) = nd.distance_transform_edt(~mask, return_indices=True)
    return img[iy, ix]


# ----------------------------------------------------------------- ruído
_PERM = np.random.default_rng(7).permutation(256).astype(np.int32)
_PERM = np.concatenate([_PERM, _PERM])
_VAL = np.random.default_rng(11).random(512).astype(np.float32) * 2 - 1


def _hash(ix, iy, iz):
    return _VAL[_PERM[(_PERM[(_PERM[ix & 255] + iy) & 255] + iz) & 255]]


def ruido(p: np.ndarray, freq: float, semente: int = 0) -> np.ndarray:
    """Ruído de valor 3D suave, em [-1, 1]."""
    q = p * freq + semente * 17.31
    i = np.floor(q).astype(np.int32)
    t = q - i
    t = t * t * (3 - 2 * t)
    x, y, z = i[:, 0], i[:, 1], i[:, 2]
    tx, ty, tz = t[:, 0], t[:, 1], t[:, 2]
    c000 = _hash(x, y, z); c100 = _hash(x + 1, y, z)
    c010 = _hash(x, y + 1, z); c110 = _hash(x + 1, y + 1, z)
    c001 = _hash(x, y, z + 1); c101 = _hash(x + 1, y, z + 1)
    c011 = _hash(x, y + 1, z + 1); c111 = _hash(x + 1, y + 1, z + 1)
    a = c000 + (c100 - c000) * tx
    b = c010 + (c110 - c010) * tx
    c = c001 + (c101 - c001) * tx
    d = c011 + (c111 - c011) * tx
    e = a + (b - a) * ty
    g = c + (d - c) * ty
    return e + (g - e) * tz


def fbm(p, freq, oitavas=4, semente=0):
    s, amp, tot = 0.0, 1.0, 0.0
    for k in range(oitavas):
        s = s + ruido(p, freq * (2.03 ** k), semente + k) * amp
        tot += amp
        amp *= 0.5
    return s / tot


def suave(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def srgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


def mistura(base, cor, peso):
    return base + (np.asarray(cor, np.float32) - base) * peso[:, None]


# ------------------------------------------------------------------ pele
def pintar_pele(ctx: dict, tam: int = 4096):
    v, f, uv, fuv, n = ctx["v"], ctx["f"], ctx["uv"], ctx["fuv"], ctx["n"]
    # Canais por vértice: posição, normal, cavidade, e máscaras.
    cav = ctx["cavidade"]
    olho = ctx["olho"].astype(np.float32)
    cabeca = ctx["peso_cabeca"]
    val = np.concatenate([v, n, cav[:, None], olho[:, None], cabeca[:, None],
                          ctx["palpebra"][:, None]], 1).astype(np.float32)
    tri = ctx["tri_pele"]
    img, mask = rasterizar(tam, uv[fuv[tri]], val[f[tri]])
    img = dilatar(img, mask)
    H = img.shape[0]
    P = img[..., 0:3].reshape(-1, 3)
    N = img[..., 3:6].reshape(-1, 3)
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-6)
    CAV = img[..., 6].reshape(-1)
    OLHO = img[..., 7].reshape(-1)
    CAB = img[..., 8].reshape(-1)
    PALP = img[..., 9].reshape(-1)
    del img
    pos = ctx["ossos"]
    pt = ctx["pontos"]

    # ---- o tom de pele: moreno, com manchas largas de cor e de luz.
    cor = np.tile(srgb("a8704f"), (P.shape[0], 1))
    grande = fbm(P, 3.0, 3, 1)
    cor *= (1.0 + grande * 0.07)[:, None]
    avermelha = np.clip(fbm(P, 5.0, 3, 2) * 0.5 + 0.5, 0, 1)
    cor = mistura(cor, srgb("a55a45"), avermelha * 0.18)
    amarela = np.clip(fbm(P, 4.0, 2, 3), 0, 1)
    cor = mistura(cor, srgb("b58a5c"), amarela * 0.15)
    # Costas e ombros tostados de sol, barriga e parte de dentro mais clara.
    frente = N[:, 2]
    cor *= (1.0 - 0.05 * np.clip(-frente, 0, 1) + 0.03 * np.clip(frente, 0, 1))[:, None]

    # ---- relevo muscular: o vale entre músculos escurece, a crista acende.
    c = np.clip(CAV / 0.0035, -1.5, 1.5) * (1 - PALP)
    cor *= (1.0 - 0.21 * np.clip(c, 0, 1.5) + 0.06 * np.clip(-c, 0, 1))[:, None]

    # ---- sangue perto da pele: orelhas, nariz, bochechas, joelhos, cotovelos.
    def perto(ponto, raio):
        d = np.linalg.norm(P - np.asarray(ponto, np.float32), axis=1)
        return 1.0 - suave(raio * 0.35, raio, d)

    vermelho = perto(pt["nariz"], 0.03) * 0.5
    for s in (1, -1):
        vermelho = vermelho + perto(pt["orelha"] * [s, 1, 1], 0.045) * 0.55
        vermelho = vermelho + perto(pt["bochecha"] * [s, 1, 1], 0.035) * 0.35
        for osso in ("ForeArm", "Leg"):
            lado = "Left" if s > 0 else "Right"
            vermelho = vermelho + perto(pos[lado + osso], 0.06) * 0.25
    cor = mistura(cor, srgb("9c4a3c"), np.clip(vermelho, 0, 1) * 0.55)

    # ---- veias dos antebraços e bíceps: fios azulados finos.
    braco = np.zeros(P.shape[0], np.float32)
    for lado in ("Left", "Right"):
        a, b = pos[lado + "Arm"], pos[lado + "Hand"]
        ab = b - a
        t = np.clip(((P - a) @ ab) / ab.dot(ab), 0, 1)
        d = np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
        braco = np.maximum(braco, (1 - suave(0.045, 0.07, d)) * suave(0.15, 0.4, t))
    fio = 1.0 - np.abs(fbm(P * [1.0, 0.35, 1.0], 40.0, 3, 5))
    veia = suave(0.94, 0.985, fio) * braco
    cor = mistura(cor, srgb("7d6f72"), veia * 0.16)

    # ---- mamilos
    for s in (1, -1):
        d = np.linalg.norm(P - pt["mamilo"] * [s, 1, 1], axis=1)
        cor = mistura(cor, srgb("6d3f2e"), (1 - suave(0.006, 0.016, d)) * 0.75)

    # ---- rosto: lábios, sobrancelhas, barba por fazer, cílios.
    boca = pt["boca"]
    dx = (P[:, 0] - boca[0]) / 0.027
    dy = (P[:, 1] - boca[1]) / 0.0105
    labio = (1 - suave(0.75, 1.05, np.sqrt(dx * dx + dy * dy))) * suave(0.2, 0.6, N[:, 2]) * (P[:, 2] > boca[2] - 0.03)
    cor = mistura(cor, srgb("7a3f37"), labio * 0.55)
    fio_cabelo = np.clip(ruido(P * [1, 3.0, 1], 900.0, 9) * 0.5 + 0.5, 0, 1)
    for s in (1, -1):
        e = pt["olho"] * [s, 1, 1]
        # sobrancelha: arco afinando para fora, com fios
        u = (P[:, 0] - e[0]) * s  # para fora
        tu = np.clip((u + 0.019) / 0.047, 0, 1)
        altura = e[1] + 0.017 + 0.009 * np.sin(tu * 2.6) - 0.004 * tu
        grossura = 0.0038 * (1 - tu) + 0.0016 * tu
        banda = (1 - suave(grossura * 0.6, grossura, np.abs(P[:, 1] - altura)))
        banda *= suave(-0.021, -0.016, u) * (1 - suave(0.024, 0.030, u)) * suave(0.25, 0.5, N[:, 2])
        fios = np.clip(ruido(np.stack([P[:, 0] * 1.0, P[:, 1] * 0.25, P[:, 2]], 1), 2200.0, 8) * 0.8 + 0.5, 0, 1)
        cor = mistura(cor, srgb("1c1411"), np.clip(banda * (0.45 + 0.55 * fios), 0, 1) * 0.9)
        # linha dos cílios em volta do olho
        d = np.linalg.norm(P - e, axis=1)
        cilio = (1 - suave(pt["raio_olho"] + 0.0006, pt["raio_olho"] + 0.0024, d)) * (1 - OLHO)
        cilio *= 0.45 + 0.55 * suave(e[1] - 0.004, e[1] + 0.004, P[:, 1])
        cilio *= 1 - PALP * 0.85
        cor = mistura(cor, srgb("2a1c18"), np.clip(cilio, 0, 1) * 0.7)
    # barba por fazer: queixo, mandíbula, buço
    queixo = pt["queixo"]
    rosto = CAB * suave(0.0, 0.3, N[:, 2] + 0.35)
    abaixo_da_maca = suave(pt["maca_y"], pt["maca_y"] - 0.025, P[:, 1])
    acima_do_pescoco = suave(queixo[1] - 0.045, queixo[1] - 0.01, P[:, 1])
    na_frente = suave(pt["orelha"][2] - 0.01, pt["orelha"][2] + 0.03, P[:, 2])
    barba = rosto * abaixo_da_maca * acima_do_pescoco * na_frente * (1 - labio)
    pontinho = suave(-0.2, 0.6, ruido(P, 1400.0, 12))
    cor = mistura(cor, srgb("4a3a33"), np.clip(barba * (0.22 + 0.22 * pontinho), 0, 1))

    # ---- cabelo: degradê (máquina 1 dos lados, 3 em cima).
    cab_c = pt["centro_cabeca"]
    e_y = pt["olho"][1]
    rel = P - cab_c
    ang = np.arctan2(rel[:, 0], rel[:, 2])  # 0 = frente
    fa = np.cos(ang)
    # linha do cabelo: testa em cima, têmpora, acima da orelha, nuca
    linha = np.where(fa > 0, pt["testa_y"] - (1 - fa) ** 1.4 * 0.050,
                     pt["testa_y"] - 0.050 - np.clip(-fa, 0, 1) ** 0.8 * 0.085)
    # entradas discretas nas têmporas
    linha += 0.008 * np.exp(-((np.abs(ang) - 0.55) / 0.18) ** 2)
    orelha_d = np.minimum(np.linalg.norm(P - pt["orelha"], axis=1),
                          np.linalg.norm(P - pt["orelha"] * [-1, 1, 1], axis=1))
    borda = fbm(P, 90.0, 2, 22) * 0.004
    cabelo = suave(linha - 0.003, linha + 0.005, P[:, 1] + borda) * CAB * suave(0.026, 0.036, orelha_d)
    # costeleta curta na frente da orelha
    frente_orelha = (np.abs(np.abs(P[:, 0]) - (np.abs(pt["orelha"][0]) - 0.006)) < 0.016) \
        & (P[:, 2] > pt["orelha"][2] + 0.008) & (P[:, 2] < pt["orelha"][2] + 0.030) \
        & (P[:, 1] > pt["orelha"][1] - 0.012) & (P[:, 1] < linha)
    cabelo = np.maximum(cabelo, frente_orelha * CAB * 0.85)
    topo = suave(e_y + 0.03, e_y + 0.075, P[:, 1])
    densidade = 0.45 + 0.55 * topo  # degradê: dos lados a pele aparece
    raiz = suave(0.25, 0.75, ruido(P, 1100.0, 21) * 0.5 + 0.5)
    tinta = np.clip(cabelo * densidade * (0.70 + 0.30 * raiz), 0, 1)
    cor = mistura(cor, srgb("15100e"), tinta * 0.94)

    # ---- olhos: esclera, íris castanha com raios, pupila.
    if OLHO.max() > 0.5:
        for s in (1, -1):
            e = pt["olho"] * [s, 1, 1]
            rel = P - e

            nr = rel / np.maximum(np.linalg.norm(rel, axis=1, keepdims=True), 1e-6)
            olhar = np.array([-0.06 * s, -0.03, 1.0], np.float32)
            olhar /= np.linalg.norm(olhar)
            ang = np.arccos(np.clip(nr @ olhar, -1, 1))
            este = (OLHO > 0.5) & (np.sign(P[:, 0]) == s)
            esclera = mistura(np.tile(srgb("e9e3dc"), (P.shape[0], 1)), srgb("c98f87"), suave(0.5, 1.2, ang) * 0.5)
            raio = np.arctan2(rel[:, 1], rel[:, 0])
            iris_c = mistura(np.tile(srgb("4a2c1a"), (P.shape[0], 1)), srgb("7a5230"),
                             np.clip(ruido(np.stack([raio * 3, ang * 20, raio], 1), 3.0, 4) * 0.5 + 0.5, 0, 1))
            iris = 1 - suave(0.50, 0.56, ang)
            anel_esc = suave(0.40, 0.52, ang) * iris
            pupila = 1 - suave(0.17, 0.21, ang)
            olho_cor = mistura(esclera, iris_c, iris)
            olho_cor *= (1 - 0.5 * anel_esc)[:, None]
            olho_cor = mistura(olho_cor, srgb("060505"), pupila)
            cor[este] = olho_cor[este]

    # ---- boca por dentro e língua, pelo mapa de partes do Anny.
    seg = np.asarray(Image.open(ctx["segmentacao"]).convert("RGB").resize((H, H), Image.NEAREST), np.int16)
    seg = seg.reshape(-1, 3)

    def parte(rgb):
        return np.abs(seg - np.array(rgb, np.int16)).sum(1) < 30

    cavidade = parte((112, 172, 255))
    lingua = parte((206, 153, 167))
    cor[cavidade] = srgb("3b1515") * (0.6 + 0.4 * np.clip(N[cavidade, 2], 0, 1))[:, None]
    cor[lingua] = srgb("9a4a4a") * (1.0 + 0.1 * ruido(P[lingua], 300.0, 60))[:, None]
    del seg

    # ---- poros e micro variação
    poro = ruido(P, 900.0, 30)
    cor *= (1.0 + poro * 0.018)[:, None]
    cor = np.clip(cor, 0, 1)
    albedo = Image.fromarray((cor.reshape(H, H, 3) * 255 + 0.5).astype(np.uint8), "RGB")

    # ---- relevo: poros + fios do cabelo + marca muscular
    altura = (ruido(P, 900.0, 30) * 0.5 + ruido(P, 380.0, 31) * 0.15).reshape(H, H)
    altura += (tinta * ruido(P * [1, 2, 1], 1400.0, 32) * 0.6).reshape(H, H)
    altura = nd.gaussian_filter(altura.astype(np.float32), 0.8)
    gy, gx = np.gradient(altura)
    forca = 0.45
    nx, ny = -gx * forca, gy * forca
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    rel = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5
    relevo = Image.fromarray((rel * 255 + 0.5).astype(np.uint8), "RGB").resize((tam // 2, tam // 2), Image.LANCZOS)
    return albedo, relevo


# ----------------------------------------------------------------- roupa
def _letreiro(texto: str, fonte: str, largura=1400, altura=220):
    img = Image.new("L", (largura, altura), 0)
    dr = ImageDraw.Draw(img)
    tam = 180
    while tam > 20:
        fnt = ImageFont.truetype(fonte, tam)
        caixa = dr.textbbox((0, 0), texto, font=fnt)
        if caixa[2] - caixa[0] < largura * 0.94 and caixa[3] - caixa[1] < altura * 0.8:
            break
        tam -= 4
    caixa = dr.textbbox((0, 0), texto, font=fnt)
    dr.text(((largura - caixa[2] - caixa[0]) / 2, (altura - caixa[3] - caixa[1]) / 2), texto, fill=255, font=fnt)
    return np.asarray(img, np.float32) / 255.0


def pintar_roupa(ctx: dict, tam: int = 2048):
    v, f, uv, fuv, n = ctx["v"], ctx["f"], ctx["uv"], ctx["fuv"], ctx["n"]
    r = ctx["regioes"]
    val = np.concatenate([v, n, r["coxa_t"][:, None], r["canela_t"][:, None],
                          r["calcao"][:, None].astype(np.float32)], 1).astype(np.float32)
    tri = ctx["tri_roupa"]
    img, mask = rasterizar(tam, uv[fuv[tri]], val[f[tri]])
    img = dilatar(img, mask)
    H = img.shape[0]
    P = img[..., 0:3].reshape(-1, 3)
    N = img[..., 3:6].reshape(-1, 3)
    COXA = img[..., 6].reshape(-1)
    CANELA = img[..., 7].reshape(-1)
    CALCAO = img[..., 8].reshape(-1) > 0.5
    del img
    cintura = r["cintura"]

    # ---- calção de cetim vermelho: brilho em faixas de dobra.
    dobra = fbm(P * [2.5, 0.5, 2.5], 18.0, 3, 40)
    verm = np.tile(srgb("b3121f"), (P.shape[0], 1)) * (1.0 + dobra * 0.10)[:, None]
    # cós largo dourado com o nome
    cos = suave(cintura - 0.062, cintura - 0.055, P[:, 1])
    ouro = np.tile(srgb("e0a526"), (P.shape[0], 1)) * (1.0 + fbm(P, 60.0, 2, 41) * 0.08)[:, None]
    roupa = mistura(verm, ouro, cos)
    friso_cos = (1 - suave(0.002, 0.004, np.abs(P[:, 1] - (cintura - 0.058))))
    roupa = mistura(roupa, srgb("f4f1ea"), friso_cos)
    letras = _letreiro("LAZER SPORT", ctx["fonte"])
    lx = (P[:, 0] + 0.15) / 0.30
    ly = 1.0 - (P[:, 1] - (cintura - 0.052)) / 0.050
    dentro = (lx > 0) & (lx < 1) & (ly > 0) & (ly < 1) & (N[:, 2] > 0.25)
    li = np.clip((ly * (letras.shape[0] - 1)).astype(int), 0, letras.shape[0] - 1)
    lj = np.clip((lx * (letras.shape[1] - 1)).astype(int), 0, letras.shape[1] - 1)
    tinta = np.where(dentro, letras[li, lj], 0.0) * cos
    roupa = mistura(roupa, srgb("7a0710"), tinta)
    # barra dourada e friso branco na lateral da perna
    barra = np.zeros_like(COXA)
    lateral = (1 - suave(0.012, 0.018, np.abs(N[:, 2]))) * (np.abs(N[:, 0]) > 0.5) * (P[:, 1] < cintura - 0.06)
    roupa = mistura(roupa, srgb("f4f1ea"), lateral * (1 - barra))

    # ---- botas pretas de couro, sola branca, cadarço branco.
    couro = np.tile(srgb("141417"), (P.shape[0], 1)) * (1.0 + fbm(P, 120.0, 3, 50) * 0.18)[:, None]
    sola = 1 - suave(0.009, 0.013, P[:, 1])
    bota = mistura(couro, srgb("d9d5cc"), sola)
    topo = (1 - suave(0.004, 0.008, np.abs(CANELA - 0.765))) * (CANELA > 0.5)
    bota = mistura(bota, srgb("e0a526"), topo)
    # cadarço: xis na frente do peito do pé e da canela
    frente = suave(0.35, 0.6, N[:, 2]) * (P[:, 1] > 0.04) * (P[:, 1] < 0.22)
    lado_pe = np.where(P[:, 0] > 0, 1.0, -1.0)
    centro_x = lado_pe * ctx["pe_x"]
    u = (P[:, 0] - centro_x) / 0.018
    fase = (P[:, 1] / 0.016)
    cruz = np.minimum(np.abs(((fase + u * 0.5) % 1.0) - 0.5), np.abs(((fase - u * 0.5) % 1.0) - 0.5))
    cadarco = (1 - suave(0.08, 0.14, cruz)) * (np.abs(u) < 1.0) * frente
    bota = mistura(bota, srgb("ecebe6"), cadarco)
    final = np.where(CALCAO[:, None], roupa, bota)
    final = np.clip(final, 0, 1)
    return Image.fromarray((final.reshape(H, H, 3) * 255 + 0.5).astype(np.uint8), "RGB")
