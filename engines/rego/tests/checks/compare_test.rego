package ergo_test

import data.ergo
import rego.v1

_low := 1234567890.1209567890

_high := 1234567890.1209567990

_long_causes(checks, rows, params) := {[r.subject.id, r.check, r.cause] | some r in ergo.report({"things": rows}, _sentence_policy(checks), params).results; not startswith(r.check, "$")}

_long_in_both_orders(checks, rows, params, want) if {
	_long_causes(checks, rows, params) == want
	_long_causes(checks, array.reverse(rows), params) == want
}

test_numbers_opa_counts_as_equal_compare_by_every_digit_in_any_order if {
	checks := {
		"eq": "l equals 1234567890.1209567890",
		"ne": "l is not 1234567890.1209567890",
		"lte": "l is at most 1234567890.1209567890",
		"lt": "l is less than 1234567890.1209567990",
		"gte": "l is at least 1234567890.1209567990",
		"gt": "l is more than r",
		"same": "l equals r",
		"between": "l is between 1 and 1234567890.1209567890",
		"outside": "l is not between 1 and 1234567890.1209567890",
	}
	_long_in_both_orders(checks, [{"id": "a", "l": _low, "r": _low}, {"id": "b", "l": _high, "r": _low}], {}, {
		["a", "eq", "satisfied"], ["b", "eq", "value"],
		["a", "ne", "value"], ["b", "ne", "satisfied"],
		["a", "lte", "satisfied"], ["b", "lte", "value"],
		["a", "lt", "satisfied"], ["b", "lt", "value"],
		["a", "gte", "value"], ["b", "gte", "satisfied"],
		["a", "gt", "value"], ["b", "gt", "satisfied"],
		["a", "same", "satisfied"], ["b", "same", "value"],
		["a", "between", "satisfied"], ["b", "between", "value"],
		["a", "outside", "value"], ["b", "outside", "satisfied"],
	})
}

test_numbers_opa_counts_as_equal_compare_by_every_digit_in_a_list_in_any_order if {
	checks := {
		"one_of": "l is one of 1234567890.1209567890, 1",
		"not_one_of": "l is not one of 1234567890.1209567890, 1",
		"in": "l is in $params.lst",
		"not_in": "l is not in $params.lst",
		"contains": "ls contains 1234567890.1209567890",
		"lacks": "ls does not contain 1234567890.1209567890",
		"all": "ls contains all of $params.lst",
		"none": "ls contains none of $params.lst",
		"field": "l is one of ls2",
	}
	_long_in_both_orders(checks, [{"id": "a", "l": _low, "ls": [_low], "ls2": [_low]}, {"id": "b", "l": _high, "ls": [_high], "ls2": [_low]}], {"lst": [_low]}, {
		["a", "one_of", "satisfied"], ["b", "one_of", "value"],
		["a", "not_one_of", "value"], ["b", "not_one_of", "satisfied"],
		["a", "in", "satisfied"], ["b", "in", "value"],
		["a", "not_in", "value"], ["b", "not_in", "satisfied"],
		["a", "contains", "satisfied"], ["b", "contains", "value"],
		["a", "lacks", "value"], ["b", "lacks", "satisfied"],
		["a", "all", "satisfied"], ["b", "all", "value"],
		["a", "none", "value"], ["b", "none", "satisfied"],
		["a", "field", "satisfied"], ["b", "field", "value"],
	})
}

test_within_across_rows_compares_each_row_by_its_own_digits_in_any_order if {
	_long_in_both_orders({"w": "l equals r within 1234567889.6209567890", "nw": "l is not r within 1234567889.6209567890"}, [{"id": "a", "l": _low, "r": 0.5}, {"id": "b", "l": _high, "r": 0.5}], {}, {
		["a", "w", "satisfied"], ["b", "w", "value"],
		["a", "nw", "value"], ["b", "nw", "satisfied"],
	})
}

test_distinct_counts_numbers_opa_counts_as_equal_by_every_digit_in_any_order if {
	_long_in_both_orders({"c": "count of distinct xs is 2"}, [{"id": "a", "xs": [_low, _low, 1234567890.120956789]}, {"id": "b", "xs": [_low, _high, _low]}], {}, {
		["a", "c", "value"], ["b", "c", "satisfied"],
	})
}

test_a_time_written_as_a_number_compares_by_every_digit_in_any_order if {
	_long_in_both_orders({"t": "l is before 1234567890.1209567990"}, [{"id": "a", "l": _low}, {"id": "b", "l": _high}], {}, {
		["a", "t", "satisfied"], ["b", "t", "value"],
	})
}

test_a_message_quotes_each_number_by_its_own_digits_in_any_order if {
	rows := [{"id": "a", "l": _low, "r": _low}, {"id": "b", "l": _high, "r": _low}]
	want := {
		["a", "r is 1234567890.120956789, and l is 1234567890.120956789"],
		["b", "r is 1234567890.120956789, and l is 1234567890.120956799"],
	}
	every doc in [rows, array.reverse(rows)] {
		{[r.subject.id, r.message] | some r in ergo.report({"things": doc}, _sentence_policy({"c": "r is less than l"}), {}).results; r.check == "c"} == want
	}
}

test_order_trusts_opa_when_it_tells_two_numbers_apart if {
	ergo._order(1, 2, "1", "2") == -1
	ergo._order(2, 1, "2", "1") == 1
	ergo._order(1, 1.0, "1", "1.0") == 0
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
