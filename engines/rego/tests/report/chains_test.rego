package ergo_test

import data.ergo
import rego.v1

test_a_row_that_passes_has_no_failures_and_one_that_fails_has_an_empty_list if {
	ergo._no_items(true) == {}
	ergo._no_items(false) == {"failures": []}
}

test_a_copied_failed_item_list_without_items_stays_empty if {
	f := {"locations": [], "failed_items": []}
	ergo._copied_failed(f, []) == f
}
