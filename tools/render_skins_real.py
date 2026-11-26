from PIL import Image, ImageDraw, ImageFont
import os, json

SCALE = 2
W_FINAL, H_FINAL = 1280, 900
W, H = W_FINAL * SCALE, H_FINAL * SCALE

BG_A     = (10, 4, 18)
BG_B     = (24, 8, 32)
PANEL    = (18, 8, 26)
PANEL2   = (28, 12, 38)
PANEL3   = (34, 14, 44)
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

ASSETS_DIR = "/home/user/sezx/assets/skins"
with open(os.path.join(ASSETS_DIR, "catalog.json")) as f:
    CATALOG = json.load(f)

KIND_LABEL = {
    "rifle":   "Винтовки",
    "sniper":  "Снайперки",
    "smg":     "ПП",
    "mg":      "Пулемёты",
    "pistol":  "Пистолеты",
    "shotgun": "Дробовики",
    "knife":   "Ножи",
    "grenade": "Гранаты",
}
KIND_ORDER = ["rifle","sniper","smg","mg","pistol","shotgun","knife","grenade"]

# selection state for mockup
ACTIVE_WEAPON = "AKR"
ACTIVE_SKIN   = "2 Years Red"
ACTIVE_KIND   = None   # None == все
SEARCH_QUERY  = ""

def font(paths, size):
    s = int(size * SCALE)
    for p in paths:
        try: return ImageFont.truetype(p, s)
        except Exception: pass
    return ImageFont.load_default()

SFB = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]
SF  = ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
f_hero  = font(SFB, 26)
f_h2    = font(SFB, 18)
f_h3    = font(SFB, 14)
f_sec   = font(SFB, 11)
f_row   = font(SF,  14)
f_desc  = font(SF,  11)
f_tiny  = font(SF,  10)
f_badge = font(SFB, 10)
f_chip  = font(SFB, 13)
f_search= font(SF,  15)

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

def ellipse_(d, xy, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = xy
    d.ellipse((x0*SCALE, y0*SCALE, x1*SCALE, y1*SCALE), fill=fill,
              outline=outline, width=int(width*SCALE))

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
    p = os.path.join(ASSETS_DIR, slug + ".png")
    if not os.path.exists(p): return False
    src = Image.open(p).convert("RGBA")
    x, y, w, h = box
    tw, th = w * SCALE, h * SCALE
    sw, sh = src.size
    s = min(tw / sw, th / sh)
    nw, nh = int(sw * s), int(sh * s)
    src = src.resize((nw, nh), Image.LANCZOS)
    img.alpha_composite(src, (x*SCALE + (tw - nw)//2,
                              y*SCALE + (th - nh)//2))
    return True

def draw_header(d):
    for y in range(76):
        t = y / 76
        r = int(60 * (1-t) + 20 * t)
        g = int(14 * (1-t) + 10 * t)
        b = int(40 * (1-t) + 26 * t)
        d.line([(0, y*SCALE), (W, y*SCALE)], fill=(r, g, b), width=SCALE)
    rrect(d, (22, 16, 54, 48), 8, ACCENT)
    text(d, (29, 21), "S2", f_h3, WHITE)
    text(d, (66, 10), "so2mm", f_hero, WHITE)
    text(d, (66, 44), "тёмно-красная · arm64 · v2.4.1 · Скины",
         f_desc, SECOND, max_w=W_FINAL//2)
    cx = W_FINAL - 302
    rrect(d, (cx, 14, W_FINAL - 22, 58), 14, (18, 8, 26), outline=HAIR, width=1)
    ellipse_(d, (cx+8, 20, cx+40, 52), fill=(60, 30, 50))
    text(d, (cx+16, 26), "SB", f_h3, ACCENT_HI)
    text(d, (cx+50, 18), "user_4421", f_h3, WHITE, max_w=160)
    text(d, (cx+50, 38), "Phoenix · 63 д · comp_ak", f_desc, SECOND, max_w=220)

def draw_sidebar(d):
    SB_X, SB_Y, SB_W = 18, 86, 216
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

def draw_search_bar(d, x, y, w):
    rrect(d, (x, y, x+w, y+42), 10, PANEL2, outline=HAIR, width=1)
    # magnifier icon
    ellipse_(d, (x+14, y+12, x+28, y+26), outline=SECOND, width=2)
    line_(d, (x+25, y+23, x+31, y+29), SECOND, width=2)
    # placeholder / query
    if SEARCH_QUERY:
        text(d, (x+42, y+12), SEARCH_QUERY, f_search, LABEL)
        # caret
        rect_px(d, (x+42 + textw(d, SEARCH_QUERY, f_search) + 2, y+12,
                    x+42 + textw(d, SEARCH_QUERY, f_search) + 4, y+32), ACCENT_HI)
    else:
        text(d, (x+42, y+12), "Поиск скина, оружия, коллекции…",
             f_search, TERTIARY)
    # shortcut badge
    rrect(d, (x+w-60, y+10, x+w-12, y+32), 6, PANEL3, outline=HAIR, width=1)
    text(d, (x+w-55, y+14), "⌘ K", f_desc, SECOND)

def draw_kind_chips(d, x, y, w):
    chips = [("Все", None), *[(KIND_LABEL[k], k) for k in KIND_ORDER]]
    cx = x
    for label, kind in chips:
        tw = textw(d, label, f_chip)
        cw = int(tw) + 28
        active = (kind == ACTIVE_KIND)
        bg = ACCENT if active else PANEL3
        rrect(d, (cx, y, cx+cw, y+32), 16, bg,
              outline=None if active else HAIR, width=1)
        text(d, (cx + (cw - tw)/2, y + 8), label, f_chip,
             WHITE if active else LABEL)
        # count
        total = 0
        for name, e in CATALOG.items():
            if kind is None or e["kind"] == kind:
                total += len(e["skins"])
        cnt = str(total)
        cw_cnt = textw(d, cnt, f_tiny)
        cx += cw + 8
    # right-side count
    total = sum(len(e["skins"]) for e in CATALOG.values())
    s = f"{total} скинов · {len(CATALOG)} оружий"
    text(d, (x + w - textw(d, s, f_desc), y + 10), s, f_desc, SECOND)

def draw_weapon_list(d, x, y, w, h):
    rrect(d, (x, y, x+w, y+h), 12, PANEL)
    text(d, (x+16, y+12), "ОРУЖИЕ", f_sec, TERTIARY)
    yy = y + 36
    weapons = sorted(CATALOG.items(),
                     key=lambda it: (KIND_ORDER.index(it[1]["kind"]),
                                     it[0]))
    cur_kind = None
    for name, e in weapons:
        if e["kind"] != cur_kind:
            cur_kind = e["kind"]
            text(d, (x+16, yy), KIND_LABEL[cur_kind].upper(), f_sec, TERTIARY)
            yy += 20
        active = (name == ACTIVE_WEAPON)
        row_h = 26
        if active:
            rrect(d, (x+6, yy-2, x+w-6, yy+row_h-2), 7, (60, 22, 46))
            rect_px(d, (x+6, yy-2, x+10, yy+row_h-2), ACCENT_HI)
        text(d, (x+22, yy+3), name, f_row,
             ACCENT_HI if active else LABEL, max_w=w-60)
        cnt = str(len(e["skins"]))
        cw = textw(d, cnt, f_desc)
        text(d, (x+w-14-cw, yy+5), cnt, f_desc, SECOND)
        yy += row_h
        if yy > y + h - 12: break

def draw_grid(img, d, x, y, w, h):
    rrect(d, (x, y, x+w, y+h), 12, PANEL)

    # title row
    skins = CATALOG[ACTIVE_WEAPON]["skins"]
    if SEARCH_QUERY:
        q = SEARCH_QUERY.lower()
        skins = [s for s in skins if q in s["name"].lower()]
    text(d, (x+18, y+12), f"{ACTIVE_WEAPON} · {len(skins)} скинов",
         f_h2, LABEL)
    right = f"активен: {ACTIVE_SKIN}"
    text(d, (x+w-16-textw(d, right, f_desc), y+22),
         right, f_desc, SECOND)
    line_(d, (x+16, y+48, x+w-16, y+48), HAIR, width=1)

    # grid
    cols = 4
    gap = 12
    gx0 = x + 16
    gy0 = y + 62
    inner_w = w - 32
    cw = (inner_w - gap * (cols - 1)) // cols
    ch = 150

    max_rows = (y + h - gy0 - 12) // (ch + gap)
    visible = skins[:cols * max_rows]
    for i, s in enumerate(visible):
        r = i // cols; c = i % cols
        cx = gx0 + c * (cw + gap)
        cy = gy0 + r * (ch + gap)
        selected = (s["name"] == ACTIVE_SKIN)
        rrect(d, (cx, cy, cx+cw, cy+ch), 10, PANEL2)
        preview_h = ch - 38
        paste_skin(img, s["slug"], (cx+4, cy+4, cw-8, preview_h-6))
        if selected:
            rrect(d, (cx, cy, cx+cw, cy+ch), 10, outline=ACCENT_HI, width=2)
        else:
            rrect(d, (cx, cy, cx+cw, cy+ch), 10, outline=HAIR, width=1)
        rect_px(d, (cx+2, cy+ch-38, cx+cw-2, cy+ch-2), (28, 12, 38))
        text(d, (cx+10, cy+ch-33), s["name"], f_row, LABEL, max_w=cw - 20)
        text(d, (cx+10, cy+ch-18), "float 0.07", f_tiny, SECOND)

    # pager
    if len(skins) > cols * max_rows:
        py = y + h - 32
        text(d, (x+18, py),
             f"показано {cols*max_rows} из {len(skins)}",
             f_desc, SECOND)
        rrect(d, (x+w-110, py-4, x+w-18, py+18), 10, PANEL2,
              outline=HAIR, width=1)
        text(d, (x+w-96, py), "далее →", f_desc, LABEL)

def draw_footer(d, x, y, w):
    rrect(d, (x, y, x+w, y+92), 12, PANEL)
    text(d, (x+16, y+10), "StatTrak", f_row, LABEL)
    text(d, (x+16, y+28), "Счётчик фрагов на корпусе", f_desc, TERTIARY)
    rrect(d, (x+218, y+12, x+264, y+36), 12, ACCENT)
    ellipse_(d, (x+240, y+16, x+258, y+32), fill=WHITE)

    text(d, (x+310, y+10), "Износ", f_row, LABEL)
    text(d, (x+310, y+28), "0.050 · Factory New", f_desc, TERTIARY)
    bx1, bx2 = x+420, x+w-170
    by = y+22
    rrect(d, (bx1, by, bx2, by+6), 3, (60, 30, 40))
    fx = bx1 + (bx2-bx1) * 0.05
    rrect(d, (bx1, by, fx, by+6), 3, ACCENT)
    ellipse_(d, (fx-8, by-5, fx+8, by+11), fill=WHITE)

    rrect(d, (x+w-150, y+12, x+w-16, y+36), 10, ACCENT)
    aw = textw(d, "Применить", f_h3)
    text(d, (x+w-150 + (134-aw)/2, y+16), "Применить", f_h3, WHITE)

    text(d, (x+16, y+60), "Локально · сервер не видит подмену", f_desc, TERTIARY)
    text(d, (x+w-160, y+60), "AKR · 2 Years Red (ST)", f_desc, ACCENT_HI)

OUT = "/tmp/claude-0/-home-user-sezx/c19d3923-cc31-59a5-a153-26878d244cef/scratchpad"
os.makedirs(OUT, exist_ok=True)

img = Image.new("RGBA", (W, H), BG_A)
gradient_bg(img)
d = ImageDraw.Draw(img, "RGBA")
draw_header(d)
draw_sidebar(d)

MX = 18 + 216 + 14
MW = W_FINAL - MX - 18
MY = 86
text(d, (MX+2, MY-4), "Скины", f_hero, LABEL)
text(d, (MX+2, MY+30), "544 модели · 38 оружий · поиск · StatTrak · износ",
     f_desc, SECOND)

# Search bar
sr_y = MY + 64
draw_search_bar(d, MX, sr_y, MW)

# Kind chips
chip_y = sr_y + 54
draw_kind_chips(d, MX, chip_y, MW)

# Main area
main_y = chip_y + 46
list_w = 240
grid_x = MX + list_w + 14
grid_w = MW - list_w - 14
main_h = H_FINAL - main_y - 108 - 20
draw_weapon_list(d, MX, main_y, list_w, main_h)
draw_grid(img, d, grid_x, main_y, grid_w, main_h)

# Footer
f_y = main_y + main_h + 8
draw_footer(d, MX, f_y, MW)

out = f"{OUT}/so2mm_skins_real.png"
img.resize((W_FINAL, H_FINAL), Image.LANCZOS).convert("RGB").save(out, "PNG")
print(out)
