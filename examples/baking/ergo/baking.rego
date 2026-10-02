package baking

import data.ergo

report := ergo.report(input, data.baking.requirements)

violations := ergo.violations(report)
