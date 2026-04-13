# MacSift landing page

Static, dependency-free landing page for MacSift. Three files:

- `index.html` — content and structure
- `styles.css` — all styling
- `script.js` — copy buttons + smooth scroll + (optional) live GitHub star count

## Preview locally

```bash
python3 -m http.server 8765 --directory docs
open http://localhost:8765/
```

## Deploy via GitHub Pages

1. Open the repo on GitHub → **Settings → Pages**.
2. Under **Source**, pick **Deploy from a branch**.
3. Select branch `main` and folder `/docs`. Save.
4. Wait ~1 minute. The page will be live at
   `https://lcharvol.github.io/MacSift/`.

## Adding a real screenshot

Drop a PNG at `docs/images/screenshot-main.png`. It will be picked up
automatically by the hero frame. If the file is missing, the page falls back
to an inline SVG/CSS mockup so the layout never breaks.

Recommended size: 1920×1200, showing the main window with results loaded.

## Updating the description / topics

Content to edit lives in `index.html` directly — no build step, no framework.
Tailwind / Next / Astro were intentionally not used.
