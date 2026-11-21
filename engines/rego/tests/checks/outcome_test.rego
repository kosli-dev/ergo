package ergo_test

import data.ergo
import rego.v1

test_a_root_said_before_the_items_isnt_counted_as_an_item_in_and_n_more if {
	roots := ["item 2 of $params.l is 3, which isn't text"]
	items := ["item 2 of xs: v is 5, which isn't text", "item 3 of xs: v is missing", "item 4 of xs: v is null"]
	r := {"cause": "unusable", "root_msgs": array.concat(roots, items), "ergo/alone_items": items}
	out := ergo._m_walk_outcome({"op": "every", "path": ["xs"]}, {}, r)
	out.message == concat("; ", array.concat(roots, items))
	out["ergo/own"] == roots
	more := array.concat(items, ["item 5 of xs: v is null"])
	ergo._m_walk_outcome({"op": "every", "path": ["xs"]}, {}, {"cause": "unusable", "root_msgs": array.concat(roots, more), "ergo/alone_items": more}).message == concat("; ", array.concat(roots, array.concat(array.slice(items, 0, 3), ["and 1 more"])))
}

test_clauses_about_the_members_of_one_list_keep_their_key_order if {
	ps := ["member b of xs is missing", "member c of xs is 1, which isn't text"]
	ergo._walk_roots_sorted(ps, {"op": "every", "path": ["xs"]}) == ps
}
