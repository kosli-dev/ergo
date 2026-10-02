package ergo

operators contains "even"

operators contains "both_present"

operators contains "multiple_of"

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

op_passed(check, subj) if {
	check.op == "multiple_of"
	n := value_at(subj, check.path)
	by := arg(check.by)
	is_number(n)
	is_number(by)
	n % by == 0
}

op_passed(check, _) if check.op == "undeclared"
