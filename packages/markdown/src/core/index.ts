import {fromMarkdown} from 'mdast-util-from-markdown'
import {gfmTable} from 'micromark-extension-gfm-table'
import {gfmTableFromMarkdown} from 'mdast-util-gfm-table'

import type {Analysis, Anchor, Block, Check, CustomOpRegistry, Diagnostic, DocContext, PropertyDef, SubjectDef, SubjectSummary} from './types.ts'
import {type Atom, type Ctx, RuleError, atomize, matchRecords, matchRule, plain, sentences} from './grammar.ts'
import {parseConstantHead, parseSubject, parseTable} from './declare.ts'
import {validateRequirements} from './validate.ts'
import {renderDeclared, renderPath} from './paths.ts'
import {contextFor, writeCheck} from './render.ts'

interface Node {
	type: string
	depth?: number
	value?: string
	children?: Node[]
	position?: {start: {line: number; column: number; offset?: number}; end: {line: number; offset?: number}}
}

const subjectKey = (s: string): string => s.toLowerCase().replace(/\*/g, '').replace(/\s+/g, ' ').trim()

const lineOf = (n: Node): number => n.position?.start.line ?? 0
const endOf = (n: Node): number => n.position?.end.line ?? lineOf(n)
const from = (n: Node): number => n.position?.start.offset ?? 0
const to = (n: Node): number => n.position?.end.offset ?? from(n)
const indentOf = (n: Node): string => ' '.repeat((n.position?.start.column ?? 1) - 1)

function textOf(n: Node): string {
	if (n.type === 'text' || n.type === 'inlineCode') return n.value ?? ''
	return (n.children ?? []).map(textOf).join('')
}

interface SubjectEntry {
	def: SubjectDef
	props: Map<string, PropertyDef>
}

interface Req {
	name: string
	line: number
	depth: number
	subject: SubjectEntry | null
	subjectName: string | null
	minSubjects?: number
	require?: string
	appliesTo: Record<string, Check>
	checks: Record<string, Check>
}

export function analyze(markdown: string, opts: {customOps?: CustomOpRegistry} = {}): Analysis {
	const tree = fromMarkdown(markdown, {
		extensions: [gfmTable()],
		mdastExtensions: [gfmTableFromMarkdown()],
	}) as unknown as Node
	const nodes = tree.children ?? []

	const blocks: Block[] = []
	const anchors: Anchor[] = []
	const diagnostics: Diagnostic[] = []
	const subjects = new Map<string, SubjectEntry>()
	const allProps = new Map<string, PropertyDef>()
	const ctx: Ctx = {
		props: allProps,
		constants: new Map<string, unknown[]>(),
		substitutes: new Map<string, Check>(),
		customOps: opts.customOps ?? {},
	}
	const customOpNames = new Set(Object.keys(ctx.customOps))

	const err = (line: number, message: string): number => diagnostics.push({severity: 'error', line, message})
	const warn = (line: number, message: string): number => diagnostics.push({severity: 'warning', line, message})
	const claimed = new Set<number>()
	const claim = (i: number, block: Block): void => {
		claimed.add(i)
		blocks.push(block)
	}

	const readRule = (item: Node): {name: string; check: Check; lead?: string; head?: string} | null => {
		const para = (item.children ?? [])[0]
		if (!para) return null
		const atoms = atomize((para.children ?? []) as never[])
		const line = lineOf(para)

		let rest = atoms
		let name = ''
		if (atoms[0]?.kind === 'code') {
			name = atoms[0].text
			rest = atoms.slice(1)
			const sep = rest[0]
			if (sep && sep.kind === 'text') rest = [{kind: 'text', text: sep.text.replace(/^\s*[\u2014\u2013-]\s*/, '')}, ...rest.slice(1)]
		}
		if (!name) {
			err(line, 'a rule needs a name: put it in backticks at the start of the bullet')
			return null
		}

		const sents = sentences(rest)
		const first = sents[0]
		if (!first) {
			err(line, `${name}: no rule sentence`)
			return null
		}

		let matched
		try {
			matched = matchRule(first, ctx, false)
		} catch (e) {
			err(line, `${name}: ${(e as Error).message}`)
			return null
		}
		if (!matched) {
			err(line, `${name}: "${plain(first)}" matches no operator`)
			return null
		}

		const check: Check = {...matched.check}
		const descriptions: string[] = []
		for (const sentence of sents.slice(1)) {
			let record: Check | null = null
			try {
				record = matchRecords(sentence, ctx)
			} catch (e) {
				err(line, `${name}: ${(e as Error).message}`)
			}
			if (record) {
				check['inputs'] = [...((check['inputs'] as unknown[]) ?? []), record]
				continue
			}
			descriptions.push(plain(sentence))
		}
		const description = descriptions.join(' ').trim().replace(/\.$/, '')
		if (description) check['description'] = description

		return {name, check, ...(matched.lead ? {lead: matched.lead} : {}), ...(matched.head ? {head: matched.head} : {})}
	}

	const reqs: Req[] = []
	const owner: Array<Req | null> = new Array(nodes.length).fill(null)
	{
		let open: Req | null = null
		nodes.forEach((node, i) => {
			if (node.type === 'heading') {
				const depth = node.depth ?? 1
				const kids = node.children ?? []
				const last = kids[kids.length - 1]
				if (last?.type === 'inlineCode') {
					const label = textOf(node).trim()
					open = {
						name: last.value ?? '',
						line: lineOf(node),
						depth,
						subject: null,
						subjectName: null,
						appliesTo: {},
						checks: {},
					}
					reqs.push(open)
					owner[i] = open
					claim(i, {
						kind: 'requirement',
						line: lineOf(node),
						endLine: endOf(node),
						label: open.name,
						detail: label.replace(/\s*`?[\w-]+`?$/, '').trim(),
					})
					return
				}
				if (open && depth <= open.depth) open = null
			}
			owner[i] = open
		})
	}

	let lastSubject: SubjectEntry | null = null
	let pendingConstant: {name: string; at: number; line: number} | null = null

	nodes.forEach((node, i) => {
		if (node.type === 'paragraph') {
			const atoms = atomize((node.children ?? []) as never[])

			const parsed = parseSubject(atoms, lineOf(node))
			if (parsed) {
				const key = subjectKey(parsed.subjectType)
				if (subjects.has(key)) err(lineOf(node), `a subject named "${parsed.subjectType}" is already declared`)
				lastSubject = {def: parsed, props: new Map<string, PropertyDef>()}
				subjects.set(key, lastSubject)
				pendingConstant = null
				claim(i, {
					kind: 'subject',
					line: lineOf(node),
					endLine: endOf(node),
					label: parsed.subjectType,
					detail: `from=${renderPath(parsed.from)} id=${renderPath(parsed.id)}`,
				})
				return
			}

			const name = parseConstantHead(atoms)
			if (name && isPatternList(nodes[i + 1])) {
				pendingConstant = {name, at: i, line: lineOf(node)}
				claim(i, {kind: 'constant', line: lineOf(node), endLine: endOf(node), label: name})
				return
			}
			pendingConstant = null
			return
		}

		if (node.type === 'table') {
			if (!isPropertyTable(node)) return
			const rows = (node.children ?? []) as {children?: {children?: unknown[]}[]}[]
			try {
				const parsed = parseTable(rows, (c) => textOf(c as Node))
				if (!lastSubject) err(lineOf(node), 'declare a subject before its properties')
				for (const [k, v] of parsed) {
					lastSubject?.props.set(k, v)
					allProps.set(k, v)
				}
				claim(i, {
					kind: 'properties',
					line: lineOf(node),
					endLine: endOf(node),
					label: lastSubject?.def.subjectType,
					detail: `${parsed.size} properties`,
				})
				if (lastSubject) anchors.push({kind: 'table', name: lastSubject.def.subjectType, start: from(node), end: to(node)})
			} catch (e) {
				err(lineOf(node), (e as Error).message)
			}
			pendingConstant = null
			return
		}

		if (node.type === 'list' && pendingConstant && pendingConstant.at === i - 1) {
			const patterns = (node.children ?? []).map((item) => plain(atomize(((item.children ?? [])[0]?.children ?? []) as never[])))
			ctx.constants.set(pendingConstant.name, patterns)
			claim(i, {
				kind: 'constant',
				line: lineOf(node),
				endLine: endOf(node),
				label: pendingConstant.name,
				detail: `${patterns.length} patterns`,
			})
			pendingConstant = null
			return
		}

		if (node.type !== 'list') pendingConstant = null
	})

	nodes.forEach((node, i) => {
		if (node.type !== 'list' || owner[i] || claimed.has(i)) return
		if (isPatternList(node)) {
			err(lineOf(node), 'a list of patterns has to come straight after the sentence that names the constant, with nothing between them')
			claimed.add(i)
			return
		}
		if (!(node.children ?? []).some(isNamedBullet)) return
		for (const item of node.children ?? []) {
			const parsed = readRule(item)
			if (!parsed) continue
			ctx.substitutes.set(parsed.name, parsed.check)
			blocks.push({
				kind: 'substitute',
				line: lineOf(item),
				endLine: endOf(item),
				label: parsed.name,
				op: String(parsed.check['op']),
			})
			anchors.push({kind: 'substitute', name: parsed.name, start: from(item), end: to(item), indent: indentOf(item), ...(parsed.lead ? {lead: parsed.lead} : {}), ...(parsed.head ? {head: parsed.head} : {})})
		}
		claimed.add(i)
	})

	const soleSubject = (): SubjectEntry | null => (subjects.size === 1 ? [...subjects.values()][0]! : null)

	for (const r of reqs) {
		const mine = nodes.map((n, i) => [n, i] as const).filter(([, i]) => owner[i] === r)

		for (const [node] of mine) {
			if (node.type !== 'paragraph') continue
			const atoms = atomize((node.children ?? []) as never[])
			const bound = /^(?:For|About) each /i.test(plain(atoms)) || /must be in scope\.?$/i.test(plain(atoms))
			if (!bound) continue
			const key = subjectKey(atoms.find((a) => a.kind === 'prop')?.text ?? '')
			if (subjects.has(key)) r.subjectName = key
		}
		const headingNode = nodes.find((n) => n.type === 'heading' && lineOf(n) === r.line)
		const owned = mine.map(([n]) => n)
		anchors.push({
			kind: 'requirement',
			requirement: r.name,
			name: r.name,
			start: headingNode ? from(headingNode) : (owned[0] ? from(owned[0]) : 0),
			end: owned.length ? Math.max(...owned.map(to)) : (headingNode ? to(headingNode) : 0),
			insertAt: headingNode ? to(headingNode) : (owned[0] ? from(owned[0]) : 0),
		})
		r.subject = (r.subjectName ? subjects.get(r.subjectName) : null) ?? soleSubject()
		ctx.props = r.subject ? r.subject.props : allProps

		let role: 'scope' | 'checks' | null = null

		for (const [node, i] of mine) {
			if (claimed.has(i)) continue
			const line = lineOf(node)

			if (node.type === 'paragraph') {
				const atoms = atomize((node.children ?? []) as never[])
				const text = plain(atoms)
				let m: RegExpExecArray | null

				if (/^In scope:?$/i.test(text)) {
					role = 'scope'
					claim(i, {kind: 'directive', line, endLine: endOf(node), detail: 'applies_to follows'})
					anchors.push({kind: 'directive', requirement: r.name, name: 'applies_to:lead', start: from(node), end: to(node)})
					continue
				}
				if (/^Must hold:?$/i.test(text)) {
					role = 'checks'
					claim(i, {kind: 'directive', line, endLine: endOf(node), detail: 'checks follow'})
					anchors.push({kind: 'directive', requirement: r.name, name: 'checks:lead', start: from(node), end: to(node)})
					continue
				}
				if (/^(?:For|About) each /i.test(text) && r.subject) {
					claim(i, {kind: 'directive', line, endLine: endOf(node), detail: `subject: ${r.subject.def.subjectType}`})
					anchors.push({kind: 'directive', requirement: r.name, name: 'subject', start: from(node), end: to(node)})
					continue
				}
				if ((m = /^At least (\d+|one) \S.* must be in scope\.?$/i.exec(text))) {
					r.minSubjects = m[1] === 'one' ? 1 : Number(m[1])
					claim(i, {kind: 'directive', line, endLine: endOf(node), detail: `min_subjects: ${r.minSubjects}`})
					anchors.push({kind: 'directive', requirement: r.name, name: 'min_subjects', start: from(node), end: to(node)})
					continue
				}
				if (/^No minimum\b/i.test(text)) {
					r.minSubjects = 0
					claim(i, {kind: 'directive', line, endLine: endOf(node), detail: 'min_subjects: 0'})
					anchors.push({kind: 'directive', requirement: r.name, name: 'min_subjects', start: from(node), end: to(node)})
					continue
				}
				if (/^One \S.* must satisfy all of these\.?$/i.test(text)) {
					r.require = 'some'
					claim(i, {kind: 'directive', line, endLine: endOf(node), detail: 'require: some'})
					anchors.push({kind: 'directive', requirement: r.name, name: 'require', start: from(node), end: to(node)})
					continue
				}
				continue
			}

			if (node.type === 'list') {
				if (!(node.children ?? []).some(isNamedBullet)) continue
				if (!role) {
					err(line, `${r.name}: say what these are before the list — "Must hold:" for checks, "In scope:" for a scope filter`)
					claimed.add(i)
					continue
				}
				const field = role === 'scope' ? 'applies_to' : 'checks'
				let indent = ''
				for (const item of node.children ?? []) {
					const parsed = readRule(item)
					if (!parsed) continue
					const target = role === 'scope' ? r.appliesTo : r.checks
					if (target[parsed.name]) err(lineOf(item), `${parsed.name}: already defined in this requirement`)
					target[parsed.name] = parsed.check
					indent = indentOf(item)
					blocks.push({
						kind: role === 'scope' ? 'scope' : 'rule',
						line: lineOf(item),
						endLine: endOf(item),
						label: parsed.name,
						op: String(parsed.check['op']),
					})
					anchors.push({
						kind: role === 'scope' ? 'scope' : 'rule',
						requirement: r.name,
						name: parsed.name,
						start: from(item),
						end: to(item),
						indent: indentOf(item),
						...(parsed.lead ? {lead: parsed.lead} : {}),
						...(parsed.head ? {head: parsed.head} : {}),
					})
				}
				anchors.push({kind: 'list', requirement: r.name, name: field, start: from(node), end: to(node), indent})
				claimed.add(i)
			}
		}
	}

	ctx.props = allProps
	nodes.forEach((node, i) => {
		if (claimed.has(i)) return
		const atoms = node.type === 'heading' || node.type === 'paragraph' ? atomize((node.children ?? []) as never[]) : []
		if (node.type === 'paragraph')
			for (const sentence of sentences(atoms)) {
				try {
					matchRule(sentence, ctx, true)
				} catch (e) {
					if (e instanceof RuleError) warn(lineOf(node), e.message)
				}
			}
		blocks.push({
			kind: 'prose',
			line: lineOf(node),
			endLine: endOf(node),
			detail: atoms.length ? plain(atoms).slice(0, 90) : node.type,
		})
	})

	blocks.sort((a, b) => a.line - b.line || a.endLine - b.endLine)

	const requirements: Record<string, unknown> = {}
	if (subjects.size === 0) err(0, 'no subject declared: say `A **thing** is each of `path`, identified by its `path`.`')

	for (const r of reqs) {
		if (!Object.keys(r.checks).length) {
			err(r.line, `${r.name}: declares no checks, so it asserts nothing`)
			continue
		}
		if (!r.subject && subjects.size > 1) {
			err(r.line, `${r.name}: several subjects are declared, so say which one this is about — \`For each **${[...subjects.values()][0]!.def.subjectType}**.\``)
			continue
		}
		const out: Record<string, unknown> = {}
		const subject = r.subject?.def
		if (subject) {
			out['subject_type'] = subject.subjectType
			out['from'] = subject.from
			out['id'] = subject.id
		}
		if (r.minSubjects !== undefined) out['min_subjects'] = r.minSubjects
		if (r.require !== undefined) out['require'] = r.require
		if (Object.keys(r.appliesTo).length) out['applies_to'] = r.appliesTo
		out['checks'] = r.checks
		requirements[r.name] = out
	}

	diagnostics.push(...validateRequirements(requirements, customOpNames))

	const context: DocContext = {
		constants: Object.fromEntries(ctx.constants),
		substitutes: Object.fromEntries(ctx.substitutes),
		properties: Object.fromEntries(reqs.map((r) => [r.name, [...(r.subject?.props ?? allProps).values()]])),
		all: [...allProps.values()],
		subjectOf: Object.fromEntries(reqs.filter((r) => r.subject).map((r) => [r.name, r.subject!.def.subjectType])),
	}

	const read = new Set<PropertyDef>()
	const noteReads = (owner: string, check: Check): void => {
		const seen = contextFor(context, owner, ctx.customOps)
		seen.record = (p) => read.add(p)
		try {
			writeCheck(seen, check)
		} catch {
		}
	}
	for (const [name, body] of Object.entries(requirements))
		for (const field of ['checks', 'applies_to'])
			for (const check of Object.values(((body as Record<string, unknown>)[field] ?? {}) as Record<string, Check>)) noteReads(name, check)
	for (const check of ctx.substitutes.values()) noteReads('\u0000document', check)

	const summaries: SubjectSummary[] = [...subjects.values()].map((e) => ({
		name: e.def.subjectType,
		subjectType: e.def.subjectType,
		from: e.def.from,
		id: e.def.id,
		line: e.def.line,
		properties: [...e.props.values()].map((p) => ({
			display: p.display,
			path: p.path,
			pathText: renderDeclared(p.path, p.splits),
			line: p.line,
			used: read.has(p),
		})),
	}))

	anchors.sort((a, b) => a.start - b.start)

	return {
		blocks,
		anchors,
		context,
		subjects: summaries,
		substitutes: [...ctx.substitutes.keys()],
		constants: [...ctx.constants.keys()],
		requirements,
		diagnostics,
		ok: !diagnostics.some((d) => d.severity === 'error'),
	}
}

function isNamedBullet(item: Node): boolean {
	const para = (item.children ?? [])[0]
	return (para?.children ?? [])[0]?.type === 'inlineCode'
}

function isPatternList(node: Node | undefined): boolean {
	if (!node || node.type !== 'list') return false
	const items = node.children ?? []
	if (!items.length) return false
	return items.every((item) => {
		const kids = ((item.children ?? [])[0]?.children ?? []) as Node[]
		return kids.length === 1 && kids[0]?.type === 'inlineCode'
	})
}

function isPropertyTable(node: Node): boolean {
	const rows = (node.children ?? []).slice(1)
	if (!rows.length) return false
	return rows.some((row) => {
		const cells = row.children ?? []
		return cells.length >= 2 && ((cells[1]?.children ?? []) as Node[]).some((c) => c.type === 'inlineCode')
	})
}

export type {Analysis, Block, Diagnostic} from './types.ts'
export {VOCABULARY, type Phrase} from './grammar.ts'
export {validateRequirements} from './validate.ts'
