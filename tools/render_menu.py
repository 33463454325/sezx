from PIL import Image, ImageDraw, ImageFont

W, H = 1180, 1000

BG       = (242, 242, 247, 255)
CARD     = (255, 255, 255, 255)
HAIR     = (198, 198, 200, 255)
LABEL    = (0, 0, 0, 255)
SECOND   = (90, 90, 95, 255)
TERTIARY = (170, 170, 175, 255)
BLUE     = (0, 122, 255, 255)
GREEN_ON = (52, 199, 89, 255)
GRAY_OFF = (229, 229, 234, 255)
RED      = (255, 59, 48, 255)

img = Image.new("RGBA", (W, H), BG)
d = ImageDraw.Draw(img)

def font(paths, size):
    for p in paths:
        try: return ImageFont.truetype(p, size)
        except Exception: pass
    return ImageFont.load_default()

SFB = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]
SF  = ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]

f_large = font(SFB, 34)
f_title = font(SFB, 22)
f_row   = font(SF,  18)
f_sub   = font(SF,  15)
f_small = font(SF,  13)
f_badge = font(SFB, 11)

def rrect(xy, r, fill, outline=None, width=1):
    d.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)

def switch(x, y, on):
    w, h = 50, 30
    track = GREEN_ON if on else GRAY_OFF
    rrect((x, y, x+w, y+h), h//2, track)
    knob_x = x + (w - h + 2) if on else x + 2
    d.ellipse((knob_x, y+2, knob_x+h-4, y+h-2), fill=(255,255,255,255))

def chevron(x, y):
    d.line((x, y-5, x+6, y, x, y+5), fill=TERTIARY, width=2)

d.rectangle((0, 0, W, 90), fill=BG)
d.text((36, 20), "‹ Settings", font=f_row, fill=BLUE)
d.text((36, 48), "Skins", font=f_large, fill=LABEL)

tabs = ["Aim", "ESP", "Weapon", "Move", "Skins", "Guard", "Config"]
active = 4
seg_x, seg_y, seg_w, seg_h = 36, 104, W - 72, 38
rrect((seg_x, seg_y, seg_x+seg_w, seg_y+seg_h), 9, (120,120,128, 50))
cell_w = seg_w / len(tabs)
for i, t in enumerate(tabs):
    cx = seg_x + i*cell_w
    if i == active:
        rrect((cx+2, seg_y+2, cx+cell_w-2, seg_y+seg_h-2), 8, CARD)
    tw = d.textlength(t, font=f_row)
    d.text((cx + (cell_w - tw)/2, seg_y + 8), t, font=f_row,
           fill=LABEL if i == active else SECOND)

sec_y = seg_y + seg_h + 24
d.text((48, sec_y - 22), "SKIN CHANGER", font=f_small, fill=SECOND)
rrect((36, sec_y, W-36, sec_y+56), 12, CARD)
d.text((56, sec_y+18), "Enable", font=f_row, fill=LABEL)
switch(W - 36 - 18 - 50, sec_y + 13, on=True)

sec2_y = sec_y + 56 + 28
d.text((48, sec2_y - 22), "WEAPONS", font=f_small, fill=SECOND)
left_w = 320
card_h = 480
rrect((36, sec2_y, 36+left_w, sec2_y+card_h), 12, CARD)
right_x = 36 + left_w + 14
right_w = W - 36 - right_x
rrect((right_x, sec2_y, right_x+right_w, sec2_y+card_h), 12, CARD)

weapons = ["AKR", "M4", "AWM", "Desert Eagle", "USP", "Glock-18",
           "Karambit", "M9 Bayonet", "Butterfly"]
counts = [14, 2, 2, 2, 1, 1, 2, 2, 2]
sel_w = 0
row_h = 46
for i, (w, c) in enumerate(zip(weapons, counts)):
    ry = sec2_y + 8 + i*row_h
    if i == sel_w:
        rrect((36+6, ry-2, 36+left_w-6, ry+row_h-6), 8, (0, 122, 255, 30))
    d.text((56, ry+12), w, font=f_row, fill=LABEL)
    tw = d.textlength(str(c), font=f_sub)
    d.text((36+left_w - 44 - tw, ry+14), str(c), font=f_sub, fill=SECOND)
    chevron(36+left_w - 26, ry + row_h/2 - 2)
    if i < len(weapons)-1:
        d.line((56, ry+row_h-4, 36+left_w-14, ry+row_h-4), fill=HAIR, width=1)

skins = [
    ("Default",          True,  False),
    ("Steel Grip",       True,  False),
    ("Tiger",            True,  True),
    ("Sport",            True,  False),
    ("2Years Red",       True,  True),
    ("Treasure Hunter",  True,  True),
    ("Galaxy",           False, False),
    ("Neon Tiger",       False, False),
    ("Dragon",           False, True),
    ("Evolution",        False, False),
]
sel_s = 4
d.text((right_x+20, sec2_y+14), "AKR", font=f_title, fill=LABEL)
d.text((right_x+right_w-110, sec2_y+20), "14 skins", font=f_sub, fill=SECOND)
d.line((right_x+20, sec2_y+54, right_x+right_w-20, sec2_y+54), fill=HAIR, width=1)

base_y = sec2_y + 66
rh = 40
for i, (name, verified, st) in enumerate(skins):
    ry = base_y + i*rh
    if i == sel_s:
        rrect((right_x+6, ry-2, right_x+right_w-6, ry+rh-6), 8, (0, 122, 255, 30))
        d.ellipse((right_x+right_w-32, ry+rh/2-8, right_x+right_w-16, ry+rh/2+8), fill=BLUE)
        d.line((right_x+right_w-28, ry+rh/2+1, right_x+right_w-23, ry+rh/2+5,
                right_x+right_w-19, ry+rh/2-3), fill=(255,255,255,255), width=2)
    d.text((right_x+20, ry+10), name, font=f_row, fill=LABEL)
    tag_x = right_x + 20 + d.textlength(name, font=f_row) + 10
    if verified:
        rrect((tag_x, ry+12, tag_x+18, ry+28), 4, (52,199,89, 50))
        d.text((tag_x+5, ry+13), "✓", font=f_badge, fill=GREEN_ON)
    else:
        rrect((tag_x, ry+12, tag_x+18, ry+28), 4, (255,204,0, 50))
        d.text((tag_x+7, ry+13), "?", font=f_badge, fill=(180,120,0,255))
    tag_x += 24
    if st:
        rrect((tag_x, ry+12, tag_x+30, ry+28), 4, (255,59,48, 50))
        d.text((tag_x+6, ry+14), "ST", font=f_badge, fill=RED)
    if i < len(skins)-1:
        d.line((right_x+20, ry+rh-4, right_x+right_w-20, ry+rh-4), fill=HAIR, width=1)

sec3_y = sec2_y + card_h + 28
rrect((36, sec3_y, W-36, sec3_y+150), 12, CARD)
d.text((56, sec3_y+18), "StatTrak", font=f_row, fill=LABEL)
switch(W - 36 - 18 - 50, sec3_y + 13, on=True)
d.line((56, sec3_y+56, W-56, sec3_y+56), fill=HAIR, width=1)

d.text((56, sec3_y+70), "Wear", font=f_row, fill=LABEL)
d.text((W-220, sec3_y+70), "0.070  ·  Factory New", font=f_sub, fill=SECOND)
bar_x1, bar_x2 = 56, W - 56
by = sec3_y + 115
d.rounded_rectangle((bar_x1, by-3, bar_x2, by+3), 3, fill=(120,120,128, 60))
fill_px = int(bar_x1 + (bar_x2-bar_x1) * 0.07)
d.rounded_rectangle((bar_x1, by-3, fill_px, by+3), 3, fill=BLUE)
d.ellipse((fill_px-12, by-12, fill_px+12, by+12), fill=CARD, outline=(0,0,0,30), width=1)

apply_y = sec3_y + 150 + 20
rrect((36, apply_y, W-36, apply_y+52), 12, BLUE)
label = "Apply to Loadout"
tw = d.textlength(label, font=f_title)
d.text(((W - tw)/2, apply_y+13), label, font=f_title, fill=(255,255,255,255))

d.text((W//2 - 230, apply_y + 68),
       "Local only  ·  server never sees the swap  ·  AKR • 2Years Red (ST)",
       font=f_small, fill=SECOND)

out = "/tmp/claude-0/-home-user-sezx/c19d3923-cc31-59a5-a153-26878d244cef/scratchpad/so2mm_menu.png"
img.convert("RGB").save(out, "PNG")
print(out)
