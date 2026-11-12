package ergo

import rego.v1

_req_field(req, f, d) := object.get(req, f, d) if is_object(req)

_req_field(req, _, d) := d if not is_object(req)

_object_or_empty(x) := x if is_object(x)

_object_or_empty(x) := {} if not is_object(x)

_checks_of(req) := _object_or_empty(_req_field(req, "checks", {}))

_has_type("applies_to", v) if is_object(v)

_has_type("checks", v) if is_object(v)

_has_type("from", v) if is_array(v)

_has_type("from", v) if is_string(v)

_has_type("identified_by", v) if is_array(v)

_has_type("identified_by", v) if is_string(v)

_has_type("min_subjects", v) if {
	is_number(v)
	v >= 0
	v <= 1000000
	v == floor(v)
}

_has_type("subject", v) if {
	is_string(v)
	trim_space(v) != ""
}

_has_type("of", v) if {
	is_string(v)
	trim_space(v) != ""
}

_has_type("description", v) if is_string(v)

_has_type("description", null)

_has_type("meta", v) if is_object(v)

_has_type("meta", null)

_first_or_null([x]) := x

_first_or_null([]) := null

_joined(base, []) := base

_joined(base, keys) := concat("", [base, "/", concat("/", [_escaped(k) | some k in keys])]) if count(keys) > 0

_first_seen(xs) := [p[1] | some p in sort([[s[1], s[0]] | some j, s in sorted; _starts_group(sorted, j)])] if sorted := sort([[x, i] | some i, x in xs])

_once(xs) := [x | some i, x in xs; not x in array.slice(xs, 0, i)]

version := "0.7.0-dev"

_engine := {"name": "ergo-rego", "version": version}

_spec := "v0.7-dev"

_is_version(v) if regex.match(`^v[0-9]+\.[0-9]+(-dev)?$`, v)
