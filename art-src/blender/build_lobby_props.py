"""Mushroom Guardians - lobby props (Guardians' Glade). Run: python build_lobby_props.py
or: blender -b -P build_lobby_props.py.  1 unit = 1 stud, Z up, origin on ground, front = -Y."""
import bpy, bmesh, math, os, random, sys
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
OUT_BLEND = os.path.join(HERE, "lobby_props.blend")
EXPORT_DIR = os.path.join(HERE, "export")
PREVIEW_DIR = os.path.join(HERE, "preview")
RENDER_PREVIEWS = True
SEED = 1337

# ---- palette (sRGB 0-255) ----
C = dict(
    wood=(72, 56, 44), cap_red=(190, 52, 44), cream=(244, 240, 228), amber=(255, 214, 120),
    stone=(112, 118, 112), dark_stone=(70, 78, 72), rune=(120, 230, 200), shelf=(226, 170, 70),
    moss=(86, 132, 74), portal=(150, 90, 230), statue=(150, 152, 146), glow_blue=(120, 170, 220),
    stem=(232, 222, 198), parchment=(236, 226, 196), roof=(96, 70, 52), iron=(50, 52, 56),
)
REGIONS = {
    "Mushroomhaven": (190, 52, 44), "EmeraldForest": (70, 170, 90), "MistySporeSwamps": (120, 140, 90),
    "CrystalCaves": (140, 225, 255), "AshGardens": (255, 140, 50), "SkyIslands": (214, 236, 245),
    "EclipseCitadel": (150, 90, 230),
}
# per-prop sizes (studs)
LANTERN_H = 9.0
GATE_W, GATE_H, GATE_D = 18.0, 20.0, 5.0
STATUE_H, PLINTH_H = 14.0, 3.0
RING_R, RING_DISC_R, RING_DISC_H = 12.0, 10.0, 0.4
BOARD_W, BOARD_H = 8.0, 9.0
STONE_W, STONE_H = 3.0, 5.0

_mats = {}
def lin(c):
    f = lambda v: (v / 255.0) ** 2.2
    return (f(c[0]), f(c[1]), f(c[2]), 1.0)

def mat(name, rgb, emit=0.0):
    key = (name, rgb, emit)
    if key in _mats: return _mats[key]
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = lin(rgb)
    b.inputs["Roughness"].default_value = 0.9
    m.diffuse_color = lin(rgb)
    if emit > 0:
        b.inputs["Emission Color"].default_value = lin(rgb)
        b.inputs["Emission Strength"].default_value = emit
    _mats[key] = m
    return m

class Prop:
    def __init__(self, name):
        self.name = name
        self.col = bpy.data.collections.new(name); bpy.context.scene.collection.children.link(self.col)
        self.root = bpy.data.objects.new(name, None); self.col.objects.link(self.root)
        self.n = 0
    def _finish(self, o, m, smooth=False):
        bpy.context.view_layer.objects.active = o; o.select_set(True)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        o.select_set(False)
        for c in list(o.users_collection): c.objects.unlink(o)
        self.col.objects.link(o)
        o.parent = self.root
        o.data.materials.append(m)
        for p in o.data.polygons: p.use_smooth = smooth
        self.n += 1
        o.name = f"{self.name}_{o.name.split('.')[0]}_{self.n:02d}"
        return o
    def box(self, loc, size, m, rot=(0, 0, 0), nm="Block"):
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
        o = bpy.context.object; o.scale = size; o.name = nm
        return self._finish(o, m)
    def cyl(self, loc, r, h, m, verts=8, rot=(0, 0, 0), r2=None, nm="Cyl", scale=(1, 1, 1)):
        if r2 is None: r2 = r
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=h, location=loc, rotation=rot)
        o = bpy.context.object; o.scale = scale; o.name = nm
        return self._finish(o, m)
    def sph(self, loc, size, m, seg=10, rings=6, rot=(0, 0, 0), nm="Blob", smooth=True):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=1, location=loc, rotation=rot)
        o = bpy.context.object; o.scale = size; o.name = nm
        return self._finish(o, m, smooth)
    def torus(self, loc, R, r, m, rot=(0, 0, 0), seg=24, nm="Ring"):
        bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=seg, minor_segments=6, location=loc, rotation=rot)
        o = bpy.context.object; o.name = nm
        return self._finish(o, m)

def mushroom(p, loc, stem_h, stem_r, cap_r, cap_h, capm, stemm=None, spots=0, rng=None, tilt=0.0):
    stemm = stemm or mat("Stem", C["stem"])
    x, y, z = loc
    p.cyl((x, y, z + stem_h / 2), stem_r, stem_h, stemm, verts=8, r2=stem_r * 0.8, nm="MushStem")
    p.sph((x, y, z + stem_h), (cap_r, cap_r, cap_h), capm, seg=12, rings=6, nm="MushCap")
    if spots and rng:
        for _ in range(spots):
            a = rng.uniform(0, 2 * math.pi); t = rng.uniform(0.15, 0.6)
            sx = x + math.cos(a) * cap_r * 0.75 * (1 - t * 0.3) * (1 - t * 0.5)
            sy = y + math.sin(a) * cap_r * 0.75 * (1 - t * 0.3) * (1 - t * 0.5)
            sz = z + stem_h + cap_h * math.sqrt(max(0.05, 1 - (0.75 * (1 - t * 0.5)) ** 2)) * 0.97
            p.sph((sx, sy, sz), (cap_r * .14,) * 2 + (cap_r * .06,), mat("Spot", C["cream"]), seg=6, rings=4, nm="Spot")

def arc(p, center, R, a0, a1, thick, depth, m, steps=8, plane="XZ", nm="Arc"):
    for i in range(steps):
        t0 = a0 + (a1 - a0) * i / steps; t1 = a0 + (a1 - a0) * (i + 1) / steps
        tm = (t0 + t1) / 2
        ln = R * abs(t1 - t0) * 1.15
        cx, cz = center[0] + R * math.cos(tm), center[2] + R * math.sin(tm)
        p.box((cx, center[1], cz), (ln, depth, thick), m, rot=(0, -tm + math.pi / 2, 0), nm=nm)

# ================= props =================
def build_spore_lantern(rng):
    p = Prop("Build_Lobby_SporeLantern"); wood = mat("Wood", C["wood"])
    lean = 0.07
    p.box((0, 0, 4.2), (0.6, 0.6, 8.4), wood, rot=(0, lean, 0), nm="Post")
    p.box((0.55, 0, 8.3), (0.5, 0.5, 0.5), wood, nm="PostCap")
    p.box((1.9, 0, 8.0), (4.2, 0.35, 0.35), wood, rot=(0, -0.05, 0), nm="Crossbeam")
    p.box((1.0, 0, 7.4), (1.8, 0.25, 0.25), wood, rot=(0, 0.75, 0), nm="Brace")
    p.cyl((3.4, 0, 7.6), 0.04, 0.8, mat("Chain", C["iron"]), verts=4, nm="Chain")
    # lantern: cap + glowing bulb
    p.sph((3.4, 0, 6.6), (0.65, 0.65, 0.5), mat("LanternGlow", C["amber"], 6.0), seg=10, rings=6, nm="Bulb")
    capm = mat("CapRed", C["cap_red"])
    p.sph((3.4, 0, 7.0), (1.3, 1.3, 0.85), capm, seg=12, rings=6, nm="LanternCap")
    for i in range(5):
        a = i * 2 * math.pi / 5 + 0.3
        p.sph((3.4 + math.cos(a) * 0.95, math.sin(a) * 0.95, 7.35), (0.22, 0.22, 0.1), mat("Spot", C["cream"]), seg=6, rings=4, nm="Spot")
    p.sph((3.4, 0, 7.8), (0.3, 0.3, 0.1), mat("Spot", C["cream"]), seg=6, rings=4, nm="Spot")
    p.cyl((3.4, 0, 6.15), 0.5, 0.15, wood, verts=8, nm="LanternBase")
    for i in range(3):
        a = i * 2.1 + .6
        mushroom(p, (math.cos(a) * 1.1 + .3, math.sin(a) * 1.1, 0), rng.uniform(.4, .8), .12, rng.uniform(.35, .55), .3,
                 mat("CapRed" if i != 1 else "CapAmber", C["cap_red"] if i != 1 else C["shelf"]), spots=1 if i != 1 else 0, rng=rng)
    return p

def build_gate(rng):
    p = Prop("Build_Lobby_ExpeditionGate")
    st, dk, moss = mat("Stone", C["stone"]), mat("DarkStone", C["dark_stone"]), mat("Moss", C["moss"])
    rune, sh = mat("RuneGlow", C["rune"], 4.0), mat("ShelfMushroom", C["shelf"])
    pw, d = 3.6, GATE_D
    for s in (-1, 1):
        x = s * (GATE_W / 2 - pw / 2)
        p.box((x, 0, 0.5), (pw + 1.6, d + 1.0, 1.0), dk, nm="BaseStep")
        p.box((x, 0, 1.4), (pw + 0.8, d + 0.4, 0.8), st, nm="BaseStep")
        z = 1.8
        for i in range(5):
            h = rng.uniform(2.6, 3.4); w = pw + rng.uniform(-.2, .2)
            p.box((x + rng.uniform(-.1, .1), rng.uniform(-.1, .1), z + h / 2), (w, d - rng.uniform(0, .5), h - .05),
                  st if i % 2 == 0 else dk, rot=(0, 0, rng.uniform(-.03, .03)), nm="PillarBlock")
            z += h
        p.box((x, -d / 2 - 0.02, 8.0), (pw - 1.2, 0.2, 1.0), rune, nm="RuneBand")
        p.box((x, -d / 2 - 0.02, 11.0), (pw - 1.6, 0.2, 0.5), rune, nm="RuneBand")
    # arch: stepped voussoir blocks
    ir, cz = GATE_W / 2 - pw, 15.2
    n = 9
    for i in range(n):
        a = math.pi * (i + .5) / n; ln = 2 * math.pi * (ir + 1.6) / (2 * n) * 1.1
        rr = ir + 1.5
        p.box((-math.cos(a) * rr, 0, cz + math.sin(a) * rr * 0.62), (3.0, d - rng.uniform(0, .6), ln),
              st if i % 2 else dk, rot=(0, -(a - math.pi / 2) * 0.9 + math.pi / 2 * 0 , 0), nm="ArchBlock")
    p.box((0, 0, 19.0), (3.2, d + .4, 2.0), dk, nm="Keystone")
    p.box((0, -d / 2 - 0.02, 19.0), (1.0, 0.2, 1.0), rune, rot=(0, math.pi / 4, 0), nm="KeystoneRune")
    for i in range(6):
        p.sph((rng.uniform(-6, 6), rng.uniform(-1.5, 1.5), rng.uniform(19.6, 20.2) - abs(rng.uniform(-6, 6)) * .12),
              (rng.uniform(.8, 1.6), rng.uniform(.8, 1.6), .35), moss, nm="Moss")
    p.sph((-GATE_W / 2 + 1.5, -1, 9.0), (2.0, 1.4, .5), moss, nm="Moss")
    # shelf mushrooms up the left side
    for i in range(6):
        z = 2.5 + i * 2.1; r = 1.2 - i * 0.1
        p.sph((-GATE_W / 2 - 0.4, -d / 2 + rng.uniform(.3, 1.2), z), (r, r * .9, .3), sh, seg=10, rings=4, rot=(0, rng.uniform(-.2, .2), 0), nm="ShelfMush")
    # portal: concave rings + spiral arms
    pm = mat("PortalGlow", C["portal"], 5.0); pm2 = mat("PortalDeep", (90, 50, 170), 4.0)
    pr = ir - 0.1
    for i, k in enumerate(range(5)):
        r = pr * (1 - k * 0.19)
        p.cyl((0, 0.35 * (1 - k * .19) + 0.0, cz - 1.0), r, 0.12, pm if k % 2 == 0 else pm2, verts=24,
              rot=(math.pi / 2, 0, 0), scale=(1, 1.15, 1), nm="PortalRing")
        # reposition: concave -> inner rings recessed (+Y)
    for arm in range(3):
        for j in range(8):
            t = j / 8; a = arm * 2 * math.pi / 3 + t * 3.2; rr = pr * (0.95 - 0.8 * t)
            p.box((math.cos(a) * rr, 1.0 + t * .4, cz - 1.0 + math.sin(a) * rr * 1.15), (0.8, 0.12, 0.35), pm,
                  rot=(0, -a - math.pi / 2 - 0.5, 0), nm="PortalSwirl")
    return p

def build_statue(rng):
    p = Prop("Build_Lobby_GuardianStatue"); st = mat("Statue", C["statue"]); dk = mat("DarkStone", C["dark_stone"], 0)
    moss, glow = mat("Moss", C["moss"]), mat("GlowShroom", C["glow_blue"], 4.0)
    p.box((0, 0, 0.6), (5.0, 5.0, 1.2), dk, nm="PlinthBase")
    p.box((0, 0, 1.8), (4.2, 4.2, 1.2), mat("Stone", C["stone"]), nm="PlinthMid")
    p.box((0, 0, 2.7), (3.6, 3.6, 0.6), dk, nm="PlinthTop")
    z0 = PLINTH_H
    p.cyl((0, 0.1, z0 + 3.0), 1.9, 6.0, st, verts=8, r2=1.1, nm="Cloak")
    p.cyl((0, 0.1, z0 + 0.4), 2.1, 0.8, st, verts=8, nm="CloakHem")
    p.box((0, 1.0, z0 + 3.0), (2.0, 0.7, 4.4), st, rot=(-.08, 0, 0), nm="CloakBack")
    p.sph((0, 0, z0 + 6.3), (0.95, 0.95, 0.9), st, nm="Head")
    p.box((0, -0.75, z0 + 6.1), (0.9, 0.3, 0.25), dk, nm="Brow")
    p.sph((0, 0, z0 + 7.0), (2.6, 2.6, 1.35), st, seg=12, rings=6, nm="CapHelmet")
    p.cyl((0, 0, z0 + 6.75), 2.7, 0.3, dk, verts=12, nm="CapRim")
    for i in range(4):
        a = i * 1.7 + .5
        p.sph((math.cos(a) * 1.5, math.sin(a) * 1.5 - .3, z0 + 7.9 - i * .15), (.3, .3, .12), moss, seg=6, rings=4, nm="Moss")
    # sickle haft resting in front, hands on top
    hx = 1.9
    p.cyl((hx, -1.4, z0 + 4.2), 0.22, 9.0, mat("Wood", C["wood"]), verts=6, rot=(0, 0.05, 0), nm="SickleHaft")
    p.sph((hx - .35, -1.4, z0 + 4.2), (0.5, 0.5, 0.45), st, seg=8, rings=5, nm="Hand")
    p.sph((hx - .45, -1.4, z0 + 3.5), (0.5, 0.5, 0.45), st, seg=8, rings=5, nm="Hand")
    p.box((0.9, -1.0, z0 + 4.0), (0.8, 2.2, 0.8), st, rot=(0, 0, -0.3), nm="Arm")
    # blade: arc curving above shoulder, from top of haft inward
    steel = mat("Blade", (176, 182, 176))
    arc(p, (hx - 1.9, -1.4, z0 + 8.6), 1.9, 0.0, math.pi * 0.95, 0.38, 0.22, steel, steps=8, nm="Blade")
    p.box((hx, -1.4, z0 + 8.8), (0.5, 0.5, 0.6), dk, nm="BladeSocket")
    for pos in [(-1.3, -1.5, .55), (1.2, -1.6, 1.0), (-.8, 1.4, 1.45)]:
        p.sph((pos[0], pos[1], z0 - 3 + pos[2] + 3.2 - 3.0 + 0.0), (.9, .9, .3), moss, nm="Moss") if False else None
    p.sph((-1.8, -2.1, 1.25), (0.9, 0.7, 0.3), moss, nm="Moss")
    p.sph((1.9, -2.15, 2.3), (0.8, 0.6, 0.3), moss, nm="Moss")
    p.sph((-0.8, -1.7, z0 + 0.6), (1.0, 0.7, 0.4), moss, nm="Moss")
    for i, (x, y) in enumerate([(-2.2, -2.4), (-1.5, -2.5), (2.0, -2.6)]):
        mushroom(p, (x, y, 0.0 if i != 2 else 1.2), .35 + .1 * i, .07, .22 + .05 * i, .16, glow)
    return p

def build_fairy_ring(rng):
    p = Prop("Build_Lobby_FairyRing"); st = mat("Stone", C["stone"]); rune = mat("RuneGlow", C["rune"], 4.0)
    p.cyl((0, 0, RING_DISC_H / 2), RING_DISC_R, RING_DISC_H, st, verts=32, nm="Disc")
    p.cyl((0, 0, 0.1), RING_DISC_R + 0.6, 0.2, mat("DarkStone", C["dark_stone"]), verts=32, nm="DiscRim")
    p.torus((0, 0, RING_DISC_H + 0.02), 7.0, 0.14, mat("DarkStone", C["dark_stone"]), seg=32, nm="Groove")
    for i in range(24):
        a = i * 2 * math.pi / 24
        p.box((math.cos(a) * 7.0, math.sin(a) * 7.0, RING_DISC_H + 0.05), (0.9, 0.3, 0.12), rune, rot=(0, 0, a + math.pi / 2), nm="Rune")
    p.torus((0, 0, RING_DISC_H + 0.02), 4.5, 0.1, rune, seg=32, nm="InnerRune")
    p.torus((0, 0, RING_DISC_H + 0.02), 9.2, 0.1, rune, seg=32, nm="OuterRune")
    caps = [mat("CapRed", C["cap_red"]), mat("CapAmber", C["shelf"]), mat("CapBlue", C["glow_blue"])]
    for i in range(12):
        a = i * 2 * math.pi / 12 + rng.uniform(-.06, .06); r = RING_R - 1.4 + rng.uniform(-.3, .3)
        h = rng.uniform(1.0, 2.0) if i % 3 else rng.uniform(1.8, 2.3)
        cr = rng.uniform(.8, 1.2)
        mushroom(p, (math.cos(a) * r, math.sin(a) * r, 0), h, .28 + cr * .1, cr, rng.uniform(.5, .8), caps[i % 3], spots=3 if i % 3 == 0 else 0, rng=rng)
        for k in range(2):
            b = a + rng.uniform(-.25, .25); rr = r + rng.uniform(.8, 1.4)
            mushroom(p, (math.cos(b) * rr, math.sin(b) * rr, 0), rng.uniform(.3, .6), .1, rng.uniform(.25, .4), .2, caps[(i + k) % 3])
    return p

def build_notice_board(rng):
    p = Prop("Build_Lobby_NoticeBoard"); wood, dk = mat("Wood", C["wood"]), mat("WoodDark", (52, 40, 32))
    par = mat("Parchment", C["parchment"]); roof = mat("Shingle", C["roof"])
    for s in (-1, 1):
        p.box((s * 3.4, 0.2, 3.6), (0.7, 0.7, 7.2), wood, rot=(0, s * 0.02, 0), nm="Post")
    for i in range(4):
        p.box((0, -0.35, 3.2 + i * 1.15), (6.6, 0.3, 1.1), dk if i % 2 else wood, rot=(0, 0, rng.uniform(-.015, .015)), nm="Plank")
    p.box((0, -0.55, 3.0), (6.8, 0.15, 0.3), wood, nm="Trim"); p.box((0, -0.55, 7.2), (6.8, 0.15, 0.3), wood, nm="Trim")
    notes = [(-2.2, 6.2, 1.8, 2.2, 0.06), (0.2, 6.0, 2.0, 2.6, -0.04), (2.4, 5.8, 1.6, 1.8, 0.08), (-1.5, 3.9, 2.0, 1.5, -0.06), (1.6, 3.8, 1.8, 1.7, 0.05)]
    for k, (x, z, w, h, r) in enumerate(notes):
        p.box((x, -0.6 - k * .01, z), (w, 0.06, h), par, rot=(0, r, 0), nm="Note")
        p.sph((x, -0.68, z + h / 2 - .2), (.12, .06, .12), mat("Pin", C["cap_red"]), seg=6, rings=4, nm="Pin")
    p.sph((0.3, -0.7, 5.3), (0.32, 0.08, 0.32), mat("WaxSeal", (170, 30, 30)), seg=8, rings=5, nm="WaxSeal")
    # roof
    for s in (-1, 1):
        p.box((0, s * 0.0 + 0.2 + (0 if s < 0 else 0), 8.2), (0.01, 0.01, 0.01), roof, nm="_x") if False else None
    for s in (-1, 1):
        p.box((0, s * 1.1, 8.1 + 0.0), (8.2, 1.9, 0.3), roof, rot=(s * -0.45 if False else s * 0.45, 0, 0), nm="RoofSlope")
        for r in range(5):
            p.box((-3.6 + r * 1.8, s * 1.35, 7.9), (1.7, 0.5, 0.15), dk if r % 2 else roof, rot=(s * 0.45, 0, 0), nm="Shingle")
    p.box((0, 0, 8.85), (8.4, 0.4, 0.3), dk, nm="RoofRidge")
    # hanging lantern on right post
    p.box((4.4, 0.2, 6.6), (1.6, 0.18, 0.18), wood, nm="LanternArm")
    p.cyl((5.05, 0.2, 6.2), 0.03, 0.8, mat("Chain", C["iron"]), verts=4, nm="Chain")
    p.cyl((5.05, 0.2, 5.6), 0.38, 0.6, mat("LanternGlow", C["amber"], 6.0), verts=8, nm="LanternGlass")
    p.cyl((5.05, 0.2, 5.25), 0.45, 0.1, mat("Chain", C["iron"]), verts=8, nm="LanternBase")
    p.cyl((5.05, 0.2, 6.0), 0.5, 0.2, mat("Chain", C["iron"]), verts=8, r2=0.15, nm="LanternTop")
    mushroom(p, (-3.9, -0.3, 0), .5, .1, .4, .25, mat("CapRed", C["cap_red"]), spots=1, rng=rng)
    mushroom(p, (-3.2, -.6, 0), .3, .08, .3, .2, mat("CapAmber", C["shelf"]))
    return p

def build_map_stone(rng, region, rgb):
    p = Prop(f"Build_Lobby_MapStone_{region}"); st = mat("Stone", C["stone"]); dk = mat("DarkStone", C["dark_stone"])
    glow = mat(f"Glyph_{region}", rgb, 5.0)
    p.cyl((0, 0, 0.25), 1.9, 0.5, dk, verts=8, nm="Footing")
    p.box((0, 0, 2.7), (2.6, 1.2, 4.5), st, rot=(0.02, 0.05, 0.08), nm="Stone")
    p.box((0.1, 0, 5.0 - 0.3), (2.0, 1.0, 0.9), st, rot=(0, 0.12, 0.12), nm="StoneTop")
    p.box((-.05, -0.62, 2.9), (0.14, 0.08, 2.2), glow, rot=(0, 0, 0.08), nm="GlyphStem")
    p.box((-.05, -0.62, 3.9), (1.0, 0.08, 0.14), glow, rot=(0, 0, 0.08), nm="GlyphBar")
    p.box((-.45, -0.62, 2.0), (0.6, 0.08, 0.14), glow, rot=(0, 0, 0.8), nm="GlyphArm")
    p.box((.35, -0.62, 2.0), (0.6, 0.08, 0.14), glow, rot=(0, 0, -0.8), nm="GlyphArm")
    p.torus((-.05, -0.64, 4.35), 0.3, 0.06, glow, rot=(math.pi / 2, 0, 0.08), seg=12, nm="GlyphRing")
    p.sph((-0.9, -0.4, 0.6), (0.8, 0.6, 0.3), mat("Moss", C["moss"]), nm="Moss")
    p.sph((0.7, -0.6, 4.4), (0.5, 0.35, 0.18), mat("Moss", C["moss"]), nm="Moss")
    mushroom(p, (1.3, -0.7, 0), .4, .08, .3, .2, mat("CapRed", C["cap_red"]))
    return p

# ================= pipeline =================
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def measure(p):
    mn, mx, tris = Vector((1e9,) * 3), Vector((-1e9,) * 3), 0
    for o in p.col.objects:
        if o.type != "MESH": continue
        tris += sum(len(q.vertices) - 2 for q in o.data.polygons)
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3): mn[i], mx[i] = min(mn[i], w[i]), max(mx[i], w[i])
    return tris, mn, mx

def export(p):
    bpy.ops.object.select_all(action="DESELECT")
    for o in p.col.all_objects: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(EXPORT_DIR, p.name + ".glb"), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True)
    bpy.ops.object.select_all(action="DESELECT")

def main():
    os.makedirs(EXPORT_DIR, exist_ok=True); os.makedirs(PREVIEW_DIR, exist_ok=True)
    reset(); rng = random.Random(SEED)
    jobs = [build_spore_lantern, build_gate, build_statue, build_fairy_ring, build_notice_board]
    props = [fn(random.Random(SEED + i)) for i, fn in enumerate(jobs)]
    for i, (r, c) in enumerate(REGIONS.items()):
        props.append(build_map_stone(random.Random(SEED + 100), r, c))
    stats = []
    for p in props:
        bpy.context.view_layer.update()
        t, mn, mx = measure(p); export(p); stats.append((p.name, t, mn, mx))
        print(f"STAT {p.name}: tris={t} min=({mn.x:.2f},{mn.y:.2f},{mn.z:.2f}) max=({mx.x:.2f},{mx.y:.2f},{mx.z:.2f}) size=({mx.x-mn.x:.2f},{mx.y-mn.y:.2f},{mx.z-mn.z:.2f})")
    previews = None
    if RENDER_PREVIEWS:
        try: render_previews(props)
        except Exception as e: print("PREVIEW FAILED", e)
    # layout side by side (after export, exports are made at the origin)
    x = 0.0
    for p in props:
        t, mn, mx = measure(p)
        w = max(mx.x - mn.x, 3.0)
        p.root.location.x = x - mn.x; x += w + 8.0
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    print("SAVED", OUT_BLEND)

def render_previews(props):
    sc = bpy.context.scene
    # Workbench/EEVEE need libEGL (absent on headless boxes); Cycles CPU works everywhere.
    sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 12
    w = bpy.data.worlds.new("W"); w.use_nodes = True; sc.world = w
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.35, 0.4, 0.5, 1)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN")); sun.data.energy = 3.0
    sun.rotation_euler = (0.9, 0.3, 0.6); sc.collection.objects.link(sun)
    sc.render.resolution_x = sc.render.resolution_y = 512
    sc.render.film_transparent = True; sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    cam_d = bpy.data.cameras.new("PrevCam"); cam = bpy.data.objects.new("PrevCam", cam_d)
    sc.collection.objects.link(cam); sc.camera = cam; cam_d.type = "ORTHO"
    for p in props:
        for q in props:
            q.col.hide_render = q is not p
        t, mn, mx = measure(p); c = (mn + mx) / 2; ext = max(mx.x - mn.x, mx.z - mn.z, mx.y - mn.y)
        cam_d.ortho_scale = ext * 1.25
        d = Vector((0.55, -1.0, 0.45)).normalized() * 100
        cam.location = c + d
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(PREVIEW_DIR, p.name + ".png")
        bpy.ops.render.render(write_still=True)
    for q in props: q.col.hide_render = False
    bpy.data.objects.remove(cam); bpy.data.objects.remove(sun)

if __name__ == "__main__":
    main()
