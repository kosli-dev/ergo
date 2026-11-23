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
	every text in [`x is 2.22507385850721e-308`, `x is 0.0`, `x is 0.00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000`] {
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

test_ignoring_words_read_after_is_and_is_one_of if {
	_read(`x is "a" ignoring case`).assertions[0].phrase == {"op": "is", "value": "a", "ignoring": "case"}
	_read(`x is  "a"  ignoring  case  and  surrounding  spaces`).assertions[0].phrase == {"op": "is", "value": "a", "ignoring": "case and surrounding spaces"}
	_read(`x is not one of "a", "b" ignoring surrounding spaces`).assertions[0].phrase == {"op": "is not one of", "values": ["a", "b"], "ignoring": "surrounding spaces"}
	_printed(`x is in "a", "b" ignoring case and surrounding spaces`) == `x is one of "a", "b" ignoring case and surrounding spaces`
	_printed(`every xs whose k is not "a" ignoring case exists`) == `every xs whose k is not "a" ignoring case exists`
}

test_ignoring_words_after_another_phrase_or_in_another_order_are_written_wrong if {
	_read(`x is "a" ignoring surrounding spaces and case`) == {"problems": [`"ignoring surrounding spaces and case" is written "ignoring case and surrounding spaces"`]}
	every pair in [
		[`x is at least 3 ignoring case`, "is at least"],
		[`x is 1 within 2 ignoring case`, "within"],
		[`x matches "a" ignoring case`, "matches"],
		[`x exists ignoring case`, "exists"],
		[`x is a non-empty string ignoring case`, "is a non-empty string"],
	] {
		_read(pair[0]) == {"problems": [concat("", [`"`, pair[1], `" can't take ignoring case`])]}
	}
	_read(`x is y plus 1 ignoring case`) == {"problems": [`"ignoring case" can't take a count of, a sum of or a plus`]}
	_read(`count of xs is "a" ignoring case`) == {"problems": [`"ignoring case" can't follow a count of, a sum of or a plus`]}
	_read(`x is y ignoring case and y is 1 ignoring surrounding spaces`) == {"problems": [`"ignoring surrounding spaces" takes text`]}
	every line in [`x is 1 ignoring case`, `x is null ignoring case`, `x is not true ignoring case`, `x is one of "a", 1 ignoring case`, `x is one of "a", null ignoring case`] {
		`"ignoring case" takes text` in _read(line).problems
	}
	ergo._s_self_problems(_read(`x equals x ignoring case`).assertions) == {"x is compared with itself"}
}

test_ignoring_words_after_a_list_from_a_path_are_read if {
	every line in [
		`x is in $params.l ignoring case`,
		`x is one of $params.l ignoring case`,
		`x is in ys ignoring surrounding spaces`,
		`x is one of $input.ys ignoring case and surrounding spaces`,
		`x is not in $params.l ignoring case`,
		`x is not one of ys ignoring case`,
		`x is in $input[0] ignoring case`,
		`x is in .ys ignoring case`,
		`x is in it ignoring case`,
		`x is in $params[k] ignoring case`,
		`every xs.v is in $params.l ignoring case`,
		`some xs.v is not in ys ignoring case`,
		`count of xs whose v is in ys ignoring case is 1`,
		`every xs whose v is in ys ignoring case, if any, exists`,
	] {
		not "problems" in object.keys(_read(line))
	}
	not "problems" in object.keys(ergo._for_line(`every xs whose v is not in $params.l ignoring case as x`))
	_read(`x is in ys ignoring surrounding spaces and case`) == {"problems": [`"ignoring surrounding spaces and case" is written "ignoring case and surrounding spaces"`]}
}

test_ignoring_words_after_a_list_from_a_path_of_more_than_one_step_are_written_wrong_for_now if {
	every pair in [
		[`x is in pl.name ignoring case`, `"is in" can't take ignoring case yet`],
		[`x is in xs[0] ignoring surrounding spaces`, `"is in" can't take ignoring surrounding spaces yet`],
		[`x is in item 2 of xs ignoring case`, `"is in" can't take ignoring case yet`],
		[`x is in first of xs ignoring case`, `"is in" can't take ignoring case yet`],
		[`x is in $input.cs named by k ignoring case`, `"is in" can't take ignoring case yet`],
		[`x is in $input.cs.name ignoring case and surrounding spaces`, `"is in" can't take ignoring case and surrounding spaces yet`],
		[`x is one of $params.cs.name ignoring case`, `"is in" can't take ignoring case yet`],
		[`x is not in $input.cs[0] ignoring case`, `"is not in" can't take ignoring case yet`],
		[`x is not one of it.x ignoring case`, `"is not in" can't take ignoring case yet`],
		[`x is in $params[k].l ignoring case`, `"is in" can't take ignoring case yet`],
		[`count of xs whose v is in thing.ys ignoring case is 1`, `"is in" can't take ignoring case yet`],
		[`every xs.v is in .a.b ignoring case`, `"is in" can't take ignoring case yet`],
	] {
		_read(pair[0]) == {"problems": [pair[1]]}
	}
	_read(`count of xs is in ps.b ignoring case`) == {"problems": [`"is in" can't take ignoring case yet`, "is one of can't follow a count of, a sum of or a plus"]}
	ergo._for_line(`every xs whose v is not in $params.a.l ignoring case as x`) == {"problems": [`"is not in" can't take ignoring case yet`]}
	_read(`x is in ps.b ignoring surrounding spaces and case`) == {"problems": [
		`"ignoring surrounding spaces and case" is written "ignoring case and surrounding spaces"`,
		`"is in" can't take ignoring surrounding spaces and case yet`,
	]}
}

test_a_list_read_from_a_field_keeps_the_ignoring_words_in_its_model if {
	ergo._s_plain_model(_read(`x is in ys ignoring case`).assertions[0]) == {"op": "compare", "left": ["x"], "cmp": "in", "right": ["ys"], "ignoring": "case"}
	ergo._s_plain_model(_read(`x is not one of ys ignoring surrounding spaces`).assertions[0]) == {"op": "compare", "left": ["x"], "cmp": "not_in", "right": ["ys"], "ignoring": "surrounding spaces"}
}

test_ignoring_words_dont_read_after_contains_or_starts_with_yet if {
	every line in [
		`x contains "a" ignoring case`,
		`x is alphabetically before "a" ignoring case`,
		`x is "a" ignoring`,
	] {
		_read(line) == {"problems": ["doesn't parse"]}
	}
}

test_ignoring_is_a_word_of_the_grammar if {
	_read(`ignoring is 1`) == {"problems": ["ignoring is a word of the grammar: write .ignoring"]}
	_read(`.ignoring is 1`).assertions[0].path == {"steps": ["ignoring"], "dot": true}
	ergo._s_word("ignoring")
	ergo._s_word("every")
	not ergo._s_word("status")
	not "ignoring" in ergo._s_words
}

test_every_member_of_reads_the_members_at_the_end_of_a_from_line if {
	ergo._from_line(`every member of record.evidence`) == {"every": true, "member": true, "path": {"steps": ["record", "evidence"]}}
	ergo._from_line(`every  member  of x whose k is 1`) == {"every": true, "member": true, "path": {"steps": ["x"]}, "where": [{"path": {"steps": ["k"]}, "phrase": {"op": "is", "value": 1}}]}
	ergo._s_from_line_text(ergo._from_line(`every  member  of record.evidence whose kind is "a"`)) == `every member of record.evidence whose kind is "a"`
}

test_a_field_called_member_still_reads_as_a_field if {
	ergo._from_line(`every member.x`) == {"every": true, "path": {"steps": ["member", "x"]}}
	ergo._from_line(`every member of member`) == {"every": true, "member": true, "path": {"steps": ["member"]}}
	ergo._from_line(`member`) == {"path": {"steps": ["member"]}}
}

test_member_of_without_every_or_with_distinct_still_reads_so_a_rule_can_name_it if {
	ergo._from_line(`member of x`) == {"member": true, "path": {"steps": ["x"]}}
	ergo._from_line(`every distinct member of x`) == {"every": true, "distinct": true, "member": true, "path": {"steps": ["x"]}}
	ergo._s_from_line_text(ergo._from_line(`every distinct member of x`)) == `every distinct member of x`
}

test_member_of_reads_after_every_some_count_of_and_sum_of if {
	ergo._sentence(`every member of xs is 1`) == {"assertions": [{"every": {"steps": ["xs"]}, "member": true, "phrase": {"op": "is", "value": 1}}]}
	ergo._sentence(`some  member  of xs.y whose k is 1 exists`) == {"assertions": [{"some": {"steps": ["xs", "y"]}, "member": true, "where": [{"path": {"steps": ["k"]}, "phrase": {"op": "is", "value": 1}}], "phrase": {"op": "exists"}}]}
	ergo._sentence(`count of member of xs is 1`).assertions[0].terms == [{"count": {"steps": ["xs"]}, "member": true}]
	ergo._sentence(`sum of member of xs is at most 2`).assertions[0].terms == [{"sum": {"steps": ["xs"]}, "member": true}]
	ergo._sentence(`x is count of member of xs`).assertions[0].phrase.terms == [{"count": {"steps": ["xs"]}, "member": true}]
	ergo._sentence(`every member of member is 1`).assertions[0].every == {"steps": ["member"]}
	ergo._for_line(`every member of xs as m`) == {"items": [{"every": {"steps": ["xs"]}, "member": true, "as": "m"}]}
	ergo._from_line(`xs whose every member of t is 1`).where == [{"every": {"steps": ["t"]}, "member": true, "phrase": {"op": "is", "value": 1}}]
}

test_member_of_writes_back_as_it_reads if {
	every line in [
		`every member of xs is 1`,
		`some member of xs.y whose k is 1 exists`,
		`count of member of xs is 1`,
		`every member of xs, if any, is 1`,
	] {
		ergo._s_assertion_text(ergo._sentence(line).assertions[0]) == line
	}
	ergo._s_assertion_text(ergo._sentence(`x is count of member of xs`).assertions[0]) == `x equals count of member of xs`
	ergo._s_for_line_text(ergo._for_line(`every records as r, every member of r.evidence as e`)) == `every records as r, every member of r.evidence as e`
}

test_distinct_with_member_of_is_written_wrong_everywhere if {
	said := ["distinct can't go with every member of"]
	ergo._sentence(`every distinct member of xs is 1`).problems == said
	ergo._sentence(`count of distinct member of xs is 1`).problems == said
	ergo._for_line(`every distinct member of xs as m`).problems == said
}
