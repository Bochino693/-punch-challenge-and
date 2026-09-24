"""Gera os mapas da PELE do boxeador (rode depois do gerar_boxeador.py).

  assets/lutador3d/pele_relevo.png  normal map 2048: o relevo original do
      modelo SOMADO ao relevo dos músculos, tirado da própria pintura do
      corpo (peito, abdome, ombros e braços já vêm sombreados na textura;
      aqui essa sombra vira volume de verdade, que pega a luz da arena).
  assets/lutador3d/pele_poros.png   normal map 512 que se repete: poros e
      micro-relevo. De perto a pele deixa de ser plástico liso; de longe
      quebra o brilho do suor em pontinhos, como pele de verdade.

Uso:  python tools/gerar_pele.py
"""
import os
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

RAIZ = os.path.join(os.path.dirname(__file__), "..")
PASTA = os.path.join(RAIZ, "assets", "lutador3d")
PINTURA = os.path.join(PASTA, "boxeador_1.jpg")
RELEVO_ORIGINAL = os.path.join(PASTA, "boxeador_2.png")

# Força do relevo dos músculos (derivada da luminância da pintura).
FORCA_MUSCULO = 4.0
FORCA_DETALHE = 0.0
TAM = 2048


def normal_de_altura(h, forca, periodico=False):
    if periodico:
        dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
        dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    else:
        dy, dx = np.gradient(h)
    # Convenção OpenGL (a do glTF e a do Godot): verde aponta para +V, e a
    # linha da imagem cresce para baixo.
    n = np.dstack([-dx * forca, dy * forca, np.ones_like(h)])
    return n / np.linalg.norm(n, axis=2, keepdims=True)


def para_png(n):
    return Image.fromarray(np.clip((n * 0.5 + 0.5) * 255.0 + 0.5, 0, 255).astype(np.uint8))


def de_png(im):
    a = np.asarray(im.convert("RGB"), dtype=np.float32) / 255.0 * 2.0 - 1.0
    return a / np.maximum(np.linalg.norm(a, axis=2, keepdims=True), 1e-6)


def relevo():
    pintura = np.asarray(Image.open(PINTURA).convert("RGB").resize((TAM, TAM), Image.LANCZOS), dtype=np.float32) / 255.0
    lum = pintura @ np.array([0.30, 0.55, 0.15], dtype=np.float32)
    # Cabelo, sobrancelha, cílios e mamilos são ESCUROS na pintura, mas não
    # são buracos: sem isto viravam sulcos fundos e as bordas deles
    # brilhavam (sobrancelha branca). O escuro é preenchido com a pele em
    # volta antes de medir o relevo.
    pele = (lum > 0.30).astype(np.float32)
    cheio = gaussian_filter(lum * pele, 6.0) / np.maximum(gaussian_filter(pele, 6.0), 1e-3)
    lum = np.where(pele > 0.5, lum, cheio)
    # Faixa dos músculos: tira o fino (poros da pintura, ruído do jpg) e o
    # muito largo (a cor geral de cada região), fica o volume.
    musculo = gaussian_filter(lum, 9.0) - gaussian_filter(lum, 56.0)
    detalhe = gaussian_filter(lum, 1.2) - gaussian_filter(lum, 6.0)
    # Pele escura na pintura = reentrância (vão entre músculos).
    altura = musculo * FORCA_MUSCULO + detalhe * FORCA_DETALHE
    n_det = normal_de_altura(altura, 60.0)
    base = de_png(Image.open(RELEVO_ORIGINAL).resize((TAM, TAM), Image.BICUBIC))
    # Mistura "reorientada" simplificada: soma as inclinações.
    n = np.dstack([base[..., 0] + n_det[..., 0], base[..., 1] + n_det[..., 1], base[..., 2] * n_det[..., 2]])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    para_png(n).save(os.path.join(PASTA, "pele_relevo.png"))


def poros():
    rng = np.random.default_rng(7)
    lado = 512
    ruido = rng.standard_normal((lado, lado)).astype(np.float32)
    # Filtro no espaço da frequência: repete sem emenda nas bordas.
    f = np.fft.fft2(ruido)
    ky = np.fft.fftfreq(lado)[:, None]
    kx = np.fft.fftfreq(lado)[None, :]
    k = np.sqrt(kx * kx + ky * ky)
    faixa = np.exp(-((k - 0.09) ** 2) / (2 * 0.035 ** 2)) + 0.35 * np.exp(-((k - 0.025) ** 2) / (2 * 0.012 ** 2))
    h = np.real(np.fft.ifft2(f * faixa))
    h = (h - h.mean()) / (h.std() + 1e-6)
    # Poros são buracos pequenos: puxa os vales, achata os picos.
    h = np.where(h < 0, h * 1.6, h * 0.5)
    para_png(normal_de_altura(h, 0.55, periodico=True)).save(os.path.join(PASTA, "pele_poros.png"))


if __name__ == "__main__":
    relevo()
    poros()
    print("pele_relevo.png e pele_poros.png gerados em", PASTA)
