package baking

batches[b.id] := {
	"compliant": compliant(b),
	"nut_free": nut_free(b),
	"temp_ok": temp_ok(b),
	"time_ok": time_ok(b),
} if {
	some b in input.batches
}

default nut_free(_) := false

nut_free(b) if {
	not has(b.allergens, "nuts")
}

default temp_ok(_) := false

temp_ok(b) if {
	b.bake.temp_c >= 175
	b.bake.temp_c <= 200
}

default time_ok(_) := false

time_ok(b) if {
	b.bake.minutes >= 25
	b.bake.minutes <= 40
}

default compliant(_) := false

compliant(b) if {
	nut_free(b)
	temp_ok(b)
	time_ok(b)
}

has(arr, x) if {
	arr[_] == x
}
