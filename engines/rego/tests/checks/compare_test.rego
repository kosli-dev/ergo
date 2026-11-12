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
