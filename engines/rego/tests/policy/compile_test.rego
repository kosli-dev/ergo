package ergo_test

import data.ergo
import rego.v1

well_formed_or_not := array.concat(
	[object.union(object.remove(typed_req, object.keys(fields)), fields) | some [fields, _] in badly_written_requirements],
	array.concat(
		[object.union(typed_req, {f: v}) | some [f, v] in wrong_types],
		[
			typed_req,
			object.union(typed_req, {"require": "some", "subject_type": "item", "from": "items whose id exists"}),
			object.union(typed_req, {"from": "every groups.items"}),
			object.union(typed_req, {"zz": 1}),
			object.union(typed_req, {"checks": {"c": {"op": "nope"}}}),
			{"from": "items"},
			{"from": "items", "checks": {}},
			5,
		],
	),
)

test_a_requirement_fails_well_formed_exactly_when_its_row_says_what_is_wrong if {
	lifted_reqs := [lifted({"s": req}) | some req in well_formed_or_not]
	well_formed := {i |
		some i, l in lifted_reqs
		rd := ergo._read(l)
		ergo._well_formed(rd.reqs.s) with data.ergo_subjects as rd.subjects with data.ergo_resolved as rd.resolved with data.ergo_sentences as rd.sentences with data.ergo_subject_sentences as rd.subject_sentences
	}
	nothing_listed := {i |
		some i, l in lifted_reqs
		rd := ergo._read(l)
		req := rd.reqs.s
		problems := (count(ergo._req_problems(req)) + count(ergo._check_problem_inputs(req))) + count(ergo._not_an_object_inputs(req)) with data.ergo_subjects as rd.subjects with data.ergo_resolved as rd.resolved with data.ergo_sentences as rd.sentences with data.ergo_subject_sentences as rd.subject_sentences
		problems == 0
	}
	well_formed == nothing_listed
	count(well_formed) > 2
	count(well_formed_or_not) - count(well_formed) > 30
}

narrowed_chain_subjects := {
	"art": {"from": "arts", "identified_by": "id"},
	"b": {"from": "every art.bs whose y exists", "identified_by": "k"},
	"nb": {"from": "b whose x exists"},
	"nnb": {"from": "nb whose art.ok is true"},
	"c": {"from": "nnb.cs"},
	"d": {"from": "c.ds"},
}

test_a_subject_that_narrows_a_child_is_read_inside_the_childs_parent if {
	rd := ergo._read({"subjects": narrowed_chain_subjects, "requirements": {}})
	rd.subject_sentences.chains == {"b": "art", "nb": "art", "nnb": "art", "c": "nnb"}
}

test_narrowing_a_child_does_not_count_as_a_level_of_a_chain if {
	rd := ergo._read({"subjects": narrowed_chain_subjects, "requirements": {}})
	not "c" in object.keys(rd.subject_sentences.problems)
	rd.subject_sentences.problems.d.from == ["a chain of more than three subjects isn't supported yet"]
}

test_a_subject_that_narrows_a_child_resolves_to_the_childs_path_and_both_conditions if {
	rd := ergo._read({"subjects": narrowed_chain_subjects, "requirements": {}})
	rd.resolved.nb.problems == set()
	rd.resolved.nb.def.from == rd.resolved.b.def.from
	count(rd.resolved.nb.def.applies_to) == 2
	rd.resolved.nnb.problems == set()
}
