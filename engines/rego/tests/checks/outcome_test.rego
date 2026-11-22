package ergo_test

import data.ergo
import rego.v1

test_clauses_about_the_members_of_one_list_keep_their_key_order if {
	ps := [ergo._m_clause("item", "member b of xs", "absent", "member b of xs is missing"), ergo._m_clause("item", "member c of xs", "unusable", "member c of xs is 1, which isn't text")]
	ergo._m_walk_outcome({"op": "every", "path": ["xs"]}, {}, {"cause": "unusable", "root_msgs": ps}).message == "member b of xs is missing; member c of xs is 1, which isn't text"
}
