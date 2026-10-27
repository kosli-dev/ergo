# Ergo site

The landing page and docs for Ergo, built with [Hugo](https://gohugo.io/) (0.157, extended).

The site shows the latest release of Ergo, not `main`. The docs pages, the bakery example and the tutorial's Ergo all come from the newest `rego-vX.Y.Z` tag, so a change to `README.md`, `REFERENCE.md`, `examples/` or `ergo.rego` reaches the site when it's released.

## Run it locally

You need the tags, [OPA](https://www.openpolicyagent.org/), `curl` and `openssl`:

```sh
git fetch --tags
site/prepare.sh
hugo server -s site
```

Then open http://localhost:1313.

`site/prepare.sh` picks the newest `rego-vX.Y.Z` tag by version, ignoring tags of any other shape, and writes what Hugo needs from it, all of which git ignores:

- `site/release/` holds that tag's `README.md`, `REFERENCE.md` and `examples/`, with `X.Y.Z-dev` written `X.Y.Z` as in the `ergo.rego` the release publishes. Each example file ends in `.txt`, so that OPA, which loads every `.rego`, `.json` and `.yaml` file under the folder it's given, doesn't load them next to the repo's own.
- `site/assets/tutorial/` holds that `ergo.rego` compiled to Wasm, OPA's Wasm runtime, and `release.mjs`, which says the spec version the tutorial writes in its policies.
- `site/data/release.json` holds the versions the home page shows: the release, the newest `spec-vX.Y` tag, and the spec that `ergo.rego` reads, for the `ergo_spec` lines.
- `site/static/spec/` holds the schemas of every released spec, from `site/spec-schemas.sh`.

Run it again after a new release. Hugo stops with a message naming the script when any of it is missing.

## The tutorial

`/tutorial/` teaches check sentences one step at a time, with Ergo running in the reader's browser as Wasm. It runs the released `ergo.rego`, so the tutorial on `main` must work with the latest release. The tests check that, with Node 24:

```sh
site/prepare.sh
node --test site/assets/js/tutorial/lib.test.mjs
hugo server -s site
```

Then open http://localhost:1313/tutorial/. The tests run the built Wasm, so they need the script to have run first.

The logic that builds the policy and grades each step is in `assets/js/tutorial/lib.mjs`, with no page code in it. The steps' text, hints and goals are in the same file.

## Files

| What | Where |
| --- | --- |
| Landing page copy | front matter in `content/_index.md` |
| Landing page layout | `layouts/home.html` |
| Docs page shell | `layouts/page.html` |
| How the docs are read from the release | `content/docs/_content.gotmpl` and `[module]` in `hugo.toml` |
| Styles and colour tokens | `assets/css/ergo.css` |
| Logo | `static/brand/ergo-wordmark-white.svg` (master), inlined in `layouts/_partials/wordmark.html` and `mark.html`; `static/favicon.svg` |
| Tutorial page and layout | `content/tutorial.md`, `layouts/tutorial.html` |
| Tutorial script and styles | `assets/js/tutorial/`, `assets/css/tutorial.css` |
| Site settings (repo links, status bar) | `hugo.toml` |

## Edit the landing page copy

The words on the landing page live in the front matter of `content/_index.md`, one block per section. The code samples and the example report stay in `layouts/home.html`.

Most text is Markdown, so `` `code` ``, `*emphasis*` and `**bold**` work. Write `==ergo==` to get the highlighted name. Headings, labels and button text are plain text.

## Deploy

GitHub Pages serves the site at https://ergo.kosli.com. `.github/workflows/pages.yml` builds `site/` and deploys it each time the `test` workflow passes on `main`, and the release workflow starts it after each release. You can also run it by hand from the Actions tab.

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
