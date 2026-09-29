package ergo

op_passed(check, subj) if {
	check.op == "even"
	n := value_at(subj, check.path)
	is_number(n)
	n % 2 == 0
}

op_passed(check, subj) if {
	check.op == "both_present"
	every path in check.paths {
		leaf_passed({"op": "present", "path": path}, subj)
	}
}
