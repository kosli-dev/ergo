package ergo_test

import data.ergo
import rego.v1

test_a_from_condition_that_cannot_be_turned_back_into_text_is_written_wrong_and_never_dropped if {
	read := ergo._s_from_read("x", {"path": {"steps": ["xs"]}, "where": [{"nonsense": true, "phrase": {"op": "is", "value": 1}}]}, {"x": {"from": "xs"}}, {"parts": {}, "descend": {}, "narrow": {}})
	"whose: a condition can't be read" in read.problems
}
