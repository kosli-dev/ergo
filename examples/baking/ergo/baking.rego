package baking

import data.ergo
import data.workings

report := ergo.report(input, {"ergo_spec": data.baking.ergo_spec, "subjects": data.baking.subjects, "requirements": data.baking.requirements}, {})

violations := ergo.violations(report)

workings_table := workings.by_subject(report)
