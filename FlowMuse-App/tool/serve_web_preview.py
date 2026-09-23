"""Loopback-only Flutter preview with history-route fallback. No dependencies."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


class Preview(SimpleHTTPRequestHandler):
    def do_GET(self):
        path = Path(self.translate_path(urlsplit(self.path).path))
        if not path.is_file() and not path.suffix:
            self.path = '/index.html'
        super().do_GET()

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', default='build/web')
    parser.add_argument('--port', type=int, default=18344)
    args = parser.parse_args()
    root = Path(args.directory).resolve()
    if not (root / 'index.html').is_file():
        parser.error('Build the Flutter Web app first')
    ThreadingHTTPServer(('127.0.0.1', args.port), partial(Preview, directory=str(root))).serve_forever()
