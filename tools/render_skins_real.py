from PIL import Image, ImageDraw, ImageFont
import os, glob

SCALE = 2
W_FINAL, H_FINAL = 1180, 820
W, H = W_FINAL * SCALE, H_FINAL * SCALE

BG_A     = (10, 4, 18)
BG_B     = (24, 8, 32)
PANEL    = (18, 8, 26)
PANEL2   = (28, 12, 38)
HAIR     = (56, 22, 70)
LABEL    = (238, 230, 240)
SECOND   = (170, 140, 170)
TERTIARY = (120, 95, 130)
ACCENT   = (235, 55, 110)
ACCENT_HI= (255, 100, 150)
GREEN    = (90, 220, 130)
AMBER    = (255, 190, 60)
WHITE    = (245, 236, 245)

CATS = [
    ("ГЕЙМПЛЕЙ",    ["Прицел", "ESP", "Оружие", "Движение", "Камера"]),
    ("ВИЗУАЛ",      ["HUD", "Темы", "Кастом прицел"]),
    ("МИР",         ["Утилиты", "Инвентарь", "Скины"]),
    ("БЕЗОПАСНОСТЬ",["Защита", "Humanize", "Kill-switch", "HWID"]),
    ("СИСТЕМА",     ["Профили", "Биндинги", "Макросы", "Статистика", "Лицензия"]),
]

ASSETS = "/home/user/sezx/assets/skins"

# (slug, pretty name, stattrak, wear, verified)
AKR = [
    ("akr-2-years-red",     "2Years Red",      True,  0.050, True),
    ("akr-steel-grip",      "Steel Grip",      False, 0.040, True),
    ("akr-tiger",           "Tiger",           True,  0.100, True),
    ("akr-sport",           "Sport",           False, 0.060, True),
    ("akr-treasure-hunter", "Treasure Hunter", True,  0.030, True),
    ("akr-dragon",          "Dragon",          False, 0.120, True),
    ("akr-digital-burst",   "Digital Burst",   False, 0.080, True),
    ("akr-tag-king",        "Tag King",        False, 0.070, True),
    ("akr-genesis",         "Genesis",         False, 0.090, True),
    ("akr-icewing",         "Icewing",         False, 0.070, True),
    ("akr-scylla",          "Scylla",          True,  0.080, True),
    ("akr-fabric-storm",    "Fabric Storm",    False, 0.110, True),
    ("akr-evolution",       "Evolution",       False, 0.100, True),
]

def font(paths, size):
    s = int(size * SCALE)
    for p in paths:
        try: return ImageFont.truetype(p, s)
        except Exception: pass
    return ImageFont.load_default()

SFB = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]
SF  = ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
f_hero  = font(SFB, 26)
f_h2    = font(SFB, 19)
f_h3    = font(SFB, 14)
f_sec   = font(SFB, 11)
f_row   = font(SF,  14)
f_desc  = font(SF,  11)
f_tiny  = font(SF,  10)
f_badge = font(SFB, 10)

def rrect(d, xy, r, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = xy
    d.rounded_rectangle((x0*SCALE, y0*SCALE, x1*SCALE, y1*SCALE),
                        radius=r*SCALE, fill=fill, outline=outline,
                        width=int(width*SCALE))

def rect_px(d, xy, fill=None):
    x0, y0, x1, y1 = xy
    d.rectangle((x0*SCALE, y0*SCALE, x1*SCALE, y1*SCALE), fill=fill)

def line_(d, xy, fill, width=1):
    x0, y0, x1, y1 = xy
    d.line((x0*SCALE, y0*SCALE, x1*SCALE, y1*SCALE), fill=fill,
           width=int(width*SCALE))

def text(d, xy, s, f, fill, max_w=None):
    x, y = xy
    if max_w is not None:
        if d.textlength(s, font=f) / SCALE > max_w:
            while len(s) > 1 and d.textlength(s + "…", font=f) / SCALE > max_w:
                s = s[:-1]
            s = s + "…"
    d.text((x*SCALE, y*SCALE), s, font=f, fill=fill)

def textw(d, s, f): return d.textlength(s, font=f) / SCALE

def gradient_bg(img):
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        r = int(BG_A[0] * (1-t) + BG_B[0] * t)
        g = int(BG_A[1] * (1-t) + BG_B[1] * t)
        b = int(BG_A[2] * (1-t) + BG_B[2] * t)
        d.line([(0, y), (W, y)], fill=(r, g, b))

def paste_skin(img, slug, box):
    """box in pre-scale coords (x, y, w, h); scales the real PNG to fit."""
    p = os.path.join(ASSETS, slug + ".png")
    if not os.path.exists(p): return False
    src = Image.open(p).convert("RGBA")
    x, y, w, h = box
    tw, th = w * SCALE, h * SCALE
    # keep aspect
    sw, sh = src.size
    s = min(tw / sw, th / sh)
    nw, nh = int(sw * s), int(sh * s)
    src = src.resize((nw, nh), Image.LANCZOS)
    img.alpha_composite(src, (x*SCALE + (tw - nw)//2, y*SCALE + (th - nh)//2))
    return True

def draw_header(d):
    for y in range(78):
        t = y / 78
        r = int(60 * (1-t) + 20 * t)
        g = int(14 * (1-t) + 10 * t)
        b = int(40 * (1-t) + 26 * t)
        d.line([(0, y*SCALE), (W, y*SCALE)], fill=(r, g, b), width=SCALE)
    rrect(d, (22, 16, 54, 48), 8, ACCENT)
    text(d, (29, 21), "S2", f_h3, WHITE)
    text(d, (66, 12), "so2mm", f_hero, WHITE)
    text(d, (66, 46), "тёмно-красная · arm64 · v2.4.1 · Скины",
         f_desc, SECOND, max_w=W_FINAL//2)
    cx = W_FINAL - 302
    rrect(d, (cx, 14, W_FINAL - 22, 60), 14, (18, 8, 26), outline=HAIR, width=1)
    d.ellipse(((cx+8)*SCALE, 22*SCALE, (cx+40)*SCALE, 54*SCALE),
              fill=(60, 30, 50))
    text(d, (cx+15, 27), "SB", f_h3, ACCENT_HI)
    text(d, (cx+50, 20), "user_4421", f_h3, WHITE, max_w=160)
    text(d, (cx+50, 40), "Phoenix · 63 д · comp_ak", f_desc, SECOND, max_w=220)

def draw_sidebar(d):
    SB_X, SB_Y, SB_W = 18, 94, 216
    rrect(d, (SB_X, SB_Y, SB_X+SB_W, H_FINAL-18), 14, PANEL)
    y = SB_Y + 14
    for ci, (cat, items) in enumerate(CATS):
        text(d, (SB_X+18, y), cat, f_sec, TERTIARY)
        y += 20
        for ii, it in enumerate(items):
            active = (ci == 2 and ii == 2)
            if active:
                rrect(d, (SB_X+8, y-2, SB_X+SB_W-8, y+24), 8, (60, 22, 46))
                rect_px(d, (SB_X+8, y-2, SB_X+12, y+24), ACCENT_HI)
            text(d, (SB_X+22, y+3), it, f_row,
                 ACCENT_HI if active else LABEL, max_w=SB_W-40)
            y += 28
        y += 8

def draw_weapons_list(d, x, y, w, h):
    rrect(d, (x, y, x+w, y+h), 12, PANEL)
    weps = [("AKR", 13, True), ("M4", 3, False), ("AWM", 3, False),
            ("Desert Eagle", 3, False),
            ("Karambit", 3, False), ("M9 Bayonet", 3, False),
            ("Butterfly", 3, False)]
    yy = y + 10
    for name, n, active in weps:
        if active:
            rrect(d, (x+6, yy-2, x+w-6, yy+28), 8, (60, 22, 46))
            rect_px(d, (x+6, yy-2, x+10, yy+28), ACCENT_HI)
        text(d, (x+20, yy+4), name, f_row,
             ACCENT_HI if active else LABEL, max_w=w-70)
        cnt = str(n)
        cw = textw(d, cnt, f_desc)
        text(d, (x+w-16-cw, yy+6), cnt, f_desc, SECOND)
        yy += 32

def draw_grid(img, d, x, y, w, h):
    rrect(d, (x, y, x+w, y+h), 12, PANEL)
    text(d, (x+16, y+14), "AKR · 13 скинов", f_h2, LABEL)
    text(d, (x+w-170, y+22), "активен: 2Years Red", f_desc, SECOND)
    line_(d, (x+16, y+48, x+w-16, y+48), HAIR, width=1)
    cols = 4
    gap = 10
    gx0 = x + 16
    gy0 = y + 60
    inner_w = w - 32
    cw = (inner_w - gap * (cols - 1)) // cols
    ch = 150
    for i, (slug, name, st, wear, ver) in enumerate(AKR):
        r = i // cols; c = i % cols
        cx = gx0 + c * (cw + gap)
        cy = gy0 + r * (ch + gap)
        selected = (name == "2Years Red")
        # card frame
        rrect(d, (cx, cy, cx+cw, cy+ch), 10, PANEL2)
        # preview area
        preview_h = ch - 38
        paste_skin(img, slug, (cx+4, cy+4, cw-8, preview_h-6))
        # selection ring
        if selected:
            rrect(d, (cx, cy, cx+cw, cy+ch), 10, outline=ACCENT_HI, width=2)
        else:
            rrect(d, (cx, cy, cx+cw, cy+ch), 10, outline=HAIR, width=1)
        # bottom strip
        rect_px(d, (cx+2, cy+ch-38, cx+cw-2, cy+ch-2), (28, 12, 38))
        text(d, (cx+10, cy+ch-33), name, f_row, LABEL, max_w=cw - 44)
        if st:
            rrect(d, (cx+cw-36, cy+ch-32, cx+cw-12, cy+ch-16), 4, (120,30,42))
            text(d, (cx+cw-30, cy+ch-31), "ST", f_badge, WHITE)
        text(d, (cx+10, cy+ch-18), f"{wear:.3f}", f_tiny, SECOND)

def draw_footer_controls(d, x, y, w):
    rrect(d, (x, y, x+w, y+120), 12, PANEL)
    text(d, (x+16, y+14), "StatTrak", f_row, LABEL)
    text(d, (x+16, y+34), "Счётчик фрагов на корпусе оружия", f_desc, TERTIARY)
    rrect(d, (x+w-62, y+16, x+w-16, y+40), 12, ACCENT)
    d.ellipse(((x+w-38)*SCALE, (y+20)*SCALE, (x+w-20)*SCALE, (y+38)*SCALE),
              fill=WHITE)
    line_(d, (x+16, y+60, x+w-16, y+60), HAIR, width=1)
    text(d, (x+16, y+68), "Износ", f_row, LABEL)
    text(d, (x+w-140, y+70), "0.050 · Factory New", f_desc, SECOND)
    bx1, bx2 = x+16, x+w-16
    by = y + 100
    rrect(d, (bx1, by, bx2, by+6), 3, (60, 30, 40))
    fx = bx1 + (bx2-bx1) * 0.05
    rrect(d, (bx1, by, fx, by+6), 3, ACCENT)
    d.ellipse(((fx-8)*SCALE, (by-5)*SCALE, (fx+8)*SCALE, (by+11)*SCALE),
              fill=WHITE)

def draw_apply_button(d, x, y, w):
    rrect(d, (x, y, x+w, y+48), 12, ACCENT)
    txt = "Применить к инвентарю"
    tw = textw(d, txt, f_h2)
    text(d, (x + w/2 - tw/2, y+14), txt, f_h2, WHITE)

OUT = "/tmp/claude-0/-home-user-sezx/c19d3923-cc31-59a5-a153-26878d244cef/scratchpad"
os.makedirs(OUT, exist_ok=True)

img = Image.new("RGBA", (W, H), BG_A)
gradient_bg(img)
d = ImageDraw.Draw(img, "RGBA")
draw_header(d)
draw_sidebar(d)

MX = 18 + 216 + 14
MW = W_FINAL - MX - 18
MY = 94
text(d, (MX+2, MY-2), "Скины", f_hero, LABEL)
text(d, (MX+2, MY+32), "выбор модели · износ · StatTrak · применение",
     f_desc, SECOND)

cy = MY + 70
list_w = 200
grid_x = MX + list_w + 14
grid_w = MW - list_w - 14

rrect(d, (MX, cy, MX+MW, cy+54), 12, PANEL)
text(d, (MX+16, cy+10), "Смена скинов", f_row, LABEL)
text(d, (MX+16, cy+30), "Подменяет скин оружия локально, сервер не видит",
     f_desc, TERTIARY)
rrect(d, (MX+MW-62, cy+14, MX+MW-16, cy+38), 12, ACCENT)
d.ellipse(((MX+MW-38)*SCALE, (cy+18)*SCALE, (MX+MW-20)*SCALE, (cy+36)*SCALE),
          fill=WHITE)

cy2 = cy + 64
grid_h = H_FINAL - cy2 - 200
draw_weapons_list(d, MX, cy2, list_w, grid_h)
draw_grid(img, d, grid_x, cy2, grid_w, grid_h)

cy3 = cy2 + grid_h + 12
draw_footer_controls(d, MX, cy3, (MW - 14) // 2)
draw_apply_button(d, MX + (MW - 14) // 2 + 14, cy3 + 36, (MW - 14) // 2)

out = f"{OUT}/so2mm_skins_real.png"
img.resize((W_FINAL, H_FINAL), Image.LANCZOS).convert("RGB").save(out, "PNG")
print(out)
