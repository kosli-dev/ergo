# ergo site

The landing page and docs for ergo, built with [Hugo](https://gohugo.io/) (0.157, extended).

The docs pages aren't copied here. They're read from the repo's own `README.md` and `REFERENCE.md` when the site builds, so change the docs there and the site follows.

## Run it locally

```sh
hugo server -s site
```

Then open http://localhost:1313.

## Files

| What | Where |
| --- | --- |
| Landing page | `layouts/home.html` |
| Docs page shell | `layouts/page.html` |
| How the docs are read from the repo | `content/docs/_content.gotmpl` and `[module]` in `hugo.toml` |
| Styles and colour tokens | `assets/css/ergo.css` |
| Logo | `static/brand/ergo-wordmark-white.svg` (master), inlined in `layouts/_partials/wordmark.html` and `mark.html`; `static/favicon.svg` |
| Site settings (repo links, status bar) | `hugo.toml` |

## Deploy

GitHub Pages serves the site at https://ergo.kosli.com. `.github/workflows/pages.yml` builds `site/` and deploys it on every push to `main`. You can also run it by hand from the Actions tab.

The custom domain is set in the repo's **Settings → Pages**, with a DNS `CNAME` record pointing `ergo` at `kosli-dev.github.io`.

## Colour is syntax

Each colour means one thing, everywhere:

| Colour | Hex | Means |
| --- | --- | --- |
| Lime | `#D6FF4D` | passed, evidence |
| Signal | `#FE5431` | failed |
| Violet | `#733DF7` | system: `$` checks and keys |
| Paper | `#F7F7EF` | human text |
| Ink | `#080F1A` | structure, background |
