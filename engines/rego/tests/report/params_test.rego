package ergo_test

import data.ergo
import rego.v1

test_a_missing_params_path_is_left_out_and_its_item_moves_to_the_next_part if {
	ergo._params_rest("item 2 of xs: $params.a is missing, and m.w is missing; y is missing") == ["item 2 of xs: m.w is missing", "y is missing"]
}

test_a_chunk_that_only_names_missing_params_is_left_out if {
	ergo._params_rest("$params.a is missing; xs named by $params.k is missing") == []
}

test_the_count_of_hidden_items_is_left_out_when_a_line_was_dropped_because_it_may_count_that_line if {
	ergo._params_rest("$params.k is missing; item 1 of es: v: $params.k is missing; item 2 of es: v is missing; and 1 more") == ["item 2 of es: v is missing"]
	ergo._params_rest("item 1 of es: v is 2; item 2 of es: v is 3; item 3 of es: v is 4; and 1 more") == ["item 1 of es: v is 2", "item 2 of es: v is 3", "item 3 of es: v is 4", "and 1 more"]
}

test_the_params_problem_is_the_first_one_said_in_the_form_path_start_gives if {
	ergo._params_problem(["zz is \"v\", which isn't a list, and $params is 3, which isn't a list", "b: $params is 3, which isn't an object"]) == "$params is 3, which isn't a list"
	ergo._params_problem(["x is 2"]) == "$params is 3, which isn't an object" with data.ergo_params as 3
}

test_what_a_check_says_with_broken_params_drops_the_params_problem_and_the_fallback if {
	check := {"expression": "x is 1", "checks": [{"op": "eq", "path": ["$$params", "a"]}]}
	ergo._params_said_rest(check, "x is 1 is false; the check is false; zz is \"v\", which isn't a list, and $params is 3, which isn't an object; b: $params is 3, which isn't an object") == ["zz is \"v\", which isn't a list"]
}

test_what_a_check_that_reads_no_params_says_with_broken_params_is_not_kept_because_its_message_with_no_params_is_the_right_one if {
	ergo._params_said_rest({"expression": "x is 1"}, "x is 1 is false") == []
}

test_a_missing_params_path_said_first_with_no_item_leaves_the_rest_of_the_sentence if {
	ergo._params_rest("$params.a is missing, and y is missing") == ["y is missing"]
}

test_a_row_that_passed_keeps_no_message_so_it_never_drops_out_of_the_report if {
	ergo._params_first_row({"passed": true, "cause": "satisfied"}, {}, []) == {"passed": true, "cause": "satisfied"}
}
