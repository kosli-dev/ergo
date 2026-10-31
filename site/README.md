# Ergo site

The landing page and docs for Ergo, built with [Hugo](https://gohugo.io/) (0.157, extended).

## What follows the release and what follows `main`

The live site shows the latest published release of `ergo.rego`, so it never teaches something people can't download yet. These parts come from that release:

| Part                                 | From the release                                                                                                      |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| The Ergo the tutorial runs           | the `ergo.rego` attached to the release, compiled to Wasm                                                             |
| The tutorial                         | the release tag's `assets/js/tutorial/`, `assets/css/tutorial.css`, `layouts/tutorial.html` and `content/tutorial.md` |
| The docs pages                       | the release tag's `README.md` and `REFERENCE.md`, with `X.Y.Z-dev` written `X.Y.Z` as in the released `ergo.rego`     |
| The bakery page's example            | the release tag's `examples/`                                                                                         |
| The home page's examples and reports | the release tag's `data/examples.yaml`, or this one when the tag has none, as 0.1.0 doesn't                           |
| `ergo_spec` on the home page         | the `_spec` of the released `ergo.rego`                                                                               |
| The spec link and `/spec/X.Y/`       | the published `spec-vX.Y` releases                                                                                    |

Everything else follows `main`: the home page's layout, design and words, the other pages, the CSS other than `tutorial.css`, and the bakery page's text. So a change to the tutorial, the docs, the examples or the home page's examples reaches the site at the next release, and a change to the rest reaches it when it's merged.

## Run it locally

You need the tags, [OPA](https://www.openpolicyagent.org/), `curl`, `openssl`, Python 3 and Node 24. To see the site as it's deployed, from the latest release, you also need the [GitHub CLI](https://cli.github.com/), logged in:

```sh
git fetch --tags
site/prepare.sh
site/check.sh
hugo server -s site
```

To see your own changes instead, like tutorial steps for something that isn't released yet, build from the working tree:

```sh
site/prepare.sh --working-tree
site/check.sh
hugo server -s site
```

Then open http://localhost:1313. Hugo picks up edits to the working tree's tutorial, layouts, CSS and home page examples as you save them. Run `site/prepare.sh --working-tree` again after you change `ergo.rego`, `README.md`, `REFERENCE.md` or `examples/`.

`site/prepare.sh` writes what Hugo needs into folders git ignores, and Hugo stops with a message naming the script when they're missing:

- `site/prepared/` holds what comes from the release, laid out like `site/`, and where a file is in both, Hugo uses the one in `site/prepared/`. It always holds `README.md` and `REFERENCE.md` for the docs and `examples/` for the bakery page, from the release or the working tree, so run the script again after you edit those. The example files end in `.txt`, and the released `ergo.rego` is `ergo.rego.txt`, because OPA loads every `.rego`, `.json` and `.yaml` file under the folder it's given, and they'd clash with the repo's own.
- `site/prepared/data/release.json` holds the versions the home page shows: the release, the newest published `rust-vX.Y.Z` release (empty when there is none, and then the home page leaves it out), the newest published `spec-vX.Y` release, and the spec that `ergo.rego` reads.
- `site/assets/tutorial/` holds `ergo.rego` compiled to Wasm, and OPA's Wasm runtime.
- `site/static/spec/` holds the schemas of every published spec release, from `site/spec-schemas.sh`.

The script picks the newest `rego-vX.Y.Z`, `rust-vX.Y.Z` and `spec-vX.Y` releases by version, and ignores drafts, pre-releases and tags of any other shape. It fails when there's no such release, or when a release's tag isn't fetched. With `--working-tree`, it takes the spec and the Rust release from the `spec-vX.Y` and `rust-vX.Y.Z` tags instead, so it needs no GitHub CLI.

`site/check.sh` tests what `site/prepare.sh` wrote. From the working tree, it runs the tutorial's tests and checks the home page's examples against the working tree's `ergo.rego`. From the release, it runs the released tutorial's tests, checks the home page's examples against the released `ergo.rego`, and checks that the released tutorial still has what it needs from `main`: the CSS variables and classes it took from `ergo.css`, the partials its layout calls, and the files its scripts import.

After `hugo` builds the site, `site/check_build.py <folder>` checks that the built tutorial writes the spec of the Ergo it runs, that its script has the strings of the tutorial `site/prepare.sh` chose and none that only the other one has, that its page has that tutorial's layout and title, that its CSS has that `tutorial.css`'s classes, properties, colours and lengths, and that the home page shows the examples `site/check.sh` checked. That catches a mount in `hugo.toml` that lets `main`'s file win over the release's.

The deploy also builds `packages/playground` and `site/playground.sh` puts it at `/playground/` with a `noindex` meta tag, and also writes a small page at `/editor/` that sends old links on to it. The top navigation of every page links to it, and so does the home page's start section. `check_build.py` fails when the home page has no link to it, when `sitemap.xml` lists it or when the tag is missing. The deploy reuses the Wasm the `test` run built, so it needs a successful `test` run for the commit.

CI does all of this from the working tree and from the release on every pull request, and the deploy runs the release checks before it publishes.

## The tutorial

`/tutorial/` teaches check sentences one step at a time, with Ergo running in the reader's browser as Wasm. The logic that builds the policy and grades each step is in `assets/js/tutorial/lib.mjs`, with no page code in it. The steps' text, hints and goals are in the same file. Its tests, in `lib.test.mjs`, run the built Wasm.

## The home page's examples

The policies, inputs and reports in the hero, the "problem" section and the policy next to the notes come from `data/examples.yaml`. `site/check_examples.py` runs each policy and fails when the report says something else than the page: a row's subject, check, result or cause, or a value it shows. The page can leave out an input, like `require`. An input with `list: <field>` is shown on its own line as that field of each of its items, like `approvers: ann, bob`, so the line comes from the value the check compared. The Ergo policies leave out `ergo_spec`, and the page adds the spec of the `ergo.rego` it runs with.

## Files

| What                                   | Where                                                                                                                               |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Landing page copy                      | front matter in `content/_index.md`                                                                                                 |
| Landing page layout                    | `layouts/home.html`                                                                                                                 |
| Home page examples                     | `data/examples.yaml`, checked by `check_examples.py`                                                                                |
| Docs page shell                        | `layouts/page.html`                                                                                                                 |
| How the docs are read                  | `content/docs/_content.gotmpl` and `[module]` in `hugo.toml`                                                                        |
| Styles and colour tokens               | `assets/css/ergo.css`                                                                                                               |
| Logo                                   | `static/brand/ergo-wordmark-white.svg` (master), inlined in `layouts/_partials/wordmark.html` and `mark.html`; `static/favicon.svg` |
| Tutorial page and layout               | `content/tutorial.md`, `layouts/tutorial.html`                                                                                      |
| Tutorial script and styles             | `assets/js/tutorial/`, `assets/css/tutorial.css`                                                                                    |
| Site settings (repo links, status bar) | `hugo.toml`                                                                                                                         |

## Edit the landing page copy

The words on the landing page live in the front matter of `content/_index.md`, one block per section. The examples and their reports are in `data/examples.yaml`.

Most text is Markdown, so `` `code` ``, `*emphasis*` and `**bold**` work. Write `==ergo==` to get the highlighted name. Headings, labels and button text are plain text.

## Deploy

GitHub Pages serves the site at https://ergo.kosli.com. `.github/workflows/pages.yml` builds `site/` and deploys it each time the `test` workflow passes on `main`, and the release workflow starts it after each release. You can also run it by hand from the Actions tab.

The custom domain is set in the repo's **Settings → Pages**, with a DNS `CNAME` record pointing `ergo` at `kosli-dev.github.io`.

## Colour is syntax

Each colour means one thing, everywhere:

| Colour | Hex       | Means                       |
| ------ | --------- | --------------------------- |
| Lime   | `#D6FF4D` | passed, evidence            |
| Signal | `#FE5431` | failed                      |
| Violet | `#733DF7` | system: `$` checks and keys |
| Paper  | `#F7F7EF` | human text                  |
| Ink    | `#080F1A` | structure, background       |
