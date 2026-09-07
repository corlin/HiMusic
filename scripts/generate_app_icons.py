"""Generate native launcher resources. Requires Pillow (pip install Pillow)."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/branding/app-icon.png'
BG = '#FFF3CE'
art = Image.open(SOURCE).convert('RGBA')


def canvas(size, fraction=0.86, background=BG):
    result = Image.new('RGBA', (size, size), background)
    stamp = art.copy()
    stamp.thumbnail((round(size * fraction), round(size * fraction)), Image.Resampling.LANCZOS)
    result.alpha_composite(stamp, ((size - stamp.width) // 2, (size - stamp.height) // 2))
    return result


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)


for platform in ('ios', 'macos'):
    folder = ROOT / platform / 'Runner/Assets.xcassets/AppIcon.appiconset'
    entries = json.loads((folder / 'Contents.json').read_text())['images']
    for entry in entries:
        size = round(float(entry['size'].split('x')[0]) * float(entry['scale'][:-1]))
        save(canvas(size).convert('RGB'), folder / entry['filename'])

res = ROOT / 'android/app/src/main/res'
for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    save(canvas(size).convert('RGB'), res / f'mipmap-{density}/ic_launcher.png')
    # 108dp adaptive layer; keep artwork within the central 66dp safe area.
    save(canvas(round(size * 108 / 48), 0.60, (0, 0, 0, 0)),
         res / f'mipmap-{density}/ic_launcher_foreground.png')

adaptive = res / 'mipmap-anydpi-v26/ic_launcher.xml'
adaptive.parent.mkdir(parents=True, exist_ok=True)
adaptive.write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''')
(res / 'values/icon_colors.xml').write_text(f'<resources><color name="ic_launcher_background">{BG}</color></resources>\n')

# Explicitly include small native Windows frames as well as the 256px frame.
canvas(256).save(ROOT / 'windows/runner/resources/app_icon.ico',
                 sizes=[(n, n) for n in (16, 24, 32, 48, 64, 128, 256)])

# Android TV launcher banner, 320x180 at xhdpi, includes the app name.
banner = Image.new('RGB', (320, 180), BG)
stamp = canvas(158).convert('RGB')
banner.paste(stamp, (4, 11))
font = ImageFont.truetype(str(ROOT / '.tooling/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'), 31)
ImageDraw.Draw(banner).text((163, 70), 'HiMusic', font=font, fill='#28266A')
save(banner, res / 'drawable-xhdpi/tv_banner.png')
print('Generated iOS, macOS, Android/adaptive/TV, and Windows icons.')
