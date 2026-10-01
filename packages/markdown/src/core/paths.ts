import type {Path, Segment} from './types.ts'

export interface ParsedPath {
	path: Path
	splits: number[]
}

export function literal(raw: string): unknown {
	if (raw === 'true') return true
	if (raw === 'false') return false
	if (raw === 'null') return null
	if (/^-?\d+$/.test(raw)) return Number(raw)
	if (/^-?\d*\.\d+$/.test(raw)) return Number(raw)
	return raw
}

function tokenize(text: string): string[] {
	const out: string[] = []
	let buf = ''
	let depth = 0
	for (const ch of text) {
		if (ch === '[') depth++
		else if (ch === ']') depth--
		if (ch === '.' && depth === 0) {
			out.push(buf)
			buf = ''
			continue
		}
		buf += ch
	}
	out.push(buf)
	return out.filter((t) => t.length > 0)
}

export function parsePath(text: string): ParsedPath {
	const path: Path = []
	const splits: number[] = []

	for (const token of tokenize(text.trim())) {
		const m = /^([^[\]]*)(\[(.*)\])?$/.exec(token)
		if (!m) throw new Error(`cannot read path segment "${token}"`)
		const [, key = '', bracket, inner] = m

		if (key) path.push(key)

		if (bracket === undefined) continue

		if (inner === '') {
			splits.push(path.length)
			continue
		}

		const eq = (inner ?? '').indexOf('=')
		if (eq < 0) throw new Error(`selector "${inner}" is not key=value`)
		const field = (inner ?? '').slice(0, eq).trim()
		const value = (inner ?? '').slice(eq + 1).trim()
		path.push({where: {[field]: literal(value)}})
	}

	return {path, splits}
}

export function renderPath(path: Path): string {
	return path
		.map((seg: Segment) =>
			typeof seg === 'string'
				? seg
				: '[' +
					Object.entries(seg.where)
						.map(([k, v]) => `${k}=${String(v)}`)
						.join(' ') +
					']',
		)
		.join('.')
		.replace(/\.\[/g, '[')
}

export function renderDeclared(path: Path, splits: number[]): string {
	const marks = new Set(splits)
	return path
		.map((seg, i) => (typeof seg === 'string' ? seg : renderPath([seg])) + (marks.has(i + 1) ? '[]' : ''))
		.join('.')
		.replace(/\.\[/g, '[')
}
