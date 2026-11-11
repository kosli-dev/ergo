package ergo_test

import data.ergo
import rego.v1

test_a_from_that_cannot_be_printed_is_invalid_even_when_nothing_flagged_it if {
	every def in [{"from": "ds", "applies_to": {}}, {"from": "ds", "of": "b"}, {"from": 1}, {"of": 1}] {
		ergo._subject_from_text("d", def, set()) == "<invalid from>" with data.ergo_resolved as {"d": {"problems": set()}} with data.ergo_subjects as {"d": def, "b": {}}
	}
}
