import html
import json
import pathlib
import re
import subprocess
import sys
import urllib.parse

public = pathlib.Path(sys.argv[1])
site = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else pathlib.Path(__file__).parent)
prepared = site / "prepared"
release = json.loads((prepared / "data/release.json").read_text())
spec = release["ergo_spec"]
problems = []

def used(path):
    return prepared / path if (prepared / path).exists() else site / path


def strings(folder):
    found = set()
    for name in ("lib.mjs", "main.mjs"):
        text = (folder / name).read_text()
        found |= {s for s in re.findall(r'"([A-Za-z][\w ,.:;!?()\'/-]{2,})"', text) if not s.startswith(("./", "../"))}
    return found


def css_parts(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S).lower()
    parts = set(re.findall(r"\.(-?[_a-z][\w-]*)", text))
    parts |= {"property " + p for p in re.findall(r"([-a-z]+)\s*:(?!:)", text)}
    parts |= set(re.findall(r"var\(--[\w-]+\)", text))
    parts |= {"#" + (h if len(h) == 6 else "".join(c * 2 for c in h)) for h in re.findall(r"#([0-9a-f]{6}|[0-9a-f]{3})\b", text)}
    for length in re.findall(r"(?<![\w.#-])(\d*\.?\d+(?:px|rem|em|vw|vh|dvh|ch|%))", text):
        if float(re.match(r"[\d.]+", length).group()) != 0:
            parts.add(re.sub(r"^0(?=\.)", "", length))
    return parts


bundles = sorted((public / "js/tutorial").glob("main.*.js"))
if not bundles:
    problems.append("the build has no tutorial script")
script = used("assets/js/tutorial/lib.mjs").parent
wanted = strings(script)
others = strings(site / "assets/js/tutorial") - wanted if script != site / "assets/js/tutorial" else set()
for bundle in bundles:
    text = bundle.read_text()
    found = set(re.findall(r'ergo_spec:\s*"([^"]*)"', text))
    if found != {spec}:
        problems.append(f"the tutorial's policies say ergo_spec {', '.join(sorted(found)) or 'nothing'}, and the Ergo it runs reads {spec}")
    shows = lambda s: re.search("[\"'`]" + re.escape(s) + "[\"'`]", text) is not None
    for s in sorted(s for s in wanted if not shows(s)):
        problems.append(f"the tutorial script doesn't have \"{s}\", from {script}")
    for s in sorted(s for s in others if shows(s)):
        problems.append(f"the tutorial script has \"{s}\", which only {site / 'assets/js/tutorial'} has")


tutorial_page = (public / "tutorial/index.html").read_text()
layout = used("layouts/tutorial.html")
names = set(re.findall(r"\b(data-[\w-]+)", layout.read_text()))
built_names = set(re.findall(r"\b(data-[\w-]+)", tutorial_page))
for name in sorted(names - built_names):
    problems.append(f"the tutorial page has no {name}, which {layout} writes")
other = site / "layouts/tutorial.html"
if other != layout:
    for name in sorted((set(re.findall(r"\b(data-[\w-]+)", other.read_text())) - names) & built_names):
        problems.append(f"the tutorial page has {name}, which only {other} writes")

content = used("content/tutorial.md")
title = re.search(r'^title:\s*"?(.*?)"?\s*$', content.read_text(), re.M).group(1)
built_title = re.search(r"<title>(.*?)</title>", tutorial_page, re.S)
if not title or not built_title or not html.unescape(built_title.group(1)).startswith(title):
    problems.append(f"the tutorial page's title isn't \"{title}\", from {content}")

css = used("assets/css/tutorial.css")
built_css = sorted((public / "css").glob("tutorial*.css"))
if not built_css or css_parts(css.read_text()) != css_parts(built_css[0].read_text()):
    problems.append(f"the built tutorial.css doesn't have the classes, properties, colours and lengths of {css}")

examples_file = used("data/examples.yaml")
out = subprocess.run(["opa", "eval", "--format", "json", "-i", str(examples_file), "input"], capture_output=True, text=True, check=True)
examples = json.loads(out.stdout)["result"][0]["expressions"][0]["value"]
page = (public / "index.html").read_text()
shown = {html.unescape(re.sub(r"<[^>]+>", "", block)).strip() for block in re.findall(r"<pre[^>]*><code>(.*?)</code></pre>", page, re.S)}
for name in sorted(examples):
    for what, text in (("input", examples[name]["input"]), ("policy", f"ergo_spec: {spec}\n{examples[name]['policy']}")):
        if text.strip() not in shown:
            problems.append(f"the home page doesn't show the {what} of {name} from {examples_file}")

editor_page = public / "editor/index.html"
link = re.compile(r"""\b(?:href|src|action|content)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))""", re.I)
for page_file in sorted(public.rglob("*.html")):
    if page_file == editor_page:
        continue
    address = "https://site.test/" + page_file.relative_to(public).as_posix()
    for match in link.finditer(page_file.read_text(errors="replace")):
        target = html.unescape(next(g for g in match.groups() if g is not None)).strip()
        path = urllib.parse.urlsplit(urllib.parse.urljoin(address, target)).path
        if re.search(r"/editor(/(index\.html)?)?$", path):
            problems.append(f"{page_file.relative_to(public)} links to the editor with \"{target}\"")
sitemap = public / "sitemap.xml"
if sitemap.exists() and "/editor" in sitemap.read_text():
    problems.append("sitemap.xml lists the editor")
if editor_page.exists() and not re.search(r"""<meta\s+name=["']robots["']\s+content=["']noindex["']""", editor_page.read_text(errors="replace"), re.I):
    problems.append("the editor page has no noindex meta")

if problems:
    print("\n".join(problems))
    raise SystemExit(1)
print(f"The built site shows the tutorial and the home page's examples from {release['source']}")
