package baking_test

import data.baking

batches_input := {"batches": data.examples.baking.batches}

result(id) := r if {
	r := baking.batches[id] with input as batches_input
}

test_good_batch_is_compliant if {
	result("cake-batch-2026-03-18-001") == {"compliant": true, "nut_free": true, "temp_ok": true, "time_ok": true}
}

test_batch_with_nuts_in_its_allergens_is_not_compliant if {
	result("cake-batch-2026-03-18-002") == {"compliant": false, "nut_free": false, "temp_ok": true, "time_ok": true}
}

test_batch_with_nuts_as_a_string_passes_plain_rego if {
	result("cake-batch-2026-03-18-003") == {"compliant": true, "nut_free": true, "temp_ok": true, "time_ok": true}
}

test_batch_without_allergens_looks_the_same_as_a_batch_with_nuts if {
	result("cake-batch-2026-03-18-004") == result("cake-batch-2026-03-18-002")
}

test_batch_baked_too_hot_is_not_compliant if {
	r := baking.batches.hot with input as {"batches": [{"id": "hot", "allergens": [], "bake": {"minutes": 32, "temp_c": 220}}]}
	r == {"compliant": false, "nut_free": true, "temp_ok": false, "time_ok": true}
}

test_batch_baked_too_long_is_not_compliant if {
	r := baking.batches.long with input as {"batches": [{"id": "long", "allergens": [], "bake": {"minutes": 50, "temp_c": 180}}]}
	r == {"compliant": false, "nut_free": true, "temp_ok": true, "time_ok": false}
}
