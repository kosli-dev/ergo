import pathlib
import re
import sys

site = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).parent).resolve()
prepared = site / "prepared"
layout = (prepared / "layouts/tutorial.html").read_text()
tutorial_css = (prepared / "assets/css/tutorial.css").read_text()
ergo_css = (site / "assets/css/ergo.css").read_text()
released_ergo_css = (prepared / "reference/ergo.css").read_text()
problems = []

def variables(css):
    return set(re.findall(r"(--[\w-]+)\s*:", css))


needed = set(re.findall(r"var\((--[\w-]+)", tutorial_css + layout)) & variables(released_ergo_css)
for name in sorted(needed - variables(tutorial_css) - variables(ergo_css)):
    problems.append(f"the released tutorial uses the CSS variable {name} from css/ergo.css, which no longer defines it")

for name in sorted(set(re.findall(r'partial "([^"]+)"', layout))):
    if not (site / "layouts/_partials" / name).exists() and not (prepared / "layouts/_partials" / name).exists():
        problems.append(f"the released tutorial layout uses the partial {name}, which layouts/_partials doesn't have")

generated = {"tutorial/ergo.wasm"}
for path in sorted(set(re.findall(r'resources\.Get "([^"]+)"', layout)) - generated):
    if not (site / "assets" / path).exists() and not (prepared / "assets" / path).exists():
        problems.append(f"the released tutorial layout reads assets/{path}, which doesn't exist")

def classes(css):
    return set(re.findall(r"\.(-?[_a-zA-Z][\w-]*)", css))


used = {c for attr in re.findall(r'class="([^"{]*)"', layout) for c in attr.split()}
for name in sorted((used & classes(released_ergo_css)) - classes(tutorial_css) - classes(ergo_css)):
    problems.append(f"the released tutorial layout uses the class {name} from css/ergo.css, which no longer styles it")

js = prepared / "assets/js/tutorial"
for file in sorted(js.glob("*.mjs")):
    for spec in re.findall(r'from "(\.[^"]+)"', file.read_text()):
        target = (file.parent / spec).resolve().relative_to((prepared / "assets").resolve())
        if not (site / "assets" / target).exists() and not (prepared / "assets" / target).exists():
            problems.append(f"the released {file.name} imports {spec}, which doesn't exist")

if problems:
    print("\n".join(problems))
    raise SystemExit(1)
print("The released tutorial fits this site's layouts and CSS")
