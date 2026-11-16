"""Serve the built console (build/web) to the office's browsers.

    python3 tool/serve_web.py PORT DIRECTORY

`python3 -m http.server` sends no Cache-Control, so a browser guesses how
long it may reuse a file without asking: a tenth of the file's age. A file
that went weeks unchanged -- the logo -- was then kept for days after a
rebuild replaced it, and the office saw the old one (10 Nov). Every file
here goes out with `Cache-Control: no-cache`: the browser keeps its copy
but asks first, and an unchanged file costs a 304 on the office network.
A rebuild therefore reaches every PC on its next load.
"""

import functools
import http.server
import sys


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


def main() -> None:
    port, directory = int(sys.argv[1]), sys.argv[2]
    handler = functools.partial(NoCacheHandler, directory=directory)
    # Threaded, as `http.server` is since 3.7: the app's many asset
    # requests are not served one behind another.
    http.server.ThreadingHTTPServer(("0.0.0.0", port), handler).serve_forever()


if __name__ == "__main__":
    main()
