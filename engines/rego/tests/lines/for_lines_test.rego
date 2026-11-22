package ergo_test

import data.ergo
import rego.v1

test_a_for_row_with_no_failed_item_says_what_the_empty_list_found if {
	ergo._for_item_parts({"items": [{"path": ["xs"]}]}, {"xs": []}, {"cause": "value", "failed": []}, []) == ["xs is []"]
}

test_a_root_message_said_inside_another_is_not_said_again if {
	ergo._with_roots(["x is 1"], ["y is missing"]) == ["y is missing", "x is 1"]
	ergo._with_roots(["y is missing", "x is 1"], ["y is missing"]) == ["y is missing", "x is 1"]
	ergo._with_roots(["item 1 of xs: y is missing"], ["y is missing"]) == ["item 1 of xs: y is missing"]
}

test_a_for_row_that_only_names_roots_has_no_item_text if {
	ergo._for_item_parts({}, {}, {"root_msgs": ["a"], "failed": []}, ["a"]) == []
}

test_a_second_for_roots_problem_is_added_to_the_row_in_every_state_the_row_can_be_in if {
	xs := [{"fl": "absent", "ms": ["m"]}]
	ergo._for_second_rooted({"cause": "value", "failed": [{}]}, xs) == {"cause": "absent", "failed": [{}], "other_roots": ["m"]}
	ergo._for_second_rooted({"cause": "value", "failed": [{"failed_assertions": [1]}]}, xs) == {"cause": "absent", "failed": [], "root_msgs": ["m"]}
	ergo._for_second_rooted({"cause": "unusable", "failed": [{"failed_assertions": [1]}]}, xs) == {"cause": "unusable", "failed": [{"failed_assertions": [1]}], "other_roots": ["m"]}
}

test_a_root_said_once_is_not_said_again_under_an_item_and_its_count_of_more_goes_with_it if {
	ergo._for_deduped("item 2 of pos: name is missing; item 1 of ms: item 2 of pos: name is missing; item 1 of ms: and 2 more") == "item 2 of pos: name is missing"
	ergo._for_deduped("item 1 of ms: v is missing; item 1 of ms: and 2 more") == "item 1 of ms: v is missing; item 1 of ms: and 2 more"
}

test_a_for_line_keeps_that_a_member_walk_wanted_an_object if {
	ergo._for_failed_flags({"msg": "an object"}).wants == "an object"
	not ergo._for_failed_flags({"msg": "a list"}).wants
	not ergo._for_failed_flags({}).wants
}

test_a_for_line_drops_a_member_clause_that_only_repeats_a_text_or_says_how_many_more if {
	not ergo._for_led_once("member a of xs: $params.k is missing", ["member b of ys: $params.k is missing"])
	ergo._for_led_once("member a of xs: member b of ys is 1", ["member b of ys is 1"])
	ergo._for_led_more("member a of xs: and 2 more")
	not ergo._for_led_more("member a of xs: v is 1")
}

test_an_item_of_the_second_list_keeps_that_a_member_walk_wanted_an_object if {
	check := {"items": [{"as": "r", "path": ["rs"]}, {"as": "y", "path": ["$r", "s"]}]}
	f := {"path": ["$r", "s"], "item": ["$r", "s"], "cause": "unusable", "value": [1], "msg": "an object"}
	ergo._for_unchecked_item(check, f).wants == "an object"
	not ergo._for_unchecked_item(check, object.union(f, {"msg": "a list"})).wants
}

_second_list_outcome(line, subj) := object.get([i | some i in ergo._for_inputs(check, subj, {}, check.items[0], ergo._for_walk(check.items[0], subj, {})); i.name == "x.ys"][0], "ergo/outcome", "usable") if {
	check := ergo._s_written_check({"for": line, "assert": "y is 1"})
}

test_a_second_list_that_no_item_of_the_first_reads_says_its_worst_stop_in_any_order if {
	member := "every xs as x, every member of x.ys as y"
	plain := "every xs as x, every x.ys as y"
	_second_list_outcome(member, {"xs": [{"ys": [1]}]}) == "unusable"
	_second_list_outcome(member, {"xs": [{"ys": 3}, {"ys": null}]}) == "unusable"
	_second_list_outcome(member, {"xs": [{"ys": null}, {"ys": 3}]}) == "unusable"
	_second_list_outcome(member, {"xs": [{"ys": null}, {}]}) == "absent"
	_second_list_outcome(plain, {"xs": [{"ys": null}]}) == "null"
	_second_list_outcome(plain, {"xs": [{"ys": {"a": 1}}, {"ys": 3}]}) == "unusable"
	_second_list_outcome(member, {"xs": [{"ys": {"a": 1}}, {"ys": 3}]}) == "usable"
}
