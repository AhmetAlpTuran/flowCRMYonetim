"""Builds every icon from the owner's f logo, recolored to the design tokens."""
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[1]
INK = np.array([0x0E, 0x11, 0x16], float)
LIME = np.array([0xC6, 0xF4, 0x32], float)

src = np.asarray(Image.open(REPO / 'assets/brand/source/app-icon-v5-f.png').convert('RGB')).astype(float)
lum = 0.2126 * src[..., 0] + 0.7152 * src[..., 1] + 0.0722 * src[..., 2]
mask = np.clip((lum - 22) / (238 - 22), 0, 1)  # vignetted ink → 0, lime → 1
mask_img = Image.fromarray((mask * 255).astype(np.uint8), 'L')

def icon(size, scale=1.0):
    """Ink square with the lime f; scale < 1 shrinks the glyph (maskable safe zone)."""
    m = mask_img
    if scale != 1.0:
        n = m.size[0]
        inner = m.resize((round(n * scale),) * 2, Image.LANCZOS)
        canvas = Image.new('L', m.size, 0)
        off = (n - inner.size[0]) // 2
        canvas.paste(inner, (off, off))
        m = canvas
    a = np.asarray(m.resize((size, size), Image.LANCZOS)).astype(float)[..., None] / 255
    rgb = INK * (1 - a) + LIME * a
    return Image.fromarray(rgb.round().astype(np.uint8), 'RGB')

def save(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print(path.relative_to(REPO), img.size)

# In-app logo and the website header mark.
save(icon(512), REPO / 'assets/brand/flow-mark.png')
save(icon(96), REPO / 'docs/assets/flow-mark.png')
# Flutter web.
save(icon(32), REPO / 'web/favicon.png')
save(icon(192), REPO / 'web/icons/Icon-192.png')
save(icon(512), REPO / 'web/icons/Icon-512.png')
save(icon(192, 0.84), REPO / 'web/icons/Icon-maskable-192.png')
save(icon(512, 0.84), REPO / 'web/icons/Icon-maskable-512.png')
# Website favicons.
save(icon(32), REPO / 'docs/assets/favicon-32.png')
save(icon(180), REPO / 'docs/assets/apple-touch-icon.png')
# Android launcher icons.
for folder, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    save(icon(px), REPO / f'android/app/src/main/res/mipmap-{folder}/ic_launcher.png')
# iOS app icons (no alpha).
appicon = REPO / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((appicon / 'Contents.json').read_text())['images']:
    points = float(item['size'].split('x')[0])
    px = round(points * int(item['scale'][0]))
    save(icon(px), appicon / item['filename'])
# iOS launch image (shown centered on the ink launch screen).
launch = REPO / 'ios/Runner/Assets.xcassets/LaunchImage.imageset'
for item in json.loads((launch / 'Contents.json').read_text())['images']:
    if item.get('filename'):
        save(icon(96 * int(item['scale'][0])), launch / item['filename'])

# Open Graph card: ink, dot grid, the mark, wordmark and headline.
W, H = 1200, 630
og = Image.new('RGB', (W, H), tuple(INK.astype(int)))
draw = ImageDraw.Draw(og)
for y in range(8, H, 16):
    for x in range(8, W, 16):
        draw.ellipse((x - 1, y - 1, x + 1, y + 1), fill=(0x26, 0x2E, 0x3A))
mark = icon(132)
rounded = Image.new('L', mark.size, 0)
ImageDraw.Draw(rounded).rounded_rectangle((0, 0, *mark.size), radius=30, fill=255)
og.paste(mark, (80, 92), rounded)
fonts = REPO / 'assets/fonts'
display = ImageFont.truetype(str(fonts / 'BricolageDisplay-ExtraBold.ttf'), 76)
word = ImageFont.truetype(str(fonts / 'BricolageDisplay-ExtraBold.ttf'), 64)
mono = ImageFont.truetype(str(fonts / 'JetBrainsMono-Medium.ttf'), 24)
draw.text((236, 116), 'flow', font=word, fill=(0xF4, 0xF6, 0xF8))
draw.text((80, 300), "Tüm WhatsApp'ınız", font=display, fill=(0xF4, 0xF6, 0xF8))
draw.text((80, 390), 'tek bir komuta merkezinde.', font=display, fill=tuple(LIME.astype(int)))
draw.text((80, 520), 'WHATSAPP + YAPAY ZEKÂ · 14 GÜN ÜCRETSİZ', font=mono, fill=(0x9A, 0xA4, 0xB2))
save(og, REPO / 'docs/assets/og-image.png')
