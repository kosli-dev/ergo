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
