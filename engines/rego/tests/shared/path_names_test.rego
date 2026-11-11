package ergo_test

import data.ergo
import rego.v1

test_a_name_that_starts_or_ends_with_a_space_or_an_invisible_character_is_written_wrong_wherever_it_stands if {
	wrong := "a name can't start or end with a space or an invisible character"
	bad := [" x", "x ", "\tx", "x\t", "\u00a0x", "x\u00a0", "\u200bx", "x\u200b", "\ufeffx", "x\ufeff", "\u2060x", "x\u200d", "\u3000x", "x\ud804\udcbd", "x\udb40\udc01"]
	every name in bad {
		policy := {"ergo_spec": ergo._spec, "subjects": {name: {"from": "xs"}, "t": {"from": "xs"}}, "requirements": {
			name: {"subject": "t", "checks": {"c": "x exists"}},
			"q": {"subject": name, "checks": {"c": "x exists"}},
			"o": {"subject": "t", "checks": {"c": {"any_of": {name: "x exists", "p": "x is 1"}}}},
			"k": {"subject": "t", "checks": {name: "x exists"}},
		}}
		rep := ergo.report({"xs": [{"x": 1}]}, policy, {})
		wrong in [v | some i in rows_for(rep, name, "$well_formed")[0].inputs; i.name == "requirement name"; some v in i.value]
		wrong in [v | some i in rows_for(rep, "q", "$well_formed")[0].inputs; i.name == ergo._field_path_name(["subjects", name]); some v in i.value]
		concat("", ["option ", name, ": ", wrong]) in [v | some i in rows_for(rep, "o", "$well_formed")[0].inputs; i.name == "checks.c"; some v in i.value]
		[i.value | some i in rows_for(rep, "k", "$well_formed")[0].inputs; i.name == ergo._field_path_name(["checks", name])] == [[wrong]]
		parts := ergo.report({"xs": [{"x": 1}]}, {"ergo_spec": ergo._spec, "subjects": {"t": {"from": "xs", "has": {name: "ys"}}}, "requirements": {"r": {"subject": "t", "checks": {"c": "x exists"}}}}, {})
		[i.value | some i in rows_for(parts, "r", "$well_formed")[0].inputs; i.name == ergo._field_path_name(["subjects", "t", "has", name])] == [[wrong]]
	}
}

test_a_name_with_both_problems_lists_both_sorted if {
	policy := {"ergo_spec": ergo._spec, "subjects": {"s": {"from": "xs"}}, "requirements": {"r": {"subject": "s", "checks": {"$x ": "x exists"}}}}
	rep := ergo.report({"xs": [{"x": 1}]}, policy, {})
	[i.value | some i in rows_for(rep, "r", "$well_formed")[0].inputs; i.name == ergo._field_path_name(["checks", "$x "])] == [["a name can't start or end with a space or an invisible character", "a name can't start with $"]]
}

test_a_path_with_no_name_is_called_the_subject_and_never_it if {
	ergo._path_name([]) == "the subject"
	ergo._path_name([0]) == "item 1 of the subject"
	ergo._steps_name([0]) == "the subject[0]"
	ergo._walk_root_name([]) == ["the subject"]
}
