package ergo_test

import data.ergo
import rego.v1

test_a_clause_holds_its_kind_name_cause_text_and_what_it_says if {
	ergo._m_clause("root", "$params.min", "unusable", `$params.min is "s", which isn't a number`) == {
		"kind": "root",
		"name": "$params.min",
		"cause": "unusable",
		"text": `$params.min is "s", which isn't a number`,
		"said": [],
	}
	ergo._m_item_clause("item 2 of xs", "absent", [ergo._m_clause("root", "v", "absent", "v is missing")]) == {
		"kind": "item",
		"name": "item 2 of xs",
		"cause": "absent",
		"text": "",
		"said": [{"kind": "root", "name": "v", "cause": "absent", "text": "v is missing", "said": []}],
	}
	ergo._m_clause_more(2) == {"kind": "more", "count": 2, "name": "", "cause": "value", "text": "", "said": []}
}

_clause_root(name, cause, text) := ergo._m_clause("root", name, cause, text)

_clause_missing(name) := _clause_root(name, "absent", concat("", [name, " is missing"]))

_clause_null(name) := _clause_root(name, "null", concat("", [name, " is null"]))

_clause_unread(name, cause, text) := ergo._m_clause("item", name, cause, text)

_clause_item(name, cause, said) := ergo._m_item_clause(name, cause, said)

test_roots_lists_and_and_n_more_are_joined_with_a_semicolon if {
	ergo._m_clauses_text([
		_clause_root("$params", "not_an_object", "$params is 3, which isn't an object"),
		ergo._m_clause("list", "es", "absent", "es is missing"),
		ergo._m_clause_more(2),
	]) == "$params is 3, which isn't an object; es is missing; and 2 more"
}

test_an_item_says_its_clauses_after_its_name_joined_with_and if {
	ergo._m_clauses_text([
		_clause_item("item 1 of xs", "absent", [_clause_missing("x.v"), _clause_missing("x.w")]),
		_clause_unread("item 2 of xs", "unusable", "item 2 of xs is null, which isn't an object"),
	]) == "item 1 of xs: x.v is missing, and x.w is missing; item 2 of xs is null, which isn't an object"
}

test_a_nested_item_says_each_leaf_after_every_name_above_it if {
	ergo._m_clauses_text([_clause_item("item 1 of ws", "unusable", [
		_clause_missing("w.a"),
		_clause_unread("item 2 of items", "unusable", "item 2 of items is null, which isn't an object"),
		_clause_missing("cov.x"),
		_clause_null("cov.y"),
		_clause_item("item 3 of ys", "absent", [_clause_item("item 1 of y.zs", "absent", [_clause_missing("n")])]),
	])]) == concat("; ", [
		"item 1 of ws: w.a is missing",
		"item 1 of ws: item 2 of items is null, which isn't an object",
		"item 1 of ws: cov.x is missing, and cov.y is null",
		"item 1 of ws: item 3 of ys: item 1 of y.zs: n is missing",
	])
}

test_roots_come_worst_cause_first_then_by_name_before_the_lists_and_the_items if {
	ergo._m_clauses_shown([
		_clause_item("item 1 of xs", "absent", [_clause_missing("v")]),
		ergo._m_clause("list", "xs", "value", "xs is []"),
		_clause_root("za", "null", "za is null"),
		_clause_root("zc", "unusable", `zc is "s", which isn't a number`),
		_clause_missing("zd"),
		_clause_root("zb", "unusable", `zb is "s", which isn't a number`),
		_clause_root("ze", "not_an_object", "ze is 3, which isn't an object"),
		_clause_root("zf", "ambiguous", "zf is ambiguous"),
		_clause_root("zg", "value", "zg is 1"),
	]) == [
		_clause_root("ze", "not_an_object", "ze is 3, which isn't an object"),
		_clause_root("zf", "ambiguous", "zf is ambiguous"),
		_clause_root("zb", "unusable", `zb is "s", which isn't a number`),
		_clause_root("zc", "unusable", `zc is "s", which isn't a number`),
		_clause_missing("zd"),
		_clause_root("za", "null", "za is null"),
		_clause_root("zg", "value", "zg is 1"),
		ergo._m_clause("list", "xs", "value", "xs is []"),
		_clause_item("item 1 of xs", "absent", [_clause_missing("v")]),
	]
}

_clause_items_of(list, from, to, said) := [_clause_item(concat("", ["item ", format_int(n, 10), " of ", list]), "absent", said) | some n in numbers.range(from, to)]

test_and_n_more_comes_after_the_roots_and_the_lists_in_a_count if {
	ergo._m_clauses_text(ergo._m_clauses_shown(array.concat(
		_clause_items_of("xs", 1, 5, [_clause_missing("v")]),
		[_clause_root("$params.min", "unusable", `$params.min is "s", which isn't a number`)],
	))) == concat("; ", [
		`$params.min is "s", which isn't a number`,
		"item 1 of xs: v is missing",
		"item 2 of xs: v is missing",
		"item 3 of xs: v is missing",
		"and 2 more",
	])
}

test_the_cap_counts_leaf_items_not_outer_items if {
	ergo._m_clauses_text(ergo._m_clauses_shown(_clause_items_of("cs", 1, 2, _clause_items_of("rs", 1, 2, [_clause_missing("ok")])))) == concat("; ", [
		"item 1 of cs: item 1 of rs: ok is missing",
		"item 1 of cs: item 2 of rs: ok is missing",
		"item 2 of cs: item 1 of rs: ok is missing",
		"and 1 more",
	])
}

test_an_items_own_part_beside_the_items_under_it_isnt_counted if {
	ergo._m_clauses_text(ergo._m_clauses_shown([_clause_item(concat("", ["item ", format_int(n, 10), " of cs"]), "value", [
		_clause_item(concat("", ["item ", format_int(min({n, 2}), 10), " of c.reviews"]), "value", [_clause_root("ok", "value", "ok is false")]),
		_clause_root("c.a", "value", "c.a is 2"),
	]) |
		some n in numbers.range(1, 5)
	])) == concat("; ", [
		"item 1 of cs: item 1 of c.reviews: ok is false",
		"item 1 of cs: c.a is 2",
		"item 2 of cs: item 2 of c.reviews: ok is false",
		"item 2 of cs: c.a is 2",
		"item 3 of cs: item 2 of c.reviews: ok is false",
		"item 3 of cs: c.a is 2",
		"and 2 more",
	])
}

test_a_clause_given_twice_is_shown_once if {
	ergo._m_clauses_shown([
		_clause_missing("$params.k"),
		_clause_item("item 1 of es", "absent", [_clause_missing("m")]),
		ergo._m_clause("list", "es", "value", "es is []"),
		_clause_missing("$params.k"),
		_clause_item("item 2 of es", "absent", [_clause_missing("m")]),
		ergo._m_clause("list", "es", "value", "es is []"),
		_clause_item("item 1 of es", "absent", [_clause_missing("m")]),
	]) == [
		_clause_missing("$params.k"),
		ergo._m_clause("list", "es", "value", "es is []"),
		_clause_item("item 1 of es", "absent", [_clause_missing("m")]),
		_clause_item("item 2 of es", "absent", [_clause_missing("m")]),
	]
}

_clause_parity_rows := [
	[
		[
			_clause_root("$params.min", "unusable", `$params.min is "s", which isn't a number`),
			_clause_item("item 2 of xs", "absent", [_clause_missing("v")]),
		],
		[`$params.min is "s", which isn't a number`, "item 2 of xs: v is missing"],
		{"xs"},
	],
	[
		_clause_items_of("cs", 1, 2, _clause_items_of("rs", 1, 2, [_clause_missing("ok")])),
		[
			"item 1 of cs: item 1 of rs: ok is missing",
			"item 1 of cs: item 2 of rs: ok is missing",
			"item 2 of cs: item 1 of rs: ok is missing",
			"item 2 of cs: item 2 of rs: ok is missing",
		],
		{"cs"},
	],
	[
		_clause_items_of("xs", 1, 5, [_clause_missing("x.v"), _clause_missing("x.w")]),
		[
			"item 1 of xs: x.v is missing, and x.w is missing",
			"item 2 of xs: x.v is missing, and x.w is missing",
			"item 3 of xs: x.v is missing, and x.w is missing",
			"item 4 of xs: x.v is missing, and x.w is missing",
			"item 5 of xs: x.v is missing, and x.w is missing",
		],
		{"xs"},
	],
	[
		[
			_clause_item("item 1 of xs", "absent", [_clause_missing("w")]),
			_clause_root("pr.l", "unusable", `pr.l is "s", which isn't a list`),
			_clause_null("$params.l"),
		],
		["item 1 of xs: w is missing", `pr.l is "s", which isn't a list`, "$params.l is null"],
		{"xs"},
	],
	[
		[
			_clause_unread("item 2 of $params.envs", "unusable", "item 2 of $params.envs is null, which isn't an object"),
			_clause_item("item 3 of $params.envs", "absent", [_clause_missing("name")]),
			_clause_unread("item 4 of $params.envs", "unusable", "item 4 of $params.envs is 3, which isn't an object"),
			_clause_item("item 5 of $params.envs", "absent", [_clause_missing("name")]),
			_clause_item("item 6 of $params.envs", "absent", [_clause_missing("name")]),
		],
		[
			"item 2 of $params.envs is null, which isn't an object",
			"item 3 of $params.envs: name is missing",
			"item 4 of $params.envs is 3, which isn't an object",
			"item 5 of $params.envs: name is missing",
			"item 6 of $params.envs: name is missing",
		],
		{"$params.envs"},
	],
	[
		[
			ergo._m_clause("list", "es", "absent", "es is missing"),
			_clause_root("$params", "not_an_object", "$params is 3, which isn't an object"),
		],
		["es is missing", "$params is 3, which isn't an object"],
		{"es"},
	],
	[
		array.concat([_clause_missing("$params.k"), _clause_missing("$params.k")], _clause_items_of("es", 1, 5, [_clause_missing("m")])),
		[
			"$params.k is missing",
			"$params.k is missing",
			"item 1 of es: m is missing",
			"item 2 of es: m is missing",
			"item 3 of es: m is missing",
			"item 4 of es: m is missing",
			"item 5 of es: m is missing",
		],
		{"es"},
	],
	[
		[_clause_root("x", "value", `x is "a; y is 1, which isn't b"`)],
		[`x is "a; y is 1, which isn't b"`],
		set(),
	],
	[
		[_clause_null("x"), _clause_missing("zz"), _clause_root("zb", "unusable", `zb is "s", which isn't a list or an object`)],
		["x is null", "zz is missing", `zb is "s", which isn't a list or an object`],
		set(),
	],
	[
		[_clause_item("item 1 of xs", "value", [_clause_unread("item 1 of x.ns", "value", "item 1 of x.ns is 2"), _clause_unread("item 2 of x.ns", "value", "item 2 of x.ns is 3"), _clause_unread("item 3 of x.ns", "value", "item 3 of x.ns is 4"), _clause_unread("item 4 of x.ns", "value", "item 4 of x.ns is 5")])],
		["item 1 of xs: item 1 of x.ns is 2", "item 1 of xs: item 2 of x.ns is 3", "item 1 of xs: item 3 of x.ns is 4", "item 1 of xs: item 4 of x.ns is 5"],
		{"xs"},
	],
]

test_shown_and_text_give_what_roots_then_lists_and_joined_give if {
	count(_clause_parity_rows) == 10
	every row in _clause_parity_rows {
		ergo._m_clauses_text(ergo._m_clauses_shown(row[0])) == ergo._m_joined(ergo._roots_then_lists(row[1], row[2]))
	}
}

test_no_clauses_give_no_text if {
	ergo._m_clauses_shown([]) == []
	ergo._m_clauses_text(ergo._m_clauses_shown([])) == ""
}

test_two_clauses_of_one_item_join_with_and if {
	ergo._m_clauses_text(ergo._m_clauses_shown(_clause_items_of("xs", 1, 5, [_clause_missing("x.v"), _clause_missing("x.w")]))) == concat("; ", [
		"item 1 of xs: x.v is missing, and x.w is missing",
		"item 2 of xs: x.v is missing, and x.w is missing",
		"item 3 of xs: x.v is missing, and x.w is missing",
		"and 2 more",
	])
}

test_a_root_whose_value_holds_a_semicolon_stays_one_clause if {
	clauses := [
		_clause_root("w.z", "unusable", `w.z is "p; q", which isn't a number`),
		_clause_item("item 1 of ws", "absent", [_clause_missing("w.v")]),
	]
	ergo._m_clauses_shown(clauses) == clauses
	ergo._m_clauses_text(clauses) == `w.z is "p; q", which isn't a number; item 1 of ws: w.v is missing`
}

test_roots_that_tie_on_their_cause_sort_by_their_name_not_their_text if {
	ergo._m_clauses_text(ergo._m_clauses_shown([
		_clause_missing("$params.z"),
		_clause_root("$input.os.name", "absent", "item 2 of $input.os: name is missing"),
	])) == "item 2 of $input.os: name is missing; $params.z is missing"
}

test_an_items_own_text_counts_as_one_leaf_of_the_cap if {
	ergo._m_clauses_text(ergo._m_clauses_shown([_clause_item("item 1 of ws", "unusable", [
		_clause_unread("item 1 of w.items", "unusable", "item 1 of w.items is null, which isn't an object"),
		_clause_unread("item 2 of w.items", "unusable", "item 2 of w.items is 3, which isn't an object"),
		_clause_item("item 3 of w.items", "absent", [_clause_missing("n")]),
		_clause_unread("item 4 of w.items", "unusable", "item 4 of w.items is 4, which isn't an object"),
	])])) == concat("; ", [
		"item 1 of ws: item 1 of w.items is null, which isn't an object",
		"item 1 of ws: item 2 of w.items is 3, which isn't an object",
		"item 1 of ws: item 3 of w.items: n is missing",
		"and 1 more",
	])
}

test_two_clauses_for_one_item_count_as_one_item_in_the_cap if {
	ergo._m_clauses_text(ergo._m_clauses_shown([
		_clause_item("item 1 of xs", "absent", [_clause_missing("v")]),
		_clause_item("item 1 of xs", "absent", [_clause_missing("w")]),
		_clause_item("item 2 of xs", "absent", [_clause_missing("v")]),
		_clause_item("item 3 of xs", "absent", [_clause_missing("v")]),
		_clause_item("item 4 of xs", "absent", [_clause_missing("v")]),
		_clause_item("item 4 of xs", "absent", [_clause_missing("w")]),
	])) == concat("; ", [
		"item 1 of xs: v is missing",
		"item 1 of xs: w is missing",
		"item 2 of xs: v is missing",
		"item 3 of xs: v is missing",
		"and 1 more",
	])
}

test_roots_and_lists_with_the_same_text_are_said_once_whatever_their_names if {
	ergo._m_clauses_shown([
		_clause_root("$input.os.name", "absent", "item 2 of $input.os: name is missing"),
		ergo._m_clause("list", "es", "absent", "es is missing"),
		_clause_root("$input.os", "absent", "item 2 of $input.os: name is missing"),
		_clause_missing("es"),
		ergo._m_clause("list", "ws", "value", "ws is []"),
		ergo._m_clause("list", "x.ws", "value", "ws is []"),
	]) == [
		_clause_root("$input.os", "absent", "item 2 of $input.os: name is missing"),
		_clause_missing("es"),
		ergo._m_clause("list", "ws", "value", "ws is []"),
	]
}

test_a_cut_item_keeps_its_own_clauses_apart_like_an_uncut_one if {
	review := _clause_item("item 1 of c.reviews", "value", [_clause_root("ok", "value", "ok is false")])
	third := _clause_item("item 3 of cs", "value", [
		review,
		_clause_root("c.a", "value", "c.a is 2"),
		_clause_item("item 2 of c.reviews", "value", [_clause_root("ok", "value", "ok is false")]),
		_clause_root("c.b", "value", "c.b is 3"),
	])
	ergo._m_clauses_text(ergo._m_clauses_shown([third])) == concat("; ", [
		"item 3 of cs: item 1 of c.reviews: ok is false",
		"item 3 of cs: c.a is 2",
		"item 3 of cs: item 2 of c.reviews: ok is false",
		"item 3 of cs: c.b is 3",
	])
	ergo._m_clauses_text(ergo._m_clauses_shown([
		_clause_item("item 1 of cs", "value", [review]),
		_clause_item("item 2 of cs", "value", [review]),
		third,
	])) == concat("; ", [
		"item 1 of cs: item 1 of c.reviews: ok is false",
		"item 2 of cs: item 1 of c.reviews: ok is false",
		"item 3 of cs: item 1 of c.reviews: ok is false",
		"item 3 of cs: c.a is 2",
		"item 3 of cs: c.b is 3",
		"and 1 more",
	])
}
