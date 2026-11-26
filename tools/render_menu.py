from PIL import Image, ImageDraw, ImageFont

W, H = 1180, 820
BG      = (18, 20, 28, 255)
PANEL   = (23, 26, 33, 255)
PANEL2  = (28, 31, 38, 255)
TITLE   = (72, 20, 36, 255)
ACCENT  = (247, 86, 124, 255)
ACCENT2 = (255, 128, 160, 255)
TEXT    = (230, 232, 238, 255)
MUTED   = (140, 148, 160, 255)
GREEN   = (90, 220, 130, 255)

img = Image.new("RGBA", (W, H), BG)
d = ImageDraw.Draw(img)

try:
    font_b  = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
    font_m  = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 17)
    font_s  = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
except Exception:
    font_b = font_m = font_s = ImageFont.load_default()

def rrect(xy, radius, fill, outline=None, width=1):
    d.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)

rrect((40, 40, W-40, H-40), 10, PANEL)
rrect((40, 40, W-40, 86), 10, TITLE)
d.rectangle((40, 76, W-40, 86), fill=TITLE)
d.text((60, 52), "so2mm", font=font_b, fill=TEXT)
d.text((W-110, 56), "— □ ×", font=font_m, fill=MUTED)

tabs = ["aim", "esp", "weapon", "move", "skins", "antiban", "config"]
active = 4
x = 60
y = 104
for i, t in enumerate(tabs):
    tw = 90
    col = (66, 20, 36, 255) if i == active else (30, 24, 30, 255)
    rrect((x, y, x+tw, y+34), 5, col)
    d.text((x + (tw - d.textlength(t, font=font_m))//2, y+8), t, font=font_m,
           fill=TEXT if i == active else MUTED)
    x += tw + 6

body_y = 160
rrect((60, body_y, 60+22, body_y+22), 4, PANEL2, outline=ACCENT, width=2)
d.text((64, body_y+3), "✓", font=font_m, fill=ACCENT)
d.text((94, body_y+2), "skin changer", font=font_m, fill=TEXT)
rrect((260, body_y-3, 400, body_y+27), 5, (58, 24, 36, 255))
d.text((285, body_y+3), "reload catalog", font=font_m, fill=TEXT)

left_x, left_w = 60, 230
right_x = 60 + 230 + 14
right_w = W - 60 - right_x
panel_y, panel_h = body_y + 44, 340
rrect((left_x, panel_y, left_x+left_w, panel_y+panel_h), 6, PANEL2)
rrect((right_x, panel_y, right_x+right_w, panel_y+panel_h), 6, PANEL2)

weapons = ["AK-47", "M4A1", "AWP", "Glock-18", "Desert Eagle", "Karambit", "Butterfly", "Bayonet"]
sel_w = 0
for i, w in enumerate(weapons):
    ry = panel_y + 10 + i*34
    if i == sel_w:
        rrect((left_x+6, ry-3, left_x+left_w-6, ry+24), 4, (66, 20, 36, 255))
    d.text((left_x+18, ry), w, font=font_m, fill=TEXT if i == sel_w else MUTED)

skins = [
    ("Default",     False),
    ("Neon Rider",  True),
    ("Asiimov",     False),
    ("Wild Lotus",  True),
]
sel_s = 2
for i, (sname, st) in enumerate(skins):
    ry = panel_y + 10 + i*34
    if i == sel_s:
        rrect((right_x+6, ry-3, right_x+right_w-6, ry+24), 4, (66, 20, 36, 255))
    d.text((right_x+18, ry), sname, font=font_m, fill=TEXT if i == sel_s else MUTED)
    if st:
        tag_w = 36
        rrect((right_x+right_w-tag_w-16, ry+1, right_x+right_w-16, ry+22), 4, (40, 70, 50, 255))
        d.text((right_x+right_w-tag_w-6, ry+2), "ST", font=font_s, fill=GREEN)

cy = panel_y + panel_h + 20
rrect((60, cy, 82, cy+22), 4, PANEL2, outline=ACCENT, width=2)
d.text((64, cy+3), "✓", font=font_m, fill=ACCENT)
d.text((92, cy+2), "StatTrak", font=font_m, fill=TEXT)

sy = cy + 40
d.text((60, sy-2), "wear (float)", font=font_m, fill=MUTED)
bar_x1, bar_x2 = 200, 760
d.rectangle((bar_x1, sy+7, bar_x2, sy+13), fill=(40, 44, 54, 255))
fill_px = int(bar_x1 + (bar_x2-bar_x1) * 0.07)
d.rectangle((bar_x1, sy+7, fill_px, sy+13), fill=ACCENT)
d.ellipse((fill_px-9, sy+1, fill_px+9, sy+19), fill=ACCENT2, outline=ACCENT, width=2)
d.text((bar_x2+20, sy-2), "0.070", font=font_m, fill=TEXT)

by = sy + 42
rrect((60, by, 230, by+34), 5, (72, 24, 42, 255))
d.text((90, by+8), "apply to loadout", font=font_m, fill=TEXT)
rrect((246, by, 386, by+34), 5, (42, 18, 28, 255))
d.text((278, by+8), "force refresh", font=font_m, fill=TEXT)
d.text((60, by+46), "local-only; server never sees the swap", font=font_s, fill=MUTED)

d.line((60, H-80, W-60, H-80), fill=(40, 44, 54, 255), width=1)
d.text((60, H-70), "snapshot ready: 1    enemies: 4    fps: 118",
       font=font_s, fill=MUTED)
d.text((W-260, H-70), "three-finger tap to toggle", font=font_s, fill=MUTED)

out = "/tmp/claude-0/-home-user-sezx/c19d3923-cc31-59a5-a153-26878d244cef/scratchpad/so2mm_menu.png"
img.convert("RGB").save(out, "PNG")
print(out)
