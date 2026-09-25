"""Gera o lutador 3D do jogo: assets/lutador3d/boxeador.glb

    python tools/gerar_boxeador.py

O corpo vem do Anny (NAVER, Apache 2.0), que por sua vez é o corpo do
MakeHuman (CC0): um homem adulto, peso-médio musculoso, com as proporções
de atleta. Por cima dele este script faz, sem nenhum arquivo externo:

  * um esqueleto compacto no padrão Mixamo (Hips, Spine, LeftArm...),
    fundindo os 163 ossos do MakeHuman nos 23 que o jogo anima;
  * o calção de cetim e as botas de cano alto como MALHAS próprias
    (casca do corpo alisada e afastada da pele, com a mesma pele de ossos:
    dobram junto com as pernas, não são pintura);
  * as luvas esculpidas (bulbo do punho, polegar e punho de amarrar) por
    campo de distância e marching cubes;
  * as texturas em alta: pele 4096 px pintada texel a texel a partir da
    posição 3D de cada ponto do corpo (tom, poros, veias do antebraço,
    cabelo degradê, barba por fazer, sobrancelha, lábio, olhos) e um mapa
    de relevo de poros; roupa 2048 px (cetim, cós com a marca, frisos).

Requer: pip install anny scikit-image scipy pillow numpy
(o Anny puxa o torch; a primeira execução leva alguns minutos para montar
o cache do MakeHuman).
"""
from __future__ import annotations

import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as nd

RAIZ = Path(__file__).resolve().parents[1]
SAIDA = RAIZ / "assets" / "lutador3d" / "boxeador.glb"
FONTE = str(RAIZ / "assets" / "fonts" / "Bungee-Regular.ttf")
CACHE = Path(__file__).resolve().parent / ".cache_boxeador.npz"

# TV BOX PRIMEIRO: pele em 2048 (o lutador ocupa ~500 px de altura na
# tela; 4096 só custava memória de vídeo e tempo de carregamento).
TEX_PELE = 2048
# O corpo sem subdivisão (~15 mil triângulos): a subdivisão Loop quadruplicava
# a malha (62 mil) para um ganho que não aparece no quadro da arena.
# BOXEADOR_SUBDIVIDIR=1 volta a subdividir (para PC).
import os as _os
SUBDIVIDIR = _os.environ.get("BOXEADOR_SUBDIVIDIR", "0") == "1"
TEX_ROUPA = 2048
rng = np.random.default_rng(20260924)


# ---------------------------------------------------------------- corpo
def corpo() -> dict:
    """Roda o Anny uma vez e guarda o resultado (a montagem é lenta)."""
    if CACHE.exists():
        z = np.load(CACHE, allow_pickle=False)
        return {k: z[k] for k in z.files}
    import torch
    import anny

    m = anny.Anny(rig="makehuman", local_changes="all", facial_actions="all").to(dtype=torch.float32)
    pose = torch.eye(4)[None, None].repeat(1, m.bone_count, 1, 1)
    # O CAMPEÃO DE ANIME: jovem, peito largo, ombros e braços grandes,
    # cintura fina (o "V" do boxeador), barriga trincada.
    fenotipo = dict(gender=1.0, age=0.40, muscle=1.0, weight=0.66, height=0.62, proportions=1.0)
    local = {
        "torso-muscle-pectoral-incr": 1.0, "torso-muscle-dorsi-incr": 1.0,
        "torso-vshape-incr": 1.0, "measure-shoulder-dist-incr": 0.55,
        "l-upperarm-muscle-incr": 1.0, "r-upperarm-muscle-incr": 1.0,
        "l-upperarm-shoulder-muscle-incr": 1.0, "r-upperarm-shoulder-muscle-incr": 1.0,
        "l-lowerarm-muscle-incr": 0.9, "r-lowerarm-muscle-incr": 0.9,
        "measure-upperarm-circ-incr": 0.35,
        "l-upperleg-muscle-incr": 0.7, "r-upperleg-muscle-incr": 0.7,
        "l-lowerleg-muscle-incr": 0.6, "r-lowerleg-muscle-incr": 0.6,
        "measure-neck-circ-incr": 0.8, "stomach-tone-incr": 0.9,
        "measure-waist-circ-incr": -0.35, "measure-frontchest-dist-incr": 0.3,
    }
    local = {k: v for k, v in local.items() if k in m.local_change_labels}
    def rosto(acoes):
        base = dict(ROSTO_BASE)
        base.update(acoes)
        return m(pose_parameters=pose, phenotype_kwargs=fenotipo, local_changes_kwargs=local,
                 facial_actions=base, return_bone_ends=True)

    out = rosto({})
    repouso = out["rest_vertices"][0].detach().numpy()
    alvos = np.stack([rosto(EXPRESSOES[k])["rest_vertices"][0].detach().numpy() - repouso
                      for k in EXPRESSOES])
    dados = dict(
        expressoes=alvos.astype(np.float32),
        verts=out["rest_vertices"][0].detach().numpy(),
        faces=m.faces.numpy(), uv=m.texture_coordinates.numpy(),
        face_uv=m.face_texture_coordinate_indices.numpy(),
        heads=out["rest_bone_heads"][0].detach().numpy(),
        labels=np.array(m.bone_labels), vbi=m.vertex_bone_indices.numpy(),
        vbw=m.vertex_bone_weights.numpy(), base_idx=m.base_mesh_vertex_indices.numpy(),
    )
    np.savez_compressed(CACHE, **dados)
    return dados


## O rosto de repouso: concentrado, sobrancelha baixa, olhar apertado.
ROSTO_BASE = {"browDownLeft": 0.40, "browDownRight": 0.40, "eyeSquintLeft": 0.30,
              "eyeSquintRight": 0.30, "mouthPressLeft": 0.25, "mouthPressRight": 0.25,
              "eyeBlinkLeft": 0.12, "eyeBlinkRight": 0.12}
## As expressões que o jogo liga por cima (morph targets do glTF).
EXPRESSOES = {
    "deboche": {"mouthSmileLeft": 0.85, "mouthSmileRight": 0.30, "cheekSquintLeft": 0.5,
                "browOuterUpRight": 0.45, "browDownLeft": 0.55, "mouthPressLeft": 0.0,
                "mouthPressRight": 0.0, "eyeSquintLeft": 0.55},
    "dor": {"eyeSquintLeft": 0.85, "eyeSquintRight": 0.85, "browInnerUp": 0.45,
            "browDownLeft": 0.6, "browDownRight": 0.6, "mouthStretchLeft": 0.65,
            "mouthStretchRight": 0.65, "jawOpen": 0.18, "noseSneerLeft": 0.45,
            "noseSneerRight": 0.45, "mouthPressLeft": 0.0, "mouthPressRight": 0.0},
    "grito": {"jawOpen": 0.70, "mouthStretchLeft": 0.35, "mouthStretchRight": 0.35,
              "mouthUpperUpLeft": 0.45, "mouthUpperUpRight": 0.45, "browDownLeft": 0.2,
              "browDownRight": 0.2, "mouthPressLeft": 0.0, "mouthPressRight": 0.0,
              "noseSneerLeft": 0.3, "noseSneerRight": 0.3},
    "apagado": {"eyeBlinkLeft": 0.82, "eyeBlinkRight": 0.9, "jawOpen": 0.28, "eyeLookUpLeft": 0.5, "eyeLookUpRight": 0.5,
                "browDownLeft": 0.0, "browDownRight": 0.0, "eyeSquintLeft": 0.0,
                "eyeSquintRight": 0.0, "mouthPressLeft": 0.0, "mouthPressRight": 0.0},
}


def para_gltf(p: np.ndarray) -> np.ndarray:
    """MakeHuman/Blender (Z cima, frente -Y) -> glTF (Y cima, frente +Z)."""
    return np.stack([p[..., 0], p[..., 2], -p[..., 1]], -1)


# ------------------------------------------------------------ esqueleto
## osso compacto -> (pai, ossos do MakeHuman que ele absorve)
OSSOS = [
    ("Hips", None, ["root", "pelvis.L", "pelvis.R", "spine05"]),
    ("Spine", "Hips", ["spine04"]),
    ("Spine1", "Spine", ["spine03", "spine02"]),
    ("Spine2", "Spine1", ["spine01", "breast.L", "breast.R"]),
    ("Neck", "Spine2", ["neck01", "neck02", "neck03"]),
    ("Head", "Neck", ["head", "*"]),
    ("HeadTop_End", "Head", []),
]
for lado, s in (("Left", "L"), ("Right", "R")):
    OSSOS += [
        (f"{lado}Shoulder", "Spine2", [f"clavicle.{s}", f"shoulder01.{s}"]),
        (f"{lado}Arm", f"{lado}Shoulder", [f"upperarm01.{s}", f"upperarm02.{s}"]),
        (f"{lado}ForeArm", f"{lado}Arm", [f"lowerarm01.{s}", f"lowerarm02.{s}"]),
        (f"{lado}Hand", f"{lado}ForeArm", [f"wrist.{s}", f"finger*.{s}", f"metacarpal*.{s}"]),
        (f"{lado}HandMiddle1", f"{lado}Hand", []),
        (f"{lado}HandThumb1", f"{lado}Hand", []),
        (f"{lado}UpLeg", "Hips", [f"upperleg01.{s}", f"upperleg02.{s}"]),
        (f"{lado}Leg", f"{lado}UpLeg", [f"lowerleg01.{s}", f"lowerleg02.{s}"]),
        (f"{lado}Foot", f"{lado}Leg", [f"foot.{s}"]),
        (f"{lado}ToeBase", f"{lado}Foot", [f"toe*.{s}"]),
        (f"{lado}Toe_End", f"{lado}ToeBase", []),
    ]
NOMES = [o[0] for o in OSSOS]


def casa(padrao: str, nome: str) -> bool:
    if padrao == "*":
        return False
    if "*" in padrao:
        a, b = padrao.split("*")
        return nome.startswith(a) and nome.endswith(b)
    return nome == padrao


def montar_esqueleto(d: dict, v: np.ndarray):
    rotulos = [str(x) for x in d["labels"]]
    cab = para_gltf(d["heads"])
    mapa = np.zeros(len(rotulos), np.int32)
    for i, nome in enumerate(rotulos):
        alvo = NOMES.index("Head")
        for j, (_, _, pads) in enumerate(OSSOS):
            if any(casa(p, nome) for p in pads):
                alvo = j
                break
        mapa[i] = alvo
    pos = np.zeros((len(OSSOS), 3), np.float32)

    def h(n):
        return cab[rotulos.index(n)]

    pos[NOMES.index("Hips")] = h("upperleg01.L") * 0.5 + h("upperleg01.R") * 0.5 + [0, 0.02, 0]
    pos[NOMES.index("Spine")] = h("spine04")
    pos[NOMES.index("Spine1")] = h("spine03")
    pos[NOMES.index("Spine2")] = h("spine01")
    pos[NOMES.index("Neck")] = h("neck01")
    pos[NOMES.index("Head")] = h("head")
    topo = v[np.argmax(v[:, 1])]
    pos[NOMES.index("HeadTop_End")] = [0.0, topo[1], h("head")[2]]
    for lado, s in (("Left", "L"), ("Right", "R")):
        pos[NOMES.index(f"{lado}Shoulder")] = h(f"clavicle.{s}")
        pos[NOMES.index(f"{lado}Arm")] = h(f"upperarm01.{s}")
        pos[NOMES.index(f"{lado}ForeArm")] = h(f"lowerarm01.{s}")
        pos[NOMES.index(f"{lado}Hand")] = h(f"wrist.{s}")
        pos[NOMES.index(f"{lado}HandMiddle1")] = h(f"finger3-1.{s}")
        pos[NOMES.index(f"{lado}HandThumb1")] = h(f"finger1-2.{s}")
        pos[NOMES.index(f"{lado}UpLeg")] = h(f"upperleg01.{s}")
        pos[NOMES.index(f"{lado}Leg")] = h(f"lowerleg01.{s}")
        pos[NOMES.index(f"{lado}Foot")] = h(f"foot.{s}")
        pos[NOMES.index(f"{lado}ToeBase")] = h(f"toe3-1.{s}")
        ponta = h(f"toe3-1.{s}") + (h(f"toe3-1.{s}") - h(f"foot.{s}")) * 0.45
        pos[NOMES.index(f"{lado}Toe_End")] = ponta
    # Pesos: soma os ossos fundidos, fica com os 4 maiores.
    n = v.shape[0]
    w = np.zeros((n, len(OSSOS)), np.float32)
    for k in range(d["vbi"].shape[1]):
        np.add.at(w, (np.arange(n), mapa[d["vbi"][:, k]]), d["vbw"][:, k])
    return pos, w


def top4(w: np.ndarray):
    idx = np.argsort(-w, axis=1)[:, :4]
    val = np.take_along_axis(w, idx, 1)
    val = val / np.maximum(val.sum(1, keepdims=True), 1e-8)
    return idx.astype(np.uint16), val.astype(np.float32)


# --------------------------------------------------------------- malhas
def normais(v: np.ndarray, f: np.ndarray) -> np.ndarray:
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    n = np.zeros_like(v)
    for k in range(3):
        np.add.at(n, f[:, k], fn)
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)


def vizinhos(n: int, f: np.ndarray):
    import scipy.sparse as sp
    i = np.concatenate([f[:, 0], f[:, 1], f[:, 2], f[:, 1], f[:, 2], f[:, 0]])
    j = np.concatenate([f[:, 1], f[:, 2], f[:, 0], f[:, 0], f[:, 1], f[:, 2]])
    a = sp.coo_matrix((np.ones(len(i), np.float32), (i, j)), shape=(n, n)).tocsr()
    a.data[:] = 1.0
    grau = np.asarray(a.sum(1)).ravel()
    return a, np.maximum(grau, 1.0)


def alisar(v: np.ndarray, a, grau, vezes: int, trava=None) -> np.ndarray:
    out = v.copy()
    for _ in range(vezes):
        media = (a @ out) / grau[:, None]
        if trava is not None:
            media[trava] = out[trava]
        out = out * 0.4 + media * 0.6
    return out


def curvatura(v, f, a, grau, n) -> np.ndarray:
    """Positivo = côncavo (vale entre músculos)."""
    media = (a @ v) / grau[:, None]
    c = np.einsum("ij,ij->i", media - v, n)
    return c


def casca(v, f, n, mascara_v, afasta, a, grau, alisa=6):
    """Pega os triângulos com os 3 vértices na máscara e afasta da pele."""
    tri = mascara_v[f].all(1)
    ff = f[tri]
    usados = np.unique(ff)
    novo = -np.ones(len(v), np.int64)
    novo[usados] = np.arange(len(usados))
    vv = v.copy()
    # A borda da casca não se mexe no alisamento (senão a bainha encolhe).
    conta = np.zeros(len(v), np.int32)
    for k in range(3):
        np.add.at(conta, ff[:, k], 1)
    tot = np.zeros(len(v), np.int32)
    for k in range(3):
        np.add.at(tot, f[:, k], 1)
    borda = (conta > 0) & (conta < tot)
    vv = alisar(vv, a, grau, alisa, trava=borda)
    nn = normais(vv, f)
    vv = vv + nn * afasta[:, None]
    return vv, novo[ff], usados, borda


def fechar_cavalo(cv, usados, pos):
    """O CALÇÃO CAI RETO ENTRE AS PERNAS, como cetim de verdade.

    A casca seguia o corpo até dentro do vão entre as coxas: na frente do
    calção ficava um buraco fundo e escuro bem no cavalo (e a câmera do
    soco na tela ia justo nele). Aqui, fatia por fatia de altura, a frente
    e as costas do calção são puxadas até o "contorno de tecido esticado"
    (a envoltória convexa da fatia): o pano passa reto de uma coxa à
    outra, sem entrar no vão.
    """
    I = NOMES.index
    uso = np.zeros(len(cv), bool)
    uso[usados] = True
    meio = uso & (np.abs(cv[:, 0]) < 0.015)
    if not meio.any():
        return
    apice = float(cv[meio, 1].min())
    topo = float(pos[I("Hips")][1]) + 0.03
    faixa = np.where(uso & (cv[:, 1] > apice - 0.012) & (cv[:, 1] < topo))[0]
    passo = 0.008

    def cruz(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    for sinal in (1.0, -1.0):
        for yb in np.arange(apice - 0.012, topo, passo):
            sel = faixa[(cv[faixa, 1] >= yb) & (cv[faixa, 1] < yb + passo)]
            if len(sel) < 4:
                continue
            x = cv[sel, 0]
            z = cv[sel, 2] * sinal
            centro = float(np.median(cv[sel, 2])) * sinal
            ordem = np.argsort(x)
            casco = []
            for k in ordem:
                ponto = (x[k], z[k])
                while len(casco) >= 2 and cruz(casco[-2], casco[-1], ponto) >= 0:
                    casco.pop()
                casco.append(ponto)
            h = np.array(casco)
            zh = np.interp(x, h[:, 0], h[:, 1]) - 0.003
            # Só perto do meio, e só na metade da frente (ou de trás):
            # as laterais das coxas continuam seguindo o corpo.
            peso_x = np.clip((0.11 - np.abs(x)) / 0.05, 0.0, 1.0)
            frente = np.clip((z - centro) / max(float(zh.max() - centro), 1e-4) * 2.0, 0.0, 1.0)
            peso = peso_x * frente
            novo = np.maximum(z, z + (zh - z) * peso)
            cv[sel, 2] = novo * sinal


def friso(cv, ci, nrm, jj, ww, pos, r, v0):
    """Faixa da bainha: um anel de quadriláteros subindo da borda da perna."""
    from collections import Counter
    arestas = Counter()
    for t in ci:
        for k in range(3):
            a_, b_ = sorted((int(t[k]), int(t[(k + 1) % 3])))
            arestas[(a_, b_)] += 1
    borda = [e for e, c in arestas.items() if c == 1]
    P, N, F, C, J, W = [], [], [], [], [], []
    I = NOMES.index
    alt = 0.014
    for a_, b_ in borda:
        pa, pb = cv[a_], cv[b_]
        if min(pa[1], pb[1]) > r["cintura"] - 0.05:
            continue  # borda de cima (cintura) não leva friso
        lado = "Left" if pa[0] > 0 else "Right"
        eixo = pos[I(f"{lado}UpLeg")] - pos[I(f"{lado}Leg")]
        eixo = eixo / np.linalg.norm(eixo)
        base = len(P)
        for p_, k in ((pa, a_), (pb, b_)):
            fora = p_ - pos[I(f"{lado}Leg")]
            fora = fora - eixo * fora.dot(eixo)
            fora = fora / max(np.linalg.norm(fora), 1e-6)
            for h in (0.0, alt):
                # a faixa desce da bainha, abrindo um pouco (a barra do cetim)
                P.append(p_ - eixo * h + fora * (0.0015 + h * 0.25))
                N.append(fora)
                C.append([0.78, 0.05, 0.09])
                J.append(jj[k])
                W.append(ww[k])
        F += [[base, base + 2, base + 1], [base + 1, base + 2, base + 3]]
    if not F:
        return [], [], [], [], [], []
    F = np.array(F, np.uint32)
    P = np.array(P, np.float32)
    # a ordem dos triângulos depende do sentido da aresta: dupla face.
    F = np.concatenate([F, F[:, ::-1]])
    return (P, np.array(N, np.float32), F, np.array(C, np.float32),
            np.array(J, np.uint16), np.array(W, np.float32))


def dentes(pt):
    """Arco dos dentes de cima, logo atrás do lábio."""
    b = pt["boca"]
    P, N, F, C = [], [], [], []
    passos = 14
    for i_ in range(passos + 1):
        a_ = (i_ / passos - 0.5) * 2.3  # radianos em volta do arco
        raio = 0.024
        cx, cz = np.sin(a_) * raio, np.cos(a_) * raio - raio
        base = np.array([b[0] + cx, b[1] + 0.0015, b[2] - 0.0085 + cz])
        nrm = np.array([np.sin(a_), 0.0, np.cos(a_)])
        for h in (0.0, 0.0095):
            P.append(base + [0, h, 0])
            N.append(nrm)
            borda = 0.93 if 0.0 < abs(a_) else 1.0
            C.append([0.86 * borda, 0.84 * borda, 0.78 * borda])
        if i_ < passos:
            q = i_ * 2
            F += [[q, q + 2, q + 1], [q + 1, q + 2, q + 3]]
    F = np.array(F, np.uint32)
    F = np.concatenate([F, F[:, ::-1]])
    return np.array(P, np.float32), F, np.array(N, np.float32), np.array(C, np.float32)


# --------------------------------------------------------------- luvas
# ---------------------------------------------------- campos de distância
def _sd_elipsoide(p, c, r):
    q = (p - c) / r
    k0 = np.linalg.norm(q, axis=-1)
    k1 = np.linalg.norm(q / r, axis=-1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def _sd_cone_redondo(p, a, b, r1, r2):
    """Cone de pontas redondas de a (raio r1) até b (raio r2)."""
    ba = b - a
    l2 = ba.dot(ba)
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pa = p - a
    y = pa @ ba
    z = y - l2
    x = pa * l2 - y[..., None] * ba
    x2 = np.einsum("...i,...i->...", x, x)
    y2 = y * y * l2
    z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    d = np.where(
        np.sign(z) * a2 * z2 > k, np.sqrt(x2 + z2) * il2 - r2,
        np.where(np.sign(y) * a2 * y2 < k, np.sqrt(x2 + y2) * il2 - r1,
                 (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1))
    return d


def _sd_caixa_redonda(p, c, meia, raio):
    q = np.abs(p - c) - (meia - raio)
    fora = np.linalg.norm(np.maximum(q, 0.0), axis=-1)
    dentro = np.minimum(np.max(q, axis=-1), 0.0)
    return fora + dentro - raio


def _uniao(d1, d2, k):
    h = np.clip(0.5 + 0.5 * (d2 - d1) / k, 0, 1)
    return d2 * (1 - h) + d1 * h - k * h * (1 - h)


def _malha_do_campo(campo, minimo, maximo, res):
    """Marching cubes de uma função campo(P) numa caixa."""
    from skimage import measure
    eixos = [np.arange(minimo[k], maximo[k] + res, res) for k in range(3)]
    X, Y, Z = np.meshgrid(*eixos, indexing="ij")
    P = np.stack([X, Y, Z], -1)
    d = campo(P)
    verts, faces, nrm, _ = measure.marching_cubes(d, 0.0, spacing=(res, res, res))
    verts = verts + np.asarray(minimo)
    return verts.astype(np.float64), faces[:, ::-1].astype(np.uint32), (-nrm).astype(np.float64)


# -------------------------------------------------------------- cabelo
def cabelo(v, n, f, w, pontos, semente=7):
    """CABELO ESPETADO DE ANIME, de verdade (malha, não pintura).

    Uma casca fina colada ao couro cabeludo e ~50 mechas em cone saindo
    dele: para cima e para trás no alto da cabeça, e a franja caindo para
    a frente sobre a testa — o penteado do boxeador de mangá. Tudo num
    campo de distância só, fechado por marching cubes (sem emendas)."""
    from scipy.spatial import cKDTree
    rng_ = np.random.default_rng(semente)
    I = NOMES.index
    cab_c = np.asarray(pontos["centro_cabeca"], np.float64)
    testa_y = float(pontos["testa_y"])
    orelha = np.asarray(pontos["orelha"], np.float64)
    rel = v - cab_c
    fa = np.cos(np.arctan2(rel[:, 0], rel[:, 2]))  # 1 = frente
    linha = np.where(fa > 0, testa_y - (1 - fa) ** 1.4 * 0.036,
                     testa_y - 0.036 - np.clip(-fa, 0, 1) ** 0.8 * 0.07)
    perto_orelha = np.minimum(np.linalg.norm(v - orelha, axis=1),
                              np.linalg.norm(v - orelha * [-1, 1, 1], axis=1)) < 0.036
    couro = (w[:, I("Head")] > 0.6) & (v[:, 1] > linha) & ~perto_orelha
    pts = v[couro].astype(np.float64)
    nrm = n[couro].astype(np.float64)
    # A CASCA PRECISA DE PONTOS DENSOS: os vértices do corpo ficam a 1–2 cm
    # uns dos outros, e a casca de 1 cm saía em bolinhas, com o cabelo
    # pintado aparecendo entre elas. Cada triângulo do couro cabeludo é
    # salpicado de pontos.
    tri = f[couro[f].all(1)]
    amostras = [pts]
    for _ in range(24):
        b = rng_.dirichlet([1.0, 1.0, 1.0], len(tri))
        amostras.append((v[tri] * b[:, :, None]).sum(1))
    denso = np.concatenate(amostras)
    arvore = cKDTree(denso)
    # sementes das mechas: amostragem espalhada (a mais longe primeiro)
    escolha = [int(np.argmax(pts[:, 1]))]
    dist = np.linalg.norm(pts - pts[escolha[0]], axis=1)
    for _ in range(40):
        k = int(np.argmax(dist))
        escolha.append(k)
        dist = np.minimum(dist, np.linalg.norm(pts - pts[k], axis=1))
    mechas = []
    for k in escolha:
        p0, n0 = pts[k], nrm[k] / max(np.linalg.norm(nrm[k]), 1e-6)
        r0 = p0 - cab_c
        frente = np.cos(np.arctan2(r0[0], r0[2]))
        if frente > 0.5 and p0[1] < testa_y + 0.05:
            # FRANJA: mechas grossas saindo para a frente e caindo sobre a
            # testa (sem furar a pele)
            dirc = n0 * 0.6 + np.array([rng_.normal(0, 0.15), -0.55, 0.65])
            comp = rng_.uniform(0.05, 0.075)
            raio = rng_.uniform(0.022, 0.028)
        else:
            # o resto PENTEADO PARA TRÁS e para cima, em chamas
            dirc = n0 * 0.8 + np.array([0.0, 0.35, -0.55]) + rng_.normal(0, 0.12, 3)
            comp = rng_.uniform(0.07, 0.12)
            raio = rng_.uniform(0.026, 0.034)
        dirc /= np.linalg.norm(dirc)
        base = p0 + n0 * 0.006
        mechas.append((base, base + dirc * comp, raio))
    lo = pts.min(0) - 0.13
    hi = pts.max(0) + 0.13

    def campo(P):
        forma = P.shape[:-1]
        Q = P.reshape(-1, 3)
        d, _ = arvore.query(Q, k=1)
        casca = d - 0.013
        for a_, b_, r_ in mechas:
            casca = _uniao(casca, _sd_cone_redondo(Q, a_, b_, r_, 0.002), 0.02)
        return casca.reshape(forma)

    loc, faces, nrm_m = _malha_do_campo(campo, lo, hi, 0.0045)
    # preto azulado, com as pontas e o alto mais claros (brilho de mangá)
    alt = np.clip((loc[:, 1] - testa_y) / 0.14, 0, 1)
    cor = np.tile(np.array([0.035, 0.035, 0.05], np.float32), (len(loc), 1))
    cor += (alt[:, None] * np.array([0.05, 0.06, 0.12])).astype(np.float32)
    # O sentido dos triângulos sai invertido em relação às luvas (lá a base
    # de rotação da mão desvira): sem isto só a face de DENTRO da casca era
    # desenhada — o topo da cabeça ficava careca e as mechas só por trás.
    faces = faces[:, ::-1].copy()
    return loc.astype(np.float32), faces, nrm_m.astype(np.float32), cor.astype(np.float32)


# --------------------------------------------------------------- luvas
def luva(pulso, junta, dedao, palma_n, lado, eixo_do_antebraco):
    """Luva de boxe de verdade: corpo acolchoado, dorso, polegar colado,
    punho alinhado com o ANTEBRAÇO (é ele que o punho abraça) e a faixa
    de velcro."""
    eixo = eixo_do_antebraco / np.linalg.norm(eixo_do_antebraco)
    comp = np.linalg.norm(junta - pulso)
    lateral = dedao - pulso
    lateral = lateral - eixo * lateral.dot(eixo)
    lateral /= np.linalg.norm(lateral)
    normal = np.cross(eixo, lateral)
    if normal.dot(palma_n) < 0:
        normal = -normal
    base = np.stack([lateral, normal, eixo], 1)  # x=polegar, y=palma, z=dedos
    s = comp / 0.105
    A = lambda *v: np.array(v) * s

    def campo(P):
        corpo = _sd_caixa_redonda(P, A(0.0, -0.004, 0.112), A(0.055, 0.049, 0.080), 0.036 * s)
        punho = _sd_elipsoide(P, A(0.0, -0.002, 0.150), A(0.060, 0.053, 0.052))
        dorso = _sd_elipsoide(P, A(0.0, -0.026, 0.112), A(0.056, 0.036, 0.084))
        polegar = _sd_cone_redondo(P, A(0.052, 0.020, 0.050), A(0.047, 0.030, 0.128), 0.0215 * s, 0.019 * s)
        # o cano afina para o cotovelo: abraça o antebraço (sem boca larga)
        cano = _sd_cone_redondo(P, A(0.0, 0.0, -0.080), A(0.0, 0.0, 0.026), 0.039 * s, 0.048 * s)
        faixa = _sd_cone_redondo(P, A(0.0, 0.0, -0.052), A(0.0, 0.0, -0.022), 0.0475 * s, 0.0485 * s)
        d = _uniao(corpo, punho, 0.03 * s)
        d = _uniao(d, dorso, 0.025 * s)
        d = _uniao(d, polegar, 0.009 * s)
        d = _uniao(d, cano, 0.035 * s)
        # O punho termina num corte reto e FECHADO: antes a ponta do cano
        # passava da caixa da malha e o punho saía aberto — de lado dava
        # para ver a luva por dentro, oca.
        corte = -(P[..., 2] + 0.092 * s)
        return -_uniao(-np.minimum(d, faixa), -corte, 0.014 * s)

    loc, faces, nrm = _malha_do_campo(campo, A(-0.085, -0.085, -0.10), A(0.085, 0.085, 0.215), 0.0058 * s)
    z = loc[:, 2] / s
    cor = np.tile(np.array([0.74, 0.025, 0.05], np.float32), (len(loc), 1))
    cor[z < 0.0] = [0.93, 0.93, 0.92]                            # punho branco
    faixa = (z > -0.052) & (z < -0.020)
    cor[faixa] = [0.70, 0.02, 0.05]                              # velcro vermelho
    for a, b in ((-0.046, -0.042), (-0.031, -0.027)):
        cor[(z > a) & (z < b)] = [0.95, 0.95, 0.94]              # frisos brancos
    cor[(z < -0.074) & (z > -0.084)] = [0.12, 0.10, 0.12]         # borda do punho
    cor[z <= -0.084] = [0.86, 0.86, 0.85]                         # tampa do punho
    # Palma um pouco mais escura, em degradê (a mancha chapada de antes
    # parecia um buraco na luva).
    palma = np.clip((loc[:, 1] / s - 0.030) / 0.030, 0, 1) * np.clip((z - 0.03) / 0.03, 0, 1)
    cor = cor * (1 - 0.08 * palma[:, None]).astype(np.float32)
    # costura do polegar: fio escuro SÓ onde o polegar encontra o corpo.
    # (Antes a conta pegava todo ponto na superfície do polegar — ele
    # inteiro ficava escuro e parecia uma mancha chapada na luva.)
    pol = _sd_cone_redondo(loc, A(0.052, 0.020, 0.050), A(0.047, 0.030, 0.128), 0.0215 * s, 0.019 * s)
    corpo_sd = _sd_caixa_redonda(loc, A(0.0, -0.004, 0.112), A(0.055, 0.049, 0.080), 0.036 * s)
    costura = (np.abs(pol) < 0.004 * s) & (np.abs(corpo_sd) < 0.004 * s) & (z > 0.02)
    cor[costura] = [0.45, 0.015, 0.035]
    # SOMBRA EMBUTIDA NA COR: o vermelho saturado com a luz de frente
    # quase uniforme apagava a forma da luva (ela lia como um recorte
    # chapado). Mais escuro embaixo e nas laterais, mais claro no dorso e
    # nos nós dos dedos — a forma aparece com qualquer luz.
    nn = nrm / (np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-9)
    dorso = np.clip(-nn[:, 1], 0, 1)              # -y é o dorso (y = palma)
    frente = np.clip(nn[:, 2], 0, 1)              # nós dos dedos
    lado = np.abs(nn[:, 0])
    luz = 0.62 + 0.30 * dorso + 0.18 * frente - 0.16 * lado
    cor = (cor * np.clip(luz, 0.45, 1.1)[:, None]).astype(np.float32)
    mundo = loc @ base.T + pulso
    return mundo.astype(np.float32), faces, (nrm @ base.T).astype(np.float32), cor


# --------------------------------------------------------------- botas
def bota(pos, lado):
    """Bota de boxe com forma de bota: sola de borracha, biqueira redonda,
    cano alto até a metade da canela e cadarço em relevo."""
    I = NOMES.index
    tornozelo = pos[I(f"{lado}Foot")]
    ponta = pos[I(f"{lado}Toe_End")]
    joelho = pos[I(f"{lado}Leg")]
    frente = ponta - tornozelo
    frente[1] = 0.0
    frente /= np.linalg.norm(frente)
    fora = np.cross(np.array([0.0, 1.0, 0.0]), frente)
    if fora[0] * np.sign(tornozelo[0]) < 0:
        fora = -fora
    base = np.stack([fora, np.array([0.0, 1.0, 0.0]), frente], 1)
    origem = np.array([tornozelo[0], 0.0, tornozelo[2]])
    perna = (joelho - tornozelo) @ base          # eixo da canela no espaço da bota
    perna_dir = perna / np.linalg.norm(perna)
    topo_t = 0.44                                  # fração do caminho tornozelo -> joelho
    tor = (tornozelo - origem) @ base
    topo = tor + perna * topo_t
    comp = np.linalg.norm(ponta - tornozelo)
    s = comp / 0.205

    def pegada(P):
        # contorno do solado: calcanhar, planta e ponta
        calc = np.linalg.norm(P[..., [0, 2]] - np.array([0.0, -0.036 * s]), axis=-1) - 0.037 * s
        planta = np.linalg.norm(P[..., [0, 2]] - np.array([0.004 * s, 0.118 * s]), axis=-1) - 0.049 * s
        dedo = np.linalg.norm(P[..., [0, 2]] - np.array([0.0, 0.168 * s]), axis=-1) - 0.034 * s
        d2 = _uniao(_uniao(calc, planta, 0.06 * s), dedo, 0.03 * s)
        return d2

    def solado(P):
        # A SOLA ACOMPANHA A BOTA: um fio para dentro do contorno, fina.
        # Mais larga e branca, ela virava uma prancha saindo do pé toda
        # vez que o pé inclinava.
        d2 = pegada(P) + 0.0015 * s
        dy = np.abs(P[..., 1] - 0.008 * s) - 0.008 * s
        return np.maximum(d2, dy)

    def cabedal(P):
        calcanhar = _sd_cone_redondo(P, A(0, 0.045, -0.040), A(0, 0.052, 0.02), 0.037 * s, 0.040 * s)
        peito = _sd_cone_redondo(P, A(0, 0.052, 0.02), A(0.004, 0.036, 0.120), 0.040 * s, 0.040 * s)
        bico = _sd_elipsoide(P, A(0.0, 0.030, 0.150), A(0.042, 0.028, 0.040))
        cano = _sd_cone_redondo(P, tor + np.array([0, 0.01 * s, -0.004 * s]), topo, 0.043 * s, 0.049 * s)
        d = _uniao(calcanhar, peito, 0.03 * s)
        d = _uniao(d, bico, 0.03 * s)
        d = _uniao(d, cano, 0.035 * s)
        # corta o que desceria abaixo do solado
        return np.maximum(d, -(P[..., 1] - 0.012 * s))

    def A(*v):
        return np.array(v) * s

    def frente_da_bota(y):
        """Ponto da superfície da frente do cano/peito numa altura y."""
        t = np.clip((y - tor[1]) / max(topo[1] - tor[1], 1e-6), 0, 1)
        eixo_p = tor + (topo - tor) * t
        # anda para a frente (+z) até sair da bota
        lo, hi = 0.0, 0.2 * s
        for _ in range(30):
            mid = (lo + hi) / 2
            q = eixo_p + np.array([0, 0, mid])
            q[1] = y
            if cabedal(q[None, :])[0] < 0:
                lo = mid
            else:
                hi = mid
        q = eixo_p + np.array([0, 0, lo])
        q[1] = y
        return q

    # cadarço: xis do peito do pé até o topo
    furos = []
    alturas = np.linspace(0.055 * s, topo[1] - 0.018 * s, 8)
    for y in alturas:
        c = frente_da_bota(y)
        furos.append((c + np.array([0.013 * s, 0, 0.002 * s]), c + np.array([-0.013 * s, 0, 0.002 * s])))

    def cadarco(P):
        d = np.full(P.shape[:-1], 9.0)
        for k in range(len(furos) - 1):
            (e0, d0), (e1, d1) = furos[k], furos[k + 1]
            d = np.minimum(d, _sd_cone_redondo(P, e0, d1, 0.0036 * s, 0.0036 * s))
            d = np.minimum(d, _sd_cone_redondo(P, d0, e1, 0.0036 * s, 0.0036 * s))
        return d

    def campo(P):
        return np.minimum(np.minimum(_uniao(solado(P), cabedal(P), 0.006 * s), cadarco(P)), 9.0)

    lo = np.array([-0.075 * s, 0.0 - 0.004, -0.095 * s])
    hi = np.array([0.075 * s, topo[1] + 0.03 * s, 0.215 * s])
    # Passo do campo maior: metade dos triângulos (a TV Box agradece) com
    # a mesma forma — o detalhe fino (cadarço, frisos) vem da cor.
    loc, faces, nrm = _malha_do_campo(campo, lo, hi, 0.0062 * s)
    y = loc[:, 1]
    cor = np.tile(np.array([0.035, 0.033, 0.04], np.float32), (len(loc), 1))
    ruido = np.sin(loc[:, 0] * 900) * np.sin(loc[:, 2] * 700) * 0.01
    cor += ruido[:, None]
    cor[y < 0.016 * s] = [0.10, 0.095, 0.105]                    # sola de borracha
    cor[(y < 0.021 * s) & (y >= 0.016 * s)] = [0.92, 0.91, 0.88]  # vira branca, fina
    aro = y > topo[1] - 0.011 * s
    cor[aro] = [0.95, 0.72, 0.10]                                  # aro dourado
    cor[cadarco(loc) < 0.0015 * s] = [0.95, 0.95, 0.93]            # cadarço branco
    mundo = loc @ base.T + origem
    nm = nrm @ base.T
    # pele de ossos: cano -> canela, pé -> pé, ponta -> dedos
    w = np.zeros((len(loc), len(NOMES)), np.float32)
    subida = np.clip((y - (tor[1] + 0.00)) / (0.07 * s), 0, 1)
    subida = subida * subida * (3 - 2 * subida)
    dedo_z = ((pos[I(f"{lado}ToeBase")] - origem) @ base)[2]
    # A biqueira pesa só metade no osso dos dedos: bota não dobra como pé.
    dedos = 0.5 * np.clip((loc[:, 2] - (dedo_z - 0.015 * s)) / (0.035 * s), 0, 1) * (1 - subida)
    w[:, I(f"{lado}Leg")] = subida
    w[:, I(f"{lado}ToeBase")] = dedos
    w[:, I(f"{lado}Foot")] = 1 - subida - dedos
    return mundo.astype(np.float32), faces, nm.astype(np.float32), cor, w, topo_t


# ------------------------------------------------------------- cinturão
def cinturao(cv, cintura, pesos_de):
    """O cós do calção como PEÇA: faixa acolchoada em volta da cintura,
    com textura própria (nome, estrelas, costura e frisos)."""
    altura = 0.066
    y0, y1 = cintura - altura + 0.004, cintura + 0.006
    centro_x = 0.0
    zona = cv[(cv[:, 1] > y0 - 0.01) & (cv[:, 1] < y1 + 0.01)]
    centro_z = (zona[:, 2].max() + zona[:, 2].min()) * 0.5
    angulos = 128
    niveis = 9
    P, UV, N = [], [], []
    raio_tab = np.zeros((niveis, angulos))
    for j in range(niveis):
        y = y0 + (y1 - y0) * j / (niveis - 1)
        fatia = cv[np.abs(cv[:, 1] - y) < 0.012]
        ang = np.arctan2(fatia[:, 0] - centro_x, fatia[:, 2] - centro_z)
        rad = np.hypot(fatia[:, 0] - centro_x, fatia[:, 2] - centro_z)
        for k in range(angulos):
            a = -np.pi + 2 * np.pi * k / angulos
            dif = np.abs((ang - a + np.pi) % (2 * np.pi) - np.pi)
            perto = dif < 0.12
            raio_tab[j, k] = rad[perto].max() if perto.any() else np.nan
    # preenche buracos e alisa em volta
    for j in range(niveis):
        linha = raio_tab[j]
        ok = ~np.isnan(linha)
        linha[~ok] = np.interp(np.nonzero(~ok)[0], np.nonzero(ok)[0], linha[ok], period=angulos)
        raio_tab[j] = nd.uniform_filter1d(linha, 5, mode="wrap")
    rmax = raio_tab.max(axis=0)
    # perfil: dobra de dentro embaixo, a faixa acolchoada, dobra de dentro em cima
    perfil = [(-0.004, -0.012, 0.0)]
    for j in range(niveis):
        v = j / (niveis - 1)
        perfil.append((y0 + (y1 - y0) * v - y0, 0.004 + 0.006 * np.sin(np.pi * v) ** 0.6, v))
    perfil.append((y1 - y0 + 0.003, -0.010, 1.0))
    for dy, folga, v in perfil:
        y = y0 + dy
        for k in range(angulos + 1):
            kk = k % angulos
            a = -np.pi + 2 * np.pi * k / angulos
            r = rmax[kk] + folga
            P.append([centro_x + np.sin(a) * r, y, centro_z + np.cos(a) * r])
            UV.append([k / angulos, 1.0 - v])
            N.append([np.sin(a), 0.0, np.cos(a)])
    niveis = len(perfil)
    P = np.array(P, np.float32)
    F = []
    L = angulos + 1
    for j in range(niveis - 1):
        for k in range(angulos):
            a0 = j * L + k
            F += [[a0, a0 + 1, a0 + L], [a0 + 1, a0 + L + 1, a0 + L]]
    F = np.array(F, np.uint32)
    n = normais(P.astype(np.float64), F.astype(np.int64)).astype(np.float32)
    jj, ww = pesos_de(P)
    return P, F, n, np.array(UV, np.float32), jj, ww


def textura_do_cinturao(largura=2048, altura=256):
    """A TIRA DO CINTURÃO DE CAMPEÃO: couro preto com bordas douradas,
    costura vermelha, rebites de ouro e as placas laterais com estrela. A
    placa grande da frente é peça própria (`placa_do_cinturao`)."""
    rng_ = np.random.default_rng(3)
    a = np.linspace(0, 1, altura)[:, None]
    couro = np.array([22, 18, 24]) * (0.85 + 0.35 * np.sin(a * np.pi))
    arr = np.broadcast_to(couro[:, None, :], (altura, largura, 3)).copy()
    grao = nd.gaussian_filter(rng_.normal(0, 1, (altura, largura)), 1.2)
    arr += (grao * 6)[..., None]
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    ouro_c, ouro_e = (238, 190, 60), (150, 100, 20)
    for y, h, c in ((0, 16, ouro_e), (4, 8, ouro_c), (altura - 16, 16, ouro_e), (altura - 12, 8, ouro_c)):
        d.rectangle([0, y, largura, y + h], fill=c)
    for y in (30, altura - 34):
        for x in range(0, largura, 20):
            d.line([x, y, x + 11, y], fill=(190, 20, 40), width=3)
    # rebites dourados ao longo da tira
    for x in range(40, largura, 80):
        for y in (58, altura - 60):
            d.ellipse([x - 9, y - 9, x + 9, y + 9], fill=ouro_e)
            d.ellipse([x - 7, y - 7, x + 5, y + 5], fill=ouro_c)
            d.ellipse([x - 4, y - 5, x, y - 1], fill=(255, 245, 200))

    def estrela(cx, cy, r, c):
        pts = []
        for k in range(10):
            ang = -np.pi / 2 + k * np.pi / 5
            rr = r if k % 2 == 0 else r * 0.45
            pts.append((cx + np.cos(ang) * rr, cy + np.sin(ang) * rr))
        d.polygon(pts, fill=c, outline=(90, 50, 10))

    # placas laterais: medalhão dourado com estrela vermelha
    for cx in (largura * 0.30, largura * 0.70, largura * 0.12, largura * 0.88):
        d.rounded_rectangle([cx - 95, 40, cx + 95, altura - 40], 28, fill=ouro_e)
        d.rounded_rectangle([cx - 86, 48, cx + 86, altura - 48], 22, fill=ouro_c)
        estrela(cx, altura / 2, 58, (170, 12, 32))
        estrela(cx, altura / 2, 30, (255, 236, 170))
    fonte2 = ImageFont.truetype(str(RAIZ / "assets" / "fonts" / "SairaCondensed-ExtraBold.ttf"), 84)
    for cx in (0, largura):
        caixa = d.textbbox((0, 0), "LAZER SPORT", font=fonte2)
        x = cx - (caixa[2] - caixa[0]) / 2
        yv = altura / 2 - (caixa[3] + caixa[1]) / 2
        d.text((x, yv), "LAZER SPORT", font=fonte2, fill=ouro_c)
    return img


def textura_da_placa(largura=1024, altura=768):
    """A PLACA DO CINTURÃO: ouro com brilho, aro com pedras vermelhas e o
    logo SUPER BOXING no meio, em relevo (sombra e luz pintadas)."""
    yy, xx = np.mgrid[0:altura, 0:largura].astype(np.float32)
    u = (xx / largura - 0.5) * 2
    v = (yy / altura - 0.5) * 2
    r = np.sqrt(u * u + v * v)
    luz = 0.78 + 0.35 * np.clip(-v * 0.6 - u * 0.3, -1, 1) + 0.15 * np.cos(r * 9.0)
    ouro = np.stack([236 * luz, 178 * luz, 56 * luz], -1)
    # aro: faixa mais escura e gravada perto da borda
    aro = (r > 0.80) & (r < 0.92)
    ouro[aro] *= 0.72
    ouro[(r > 0.92)] *= 0.55
    # raios gravados atrás do logo
    ang = np.arctan2(v, u)
    raios = (np.sin(ang * 24) > 0.6) & (r < 0.80) & (r > 0.25)
    ouro[raios] *= 0.90
    img = Image.fromarray(np.clip(ouro, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    # pedras vermelhas no aro
    for k in range(16):
        a_ = 2 * np.pi * k / 16
        cx = largura / 2 + np.cos(a_) * largura / 2 * 0.86
        cy = altura / 2 + np.sin(a_) * altura / 2 * 0.86
        d.ellipse([cx - 16, cy - 16, cx + 16, cy + 16], fill=(90, 0, 10))
        d.ellipse([cx - 12, cy - 12, cx + 10, cy + 10], fill=(210, 20, 45))
        d.ellipse([cx - 7, cy - 8, cx - 2, cy - 3], fill=(255, 190, 200))
    logo = Image.open(RAIZ / "assets" / "logos" / "superboxing_h512.png").convert("RGBA")
    alvo_l = int(largura * 0.66)
    logo = logo.resize((alvo_l, int(logo.size[1] * alvo_l / logo.size[0])), Image.LANCZOS)
    sombra = Image.new("RGBA", logo.size, (40, 20, 0, 0))
    sombra.putalpha(logo.getchannel("A").point(lambda x: int(x * 0.7)))
    ox = (largura - logo.size[0]) // 2
    oy = (altura - logo.size[1]) // 2 - 10
    img.paste(sombra, (ox + 8, oy + 10), sombra)
    img.paste(logo, (ox, oy), logo)
    fonte = ImageFont.truetype(str(RAIZ / "assets" / "fonts" / "SairaCondensed-ExtraBold.ttf"), 64)
    caixa = d.textbbox((0, 0), "CAMPEÃO", font=fonte)
    x = (largura - (caixa[2] - caixa[0])) / 2
    y0 = oy + logo.size[1] - 6
    d.text((x + 3, y0 + 3), "CAMPEÃO", font=fonte, fill=(90, 50, 5))
    d.text((x, y0), "CAMPEÃO", font=fonte, fill=(255, 240, 190))
    return img


def placa_do_cinturao(cp, cintura, pesos_de):
    """A placa grande da frente do cinturão: oval de ouro, levemente curva
    acompanhando a barriga, com espessura (aro) — peça sólida."""
    altura_cinto = 0.066
    y_meio = cintura - altura_cinto * 0.5 + 0.004
    frente = cp[np.abs(cp[:, 0]) < 0.02]
    frente = frente[np.abs(frente[:, 1] - y_meio) < 0.02]
    z_frente = float(frente[:, 2].max())
    zona = cp[np.abs(cp[:, 1] - y_meio) < 0.02]
    centro_z = float((zona[:, 2].max() + zona[:, 2].min()) * 0.5)
    # colada no cinto: pouco saliente, com a borda descendo para dentro
    # da tira (de lado não aparece vão nem casca oca).
    raio = z_frente - centro_z + 0.005
    meia_l, meia_a = 0.094, 0.064
    esp = 0.020
    aneis, lados = 14, 72
    P, UV = [], []

    def ponto(x, y, recuo):
        # curva em volta do corpo (cilindro vertical de raio `raio`)
        a_ = x / raio
        rr = raio - recuo
        return [np.sin(a_) * rr, y_meio + y, centro_z + np.cos(a_) * rr]

    # frente: anéis de dentro para fora, contorno superelíptico
    P.append(ponto(0.0, 0.0, -0.004))
    UV.append([0.5, 0.5])
    for i in range(1, aneis + 1):
        t = i / aneis
        bojo = 0.004 * (1 - t * t)
        for k in range(lados):
            a_ = 2 * np.pi * k / lados
            c, s_ = np.cos(a_), np.sin(a_)
            ex = np.sign(c) * abs(c) ** 0.7
            ey = np.sign(s_) * abs(s_) ** 0.7
            x, y = ex * meia_l * t, ey * meia_a * t
            P.append(ponto(x, y, -bojo))
            UV.append([0.5 + ex * t * 0.5, 0.5 - ey * t * 0.5])
    F = []
    for k in range(lados):
        F.append([0, 1 + k, 1 + (k + 1) % lados])
    for i in range(aneis - 1):
        b0, b1 = 1 + i * lados, 1 + (i + 1) * lados
        for k in range(lados):
            k1 = (k + 1) % lados
            F += [[b0 + k, b1 + k, b1 + k1], [b0 + k, b1 + k1, b0 + k1]]
    # aro: borda da frente descendo até as costas da placa
    ult = 1 + (aneis - 1) * lados
    base_aro = len(P)
    for k in range(lados):
        x, y, z = P[ult + k]
        a_ = 2 * np.pi * k / lados
        c, s_ = np.cos(a_), np.sin(a_)
        ex = np.sign(c) * abs(c) ** 0.7
        ey = np.sign(s_) * abs(s_) ** 0.7
        P.append(ponto(ex * meia_l, ey * meia_a, esp))
        UV.append([0.5 + ex * 0.49, 0.5 - ey * 0.49])
    for k in range(lados):
        k1 = (k + 1) % lados
        F += [[ult + k, base_aro + k, base_aro + k1], [ult + k, base_aro + k1, ult + k1]]
    # tampa de trás: a placa é uma peça FECHADA
    centro_tras = len(P)
    P.append(ponto(0.0, 0.0, esp))
    UV.append([0.5, 0.5])
    for k in range(lados):
        k1 = (k + 1) % lados
        F.append([centro_tras, base_aro + k1, base_aro + k])
    P = np.array(P, np.float32)
    F = np.array(F, np.uint32)
    # frente virada para fora: confere o sentido pelo primeiro triângulo
    n0 = np.cross(P[F[0, 1]] - P[F[0, 0]], P[F[0, 2]] - P[F[0, 0]])
    if n0[2] < 0:
        F = F[:, ::-1].copy()
    n = normais(P.astype(np.float64), F.astype(np.int64)).astype(np.float32)
    jj, ww = pesos_de(P)
    return P, F, n, np.array(UV, np.float32), jj, ww


# ---------------------------------------------------------- subdivisão
def subdividir(v, f, fuv, uv, canais=()):
    """Subdivisão Loop uma vez: 4 triângulos por triângulo, superfície
    alisada. Os canais (pesos, expressões...) passam pela mesma conta
    linear que as posições, e o UV é dividido por face (as costuras do
    mapa continuam costuras)."""
    import scipy.sparse as sp
    nv = len(v)
    arestas = np.sort(np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]]), axis=1)
    unicas, inv, conta = np.unique(arestas, axis=0, return_inverse=True, return_counts=True)
    inv = inv.reshape(3, -1).T                    # aresta de cada lado de cada face
    ne = len(unicas)
    borda_aresta = conta == 1
    borda_v = np.zeros(nv, bool)
    borda_v[unicas[borda_aresta].ravel()] = True
    linhas, cols, vals = [], [], []
    # para cada face e lado, o vértice oposto (regra 3/8 - 1/8)
    opo = np.stack([f[:, 2], f[:, 0], f[:, 1]], 1)   # oposto às arestas (0,1),(1,2),(2,0)
    e_ids = inv.ravel()
    o_ids = opo.ravel()
    # aresta interna: 3/8 (a+b) + 1/8 (c+d); de borda: 1/2 (a+b)
    ea, eb = unicas[:, 0], unicas[:, 1]
    peso_ab = np.where(borda_aresta, 0.5, 0.375)
    linhas += [nv + np.arange(ne), nv + np.arange(ne)]
    cols += [ea, eb]
    vals += [peso_ab, peso_ab]
    interna = ~borda_aresta[e_ids]
    linhas.append(nv + e_ids[interna])
    cols.append(o_ids[interna])
    vals.append(np.full(interna.sum(), 0.125))
    # vértices originais
    viz = sp.coo_matrix((np.ones(len(ea) * 2), (np.concatenate([ea, eb]), np.concatenate([eb, ea]))),
                        shape=(nv, nv)).tocsr()
    grau = np.asarray(viz.sum(1)).ravel()
    beta = np.where(grau > 3, 3.0 / (8.0 * np.maximum(grau, 1)), 3.0 / 16.0)
    interno = ~borda_v
    viz_i = viz.tocoo()
    m = interno[viz_i.row]
    linhas.append(viz_i.row[m])
    cols.append(viz_i.col[m])
    vals.append(beta[viz_i.row[m]])
    linhas.append(np.nonzero(interno)[0])
    cols.append(np.nonzero(interno)[0])
    vals.append(1.0 - grau[interno] * beta[interno])
    # vértice de borda: 3/4 v + 1/8 dos dois vizinhos de borda
    vb = sp.coo_matrix((np.ones(borda_aresta.sum() * 2),
                        (np.concatenate([ea[borda_aresta], eb[borda_aresta]]),
                         np.concatenate([eb[borda_aresta], ea[borda_aresta]]))), shape=(nv, nv)).tocoo()
    linhas.append(vb.row)
    cols.append(vb.col)
    vals.append(np.full(len(vb.row), 0.125))
    idx_b = np.nonzero(borda_v)[0]
    linhas.append(idx_b)
    cols.append(idx_b)
    vals.append(np.full(len(idx_b), 0.75))
    S = sp.coo_matrix((np.concatenate(vals), (np.concatenate(linhas), np.concatenate(cols))),
                      shape=(nv + ne, nv)).tocsr()
    novo_v = S @ v
    saida = [S @ c if c.ndim == 2 else S @ c for c in canais]
    # faces novas
    e01, e12, e20 = nv + inv[:, 0], nv + inv[:, 1], nv + inv[:, 2]
    a, b, c = f[:, 0], f[:, 1], f[:, 2]
    nf = np.concatenate([np.stack([a, e01, e20], 1), np.stack([e01, b, e12], 1),
                         np.stack([e20, e12, c], 1), np.stack([e01, e12, e20], 1)])
    # UV: pontos médios das arestas do MAPA (por face)
    ua = np.sort(np.concatenate([fuv[:, [0, 1]], fuv[:, [1, 2]], fuv[:, [2, 0]]]), axis=1)
    uu, uinv = np.unique(ua, axis=0, return_inverse=True)
    uinv = uinv.reshape(3, -1).T
    nuv = len(uv)
    novo_uv = np.concatenate([uv, (uv[uu[:, 0]] + uv[uu[:, 1]]) * 0.5])
    t01, t12, t20 = nuv + uinv[:, 0], nuv + uinv[:, 1], nuv + uinv[:, 2]
    ta, tb, tc = fuv[:, 0], fuv[:, 1], fuv[:, 2]
    nfuv = np.concatenate([np.stack([ta, t01, t20], 1), np.stack([t01, tb, t12], 1),
                           np.stack([t20, t12, tc], 1), np.stack([t01, t12, t20], 1)])
    return novo_v, nf, nfuv, novo_uv, saida


# ------------------------------------------------------------------ glb
class Glb:
    """Escritor mínimo de glTF binário: malhas com pele, imagens, materiais."""

    def __init__(self):
        self.bin = bytearray()
        self.j = {"asset": {"version": "2.0", "generator": "gerar_boxeador.py"},
                  "buffers": [], "bufferViews": [], "accessors": [], "meshes": [],
                  "nodes": [], "skins": [], "materials": [], "images": [], "textures": [],
                  "samplers": [{"magFilter": 9729, "minFilter": 9987}],
                  "scenes": [{"nodes": []}], "scene": 0}

    def _vista(self, dados: bytes, alvo=None) -> int:
        while len(self.bin) % 4:
            self.bin += b"\0"
        vista = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(dados)}
        if alvo:
            vista["target"] = alvo
        self.bin += dados
        self.j["bufferViews"].append(vista)
        return len(self.j["bufferViews"]) - 1

    def acessor(self, arr: np.ndarray, tipo: str, alvo=None, minmax=False) -> int:
        comp = {np.float32: 5126, np.uint32: 5125, np.uint16: 5123, np.uint8: 5121}[arr.dtype.type]
        vista = self._vista(np.ascontiguousarray(arr).tobytes(), alvo)
        a = {"bufferView": vista, "componentType": comp, "count": int(arr.shape[0]), "type": tipo}
        if minmax:
            a["min"] = [float(x) for x in arr.min(0)]
            a["max"] = [float(x) for x in arr.max(0)]
        self.j["accessors"].append(a)
        return len(self.j["accessors"]) - 1

    def imagem(self, img: Image.Image, formato="PNG") -> int:
        buf = io.BytesIO()
        if formato == "JPEG":
            img.convert("RGB").save(buf, "JPEG", quality=93, subsampling=0)
            mime = "image/jpeg"
        else:
            img.save(buf, "PNG", optimize=True)
            mime = "image/png"
        vista = self._vista(buf.getvalue())
        self.j["images"].append({"bufferView": vista, "mimeType": mime})
        self.j["textures"].append({"source": len(self.j["images"]) - 1, "sampler": 0})
        return len(self.j["textures"]) - 1

    def material(self, **m) -> int:
        self.j["materials"].append(m)
        return len(self.j["materials"]) - 1

    def malha(self, nome, pos, nrm, ind, material, uv=None, tan=None, cor=None, juntas=None, pesos=None,
              alvos=None, nomes_alvos=None) -> int:
        at = {"POSITION": self.acessor(pos.astype(np.float32), "VEC3", 34962, True),
              "NORMAL": self.acessor(nrm.astype(np.float32), "VEC3", 34962)}
        if uv is not None:
            at["TEXCOORD_0"] = self.acessor(uv.astype(np.float32), "VEC2", 34962)
        if tan is not None:
            at["TANGENT"] = self.acessor(tan.astype(np.float32), "VEC4", 34962)
        if cor is not None:
            at["COLOR_0"] = self.acessor(cor.astype(np.float32), "VEC3", 34962)
        if juntas is not None:
            at["JOINTS_0"] = self.acessor(juntas.astype(np.uint16), "VEC4", 34962)
            at["WEIGHTS_0"] = self.acessor(pesos.astype(np.float32), "VEC4", 34962)
        idx = self.acessor(ind.reshape(-1).astype(np.uint32), "SCALAR", 34963)
        prim = {"attributes": at, "indices": idx, "material": material}
        malha = {"name": nome, "primitives": [prim]}
        if alvos is not None:
            prim["targets"] = [{"POSITION": self.acessor(a.astype(np.float32), "VEC3", 34962, True)}
                               for a in alvos]
            malha["weights"] = [0.0] * len(alvos)
            malha["extras"] = {"targetNames": list(nomes_alvos)}
        self.j["meshes"].append(malha)
        return len(self.j["meshes"]) - 1

    def no(self, **n) -> int:
        self.j["nodes"].append(n)
        return len(self.j["nodes"]) - 1

    def salvar(self, caminho: Path):
        while len(self.bin) % 4:
            self.bin += b"\0"
        self.j["buffers"] = [{"byteLength": len(self.bin)}]
        js = json.dumps(self.j, separators=(",", ":")).encode()
        while len(js) % 4:
            js += b" "
        with open(caminho, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(self.bin)))
            f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
            f.write(struct.pack("<II", len(self.bin), 0x004E4942) + bytes(self.bin))
        print("ok", caminho, round((12 + 16 + len(js) + len(self.bin)) / 1e6, 1), "MB")


def separar_uv(f: np.ndarray, fuv: np.ndarray):
    """glTF quer um UV por vértice: duplica os vértices das costuras."""
    par = f.astype(np.int64) * 1_000_003 + fuv.astype(np.int64)
    unicos, inv = np.unique(par.ravel(), return_inverse=True)
    vi = (unicos // 1_000_003).astype(np.int64)
    ti = (unicos % 1_000_003).astype(np.int64)
    return vi, ti, inv.reshape(f.shape).astype(np.uint32)


def tangentes(p, n, uv, f):
    t = np.zeros_like(p)
    b = np.zeros_like(p)
    e1, e2 = p[f[:, 1]] - p[f[:, 0]], p[f[:, 2]] - p[f[:, 0]]
    d1, d2 = uv[f[:, 1]] - uv[f[:, 0]], uv[f[:, 2]] - uv[f[:, 0]]
    r = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]
    r = np.where(np.abs(r) < 1e-12, 1e-12, r)
    ft = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) / r[:, None]
    fb = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) / r[:, None]
    for k in range(3):
        np.add.at(t, f[:, k], ft)
        np.add.at(b, f[:, k], fb)
    t = t - n * np.einsum("ij,ij->i", n, t)[:, None]
    t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-9)
    w = np.where(np.einsum("ij,ij->i", np.cross(n, t), b) < 0, -1.0, 1.0)
    return np.concatenate([t, w[:, None]], 1).astype(np.float32)


def suave(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def ao_longo(p, a, b):
    """Parâmetro de p ao longo do segmento a->b (0 em a, 1 em b)."""
    ab = b - a
    return ((p - a) @ ab) / ab.dot(ab)


def preparar():
    d = corpo()
    v = para_gltf(d["verts"]).astype(np.float64)
    f = d["faces"].astype(np.int64)
    uv = d["uv"].astype(np.float64).copy()
    uv[:, 1] = 1.0 - uv[:, 1]
    pos, w = montar_esqueleto(d, v)
    # Pés no chão, bacia sobre a origem.
    desloc = np.array([-pos[NOMES.index("Hips")][0], -v[:, 1].min(), -pos[NOMES.index("Hips")][2]])
    v += desloc
    pos = pos + desloc
    dono = np.argmax(w, 1)
    return d, v, f, uv, pos, w, dono


def regioes(v, pos, w, dono):
    i = NOMES.index
    y = v[:, 1]
    r = {}
    # CALÇÃO: da cintura (um palmo acima da bacia) até meia coxa.
    cintura = pos[i("Hips")][1] + 0.105
    coxa = np.zeros(len(v))
    for lado in ("Left", "Right"):
        t = ao_longo(v, pos[i(f"{lado}UpLeg")], pos[i(f"{lado}Leg")])
        eh = (dono == i(f"{lado}UpLeg")) | (dono == i(f"{lado}Leg"))
        coxa = np.where(eh, t, coxa)
    tronco_baixo = np.isin(dono, [i("Hips"), i("Spine"), i("Spine1")]) & (y < cintura)
    pernas = np.isin(dono, [i("LeftUpLeg"), i("RightUpLeg"), i("LeftLeg"), i("RightLeg")])
    r["coxa_t"] = coxa
    r["calcao"] = tronco_baixo | (pernas & (coxa < 0.46) & (y < cintura))
    # BOTA: pé inteiro e o terço de baixo da canela.
    canela = np.zeros(len(v))
    for lado in ("Left", "Right"):
        t = ao_longo(v, pos[i(f"{lado}Leg")], pos[i(f"{lado}Foot")])
        canela = np.where(np.isin(dono, [i(f"{lado}Leg"), i(f"{lado}Foot"), i(f"{lado}ToeBase")]), t, canela)
    r["canela_t"] = canela
    pes = np.isin(dono, [i("LeftFoot"), i("RightFoot"), i("LeftToeBase"), i("RightToeBase")])
    r["bota"] = pes | (np.isin(dono, [i("LeftLeg"), i("RightLeg")]) & (canela > 0.60))
    r["mao"] = np.isin(dono, [i("LeftHand"), i("RightHand")])
    r["cintura"] = cintura
    return r


def anel(mascara, f, vezes=1):
    """Encolhe a máscara em `vezes` anéis de vizinhos."""
    m = mascara.copy()
    for _ in range(vezes):
        fora = ~m[f].all(1)
        m[np.unique(f[fora])] = False
    return m


def segmentacao():
    """O mapa de partes do Anny (boca por dentro, língua...) no espaço UV.

    ANNY_DADOS aponta para a pasta `anny/data` de um pacote descompactado:
    assim dá para regerar o modelo (com o corpo em cache) sem torch."""
    import os
    if os.environ.get("ANNY_DADOS"):
        return str(Path(os.environ["ANNY_DADOS"]) / "segmentation" / "body_parts_segmentation.png")
    import anny
    return str(Path(anny.__file__).parent / "data" / "segmentation" / "body_parts_segmentation.png")


def contexto(d, v, f, uv, fuv, n, r, pos, w, a, grau, cab, rot):
    """Pontos de referência do rosto e do corpo para a pintura."""
    i = NOMES.index
    cabeca = w[:, i("Head")]
    base = d["base_idx"]
    olho = (base >= 14598) & (base <= 14741)
    c = curvatura(v, f, a, grau, n)
    for _ in range(2):
        c = (a @ c) / grau
    olho_v = v[olho & (v[:, 0] > 0)]
    olho_c = olho_v.mean(0)
    raio_olho = float(np.linalg.norm(olho_v - olho_c, axis=1).mean())
    pele = ~olho & (cabeca > 0.5)

    def superficie(x, y, raio=0.012, frente=True):
        cand = pele & (np.abs(v[:, 0] - x) < raio) & (np.abs(v[:, 1] - y) < raio)
        if not cand.any():
            cand = pele
        k = np.argmax(np.where(cand, v[:, 2], -9)) if frente else np.argmin(np.where(cand, v[:, 2], 9))
        return v[k].copy()

    boca_y = (cab[rot.index("oris01")][1] + cab[rot.index("oris05")][1]) * 0.5
    boca = superficie(0.0, boca_y, 0.006)
    nariz = v[np.argmax(np.where(pele, v[:, 2], -9))]
    orelha_cand = pele & (v[:, 0] > 0) & (np.abs(v[:, 1] - (olho_c[1] - 0.02)) < 0.03)
    xs = np.where(orelha_cand, v[:, 0], -9)
    topo = np.argsort(-xs)[:30]
    orelha = v[topo].mean(0)
    altura = v[:, 1].max()
    torso = (w[:, i("Spine2")] + w[:, i("Spine1")]) > 0.5
    mam_y = altura * 0.728
    cand = torso & (np.abs(v[:, 0] - 0.095) < 0.015) & (np.abs(v[:, 1] - mam_y) < 0.015)
    mamilo = v[np.argmax(np.where(cand, v[:, 2], -9))] if cand.any() else np.array([0.095, mam_y, 0.1])
    cranio = pele & (v[:, 1] > olho_c[1])
    centro = np.array([0.0, olho_c[1] + 0.01, (v[cranio, 2].max() + v[cranio, 2].min()) * 0.5])
    pontos = dict(
        olho=olho_c.astype(np.float32), raio_olho=raio_olho, boca=boca.astype(np.float32),
        nariz=nariz.astype(np.float32), orelha=orelha.astype(np.float32),
        bochecha=superficie(olho_c[0] + 0.012, olho_c[1] - 0.035).astype(np.float32),
        mamilo=mamilo.astype(np.float32), queixo=superficie(0.0, boca[1] - 0.045, 0.008).astype(np.float32),
        maca_y=float(olho_c[1] - 0.022), centro_cabeca=centro.astype(np.float32),
        # linha do cabelo mais baixa: o cabelo vem para a frente da testa
        testa_y=float(olho_c[1] + 0.058),
    )
    roupa = r["calcao"][f].all(1) | r["bota"][f].all(1)
    fecha = para_gltf(d["expressoes"][list(EXPRESSOES).index("apagado")])
    palpebra = (np.linalg.norm(fecha, axis=1) > 0.0015) & (cabeca > 0.5) & (v[:, 1] > olho_c[1] - 0.02)
    return dict(palpebra=palpebra.astype(np.float32),v=v.astype(np.float32), f=f, uv=uv, fuv=fuv, n=n.astype(np.float32),
                cavidade=c.astype(np.float32), olho=olho, peso_cabeca=cabeca.astype(np.float32),
                ossos={k: pos[i(k)].astype(np.float32) for k in NOMES}, pontos=pontos,
                tri_pele=np.arange(len(f)), tri_roupa=np.nonzero(roupa)[0], regioes=r,
                pe_x=float(pos[i("LeftToeBase")][0]), fonte=FONTE, segmentacao=segmentacao())


def construir(pintar=True):
    d, v, f, uv, pos, w, dono = preparar()
    r = regioes(v, pos, w, dono)
    fuv = d["face_uv"].astype(np.int64)
    n = normais(v, f)
    a, grau = vizinhos(len(v), f)
    juntas, pesos = top4(w)
    glb = Glb()

    # ---- esqueleto: nós com rotação identidade, só translação.
    pais = {o[0]: o[1] for o in OSSOS}
    nos = {}
    for nome in NOMES:
        pai = pais[nome]
        t = pos[NOMES.index(nome)] - (pos[NOMES.index(pai)] if pai else 0)
        nos[nome] = glb.no(name="mixamorig:" + nome, translation=[float(x) for x in t])
    for nome in NOMES:
        filhos = [nos[o] for o in NOMES if pais[o] == nome]
        if filhos:
            glb.j["nodes"][nos[nome]]["children"] = filhos
    ibm = np.zeros((len(NOMES), 4, 4), np.float32)
    for k in range(len(NOMES)):
        m = np.eye(4, dtype=np.float32)
        m[:3, 3] = -pos[k]
        ibm[k] = m.T  # glTF: coluna-maior
    ibm_acc = glb.acessor(ibm.reshape(-1, 16), "MAT4")
    glb.j["skins"].append({"joints": [nos[x] for x in NOMES], "inverseBindMatrices": ibm_acc,
                           "skeleton": nos["Hips"]})

    # ---- texturas
    rot = [str(x) for x in d["labels"]]
    desloc = pos[NOMES.index("LeftArm")] - para_gltf(d["heads"])[rot.index("upperarm01.L")]
    cab = para_gltf(d["heads"]) + desloc
    ctx_pontos = contexto(d, v, f, uv, fuv, n, r, pos, w, a, grau, cab, rot)["pontos"]
    if pintar:
        from pintura import pintar_pele, pintar_roupa
        ctx = contexto(d, v, f, uv, fuv, n, r, pos, w, a, grau, cab, rot)
        ctx_pontos = ctx["pontos"]
        img_pele, img_relevo = pintar_pele(ctx, TEX_PELE)
        img_roupa = pintar_roupa(ctx, TEX_ROUPA)
        img_pele.save(Path(__file__).resolve().parent / ".previa_pele.jpg", quality=90)
        img_roupa.save(Path(__file__).resolve().parent / ".previa_roupa.jpg", quality=90)
    mat_pele = glb.material(name="Pele", pbrMetallicRoughness={
        "baseColorFactor": [0.62, 0.43, 0.32, 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.62})
    mat_roupa = glb.material(name="Roupa", pbrMetallicRoughness={
        "baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.38})
    mat_luva = glb.material(name="Luva", pbrMetallicRoughness={
        "baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.26})
    mat_bota = glb.material(name="Bota", pbrMetallicRoughness={
        "baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.34})
    mat_cinto = glb.material(name="Cinturao", pbrMetallicRoughness={
        "baseColorTexture": {"index": glb.imagem(textura_do_cinturao(), "JPEG")},
        "baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.15, "roughnessFactor": 0.40})
    mat_cabelo = glb.material(name="Cabelo", pbrMetallicRoughness={
        "baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.55})
    mat_placa = glb.material(name="Placa", pbrMetallicRoughness={
        "baseColorTexture": {"index": glb.imagem(textura_da_placa(), "JPEG")},
        "baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.35, "roughnessFactor": 0.22})
    if pintar:
        tp = glb.imagem(img_pele, "JPEG")
        tn = glb.imagem(img_relevo, "PNG")
        tr = glb.imagem(img_roupa, "JPEG")
        glb.j["materials"][mat_pele]["pbrMetallicRoughness"]["baseColorTexture"] = {"index": tp}
        glb.j["materials"][mat_pele]["pbrMetallicRoughness"]["baseColorFactor"] = [1, 1, 1, 1]
        glb.j["materials"][mat_pele]["normalTexture"] = {"index": tn, "scale": 0.8}
        glb.j["materials"][mat_roupa]["pbrMetallicRoughness"]["baseColorTexture"] = {"index": tr}

    malhas = []
    # ---- pele: sem as mãos (vão dentro da luva) e sem o que a roupa cobre.
    escondido = anel(r["calcao"], f, 2) | r["bota"] | r["mao"]
    tri = ~(escondido[f].all(1) | r["mao"][f].any(1))
    fp, fuvp = f[tri], fuv[tri]
    # MAIS DEFINIÇÃO: uma subdivisão Loop do corpo (4x os triângulos),
    # com pesos e expressões passando pela mesma conta.
    expr = para_gltf(d["expressoes"])            # (E, V, 3)
    ne_ = expr.shape[0]
    canal_expr = np.transpose(expr, (1, 0, 2)).reshape(len(v), -1)
    if SUBDIVIDIR:
        v2, f2, fuv2, uv2, (w2, e2) = subdividir(v, fp, fuvp, uv, canais=(w, canal_expr))
    else:
        v2, f2, fuv2, uv2, w2, e2 = v, fp, fuvp, uv, w, canal_expr
    n2 = normais(v2, f2)
    vi, ti, ind = separar_uv(f2, fuv2)
    p = v2[vi]
    nn = n2[vi]
    uu = uv2[ti]
    tan = tangentes(p, nn, uu, ind)
    j2, p2_ = top4(np.asarray(w2)[vi])
    alvos = np.transpose(np.asarray(e2)[vi].reshape(len(vi), ne_, 3), (1, 0, 2))
    print("pele:", len(p), "vértices,", len(ind), "triângulos")
    malhas.append(("Pele", glb.malha("Pele", p, nn, ind, mat_pele, uv=uu, tan=tan,
                                      juntas=j2, pesos=p2_,
                                      alvos=alvos, nomes_alvos=list(EXPRESSOES))))

    # ---- calção e botas: cascas alisadas, afastadas da pele.
    y = v[:, 1]
    folga = 0.011 + 0.022 * suave(0.18, 0.46, r["coxa_t"]) + 0.004 * suave(r["cintura"] - 0.04, r["cintura"], y)
    folga += 0.006 * suave(0.2, 0.0, np.abs(v[:, 0]))  # cavalo mais folgado
    cv, ci, usados, cb = casca(v, f, n, r["calcao"], folga, a, grau, alisa=10)

    # BAINHA RETA: a borda da casca vai exatamente para a linha do corte
    # (sem o serrilhado dos triângulos).
    I = NOMES.index
    for lado in ("Left", "Right"):
        a0, b0 = pos[I(f"{lado}UpLeg")], pos[I(f"{lado}Leg")]
        ab = b0 - a0
        perna = cb & (r["coxa_t"] > 0.25) & (np.sign(v[:, 0]) == np.sign(a0[0]))
        t = ao_longo(cv[perna], a0, b0)
        cv[perna] += np.outer(0.47 - t, ab)
    cintura = cb & (v[:, 1] > r["cintura"] - 0.05)
    cv[cintura, 1] = r["cintura"] + 0.004
    fechar_cavalo(cv, usados, pos)
    cv = cv[usados]
    for nome, vv, ii, us in (("Calcao", cv, ci, usados),):
        tri_mask = np.isin(f, us).all(1) & r["calcao"][f].all(1)
        fuv_c = fuv[tri_mask]
        vi2, ti2, ind2 = separar_uv(ii, fuv_c)
        p2 = vv[vi2]
        n2 = normais(vv, ii)[vi2]
        u2 = uv[ti2]
        orig = us[vi2]
        malhas.append((nome, glb.malha(nome, p2, n2, ind2, mat_roupa, uv=u2,
                                        juntas=juntas[orig], pesos=pesos[orig])))

    # ---- friso dourado da bainha: faixa de verdade, seguindo a borda.
    fv, fn_, ff, fc, fj, fw = friso(cv, ci, n[usados], juntas[usados], pesos[usados], pos, r, v[usados])
    if len(ff):
        malhas.append(("Friso", glb.malha("Friso", fv, fn_, ff, mat_luva, cor=fc, juntas=fj, pesos=fw)))

    # ---- o cinturão (cós acolchoado) e as botas: peças próprias.
    from scipy.spatial import cKDTree
    arvore = cKDTree(v)

    def pesos_de(P):
        _, idx = arvore.query(P, k=4)
        ww_ = w[idx].mean(1)
        return top4(ww_)

    cp, cf, cn, cuv, cj, cw = cinturao(cv, r["cintura"], pesos_de)
    malhas.append(("Cinturao", glb.malha("Cinturao", cp, cn, cf, mat_cinto, uv=cuv, juntas=cj, pesos=cw)))
    pp, pf, pn, puv, pj, pw = placa_do_cinturao(cp, r["cintura"], pesos_de)
    malhas.append(("Placa", glb.malha("Placa", pp, pn, pf, mat_placa, uv=puv, juntas=pj, pesos=pw)))
    for lado in ("Left", "Right"):
        bp, bf, bn, bc, bw, _ = bota(pos, lado)
        bj, bw4 = top4(bw)
        malhas.append((f"Bota{lado}", glb.malha(f"Bota{lado}", bp, bn, bf, mat_bota, cor=bc, juntas=bj, pesos=bw4)))

    # ---- dentes de cima: só aparecem com a boca aberta (grito, dor).
    dv, df_, dn, dc = dentes(ctx_pontos)
    k = NOMES.index("Head")
    jj = np.zeros((len(dv), 4), np.uint16); jj[:, 0] = k
    ww = np.zeros((len(dv), 4), np.float32); ww[:, 0] = 1
    malhas.append(("Dentes", glb.malha("Dentes", dv, dn, df_, mat_luva, cor=dc, juntas=jj, pesos=ww)))

    # ---- cabelo espetado, preso à cabeça
    hv, hf, hn, hc = cabelo(v, n, f, w, ctx_pontos)
    print("cabelo:", len(hv), "vértices")
    k = NOMES.index("Head")
    jj = np.zeros((len(hv), 4), np.uint16); jj[:, 0] = k
    ww = np.zeros((len(hv), 4), np.float32); ww[:, 0] = 1
    malhas.append(("Cabelo", glb.malha("Cabelo", hv, hn, hf, mat_cabelo, cor=hc, juntas=jj, pesos=ww)))

    # ---- luvas
    for lado, s in (("Left", "L"), ("Right", "R")):
        pulso = cab[rot.index(f"wrist.{s}")]
        junta = cab[rot.index(f"finger3-1.{s}")]
        dedao = cab[rot.index(f"finger1-2.{s}")]
        medial = np.array([-np.sign(pulso[0]), 0.0, 0.0])
        cotovelo = cab[rot.index(f"lowerarm01.{s}")]
        lv, lf, ln, lc = luva(pulso, junta, dedao, medial, s, pulso - cotovelo)
        k = NOMES.index(f"{lado}Hand")
        jj = np.zeros((len(lv), 4), np.uint16)
        jj[:, 0] = k
        ww = np.zeros((len(lv), 4), np.float32)
        ww[:, 0] = 1
        malhas.append((f"Luva{lado}", glb.malha(f"Luva{lado}", lv, ln, lf, mat_luva, cor=lc,
                                                 juntas=jj, pesos=ww)))

    raiz = glb.no(name="Boxeador", children=[nos["Hips"]])
    for nome, m in malhas:
        glb.j["nodes"][raiz]["children"].append(glb.no(name=nome, mesh=m, skin=0))
    glb.j["scenes"][0]["nodes"] = [raiz]
    glb.salvar(SAIDA)


if __name__ == "__main__":
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    construir(pintar="--sem-textura" not in sys.argv)
