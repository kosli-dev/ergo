package ergo_test

import data.ergo
import rego.v1

test_an_id_is_a_path_inside_each_subject_so_it_cannot_start_at_the_input_or_the_params if {
	every text in ["$input.x", "$input", "$params.x"] {
		ergo._s_id_read(text) == {"problems": [`identified_by is a path, like "id" or "build.number"`]}
	}
	ergo._s_id_read("meta.id") == {"path": ["meta", "id"]}
}
