"""Gera a imagem de abertura (boot splash) JÁ GIRADA para a TV Box.

    python3 tools/gerar_abertura.py

O Android da TV Box fica em paisagem (1920x1080) e o jogo gira o quadro
vertical por dentro. A abertura aparece ANTES de o jogo existir, então
ninguém a gira: por isso ela é desenhada em pé (1080x1920) e salva
girada 90° — o topo do selo fica na esquerda do HDMI, igual ao jogo, e
no monitor vertical ele aparece em pé desde o primeiro instante.

Selo, tamanho e posição são os mesmos de `scripts/carregador.gd`, para a
troca da abertura para a tela de carregamento não ter emenda.
"""
from pathlib import Path

from PIL import Image

RAIZ = Path(__file__).resolve().parents[1]
FUNDO = (0x19, 0x06, 0x0D, 255)
SELO_CENTRO = (540, 900)
SELO_TAMANHO = 560

selo = Image.open(RAIZ / "assets/branding/selo_lazer.png").convert("RGBA")
selo = selo.resize((SELO_TAMANHO, SELO_TAMANHO), Image.LANCZOS)
retrato = Image.new("RGBA", (1080, 1920), FUNDO)
retrato.alpha_composite(selo, (SELO_CENTRO[0] - SELO_TAMANHO // 2, SELO_CENTRO[1] - SELO_TAMANHO // 2))
# rotate(90) é anti-horário: o topo do retrato vai para a esquerda.
retrato.rotate(90, expand=True).convert("RGB").save(RAIZ / "assets/branding/abertura_tvbox.png", optimize=True)
print("ok assets/branding/abertura_tvbox.png")
