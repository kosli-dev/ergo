package ergo_test

import data.ergo
import rego.v1

test_a_walk_that_starts_at_a_name_with_no_location_still_walks_its_items if {
	start := ergo._walk_start({"path": ["$x", "a"]}, {}) with input as {"ergo/names": {"x": {"a": [1]}}}
	start.v == {"a": [1]}
	start.a == ""
}
