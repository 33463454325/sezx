from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os, random, sys
sys.path.insert(0, os.path.dirname(__file__))
from _brand import apply_watermark, header_logo

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
RED      = (255, 70, 90)
WHITE    = (245, 236, 245)

CATS = [
    ("ГЕЙМПЛЕЙ",    ["Прицел", "ESP", "Оружие", "Движение", "Камера"]),
    ("ВИЗУАЛ",      ["HUD", "Темы", "Кастом прицел"]),
    ("МИР",         ["Утилиты", "Инвентарь", "Скины"]),
    ("БЕЗОПАСНОСТЬ",["Защита", "Humanize", "Kill-switch", "HWID"]),
    ("СИСТЕМА",     ["Профили", "Биндинги", "Макросы", "Статистика", "Лицензия"]),
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
f_h3    = font(SFB, 15)
f_sec   = font(SFB, 11)
f_row   = font(SF,  14)
f_desc  = font(SF,  11)
f_tiny  = font(SF,  10)
f_badge = font(SFB, 10)
f_num   = font(SFB, 30)

def rrect(d, xy, r, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = xy
    d.rounded_rectangle((x0*SCALE, y0*SCALE, x1*SCALE, y1*SCALE),
                        radius=r*SCALE, fill=fill, outline=outline,
                        width=int(width*SCALE))

def rect(d, xy, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = xy
    d.rectangle((x0*SCALE, y0*SCALE, x1*SCALE, y1*SCALE),
                fill=fill, outline=outline, width=int(width*SCALE))

def line(d, xy, fill, width=1):
    x0, y0, x1, y1 = xy
    d.line((x0*SCALE, y0*SCALE, x1*SCALE, y1*SCALE),
           fill=fill, width=int(width*SCALE))

def ellipse(d, xy, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = xy
    d.ellipse((x0*SCALE, y0*SCALE, x1*SCALE, y1*SCALE),
              fill=fill, outline=outline, width=int(width*SCALE))

def text(d, xy, s, f, fill, max_w=None):
    x, y = xy
    if max_w is not None:
        s = clip_text(d, s, f, max_w)
    d.text((x*SCALE, y*SCALE), s, font=f, fill=fill)

def textw(d, s, f):
    return d.textlength(s, font=f) / SCALE

def clip_text(d, s, f, max_w):
    if textw(d, s, f) <= max_w: return s
    while len(s) > 1 and textw(d, s + "…", f) > max_w:
        s = s[:-1]
    return s + "…"

def gradient_bg(img):
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        r = int(BG_A[0] * (1-t) + BG_B[0] * t)
        g = int(BG_A[1] * (1-t) + BG_B[1] * t)
        b = int(BG_A[2] * (1-t) + BG_B[2] * t)
        d.line([(0, y), (W, y)], fill=(r, g, b))
    apply_watermark(img, size_frac=0.80, alpha=24)

def soft_shadow(img, box, radius=14, blur=10, alpha=120):
    sh = Image.new("RGBA", img.size, (0,0,0,0))
    sd = ImageDraw.Draw(sh)
    x0, y0, x1, y1 = box
    sd.rounded_rectangle((x0*SCALE, (y0+4)*SCALE, x1*SCALE, (y1+6)*SCALE),
                         radius=radius*SCALE, fill=(0, 0, 0, alpha))
    sh = sh.filter(ImageFilter.GaussianBlur(radius=blur*SCALE/2))
    img.alpha_composite(sh)

def switch(d, x, y, on):
    w, h = 42, 24
    track = ACCENT if on else (60, 30, 40)
    rrect(d, (x, y, x+w, y+h), h//2, track)
    kx = x + (w - h + 2) if on else x + 2
    ellipse(d, (kx, y+2, kx+h-4, y+h-2), fill=WHITE)

def slider(d, x, y, w, val, right_text=""):
    rrect(d, (x, y, x+w, y+5), 3, fill=(60, 30, 40))
    fx = x + w * val
    rrect(d, (x, y, fx, y+5), 3, fill=ACCENT)
    ellipse(d, (fx-7, y-4, fx+7, y+10), fill=WHITE)
    if right_text:
        text(d, (x + w + 12, y - 6), right_text, f_row, LABEL)

def gauge_bar(d, x, y, w, val, cap, label):
    pct = min(1.0, val / cap)
    color = GREEN if pct < 0.7 else AMBER if pct < 0.9 else RED
    rrect(d, (x, y, x+w, y+8), 4, fill=(50, 25, 36))
    rrect(d, (x, y, x + int(w*pct), y+8), 4, fill=color)
    text(d, (x, y-16), label, f_desc, SECOND)
    right = f"{val:.1f} / {cap:.1f}"
    rw = textw(d, right, f_desc)
    text(d, (x + w - rw, y-16), right, f_desc, LABEL)

def sparkline_smooth(d, x, y, w, h, series, color):
    rrect(d, (x, y, x+w, y+h), 8, fill=(22, 10, 32))
    if len(series) < 2: return
    mn, mx = min(series), max(series)
    if mx - mn < 1e-6: mx = mn + 1
    pts = []
    for i, v in enumerate(series):
        px = x + i * w / (len(series) - 1)
        py = y + h - 8 - (v - mn) / (mx - mn) * (h - 16)
        pts.append((px, py))
    # fill under line
    poly = [(x, y+h-4)] + pts + [(x+w, y+h-4)]
    d.polygon([(p[0]*SCALE, p[1]*SCALE) for p in poly], fill=(color[0], color[1], color[2], 40))
    for i in range(1, len(pts)):
        line(d, (pts[i-1][0], pts[i-1][1], pts[i][0], pts[i][1]), color, width=2)
    ellipse(d, (pts[-1][0]-3, pts[-1][1]-3, pts[-1][0]+3, pts[-1][1]+3), fill=color)

def draw_header(d, active_tab):
    for y in range(78):
        t = y / 78
        r = int(60 * (1-t) + 20 * t)
        g = int(14 * (1-t) + 10 * t)
        b = int(40 * (1-t) + 26 * t)
        d.line([(0, y*SCALE), (W, y*SCALE)], fill=(r, g, b), width=SCALE)
    # logo
    text(d, (90, 12), "VEKTOR", f_hero, WHITE)
    text(d, (66, 46), f"тёмно-красная · arm64 · v2.4.1 · {active_tab}",
         f_desc, SECOND, max_w=W_FINAL//2)
    # user chip
    cx = W_FINAL - 302
    rrect(d, (cx, 14, W_FINAL - 22, 60), 14, (18, 8, 26), outline=HAIR, width=1)
    ellipse(d, (cx+8, 22, cx+40, 54), fill=(60, 30, 50))
    text(d, (cx+15, 27), "SB", f_h3, ACCENT_HI)
    text(d, (cx+50, 20), "user_4421", f_h3, WHITE, max_w=160)
    text(d, (cx+50, 40), "Phoenix · 63 д · comp_ak",
         f_desc, SECOND, max_w=220)

def draw_sidebar(d, active_cat_idx, active_item_idx):
    SB_X, SB_Y, SB_W = 18, 94, 216
    rrect(d, (SB_X, SB_Y, SB_X+SB_W, H_FINAL-18), 14, PANEL)
    y = SB_Y + 14
    for ci, (cat, items) in enumerate(CATS):
        text(d, (SB_X+18, y), cat, f_sec, TERTIARY)
        y += 20
        for ii, it in enumerate(items):
            active = (ci == active_cat_idx and ii == active_item_idx)
            if active:
                rrect(d, (SB_X+8, y-2, SB_X+SB_W-8, y+24), 8, (60, 22, 46))
                rect(d, (SB_X+8, y-2, SB_X+12, y+24), fill=ACCENT_HI)
            text(d, (SB_X+22, y+3), it, f_row,
                 ACCENT_HI if active else LABEL, max_w=SB_W-40)
            y += 28
        y += 8

def draw_stats_panel(d, x, y, w, h, fps_series):
    rrect(d, (x, y, x+w, y+h), 14, PANEL)
    text(d, (x+16, y+14), "СЕССИЯ", f_sec, SECOND)
    rrect(d, (x+w-62, y+14, x+w-16, y+32), 6, (40, 20, 32))
    text(d, (x+w-55, y+17), "LIVE", f_badge, ACCENT_HI)

    text(d, (x+16, y+44), "K / D", f_desc, TERTIARY)
    text(d, (x+16, y+58), "17 / 6", f_num, WHITE)
    kd_s = "2.83"
    kdw = textw(d, kd_s, f_h2)
    text(d, (x+w-16-kdw, y+68), kd_s, f_h2, ACCENT_HI)

    line(d, (x+16, y+110, x+w-16, y+110), HAIR, width=1)

    text(d, (x+16, y+122), "FPS", f_desc, TERTIARY)
    r = f"{fps_series[-1]:.0f}  avg {sum(fps_series)/len(fps_series):.0f}"
    rw = textw(d, r, f_desc)
    text(d, (x+w-16-rw, y+122), r, f_desc, LABEL)
    sparkline_smooth(d, x+16, y+140, w-32, 54, fps_series, ACCENT_HI)

    line(d, (x+16, y+208, x+w-16, y+208), HAIR, width=1)

    text(d, (x+16, y+220), "ЛИМИТЫ HUMANIZE", f_sec, SECOND)
    gauge_bar(d, x+16, y+254, w-32, 52.0, 58.0, "Хедшоты %")
    gauge_bar(d, x+16, y+294, w-32, 2.83, 3.30, "K/D")
    gauge_bar(d, x+16, y+334, w-32, 98.0, 105.0, "ADR")
    gauge_bar(d, x+16, y+374, w-32, 4.0,  6.0,  "Матчей в сессии")

    line(d, (x+16, y+412, x+w-16, y+412), HAIR, width=1)

    rows = [
        ("Fairplay",    "нейтрализ.",     GREEN),
        ("Kill-switch", "wave 0 · чисто", GREEN),
        ("HWID spoof",  "comp_ak",        GREEN),
        ("CRC flip",    "6 мс / 0.9 мс",  GREEN),
        ("Потоки",      "3 заморожены",   GREEN),
    ]
    yr = y + 424
    for name, val, col in rows:
        ellipse(d, (x+20, yr+5, x+28, yr+13), fill=col)
        text(d, (x+36, yr), name, f_desc, LABEL)
        vw = textw(d, val, f_desc)
        text(d, (x+w-16-vw, yr), val, f_desc, SECOND)
        yr += 22

    rrect(d, (x+16, y+h-52, x+w-16, y+h-14), 10, (120, 24, 44))
    txt = "ПАНИК — всё OFF"
    tw = textw(d, txt, f_h3)
    text(d, (x + w/2 - tw/2, y+h-42), txt, f_h3, WHITE)

def main_box():
    MX = 18 + 216 + 14
    PANEL_R_W = 294
    MW = W_FINAL - MX - PANEL_R_W - 18 - 6
    return MX, MW

def row(d, x, y, w, label, desc, control):
    text(d, (x, y), label, f_row, LABEL, max_w=w)
    text(d, (x, y+20), desc, f_desc, TERTIARY, max_w=w+80)
    control(x + w + 80, y + 10)
    line(d, (x, y+46, x+w+130, y+46), HAIR, width=1)
    return y + 56

# ---------------- tabs ----------------

def tab_stats(d):
    MX, MW = main_box()
    MY = 94
    text(d, (MX+2, MY-2), "Статистика", f_hero, LABEL)
    text(d, (MX+2, MY+32), "сессия · матчи · потолки · железо", f_desc, SECOND)

    cy = MY + 70
    rrect(d, (MX, cy, MX+MW, H_FINAL-18), 14, PANEL)
    px = MX + 18
    pw = MW - 36

    tiles = [
        ("Убийств", "17", "+4 / матч",  GREEN),
        ("Смертей", "6",  "1.5 / матч", AMBER),
        ("HS %",    "52", "cap 58",     AMBER),
        ("Сыграно", "4",  "cap 6",      GREEN),
    ]
    tile_w = (pw - 42) // 4
    tx = px
    for name, big, sub, col in tiles:
        rrect(d, (tx, cy+16, tx+tile_w, cy+120), 12, PANEL2)
        text(d, (tx+14, cy+24), name, f_sec, TERTIARY, max_w=tile_w-20)
        text(d, (tx+14, cy+42), big, f_num, WHITE)
        ellipse(d, (tx+14, cy+96, tx+22, cy+104), fill=col)
        text(d, (tx+28, cy+94), sub, f_desc, SECOND, max_w=tile_w-40)
        tx += tile_w + 14

    chy = cy + 136
    chart_h = 180
    rrect(d, (px, chy, px+pw, chy+chart_h), 12, PANEL2)
    text(d, (px+16, chy+12), "K/D по матчам сессии", f_sec, SECOND)
    series = [2.1, 2.8, 3.2, 2.83]
    gap = (pw - 64) / len(series)
    base_y = chy + chart_h - 28
    for i, v in enumerate(series):
        bx = px + 32 + i * gap
        bw = gap - 24
        bh = int((v / 3.5) * (chart_h - 70))
        c = GREEN if v < 3.0 else AMBER if v < 3.3 else RED
        rrect(d, (bx, base_y - bh, bx + bw, base_y), 6, c)
        text(d, (bx, base_y + 6), f"М{i+1}", f_desc, SECOND)
        vt = f"{v:.2f}"
        vw = textw(d, vt, f_desc)
        text(d, (bx + bw/2 - vw/2, base_y - bh - 16), vt, f_desc, LABEL)

    diy = chy + chart_h + 14
    rrect(d, (px, diy, px+pw, H_FINAL - 32), 12, PANEL2)
    text(d, (px+16, diy+12), "УСТРОЙСТВО · SPOOF АКТИВЕН", f_sec, SECOND)
    info = [
        ("HWID реальный",    "1a2c47e3b0…85fb98d1cc"),
        ("HWID подменён",    "8f91…e204 · профиль comp_ak"),
        ("Serial spoof",     "8f91c7a0e2043b1d"),
        ("Fingerprint",      "samsung/beyond:14/UP1A.A8F30C/482… release-keys"),
        ("ABI · API level",  "arm64-v8a · android-34"),
    ]
    y = diy + 40
    key_x = px + 16
    val_x = px + 180
    for k, v in info:
        text(d, (key_x, y), k, f_desc, SECOND, max_w=160)
        text(d, (val_x, y), v, f_desc, LABEL, max_w=pw - 200)
        y += 22

def tab_themes(d):
    MX, MW = main_box()
    MY = 94
    text(d, (MX+2, MY-2), "Темы", f_hero, LABEL)
    text(d, (MX+2, MY+32), "пресеты палитры · масштаб · эффекты", f_desc, SECOND)

    cy = MY + 70
    rrect(d, (MX, cy, MX+MW, H_FINAL-18), 14, PANEL)
    px = MX + 18
    pw = MW - 36

    palettes = [
        ("Blood Red",  (235, 55, 72),   (60, 18, 28),  True),
        ("Dark Red",   (190, 40, 60),   (50, 14, 22),  False),
        ("Obsidian",   (190, 140, 50),  (34, 26, 18),  False),
        ("Midnight",   (80,  140, 240), (18, 28, 56),  False),
        ("Neon Rose",  (230, 80, 230),  (50, 18, 60),  False),
        ("Carbon",     (60,  230, 220), (14, 36, 42),  False),
    ]
    cw = (pw - 24) // 3
    ch = 150
    for i, (name, hi, lo, active) in enumerate(palettes):
        r = i // 3; c = i % 3
        x = px + c * (cw + 12)
        y = cy + 16 + r * (ch + 14)
        rrect(d, (x, y, x+cw, y+ch), 14, PANEL2,
              outline=hi if active else None, width=2 if active else 1)
        rrect(d, (x+12, y+12, x+cw-12, y+62), 10, lo)
        sw_x = x + 18
        swatches = [hi,
                    (int(hi[0]*0.6), int(hi[1]*0.6), int(hi[2]*0.6)),
                    (230, 230, 230),
                    (150, 150, 150)]
        for col in swatches:
            ellipse(d, (sw_x, y+22, sw_x+28, y+50), fill=col, outline=HAIR, width=1)
            sw_x += 34
        text(d, (x+14, y+76), name, f_h3, LABEL, max_w=cw-80)
        text(d, (x+14, y+100), "основной · фон · акценты", f_desc, SECOND, max_w=cw-80)
        badge_label = "активно" if active else "выбрать"
        bw = max(60, int(textw(d, badge_label, f_badge)) + 16)
        rrect(d, (x+cw-bw-12, y+ch-30, x+cw-12, y+ch-10), 7,
              hi if active else (40, 20, 30))
        text(d, (x+cw-bw-12 + (bw - textw(d, badge_label, f_badge))/2,
                 y+ch-28), badge_label, f_badge, WHITE if active else LABEL)

    oy = cy + 16 + 2 * (ch + 14) + 10
    rrect(d, (px, oy, px+pw, H_FINAL - 32), 14, PANEL2)
    opts = [
        ("Акцентный свет",    "Мягкое свечение вокруг активной вкладки",  True),
        ("Полупрозрачность",  "Фон меню пропускает часть изображения",    False),
        ("Крупные кнопки",    "Увеличенный padding для сенсорного ввода", True),
        ("Анимации",          "Плавные переходы между вкладками",         True),
    ]
    y = oy + 14
    for name, desc, on in opts:
        text(d, (px+16, y), name, f_row, LABEL)
        text(d, (px+16, y+20), desc, f_desc, TERTIARY, max_w=pw-120)
        switch(d, px + pw - 60, y+10, on)
        line(d, (px+16, y+46, px+pw-16, y+46), HAIR, width=1)
        y += 52

def tab_inventory(d):
    MX, MW = main_box()
    MY = 94
    text(d, (MX+2, MY-2), "Инвентарь", f_hero, LABEL)
    text(d, (MX+2, MY+32), "скин · перчатки · брелок · наклейки · имятег",
         f_desc, SECOND)

    cy = MY + 70
    rrect(d, (MX, cy, MX+MW, H_FINAL-18), 14, PANEL)
    px = MX + 18
    pw = MW - 36

    wc_h = 240
    rrect(d, (px, cy+16, px+pw, cy+16+wc_h), 14, PANEL2)
    # inner preview with vertical gradient
    inner = (px+14, cy+30, px+pw-14, cy+16+wc_h-14)
    for yy in range(inner[1], inner[3]):
        t = (yy - inner[1]) / max(1, inner[3] - inner[1])
        r = int(70 * (1-t) + 24 * t)
        g = int(24 * (1-t) + 12 * t)
        b = int(50 * (1-t) + 30 * t)
        d.rectangle((inner[0]*SCALE, yy*SCALE, inner[2]*SCALE, yy*SCALE+SCALE),
                    fill=(r, g, b))
    rrect(d, inner, 10, outline=HAIR, width=1)

    # faux weapon silhouette (barrel + body + grip + mag)
    gun_y = cy + 150
    line(d, (px+90, gun_y, px+pw-150, gun_y), (210, 190, 120), width=14)
    line(d, (px+90, gun_y, px+pw-150, gun_y), (90, 60, 30), width=3)
    rrect(d, (px+pw-180, gun_y-18, px+pw-128, gun_y+16), 4, (150, 70, 40))
    rrect(d, (px+pw-230, gun_y+10, px+pw-180, gun_y+56), 4, (90, 60, 40))

    text(d, (px+28, cy+40), "AKR · 2Years Red", f_h2, LABEL, max_w=pw-200)
    rrect(d, (px+28, cy+72, px+66, cy+92), 6, (120, 30, 42))
    text(d, (px+37, cy+74), "ST", f_badge, WHITE)
    rrect(d, (px+72, cy+72, px+174, cy+92), 6, (40, 70, 50))
    text(d, (px+80, cy+74), "Factory New", f_badge, GREEN)
    text(d, (px+28, cy+100), "Износ 0.070 · паттерн #731 · коллекция 2Years",
         f_desc, SECOND, max_w=pw-60)

    # stickers strip — внутри карточки, 5 слотов
    strip_y = cy + 16 + wc_h - 72
    slot_w = (pw - 32 - 16) // 5
    slot_names = ["SW", "DL", "KT14", "", ""]
    slot_full  = ["Shattered Web", "Dragon Lore", "Katowice 14", "—", "—"]
    for i in range(5):
        sx = px + 16 + i * (slot_w + 4)
        rrect(d, (sx, strip_y, sx+slot_w, strip_y+56), 8, (36, 20, 32))
        if slot_names[i]:
            rrect(d, (sx+8, strip_y+8, sx+slot_w-8, strip_y+34), 5, (160, 60, 80))
            text(d, (sx+8 + (slot_w-16)/2 - textw(d, slot_names[i], f_badge)/2,
                     strip_y+14), slot_names[i], f_badge, WHITE)
            text(d, (sx+6, strip_y+38), slot_full[i], f_tiny, LABEL,
                 max_w=slot_w-12)
        else:
            tw = textw(d, "+", f_h3)
            text(d, (sx + slot_w/2 - tw/2, strip_y+14), "+", f_h3, TERTIARY)
            text(d, (sx+6, strip_y+40), "пусто", f_tiny, TERTIARY)

    row_y = cy + 16 + wc_h + 14
    card_w = (pw - 14) // 2
    # gloves
    rrect(d, (px, row_y, px+card_w, row_y+120), 12, PANEL2)
    text(d, (px+16, row_y+14), "ПЕРЧАТКИ", f_sec, SECOND)
    text(d, (px+16, row_y+34), "Specialist · Fade", f_h3, LABEL, max_w=card_w-32)
    text(d, (px+16, row_y+58), "Износ 0.12 · редкий паттерн", f_desc, TERTIARY,
         max_w=card_w-32)
    rrect(d, (px+16, row_y+84, px+136, row_y+110), 8, (60, 22, 44))
    tw = textw(d, "Сменить", f_desc)
    text(d, (px+16 + (120-tw)/2, row_y+90), "Сменить", f_desc, LABEL)

    # charm
    cx_x = px+card_w+14
    rrect(d, (cx_x, row_y, cx_x+card_w, row_y+120), 12, PANEL2)
    text(d, (cx_x+16, row_y+14), "БРЕЛОК", f_sec, SECOND)
    text(d, (cx_x+16, row_y+34), "Красный дракончик", f_h3, LABEL, max_w=card_w-32)
    text(d, (cx_x+16, row_y+58), "висит на боковой планке", f_desc, TERTIARY,
         max_w=card_w-32)
    rrect(d, (cx_x+16, row_y+84, cx_x+136, row_y+110), 8, (60, 22, 44))
    text(d, (cx_x+16 + (120-tw)/2, row_y+90), "Сменить", f_desc, LABEL)

    # nametag
    ny = row_y + 134
    rrect(d, (px, ny, px+pw, ny+56), 12, PANEL2)
    text(d, (px+16, ny+10), "ИМЯТЕГ", f_sec, SECOND)
    rrect(d, (px+16, ny+28, px+pw-116, ny+50), 8, (36, 20, 32))
    text(d, (px+26, ny+32), "comp_ak · phx", f_row, LABEL, max_w=pw-170)
    rrect(d, (px+pw-100, ny+28, px+pw-16, ny+50), 8, ACCENT)
    aw = textw(d, "Применить", f_desc)
    text(d, (px+pw-100 + (84-aw)/2, ny+33), "Применить", f_desc, WHITE)

def tab_keybinds(d):
    MX, MW = main_box()
    MY = 94
    text(d, (MX+2, MY-2), "Биндинги", f_hero, LABEL)
    text(d, (MX+2, MY+32), "горячие клавиши и жесты", f_desc, SECOND)

    cy = MY + 70
    rrect(d, (MX, cy, MX+MW, H_FINAL-18), 14, PANEL)
    px = MX + 18
    pw = MW - 36

    COL_KEY_W   = 160
    COL_LONG_W  = 80
    COL_KEY_X   = px + pw - COL_LONG_W - 24 - COL_KEY_W
    COL_LONG_X  = px + pw - COL_LONG_W + 8

    y = cy + 14
    rrect(d, (px, y, px+pw, y+34), 10, PANEL2)
    text(d, (px+16, y+9), "ДЕЙСТВИЕ", f_sec, SECOND)
    text(d, (COL_KEY_X, y+9),  "КНОПКА", f_sec, SECOND)
    text(d, (COL_LONG_X, y+9), "LONG",   f_sec, SECOND)
    y += 42

    binds = [
        ("Открыть меню",          "Показать / скрыть окно модуля",         "3 пальца",  False),
        ("Переключить аимбот",    "On / off без открытия меню",            "Vol −",     False),
        ("Переключить ESP",       "Быстро скрыть рамки",                   "Vol +",     False),
        ("Переключить стены",     "Chams по стенам on / off",              "—",         False),
        ("Паник — выключить всё", "Снять все хуки и спрятать меню",        "Power ×2",  True),
        ("Следующий профиль",     "Циклить сохранённые профили",           "—",         False),
        ("Предыдущий профиль",    "",                                      "—",         False),
        ("Применить скин",        "Перезаписать текущий скин в руках",     "—",         False),
        ("Инспектировать",        "Анимация осмотра оружия",               "—",         False),
    ]
    for name, desc, key, longp in binds:
        rrect(d, (px, y, px+pw, y+60), 10, PANEL2)
        text(d, (px+16, y+9),  name, f_row,  LABEL,    max_w=COL_KEY_X - px - 32)
        text(d, (px+16, y+29), desc, f_desc, TERTIARY, max_w=COL_KEY_X - px - 32)
        # key chip
        chip_w = COL_KEY_W - 8
        rrect(d, (COL_KEY_X, y+16, COL_KEY_X+chip_w, y+44), 8,
              (40, 20, 32), outline=HAIR, width=1)
        kcol = LABEL if key != "—" else TERTIARY
        kw = textw(d, key, f_row)
        text(d, (COL_KEY_X + (chip_w - kw)/2, y+20), key, f_row, kcol)
        switch(d, COL_LONG_X + 4, y+18, longp)
        y += 68

OUT = "/tmp/claude-0/-home-user-sezx/c19d3923-cc31-59a5-a153-26878d244cef/scratchpad"
os.makedirs(OUT, exist_ok=True)

random.seed(42)
fps_series = [60 + random.random()*20 + math.sin(i/6)*4 for i in range(90)]

def render(tab_name, draw_body, active_cat, active_item, out):
    img = Image.new("RGBA", (W, H), BG_A)
    gradient_bg(img)
    d = ImageDraw.Draw(img, "RGBA")
    draw_header(d, tab_name)
    header_logo(img, 16*SCALE, 8*SCALE, 60*SCALE)
    draw_sidebar(d, active_cat, active_item)
    draw_body(d)
    draw_stats_panel(d, W_FINAL - 300 + 6, 94, 282, H_FINAL - 94 - 18, fps_series)
    # downsample with LANCZOS for smooth result
    final = img.resize((W_FINAL, H_FINAL), Image.LANCZOS)
    final.convert("RGB").save(out, "PNG")
    return out

paths = [
    render("Статистика", tab_stats,     4, 3, f"{OUT}/so2mm_pretty_stats.png"),
    render("Темы",        tab_themes,    1, 1, f"{OUT}/so2mm_pretty_themes.png"),
    render("Инвентарь",   tab_inventory, 2, 1, f"{OUT}/so2mm_pretty_inventory.png"),
    render("Биндинги",    tab_keybinds,  4, 1, f"{OUT}/so2mm_pretty_keybinds.png"),
]
for p in paths: print(p)
