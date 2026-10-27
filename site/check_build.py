import html
import json
import pathlib
import re
import subprocess
import sys

public = pathlib.Path(sys.argv[1])
site = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else pathlib.Path(__file__).parent)
prepared = site / "prepared"
release = json.loads((prepared / "data/release.json").read_text())
spec = release["ergo_spec"]
problems = []

bundles = sorted((public / "js/tutorial").glob("main.*.js"))
if not bundles:
    problems.append("the build has no tutorial script")
for bundle in bundles:
    found = set(re.findall(r'ergo_spec:\s*"([^"]*)"', bundle.read_text()))
    if found != {spec}:
        problems.append(f"the tutorial's policies say ergo_spec {', '.join(sorted(found)) or 'nothing'}, and the Ergo it runs reads {spec}")

def used(path):
    return prepared / path if (prepared / path).exists() else site / path


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
if not built_title or not html.unescape(built_title.group(1)).startswith(title):
    problems.append(f"the tutorial page's title isn't \"{title}\", from {content}")

css = used("assets/css/tutorial.css")
selectors = set(re.findall(r"\.(-?[_a-zA-Z][\w-]*)", css.read_text()))
built_css = sorted((public / "css").glob("tutorial*.css"))
built_selectors = set(re.findall(r"\.(-?[_a-zA-Z][\w-]*)", built_css[0].read_text())) if built_css else set()
if selectors != built_selectors:
    problems.append(f"the built tutorial.css doesn't have the classes of {css}")

examples_file = used("data/examples.yaml")
out = subprocess.run(["opa", "eval", "--format", "json", "-i", str(examples_file), "input"], capture_output=True, text=True, check=True)
examples = json.loads(out.stdout)["result"][0]["expressions"][0]["value"]
page = (public / "index.html").read_text()
shown = {html.unescape(re.sub(r"<[^>]+>", "", block)).strip() for block in re.findall(r"<pre[^>]*><code>(.*?)</code></pre>", page, re.S)}
for name in sorted(examples):
    for what, text in (("input", examples[name]["input"]), ("policy", f"ergo_spec: {spec}\n{examples[name]['policy']}")):
        if text.strip() not in shown:
            problems.append(f"the home page doesn't show the {what} of {name} from {examples_file}")

if problems:
    print("\n".join(problems))
    raise SystemExit(1)
print(f"The built site shows the tutorial and the home page's examples from {release['source']}")
