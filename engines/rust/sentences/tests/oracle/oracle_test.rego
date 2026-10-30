package oracle

import data.ergo

check(line) := {"kind": "rejected", "problems": p.problems} if {
	p := ergo._sentence(line)
	not "assertions" in object.keys(p)
}

check(line) := {"kind": "ok", "printed": ergo._s_check_text({"assertions": plain}), "plain": sort(ergo._s_self_problems(plain)), "aliases": sort(ergo._s_self_problems(aliased)), "unsupported": sort(ergo._s_unsupported(p))} if {
	p := ergo._sentence(line)
	"assertions" in object.keys(p)
	plain := [ergo._s_aliased(a, ergo._s_names(set(), set())) | some a in p.assertions]
	aliased := [ergo._s_aliased(a, ergo._s_names({"pr", "x"}, set())) | some a in p.assertions]
}

for(line) := {"kind": "rejected", "problems": p.problems} if {
	p := ergo._for_line(line)
	not "items" in object.keys(p)
}

for(line) := {"kind": "ok", "printed": ergo._s_for_line_text({"items": plain}), "plain": sort(ergo._s_whose_self_problems(plain)), "aliases": sort(ergo._s_whose_self_problems(aliased)), "unsupported": sort(ergo._s_for_unsupported(p, []))} if {
	p := ergo._for_line(line)
	"items" in object.keys(p)
	plain := ergo._s_marked_items(p, set())
	aliased := ergo._s_marked_items(p, {"pr", "x"})
}

from(line) := {"kind": "rejected", "problems": fl.problems} if {
	fl := ergo._from_line(line)
	"problems" in object.keys(fl)
}

from(line) := {"kind": "ok", "printed": ergo._s_from_line_text(fl)} if {
	fl := ergo._from_line(line)
	not "problems" in object.keys(fl)
}

path(line) := {"kind": "ok", "printed": ergo._s_path_text(fl.path, "left")} if {
	fl := ergo._from_line(line)
	object.keys(fl) == {"path"}
} else := {"kind": "rejected"}

out := {
	"checks": {l: check(l) | some l in input.checks},
	"fors": {l: for(l) | some l in input.fors},
	"froms": {l: from(l) | some l in input.froms},
	"paths": {l: path(l) | some l in input.paths},
}
