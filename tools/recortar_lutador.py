"""Recorta a folha 3x3 do lutador em nove poses inteiras e nitidas.

    python3 tools/recortar_lutador.py FOLHA_3x3.png [pesos_anime6B.pth]

O que faz, e por que:
  * separa cada pose pelo DESENHO (componente conexo do alfa), e nao pela
    grade: na folha original os pes passavam 6 px da celula e eram cortados;
  * aperta o halo translucido que sobrou do fundo removido e puxa a cor
    das bordas para a do interior (sem franja vermelha/rosa);
  * amplia 1,5x com Real-ESRGAN anime 6B quando os pesos sao passados
    (sem eles, Lanczos);
  * grava pose_<nome>.png, todas do mesmo tamanho e com o ponto mais baixo
    do desenho na mesma linha -- e isso que scripts/arena/lutador.gd espera.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as nd

NOMES = ["guarda", "idle", "preparado", "jab", "direto", "impacto_corpo",
         "impacto_forte", "nocaute", "recuperacao"]
CEL = (410, 426)
ESCALA = 1.5
PAD, PADX, MARGEM_BASE, MARGEM_TOPO = 10, 40, 8, 6
SAIDA = Path(__file__).resolve().parents[1] / "assets" / "personagem" / "sprites"


def ampliador(pesos):
    if not pesos:
        return None
    import torch
    import torch.nn as nn
    import torch.nn.functional as F

    class RDB(nn.Module):
        def __init__(s, nf=64, gc=32):
            super().__init__()
            s.conv1 = nn.Conv2d(nf, gc, 3, 1, 1); s.conv2 = nn.Conv2d(nf + gc, gc, 3, 1, 1)
            s.conv3 = nn.Conv2d(nf + 2 * gc, gc, 3, 1, 1); s.conv4 = nn.Conv2d(nf + 3 * gc, gc, 3, 1, 1)
            s.conv5 = nn.Conv2d(nf + 4 * gc, nf, 3, 1, 1); s.l = nn.LeakyReLU(0.2, True)

        def forward(s, x):
            x1 = s.l(s.conv1(x)); x2 = s.l(s.conv2(torch.cat((x, x1), 1)))
            x3 = s.l(s.conv3(torch.cat((x, x1, x2), 1))); x4 = s.l(s.conv4(torch.cat((x, x1, x2, x3), 1)))
            return s.conv5(torch.cat((x, x1, x2, x3, x4), 1)) * 0.2 + x

    class RRDB(nn.Module):
        def __init__(s, nf):
            super().__init__(); s.rdb1 = RDB(nf); s.rdb2 = RDB(nf); s.rdb3 = RDB(nf)

        def forward(s, x):
            return s.rdb3(s.rdb2(s.rdb1(x))) * 0.2 + x

    class RRDBNet(nn.Module):
        def __init__(s, nb=6, nf=64):
            super().__init__()
            s.conv_first = nn.Conv2d(3, nf, 3, 1, 1); s.body = nn.Sequential(*[RRDB(nf) for _ in range(nb)])
            s.conv_body = nn.Conv2d(nf, nf, 3, 1, 1); s.conv_up1 = nn.Conv2d(nf, nf, 3, 1, 1)
            s.conv_up2 = nn.Conv2d(nf, nf, 3, 1, 1); s.conv_hr = nn.Conv2d(nf, nf, 3, 1, 1)
            s.conv_last = nn.Conv2d(nf, 3, 3, 1, 1); s.l = nn.LeakyReLU(0.2, True)

        def forward(s, x):
            f = s.conv_first(x); f = f + s.conv_body(s.body(f))
            f = s.l(s.conv_up1(F.interpolate(f, scale_factor=2, mode="nearest")))
            f = s.l(s.conv_up2(F.interpolate(f, scale_factor=2, mode="nearest")))
            return s.conv_last(s.l(s.conv_hr(f)))

    m = RRDBNet()
    sd = torch.load(pesos, map_location="cpu")
    m.load_state_dict(sd.get("params_ema", sd.get("params", sd)))
    m.eval()

    def up(img3):
        with torch.no_grad():
            o = m(torch.from_numpy(img3.transpose(2, 0, 1)).unsqueeze(0)).clamp(0, 1)
        return o[0].numpy().transpose(1, 2, 0)
    return up


def main():
    a = np.array(Image.open(sys.argv[1]).convert("RGBA")).astype(np.float32)
    up = ampliador(sys.argv[2] if len(sys.argv) > 2 else "")
    A = a[..., 3] / 255.0
    lab, n = nd.label(nd.binary_closing(A > 40 / 255, iterations=3))
    tamanhos = nd.sum(A > 0.15, lab, range(1, n + 1))
    comps = []
    for i, s in enumerate(tamanhos):
        if s > 3000:
            ys, xs = np.nonzero(lab == i + 1)
            comps.append((int(ys.mean() // CEL[1]), int(xs.mean() // CEL[0]), i + 1))
    comps.sort()
    poses = {}
    for r, c, cid in comps:
        reg = nd.binary_dilation(lab == cid, iterations=6) & (A > 0)
        ys, xs = np.nonzero(reg)
        y0, y1 = max(ys.min() - PAD, 0), ys.max() + 1 + PAD
        x0, x1 = max(xs.min() - PAD, 0), xs.max() + 1 + PAD
        sub = a[y0:y1, x0:x1]
        al = np.where(reg[y0:y1, x0:x1], sub[..., 3] / 255.0, 0.0)
        t = np.clip((al - 0.10) / 0.70, 0, 1)
        al2 = t * t * (3 - 2 * t)
        rgb = sub[..., :3] / 255.0
        idx = nd.distance_transform_edt(~(al > 0.92), return_distances=False, return_indices=True)
        w = np.clip((al - 0.35) / 0.57, 0, 1)[..., None]
        rgb2 = (rgb * w + rgb[idx[0], idx[1]] * (1 - w)).astype(np.float32)
        h, wd = sub.shape[:2]
        H, W = int(round(h * ESCALA)), int(round(wd * ESCALA))
        if up:
            R = Image.fromarray((up(rgb2) * 255 + 0.5).astype(np.uint8))
            Al = Image.fromarray((np.clip(up(np.repeat(al2[..., None], 3, 2).astype(np.float32)).mean(2), 0, 1) * 255 + 0.5).astype(np.uint8))
        else:
            R = Image.fromarray((rgb2 * 255 + 0.5).astype(np.uint8))
            Al = Image.fromarray((al2 * 255 + 0.5).astype(np.uint8))
        im = R.resize((W, H), Image.LANCZOS).convert("RGBA")
        im.putalpha(Al.resize((W, H), Image.LANCZOS))
        poses[NOMES[r * 3 + c]] = (im, (x0 - c * CEL[0]) * ESCALA)

    fundo = {}
    for k, (im, _) in poses.items():
        ys = np.nonzero((np.array(im)[..., 3] > 24).any(1))[0]
        fundo[k] = (ys.min(), ys.max())
    celw = int(CEL[0] * ESCALA) + 2 * PADX
    celh = max(b - t for t, b in fundo.values()) + MARGEM_BASE + MARGEM_TOPO + 1
    base = celh - MARGEM_BASE - 1
    for k, (im, xo) in poses.items():
        cel = Image.new("RGBA", (celw, celh), (0, 0, 0, 0))
        cel.alpha_composite(im, (int(round(xo + PADX)), base - fundo[k][1]))
        cel.save(SAIDA / ("pose_%s.png" % k), optimize=True)
    print("quadro", celw, "x", celh, "linha do chao", base + 1)


if __name__ == "__main__":
    main()
