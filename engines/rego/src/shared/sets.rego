package ergo

import rego.v1

_no_value_states := {"absent", "null"}

_no_read_fault_causes := {"", "absent", "null"}

_value_fault_causes := {"absent", "null", "unusable"}

_value_fault_cause_list := ["absent", "null", "unusable"]

_failed_read_states := {"absent", "null", "unusable", "not_an_object"}

_root_read_flaws := {"not_an_object", "ambiguous", "unusable"}

_tolerated_root_flaws := {"", "not_an_object"}

_not_failing_causes := {"satisfied", "value"}

_tally_decided_causes := {"satisfied", "value", "missing"}

_holding_statuses := {"met", "not_applicable"}

_list_expected_msgs := {"a list", "a list or an object"}

_blank_or_list_expected_msgs := {"", "a list", "a list or an object"}

_list_or_object_types := {"array", "object"}

_collection_types := {"object", "array", "set"}

_walk_ops := {"every", "some"}

_require_modes := {"every", "some"}

_group_ops := {"all_of", "sentence_any_of"}

_non_leaf_ops := {"all_of", "sentence_any_of", "for"}

_two_sided_ops := {"compare", "compare_time"}

_single_contain_ops := {"includes", "excludes"}

_membership_ops := {"in", "not_in"}

_pattern_ops := {"matches_any", "not_matches_any"}

_equality_cmps := {"eq", "ne"}

_range_ops := {"range", "outside_range"}

_empty_list_ops := {"empty_string_or_list", "not_empty_string_or_list"}

_contain_ops := {"includes", "excludes", "includes_some", "not_includes_all"}

_all_cmps := {"includes_all", "excludes_all", "includes_some", "not_includes_all"}

_list_values_ops := _membership_ops | _contain_ops

_list_left_cmps := _single_contain_ops | _all_cmps

_list_cmps := ((_membership_ops | _single_contain_ops) | _pattern_ops) | _all_cmps

_list_phrase_ops := {"in", "not_in", "includes_some", "not_includes_all", "matches_any", "not_matches_any"}

_text_cmps := {"starts_with", "ends_with", "not_starts_with", "not_ends_with", "alphabetically_before", "alphabetically_after", "alphabetically_lte", "alphabetically_gte"}

_tally_forms := {"count_of", "sum_of"}

_derived_forms := {"count_of", "sum_of", "elapsed", "add", "join"}

_tally_path_keys := {"count_of", "sum_of", "elapsed_from", "elapsed_to"}

_term_keys := ["count", "sum", "elapsed_from", "elapsed_to"]

_term_tally_keys := {"count", "sum"}

_compare_sides := {"left", "right"}

_compare_side_list := ["left", "right"]

_ref_fields := {"path", "left", "right"}

_between_phrases := {"is between", "is not between"}

_contains_phrases := {"contains", "does not contain"}

_matches_phrases := {"matches", "does not match"}

_quantifier_words := {"every", "some"}

_quantifier_keys := {"every", "some"}

_item_quantifier_keys := {"every", "some", "pick"}

_path_quantifier_keys := {"path", "every", "some"}

_subject_field_keys := {"from", "identified_by"}

_subject_scope_keys := {"applies_to", "of"}

_subject_def_keys := {"applies_to", "of", "from", "identified_by"}

_list_argument_keys := ["values", "patterns"]

_check_argument_keys := ["value", "values", "patterns", "min", "max"]

_value_keys := {"value", "values"}

_phrase_argument_keys := {"value", "join"}

_within_keys := {"within", "max"}

_sort_keys := {"start", "position"}

_check_note_fields := {"description", "meta"}

_policy_sections := ["subjects", "requirements"]

_assertion_phrase_keys := ["terms", "phrase"]

_term_mark_keys := ["dot", "own"]

_row_extra_keys := ["root_msgs", "other_roots", "natural", "unfreed"]

_failed_internal_keys := ["msg", "said", "raw", "bare", "hoisted", "whose_of"]

_line_internal_keys := ["msg", "own_msg"]

_reserved_names := {"params", "input"}

_reserved_name_markers := {"$params", "$input"}

_reserved_ref_roots := {"$$params", "$$input"}

_input_and_params_walk_roots := {"$$input", "$$input[]", "$$params", "$$params[]"}

_text_item_states(r) := {"unusable"} if not is_array(r)

else := {_text_item_state(v) | some v in r; not is_string(v)}

_text_item_state(v) := "null" if v == null

else := "unusable"
