# ergo site

The landing page and docs for ergo, built with [Hugo](https://gohugo.io/) (0.157, extended).

The docs pages aren't copied here. They're read from the repo's own `README.md` and `REFERENCE.md` when the site builds, so change the docs there and the site follows.

## Run it locally

```sh
hugo server -s site
```

Then open http://localhost:1313.

The playground at `/playground/` needs ergo compiled to Wasm, and two JavaScript libraries. Build them once, and again after changing `ergo.rego`:

```sh
site/build-playground.sh
```

It needs [OPA](https://www.openpolicyagent.org/docs/#1-download-opa) and writes to `assets/playground/`, which git ignores. It downloads `@open-policy-agent/opa-wasm` and `js-yaml` from npm and stops if either doesn't match the hash pinned in the script, so to upgrade one, change its version and hash together. Hugo bundles them into the page's script, so the page loads no scripts from other sites.

The code that converts between YAML, JSON and Rego is in `assets/js/playground/lib.mjs`. Test it with:

```sh
node --test site/assets/js/playground/lib.test.mjs
```

The tests run `opa`, and CI runs them on every pull request, along with the script and a build of the site.

## Files

| What | Where |
| --- | --- |
| Landing page copy | front matter in `content/_index.md` |
| Landing page layout | `layouts/home.html` |
| Docs page shell | `layouts/page.html` |
| How the docs are read from the repo | `content/docs/_content.gotmpl` and `[module]` in `hugo.toml` |
| Styles and colour tokens | `assets/css/ergo.css` |
| Logo | `static/brand/ergo-wordmark-white.svg` (master), inlined in `layouts/_partials/wordmark.html` and `mark.html`; `static/favicon.svg` |
| Site settings (repo links, status bar) | `hugo.toml` |
| Playground (not linked from the site) | `content/playground.md`, `layouts/playground.html`, `assets/js/playground/`, `build-playground.sh` |

## Edit the landing page copy

The words on the landing page live in the front matter of `content/_index.md`, one block per section. The code samples and the example report stay in `layouts/home.html`.

Most text is Markdown, so `` `code` ``, `*emphasis*` and `**bold**` work. Write `==ergo==` to get the highlighted name. Headings, labels and button text are plain text.

## Deploy

GitHub Pages serves the site at https://ergo.kosli.com. `.github/workflows/pages.yml` builds `site/` and deploys it each time the `test` workflow passes on `main`. You can also run it by hand from the Actions tab.

The Pages workflow must not share any top-level keys with `test.yml` (for example `name`, `permissions` or `on.push`). `opa check .` loads every YAML file in the repo as data, and clashing keys fail the tests with a "merge error".

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
