package ergo_test

import data.ergo
import rego.v1

test_first_seen_keeps_the_first_of_each_location_in_the_order_they_came if {
	ergo._first_seen(["b", "a", "b", "c", "a"]) == ["b", "a", "c"]
	ergo._first_seen([]) == []
}
