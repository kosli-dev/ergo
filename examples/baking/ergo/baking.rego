package baking

import data.ergo
import data.workings

report := ergo.report(input, data.baking.requirements)

violations := ergo.violations(report)

workings_table := workings.by_subject(report)
