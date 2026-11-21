package ergo_test

import data.ergo
import rego.v1

test_a_clause_about_a_member_of_a_walked_list_is_not_a_root if {
	ergo._m_list_item_clause("member a of xs: v is missing", {"xs"})
	ergo._m_list_item_clause(`member "a of b" of xs is 1`, {"xs"})
	not ergo._m_list_item_clause("member a of ys: v is missing", {"xs"})
}
