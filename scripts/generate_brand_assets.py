import argparse
import io
import json
from pathlib import Path

import resvg_py
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description='从统一图形生成红果鉴 / 真果鉴平台资源；需要 Pillow 和 resvg-py。')
parser.add_argument('--output', type=Path, default=root)
parser.add_argument('--font', type=Path, default=Path('/System/Library/Fonts/PingFang.ttc'))
options = parser.parse_args()
output = options.output
source = (root / 'scripts/brand_icon.svg').read_text(encoding='utf-8')

def render(svg):
    png = resvg_py.svg_to_bytes(svg_string=svg, width=1024, height=1024)
    return Image.open(io.BytesIO(bytes(png))).convert('RGBA')

foreground = render(source)
silhouette = render(source.replace(' filter="url(#shadow)"', ''))
icon = Image.new('RGBA', (1024, 1024), '#CDE5F9')
icon.alpha_composite(foreground)
rounded = icon.copy()
corners = Image.new('L', (1024, 1024), 0)
ImageDraw.Draw(corners).rounded_rectangle((0, 0, 1023, 1023), radius=236, fill=255)
rounded.putalpha(corners)
icon = icon.convert('RGB')
adaptive = Image.new('RGBA', (1536, 1536))
adaptive.paste(foreground, (256, 256))
monochrome = Image.new('RGBA', (1536, 1536))
monochrome.paste(silhouette, (256, 256))

def save(image, name):
    destination = output / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination)

contents = json.loads((root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json').read_text())
for entry in contents['images']:
    if 'filename' in entry:
        size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
        save(icon.resize((size, size), Image.Resampling.LANCZOS),
             'ios/Runner/Assets.xcassets/AppIcon.appiconset/' + entry['filename'])
save(rounded.resize((256, 256), Image.Resampling.LANCZOS), 'windows/runner/resources/app_icon.ico')
macos_canvas = Image.new('RGBA', (1024, 1024))
macos_badge = rounded.resize((824, 824), Image.Resampling.LANCZOS)
macos_canvas.paste(macos_badge, (100, 100), macos_badge)
macos_contents = json.loads((root / 'macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json').read_text())
for entry in macos_contents['images']:
    if 'filename' in entry:
        size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
        save(macos_canvas.resize((size, size), Image.Resampling.LANCZOS),
             'macos/Runner/Assets.xcassets/AppIcon.appiconset/' + entry['filename'])
for density, scale in [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3), ('xxxhdpi', 4)]:
    legacy = round(48 * scale)
    layer = round(108 * scale)
    save(rounded.resize((legacy, legacy), Image.Resampling.LANCZOS),
         f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')
    save(adaptive.resize((layer, layer), Image.Resampling.LANCZOS),
         f'android/app/src/main/res/mipmap-{density}/ic_launcher_foreground.png')
    save(monochrome.resize((layer, layer), Image.Resampling.LANCZOS),
         f'android/app/src/main/res/mipmap-{density}/ic_launcher_monochrome.png')
font_path = options.font
if not font_path.exists():
    for candidate in ('/System/Library/Fonts/Hiragino Sans GB.ttc',
                      '/System/Library/Fonts/STHeiti Medium.ttc'):
        if Path(candidate).exists():
            font_path = Path(candidate)
            break
font = ImageFont.truetype(str(font_path), 76)
for name, resource in [('红果鉴', 'tv_banner'), ('真果鉴', 'tv_banner_all_sources')]:
    banner = Image.new('RGB', (640, 360), '#F5F9FC')
    badge = rounded.resize((180, 180), Image.Resampling.LANCZOS)
    banner.paste(badge, (44, 90), badge)
    draw = ImageDraw.Draw(banner)
    draw.text((255, 128), name, font=font, fill='#3B4552')
    save(banner, f'android/app/src/main/res/drawable-xhdpi/{resource}.png')
