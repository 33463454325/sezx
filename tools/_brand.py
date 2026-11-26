"""Общий ватермарк Vektor для всех GUI-рендереров."""
from PIL import Image
import os

LOGO_PATH = "/home/user/sezx/assets/brand/vektor_logo.png"

def apply_watermark(img, scale=1, size_frac=0.85, alpha=26):
    """Наложить лого Vektor поверх фона, приглушив до alpha (0..255).
    Чёрные пиксели исходного PNG делаются прозрачными, цветные — alpha."""
    if not os.path.exists(LOGO_PATH):
        return
    W, H = img.size
    logo = Image.open(LOGO_PATH).convert("RGBA")
    target_h = int(H * size_frac)
    aspect = logo.width / logo.height
    target_w = int(target_h * aspect)
    logo = logo.resize((target_w, target_h), Image.LANCZOS)
    px = logo.load()
    for y in range(logo.height):
        for x in range(logo.width):
            r, g, b, a = px[x, y]
            if max(r, g, b) < 20:
                px[x, y] = (0, 0, 0, 0)
            else:
                px[x, y] = (r, g, b, alpha)
    img.alpha_composite(logo, ((W - target_w) // 2, (H - target_h) // 2))

def header_logo(img, x_px, y_px, side_px):
    if not os.path.exists(LOGO_PATH):
        return
    logo = Image.open(LOGO_PATH).convert("RGBA").resize(
        (side_px, side_px), Image.LANCZOS)
    img.alpha_composite(logo, (x_px, y_px))
