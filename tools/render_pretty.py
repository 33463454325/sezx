from PIL import Image, ImageDraw, ImageFont
import math, os, random

W, H = 1180, 820

BG_A     = (10, 4, 18)
BG_B     = (24, 8, 32)
PANEL    = (18, 8, 26)
PANEL2   = (28, 12, 38)
HAIR     = (56, 22, 70)
LABEL    = (238, 230, 240)
SECOND   = (170, 140, 170)
TERTIARY = (110, 85, 120)
ACCENT   = (235, 55, 110)
ACCENT_HI= (255, 100, 150)
GREEN    = (90, 220, 130)
AMBER    = (255, 190, 60)
RED      = (255, 70, 90)
WHITE    = (245, 236, 245)

CATS = [
    ("ГЕЙМПЛЕЙ",   ["Прицел", "ESP", "Оружие", "Движение", "Камера"]),
    ("ВИЗУАЛ",     ["HUD", "Темы", "Прицел кастом"]),
    ("МИР",        ["Утилиты", "Инвентарь", "Скины"]),
    ("БЕЗОПАСНОСТЬ",["Защита", "Humanize", "Kill-switch", "HWID"]),
    ("СИСТЕМА",    ["Профили", "Биндинги", "Макросы", "Статистика", "Лицензия"]),
]

def font(paths, size):
    for p in paths:
        try: return ImageFont.truetype(p, size)
        except Exception: pass
    return ImageFont.load_default()

SFB = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]
SF  = ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
f_hero  = font(SFB, 30)
f_h2    = font(SFB, 22)
f_h3    = font(SFB, 17)
f_sec   = font(SFB, 12)
f_row   = font(SF,  16)
f_desc  = font(SF,  12)
f_tiny  = font(SF,  10)
f_badge = font(SFB, 10)
f_num_big = font(SFB, 38)

def gradient_bg(img):
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        r = int(BG_A[0] * (1-t) + BG_B[0] * t)
        g = int(BG_A[1] * (1-t) + BG_B[1] * t)
        b = int(BG_A[2] * (1-t) + BG_B[2] * t)
        d.line([(0, y), (W, y)], fill=(r, g, b))

def rrect(d, xy, r, fill, outline=None, width=1):
    d.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)

def glow_rrect(d, xy, r, color, width=4, steps=4):
    x0, y0, x1, y1 = xy
    for i in range(steps, 0, -1):
        a = int(70 * (steps - i + 1) / steps)
        c = color + (a,)
        d.rounded_rectangle((x0 - i, y0 - i, x1 + i, y1 + i), radius=r + i, outline=c, width=1)

def switch(d, x, y, on):
    w, h = 44, 24
    track = ACCENT if on else (60, 30, 40)
    rrect(d, (x, y, x+w, y+h), h//2, track)
    kx = x + (w - h + 2) if on else x + 2
    d.ellipse((kx, y+2, kx+h-4, y+h-2), fill=WHITE)

def slider(d, x, y, w, val, right_text=""):
    d.rounded_rectangle((x, y, x+w, y+6), 3, fill=(60, 30, 40))
    fx = x + w * val
    d.rounded_rectangle((x, y, fx, y+6), 3, fill=ACCENT)
    d.ellipse((fx-8, y-5, fx+8, y+11), fill=WHITE)
    if right_text:
        d.text((x + w + 14, y - 6), right_text, font=f_row, fill=LABEL)

def gauge_bar(d, x, y, w, val, cap, label):
    pct = min(1.0, val / cap)
    color = GREEN if pct < 0.7 else AMBER if pct < 0.9 else RED
    d.rounded_rectangle((x, y, x+w, y+10), 5, fill=(50, 25, 36))
    d.rounded_rectangle((x, y, x + int(w*pct), y+10), 5, fill=color)
    d.text((x, y-16), label, font=f_desc, fill=SECOND)
    d.text((x + w - 40, y-16), f"{val:.1f}/{cap:.1f}", font=f_desc, fill=LABEL)

def sparkline(d, x, y, w, h, series, color, fill_bg=True):
    if fill_bg:
        rrect(d, (x, y, x+w, y+h), 8, PANEL2)
    if not series: return
    mn, mx = min(series), max(series)
    if mx - mn < 1e-6: mx = mn + 1
    pts = []
    for i, v in enumerate(series):
        px = x + i * w / (len(series) - 1)
        py = y + h - 8 - (v - mn) / (mx - mn) * (h - 16)
        pts.append((px, py))
    for i in range(1, len(pts)):
        d.line([pts[i-1], pts[i]], fill=color, width=2)
    # tail dot
    d.ellipse((pts[-1][0]-3, pts[-1][1]-3, pts[-1][0]+3, pts[-1][1]+3), fill=color)

def draw_header(d, active_tab):
    # gradient top band
    for y in range(80):
        t = y / 80
        r = int(60 * (1-t) + 20 * t)
        g = int(14 * (1-t) + 10 * t)
        b = int(40 * (1-t) + 26 * t)
        d.line([(0, y), (W, y)], fill=(r, g, b))
    # logo
    rrect(d, (22, 16, 54, 48), 8, ACCENT)
    d.text((28, 20), "S2", font=f_h3, fill=WHITE)
    d.text((66, 14), "so2mm", font=f_hero, fill=WHITE)
    d.text((66, 50), f"тёмно-красная  ·  arm64  ·  v2.4.1  ·  {active_tab}", font=f_desc, fill=SECOND)
    # user chip
    cx = W - 310
    rrect(d, (cx, 16, W - 22, 60), 14, (18, 8, 26), outline=HAIR, width=1)
    d.ellipse((cx+6, 22, cx+40, 56), fill=(60, 30, 50))
    d.text((cx+14, 28), "SB", font=f_h3, fill=ACCENT_HI)
    d.text((cx+52, 20), "user_4421", font=f_h3, fill=WHITE)
    d.text((cx+52, 42), "Phoenix  ·  Лиц. 63д  ·  comp_ak",
           font=f_desc, fill=SECOND)

def draw_sidebar(d, active_cat_idx, active_item_idx):
    SB_X, SB_Y, SB_W = 18, 96, 220
    rrect(d, (SB_X, SB_Y, SB_X+SB_W, H-18), 14, PANEL)
    y = SB_Y + 14
    for ci, (cat, items) in enumerate(CATS):
        d.text((SB_X+18, y), cat, font=f_sec, fill=TERTIARY)
        y += 20
        for ii, it in enumerate(items):
            if ci == active_cat_idx and ii == active_item_idx:
                glow_rrect(d, (SB_X+8, y-2, SB_X+SB_W-8, y+26), 8, ACCENT, steps=3)
                rrect(d, (SB_X+8, y-2, SB_X+SB_W-8, y+26), 8, (60, 22, 46))
                d.rectangle((SB_X+8, y-2, SB_X+12, y+26), fill=ACCENT_HI)
            d.text((SB_X+22, y+4), it, font=f_row,
                   fill=ACCENT_HI if (ci == active_cat_idx and ii == active_item_idx) else LABEL)
            y += 30
        y += 8

def draw_stats_panel(d, x, y, w, h, fps_series):
    rrect(d, (x, y, x+w, y+h), 14, PANEL)
    d.text((x+16, y+14), "СЕССИЯ", font=f_sec, fill=SECOND)
    d.text((x+16, y+34), "live", font=f_tiny, fill=ACCENT_HI)
    rrect(d, (x+w-50, y+16, x+w-16, y+36), 6, (40, 20, 32))
    d.text((x+w-44, y+18), "LIVE", font=f_badge, fill=ACCENT_HI)
    # kd big
    d.text((x+16, y+58), "K / D", font=f_desc, fill=TERTIARY)
    d.text((x+16, y+72), "17/6", font=f_num_big, fill=WHITE)
    d.text((x+w-80, y+82), "2.83", font=f_h2, fill=ACCENT_HI)
    # separator
    d.line((x+16, y+130, x+w-16, y+130), fill=HAIR, width=1)
    # fps spark
    d.text((x+16, y+140), "FPS", font=f_desc, fill=TERTIARY)
    d.text((x+w-56, y+140), f"{fps_series[-1]:.0f} avg {sum(fps_series)/len(fps_series):.0f}",
           font=f_desc, fill=LABEL)
    sparkline(d, x+16, y+158, w-32, 56, fps_series, ACCENT_HI, fill_bg=False)
    d.line((x+16, y+228, x+w-16, y+228), fill=HAIR, width=1)
    # humanize caps
    d.text((x+16, y+240), "ЛИМИТЫ HUMANIZE", font=f_sec, fill=SECOND)
    gauge_bar(d, x+16, y+278, w-32, 52.0, 58.0, "Хедшоты %")
    gauge_bar(d, x+16, y+320, w-32, 2.83, 3.30, "K/D")
    gauge_bar(d, x+16, y+362, w-32, 98.0, 105.0, "ADR")
    gauge_bar(d, x+16, y+404, w-32, 4.0,  6.0,   "Матчей в сессии")
    d.line((x+16, y+448, x+w-16, y+448), fill=HAIR, width=1)
    # status rows
    rows = [
        ("Fairplay",   "нейтрализ.",    GREEN),
        ("Kill-switch","wave 0 / чисто",GREEN),
        ("HWID spoof", "comp_ak",       GREEN),
        ("CRC flip",   "6.0ms / 0.9ms", GREEN),
        ("Потоки",     "3 заморожены",  GREEN),
    ]
    yr = y + 462
    for name, val, col in rows:
        d.ellipse((x+20, yr+4, x+30, yr+14), fill=col)
        d.text((x+40, yr), name, font=f_desc, fill=LABEL)
        d.text((x+w-100, yr), val, font=f_desc, fill=SECOND)
        yr += 22
    # panic
    rrect(d, (x+16, y+h-56, x+w-16, y+h-16), 10, (120, 24, 44))
    d.text((x + w/2 - 44, y+h-45), "ПАНИК / OFF", font=f_h3, fill=WHITE)

def draw_main_shell(d):
    MX = 18 + 220 + 14
    MW = W - MX - 300 - 18
    return MX, MW

def section_header(d, x, y, text):
    d.text((x, y), text, font=f_sec, fill=SECOND)
    return y + 20

def row(d, x, y, w, label, desc, control):
    d.text((x, y), label, font=f_row, fill=LABEL)
    d.text((x, y+22), desc, font=f_desc, fill=TERTIARY)
    control(x + w, y + 10)
    d.line((x, y+50, x+w+140, y+50), fill=HAIR, width=1)
    return y + 60

# ---------------- individual tabs ----------------

def tab_stats(d):
    MX, MW = draw_main_shell(d)
    MY = 96
    d.text((MX+2, MY-2), "Статистика", font=f_hero, fill=LABEL)
    d.text((MX+2, MY+36), "сессия · матчи · потолки · железо", font=f_desc, fill=SECOND)

    cy = MY + 74
    rrect(d, (MX, cy, MX+MW, H-18), 14, PANEL)
    px = MX + 20
    pw = MW - 40

    # 4 big tiles
    tile_w = (pw - 42) // 4
    labels = [("Убийств", "17", "+4 / матч", GREEN),
              ("Смертей", "6",  "1.5 / матч", AMBER),
              ("HS %",    "52", "cap 58",    AMBER),
              ("Сыграно", "4",  "cap 6",     GREEN)]
    tx = px
    for name, big, sub, col in labels:
        rrect(d, (tx, cy+18, tx+tile_w, cy+128), 12, PANEL2)
        d.text((tx+16, cy+28), name, font=f_sec, fill=TERTIARY)
        d.text((tx+16, cy+48), big, font=f_num_big, fill=WHITE)
        d.ellipse((tx+16, cy+100, tx+26, cy+110), fill=col)
        d.text((tx+32, cy+98), sub, font=f_desc, fill=SECOND)
        tx += tile_w + 14

    # match history chart
    chy = cy + 148
    rrect(d, (px, chy, px+pw, chy+200), 12, PANEL2)
    d.text((px+16, chy+12), "K/D по матчам сессии", font=f_sec, fill=SECOND)
    series = [2.1, 2.8, 3.2, 2.83]
    gap = (pw - 80) // max(1, len(series))
    base_y = chy + 180
    for i, v in enumerate(series):
        bx = px + 40 + i * gap
        bh = int((v / 3.5) * 120)
        c = GREEN if v < 3.0 else AMBER if v < 3.3 else RED
        rrect(d, (bx, base_y - bh, bx + gap - 20, base_y), 6, c)
        d.text((bx, base_y + 6), f"M{i+1}", font=f_desc, fill=SECOND)
        d.text((bx, base_y - bh - 18), f"{v:.2f}", font=f_desc, fill=LABEL)

    # bottom device info
    diy = chy + 220
    rrect(d, (px, diy, px+pw, H - 40), 12, PANEL2)
    d.text((px+16, diy+12), "УСТРОЙСТВО (spoof активен)", font=f_sec, fill=SECOND)
    info = [
        ("HWID реальный:",  "1a2c47e3b0...85fb98d1cc"),
        ("HWID подменён:",  "8f91...e204 (comp_ak)"),
        ("Serial spoof:",   "8f91c7a0e2043b1d"),
        ("Fingerprint:",    "samsung/beyond/beyond:14/UP1A.A8F30C/4821937:user/release-keys"),
        ("ABI:",            "arm64-v8a  ·  android-34"),
    ]
    y = diy + 40
    for k, v in info:
        d.text((px+16, y), k, font=f_desc, fill=SECOND)
        d.text((px+200, y), v, font=f_desc, fill=LABEL)
        y += 22

def tab_themes(d):
    MX, MW = draw_main_shell(d)
    MY = 96
    d.text((MX+2, MY-2), "Темы", font=f_hero, fill=LABEL)
    d.text((MX+2, MY+36), "пресеты палитры · масштаб · эффекты", font=f_desc, fill=SECOND)

    cy = MY + 74
    rrect(d, (MX, cy, MX+MW, H-18), 14, PANEL)
    px = MX + 20
    pw = MW - 40

    palettes = [
        ("Blood Red",  (235, 55, 72),   (120, 20, 30), True),
        ("Dark Red",   (190, 40, 60),   (90,  18, 28), False),
        ("Obsidian",   (190, 140, 50),  (40,  30, 20), False),
        ("Midnight",   (80,  140, 240), (20,  30, 60), False),
        ("Neon Rose",  (230, 80, 230),  (60,  20, 70), False),
        ("Carbon",     (60,  230, 220), (14,  40, 46), False),
    ]
    cw = (pw - 24) // 3
    ch = 160
    for i, (name, hi, lo, active) in enumerate(palettes):
        r = i // 3; c = i % 3
        x = px + c * (cw + 12)
        y = cy + 18 + r * (ch + 14)
        if active:
            glow_rrect(d, (x, y, x+cw, y+ch), 14, hi, steps=4)
        rrect(d, (x, y, x+cw, y+ch), 14, PANEL2, outline=hi if active else None, width=2 if active else 0)
        # palette preview
        rrect(d, (x+14, y+14, x+cw-14, y+70), 10, lo)
        # swatches
        sw_x = x + 18
        for col in [hi, (hi[0]//2, hi[1]//2, hi[2]//2), (255, 255, 255), (170, 170, 170)]:
            d.ellipse((sw_x, y+24, sw_x+28, y+52), fill=col, outline=HAIR, width=1)
            sw_x += 36
        d.text((x+16, y+86), name, font=f_h3, fill=LABEL)
        d.text((x+16, y+112), "основной · фон · 2 акцента", font=f_desc, fill=SECOND)
        if active:
            rrect(d, (x+cw-70, y+108, x+cw-14, y+134), 7, hi)
            d.text((x+cw-58, y+112), "активно", font=f_badge, fill=WHITE)
        else:
            rrect(d, (x+cw-70, y+108, x+cw-14, y+134), 7, (40, 20, 30))
            d.text((x+cw-56, y+112), "выбрать", font=f_badge, fill=LABEL)

    # bottom options
    oy = cy + 18 + 2 * (ch + 14) + 10
    rrect(d, (px, oy, px+pw, H - 40), 14, PANEL2)
    opts = [
        ("Акцентный свет",   "Мягкое свечение вокруг активной вкладки", True),
        ("Полупрозрачность", "Фон меню пропускает часть изображения",   False),
        ("Крупные кнопки",   "Увеличенный padding для сенсорного ввода",True),
        ("Анимации",         "Плавные переходы между вкладками",        True),
    ]
    y = oy + 20
    for name, desc, on in opts:
        d.text((px+16, y), name, font=f_row, fill=LABEL)
        d.text((px+16, y+22), desc, font=f_desc, fill=TERTIARY)
        switch(d, px + pw - 60, y+10, on)
        d.line((px+16, y+50, px+pw-16, y+50), fill=HAIR, width=1)
        y += 60

def tab_inventory(d):
    MX, MW = draw_main_shell(d)
    MY = 96
    d.text((MX+2, MY-2), "Инвентарь", font=f_hero, fill=LABEL)
    d.text((MX+2, MY+36), "скин · перчатки · брелок · наклейки · имятег", font=f_desc, fill=SECOND)

    cy = MY + 74
    rrect(d, (MX, cy, MX+MW, H-18), 14, PANEL)
    px = MX + 20
    pw = MW - 40

    # big weapon card
    wc_h = 260
    rrect(d, (px, cy+18, px+pw, cy+18+wc_h), 14, PANEL2)
    # weapon preview area (gradient)
    for y in range(wc_h - 40):
        t = y / (wc_h - 40)
        r = int(60 * (1-t) + 20 * t)
        g = int(20 * (1-t) + 10 * t)
        b = int(40 * (1-t) + 25 * t)
        d.line([(px+16, cy+34+y), (px+pw-16, cy+34+y)], fill=(r, g, b))
    rrect(d, (px+16, cy+34, px+pw-16, cy+18+wc_h-20), 10, None, outline=HAIR, width=1)
    # faux weapon silhouette
    d.line((px+80, cy+150, px+pw-100, cy+150), fill=(210, 190, 120), width=22)
    d.line((px+80, cy+150, px+pw-100, cy+150), fill=(60, 40, 20),    width=4)
    rrect(d, (px+pw-160, cy+135, px+pw-110, cy+180), 6, (120, 60, 30))
    # name + tags
    d.text((px+30, cy+42), "AKR  ·  2Years Red", font=f_h2, fill=LABEL)
    rrect(d, (px+30, cy+74, px+70, cy+96), 6, (120, 30, 42))
    d.text((px+38, cy+76), "ST", font=f_badge, fill=WHITE)
    rrect(d, (px+78, cy+74, px+150, cy+96), 6, (40, 70, 50))
    d.text((px+84, cy+78), "Factory New", font=f_badge, fill=GREEN)
    d.text((px+30, cy+102), "Износ 0.070  ·  #PATTERN 731  ·  2Years Collection", font=f_desc, fill=SECOND)
    # stickers strip
    for i, name in enumerate(["Shattered Web", "Dragon Lore", "Katowice 14", "—", "—"]):
        sx = px + 30 + i*86
        rrect(d, (sx, cy+18+wc_h-74, sx+76, cy+18+wc_h-28), 8, (36, 20, 32))
        if name != "—":
            rrect(d, (sx+8, cy+18+wc_h-66, sx+68, cy+18+wc_h-42), 5, (160, 60, 80))
            d.text((sx+8, cy+18+wc_h-40), name[:10], font=f_tiny, fill=LABEL)
        else:
            d.text((sx+32, cy+18+wc_h-52), "+", font=f_h3, fill=TERTIARY)

    # gloves + charm cards
    row_y = cy + 18 + wc_h + 14
    card_w = (pw - 14) // 2
    rrect(d, (px, row_y, px+card_w, row_y+130), 12, PANEL2)
    d.text((px+16, row_y+14), "ПЕРЧАТКИ", font=f_sec, fill=SECOND)
    d.text((px+16, row_y+38), "Specialist — Fade", font=f_h3, fill=LABEL)
    d.text((px+16, row_y+66), "Износ 0.12  ·  редкий паттерн", font=f_desc, fill=TERTIARY)
    rrect(d, (px+16, row_y+94, px+140, row_y+122), 8, (60, 22, 44))
    d.text((px+28, row_y+100), "Сменить", font=f_desc, fill=LABEL)

    rrect(d, (px+card_w+14, row_y, px+pw, row_y+130), 12, PANEL2)
    d.text((px+card_w+30, row_y+14), "БРЕЛОК", font=f_sec, fill=SECOND)
    d.text((px+card_w+30, row_y+38), "Красный дракончик", font=f_h3, fill=LABEL)
    d.text((px+card_w+30, row_y+66), "swinging on the AKR", font=f_desc, fill=TERTIARY)
    rrect(d, (px+card_w+30, row_y+94, px+card_w+154, row_y+122), 8, (60, 22, 44))
    d.text((px+card_w+42, row_y+100), "Сменить", font=f_desc, fill=LABEL)

    # nametag bar
    ny = row_y + 150
    rrect(d, (px, ny, px+pw, ny+70), 12, PANEL2)
    d.text((px+16, ny+14), "ИМЯТЕГ", font=f_sec, fill=SECOND)
    rrect(d, (px+16, ny+36, px+pw-120, ny+66), 8, (36, 20, 32))
    d.text((px+28, ny+42), "comp_ak // phx", font=f_row, fill=LABEL)
    rrect(d, (px+pw-100, ny+36, px+pw-16, ny+66), 8, ACCENT)
    d.text((px+pw-82, ny+42), "Применить", font=f_desc, fill=WHITE)

def tab_keybinds(d):
    MX, MW = draw_main_shell(d)
    MY = 96
    d.text((MX+2, MY-2), "Биндинги", font=f_hero, fill=LABEL)
    d.text((MX+2, MY+36), "горячие клавиши и жесты", font=f_desc, fill=SECOND)

    cy = MY + 74
    rrect(d, (MX, cy, MX+MW, H-18), 14, PANEL)
    px = MX + 20
    pw = MW - 40

    binds = [
        ("Открыть меню",         "Показать / скрыть окно модуля",            "3 пальца",  False),
        ("Переключить аимбот",   "On/off без открытия меню",                 "Vol-",      False),
        ("Переключить ESP",      "Быстрое скрытие рамок",                    "Vol+",      False),
        ("Переключить стены",    "Chams по стенам on/off",                   "—",         False),
        ("Паник — выключить всё","Снять все хуки и спрятать меню (long)",    "Power (×2)",True),
        ("Следующий профиль",    "Циклить сохранённые профили",              "—",         False),
        ("Предыдущий профиль",   "",                                         "—",         False),
        ("Применить скин",       "Перезаписать текущий скин в руках",        "—",         False),
        ("Инспектировать",       "Анимация осмотра оружия",                  "—",         False),
    ]

    y = cy + 18
    rrect(d, (px, y, px+pw, y+40), 10, PANEL2)
    d.text((px+16, y+10), "ДЕЙСТВИЕ", font=f_sec, fill=SECOND)
    d.text((px+pw-280, y+10), "КНОПКА",  font=f_sec, fill=SECOND)
    d.text((px+pw-130, y+10), "LONG",    font=f_sec, fill=SECOND)
    y += 48

    for name, desc, key, longp in binds:
        rrect(d, (px, y, px+pw, y+60), 10, PANEL2)
        d.text((px+16, y+10), name, font=f_row, fill=LABEL)
        d.text((px+16, y+32), desc, font=f_desc, fill=TERTIARY)
        # key chip
        rrect(d, (px+pw-290, y+16, px+pw-150, y+44), 8, (40, 20, 32), outline=HAIR, width=1)
        d.text((px+pw-272, y+20), key, font=f_row, fill=LABEL if key != "—" else TERTIARY)
        # long-press switch
        switch(d, px+pw-120, y+18, longp)
        y += 70

# ---------------- render ----------------

OUT = "/tmp/claude-0/-home-user-sezx/c19d3923-cc31-59a5-a153-26878d244cef/scratchpad"
os.makedirs(OUT, exist_ok=True)

random.seed(42)
fps_series = [60 + random.random()*20 + math.sin(i/6)*4 for i in range(90)]

def render(tab_name, draw_body, active_cat, active_item, out):
    img = Image.new("RGBA", (W, H), BG_A)
    gradient_bg(img)
    d = ImageDraw.Draw(img)
    draw_header(d, tab_name)
    draw_sidebar(d, active_cat, active_item)
    draw_body(d)
    draw_stats_panel(d, W - 300 + 6, 96, 282, H - 96 - 18, fps_series)
    img.convert("RGB").save(out, "PNG")
    return out

paths = []
paths.append(render("Статистика", tab_stats,    4, 3, f"{OUT}/so2mm_pretty_stats.png"))
paths.append(render("Темы",        tab_themes,   1, 1, f"{OUT}/so2mm_pretty_themes.png"))
paths.append(render("Инвентарь",   tab_inventory,2, 1, f"{OUT}/so2mm_pretty_inventory.png"))
paths.append(render("Биндинги",    tab_keybinds, 4, 1, f"{OUT}/so2mm_pretty_keybinds.png"))
for p in paths: print(p)
