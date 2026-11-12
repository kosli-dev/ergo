package ergo_test

import data.ergo
import rego.v1

_lower := 1234567890.1209567790

_low := 1234567890.1209567890

_high := 1234567890.1209567990

_long_causes(checks, rows, params) := {[r.subject.id, r.check, r.cause] | some r in ergo.report({"things": rows}, _sentence_policy(checks), params).results; not startswith(r.check, "$")}

_long_in_both_orders(checks, rows, params, want) if {
	_long_causes(checks, rows, params) == want
	_long_causes(checks, array.reverse(rows), params) == want
}

_long_messages(checks, rows, params) := {[r.subject.id, r.check, r.message] | some r in ergo.report({"things": rows}, _sentence_policy(checks), params).results; not startswith(r.check, "$"); r.cause != "satisfied"}

test_numbers_opa_counts_as_equal_compare_by_every_digit_in_any_order if {
	checks := {
		"eq": "l equals $params.low",
		"ne": "l is not $params.low",
		"lte": "l is at most $params.low",
		"lt": "l is less than $params.high",
		"gte": "l is at least $params.high",
		"gt": "l is more than r",
		"same": "l equals r",
		"before": "l is before $params.high",
	}
	_long_in_both_orders(checks, [{"id": "a", "l": _low, "r": _low}, {"id": "b", "l": _high, "r": _low}], {"low": _low, "high": _high}, {
		["a", "eq", "satisfied"], ["b", "eq", "value"],
		["a", "ne", "value"], ["b", "ne", "satisfied"],
		["a", "lte", "satisfied"], ["b", "lte", "value"],
		["a", "lt", "satisfied"], ["b", "lt", "value"],
		["a", "gte", "value"], ["b", "gte", "satisfied"],
		["a", "gt", "value"], ["b", "gt", "satisfied"],
		["a", "same", "satisfied"], ["b", "same", "value"],
		["a", "before", "satisfied"], ["b", "before", "value"],
	})
}

test_a_policy_number_compares_with_a_longer_input_number_by_every_digit if {
	checks := {
		"eq": "l equals 5040424028.5118",
		"ne": "l is not 5040424028.5118",
		"gte": "l is at least 5040424028.51180",
		"lt": "l is less than 5040424028.5118",
		"between": "l is between 5040424028.5118 and 6000000000",
		"outside": "l is not between 5040424028.5118 and 6000000000",
		"one_of": "l is one of 5040424028.5118, 1",
	}
	_long_in_both_orders(checks, [{"id": "a", "l": 5040424028.51180}, {"id": "b", "l": 5040424028.5117999990}], {}, {
		["a", "eq", "satisfied"], ["b", "eq", "value"],
		["a", "ne", "value"], ["b", "ne", "satisfied"],
		["a", "gte", "satisfied"], ["b", "gte", "value"],
		["a", "lt", "value"], ["b", "lt", "satisfied"],
		["a", "between", "satisfied"], ["b", "between", "value"],
		["a", "outside", "value"], ["b", "outside", "satisfied"],
		["a", "one_of", "satisfied"], ["b", "one_of", "value"],
	})
}

test_two_checks_on_one_row_compare_their_own_numbers if {
	_long_in_both_orders({"l": "l is at most $params.low", "r": "r is at most $params.low"}, [{"id": "a", "l": _low, "r": _high}, {"id": "b", "l": _high, "r": _low}], {"low": _low}, {
		["a", "l", "satisfied"], ["a", "r", "value"],
		["b", "l", "value"], ["b", "r", "satisfied"],
	})
}

test_numbers_opa_counts_as_equal_compare_by_every_digit_in_a_list_in_any_order if {
	checks := {
		"in": "l is in $params.lst",
		"not_in": "l is not in $params.lst",
		"contains": "ls contains $params.low",
		"lacks": "ls does not contain $params.low",
		"all": "ls contains all of $params.lst",
		"none": "ls contains none of $params.lst",
		"field": "l is one of ls2",
		"short": "ls2 contains l",
	}
	_long_in_both_orders(checks, [{"id": "a", "l": _low, "ls": [_low], "ls2": [_low]}, {"id": "b", "l": _high, "ls": [_high], "ls2": [_low]}], {"lst": [_low], "low": _low}, {
		["a", "in", "satisfied"], ["b", "in", "value"],
		["a", "not_in", "value"], ["b", "not_in", "satisfied"],
		["a", "contains", "satisfied"], ["b", "contains", "value"],
		["a", "lacks", "value"], ["b", "lacks", "satisfied"],
		["a", "all", "satisfied"], ["b", "all", "value"],
		["a", "none", "value"], ["b", "none", "satisfied"],
		["a", "field", "satisfied"], ["b", "field", "value"],
		["a", "short", "satisfied"], ["b", "short", "value"],
	})
}

test_a_list_of_params_compares_each_of_its_numbers_by_every_digit if {
	_long_in_both_orders({"all": "ls contains all of $params.lst", "some": "ls contains some of $params.lst"}, [{"id": "a", "ls": [_low]}, {"id": "b", "ls": [_low, _high]}], {"lst": [_low, _high]}, {
		["a", "all", "value"], ["b", "all", "satisfied"],
		["a", "some", "satisfied"], ["b", "some", "satisfied"],
	})
}

test_within_across_rows_compares_each_row_by_its_own_digits_in_any_order if {
	_long_in_both_orders({"w": "l equals r within 1", "nw": "l is not r within 1"}, [{"id": "a", "l": _low, "r": 1234567889.1209567890}, {"id": "b", "l": _high, "r": 1234567889.1209567890}], {}, {
		["a", "w", "satisfied"], ["b", "w", "value"],
		["a", "nw", "value"], ["b", "nw", "satisfied"],
	})
}

test_distinct_counts_numbers_opa_counts_as_equal_by_every_digit_in_any_order if {
	_long_in_both_orders({"c": "count of distinct xs is 2"}, [{"id": "a", "xs": [_low, _low, 1234567890.120956789]}, {"id": "b", "xs": [_low, _high, _low]}], {}, {
		["a", "c", "value"], ["b", "c", "satisfied"],
	})
}

test_distinct_counts_numbers_equal_in_value_once if {
	_long_in_both_orders({"c": "count of distinct xs is 4"}, [{"id": "a", "xs": [1, 1.0, 1e0, 100, 1e2, -0, 0, _low, 1234567890.120956789]}], {}, {["a", "c", "satisfied"]})
}

test_every_item_compares_by_its_own_digits_in_any_order if {
	checks := {"every": "every xs is at most r", "some": "some xs is more than r"}
	_long_in_both_orders(checks, [{"id": "a", "xs": [_high, _low], "r": _low}, {"id": "b", "xs": [_low], "r": _low}, {"id": "c", "xs": [_high], "r": _low}], {}, {
		["a", "every", "value"], ["a", "some", "satisfied"],
		["b", "every", "satisfied"], ["b", "some", "value"],
		["c", "every", "value"], ["c", "some", "satisfied"],
	})
}

test_a_message_quotes_each_number_by_its_own_digits_in_any_order if {
	rows := [{"id": "a", "l": _high, "r": _low}, {"id": "b", "l": _low, "r": _lower}]
	want := {
		["a", "c", "l is 1234567890.120956799, and r is 1234567890.120956789"],
		["b", "c", "l is 1234567890.120956789, and r is 1234567890.120956779"],
		["b", "p", "l is 1234567890.120956789, and $params.lst is [1234567890.120956789]"],
	}
	every doc in [rows, array.reverse(rows)] {
		_long_messages({"c": "l is at most r", "p": "l is not in $params.lst"}, doc, {"lst": [_low]}) == want
	}
}

test_cmp_trusts_opa_when_it_tells_two_numbers_apart if {
	ergo._cmp("lt", 1, 2, {}, {})
	ergo._cmp("gt", 2, 1, {}, {})
	ergo._cmp("eq", 1, 1.0, {}, {})
	ergo._cmp("gte", 1e2, 100, {}, {})
	not ergo._cmp("ne", -0, 0, {}, {})
}

test_equal_dates_are_on_or_before_and_on_or_after_each_other if {
	checks := {"lte": "t is on or before u", "gte": "t is on or after u"}
	_long_causes(checks, [{"id": "a", "t": "2024-01-01", "u": "2024-01-01"}], {}) == {["a", "lte", "satisfied"], ["a", "gte", "satisfied"]}
	ergo._cmp("lte", "2024-01-01", "2024-01-01", {}, {})
	ergo._cmp("gte", "2024-01-01", "2024-01-01", {}, {})
}

test_text_order_reads_every_digit if {
	ergo._text_order("1234567890.1209567890", "1234567890.1209567990") == -1
	ergo._text_order("1234567890.1209567990", "1234567890.1209567890") == 1
	ergo._text_order("-1234567890.1209567890", "-1234567890.1209567990") == 1
	ergo._text_order("12345678901234567890e-10", "1234567890.1234567890") == 0
	ergo._text_order("1e2", "100.000") == 0
	ergo._text_order("-0", "0.0") == 0
	ergo._text_order("0", "1e-400") == -1
	ergo._text_order("1e-400", "0") == 1
	ergo._text_order("99", "100") == -1
	ergo._text_order("-1", "1") == -1
	ergo._text_order("1", "-1") == 1
}

_well_formed_message(checks) := [r.message | some r in ergo.report({"things": [{"id": "a", "l": 1}]}, _sentence_policy(checks), {}).results; r.check == "$well_formed"; r.cause != "satisfied"]

test_a_policy_number_with_more_than_15_significant_digits_is_written_wrong if {
	_well_formed_message({"c": "l equals 1234567890.1209567890"}) == ["checks.c: number with more than 15 significant digits: 1234567890.1209567890"]
	_well_formed_message({"c": "l is at most 1234567890123456"}) == ["checks.c: number with more than 15 significant digits: 1234567890123456"]
	_well_formed_message({"c": "l is at most 12345678901234567890"}) == ["checks.c: number with more than 15 significant digits: 12345678901234567890"]
	_well_formed_message({"c": "l equals 1 within 0.1234567890123456"}) == ["checks.c: number with more than 15 significant digits: 0.1234567890123456"]
	_well_formed_message({"c": "l is one of 1, 1234567890.1209567890"}) == ["checks.c: number with more than 15 significant digits: 1234567890.1209567890"]
	_well_formed_message({"c": "l is between 1234567890.1209567890 and 2e10"}) == ["checks.c: number with more than 15 significant digits: 1234567890.1209567890"]
}

test_significant_digits_are_counted_on_the_value if {
	_well_formed_message({"c": "l is at most 123456789012345"}) == []
	_well_formed_message({"c": "l is at most 1.50000000000000000000"}) == []
	_well_formed_message({"c": "l is at most 1e20"}) == []
	_well_formed_message({"c": "l is at most 0.000000000000000000001"}) == []
	_well_formed_message({"c": "l is at most 1234567890123456000000"}) == ["checks.c: number with more than 15 significant digits: 1234567890123456000000"]
}

test_a_long_number_in_the_meta_of_a_check_is_written_wrong if {
	_well_formed_message({"c": {"assert": "l exists", "meta": {"n": [1234567890.1209567890]}}}) == ["checks.c: number with more than 15 significant digits"]
	_well_formed_message({"c": {"assert": "l exists", "meta": {"n": 1e400, "m": 1234567890.1209567890}}}) == ["checks.c: number out of range; checks.c: number with more than 15 significant digits"]
	_well_formed_message({"c": {"assert": "l exists", "meta": {"n": 123456789012345}}}) == []
}

test_a_list_position_with_more_than_15_digits_is_not_a_policy_number if {
	every subj in [
		{"from": "things[9007199254740991]", "identified_by": "id"},
		{"from": "things[1234567890123456]", "identified_by": "id"},
		{"from": "things", "identified_by": "ids[9007199254740991]"},
		{"from": "things", "identified_by": "ids[1234567890123456]"},
	] {
		policy := object.union(_sentence_policy({"c": "l exists"}), {"subjects": {"thing": subj}})
		[r.cause | some r in ergo.report({"things": [{"id": "a", "l": 1}]}, policy, {}).results; r.check == "$well_formed"] == ["satisfied"]
	}
	_well_formed_message({"c": "l[1234567890123456] exists"}) == []
	_well_formed_message({"c": "item 9007199254740991 of l exists"}) == []
	_well_formed_message({"c": "m named by ids[1234567890123456] is 1"}) == []
	_well_formed_message({"c": {"for": "every kids[1234567890123456] as k", "assert": "k.n is 1"}}) == []
}

test_a_number_out_of_range_is_named_before_its_digits if {
	_well_formed_message({"c": "l is at least 1.2345678901234567e400"}) == ["checks.c: number out of range: 1.2345678901234567e400"]
}

test_a_long_number_outside_a_check_is_written_wrong if {
	policy := object.union(_sentence_policy({"c": "l exists"}), {"requirements": {"s": {"subject": "thing", "min_subjects": 1.0000000000000000001, "meta": {"n": 1234567890.1209567890}, "checks": {"c": "l exists"}}}})
	[r.message | some r in ergo.report({"things": [{"id": "a", "l": 1}]}, policy, {}).results; r.check == "$well_formed"] == ["meta: number with more than 15 significant digits; min_subjects: number with more than 15 significant digits"]
	from := object.union(_sentence_policy({"c": "l exists"}), {"subjects": {"thing": {"from": "things whose l is 1234567890.1209567890", "identified_by": "id"}}})
	[r.message | some r in ergo.report({"things": [{"id": "a", "l": 1}]}, from, {}).results; r.check == "$well_formed"] == ["subjects.thing.from: number with more than 15 significant digits: 1234567890.1209567890"]
}

test_objects_in_a_list_compare_by_their_own_digits_in_any_order if {
	checks := {
		"every": "every xs.v is at most $params.r",
		"some": "some xs.v is more than $params.r",
		"count": "count of xs whose v is more than $params.r equals 1",
		"distinct_v": "count of distinct xs.v equals 2",
		"distinct_xs": "count of distinct xs equals 2",
	}
	rows := [{"id": "a", "xs": [{"v": _low}, {"v": _high}]}, {"id": "b", "xs": [{"v": _high}, {"v": _low}]}]
	_long_in_both_orders(checks, rows, {"r": _low}, {
		["a", "every", "value"], ["a", "some", "satisfied"], ["a", "count", "satisfied"], ["a", "distinct_v", "satisfied"], ["a", "distinct_xs", "satisfied"],
		["b", "every", "value"], ["b", "some", "satisfied"], ["b", "count", "satisfied"], ["b", "distinct_v", "satisfied"], ["b", "distinct_xs", "satisfied"],
	})
}

test_an_item_message_quotes_the_digits_of_its_own_item if {
	_long_messages({"c": "every xs.v is at most $params.r"}, [{"id": "a", "xs": [{"v": _low}, {"v": _high}]}], {"r": _low}) == {["a", "c", "item 2 of xs: v is 1234567890.120956799, and $params.r is 1234567890.120956789"]}
}

_rows_by_digits(rows, ident) := {[json.marshal(r.subject.id), r.check, r.cause] |
	policy := {"ergo_spec": ergo._spec, "subjects": {"thing": ident}, "requirements": {"s": {"subject": "thing", "checks": {"c": "l is at most r"}}}}
	some r in ergo.report({"things": rows}, policy, {}).results
	r.check in {"c", "$unique_ids"}
}

test_subjects_that_differ_only_past_15_digits_keep_their_own_answers if {
	_rows_by_digits([{"l": _high, "r": _low}, {"l": _low, "r": _low}], {"from": "things"}) == {
		[`{"l":1234567890.120956799,"r":1234567890.120956789}`, "c", "value"],
		[`{"l":1234567890.120956789,"r":1234567890.120956789}`, "c", "satisfied"],
		["null", "$unique_ids", "satisfied"],
	}
	_rows_by_digits([{"l": 2234567890.1209567890, "r": 2234567890.1209567890}, {"l": 2234567890.1209567990, "r": 2234567890.1209567890}], {"from": "things"}) == {
		[`{"l":2234567890.120956799,"r":2234567890.120956789}`, "c", "value"],
		[`{"l":2234567890.120956789,"r":2234567890.120956789}`, "c", "satisfied"],
		["null", "$unique_ids", "satisfied"],
	}
}

test_ids_that_differ_only_past_15_digits_are_not_repeated if {
	_rows_by_digits([{"id": _high, "l": _high, "r": _low}, {"id": _low, "l": _low, "r": _low}], {"from": "things", "identified_by": "id"}) == {
		["1234567890.120956799", "c", "value"],
		["1234567890.120956789", "c", "satisfied"],
		["null", "$unique_ids", "satisfied"],
	}
	_rows_by_digits([{"id": 2234567890.1209567890, "l": 1, "r": 2}, {"id": 2234567890.1209567890, "l": 1, "r": 2}], {"from": "things", "identified_by": "id"}) == {
		["2234567890.120956789", "c", "satisfied"],
		["null", "$unique_ids", "value"],
	}
}

test_objects_and_lists_compare_by_every_digit_in_any_order if {
	checks := {
		"o_equals_p": "o equals p",
		"o_is_not_p": "o is not p",
		"ls_equals_ms": "ls equals ms",
		"o_equals_param": "o equals $params.o",
		"lls_contains_m": "lls contains m",
		"m_is_in_lls": "m is in lls",
		"same": "o equals q",
	}
	rows := [
		{"id": "a", "o": {"v": _low}, "p": {"v": _high}, "q": {"v": 1234567890.12095678900}, "ls": [_low], "ms": [_high], "m": [_high], "lls": [[_low]]},
		{"id": "b", "o": {"v": _high}, "p": {"v": _low}, "q": {"v": _high}, "ls": [_high], "ms": [_low], "m": [_low], "lls": [[_high]]},
	]
	_long_in_both_orders(checks, rows, {"o": {"v": _high}}, {
		["a", "o_equals_p", "value"], ["a", "o_is_not_p", "satisfied"], ["a", "ls_equals_ms", "value"], ["a", "o_equals_param", "value"], ["a", "lls_contains_m", "value"], ["a", "m_is_in_lls", "value"], ["a", "same", "satisfied"],
		["b", "o_equals_p", "value"], ["b", "o_is_not_p", "satisfied"], ["b", "ls_equals_ms", "value"], ["b", "o_equals_param", "satisfied"], ["b", "lls_contains_m", "value"], ["b", "m_is_in_lls", "value"], ["b", "same", "satisfied"],
	})
}

test_a_message_quotes_each_object_by_its_own_digits if {
	_long_messages({"c": "o equals p"}, [{"id": "a", "o": {"v": _low}, "p": {"v": _high}}], {}) == {["a", "c", `o is {"v": 1234567890.120956789}, and p is {"v": 1234567890.120956799}`]}
}

test_for_lines_keep_and_sort_items_by_every_digit_in_any_order if {
	checks := {
		"distinct": {"for": "every distinct ws as w", "assert": "w.z is at most $params.r"},
		"first": {"for": "first of ys sorted by z as y", "assert": "y.k is \"low\""},
	}
	rows := [
		{"id": "a", "ys": [{"z": _low, "k": "low"}, {"z": _high, "k": "high"}], "ws": [{"z": _low}, {"z": _high}]},
		{"id": "b", "ys": [{"z": _high, "k": "high"}, {"z": _low, "k": "low"}], "ws": [{"z": _high}, {"z": _low}]},
	]
	_long_in_both_orders(checks, rows, {"r": _low}, {
		["a", "distinct", "value"], ["a", "first", "satisfied"],
		["b", "distinct", "value"], ["b", "first", "satisfied"],
	})
}
