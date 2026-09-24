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

TEX_PELE = 4096
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
    fenotipo = dict(gender=1.0, age=0.46, muscle=0.92, weight=0.62, height=0.62, proportions=0.95)
    local = {
        "torso-muscle-pectoral-incr": 0.55, "torso-muscle-dorsi-incr": 0.55,
        "torso-vshape-incr": 0.5, "measure-shoulder-dist-incr": 0.25,
        "l-upperarm-muscle-incr": 0.5, "r-upperarm-muscle-incr": 0.5,
        "l-upperarm-shoulder-muscle-incr": 0.6, "r-upperarm-shoulder-muscle-incr": 0.6,
        "l-lowerarm-muscle-incr": 0.45, "r-lowerarm-muscle-incr": 0.45,
        "l-upperleg-muscle-incr": 0.4, "r-upperleg-muscle-incr": 0.4,
        "l-lowerleg-muscle-incr": 0.4, "r-lowerleg-muscle-incr": 0.4,
        "measure-neck-circ-incr": 0.6, "stomach-tone-incr": 0.2,
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
                C.append([0.88, 0.62, 0.12])
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
def luva(pulso, junta, dedao, palma_n, lado):
    """Luva de boxe por campo de distância: bulbo, polegar e punho."""
    from skimage import measure

    eixo = junta - pulso
    comp = np.linalg.norm(eixo)
    eixo = eixo / comp
    lateral = dedao - pulso
    lateral = lateral - eixo * lateral.dot(eixo)
    lateral /= np.linalg.norm(lateral)
    normal = np.cross(eixo, lateral)
    if normal.dot(palma_n) < 0:
        normal = -normal
    base = np.stack([lateral, normal, eixo], 1)  # colunas: x=polegar, y=palma, z=dedos
    esc = comp / 0.105  # tudo em proporção da mão

    def elipsoide(p, c, r):
        q = (p - c) / r
        k = np.linalg.norm(q, axis=-1)
        return (k - 1.0) * np.min(r)

    def capsula(p, a, b, r):
        pa, ba = p - a, b - a
        t = np.clip((pa @ ba) / ba.dot(ba), 0, 1)
        return np.linalg.norm(pa - t[..., None] * ba, axis=-1) - r

    def uniao(d1, d2, k):
        h = np.clip(0.5 + 0.5 * (d2 - d1) / k, 0, 1)
        return d2 * (1 - h) + d1 * h - k * h * (1 - h)

    res = 0.0052 * esc
    ext = 0.25 * esc
    g = np.arange(-ext, ext + res, res)
    X, Y, Z = np.meshgrid(g, g, g, indexing="ij")
    P = np.stack([X, Y, Z], -1)  # espaço local (polegar, palma, dedos)
    s = esc
    corpo_l = elipsoide(P, np.array([0.0, -0.004, 0.108]) * s, np.array([0.064, 0.057, 0.098]) * s)
    dorso = elipsoide(P, np.array([0.0, -0.018, 0.140]) * s, np.array([0.058, 0.046, 0.066]) * s)
    polegar = capsula(P, np.array([0.056, 0.020, 0.048]) * s, np.array([0.050, 0.032, 0.122]) * s, 0.023 * s)
    cano = capsula(P, np.array([0.0, 0.0, -0.088]) * s, np.array([0.0, 0.0, 0.03]) * s, 0.047 * s)
    d = uniao(corpo_l, dorso, 0.03 * s)
    d = uniao(d, polegar, 0.010 * s)
    d = uniao(d, cano, 0.04 * s)
    verts, faces, nrm, _ = measure.marching_cubes(d, 0.0, spacing=(res, res, res))
    verts = verts - ext
    faces = faces[:, ::-1]
    nrm = -nrm
    # cor por região: punho branco com friso, corpo vermelho, palma mais escura
    loc = verts
    cor = np.tile(np.array([0.78, 0.04, 0.06], np.float32), (len(loc), 1))
    z = loc[:, 2] / s
    cano_m = z < -0.005
    cor[cano_m] = [0.93, 0.93, 0.92]
    friso = (z < -0.030) & (z > -0.046)
    cor[friso] = [0.80, 0.05, 0.07]
    friso2 = (z < -0.062) & (z > -0.072)
    cor[friso2] = [0.80, 0.05, 0.07]
    palma = (loc[:, 1] / s > 0.030) & (z > 0.02)
    cor[palma] = cor[palma] * 0.82
    mundo = loc @ base.T + pulso
    nmundo = nrm @ base.T
    return mundo.astype(np.float32), faces.astype(np.uint32), nmundo.astype(np.float32), cor


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
    r["bota"] = pes | (np.isin(dono, [i("LeftLeg"), i("RightLeg")]) & (canela > 0.74))
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
    """O mapa de partes do Anny (boca por dentro, língua...) no espaço UV."""
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
        testa_y=float(olho_c[1] + 0.074),
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
    escondido = anel(r["calcao"], f, 2) | anel(r["bota"], f, 1) | r["mao"]
    tri = ~(escondido[f].all(1) | r["mao"][f].any(1))
    fp, fuvp = f[tri], fuv[tri]
    vi, ti, ind = separar_uv(fp, fuvp)
    p = v[vi]
    nn = n[vi]
    uu = uv[ti]
    tan = tangentes(p, nn, uu, ind)
    alvos = para_gltf(d["expressoes"])[:, vi]
    malhas.append(("Pele", glb.malha("Pele", p, nn, ind, mat_pele, uv=uu, tan=tan,
                                      juntas=juntas[vi], pesos=pesos[vi],
                                      alvos=alvos, nomes_alvos=list(EXPRESSOES))))

    # ---- calção e botas: cascas alisadas, afastadas da pele.
    y = v[:, 1]
    folga = 0.011 + 0.022 * suave(0.18, 0.46, r["coxa_t"]) + 0.004 * suave(r["cintura"] - 0.04, r["cintura"], y)
    folga += 0.006 * suave(0.2, 0.0, np.abs(v[:, 0]))  # cavalo mais folgado
    cv, ci, usados, cb = casca(v, f, n, r["calcao"], folga, a, grau, alisa=10)
    bota_folga = 0.0065 + 0.008 * np.clip(-n[:, 1], 0, 1) ** 2
    bv, bi, busados, bb = casca(v, f, n, r["bota"], bota_folga, a, grau, alisa=24)
    # BAINHA RETA: a borda da casca vai exatamente para a linha do corte
    # (sem o serrilhado dos triângulos).
    I = NOMES.index
    for lado in ("Left", "Right"):
        a0, b0 = pos[I(f"{lado}UpLeg")], pos[I(f"{lado}Leg")]
        ab = b0 - a0
        perna = cb & (r["coxa_t"] > 0.25) & (np.sign(v[:, 0]) == np.sign(a0[0]))
        t = ao_longo(cv[perna], a0, b0)
        cv[perna] += np.outer(0.47 - t, ab)
        a1, b1 = pos[I(f"{lado}Leg")], pos[I(f"{lado}Foot")]
        ab1 = b1 - a1
        cano = bb & (r["canela_t"] > 0.5) & (v[:, 1] > 0.12) & (np.sign(v[:, 0]) == np.sign(a1[0]))
        t = ao_longo(bv[cano], a1, b1)
        bv[cano] += np.outer(0.745 - t, ab1)
    cintura = cb & (v[:, 1] > r["cintura"] - 0.05)
    cv[cintura, 1] = r["cintura"] + 0.004
    cv, bv = cv[usados], bv[busados]
    for nome, vv, ii, us in (("Calcao", cv, ci, usados), ("Botas", bv, bi, busados)):
        tri_mask = np.isin(f, us).all(1) & (r["calcao"] if nome == "Calcao" else r["bota"])[f].all(1)
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

    # ---- dentes de cima: só aparecem com a boca aberta (grito, dor).
    dv, df_, dn, dc = dentes(ctx_pontos)
    k = NOMES.index("Head")
    jj = np.zeros((len(dv), 4), np.uint16); jj[:, 0] = k
    ww = np.zeros((len(dv), 4), np.float32); ww[:, 0] = 1
    malhas.append(("Dentes", glb.malha("Dentes", dv, dn, df_, mat_luva, cor=dc, juntas=jj, pesos=ww)))

    # ---- luvas
    for lado, s in (("Left", "L"), ("Right", "R")):
        pulso = cab[rot.index(f"wrist.{s}")]
        junta = cab[rot.index(f"finger3-1.{s}")]
        dedao = cab[rot.index(f"finger1-2.{s}")]
        medial = np.array([-np.sign(pulso[0]), 0.0, 0.0])
        lv, lf, ln, lc = luva(pulso, junta, dedao, medial, s)
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
