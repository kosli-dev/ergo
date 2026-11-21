package ergo_test

import data.ergo
import rego.v1

test_clauses_about_the_members_of_one_list_keep_their_key_order if {
	ps := ["member b of xs is missing", "member c of xs is 1, which isn't text"]
	ergo._walk_roots_sorted(ps, {"op": "every", "path": ["xs"]}) == ps
}
