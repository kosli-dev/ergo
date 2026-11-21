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

_root(name, cause, text) := ergo._m_clause("root", name, cause, text)

_missing(name) := _root(name, "absent", concat("", [name, " is missing"]))

_null(name) := _root(name, "null", concat("", [name, " is null"]))

_unread(name, cause, text) := ergo._m_clause("item", name, cause, text)

_item(name, cause, said) := ergo._m_item_clause(name, cause, said)

test_roots_lists_and_and_n_more_are_joined_with_a_semicolon if {
	ergo._m_clauses_text([
		_root("$params", "not_an_object", "$params is 3, which isn't an object"),
		ergo._m_clause("list", "es", "absent", "es is missing"),
		ergo._m_clause_more(2),
	]) == "$params is 3, which isn't an object; es is missing; and 2 more"
}

test_an_item_says_its_clauses_after_its_name_joined_with_and if {
	ergo._m_clauses_text([
		_item("item 1 of xs", "absent", [_missing("x.v"), _missing("x.w")]),
		_unread("item 2 of xs", "unusable", "item 2 of xs is null, which isn't an object"),
	]) == "item 1 of xs: x.v is missing, and x.w is missing; item 2 of xs is null, which isn't an object"
}

test_a_nested_item_says_each_leaf_after_every_name_above_it if {
	ergo._m_clauses_text([_item("item 1 of ws", "unusable", [
		_missing("w.a"),
		_unread("item 2 of items", "unusable", "item 2 of items is null, which isn't an object"),
		_missing("cov.x"),
		_null("cov.y"),
		_item("item 3 of ys", "absent", [_item("item 1 of y.zs", "absent", [_missing("n")])]),
	])]) == concat("; ", [
		"item 1 of ws: w.a is missing",
		"item 1 of ws: item 2 of items is null, which isn't an object",
		"item 1 of ws: cov.x is missing, and cov.y is null",
		"item 1 of ws: item 3 of ys: item 1 of y.zs: n is missing",
	])
}
