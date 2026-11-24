package ergo_test

import data.ergo
import rego.v1

test_a_root_said_before_the_items_isnt_counted_as_an_item_in_and_n_more if {
	roots := [ergo._m_clause("root", "$params.l", "unusable", "item 2 of $params.l is 3, which isn't text")]
	items := [
		ergo._m_clause("item", "item 2 of xs", "unusable", "item 2 of xs: v is 5, which isn't text"),
		ergo._m_clause("item", "item 3 of xs", "absent", "item 3 of xs: v is missing"),
		ergo._m_clause("item", "item 4 of xs", "null", "item 4 of xs: v is null"),
	]
	r := {"cause": "unusable", "root_msgs": array.concat(roots, items), "ergo/alone_items": items}
	out := ergo._m_walk_outcome({"op": "every", "path": ["xs"]}, {}, r)
	out.message == concat("; ", [c.text | some c in array.concat(roots, items)])
	out["ergo/own"] == [roots[0].text]
	more := array.concat(items, [ergo._m_clause("item", "item 5 of xs", "null", "item 5 of xs: v is null")])
	ergo._m_walk_outcome({"op": "every", "path": ["xs"]}, {}, {"cause": "unusable", "root_msgs": array.concat(roots, more), "ergo/alone_items": more}).message == concat("; ", array.concat([c.text | some c in array.concat(roots, items)], ["and 1 more"]))
}

test_clauses_about_the_members_of_one_list_keep_their_key_order if {
	ps := [ergo._m_clause("item", "member b of xs", "absent", "member b of xs is missing"), ergo._m_clause("item", "member c of xs", "unusable", "member c of xs is 1, which isn't text")]
	ergo._m_walk_outcome({"op": "every", "path": ["xs"]}, {}, {"cause": "unusable", "root_msgs": ps}).message == "member b of xs is missing; member c of xs is 1, which isn't text"
}
