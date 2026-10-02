package baking_ergo_test

import data.baking

report := r if {
	r := baking.report
		with input as {"batches": data.examples.baking.batches}
		with data.baking.requirements as data.examples.baking.ergo.baking.requirements
}

violations := v if {
	v := baking.violations
		with input as {"batches": data.examples.baking.batches}
		with data.baking.requirements as data.examples.baking.ergo.baking.requirements
}

causes(id) := {r.check: r.cause |
	some r in report.results
	r.subject.id == id
}

test_the_batches_are_not_compliant if {
	report.compliant == false
}

test_good_batch_passes_every_check if {
	causes("cake-batch-2026-03-18-001") == {"nut_free": "satisfied", "temp_ok": "satisfied", "time_ok": "satisfied"}
}

test_batch_with_nuts_in_its_allergens_fails_on_the_value if {
	causes("cake-batch-2026-03-18-002").nut_free == "value"
}

test_batch_with_nuts_as_a_string_fails_instead_of_passing if {
	causes("cake-batch-2026-03-18-003").nut_free == "value"
}

test_batch_without_allergens_fails_as_absent if {
	causes("cake-batch-2026-03-18-004").nut_free == "absent"
}

test_only_the_nut_check_is_violated if {
	{[v.subject.id, v.check] | some v in violations} == {
		["cake-batch-2026-03-18-002", "nut_free"],
		["cake-batch-2026-03-18-003", "nut_free"],
		["cake-batch-2026-03-18-004", "nut_free"],
	}
}
