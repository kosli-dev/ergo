package ergo_test

import data.ergo
import rego.v1

test_the_id_check_says_every_subject_has_a_unique_id if {
	ergo._unique_ancestor_description(0, "repo") == "Every repo has a unique id"
	ergo._unique_ancestor_description(1, "pull request") == "every pull request has a unique id"
}

test_the_id_expression_counts_missing_and_repeated_ids if {
	ergo._ids_expression("repos") == "count(missing(ids(repos))) + count(repeated(ids(repos))) == 0"
}

test_a_null_id_is_not_an_id_so_it_never_repeats if {
	refs := {0: {"id": null}, 1: {"id": null}, 2: {"id": "a"}, 3: {"id": "a"}}
	[p[1] | some p in ergo._repeated_ids(refs)] == ["a"]
}
