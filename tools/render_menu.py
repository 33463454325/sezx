from PIL import Image, ImageDraw, ImageFont

W, H = 1240, 920

BG       = (14, 5, 7, 255)
PANEL    = (26, 9, 13, 255)
PANEL2   = (36, 12, 18, 255)
HAIR     = (70, 20, 30, 255)
LABEL    = (238, 230, 232, 255)
SECOND   = (170, 130, 140, 255)
TERTIARY = (110, 80, 90, 255)
RED      = (235, 55, 72, 255)
RED_HI   = (255, 95, 110, 255)
RED_DIM  = (120, 20, 30, 255)
GREEN    = (90, 220, 130, 255)
YELLOW   = (235, 200, 70, 255)

img = Image.new("RGBA", (W, H), BG)
d = ImageDraw.Draw(img)

def font(paths, size):
    for p in paths:
        try: return ImageFont.truetype(p, size)
        except Exception: pass
    return ImageFont.load_default()

SFB = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]
SF  = ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
f_hero  = font(SFB, 30)
f_title = font(SFB, 20)
f_row   = font(SF,  17)
f_sub   = font(SF,  14)
f_small = font(SF,  12)
f_badge = font(SFB, 11)

def rrect(xy, r, fill, outline=None, width=1):
    d.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)

def switch(x, y, on):
    w, h = 44, 26
    track = RED if on else (60, 30, 36, 255)
    rrect((x, y, x+w, y+h), h//2, track)
    knob_x = x + (w - h + 2) if on else x + 2
    d.ellipse((knob_x, y+2, knob_x+h-4, y+h-2), fill=(245, 230, 232, 255))

# header
rrect((0, 0, W, 72), 0, (20, 7, 10, 255))
d.text((28, 22), "so2mm", font=f_hero, fill=RED_HI)
d.text((140, 32), "dark red  ·  v2.4  ·  arm64-v8a", font=f_sub, fill=SECOND)
# license chip
chip_x = W - 230
rrect((chip_x, 22, W-28, 50), 14, (34, 12, 16, 255), outline=RED_DIM, width=1)
d.ellipse((chip_x+10, 30, chip_x+22, 42), fill=GREEN)
d.text((chip_x+30, 28), "License  OK  ·  63 days", font=f_sub, fill=LABEL)

# sidebar tabs
SB_X, SB_Y, SB_W = 20, 92, 180
rrect((SB_X, SB_Y, SB_X+SB_W, H-20), 14, PANEL)
tabs = [
    ("Aim",      True,  False),
    ("ESP",      False, False),
    ("Weapon",   False, False),
    ("Move",     False, False),
    ("View",     False, False),
    ("HUD",      False, False),
    ("Utility",  False, False),
    ("Skins",    False, False),
    ("Guard",    False, False),
    ("Profiles", False, False),
    ("License",  False, False),
]
for i, (name, active, _) in enumerate(tabs):
    ry = SB_Y + 16 + i*54
    if active:
        rrect((SB_X+8, ry-2, SB_X+SB_W-8, ry+40), 10, (60, 15, 22, 255))
        d.rectangle((SB_X+8, ry-2, SB_X+12, ry+40), fill=RED)
    d.text((SB_X+28, ry+10), name, font=f_row,
           fill=RED_HI if active else LABEL if not active else SECOND)

# main body
MB_X = SB_X + SB_W + 16
MB_W = W - MB_X - 20
MB_Y = 92

# title row
d.text((MB_X+4, MB_Y+2), "Aim", font=f_hero, fill=LABEL)
d.text((MB_X+4, MB_Y+40), "target · trigger · knife", font=f_sub, fill=SECOND)

# profile pill
pp_w = 260
pp_x = MB_X + MB_W - pp_w
rrect((pp_x, MB_Y+14, pp_x+pp_w, MB_Y+46), 10, PANEL2, outline=RED_DIM, width=1)
d.text((pp_x+14, MB_Y+20), "Profile:", font=f_sub, fill=SECOND)
d.text((pp_x+78, MB_Y+20), "comp_ak  ▾", font=f_row, fill=LABEL)

# TARGET card
card_y = MB_Y + 74
card_h = 260
rrect((MB_X, card_y, MB_X+MB_W, card_y+card_h), 14, PANEL)
d.text((MB_X+20, card_y+14), "TARGET", font=f_badge, fill=SECOND)
rows = [
    ("Aimbot",       True),
    ("Silent aim",   True),
    ("Visible only", True),
    ("Multi-point",  True),
    ("Prediction",   True),
    ("Draw FOV",     True),
]
for i, (name, on) in enumerate(rows):
    ry = card_y + 40 + i*32
    d.text((MB_X+28, ry+4), name, font=f_row, fill=LABEL)
    switch(MB_X + MB_W - 68, ry, on)

# sliders column
sy = card_y + 40
d.text((MB_X + MB_W/2, sy+4), "FOV (px)", font=f_row, fill=LABEL)
bar_x1, bar_x2 = MB_X + MB_W/2, MB_X + MB_W - 100
rrect((bar_x1, sy+36, bar_x2, sy+42), 3, (60, 30, 36, 255))
fx = bar_x1 + (bar_x2-bar_x1) * 0.42
rrect((bar_x1, sy+36, fx, sy+42), 3, RED)
d.ellipse((fx-10, sy+30, fx+10, sy+48), fill=(245, 230, 232, 255))
d.text((bar_x2 + 10, sy+32), "248", font=f_row, fill=LABEL)

sy2 = sy + 70
d.text((MB_X + MB_W/2, sy2+4), "Smooth", font=f_row, fill=LABEL)
rrect((bar_x1, sy2+36, bar_x2, sy2+42), 3, (60, 30, 36, 255))
fx2 = bar_x1 + (bar_x2-bar_x1) * 0.25
rrect((bar_x1, sy2+36, fx2, sy2+42), 3, RED)
d.ellipse((fx2-10, sy2+30, fx2+10, sy2+48), fill=(245, 230, 232, 255))
d.text((bar_x2 + 10, sy2+32), "0.25", font=f_row, fill=LABEL)

# Bone pills
sy3 = sy2 + 70
d.text((MB_X + MB_W/2, sy3+4), "Bone", font=f_row, fill=LABEL)
bones = ["head", "chest", "pelvis"]
bx = MB_X + MB_W/2
for i, b in enumerate(bones):
    fill = RED if i == 0 else PANEL2
    rrect((bx, sy3+36, bx+90, sy3+68), 10, fill, outline=RED_DIM, width=1)
    tw = d.textlength(b, font=f_row)
    d.text((bx + (90-tw)/2, sy3+42), b, font=f_row, fill=LABEL if i == 0 else SECOND)
    bx += 98

# TRIGGER card
t_y = card_y + card_h + 18
t_h = 150
rrect((MB_X, t_y, MB_X+MB_W, t_y+t_h), 14, PANEL)
d.text((MB_X+20, t_y+14), "TRIGGER", font=f_badge, fill=SECOND)
trows = [("Trigger bot", True), ("Only when scoped", False)]
for i, (name, on) in enumerate(trows):
    ry = t_y + 40 + i*34
    d.text((MB_X+28, ry+4), name, font=f_row, fill=LABEL)
    switch(MB_X + MB_W/2 - 60, ry, on)
# delay slider
sy = t_y + 40
d.text((MB_X + MB_W/2 + 10, sy+4), "Delay (ms)", font=f_row, fill=LABEL)
bar_x1, bar_x2 = MB_X + MB_W/2 + 10, MB_X + MB_W - 100
rrect((bar_x1, sy+36, bar_x2, sy+42), 3, (60, 30, 36, 255))
fx = bar_x1 + (bar_x2-bar_x1) * 0.12
rrect((bar_x1, sy+36, fx, sy+42), 3, RED)
d.ellipse((fx-10, sy+30, fx+10, sy+48), fill=(245, 230, 232, 255))
d.text((bar_x2+10, sy+32), "24", font=f_row, fill=LABEL)

# KNIFE card
k_y = t_y + t_h + 18
k_h = 150
rrect((MB_X, k_y, MB_X+MB_W, k_y+k_h), 14, PANEL)
d.text((MB_X+20, k_y+14), "KNIFE", font=f_badge, fill=SECOND)
krows = [("Knife aura", True), ("Rapid knife", False)]
for i, (name, on) in enumerate(krows):
    ry = k_y + 40 + i*34
    d.text((MB_X+28, ry+4), name, font=f_row, fill=LABEL)
    switch(MB_X + MB_W/2 - 60, ry, on)
sy = k_y + 40
d.text((MB_X + MB_W/2 + 10, sy+4), "Range (m)", font=f_row, fill=LABEL)
bar_x1, bar_x2 = MB_X + MB_W/2 + 10, MB_X + MB_W - 100
rrect((bar_x1, sy+36, bar_x2, sy+42), 3, (60, 30, 36, 255))
fx = bar_x1 + (bar_x2-bar_x1) * 0.55
rrect((bar_x1, sy+36, fx, sy+42), 3, RED)
d.ellipse((fx-10, sy+30, fx+10, sy+48), fill=(245, 230, 232, 255))
d.text((bar_x2+10, sy+32), "2.8", font=f_row, fill=LABEL)

# footer
d.text((MB_X+4, H-40), "HWID 1a2c…85fb · Fairplay neutered · 12 hooks shadowed · 3 scanner threads frozen",
       font=f_small, fill=SECOND)
d.text((W-180, H-40), "three-finger tap", font=f_small, fill=TERTIARY)

out = "/tmp/claude-0/-home-user-sezx/c19d3923-cc31-59a5-a153-26878d244cef/scratchpad/so2mm_menu.png"
img.convert("RGB").save(out, "PNG")
print(out)
