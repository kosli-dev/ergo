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

test_every_member_of_a_subjects_name_is_a_child_and_never_narrows_it if {
	fl := {"every": true, "member": true, "path": {"steps": ["rec"]}}
	subjects := {"rec": {"from": "records"}, "m": {"from": "every member of rec"}}
	ergo._s_descends("m", fl, subjects)
	not ergo._s_narrows("m", fl, subjects)
	ergo._s_every_unsupported("m", fl, subjects) == set()
}

test_member_of_goes_after_every_and_never_with_distinct if {
	ergo._s_every_unsupported("a", {"member": true, "path": {"steps": ["x"]}}, {}) == {`on a from line, member of goes after every, like "every member of record.evidence"`}
	ergo._s_every_unsupported("b", {"every": true, "distinct": true, "member": true, "path": {"steps": ["x"]}}, {}) == {"distinct can't go with every member of"}
}

test_distinct_member_of_without_every_says_each_of_its_three_problems if {
	ergo._s_every_unsupported("a", {"distinct": true, "member": true, "path": {"steps": ["x"]}}, {}) == {
		"distinct can't go with every member of",
		`on a from line, distinct goes after every, like "every distinct sbom.components"`,
		`on a from line, member of goes after every, like "every member of record.evidence"`,
	}
}
