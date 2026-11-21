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
