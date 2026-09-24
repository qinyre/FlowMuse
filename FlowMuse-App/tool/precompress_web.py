"""Precompress a Flutter Web release for Nginx gzip_static; stdlib only."""
import argparse
import gzip
from pathlib import Path

COMPRESSIBLE = {'.js', '.mjs', '.wasm', '.json', '.css', '.html', '.svg', '.ttf', '.otf'}


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
    args = parser.parse_args()
    root = Path(args.directory).resolve()
    if not (root / 'index.html').is_file() or not (root / 'main.dart.js').is_file():
        parser.error('Build the Flutter Web release first')
    print(precompress(root))
