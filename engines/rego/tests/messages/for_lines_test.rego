package ergo_test

import data.ergo
import rego.v1

test_message_a_list_holds_a_position_and_an_object_holds_a_key if {
	ergo._m_holds([1], 0)
	ergo._m_holds({"a": 1}, "a")
	not ergo._m_holds({"a": 1}, 0)
	not ergo._m_holds([1], "a")
}

test_message_for_item_that_has_nothing_to_walk_is_narrowed_when_its_list_is_empty if {
	ergo._m_narrows({"xs": []}, {"path": ["xs"]})
	not ergo._m_narrows({"xs": [1]}, {"path": ["xs"]})
}

test_message_for_item_that_isnt_an_object_says_so if {
	ergo._m_named_item({"cause": "not_an_object", "item": "item 1 of xs", "value": 5}) == "item 1 of xs is 5, which isn't an object"
}

test_message_tie_without_a_sort_key_names_no_key if {
	ergo._m_tie_on({"items": [{}]}, 0) == ""
}

test_message_ties_in_different_lists_are_joined_with_and if {
	ergo._m_listed(["item 1 of xs", "item 2 of ys"]) == "item 1 of xs and item 2 of ys"
	ergo._m_listed(["item 1 of xs", "item 2 of xs"]) == "item 1 and item 2 of xs"
}

test_message_of_a_subject_that_does_not_match_without_a_filter_message if {
	ergo._m_applies({}, {"subject": "thing"}, false) == {"message": "thing doesn't match"}
}

test_message_a_name_that_is_not_a_for_alias_keeps_its_dollar_sign if {
	ergo._m_marked_alias("$q") == "$q" with input as {"ergo/names": {"$at": {"names": {}}}}
	ergo._m_marked_alias("$q") == "\u0002q" with input as {"ergo/names": {"$at": {"names": {"q": "/x"}}, "q": 1}}
}

test_message_stripping_a_failed_item_without_assertions_drops_its_messages if {
	ergo._m_strip({"a": 1, "msg": "x", "said": "y"}) == {"a": 1}
}

test_message_of_an_empty_for_list_that_is_missing_names_the_list if {
	check := {"op": "for", "items": [{"path": ["xs"]}]}
	ergo._m_for_empty(check, {}, "absent") == ["xs is missing"]
}

test_message_pairs_sort_by_the_number_of_their_item_and_a_lead_without_a_number_sorts_first if {
	ergo._m_lead_n("item 12 of x") == 12
	ergo._m_lead_n("item x of y") == 0
}

test_a_for_list_that_failed_names_what_it_found_whatever_narrowed_it if {
	ergo._m_for_empty({"items": [{"path": ["xs"]}]}, {"xs": []}, "value") == ["xs is []"]
	ergo._m_for_empty({"items": [{"path": ["xs"], "whose": [{"op": "present", "path": ["v"]}]}]}, {"xs": []}, "value") == ["xs is []"]
	ergo._m_for_empty({"items": [{"path": ["xs"]}]}, {"xs": [1]}, "value") == ["xs is [1]"]
	ergo._m_for_empty({"items": [{"path": ["xs"]}], "assert": "m.v is 1"}, {"xs": "s"}, "value") == ["the check is false"]
}

test_a_ref_that_is_not_a_list_names_the_kind_of_list_the_phrase_needs if {
	ergo._m_leaf_needs({"op": "includes", "values": {"ref": ["$$params", "q"]}}, "s") == "a list"
	ergo._m_leaf_needs({"op": "includes", "values": {"ref": ["$$params", "q"]}}, []) == "a list with at least one value"
	ergo._m_leaf_needs({"op": "matches", "patterns": {"ref": ["$$params", "q"]}}, "s") == "a list"
}
