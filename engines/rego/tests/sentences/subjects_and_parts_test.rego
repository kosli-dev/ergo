package ergo_test

import data.ergo
import rego.v1

test_a_from_condition_that_cannot_be_turned_back_into_text_is_written_wrong_and_never_dropped if {
	read := ergo._s_from_read("x", {"path": {"steps": ["xs"]}, "where": [{"nonsense": true, "phrase": {"op": "is", "value": 1}}]}, {"x": {"from": "xs"}}, {"parts": {}, "descend": {}, "narrow": {}})
	"whose: a condition can't be read" in read.problems
}

test_a_subject_that_narrows_a_child_descends_from_the_childs_parent if {
	parts := ergo._p_parts({
		"art": {"from": "arts"},
		"b": {"from": "art.bs"},
		"nb": {"from": "b whose x exists"},
		"nnb": {"from": "nb whose y exists"},
		"c": {"from": "nnb.cs"},
		"na": {"from": "art whose z exists"},
	})
	parts.descend == {"b": "art", "nb": "art", "nnb": "art", "c": "nnb"}
}
