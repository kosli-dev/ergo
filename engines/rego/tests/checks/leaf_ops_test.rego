package ergo_test

import data.ergo
import rego.v1

test_rfc3339_gate_accepts_valid_timestamps if {
	every ts in [
		"2024-01-01T00:00:00Z",
		"2024-06-30T23:59:59.999999999Z",
		"2024-06-30T12:00:00+02:00",
		"2024-06-30T12:00:00-05:30",
	] {
		ergo._rfc3339_shaped(ts)
	}
}

test_rfc3339_gate_rejects_everything_else if {
	every ts in [
		"yesterday",
		"",
		"2024-01-01",
		"2024-01-01T00:00:00z",
		"2024-01-01t00:00:00Z",
		"2024-02-30T00:00:00Z",
		"1677-12-31T23:59:59Z",
		"2262-01-01T00:00:00Z",
		"2024-13-01T00:00:00Z",
		"2024-00-01T00:00:00Z",
		"2024-01-32T00:00:00Z",
		"2024-01-01T24:00:00Z",
		"2024-01-01T00:60:00Z",
		"2024-12-31T23:59:60Z",
		"2024-01-01T00:00:00",
		"2024-01-01T00:00:00+24:00",
		"24-01-01T00:00:00Z",
		1753600000,
		null,
		true,
		["2024-01-01T00:00:00Z"],
	] {
		not ergo._rfc3339_shaped(ts)
	}
}

test_starts_with_only_ever_compares_two_strings_even_through_leaf_passed if {
	not ergo._leaf_passed({"op": "compare_time", "left": ["n"], "cmp": "starts_with", "right": ["m"]}, {"n": 15, "m": 1})
	not ergo._leaf_passed({"op": "compare_time", "left": ["n"], "cmp": "ends_with", "right": ["m"]}, {"n": 15, "m": 1})
}

test_a_list_comparison_only_ever_passes_on_values_of_the_type_it_reads_even_through_leaf_passed if {
	every cmp in ["in", "not_in", "includes", "excludes", "includes_all", "excludes_all", "matches_any", "not_matches_any"] {
		not ergo._leaf_passed({"op": "compare_time", "left": ["n"], "cmp": cmp, "right": ["m"]}, {"n": 15, "m": 1})
	}
	not ergo._leaf_passed({"op": "compare", "left": ["x"], "cmp": "matches_any", "right": ["y"]}, {"x": "a", "y": ["("]})
	not ergo._leaf_passed({"op": "compare", "left": ["x"], "cmp": "not_matches_any", "right": ["y"]}, {"x": "a", "y": ["(", "^b"]})
	not ergo._leaf_passed({"op": "compare", "left": ["x"], "cmp": "includes_all", "right": ["y"]}, {"x": ["a"], "y": []})
}

test_is_ignoring_case_compares_the_prepared_texts if {
	is := {"op": "compare", "left": ["x"], "cmp": "eq", "right": {"literal": "in progress"}, "ignoring": "case and surrounding spaces"}
	ergo._leaf_passed(is, {"x": "  IN Progress "})
	not ergo._leaf_passed(is, {"x": "done"})
	is_not := object.union(is, {"cmp": "ne"})
	not ergo._leaf_passed(is_not, {"x": "In Progress"})
	ergo._leaf_passed(is_not, {"x": "done"})
	case_only := {"op": "compare", "left": ["x"], "cmp": "eq", "right": ["y"], "ignoring": "case"}
	ergo._leaf_passed(case_only, {"x": "A", "y": "a"})
	not ergo._leaf_passed(case_only, {"x": " A", "y": "a"})
}

test_is_ignoring_case_fails_as_unusable_on_a_value_that_isnt_text_on_either_side if {
	every cmp in ["eq", "ne"] {
		check := {"op": "compare", "left": ["x"], "cmp": cmp, "right": ["y"], "ignoring": "case"}
		every subj in [{"x": 3, "y": "3"}, {"x": "3", "y": 3}, {"x": true, "y": "true"}, {"x": ["a"], "y": "a"}, {"x": "a", "y": {"a": 1}}] {
			not ergo._leaf_passed(check, subj)
			ergo._unusable_states(check, subj) == {"unusable"}
		}
	}
}

test_in_ignoring_case_compares_the_prepared_texts if {
	check := {"op": "in", "path": ["x"], "values": ["in progress", "done"], "ignoring": "case and surrounding spaces"}
	ergo._leaf_passed(check, {"x": " IN Progress "})
	ergo._leaf_passed(check, {"x": "Done"})
	not ergo._leaf_passed(check, {"x": "blocked"})
	not_in := object.union(check, {"op": "not_in"})
	not ergo._leaf_passed(not_in, {"x": "DONE"})
	ergo._leaf_passed(not_in, {"x": "blocked"})
	field := {"op": "compare", "left": ["x"], "cmp": "in", "right": ["ys"], "ignoring": "case"}
	ergo._leaf_passed(field, {"x": "A", "ys": ["b", "a"]})
	not ergo._leaf_passed(object.union(field, {"cmp": "not_in"}), {"x": "A", "ys": ["b", "a"]})
}

test_in_ignoring_case_never_passes_on_a_list_with_a_value_that_isnt_text if {
	every op in ["in", "not_in"] {
		every values in [["a", null], ["a", 3], [["a"]]] {
			not ergo._leaf_passed({"op": op, "path": ["x"], "values": values, "ignoring": "case"}, {"x": "b"})
			not ergo._leaf_passed({"op": "compare", "left": ["x"], "cmp": op, "right": ["ys"], "ignoring": "case"}, {"x": "b", "ys": values})
		}
		not ergo._leaf_passed({"op": op, "path": ["x"], "values": ["a"], "ignoring": "case"}, {"x": 3})
	}
}
