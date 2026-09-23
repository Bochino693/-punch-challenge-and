"""Gera as texturas das particulas 2D (assets/fx/*.png).

    python3 tools/gerar_fx.py

Todas brancas (a cor vem da particula), com borda antisserrilhada e em
resolucao folgada: a particula e sempre REDUZIDA na tela, nunca ampliada,
por isso nao ha pixel quadrado nem contorno serrilhado.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage as nd

SAIDA = Path(__file__).resolve().parents[1] / "assets" / "fx"
SUPER = 4  # desenha em 4x e reduz: borda lisa de graca


def salvar(a: np.ndarray, nome: str, rgb: np.ndarray | None = None) -> None:
    a = np.clip(a, 0, 1)
    if rgb is None:
        rgb = np.ones(a.shape + (3,), np.float32)
    img = np.dstack([np.clip(rgb, 0, 1), a])
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA").save(SAIDA / nome, optimize=True)
    print("ok", nome, a.shape[1], "x", a.shape[0])


def grade(w, h):
    yy, xx = np.mgrid[:h, :w].astype(np.float32)
    return (xx + 0.5) / w * 2 - 1, (yy + 0.5) / h * 2 - 1


def mascara(w, h, desenho) -> np.ndarray:
    im = Image.new("L", (w * SUPER, h * SUPER), 0)
    desenho(ImageDraw.Draw(im), SUPER)
    return np.asarray(im.resize((w, h), Image.LANCZOS), np.float32) / 255.0


def brilho():
    x, y = grade(64, 64)
    r = np.sqrt(x * x + y * y)
    salvar(np.exp(-(r / 0.22) ** 2) + np.exp(-(r / 0.55) ** 2) * 0.35, "brilho.png")


def faisca():
    # Risco vertical (a particula alinha o eixo Y com a velocidade):
    # cabeca branca e cauda que some.
    x, y = grade(24, 96)
    corpo = np.exp(-(x / 0.28) ** 2) * np.clip(1 - np.abs(y), 0, 1) ** 0.7
    cabeca = np.exp(-((x / 0.45) ** 2 + ((y + 0.55) / 0.18) ** 2))
    salvar(np.clip(corpo * (0.35 + 0.65 * (1 - (y + 1) / 2)) + cabeca, 0, 1), "faisca.png")


def confete():
    # Oito quadros de um papel girando no ar: a largura acompanha o
    # cosseno do giro e o tom escurece quando ele fica de lado.
    W, H, N = 40, 56, 8
    folha_a = np.zeros((H, W * N), np.float32)
    folha_rgb = np.ones((H, W * N, 3), np.float32)
    for i in range(N):
        ang = i / N * np.pi
        larg = max(0.10, abs(np.cos(ang)))
        tom = 0.62 + 0.38 * abs(np.cos(ang))
        def desenho(d, s, larg=larg):
            cx, cy = W * s / 2, H * s / 2
            meia_l, meia_a = W * s * 0.40 * larg, H * s * 0.40
            d.rounded_rectangle([cx - meia_l, cy - meia_a, cx + meia_l, cy + meia_a], radius=max(2, 3 * s * larg), fill=255)
        m = mascara(W, H, desenho)
        folha_a[:, i * W:(i + 1) * W] = m
        # Um brilho na dobra: o papel parece ter corpo.
        yy = np.linspace(-1, 1, H)[:, None]
        folha_rgb[:, i * W:(i + 1) * W] = (tom * (0.92 + 0.08 * yy))[..., None]
    salvar(folha_a, "confete.png", folha_rgb)


def raio():
    molde = [(0.10, -1.00), (-0.55, 0.10), (-0.10, 0.10), (-0.20, 1.00), (0.55, -0.15), (0.08, -0.15)]
    N = 96
    def desenho(d, s):
        pts = [((px * 0.46 + 0.5) * N * s, (py * 0.46 + 0.5) * N * s) for px, py in molde]
        d.polygon(pts, fill=255)
    m = mascara(N, N, desenho)
    halo = nd.gaussian_filter(m, 4) * 0.8
    rgb = np.ones((N, N, 3), np.float32)
    rgb[..., 2] = 0.75 + 0.25 * m  # halo levemente quente
    salvar(np.clip(m + halo, 0, 1), "raio.png", rgb)


def estilhaco():
    N = 64
    def desenho(d, s):
        d.polygon([(N * s * 0.5, N * s * 0.08), (N * s * 0.92, N * s * 0.70), (N * s * 0.12, N * s * 0.92)], fill=255)
    m = mascara(N, N, desenho)
    x, y = grade(N, N)
    tom = np.clip(0.75 + 0.35 * (-x * 0.6 - y * 0.8), 0.45, 1.0)
    salvar(m, "estilhaco.png", np.dstack([tom, tom, tom]))


def fumaca():
    N = 128
    rng = np.random.default_rng(7)
    x, y = grade(N, N)
    r = np.sqrt(x * x + y * y)
    ruido = nd.gaussian_filter(rng.normal(0, 1, (N, N)), 7)
    ruido = (ruido - ruido.min()) / (ruido.max() - ruido.min())
    a = np.clip(1 - r, 0, 1) ** 1.6 * (0.55 + 0.45 * ruido)
    salvar(a, "fumaca.png")


if __name__ == "__main__":
    SAIDA.mkdir(parents=True, exist_ok=True)
    brilho()
    faisca()
    confete()
    raio()
    estilhaco()
    fumaca()

