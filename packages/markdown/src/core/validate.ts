import type {Check, Diagnostic} from './types.ts'

export const OPS: Record<string, {required: string[]; optional?: string[]}> = {
	equals: {required: ['path', 'value']},
	present: {required: ['path']},
	non_empty_string: {required: ['path']},
	matches_any: {required: ['path', 'patterns']},
	not_matches_any: {required: ['path', 'patterns']},
	range: {required: ['path', 'min', 'max']},
	includes: {required: ['path', 'value']},
	excludes: {required: ['path', 'value']},
	compare: {required: ['left', 'right', 'cmp']},
	compare_time: {required: ['left', 'right', 'cmp']},
	all: {required: ['path', 'check'], optional: ['each']},
	any: {required: ['path', 'check'], optional: ['each']},
	any_of: {required: ['options']},
}

export const CMPS = new Set(['eq', 'ne', 'gt', 'gte', 'lt', 'lte'])

const COMMON = ['op', 'description', 'expression', 'inputs', 'substitute']

export function validateCheck(check: Check, where: string, line: number, customOps: Set<string>): Diagnostic[] {
	const out: Diagnostic[] = []
	const err = (message: string): number => out.push({severity: 'error', line, message})

	const op = check['op']
	if (typeof op !== 'string') {
		err(`${where}: no operator`)
		return out
	}

	if (customOps.has(op)) {
		if (typeof check['expression'] !== 'string' || !check['expression'])
			err(`${where}: custom operator "${op}" declares no expression`)
		if (!Array.isArray(check['inputs']) && !check['path'])
			err(`${where}: custom operator "${op}" declares neither inputs nor path`)
		return out
	}

	const spec = OPS[op]
	if (!spec) {
		err(`${where}: unknown operator "${op}" — the library would accept this and never pass it`)
		return out
	}

	for (const field of spec.required)
		if (check[field] === undefined) err(`${where}: operator "${op}" needs "${field}"`)

	const known = new Set([...COMMON, ...spec.required, ...(spec.optional ?? [])])
	for (const key of Object.keys(check))
		if (!known.has(key)) err(`${where}: operator "${op}" does not read "${key}"`)

	if ((op === 'compare' || op === 'compare_time') && !CMPS.has(String(check['cmp'])))
		err(`${where}: "${String(check['cmp'])}" is not a comparison — one of ${[...CMPS].join(', ')}`)

	if ((op === 'all' || op === 'any') && check['check'])
		out.push(...validateCheck(check['check'] as Check, `${where} > element`, line, customOps))

	if (op === 'any_of') {
		const options = check['options']
		if (options && typeof options === 'object')
			for (const [name, group] of Object.entries(options as Record<string, unknown>)) {
				if (!Array.isArray(group) || group.length === 0) {
					err(`${where}: any_of option "${name}" is not a non-empty list of clauses`)
					continue
				}
				for (const leaf of group as Check[]) {
					const leafOp = String(leaf['op'])
					if (leafOp === 'all' || leafOp === 'any' || leafOp === 'any_of')
						err(`${where}: any_of option "${name}" contains "${leafOp}" — options hold leaf clauses only`)
					out.push(...validateCheck(leaf, `${where} > ${name}`, line, customOps))
				}
			}
	}

	if (check['substitute']) out.push(...validateCheck(check['substitute'] as Check, `${where} > substitute`, line, customOps))

	return out
}

export function validateRequirements(requirements: unknown, customOps: Set<string>): Diagnostic[] {
	const out: Diagnostic[] = []
	if (!requirements || typeof requirements !== 'object')
		return [{severity: 'error', line: 0, message: 'requirements is not an object'}]

	for (const [name, req] of Object.entries(requirements as Record<string, unknown>)) {
		if (!req || typeof req !== 'object') {
			out.push({severity: 'error', line: 0, message: `${name}: not an object`})
			continue
		}
		const r = req as Record<string, unknown>
		const checks = r['checks']
		if (!checks || typeof checks !== 'object' || Object.keys(checks).length === 0)
			out.push({severity: 'error', line: 0, message: `${name}: declares no checks, so it asserts nothing`})
		const require_ = r['require']
		if (require_ !== undefined && require_ !== 'every' && require_ !== 'some')
			out.push({severity: 'error', line: 0, message: `${name}: require must be "every" or "some"`})

		for (const group of ['checks', 'applies_to'] as const)
			for (const [cname, check] of Object.entries((r[group] ?? {}) as Record<string, Check>)) {
				if (cname.startsWith('$'))
					out.push({severity: 'error', line: 0, message: `${name}.${cname}: names beginning with $ are the library's`})
				out.push(...validateCheck(check, `${name}.${cname}`, 0, customOps))
			}
	}
	return out
}
