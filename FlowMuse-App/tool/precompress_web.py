"""Precompress a Flutter Web release for Nginx gzip_static; stdlib only."""
import argparse
import gzip
import json
from pathlib import Path

COMPRESSIBLE = {'.js', '.mjs', '.wasm', '.json', '.css', '.html', '.svg', '.ttf', '.otf'}
UI_FONTS = {
    weight: f'assets/fonts/ui/FlowMuseSans-{name}.ttf'
    for weight, name in [(400, 'Regular'), (600, 'SemiBold'), (700, 'Bold')]
}
ROBOTO_ASSET = 'fonts/Roboto-Regular.ttf'


def optimize_startup_fonts(root):
    assets = root / 'assets'
    manifest = assets / 'FontManifest.json'
    families = json.loads(manifest.read_text(encoding='utf-8'))
    ui = next((family for family in families if family['family'] == 'FlowMuseSans'), None)
    if ui is None:
        raise ValueError('FlowMuseSans missing from Web font manifest')
    if not all((assets / asset).is_file() for asset in UI_FONTS.values()):
        raise ValueError('A FlowMuseSans font file is missing from the Web build')
    fonts = ui['fonts']
    entries = {font.get('weight'): font.get('asset') for font in fonts}
    if len(fonts) != 1 or entries != {400: UI_FONTS[400]}:
        if len(fonts) != len(UI_FONTS) or entries != UI_FONTS:
            raise ValueError('Unexpected FlowMuseSans entries in the Web font manifest')
        ui['fonts'] = [font for font in fonts if font['weight'] == 400]
    if not any(family['family'] == 'Roboto' for family in families):
        if not (assets / ROBOTO_ASSET).is_file():
            raise ValueError('Local Roboto fallback is missing from the Web build')
        families.append({'family': 'Roboto', 'fonts': [{'asset': ROBOTO_ASSET}]})
    manifest.write_text(json.dumps(families, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')


def precompress(root):
    raw_bytes = compressed_bytes = count = 0
    for path in sorted(root.rglob('*')):
        if not path.is_file() or path.is_symlink() or path.suffix not in COMPRESSIBLE:
            continue
        raw = path.read_bytes()
        target = path.with_name(path.name + '.gz')
        compressed = gzip.compress(raw, compresslevel=9, mtime=0)
        if len(raw) < 1024 or len(compressed) >= len(raw):
            target.unlink(missing_ok=True)
            continue
        target.write_bytes(compressed)
        raw_bytes += len(raw)
        compressed_bytes += len(compressed)
        count += 1
    return {'files': count, 'rawBytes': raw_bytes, 'gzipBytes': compressed_bytes}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', nargs='?', default='build/web')
    parser.add_argument('--optimize-startup-fonts', action='store_true',
                        help='Defer heavy UI faces and use a local Web fallback font')
    args = parser.parse_args()
    root = Path(args.directory).resolve()
    if not (root / 'index.html').is_file() or not (root / 'main.dart.js').is_file():
        parser.error('Build the Flutter Web release first')
    if args.optimize_startup_fonts:
        optimize_startup_fonts(root)
    print(precompress(root))
