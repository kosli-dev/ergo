import type {Check, CustomOpRegistry, DocContext, Path, PropertyDef} from './types.ts'
import {fromMarkdown} from 'mdast-util-from-markdown'
import {literal, renderDeclared, renderPath} from './paths.ts'
import {atomize, plain} from './grammar.ts'
import {LEAF_TABLE, type RenderHelp, RuleError, outerPath, innerPath} from './grammar.ts'

export interface RenderCtx {
	props: PropertyDef[]
	constants: Record<string, unknown[]>
	substitutes: Record<string, Check>
	customOps: CustomOpRegistry
	invent?: (path: Path, splits: number[]) => PropertyDef
	record?: (prop: PropertyDef) => void
}

export function contextFor(doc: DocContext, requirement: string, customOps: CustomOpRegistry): RenderCtx {
	return {
		props: [...(doc.properties[requirement] ?? doc.all)],
		constants: doc.constants,
		substitutes: doc.substitutes,
		customOps,
	}
}

const same = (a: unknown, b: unknown): boolean => JSON.stringify(a) === JSON.stringify(b)

function names(prop: PropertyDef, written: string | undefined): boolean {
	if (!written) return false
	const norm = (t: string): string => t.toLowerCase().replace(/\s+/g, ' ').trim()
	const a = norm(written)
	const b = norm(prop.display)
	return a === b || a + 's' === b || a === b + 's'
}

const spell = (prop: PropertyDef, written?: string): string => bold(names(prop, written) ? written! : prop.display)

export function code(v: unknown): string {
	const text = v === null ? 'null' : String(v)
	if (!text.includes('`')) return `\`${text}\``
	return `\`\` ${text} \`\``
}

export function prose(text: string): string {
	const light = text.replace(/[\\`*_[\]<&]/g, (c) => `\\${c}`)
	if (readsBack(light, text)) return light
	const heavy = text.replace(/[!-/:-@[-`{-~]/g, (c) => `\\${c}`)
	if (readsBack(heavy, text)) return heavy
	throw new RuleError('this description cannot be written as Markdown without changing what it says')
}

function readsBack(markdown: string, want: string): boolean {
	const tree = fromMarkdown(markdown) as {children?: Array<{children?: unknown[]}>}
	const para = (tree.children ?? [])[0]
	if (!para || (tree.children ?? []).length !== 1) return false
	return plain(atomize((para.children ?? []) as never[])) === want
}

export function value(v: unknown): string {
	const text = v === null ? 'null' : String(v)
	const written = text.includes('`') ? `\`\` ${text} \`\`` : `\`${text}\``
	const back = readCode(written)
	if (back === null) throw new RuleError(`the value ${JSON.stringify(text)} cannot be written as a code span`)
	const read = literal(back)
	if (read !== v)
		throw new RuleError(
			typeof read !== typeof v
				? `the value \`${back}\` would be read back as ${read === null ? 'null' : typeof read}, not ${typeof v} — prose writes a bare token, so a ${typeof v} that looks like ${read === null ? 'null' : `a ${typeof read}`} has no spelling`
				: `the value ${JSON.stringify(text)} would be read back as ${JSON.stringify(String(read))}`,
		)
	return written
}

function readCode(markdown: string): string | null {
	const tree = fromMarkdown(markdown) as {children?: Array<{children?: Array<{type: string; value?: string}>}>}
	const kids = (tree.children ?? [])[0]?.children ?? []
	if ((tree.children ?? []).length !== 1 || kids.length !== 1 || kids[0]?.type !== 'inlineCode') return null
	return kids[0].value ?? ''
}

const bold = (display: string): string => `**${display}**`
const article = (word: string): string => (/^[aeiou]/i.test(word) ? 'an' : 'a')

function property(ctx: RenderCtx, path: Path): PropertyDef {
	const found = ctx.props.find((p) => same(p.path, path))
	return found ? use(ctx, found) : declare(ctx, path, [], renderPath(path))
}

function use(ctx: RenderCtx, prop: PropertyDef): PropertyDef {
	ctx.record?.(prop)
	return prop
}

function declare(ctx: RenderCtx, path: Path, splits: number[], shown: string): PropertyDef {
	for (const seg of path)
		if (typeof seg === 'string' && /[|`.[\]\n]/.test(seg))
			throw new RuleError(`the path segment \`${seg}\` cannot be declared: a table cell holds it as a code span, and \` . [ ] |\` all mean something there`)
	if (!ctx.invent) throw new RuleError(`no declared property has the path \`${shown}\` — add a row to the Subjects table first`)
	const made = ctx.invent(path, splits)
	ctx.props.push(made)
	return use(ctx, made)
}

function patternsClause(ctx: RenderCtx, values: unknown[]): string {
	for (const [name, held] of Object.entries(ctx.constants)) if (same(held, values)) return bold(name)
	return values.map(code).join(', ')
}

function help(ctx: RenderCtx): RenderHelp {
	return {
		code: value,
		patterns: (values) => patternsClause(ctx, values),
		property: (path) => bold(property(ctx, path).display),
	}
}

function predicate(ctx: RenderCtx, check: Check): string {
	const row = LEAF_TABLE.find((l) => l.produces === check['op'])
	if (!row) throw new RuleError(`no prose writes the operator "${String(check['op'])}"`)
	return row.write(check, help(ctx))
}

function element(ctx: RenderCtx, outer: PropertyDef, inner: Check): string {
	const path = (inner['path'] ?? inner['left'] ?? []) as Path
	if (!path.length) return predicate(ctx, inner)

	const stem = outerPath(outer)
	const held = ctx.props.find((p) => same(innerPath(p), path) && startsWith(p.path, stem))
	const prop = held ? use(ctx, held) : declare(ctx, [...stem, ...path], [stem.length], renderDeclared([...stem, ...path], [stem.length]))

	if (inner['op'] === 'equals' && !('substitute' in inner))
		return `have ${article(prop.display)} ${bold(prop.display)} of ${value(inner['value'])}`
	return `have ${article(prop.display)} ${bold(prop.display)} that must ${predicate(ctx, {...inner, path: []} as Check)}`
}

const startsWith = (path: Path, prefix: Path): boolean => same(path.slice(0, prefix.length), prefix)

function substituteName(ctx: RenderCtx, sub: unknown): string {
	for (const [name, held] of Object.entries(ctx.substitutes)) if (same(held, sub)) return name
	throw new RuleError('a substitute that is not declared in the document cannot be written as prose')
}

function records(ctx: RenderCtx, entry: unknown): string {
	const e = entry as {path?: Path; each?: string[]}
	if (!e || !e.path || !e.each || e.each.length !== 1) throw new RuleError('an input that is not a single projection cannot be written as prose')
	const held = ctx.props.find((p) => same(outerPath(p), e.path))
	const prop = held ? use(ctx, held) : declare(ctx, e.path, [], renderPath(e.path))
	const possessive = prop.display.endsWith('s') ? "'" : "'s"
	return `Records the ${bold(prop.display)}${possessive} ${code(e.each[0])}.`
}

function derivedInputs(ctx: RenderCtx, op: string, path: Path): unknown[] {
	const def = ctx.customOps[op]
	if (!def) return []
	return def.inputs.map((i) => ('subject' in i ? i.subject : {path, each: i.each}))
}

export interface Written {
	rule: string
	records: string[]
	description: string
}

export function writeCheck(ctx: RenderCtx, check: Check, lead?: string, head?: string): Written {
	const c = {...check}
	const description = typeof c['description'] === 'string' ? c['description'] : ''
	delete c['description']
	if (/\.\s*$/.test(description))
		throw new RuleError('a description is a phrase, not a sentence — drop the trailing full stop, the writer adds one')

	let tail = ''
	if ('substitute' in c) {
		const name = substituteName(ctx, c['substitute'])
		tail = `, or else ${code(name)}` + tail
		delete c['substitute']
	}

	const op = String(c['op'])
	const custom = ctx.customOps[op]
	const extraInputs: unknown[] = []

	if (custom) {
		const path = (c['path'] ?? []) as Path
		if (c['patterns']) {
			let named: string | null = null
			for (const [name, held] of Object.entries(ctx.constants)) if (same(held, c['patterns'])) named = name
			if (!named) throw new RuleError(`the patterns on "${op}" are not a declared constant`)
			tail = `, treating ${bold(named)} as explained` + tail
		}
		if (c['expression'] !== custom.expression)
			throw new RuleError(`"${op}" carries an \`expression\` the registry does not define — a custom operator's expression comes from the custom operators file, not from the spec`)
		const derived = derivedInputs(ctx, op, path)
		const inputs = (c['inputs'] ?? []) as unknown[]
		if (!same(inputs.slice(0, derived.length), derived))
			throw new RuleError(`"${op}" reads \`inputs\` the registry does not derive from its \`path\` — a custom operator's inputs follow its path, so the two have to move together`)
		extraInputs.push(...inputs.slice(derived.length))
		const held = ctx.props.find((p) => same(outerPath(p), path))
		const prop = held ? use(ctx, held) : declare(ctx, path, [], renderPath(path))
		return {rule: `${lead ?? 'some'} ${spell(prop, head)} must ${custom.phrase}${tail}`, records: extraInputs.map((e) => records(ctx, e)), description}
	}

	if (c['inputs']) extraInputs.push(...(c['inputs'] as unknown[]))
	const rendered = extraInputs.map((e) => records(ctx, e))

	if (op === 'all' || op === 'any') {
		const path = (c['path'] ?? []) as Path
		const each = c['each'] as Path | undefined
		const found = ctx.props.find((p) =>
			each
				? p.splits.length >= 2 && same(p.path.slice(0, p.splits[0]), path) && same(p.path.slice(p.splits[0], p.splits[1]), each)
				: p.splits.length < 2 && same(outerPath(p), path),
		)
		const shape: [Path, number[]] = each ? [[...path, ...each], [path.length, path.length + each.length]] : [path, []]
		const prop = found ? use(ctx, found) : declare(ctx, shape[0], shape[1], renderDeclared(shape[0], shape[1]))
		const quantifier = op === 'all' ? 'every' : (lead ?? 'some')
		return {rule: `${quantifier} ${spell(prop, head)} must ${element(ctx, prop, (c['check'] ?? {}) as Check)}${tail}`, records: rendered, description}
	}

	const path = (c['path'] ?? c['left'] ?? []) as Path
	const prop = property(ctx, path)
	return {rule: `the ${spell(prop, head)} must ${predicate(ctx, c)}${tail}`, records: rendered, description}
}

export function writeBullet(ctx: RenderCtx, name: string, check: Check, indent = '', lead?: string, head?: string): string {
	const {rule, records: recorded, description} = writeCheck(ctx, check, lead, head)
	const sentences = [`${code(name)} — ${rule}.`, ...recorded]
	if (description) sentences.push(`${prose(description)}.`)
	return wrap(sentences.join(' '), indent)
}

export function wrap(text: string, indent: string, width = 78): string {
	const tokens: string[] = []
	let buf = ''
	for (let i = 0; i < text.length; ) {
		const ch = text[i]!
		if (ch === '`') {
			const fence = /^`+/.exec(text.slice(i))![0]
			const close = text.indexOf(fence, i + fence.length)
			const end = close < 0 ? text.length : close + fence.length
			buf += text.slice(i, end)
			i = end
			continue
		}
		if (/\s/.test(ch)) {
			if (buf) tokens.push(buf)
			buf = ''
			i++
			continue
		}
		buf += ch
		i++
	}
	if (buf) tokens.push(buf)

	const startsBlock = (t: string): boolean => /^(?:[-+>#]|\d+[.)])/.test(t)

	const lines: string[] = []
	let line = `${indent}- `
	let empty = true
	for (const token of tokens) {
		if (!empty && line.length + 1 + token.length > width && !startsBlock(token)) {
			lines.push(line)
			line = `${indent}  `
			empty = true
		}
		line += empty ? token : ` ${token}`
		empty = false
	}
	lines.push(line)
	return lines.join('\n')
}
