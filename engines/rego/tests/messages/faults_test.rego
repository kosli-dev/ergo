package ergo_test

import data.ergo
import rego.v1

test_message_a_number_fits_the_kind_a_number if {
	ergo._m_fits_kind(5, "a number")
	not ergo._m_fits_kind("5", "a number")
}

test_message_kind_of_a_side_read_against_a_written_value_on_the_left if {
	check := {"op": "compare", "cmp": "eq", "left": {"literal": "a"}, "right": ["x"]}
	ergo._m_side_kind({}, check, ["x"]) == "text"
}

test_message_kind_of_a_side_is_ignoring_case_compares_is_text if {
	check := {"op": "compare", "cmp": "eq", "left": ["x"], "right": ["y"], "ignoring": "case"}
	ergo._m_side_kind({"x": 3, "y": "a"}, check, ["x"]) == "text"
	ergo._m_side_kind({"x": "a", "y": 3}, check, ["y"]) == "text"
}

test_a_list_of_is_in_ignoring_case_names_each_item_that_isnt_text_in_list_order if {
	ergo._m_text_items("$params.l", ["a", 3, null, true]) == [
		"item 2 of $params.l is 3, which isn't text",
		"item 3 of $params.l is null",
		"item 4 of $params.l is true, which isn't text",
	]
	ergo._m_text_items("$params.l", ["a", "b"]) == []
}

test_a_root_of_is_in_ignoring_case_says_each_item_of_its_list_and_not_the_list if {
	check := {"op": "in", "path": ["v"], "values": {"ref": ["$$params", "l"]}, "ignoring": "case"}
	ergo._m_root_kind_text({}, check, ["$$params", "l"], "a list of text") == "item 2 of $params.l is null, and item 3 of $params.l is 3, which isn't text" with data.ergo_params as {"l": ["a", null, 3]}
}
