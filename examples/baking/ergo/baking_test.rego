package baking_ergo_test

import data.baking

report := r if {
	r := baking.report
		with input as {"batches": data.examples.baking.batches}
		with data.baking.subjects as data.examples.baking.ergo.baking.subjects
		with data.baking.requirements as data.examples.baking.ergo.baking.requirements
}

violations := v if {
	v := baking.violations
		with input as {"batches": data.examples.baking.batches}
		with data.baking.subjects as data.examples.baking.ergo.baking.subjects
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
	causes("cake-batch-2026-03-18-003").nut_free == "unusable"
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

workings_table := w if {
	w := baking.workings_table
		with input as {"batches": data.examples.baking.batches}
		with data.baking.subjects as data.examples.baking.ergo.baking.subjects
		with data.baking.requirements as data.examples.baking.ergo.baking.requirements
}

test_workings_table_has_a_row_per_check_for_every_batch if {
	object.keys(workings_table) == {
		"cake-batch-2026-03-18-001",
		"cake-batch-2026-03-18-002",
		"cake-batch-2026-03-18-003",
		"cake-batch-2026-03-18-004",
	}
	every rows in workings_table {
		{row.check | some row in rows} == {"nut_free", "temp_ok", "time_ok"}
	}
}

test_workings_table_shows_the_good_batch_clause_by_clause if {
	workings_table["cake-batch-2026-03-18-001"] == [
		{
			"requirement": "cake_batch",
			"clause": "Must not contain nut allergens",
			"check": "nut_free",
			"inputs": [{"name": "allergens", "value": ["milk", "eggs"]}],
			"expression": `not contains(allergens, "nuts")`,
			"passed": true,
		},
		{
			"requirement": "cake_batch",
			"clause": "Bake temperature 175–200°C inclusive",
			"check": "temp_ok",
			"inputs": [{"name": "bake.temp_c", "value": 180}],
			"expression": "bake.temp_c >= 175 and bake.temp_c <= 200",
			"passed": true,
		},
		{
			"requirement": "cake_batch",
			"clause": "Bake time 25–40 minutes inclusive",
			"check": "time_ok",
			"inputs": [{"name": "bake.minutes", "value": 32}],
			"expression": "bake.minutes >= 25 and bake.minutes <= 40",
			"passed": true,
		},
	]
}

test_workings_table_shows_a_missing_allergen_record_as_null if {
	some row in workings_table["cake-batch-2026-03-18-004"]
	row.check == "nut_free"
	row.inputs == [{"name": "allergens", "value": null}]
	row.passed == false
}

test_workings_table_leaves_out_the_checks_ergo_adds if {
	subjects := {"batch": object.union(
		data.examples.baking.ergo.baking.subjects.batch,
		{"applies_to": {"is_cake": {"op": "present", "path": ["bake"]}}},
	)}
	w := baking.workings_table
		with input as {"batches": data.examples.baking.batches}
		with data.baking.subjects as subjects
		with data.baking.requirements as data.examples.baking.ergo.baking.requirements
	some r in baking.report.results with input as {"batches": data.examples.baking.batches}
		with data.baking.subjects as subjects
		with data.baking.requirements as data.examples.baking.ergo.baking.requirements
	r.check == "$applies"
	every rows in w {
		{row.check | some row in rows} == {"nut_free", "temp_ok", "time_ok"}
	}
}
