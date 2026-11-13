package ergo_test

import data.ergo
import rego.v1

test_a_named_by_key_read_from_a_list_input_is_not_walked if {
	policy := _list_key_policy({"from": "$input", "identified_by": "id"}, "m named by $input.k exists")
	every doc in [[{"id": "a", "k": "x", "m": {"x": 1}}, {"id": "b"}], [{"id": "a", "k": null, "m": {"x": 1}}], [{"id": "a", "k": 3, "m": {"x": 1}}]] {
		rows := [[r.passed, r.cause, r.message] | some r in ergo.report(doc, policy, {}).results; r.check == "c"]
		count(rows) > 0
		every row in rows {
			row == [false, "not_an_object", concat("", ["$input is ", ergo._text(doc), ", which isn't an object"])]
		}
	}
}

test_contains_reads_one_value_so_a_list_its_right_side_meets_fails_as_unusable if {
	every words in ["contains", "does not contain"] {
		every components in [[{"name": "click"}, {}], [{"name": null}], [], ["click"], [{"name": "click"}], [{"name": "click"}, {"name": "attrs"}]] {
			m := concat("", ["$input.sbom.components is ", ergo._text(components), ", which isn't an object"])
			_walk_right_rows(concat("", ["tags ", words, " $input.sbom.components.name"]), _walk_right_doc(components), {}) == [[false, "unusable", m], [false, "unusable", m]]
		}
		every components in [[{"name": "click"}], [["click"]]] {
			doc := {"things": [{"id": "t1", "tags": [["click"]], "deps": components}]}
			_walk_right_rows(concat("", ["tags ", words, " deps.name"]), doc, {}) == [[false, "unusable", concat("", ["deps is ", ergo._text(components), ", which isn't an object"])]]
		}
	}
}
