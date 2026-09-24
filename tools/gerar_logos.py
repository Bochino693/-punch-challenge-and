"""Gera as logos em todos os tamanhos usados na tela (sem pixel quebrado).

    python tools/gerar_logos.py

Reduzir uma imagem de 1280 px para 66 px NA HORA, na placa de vídeo,
quebra os traços finos. Aqui cada tamanho sai pronto, reduzido em etapas
com filtro Lanczos e um leve reforço de nitidez; o jogo escolhe sempre a
versão do tamanho certo (`scripts/logos.gd`).

Saídas: assets/logos/<nome>_h<altura>.png
"""
from pathlib import Path
from PIL import Image, ImageFilter

RAIZ = Path(__file__).resolve().parents[1]
SAIDA = RAIZ / "assets" / "logos"
FONTES = {
    "lazersport": RAIZ / "assets" / "logo_lazersport.png",
    "superboxing": RAIZ / "assets" / "tema" / "logo.png",
}
ALTURAS = [48, 64, 80, 96, 128, 160, 200, 256, 320, 400, 512]


def reduzir(img: Image.Image, altura: int) -> Image.Image:
    largura = max(1, round(img.width * altura / img.height))
    atual = img
    # Em etapas de no máximo 2x: cada passo guarda os traços finos.
    while atual.height > altura * 2:
        atual = atual.resize((max(1, atual.width // 2), max(1, atual.height // 2)), Image.LANCZOS)
    atual = atual.resize((largura, altura), Image.LANCZOS)
    # Alfa pré-multiplicado para o reforço de nitidez não sujar as bordas.
    rgb = atual.convert("RGBa").filter(ImageFilter.UnsharpMask(radius=0.8, percent=60, threshold=1))
    return rgb.convert("RGBA")


def main() -> None:
    SAIDA.mkdir(parents=True, exist_ok=True)
    for nome, fonte in FONTES.items():
        img = Image.open(fonte).convert("RGBA")
        img = img.crop(img.getbbox())
        for h in ALTURAS:
            if h > img.height:
                continue
            reduzir(img, h).save(SAIDA / f"{nome}_h{h}.png", optimize=True)
        print("ok", nome, img.size)


if __name__ == "__main__":
    main()
