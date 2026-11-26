from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os, sys, random, math
sys.path.insert(0, os.path.dirname(__file__))
from _brand import LOGO_PATH

SCALE = 2
W_FINAL, H_FINAL = 1180, 520
W, H = W_FINAL * SCALE, H_FINAL * SCALE

LABEL  = (240, 232, 242)
MUTED  = (170, 140, 170)
TERT   = (120, 95, 130)
ACCENT = (235, 55, 110)
HI     = (255, 100, 150)
GREEN  = (90, 220, 130)

def font(paths, size):
    s = int(size * SCALE)
    for p in paths:
        try: return ImageFont.truetype(p, s)
        except Exception: pass
    return ImageFont.load_default()

SFB = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]
SF  = ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
f_hero = font(SFB, 24)
f_h2   = font(SFB, 16)
f_row  = font(SF,  14)
f_desc = font(SF,  11)
f_tiny = font(SF,  10)

def rrect(d, xy, r, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = xy
    d.rounded_rectangle((x0*SCALE, y0*SCALE, x1*SCALE, y1*SCALE),
                        radius=r*SCALE, fill=fill, outline=outline,
                        width=int(width*SCALE))

def text(d, xy, s, f, fill):
    d.text((xy[0]*SCALE, xy[1]*SCALE), s, font=f, fill=fill)

def textw(d, s, f): return d.textlength(s, font=f) / SCALE

def ellipse_(d, xy, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = xy
    d.ellipse((x0*SCALE, y0*SCALE, x1*SCALE, y1*SCALE), fill=fill,
              outline=outline, width=int(width*SCALE))

# Background: tiled fake game scene — gradient + decorative blobs so the
# screenshot looks like a real game frame with the overlay on top.
def fake_game_bg(img):
    d = ImageDraw.Draw(img)
    # dusk gradient
    for y in range(H):
        t = y / H
        r = int(28 * (1-t) + 70 * t)
        g = int(30 * (1-t) + 45 * t)
        b = int(44 * (1-t) + 60 * t)
        d.line([(0, y), (W, y)], fill=(r, g, b))
    # faint horizon
    d.rectangle((0, H*0.60, W, H*0.60 + 2), fill=(90, 70, 60))
    # decorative blocks like map geometry
    random.seed(7)
    for _ in range(14):
        x = random.randint(0, W-120*SCALE)
        y = random.randint(int(H*0.3), H-120*SCALE)
        w = random.randint(60*SCALE, 220*SCALE)
        h = random.randint(40*SCALE, 160*SCALE)
        shade = random.randint(16, 50)
        d.rectangle((x, y, x+w, y+h), fill=(shade, shade-6, shade-8))
    img_f = img.filter(ImageFilter.GaussianBlur(radius=4*SCALE))
    img.paste(img_f)

def fake_hud(img, d):
    # pretend-crosshair in center
    cx, cy = W_FINAL/2, H_FINAL/2
    for a, b in [(-10, 2), (-2, 10), (2, 10), (10, 2)]:
        pass
    # bottom left: HP / ammo
    rrect(d, (28, H_FINAL-70, 240, H_FINAL-24), 8, (0, 0, 0, 140))
    text(d, (42, H_FINAL-58), "HP 100", f_h2, LABEL)
    text(d, (140, H_FINAL-58), "30 / 90", f_h2, LABEL)
    # top center: round time
    rrect(d, (W_FINAL/2 - 60, 18, W_FINAL/2 + 60, 54), 10, (0, 0, 0, 140))
    text(d, (W_FINAL/2 - 20, 26), "1:24", f_hero, LABEL)

def collapsed_pill(img, d, cx, cy):
    """Floating V button with status pill, bottom-right by default."""
    # outer glow
    glow = Image.new("RGBA", img.size, (0,0,0,0))
    gd = ImageDraw.Draw(glow)
    for i in range(14, 0, -1):
        a = int(10 * i / 14)
        gd.ellipse(((cx - 48 - i)*SCALE, (cy - 48 - i)*SCALE,
                    (cx + 48 + i)*SCALE, (cy + 48 + i)*SCALE),
                   fill=(235, 55, 110, a))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=3*SCALE))
    img.alpha_composite(glow)
    # main disc
    ellipse_(d, (cx-48, cy-48, cx+48, cy+48), fill=(18, 8, 26, 240),
             outline=HI, width=2)
    # logo inside
    if os.path.exists(LOGO_PATH):
        logo = Image.open(LOGO_PATH).convert("RGBA").resize(
            (72*SCALE, 72*SCALE), Image.LANCZOS)
        img.alpha_composite(logo, ((cx-36)*SCALE, (cy-36)*SCALE))
    # status pill right of disc
    pill_x = cx + 60
    pill_y = cy - 22
    pill_w = 240
    pill_h = 44
    rrect(d, (pill_x, pill_y, pill_x+pill_w, pill_y+pill_h), 22,
          (18, 8, 26, 230), outline=(56, 22, 70), width=1)
    ellipse_(d, (pill_x+12, pill_y+15, pill_x+28, pill_y+31), fill=GREEN)
    text(d, (pill_x+38, pill_y+6), "VEKTOR · ON",   f_h2, LABEL)
    text(d, (pill_x+38, pill_y+24), "Humanize 52% · Guard OK",
         f_desc, MUTED)
    # drag handle under disc
    for i in range(4):
        ellipse_(d, (cx-3+i*2, cy+56, cx-1+i*2, cy+58), fill=TERT)

def tiny_toast(d, x, y):
    rrect(d, (x, y, x+320, y+54), 12, (18, 8, 26, 230),
          outline=HI, width=1)
    # colored dot
    ellipse_(d, (x+14, y+22, x+26, y+34), fill=HI)
    text(d, (x+36, y+10), "Vektor свёрнут", f_h2, LABEL)
    text(d, (x+36, y+30), "тап — развернуть · долгий тап — паник",
         f_desc, MUTED)

def kill_log(d, x, y):
    rows = [("user_4421",  "head",  "AKR",   "player_11"),
            ("player_02",  "chest", "USP",   "user_4421"),
            ("user_4421",  "head",  "AKR",   "player_17")]
    for i, (k, zone, w, v) in enumerate(rows):
        row_y = y + i * 30
        rrect(d, (x, row_y, x+340, row_y+24), 6, (0, 0, 0, 140))
        text(d, (x+8, row_y+5), k, f_desc, HI)
        text(d, (x+96, row_y+5), w, f_desc, MUTED)
        text(d, (x+156, row_y+5), f"→ {v}", f_desc, LABEL)
        text(d, (x+260, row_y+5), zone, f_desc, GREEN)

OUT = "/tmp/claude-0/-home-user-sezx/c19d3923-cc31-59a5-a153-26878d244cef/scratchpad"
os.makedirs(OUT, exist_ok=True)

img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
fake_game_bg(img)
d = ImageDraw.Draw(img, "RGBA")
fake_hud(img, d)
kill_log(d, W_FINAL - 370, 28)

# Minimised overlay: bottom-right floating pill
collapsed_pill(img, d, W_FINAL - 320, H_FINAL - 100)

# Small toast in top-left for "just minimised"
tiny_toast(d, 28, 80)

out = f"{OUT}/so2mm_collapsed.png"
img.resize((W_FINAL, H_FINAL), Image.LANCZOS).convert("RGB").save(out, "PNG")
print(out)
