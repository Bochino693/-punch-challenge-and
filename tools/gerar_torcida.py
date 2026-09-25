"""Gera a torcida da arena: sons longos e a plateia em silhueta.

    python tools/gerar_torcida.py

Saídas:
  assets/audio/arcade/torcida_vaia.wav   vaia longa ("uuuuh") + apitos, sintetizada
  assets/audio/arcade/torcida_festa.wav  festa longa, emendando as gravações CC0
                                          que já estão no projeto
  assets/audio/arcade/torcida_incentivo.wav  a torcida EMPURRANDO no meio da luta:
                                          palmas ritmadas, "VAI! VAI!" em coro e
                                          a plateia gravada por baixo
  assets/arena/torcida_baixo.png         plateia de braços baixos
  assets/arena/torcida_cima.png          a MESMA plateia, braços para o alto

Requer: numpy, scipy, pillow.
"""
from pathlib import Path
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import signal

RAIZ = Path(__file__).resolve().parents[1]
AUDIO = RAIZ / "assets" / "audio" / "arcade"
ARENA = RAIZ / "assets" / "arena"
SR = 44100
rng = np.random.default_rng(20260924)


def ler(nome):
    with wave.open(str(AUDIO / nome)) as w:
        dados = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
        return dados.reshape(-1, w.getnchannels())


def gravar(nome, x):
    x = x / max(1e-6, np.abs(x).max()) * 0.84
    with wave.open(str(AUDIO / nome), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    print("ok", nome, round(len(x) / SR, 2), "s")


def reverb(x, segundos=1.3, mistura=0.28):
    n = int(SR * segundos)
    t = np.arange(n) / SR
    ir = rng.standard_normal((n, 2)) * np.exp(-t * 5.0)[:, None]
    ir[0] = 1.0
    out = np.stack([signal.fftconvolve(x[:, c], ir[:, c])[: len(x)] for c in range(2)], 1)
    out /= np.abs(out).max() + 1e-9
    return x * (1 - mistura) + out * mistura * np.abs(x).max()


def formante(x, f, largura):
    b, a = signal.iirpeak(f, f / largura, SR)
    return signal.lfilter(b, a, x)


def vaia(duracao=8.0):
    n = int(SR * duracao)
    t = np.arange(n) / SR
    mix = np.zeros((n, 2))
    for _ in range(70):
        f0 = rng.uniform(92, 175) if rng.random() < 0.8 else rng.uniform(170, 260)
        vib = 1 + 0.012 * np.sin(2 * np.pi * rng.uniform(4, 6.5) * t + rng.uniform(0, 6))
        queda = 1 - 0.10 * np.clip((t - rng.uniform(1, 5)) / 3, 0, 1)
        fase = np.cumsum(f0 * vib * queda) / SR
        voz = 2 * (fase % 1) - 1  # dente de serra: a glote
        voz = formante(voz, rng.uniform(300, 360), 5) * 1.0 + formante(voz, rng.uniform(760, 880), 7) * 0.45 \
            + formante(voz, 2300, 10) * 0.06
        inicio = rng.uniform(0.0, 1.2)
        env = np.clip((t - inicio) / rng.uniform(0.25, 0.7), 0, 1)
        # respiração: a vaia vem em ondas ("uuuh... uuuuh")
        periodo = rng.uniform(1.6, 3.2)
        onda = 0.55 + 0.45 * np.clip(np.sin(2 * np.pi * (t - inicio) / periodo + rng.uniform(0, 1)) * 1.6, -1, 1)
        fim = np.clip((duracao - t) / 1.4, 0, 1)
        voz = voz * env * onda * fim * rng.uniform(0.4, 1.0)
        pan = rng.uniform(0.15, 0.85)
        mix[:, 0] += voz * (1 - pan)
        mix[:, 1] += voz * pan
    # apitos de torcida, poucos
    for _ in range(5):
        ini = rng.uniform(0.8, duracao - 2)
        dur = rng.uniform(0.35, 0.9)
        tt = np.clip(t - ini, 0, None)
        f = rng.uniform(2300, 3300) * (1 - 0.08 * tt / dur)
        ap = np.sin(2 * np.pi * np.cumsum(f) / SR) * ((t > ini) & (t < ini + dur)) * np.exp(-tt * 1.5)
        pan = rng.uniform(0.2, 0.8)
        mix[:, 0] += ap * 0.05 * (1 - pan)
        mix[:, 1] += ap * 0.05 * pan
    # cama de gente falando (ruído grave)
    cama = signal.lfilter(*signal.butter(2, [120, 900], "bandpass", fs=SR), rng.standard_normal((n, 2)), axis=0)
    mix += cama * 0.25 * np.clip(t / 0.6, 0, 1)[:, None] * np.clip((duracao - t) / 1.4, 0, 1)[:, None]
    return reverb(mix)


def festa():
    partes = [ler("torcida_recorde.wav"), ler("torcida_podio.wav"), ler("arena_publico.wav")]
    cruza = int(SR * 0.9)
    out = partes[0]
    for p in partes[1:]:
        rampa = np.linspace(0, 1, cruza)[:, None]
        meio = out[-cruza:] * (1 - rampa) + p[:cruza] * rampa
        out = np.concatenate([out[:-cruza], meio, p[cruza:]])
    n = len(out)
    t = np.arange(n) / SR
    # palmas ritmadas por baixo (a torcida "pegando fogo")
    palmas = np.zeros(n)
    batida = 60 / 128
    k = 0.6
    while k < t[-1] - 0.5:
        i = int(k * SR)
        m = min(n - i, int(0.06 * SR))
        palmas[i:i + m] += rng.standard_normal(m) * np.exp(-np.arange(m) / (0.012 * SR))
        k += batida
    palmas = signal.lfilter(*signal.butter(2, [900, 5000], "bandpass", fs=SR), palmas)
    out = out + np.stack([palmas, palmas], 1) * 0.18
    fim = np.clip((t[-1] - t) / 1.2, 0, 1)[:, None]
    return out * fim


def incentivo(duracao=4.2):
    """O coro que empurra quem está batendo: "VAI! VAI! VAI!" com palmas.

    Nada de vaia aqui — vaia é só do fim, de quem perdeu. No meio da luta
    a torcida está do lado do jogador."""
    n = int(SR * duracao)
    t = np.arange(n) / SR
    mix = np.zeros((n, 2))
    batida = 60 / 150
    inicios = np.arange(0.18, duracao - 0.6, batida * 2)
    for _ in range(46):
        f0 = rng.uniform(130, 230) if rng.random() < 0.7 else rng.uniform(210, 330)
        atraso = rng.normal(0, 0.025)
        voz = np.zeros(n)
        for k, ini in enumerate(inicios):
            ini += atraso
            dur = batida * rng.uniform(0.62, 0.8)
            m = (t >= ini) & (t < ini + dur)
            tt = np.clip(t - ini, 0, None)
            # "vai": do /a/ para o /i/, com o tom subindo no fim do grito
            fase = np.cumsum(f0 * (1 + 0.10 * np.clip(tt / dur, 0, 1))) / SR
            glote = 2 * (fase % 1) - 1
            env = np.clip(tt / 0.035, 0, 1) * np.clip((ini + dur - t) / 0.08, 0, 1) * m
            voz += glote * env
        # formantes: /a/ (730, 1090) indo para /i/ (300, 2300) — mistura fixa
        # das duas bocas; o ouvido lê o ditongo na média de 46 vozes
        voz = formante(voz, rng.uniform(640, 760), 5) + formante(voz, rng.uniform(1050, 1250), 7) * 0.5 \
            + formante(voz, rng.uniform(2100, 2500), 10) * 0.18
        pan = rng.uniform(0.1, 0.9)
        g = rng.uniform(0.4, 1.0)
        mix[:, 0] += voz * g * (1 - pan)
        mix[:, 1] += voz * g * pan
    # palmas no contratempo do coro
    palmas = np.zeros((n, 2))
    k = 0.18 + batida
    while k < duracao - 0.4:
        for _ in range(18):
            i = int((k + rng.normal(0, 0.012)) * SR)
            m = min(n - i, int(0.05 * SR))
            if m <= 0:
                continue
            pan = rng.uniform(0, 1)
            c = rng.standard_normal(m) * np.exp(-np.arange(m) / (0.009 * SR)) * rng.uniform(0.5, 1)
            palmas[i:i + m, 0] += c * (1 - pan)
            palmas[i:i + m, 1] += c * pan
        k += batida
    palmas = signal.lfilter(*signal.butter(2, [800, 6000], "bandpass", fs=SR), palmas, axis=0)
    mix = mix / (np.abs(mix).max() + 1e-9) + palmas / (np.abs(palmas).max() + 1e-9) * 0.55
    publico = ler("arena_publico.wav")
    cama = np.zeros((n, 2))
    m = min(n, len(publico))
    cama[:m] = publico[:m]
    mix = mix + cama * 0.5
    fim = np.clip((duracao - t) / 0.7, 0, 1)[:, None] * np.clip(t / 0.08, 0, 1)[:, None]
    return reverb(mix * fim, 1.1, 0.24)


# ------------------------------------------------------------ plateia
## AS FILEIRAS DA PLATEIA: (colunas, faixa em pixels, cor base).
## CADA PESSOA MORA INTEIRA DENTRO DA SUA COLUNA, e cada fileira numa
## faixa própria da imagem. O shader da arena faz cada coluna pular no seu
## ritmo — com gente espalhada ao acaso (antes), a coluna cortava a pessoa
## ao meio e metade do corpo pulava separada da outra: a torcida saía
## torta e "distorcida". Agora a coluna É a pessoa.
FILEIRAS = [
    (52, (0, 150), (24, 17, 34)),     # fundo: pequena e mais clara
    (40, (150, 320), (17, 12, 25)),   # meio
    (30, (320, 512), (11, 8, 16)),    # frente: grande e escura
]
CAMISAS = [(70, 18, 30), (22, 30, 78), (60, 20, 70), (18, 52, 60), (72, 50, 14), (40, 40, 48)]


def plateia():
    L, A = 2048, 512
    baixo = Image.new("RGBA", (L, A), (0, 0, 0, 0))
    cima = Image.new("RGBA", (L, A), (0, 0, 0, 0))
    db, dc = ImageDraw.Draw(baixo), ImageDraw.Draw(cima)
    for colunas, (y0, y1), cor in FILEIRAS:
        larg_col = L / colunas
        w = larg_col * 0.84 / 1.30
        ombro = y0 + 1.68 * w
        for c in range(colunas):
            x = (c + 0.5) * larg_col
            y = ombro + rng.uniform(-2.0, 2.0)
            ww = w * rng.uniform(0.92, 1.0)
            cabeca = ww * 0.36
            camisa = np.array(CAMISAS[rng.integers(len(CAMISAS))]) * rng.uniform(0.35, 0.6)
            tronco = tuple(int(v) for v in (np.array(cor) * 0.55 + camisa * 0.45)) + (255,)
            pele = cor + (255,)
            abre = rng.uniform(0.04, 0.16)  # o MESMO para os dois braços: simétrico
            for d, bracos in ((db, False), (dc, True)):
                d.ellipse([x - cabeca, y - ww * 1.05 - cabeca, x + cabeca, y - ww * 1.05 + cabeca], fill=pele)
                # ombros largos afinando para a cintura (um tronco, não um frasco)
                d.polygon([(x - ww * 0.65, y - ww * 0.55), (x + ww * 0.65, y - ww * 0.55),
                           (x + ww * 0.50, y1 - 1), (x - ww * 0.50, y1 - 1)], fill=tronco)
                d.ellipse([x - ww * 0.65, y - ww * 0.78, x - ww * 0.25, y - ww * 0.35], fill=tronco)
                d.ellipse([x + ww * 0.25, y - ww * 0.78, x + ww * 0.65, y - ww * 0.35], fill=tronco)
                d.rectangle([x - ww * 0.22, y - ww * 0.80, x + ww * 0.22, y - ww * 0.55], fill=pele)
                if bracos:
                    for lado in (-1, 1):
                        ox, oy = x + lado * ww * 0.50, y - ww * 0.60
                        mx, my = ox + lado * ww * abre, oy - ww * 0.95
                        d.line([ox, oy, mx, my], fill=tronco, width=max(2, int(ww * 0.24)))
                        d.ellipse([mx - ww * 0.14, my - ww * 0.14, mx + ww * 0.14, my + ww * 0.14], fill=pele)
    # luz de contorno: magenta de um lado, ciano do outro, e o alto das cabeças
    for img in (baixo, cima):
        a = np.asarray(img).astype(np.float32)
        alfa = a[..., 3] / 255
        borda_e = np.clip(alfa - np.roll(alfa, 3, axis=1), 0, 1)
        borda_d = np.clip(alfa - np.roll(alfa, -3, axis=1), 0, 1)
        borda_c = np.clip(alfa - np.roll(alfa, 3, axis=0), 0, 1)
        a[..., 0] += borda_e * 170 + borda_c * 60
        a[..., 1] += borda_c * 45
        a[..., 2] += borda_d * 190 + borda_c * 70
        a[..., :3] = np.clip(a[..., :3], 0, 255)
        img.paste(Image.fromarray(a.astype(np.uint8), "RGBA"))
    baixo = baixo.filter(ImageFilter.GaussianBlur(1.2))
    cima = cima.filter(ImageFilter.GaussianBlur(1.2))
    baixo.save(ARENA / "torcida_baixo.png", optimize=True)
    cima.save(ARENA / "torcida_cima.png", optimize=True)
    print("ok plateia", L, "x", A)


def so_plateia():
    plateia()


if __name__ == "__main__":
    import sys
    if "--so-plateia" in sys.argv:
        plateia()
        raise SystemExit
    gravar("torcida_vaia.wav", vaia())
    gravar("torcida_festa.wav", festa())
    gravar("torcida_incentivo.wav", incentivo())
    plateia()
