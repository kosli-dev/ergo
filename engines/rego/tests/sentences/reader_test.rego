package ergo_test

import data.ergo
import rego.v1

test_a_for_line_reads_its_items if {
	ergo._for_line(`every pull_requests as pr, some pr.approvers whose state is "APPROVED" as approver`) == {"items": [
		{"every": {"steps": ["pull_requests"]}, "as": "pr"},
		{"some": {"steps": ["pr", "approvers"]}, "where": [{"path": {"steps": ["state"]}, "phrase": {"op": "is", "value": "APPROVED"}}], "as": "approver"},
	]}
	ergo._for_line(`every commits, if any, as commit`) == {"items": [{"every": {"steps": ["commits"]}, "if_any": true, "as": "commit"}]}
	ergo._s_for_line_text(ergo._for_line(`every commits, if any, as commit`)) == "every commits, if any, as commit"
}

test_a_from_line_reads_its_path_keys_and_whose if {
	ergo._from_line(`artifact.attestations named by each of $params.names whose status is "COMPLETE"`) == {
		"path": {"steps": ["artifact", "attestations"]},
		"named_by_each_of": {"start": "params", "steps": ["names"]},
		"where": [{"path": {"steps": ["status"]}, "phrase": {"op": "is", "value": "COMPLETE"}}],
	}
	ergo._from_line(`trail`) == {"path": {"steps": ["trail"]}}
	ergo._s_from_line_text(ergo._from_line(`artifact.attestations named by each of $params.names whose status is "COMPLETE"`)) == `artifact.attestations named by each of $params.names whose status is "COMPLETE"`
}

test_a_sentence_written_wrong_says_what_is_wrong if {
	_read(`x is "a`) == {"problems": ["unclosed quote at column 6"]}
	_read(`x is 'a' and y is 'b`) == {"problems": ["unclosed quote at column 19"]}
	_read(`x is "\q"`) == {"problems": ["invalid string at column 6"]}
	_read(`x is "a	b"`) == {"problems": ["invalid string at column 6"]}
	_read(`x is 'a	b'`) == {"problems": ["invalid string at column 6"]}
	_read(`"\q" is 1`) == {"problems": ["invalid string at column 1"]}
	_read(`x is "\q" and y is "\q"`) == {"problems": ["invalid string at column 6", "invalid string at column 20"]}
	_read(`x is 'a"\q"b' and y is "\q"`) == {"problems": ["invalid string at column 24"]}
	_read(`x is "cost $usd" and`) == {"problems": ["doesn't parse"]}
	_read(`$foo is $bar and $foo exists`) == {"problems": ["unknown name $bar", "unknown name $foo"]}
	_read(`some x, if any, is 1`) == {"problems": ["if any can't go with some"]}
	_read(`every x some y is 1`) == {"problems": ["two quantifiers in one sentence: put them on a for line"]}
	_read(`count is 1`) == {"problems": ["count is a word of the grammar: write .count"]}
	_read(`x is empty_`) == {"assertions": [{"path": {"steps": ["x"]}, "phrase": {"op": "is", "terms": [{"steps": ["empty_"]}]}}]}
	_read(`a plus b whose c is 1 is 2`) == {"problems": ["a is a word of the grammar: write .a", "a whose goes after every, some, count of or sum of"]}
	_read(`x whose k is 1 is 2`) == {"problems": ["a whose goes after every, some, count of or sum of"]}
	_read(`count of approvers is empty`) == {"problems": ["is empty can't follow a count of, a sum of or a plus"]}
	_read(`x plus y matches "a"`) == {"problems": ["matches can't follow a count of, a sum of or a plus"]}
	_read(`5 is 5`) == {"problems": ["a number can't start a sentence"]}
	_read(`1 plus x is 5`).assertions[0].terms == [1, {"steps": ["x"]}]
	_read(`x named by every is 1`) == {"problems": ["every can't be an alias"]}
	_read(`x[params] is 1`) == {"problems": ["params can't be an alias"]}
	_read(`commits[01] is "x"`) == {"problems": ["doesn't parse"]}
	_read(`$foo is 1`) == {"problems": ["unknown name $foo"]}
	_read(`x is $params`).assertions[0].phrase.terms == [{"start": "params", "steps": []}]
	_read(`every commits.signed`) == {"problems": [`nothing after the path at column 21: expected a phrase, like "is" or "exists"`]}
	_read(`sum of stages.usd equals total within`) == {"problems": [`"within" needs a number after it`]}
	_read(`every  pull_requests  some approvers.state is "APPROVED"`) == {"problems": ["two quantifiers in one sentence: put them on a for line"]}
	_read(`x is equal to 1 within 2`).assertions[0].phrase == {"op": "is", "value": 1, "within": 2}
	_read(`x is 1 within -1`) == {"problems": [`"within" needs a number of 0 or more`]}
	_read(`x equals y within -0.5`) == {"problems": [`"within" needs a number of 0 or more`]}
	_read(`x is 1 within -0`).assertions[0].phrase.within == 0
	_read(`x is one of "a",	"b"`) == {"problems": ["doesn't parse"]}
	ergo._for_line(`every xs as x, every ys as x`) == {"problems": ["x is given twice"]}
	ergo._from_line(`xs[01]`) == {"problems": ["doesn't parse"]}
	ergo._from_line(`xs whose k is 1`) == {"path": {"steps": ["xs"]}, "where": [{"path": {"steps": ["k"]}, "phrase": {"op": "is", "value": 1}}]}
	_read(`x is between 5 and 1`) == {"problems": ["min above max"]}
	_read(`x matches "("`) == {"problems": [`invalid pattern "("`]}
	_read(`x is`) == {"problems": ["doesn't parse"]}
	_read(``) == {"problems": ["doesn't parse"]}
	_read(`x is 1 and`) == {"problems": ["doesn't parse"]}
	_read(`every x whose a is 1`) == {"problems": ["doesn't parse"]}
	_read(`x is count of y whose a is 1`) == {"problems": ["doesn't parse"]}
	_read(`item 0 of x is 1`) == {"problems": ["doesn't parse"]}
	_read(`foo$bar is 1`) == {"problems": ["doesn't parse"]}
	_read(`x is "$schema"`) == {"assertions": [{"path": {"steps": ["x"]}, "phrase": {"op": "is", "value": "$schema"}}]}
	ergo._for_line(`every x as every`) == {"problems": ["every can't be an alias"]}
	ergo._for_line(`every x as params`) == {"problems": ["params can't be an alias"]}
	ergo._for_line(`every x as a, every y as b, every z as c`) == {"problems": ["a for line holds two items at most"]}
	ergo._for_line(`some x, if any, as y`) == {"problems": ["if any can't go with some"]}
	ergo._from_line(`count whose x is 1`) == {"problems": ["count is a word of the grammar: write .count"]}
	ergo._from_line(`x is 1`) == {"problems": ["doesn't parse"]}
	ergo._from_line(`$input named by each of "T"`) == {"problems": ["doesn't parse"]}
}

test_the_smallest_number_is_checked_by_its_digits_so_opa_rounding_it_up_doesnt_let_it_in if {
	every text in [`x is 2.2250738585072013999999999e-308`, `x is 22250738585072013e-324`, `x is 1e-308`, `x is -1e-400`] {
		startswith(_sentence_problems(text)[0], "number out of range: ")
	}
	every text in [`x is 2.2250738585072014e-308`, `x is 0.0`, `x is 0.00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000`] {
		count(ergo._sentence(text).assertions) == 1
	}
}

test_a_name_from_the_report_reads_back_in_a_sentence_as_the_path_it_names if {
	every path in [
		["x", "$b"],
		["empty", "x"],
		["a"],
		["xs", 1, "k"],
		["xs", 1],
		["$$params", "allowed"],
		["$$input", "repo", "name"],
		["k", {"ref": ["$$params", "n"]}, "ok"],
		[{"literal": "$schema"}, "x"],
		["metadata", "labels", "app.kubernetes.io/name"],
		["count", "first", "is"],
	] {
		parsed := ergo._sentence(concat(" ", [ergo._path_name(path), "exists"]))
		ergo._s_model_path(parsed.assertions[0].path) == path
	}
}

test_a_phrase_lists_its_longer_wording_first_because_finding_a_phrase_never_goes_back_to_try_another_wording if {
	_read(`x is equal to 1`) == {"assertions": [{"path": {"steps": ["x"]}, "phrase": {"op": "is", "value": 1}}]}
	_read(`x is an object`).assertions[0].phrase == {"op": "is a", "type": "object"}
	_read(`x is not in $params.a`).assertions[0].phrase.op == "is not one of"
	_read(`x does not equal y`).assertions[0].phrase.op == "is not"
	every ph in ergo._s_patterns.phrases {
		ph[1] != `(?:is|is +equal +to|equals) +`
	}
}

test_the_phrase_table_has_no_more_entries_than_opas_wasm_regex_cache_takes_in_a_report_of_hundreds_of_patterns if count(ergo._s_patterns.phrases) == 29

test_a_whose_in_a_check_or_a_for_line_still_takes_no_some_or_every_condition if {
	_read(`some a whose some b.c is 1 is 2`) == {"problems": ["doesn't parse"]}
	_read(`every a whose every b.c is 1 is 2`) == {"problems": ["doesn't parse"]}
	_read(`some a whose some b.c is 1`) == {"problems": ["doesn't parse"]}
	ergo._for_line(`every a whose some b.c is 1 as x`) == {"problems": ["doesn't parse"]}
	ergo._for_line(`last of a whose every b.c is 1 as x`) == {"problems": ["doesn't parse"]}
	ergo._from_line(`releases whose some files.path matches "x"`) != {"problems": ["doesn't parse"]}
}

test_the_report_lists_a_subject_from_the_line_read_with_the_policy_not_by_reading_it_again if {
	read := {"lines": {"d": ergo._from_line("xs")}}
	ergo._subject_text("d", {"from": "ys"}) == "xs" with data.ergo_subject_sentences as read
}

test_a_field_called_every_in_a_from_line_is_written_with_a_dot if {
	rep := _from_report({"every": {"x": [{"id": 1}]}}, {"s": {"from": "every .every.x", "identified_by": "id"}}, {"c": "id exists"}, {})
	[[r.subject.id, r.cause] | some r in rep.results; r.check == "c"] == [[1, "satisfied"]]
	_from_problems(_from_report({"every": [1]}, {"s": {"from": "every"}}, {"c": "x exists"}, {})) == [{"name": "subjects.s.from", "value": ["every is a word of the grammar: write .every"], "locations": []}]
	_from_problems(_from_report({}, {"s": {"from": "every count.x"}}, {"c": "x exists"}, {})) == [{"name": "subjects.s.from", "value": ["count is a word of the grammar: write .count"], "locations": []}]
	ergo._sentence(`every x whose k is 1`) == {"problems": ["doesn't parse"]}
}

test_brackets_in_a_for_item_that_starts_with_every_some_or_a_position_are_read if {
	"items" in object.keys(ergo._for_line("first of t as i"))
	"items" in object.keys(ergo._for_line("some t[0] as i"))
	"items" in object.keys(ergo._for_line("every t[0].u as i"))
	"items" in object.keys(ergo._for_line("every t as x, some t[0] as i"))
	"items" in object.keys(ergo._for_line("every t as x, every t[0].u as i"))
	"items" in object.keys(ergo._for_line("every t as x, first of x.u as i"))
}
