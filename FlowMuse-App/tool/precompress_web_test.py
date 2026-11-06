import gzip
import json
from pathlib import Path
import tempfile
import unittest

from precompress_web import ROBOTO_ASSET, UI_FONTS, optimize_startup_fonts, precompress


class PrecompressTest(unittest.TestCase):
    def test_web_manifest_defers_heavy_faces_and_uses_local_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            assets = root / 'assets'
            assets.mkdir()
            manifest = assets / 'FontManifest.json'
            faces = [{'weight': weight, 'asset': asset}
                     for weight, asset in UI_FONTS.items()]
            other = {'family': 'MaterialIcons', 'fonts': [{'asset': 'icons.ttf'}]}
            manifest.write_text(json.dumps([
                {'family': 'FlowMuseSans', 'fonts': faces}, other,
            ]), encoding='utf-8')
            for face in faces:
                path = assets / face['asset']
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'font-fixture')
            fallback = assets / ROBOTO_ASSET
            fallback.parent.mkdir()
            fallback.write_bytes(b'font-fixture')
            optimize_startup_fonts(root)
            first = manifest.read_bytes()
            self.assertEqual(json.loads(first), [
                {'family': 'FlowMuseSans', 'fonts': faces[:1]}, other,
                {'family': 'Roboto', 'fonts': [{'asset': ROBOTO_ASSET}]},
            ])
            self.assertTrue(all((assets / face['asset']).is_file() for face in faces))
            optimize_startup_fonts(root)
            self.assertEqual(manifest.read_bytes(), first)

    def test_lossless_repeatable_and_no_stale_gzip(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            font = root / 'icons.ttf'
            font.write_bytes(bytes(range(256)) * 30)
            image = root / 'cover.png'
            image.write_bytes(b'png-fixture' * 1024)
            self.assertEqual(precompress(root)['files'], 1)
            encoded = (root / 'icons.ttf.gz').read_bytes()
            self.assertEqual(gzip.decompress(encoded), font.read_bytes())
            precompress(root)
            self.assertEqual((root / 'icons.ttf.gz').read_bytes(), encoded)
            self.assertFalse((root / 'cover.png.gz').exists())
            font.write_bytes(b'smaller replacement')
            precompress(root)
            self.assertFalse((root / 'icons.ttf.gz').exists())


if __name__ == '__main__':
    unittest.main()
