from PIL import Image, ImageDraw, ImageFont
import os, math, random

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

# weapon_id, skin_name, verified, stattrak, wear, base, detail, accent, pattern
SKINS = [
    (1, "Default",         True,  False, 0.000, (90,106,120),(44,50,56),  (128,136,144), 0),
    (1, "Steel Grip",      True,  False, 0.040, (138,150,164),(51,60,68), (194,208,221), 7),
    (1, "Tiger",           True,  True,  0.100, (26,30,36),  (240,138,26),(255,200,102),1),
    (1, "Sport",           True,  False, 0.060, (220,220,220),(197,32,54),(42,46,52),   5),
    (1, "2Years Red",      True,  True,  0.050, (94,10,20),  (192,34,52), (232,192,64), 7),
    (1, "Treasure Hunter", True,  True,  0.030, (212,181,130),(130,96,56),(232,207,140),8),
    (1, "Galaxy",          False, False, 0.080, (19,10,40),  (82,58,138), (232,212,255),4),
    (1, "Neon Tiger",      False, True,  0.090, (26,10,26),  (224,50,154),(255,140,216),1),
    (1, "Dragon",          False, False, 0.120, (10,38,20),  (60,138,76), (180,240,180),2),
    (1, "Evolution",       False, False, 0.100, (12,24,40),  (44,122,200),(188,228,255),7),
    (1, "Fabric Storm",    False, False, 0.110, (108,90,64), (166,144,120),(216,200,168),6),
    (1, "Genesis",         False, False, 0.090, (220,228,240),(72,120,184),(128,176,224),7),
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

def text(d, xy, s, f, fill, max_w=None):
    x, y = xy
    if max_w is not None:
        if d.textlength(s, font=f) / SCALE > max_w:
            while len(s) > 1 and d.textlength(s + "…", font=f) / SCALE > max_w:
                s = s[:-1]
            s = s + "…"
    d.text((x*SCALE, y*SCALE), s, font=f, fill=fill)

def textw(d, s, f): return d.textlength(s, font=f) / SCALE

def line_(d, xy, fill, width=1):
    x0, y0, x1, y1 = xy
    d.line((x0*SCALE, y0*SCALE, x1*SCALE, y1*SCALE), fill=fill,
           width=int(width*SCALE))

def gradient_bg(img):
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        r = int(BG_A[0] * (1-t) + BG_B[0] * t)
        g = int(BG_A[1] * (1-t) + BG_B[1] * t)
        b = int(BG_A[2] * (1-t) + BG_B[2] * t)
        d.line([(0, y), (W, y)], fill=(r, g, b))

def preview_bg(d, a, b, base, detail):
    x0, y0, x1, y1 = a[0], a[1], b[0], b[1]
    for yy in range(y0*SCALE, y1*SCALE):
        t = (yy - y0*SCALE) / max(1, (y1-y0)*SCALE)
        r = int(base[0]*(1-t) + detail[0]*t)
        g = int(base[1]*(1-t) + detail[1]*t)
        b_ = int(base[2]*(1-t) + detail[2]*t)
        d.line([(x0*SCALE, yy), (x1*SCALE, yy)], fill=(r, g, b_))

def pat_stripes(d, a, b, color):
    x0, y0, x1, y1 = a[0], a[1], b[0], b[1]
    n = 10
    sw = (x1 - x0) / (n * 2)
    for i in range(n):
        xa = x0 + i * 2 * sw
        rect_px(d, (xa, y0, xa + sw, y1), color)

def pat_scales(d, a, b, color):
    r = 7
    y = int(a[1])
    while y < int(b[1]):
        off = r if ((y // r) & 1) else 0
        x = a[0] - off
        while x < b[0]:
            d.ellipse(((x)*SCALE, (y)*SCALE, (x+r*2)*SCALE, (y+r)*SCALE),
                      outline=color, width=SCALE)
            x += r * 2
        y += r

def pat_starfield(d, a, b, color):
    random.seed(1337)
    for _ in range(90):
        x = random.uniform(a[0], b[0])
        y = random.uniform(a[1], b[1])
        r = random.uniform(0.4, 1.6)
        d.ellipse(((x-r)*SCALE, (y-r)*SCALE, (x+r)*SCALE, (y+r)*SCALE),
                  fill=color)

def pat_racing(d, a, b, color):
    h = b[1] - a[1]
    y1 = a[1] + h * 0.44
    y2 = a[1] + h * 0.54
    rect_px(d, (a[0], y1, b[0], y1 + 3), color)
    rect_px(d, (a[0], y2, b[0], y2 + 3), color)

def pat_speckle(d, a, b, color):
    random.seed(99)
    for _ in range(50):
        x = random.uniform(a[0], b[0])
        y = random.uniform(a[1], b[1])
        rect_px(d, (x, y, x+2, y+2), color)

def pat_radial(d, a, b, color):
    cx = (a[0]+b[0])/2; cy = (a[1]+b[1])/2
    rr = min(b[0]-a[0], b[1]-a[1]) * 0.35
    for i in range(16, 0, -1):
        alpha = int(40 * i / 16)
        d.ellipse(((cx - rr*i/16)*SCALE, (cy - rr*i/16)*SCALE,
                   (cx + rr*i/16)*SCALE, (cy + rr*i/16)*SCALE),
                  outline=color + (alpha,))

def pat_fabric(d, a, b, color):
    y = int(a[1])
    while y < int(b[1]):
        rect_px(d, (a[0], y, b[0], y+1), color)
        y += 4
    x = int(a[0])
    while x < int(b[0]):
        rect_px(d, (x, a[1], x+1, b[1]), color)
        x += 4

PATTERNS = {
    0: lambda *_: None,
    1: pat_stripes, 2: pat_scales, 4: pat_starfield,
    5: pat_racing,  6: pat_fabric, 7: pat_radial, 8: pat_speckle,
}

def draw_akr_silhouette(d, a, b, base, detail, accent, pattern):
    w = b[0] - a[0]; h = b[1] - a[1]
    cy = (a[1] + b[1]) / 2
    body = (a[0] + w*0.10, cy - h*0.11, a[0] + w*0.78, cy + h*0.08)
    rect_px(d, body, base)
    fn = PATTERNS.get(pattern)
    if fn: fn(d, (body[0], body[1]), (body[2], body[3]), detail if pattern != 7 else accent)
    # магазин
    rect_px(d, (a[0] + w*0.42, cy + h*0.08, a[0] + w*0.56, cy + h*0.30), detail)
    # приклад
    rect_px(d, (a[0] + w*0.78, cy - h*0.05, a[0] + w*0.92, cy + h*0.12), detail)
    # прицел
    rect_px(d, (a[0] + w*0.52, cy - h*0.22, a[0] + w*0.60, cy - h*0.11), accent)
    # ствол
    rect_px(d, (a[0] + w*0.02, cy - h*0.04, a[0] + w*0.10, cy + h*0.02), detail)
    # блик
    hl = accent
    line_(d, (body[0] + 4, body[1] + 3, body[2] - 6, body[1] + 3), hl, width=1)

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
            active = (ci == 2 and ii == 2)   # Скины
            if active:
                rrect(d, (SB_X+8, y-2, SB_X+SB_W-8, y+24), 8, (60, 22, 46))
                rect_px(d, (SB_X+8, y-2, SB_X+12, y+24), ACCENT_HI)
            text(d, (SB_X+22, y+3), it, f_row,
                 ACCENT_HI if active else LABEL, max_w=SB_W-40)
            y += 28
        y += 8

def draw_weapons_list(d, x, y, w, h):
    rrect(d, (x, y, x+w, y+h), 12, PANEL)
    weps = [("AKR", 14, True), ("M4", 2, False), ("AWM", 2, False),
            ("Desert Eagle", 2, False), ("USP", 1, False), ("Glock-18", 1, False),
            ("Karambit", 2, False), ("M9 Bayonet", 2, False), ("Butterfly", 2, False)]
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

def draw_grid(d, x, y, w, h):
    rrect(d, (x, y, x+w, y+h), 12, PANEL)
    # header
    text(d, (x+16, y+14), "AKR · 14 скинов", f_h2, LABEL)
    text(d, (x+w-170, y+22), "активен: 2Years Red", f_desc, SECOND)
    line_(d, (x+16, y+48, x+w-16, y+48), HAIR, width=1)
    # 3 columns x 4 rows grid
    cw, ch = 220, 150
    gap = 14
    cols = 3
    gx0 = x + 16
    gy0 = y + 62
    for i, (wid, name, ver, st, wear, base, detail, accent, pat) in enumerate(SKINS):
        r = i // cols; c = i % cols
        cx = gx0 + c * (cw + gap)
        cy = gy0 + r * (ch + gap)
        selected = (name == "2Years Red")
        # card bg
        rrect(d, (cx, cy, cx+cw, cy+ch), 10, PANEL2)
        # preview area (top ~110px)
        prev_a = (cx+2, cy+2); prev_b = (cx+cw-2, cy+ch-38)
        preview_bg(d, prev_a, prev_b, base, detail)
        draw_akr_silhouette(d, prev_a, prev_b, base, detail, accent, pat)
        # selection ring
        if selected:
            rrect(d, (cx, cy, cx+cw, cy+ch), 10, outline=ACCENT_HI, width=2)
        else:
            rrect(d, (cx, cy, cx+cw, cy+ch), 10, outline=HAIR, width=1)
        # unverified tag
        if not ver:
            rrect(d, (cx+cw-24, cy+6, cx+cw-6, cy+22), 4, (0,0,0, 140))
            text(d, (cx+cw-19, cy+7), "?", f_badge, AMBER)
        # bottom strip
        rect_px(d, (cx+2, cy+ch-38, cx+cw-2, cy+ch-2), (28, 12, 38))
        text(d, (cx+12, cy+ch-32), name, f_row, LABEL, max_w=cw-70)
        if st:
            rrect(d, (cx+cw-38, cy+ch-32, cx+cw-12, cy+ch-16), 4, (120,30,42))
            text(d, (cx+cw-32, cy+ch-31), "ST", f_badge, WHITE)
        text(d, (cx+12, cy+ch-18), f"{wear:.3f}", f_tiny, SECOND)
        # rarity dot
        rarity_col = GREEN if ver else AMBER
        d.ellipse(((cx+cw-18)*SCALE, (cy+ch-16)*SCALE,
                   (cx+cw-10)*SCALE, (cy+ch-8)*SCALE), fill=rarity_col)

def draw_footer_controls(d, x, y, w):
    rrect(d, (x, y, x+w, y+120), 12, PANEL)
    # StatTrak row
    text(d, (x+16, y+14), "StatTrak", f_row, LABEL)
    text(d, (x+16, y+34), "Счётчик фрагов на корпусе оружия", f_desc, TERTIARY)
    rrect(d, (x+w-62, y+16, x+w-16, y+40), 12, ACCENT)
    d.ellipse(((x+w-38)*SCALE, (y+20)*SCALE, (x+w-20)*SCALE, (y+38)*SCALE),
              fill=WHITE)
    line_(d, (x+16, y+60, x+w-16, y+60), HAIR, width=1)
    # Wear slider
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

# Enable toggle card
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
draw_grid(d, grid_x, cy2, grid_w, grid_h)

cy3 = cy2 + grid_h + 12
draw_footer_controls(d, MX, cy3, (MW - 14) // 2)
draw_apply_button(d, MX + (MW - 14) // 2 + 14, cy3 + 36, (MW - 14) // 2)

out = f"{OUT}/so2mm_skins_grid.png"
img.resize((W_FINAL, H_FINAL), Image.LANCZOS).convert("RGB").save(out, "PNG")
print(out)
