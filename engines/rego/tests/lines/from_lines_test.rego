package ergo_test

import data.ergo
import rego.v1

test_a_check_on_an_item_that_isnt_an_object_keeps_its_words_when_the_requirement_names_no_subject if {
	ergo._named_check({"op": "exists"}, {}, 3) == {"op": "exists"}
	ergo._named_check({"op": "exists"}, {"subject": "t"}, 3) == {"op": "exists", "label": "t"}
}

test_a_requirement_that_reads_parts_only_by_name_runs_without_a_scope_because_a_scope_makes_opa_work_out_every_row_again if {
	parts := {"parts": {"s": {"cov": {}}}}
	not ergo._scoped_of({"subject": "s", "checks": {"c": {"op": "present", "path": [ergo._p_marker("cov", 1, null, false), "b", "x"]}}}) with data.ergo_subject_sentences as parts
	ergo._scoped_of({"subject": "s", "checks": {"c": {"op": "present", "path": [ergo._p_marker("cov", 1, null, true), "b", "x"]}}}) with data.ergo_subject_sentences as parts
}

test_a_check_with_a_for_key_and_no_op_is_a_for_check if {
	ergo._for_check({"for": "every xs as m", "assert": "m.v is 1"})
	ergo._for_check({"op": "for"})
	not ergo._for_check({"op": "all_of"})
}

test_a_from_line_note_about_mixed_types_says_one_clause_per_item_so_each_item_entry_gets_its_own if {
	req := {"subject": "s", "from": ["things"]}
	mixed := {"types": [["text", ["things", 0], "a"], ["a number", ["things", 1], 1]], "plain": true}
	ergo._fl_note_clauses(req, mixed) == ["item 1 of things is text", "item 2 of things is a number"]
	beside := {"list": {"c": ["things", 0, "xs"]}, "other": {"c": ["things", 1, "xs"], "v": 3}}
	ergo._fl_note_clauses(req, beside) == ["item 1 of things: xs is a list", "item 2 of things: xs is a number"]
}
