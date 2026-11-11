package ergo_test

import data.ergo
import rego.v1

test_a_for_row_with_no_failed_item_says_what_the_empty_list_found if {
	ergo._for_item_text({"items": [{"path": ["xs"]}]}, {"xs": []}, {"cause": "value", "failed": []}, []) == "xs is []"
}

test_a_root_message_said_inside_another_is_not_said_again if {
	ergo._with_roots(["x is 1"], ["y is missing"]) == ["y is missing", "x is 1"]
	ergo._with_roots(["y is missing", "x is 1"], ["y is missing"]) == ["y is missing", "x is 1"]
	ergo._with_roots(["item 1 of xs: y is missing"], ["y is missing"]) == ["item 1 of xs: y is missing"]
}

test_a_for_row_that_only_names_roots_has_no_item_text if {
	ergo._for_item_text({}, {}, {"root_msgs": ["a"], "failed": []}, ["a"]) == ""
}

test_a_second_for_roots_problem_is_added_to_the_row_in_every_state_the_row_can_be_in if {
	xs := [{"fl": "absent", "ms": ["m"]}]
	ergo._for_second_rooted({"cause": "value", "failed": [{}]}, xs) == {"cause": "absent", "failed": [{}], "other_roots": ["m"]}
	ergo._for_second_rooted({"cause": "value", "failed": [{"failed_assertions": [1]}]}, xs) == {"cause": "absent", "failed": [], "root_msgs": ["m"]}
	ergo._for_second_rooted({"cause": "unusable", "failed": [{"failed_assertions": [1]}]}, xs) == {"cause": "unusable", "failed": [{"failed_assertions": [1]}], "other_roots": ["m"]}
}
