#!/usr/bin/env node
import {execFileSync} from 'node:child_process'
import {readFileSync, writeFileSync} from 'node:fs'
import {dirname, join} from 'node:path'
import {fileURLToPath} from 'node:url'
import {parse as parseYaml, stringify as toYaml} from 'yaml'

import {analyze} from './core/index.ts'
import {applyRequirements, differences} from './core/patch.ts'
import {validateRequirements} from './core/validate.ts'
import type {Analysis, Check, CustomOpRegistry, Diagnostic} from './core/types.ts'
import {renderPath} from './core/paths.ts'

const HERE = dirname(fileURLToPath(import.meta.url))

const USAGE = `usage:
  ergo compile <policy.ergo.md> [-o <requirements.yaml>]
  ergo check <policy.ergo.md> [<requirements.yaml>]
  ergo explain <policy.ergo.md>
  ergo lint <requirements.yaml>
  ergo apply <policy.ergo.md> <requirements.yaml>

options:
  --ops <custom_ops.json>   describe your custom operators
`

const COMMANDS = ['compile', 'check', 'explain', 'lint', 'apply']

interface Args {
	command: string
	files: string[]
	out?: string
	ops?: string
}

function parseArgs(argv: string[]): Args | string {
	const [command = '', ...rest] = argv
	const files: string[] = []
	let out: string | undefined
	let ops: string | undefined
	for (let i = 0; i < rest.length; i++) {
		const arg = rest[i]!
		if (arg === '-o' || arg === '--ops') {
			const value = rest[++i]
			if (!value) return `${arg} needs a file`
			if (arg === '-o') out = value
			else ops = value
			continue
		}
		if (arg.startsWith('-')) return `unknown option ${arg}`
		files.push(arg)
	}
	return {command, files, ...(out ? {out} : {}), ...(ops ? {ops} : {})}
}

function registry(file: string | undefined): CustomOpRegistry {
	if (!file) return {}
	return JSON.parse(readFileSync(file, 'utf8')) as CustomOpRegistry
}

const yamlOf = (requirements: unknown): string => toYaml({requirements}, {lineWidth: 0})

function report(diagnostics: Diagnostic[], file: string): void {
	for (const d of diagnostics) {
		const where = d.line ? `${file}:${d.line}` : file
		process.stderr.write(`${d.severity}: ${where}: ${d.message}\n`)
	}
}

function renderedExpressions(requirements: Record<string, unknown>): Map<string, string> {
	const out = new Map<string, string>()
	try {
		const library = join(HERE, '..', '..', '..', 'ergo.rego')
		const raw = execFileSync('opa', ['eval', '-d', library, '-I', '--format=json', 'data.ergo.report(input.doc, input.req)'], {
			input: JSON.stringify({doc: {}, req: requirements}),
			encoding: 'utf8',
			stdio: ['pipe', 'pipe', 'ignore'],
		})
		const value = JSON.parse(raw).result?.[0]?.expressions?.[0]?.value as
			| {requirements?: Record<string, {checks?: Record<string, {expression?: string}>}>}
			| undefined
		for (const [rname, req] of Object.entries(value?.requirements ?? {}))
			for (const [cname, check] of Object.entries(req.checks ?? {}))
				if (check.expression) out.set(`${rname}.${cname}`, check.expression)
	} catch {
		return out
	}
	return out
}

function shape(check: Check): string {
	const op = String(check['op'])
	const path = Array.isArray(check['path']) ? renderPath(check['path'] as never) : ''
	if (op === 'all' || op === 'any') return `${op} ${path} -> ${shape(check['check'] as Check)}`
	if (check['value'] !== undefined) return `${path} == ${String(check['value'])}`
	return `${op} ${path}`.trim()
}

function explain(result: Analysis, file: string): void {
	const blocks = result.blocks
	process.stdout.write(`${file}\n\n`)
	const rendered = renderedExpressions(result.requirements as Record<string, unknown>)
	const shapes = new Map<string, string>()
	for (const req of Object.values(result.requirements as Record<string, Record<string, unknown>>))
		for (const group of ['checks', 'applies_to'])
			for (const [name, check] of Object.entries((req[group] ?? {}) as Record<string, Check>)) shapes.set(name, shape(check))
	const width = Math.max(...blocks.map((b) => String(b.line).length), 2)
	let requirement = ''

	for (const b of blocks) {
		if (b.kind === 'requirement') requirement = b.label ?? ''
		const line = `L${String(b.line).padStart(width)}`
		const head = `  ${line}  ${b.kind.padEnd(12)}`

		if (b.kind === 'prose') {
			const snippet = (b.detail ?? '').replace(/\s+/g, ' ').trim()
			if (!snippet) continue
			process.stdout.write(`${head}${snippet.length > 56 ? snippet.slice(0, 53) + '...' : snippet}\n`)
			continue
		}

		process.stdout.write(`${head}${b.label ?? ''}${b.op ? `  ${b.op}` : ''}\n`)

		const isCheck = b.kind === 'rule' || b.kind === 'scope' || b.kind === 'substitute'
		const expr = isCheck ? (rendered.get(`${requirement}.${b.label}`) ?? shapes.get(b.label ?? '')) : undefined
		const detail = expr ? `"${expr}"` : isCheck ? '' : b.detail
		if (detail) process.stdout.write(`  ${' '.repeat(width + 14)}${detail}\n`)
	}

	const n = (k: string): number => blocks.filter((b) => b.kind === k).length
	const near = result.diagnostics.filter((d) => d.severity === 'warning').length
	const plural = (c: number, word: string): string => `${c} ${word}${c === 1 ? '' : 's'}`
	process.stdout.write(
		`\n  ${plural(n('rule'), 'check')}, ${plural(n('scope'), 'scope filter')}, ` +
			`${plural(n('substitute'), 'substitute')}, ` +
			`${plural(near, 'unclaimed sentence')} that look like rules\n`,
	)
}

function canonical(value: unknown): string {
	if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`
	if (value && typeof value === 'object')
		return `{${Object.keys(value)
			.sort()
			.map((k) => `${JSON.stringify(k)}:${canonical((value as Record<string, unknown>)[k])}`)
			.join(',')}}`
	return JSON.stringify(value)
}

function diffChecks(before: unknown, after: unknown): {lost: string[]; added: string[]; changed: string[]} {
	const flat = (o: unknown): Map<string, string> => {
		const out = new Map<string, string>()
		for (const [rname, req] of Object.entries((o ?? {}) as Record<string, Record<string, unknown>>))
			for (const group of ['checks', 'applies_to'])
				for (const [cname, check] of Object.entries((req?.[group] ?? {}) as Record<string, unknown>))
					out.set(`${rname}.${cname}`, canonical(check))
		return out
	}
	const a = flat(before)
	const b = flat(after)
	return {
		lost: [...a.keys()].filter((k) => !b.has(k)),
		added: [...b.keys()].filter((k) => !a.has(k)),
		changed: [...a.keys()].filter((k) => b.has(k) && a.get(k) !== b.get(k)),
	}
}

function lint(file: string, ops: CustomOpRegistry): number {
	const doc = parseYaml(readFileSync(file, 'utf8')) as {requirements?: unknown}
	const diagnostics = validateRequirements(doc?.requirements ?? doc, new Set(Object.keys(ops)))
	report(diagnostics, file)
	if (!diagnostics.length) process.stdout.write(`${file}: valid\n`)
	return diagnostics.some((d) => d.severity === 'error') ? 1 : 0
}

function apply(file: string, source: string, result: Analysis, spec: string, ops: CustomOpRegistry): number {
	const doc = parseYaml(readFileSync(spec, 'utf8')) as {requirements?: Record<string, unknown>}
	const patch = applyRequirements(source, result, doc?.requirements ?? {}, ops)
	const after = analyze(patch.markdown, {customOps: ops})
	const drift = differences(after.requirements, doc?.requirements ?? {})
	for (const r of patch.refusals) process.stderr.write(`error: ${file}: ${r}\n`)
	if (patch.refusals.length || drift.length) {
		if (!patch.refusals.length)
			for (const d of drift) process.stderr.write(`error: ${file}: ${d} does not come back from the patched document\n`)
		process.stderr.write(`${file}: not written\n`)
		return 1
	}
	for (const c of patch.changes) process.stdout.write(`  ${c}\n`)
	if (!patch.changes.length) process.stdout.write(`${file}: already says this\n`)
	else writeFileSync(file, patch.markdown)
	return 0
}

function check(file: string, result: Analysis, target: string): number {
	const committed = parseYaml(readFileSync(target, 'utf8')) as {requirements?: unknown}
	const {lost, added, changed} = diffChecks(committed?.requirements, result.requirements)
	for (const k of lost) process.stderr.write(`error: ${target}: check "${k}" no longer compiles from ${file}\n`)
	for (const k of added) process.stderr.write(`error: ${target}: check "${k}" is new and not committed\n`)
	for (const k of changed) process.stderr.write(`error: ${target}: check "${k}" changed\n`)
	if (lost.length || added.length || changed.length) return 1
	if (toYaml(committed, {lineWidth: 0}) !== yamlOf(result.requirements)) {
		process.stderr.write(`error: ${target}: differs from a fresh compile of ${file}\n`)
		return 1
	}
	process.stdout.write(`${target}: up to date with ${file}\n`)
	return 0
}

function main(argv: string[]): number {
	const args = parseArgs(argv)
	if (typeof args === 'string') {
		process.stderr.write(`${args}\n\n${USAGE}`)
		return 2
	}
	const {command, files} = args
	const wants = command === 'apply' ? 2 : 1
	const allows = command === 'check' ? 2 : wants
	if (!COMMANDS.includes(command) || files.length < wants || files.length > allows) {
		process.stderr.write(USAGE)
		return 2
	}
	const ops = registry(args.ops)
	const file = files[0]!

	if (command === 'lint') return lint(file, ops)

	const source = readFileSync(file, 'utf8')
	const result = analyze(source, {customOps: ops})

	if (command === 'explain') {
		explain(result, file)
		report(result.diagnostics, file)
		return result.ok ? 0 : 1
	}

	report(result.diagnostics, file)
	if (!result.ok) return 1

	if (command === 'apply') return apply(file, source, result, files[1]!, ops)
	if (command === 'check') return check(file, result, files[1] ?? join(dirname(file), 'data.yaml'))

	if (!args.out) {
		process.stdout.write(yamlOf(result.requirements))
		return 0
	}
	writeFileSync(args.out, yamlOf(result.requirements))
	process.stdout.write(`${args.out}: ${Object.keys(result.requirements).length} requirements\n`)
	return 0
}

process.exit(main(process.argv.slice(2)))
