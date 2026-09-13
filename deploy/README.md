# Hosting the web build

The exported folder is self-contained: upload it as-is. It cannot be opened from
`file://` -- WebAssembly has to be served over HTTP(S).

## Namecheap shared hosting (cPanel + LiteSpeed)

The export preset in `export_presets.cfg` is set to **thread support off**, so no
special headers are needed and the build works on plain shared hosting.

1. cPanel -> **File Manager** -> `public_html`
2. Make a folder, e.g. `golf`
3. Zip the contents of `build/web/`, upload the single zip, then **Extract**.
   Uploading one archive is far more reliable than pushing the multi-megabyte
   engine binary through the browser uploader.
4. Copy `deploy/.htaccess` into that same folder
5. Make sure AutoSSL is on, then visit `https://yourdomain.com/golf/`

`index.html` must sit directly in that folder, not in a nested one.

## A Godot 4.7 detail worth knowing

The threads-off web build uses its own export templates, `web_nothreads_debug.zip`
and `web_nothreads_release.zip`, separate from the threaded `web_*.zip` pair.
Exporting with thread support off will fail with "No export template found" until
the full template set has finished downloading. The tools folder is excluded from
the export, so the test harnesses do not ship to players.

## Why threads off

The alternative is faster, but it requires the page to be *cross-origin
isolated*, and that mode also refuses to load any third-party resource on the
same page -- Google Fonts, analytics, embedded video all break. For a 2D card
game on your own site that is a bad trade. `threads-on.htaccess` is here if you
ever want to revisit it.

Other hosts: `_headers` for Netlify or Cloudflare Pages, `nginx.conf.snippet`
for nginx. Both are threads-on configurations.

## Checking it worked

Open the page and look at the browser console:

- `SharedArrayBuffer is not defined` -- the build has threads on but the server
  is not sending the isolation headers. Either use `threads-on.htaccess` or
  re-export with thread support off.
- `Incorrect response MIME type` -- the server is not sending
  `application/wasm`. The `.htaccess` here fixes that.
- A long blank screen on first load is normal: the engine binary is tens of
  megabytes. Compression in the `.htaccess` cuts it to roughly a quarter, and
  the cache rules mean repeat visitors skip it.

## Building

From the project root:

```bash
godot --headless --path . --export-release "Web" build/web/index.html
```

Then copy `deploy/.htaccess` into `build/web/` before uploading.

## Known limits of this build

- Keyboard and mouse only. There is no touch input, so it is not playable on
  phones or tablets, which is most traffic that arrives from a link.
- Right-click deselects a card; check your browser does not open its own context
  menu over the canvas.
- No audio yet.
- It is a mid-development prototype: placeholder graphics, and six of the eleven
  map stops open a "not built yet" screen.
