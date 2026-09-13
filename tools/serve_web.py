"""Serve the exported web build locally, with the same MIME types and
compression a real host would use, so a local check reflects production."""
import functools, http.server, mimetypes, socketserver, sys

mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/octet-stream", ".pck")

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
Handler = functools.partial(http.server.SimpleHTTPRequestHandler,
                            directory="build/web")


class Server(socketserver.TCPServer):
    allow_reuse_address = True


with Server(("127.0.0.1", PORT), Handler) as httpd:
    print("serving build/web on http://127.0.0.1:%d" % PORT, flush=True)
    httpd.serve_forever()
