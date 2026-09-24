import gzip
from pathlib import Path
import tempfile
import unittest

from precompress_web import precompress


class PrecompressTest(unittest.TestCase):
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
