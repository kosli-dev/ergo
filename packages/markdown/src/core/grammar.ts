import type {Check, CustomOpRegistry, Path, PropertyDef} from './types.ts'
import {literal} from './paths.ts'

export type Atom = {kind: 'text' | 'code' | 'prop'; text: string}

export interface Ctx {
	props: Map<string, PropertyDef>
	constants: Map<string, unknown[]>
	substitutes: Map<string, Check>
	customOps: CustomOpRegistry
}

interface Inline {
	type: string
	value?: string
	children?: Inline[]
}

export function atomize(children: Inline[]): Atom[] {
	const out: Atom[] = []
	const walk = (nodes: Inline[], strong: boolean): void => {
		for (const n of nodes) {
			if (n.type === 'text') out.push({kind: strong ? 'prop' : 'text', text: n.value ?? ''})
			else if (n.type === 'inlineCode') out.push({kind: strong ? 'prop' : 'code', text: n.value ?? ''})
			else if (n.type === 'strong') walk(n.children ?? [], true)
			else if (n.type === 'break') out.push({kind: 'text', text: ' '})
			else if (n.children) walk(n.children, strong)
		}
	}
	walk(children, false)
	const merged: Atom[] = []
	for (const a of out) {
		const last = merged[merged.length - 1]
		if (last && last.kind === a.kind && a.kind !== 'code') last.text += a.text
		else merged.push({...a})
	}
	return merged
}

export function sentences(atoms: Atom[]): Atom[][] {
	const out: Atom[][] = []
	let cur: Atom[] = []
	for (const a of atoms) {
		if (a.kind !== 'text') {
			cur.push(a)
			continue
		}
		let rest = a.text
		for (;;) {
			const m = /\.(\s+|$)/.exec(rest)
			if (!m) break
			cur.push({kind: 'text', text: rest.slice(0, m.index + 1)})
			out.push(cur)
			cur = []
			rest = rest.slice(m.index + m[0].length)
		}
		if (rest) cur.push({kind: 'text', text: rest})
	}
	if (cur.some((a) => a.text.trim())) out.push(cur)
	return out
}

export function plain(atoms: Atom[]): string {
	return atoms
		.map((a) => a.text)
		.join('')
		.replace(/\s+/g, ' ')
		.trim()
}

interface Norm {
	s: string
	props: string[]
	codes: string[]
}

export function normalize(atoms: Atom[]): Norm {
	const props: string[] = []
	const codes: string[] = []
	let s = ''
	for (const a of atoms) {
		if (a.kind === 'prop') s += `«p${props.push(a.text) - 1}»`
		else if (a.kind === 'code') s += `«c${codes.push(a.text) - 1}»`
		else s += a.text
	}
	return {s: s.replace(/\s+/g, ' ').trim(), props, codes}
}

const P = '\\u00abp(\\d+)\\u00bb'
const C = '\\u00abc(\\d+)\\u00bb'

export function lookup(ctx: Ctx, display: string): PropertyDef | undefined {
	const key = display.toLowerCase().replace(/\s+/g, ' ').trim()
	return (
		ctx.props.get(key) ??
		ctx.props.get(key + 's') ??
		(key.endsWith('s') ? ctx.props.get(key.slice(0, -1)) : undefined)
	)
}

export function outerPath(p: PropertyDef): Path {
	return p.splits.length ? p.path.slice(0, p.splits[0]) : p.path
}

export function innerPath(p: PropertyDef): Path {
	return p.splits.length ? p.path.slice(p.splits[p.splits.length - 1]) : p.path
}

const CMP: Record<string, {cmp: string; time: boolean}> = {
	'equal to': {cmp: 'eq', time: false},
	'different from': {cmp: 'ne', time: false},
	'greater than': {cmp: 'gt', time: false},
	'at least': {cmp: 'gte', time: false},
	'less than': {cmp: 'lt', time: false},
	'at most': {cmp: 'lte', time: false},
	after: {cmp: 'gt', time: true},
	'at or after': {cmp: 'gte', time: true},
	before: {cmp: 'lt', time: true},
	'at or before': {cmp: 'lte', time: true},
}

export class RuleError extends Error {}

export function phraseFor(cmp: string, time: boolean): string {
	for (const [phrase, spec] of Object.entries(CMP)) if (spec.cmp === cmp && spec.time === time) return phrase
	throw new RuleError(`no phrase for comparison "${cmp}"`)
}

function patternsOf(n: Norm, rest: string, ctx: Ctx): unknown[] {
	const one = new RegExp(`^${P}$`).exec(rest)
	if (one) {
		const name = (n.props[Number(one[1])] ?? '').toLowerCase().trim()
		const found = ctx.constants.get(name)
		if (!found) throw new RuleError(`no constant named "${name}"`)
		return found
	}
	const out: unknown[] = []
	const re = new RegExp(C, 'g')
	for (let m = re.exec(rest); m; m = re.exec(rest)) out.push(n.codes[Number(m[1])])
	if (!out.length) throw new RuleError(`expected a list of patterns, or a constant, in "${rest}"`)
	return out
}

export interface RenderHelp {
	code: (v: unknown) => string
	patterns: (values: unknown[]) => string
	property: (path: Path) => string
}

interface LeafPhrase {
	prose: string
	produces: string
	re: RegExp
	build: (m: RegExpExecArray, n: Norm, path: Path, ctx: Ctx) => Check
	write: (c: Check, h: RenderHelp) => string
}

const val = (n: Norm, i: string | undefined): unknown => literal(n.codes[Number(i)] ?? '')

const LEAVES: LeafPhrase[] = [
	{
		prose: 'the **X** must be present',
		produces: 'present',
		re: /^(?:be present|exist)$/,
		build: (_m, _n, path) => ({op: 'present', path}),
		write: () => `be present`,
	},
	{
		prose: 'the **X** must be a non-empty string',
		produces: 'non_empty_string',
		re: /^be a non-empty string$/,
		build: (_m, _n, path) => ({op: 'non_empty_string', path}),
		write: () => `be a non-empty string`,
	},
	{
		prose: 'the **X** must be `value`',
		produces: 'equals',
		re: new RegExp(`^be ${C}$`),
		build: (m, n, path) => ({op: 'equals', path, value: val(n, m[1])}),
		write: (c, h) => `be ${h.code(c["value"])}`,
	},
	{
		prose: 'the **X** must be between `min` and `max`',
		produces: 'range',
		re: new RegExp(`^be between ${C} and ${C}$`),
		build: (m, n, path) => ({op: 'range', path, min: val(n, m[1]), max: val(n, m[2])}),
		write: (c, h) => `be between ${h.code(c["min"])} and ${h.code(c["max"])}`,
	},
	{
		prose: 'the **X** must include `value`',
		produces: 'includes',
		re: new RegExp(`^include ${C}$`),
		build: (m, n, path) => ({op: 'includes', path, value: val(n, m[1])}),
		write: (c, h) => `include ${h.code(c["value"])}`,
	},
	{
		prose: 'the **X** must not include `value`',
		produces: 'excludes',
		re: new RegExp(`^not include ${C}$`),
		build: (m, n, path) => ({op: 'excludes', path, value: val(n, m[1])}),
		write: (c, h) => `not include ${h.code(c["value"])}`,
	},
	{
		prose: 'the **X** must match one of `pattern`, `pattern` (or a **constant**)',
		produces: 'matches_any',
		re: /^match one of (.+)$/,
		build: (m, n, path, ctx) => ({op: 'matches_any', path, patterns: patternsOf(n, m[1] ?? '', ctx)}),
		write: (c, h) => `match one of ${h.patterns(c["patterns"] as unknown[])}`,
	},
	{
		prose: 'the **X** must match none of `pattern`, `pattern` (or a **constant**)',
		produces: 'not_matches_any',
		re: /^match none of (.+)$/,
		build: (m, n, path, ctx) => ({op: 'not_matches_any', path, patterns: patternsOf(n, m[1] ?? '', ctx)}),
		write: (c, h) => `match none of ${h.patterns(c["patterns"] as unknown[])}`,
	},
	{
		prose: 'the **X** must be greater than / at least / less than / at most the **Y**',
		produces: 'compare',
		re: new RegExp(`^be (equal to|different from|greater than|at least|less than|at most) the ${P}$`),
		build: (m, n, path, ctx) => twoSided(m, n, path, ctx, false),
		write: (c, h) => `be ${phraseFor(String(c["cmp"]), false)} the ${h.property(c["right"] as Path)}`,
	},
	{
		prose: 'the **X** must be after / at or after / before / at or before the **Y**',
		produces: 'compare_time',
		re: new RegExp(`^be (after|at or after|before|at or before) the ${P}$`),
		build: (m, n, path, ctx) => twoSided(m, n, path, ctx, true),
		write: (c, h) => `be ${phraseFor(String(c["cmp"]), true)} the ${h.property(c["right"] as Path)}`,
	},
]

function twoSided(m: RegExpExecArray, n: Norm, path: Path, ctx: Ctx, time: boolean): Check {
	const spec = CMP[m[1] ?? '']
	const right = lookup(ctx, n.props[Number(m[2])] ?? '')
	if (!spec) throw new RuleError(`unknown comparison "${m[1]}"`)
	if (!right) throw new RuleError(`no declared property named "${n.props[Number(m[2])]}"`)
	return {op: time ? 'compare_time' : 'compare', left: path, right: right.path, cmp: spec.cmp}
}

function predicate(n: Norm, rest: string, path: Path, ctx: Ctx): Check {
	for (const entry of LEAVES) {
		const m = entry.re.exec(rest)
		if (m) return entry.build(m, n, path, ctx)
	}
	throw new RuleError(`no operator matches "${rest}"`)
}

export interface Phrase {
	group: string
	prose: string
	produces: string
}

export const LEAF_TABLE: ReadonlyArray<{produces: string; write: (c: Check, h: RenderHelp) => string}> = LEAVES

export const VOCABULARY: Phrase[] = [
	{group: 'Declarations', prose: 'A **thing** is each of `path`, identified by its `path`.', produces: 'subject_type, from, id'},
	{group: 'Declarations', prose: 'a two-column table: property name | `path`', produces: 'the subject\u2019s properties'},
	{group: 'Declarations', prose: '**Name** are ... :  followed by a list of `patterns`', produces: 'a named constant'},
	{group: 'Declarations', prose: 'a named bullet outside any requirement', produces: 'a named substitute'},
	{group: 'Declarations', prose: '## Any heading text `requirement_name`', produces: 'a requirement'},

	{group: 'Per requirement', prose: 'For each **subject**.', produces: 'which subject it is about'},
	{group: 'Per requirement', prose: 'At least one **subject** must be in scope.', produces: 'min_subjects, and the subject'},
	{group: 'Per requirement', prose: 'No minimum \u2014 ...', produces: 'min_subjects: 0'},
	{group: 'Per requirement', prose: 'One **subject** must satisfy all of these.', produces: 'require: some'},
	{group: 'Per requirement', prose: 'In scope:', produces: 'the bullets below are applies_to'},
	{group: 'Per requirement', prose: 'Must hold:', produces: 'the bullets below are checks'},

	...LEAVES.map((l) => ({group: 'Leaf operators', prose: l.prose, produces: l.produces})),

	{group: 'Collections', prose: 'every **X** must have a **Y** of `value`', produces: 'all'},
	{group: 'Collections', prose: 'at least one **X** must ...', produces: 'any'},
	{group: 'Collections', prose: 'some **X** must ...', produces: 'any'},
	{group: 'Collections', prose: 'a property whose path has one `[]` can be quantified; two give the `each` projection', produces: 'all / any with each'},

	{group: 'Modifiers', prose: '..., or else `substitute_name`', produces: 'substitute'},
	{group: 'Modifiers', prose: '..., treating **constant** as explained', produces: 'patterns, for a custom operator'},
	{group: 'Modifiers', prose: 'Records the **X**\u2019 `field`.', produces: 'an extra entry in inputs'},

	{group: 'Anatomy of a rule', prose: '- `name` \u2014 <rule sentence>. <the description.>', produces: 'one check, named, with its description'},
]

function elementCheck(n: Norm, rest: string, ctx: Ctx): Check {
	let m: RegExpExecArray | null
	if ((m = new RegExp(`^have an? ${P} of ${C}$`).exec(rest))) {
		const prop = lookup(ctx, n.props[Number(m[1])] ?? '')
		if (!prop) throw new RuleError(`no declared property named "${n.props[Number(m[1])]}"`)
		return {op: 'equals', path: innerPath(prop), value: literal(n.codes[Number(m[2])] ?? '')}
	}
	if ((m = new RegExp(`^have an? ${P} that must (.+)$`).exec(rest))) {
		const prop = lookup(ctx, n.props[Number(m[1])] ?? '')
		if (!prop) throw new RuleError(`no declared property named "${n.props[Number(m[1])]}"`)
		return predicate(n, m[2] ?? '', innerPath(prop), ctx)
	}
	return predicate(n, rest, [], ctx)
}

export interface Matched {
	check: Check
	op: string
	lead?: string
	head?: string
}

export function matchRule(atoms: Atom[], ctx: Ctx, nearMiss = true): Matched | null {
	const n = normalize(atoms)
	let s = n.s.replace(/\.$/, '')
	let m: RegExpExecArray | null

	const extra: Check = {}

	if ((m = new RegExp(`,? or else ${C}$`).exec(s))) {
		const name = n.codes[Number(m[1])] ?? ''
		const sub = ctx.substitutes.get(name)
		if (!sub) throw new RuleError(`no substitute named "${name}"`)
		extra['substitute'] = sub
		s = s.slice(0, m.index).trim()
	}

	if ((m = new RegExp(`,? treating ${P} as explained$`).exec(s))) {
		const name = (n.props[Number(m[1])] ?? '').toLowerCase().trim()
		const found = ctx.constants.get(name)
		if (!found) throw new RuleError(`no constant named "${name}"`)
		extra['patterns'] = found
		s = s.slice(0, m.index).trim()
	}

	if ((m = new RegExp(`^(?:some|every|at least one|the) ${P} must (.+)$`).exec(s))) {
		const phrase = m[2] ?? ''
		for (const [op, def] of Object.entries(ctx.customOps)) {
			if (def.phrase !== phrase) continue
			const prop = lookup(ctx, n.props[Number(m[1])] ?? '')
			if (!prop) throw new RuleError(`no declared property named "${n.props[Number(m[1])]}"`)
			const path = outerPath(prop)
			return {
				op,
				lead: (/^(some|every|at least one|the)\b/.exec(s) ?? [])[1],
				head: n.props[Number(m[1])],
				check: {
					op,
					expression: def.expression,
					path,
					...extra,
					inputs: def.inputs.map((i) => ('subject' in i ? i.subject : {path, each: i.each})),
				},
			}
		}
	}

	if ((m = new RegExp(`^every ${P} must (.+)$`).exec(s))) {
		const prop = lookup(ctx, n.props[Number(m[1])] ?? '')
		if (!prop) throw new RuleError(`no declared property named "${n.props[Number(m[1])]}"`)
		return {op: 'all', lead: 'every', head: n.props[Number(m[1])], check: {op: 'all', ...collection(prop), check: elementCheck(n, m[2] ?? '', ctx), ...extra}}
	}
	if ((m = new RegExp(`^(?:at least one|some) ${P} must (.+)$`).exec(s))) {
		const prop = lookup(ctx, n.props[Number(m[1])] ?? '')
		if (!prop) throw new RuleError(`no declared property named "${n.props[Number(m[1])]}"`)
		return {op: 'any', lead: (/^(at least one|some)\b/.exec(s) ?? [])[1], head: n.props[Number(m[1])], check: {op: 'any', ...collection(prop), check: elementCheck(n, m[2] ?? '', ctx), ...extra}}
	}

	if ((m = new RegExp(`^the ${P} must (.+)$`).exec(s))) {
		const prop = lookup(ctx, n.props[Number(m[1])] ?? '')
		if (!prop) throw new RuleError(`no declared property named "${n.props[Number(m[1])]}"`)
		const check = predicate(n, m[2] ?? '', prop.path, ctx)
		return {op: String(check['op']), lead: 'the', head: n.props[Number(m[1])], check: {...check, ...extra}}
	}

	if (nearMiss && /\b(?:must|shall|never|always)\b/.test(n.s) && (n.props.length || n.codes.length))
		throw new RuleError(`this looks like a rule but matches no operator: "${n.s}"`)

	return null
}

function collection(prop: PropertyDef): Check {
	if (prop.splits.length >= 2)
		return {
			path: prop.path.slice(0, prop.splits[0]),
			each: prop.path.slice(prop.splits[0], prop.splits[1]),
		}
	return {path: outerPath(prop)}
}

export function matchRecords(atoms: Atom[], ctx: Ctx): Check | null {
	const n = normalize(atoms)
	const m = new RegExp(`^Records the ${P}'?s? ${C}\\.?$`).exec(n.s)
	if (!m) return null
	const prop = lookup(ctx, n.props[Number(m[1])] ?? '')
	if (!prop) throw new RuleError(`no declared property named "${n.props[Number(m[1])]}"`)
	return {path: outerPath(prop), each: [n.codes[Number(m[2])] ?? '']}
}
