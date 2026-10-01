import type {Check, PropertyDef, SubjectDef} from './types.ts'
import {parsePath} from './paths.ts'
import {type Atom, normalize} from './grammar.ts'

export function parseSubject(atoms: Atom[], line: number): SubjectDef | null {
	const n = normalize(atoms)
	const m = /^An? \u00abp(\d+)\u00bb is each of \u00abc(\d+)\u00bb, identified by its \u00abc(\d+)\u00bb\.?$/.exec(n.s)
	if (!m) return null
	return {
		subjectType: (n.props[Number(m[1])] ?? '').trim(),
		from: parsePath(n.codes[Number(m[2])] ?? '').path,
		id: parsePath(n.codes[Number(m[3])] ?? '').path,
		line,
	}
}

interface TableCellish {
	children?: unknown[]
}
interface TableRowish {
	children?: TableCellish[]
	position?: {start: {line: number}}
}

export function parseTable(rows: TableRowish[], cellText: (c: TableCellish) => string): Map<string, PropertyDef> {
	const props = new Map<string, PropertyDef>()
	for (const row of rows.slice(1)) {
		const cells = row.children ?? []
		if (cells.length < 2) continue
		const display = cellText(cells[0] as TableCellish).trim()
		const raw = cellText(cells[1] as TableCellish).trim()
		if (!display || !raw) continue
		const {path, splits} = parsePath(raw)
		props.set(display.toLowerCase().replace(/\s+/g, ' '), {display, path, splits, line: row.position?.start.line ?? 0})
	}
	return props
}

export function parseConstantHead(atoms: Atom[]): string | null {
	const n = normalize(atoms)
	const m = /^\u00abp(\d+)\u00bb\s+(?:are|is)\b.*:$/.exec(n.s)
	if (!m) return null
	return (n.props[Number(m[1])] ?? '').toLowerCase().trim()
}

export type Substitutes = Map<string, Check>
