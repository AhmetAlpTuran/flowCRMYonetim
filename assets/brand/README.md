# Brand mark

The logo is the owner's lowercase "f" monogram (`source/app-icon-v5-f.png`), recolored to
the design tokens: lime `#C6F432` on ink `#0E1116`. `flow-mark.png` (512 px) is the in-app
mark drawn by `FlowLogo` on a rounded tile.

`python scripts/brand_icons.py` (Pillow + NumPy) regenerates every icon from the source:
the in-app mark, Flutter web icons and favicon, the website favicons, header mark and
Open Graph card, Android launcher icons, and the iOS app and launch icons.
