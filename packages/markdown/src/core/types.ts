export type Segment = string | {where: Record<string, unknown>}
export type Path = Segment[]

export type Check = Record<string, unknown>

export interface PropertyDef {
	display: string
	path: Path
	splits: number[]
	line?: number
}

export interface SubjectDef {
	subjectType: string
	from: Path
	id: Path
	line: number
}

export type BlockKind =
	| 'prose'
	| 'subject'
	| 'properties'
	| 'constant'
	| 'substitute'
	| 'requirement'
	| 'directive'
	| 'scope'
	| 'rule'

export interface Block {
	kind: BlockKind
	line: number
	endLine: number
	label?: string
	detail?: string
	op?: string
}

export interface Anchor {
	kind: 'rule' | 'scope' | 'substitute' | 'requirement' | 'list' | 'directive' | 'table'
	requirement?: string
	name?: string
	start: number
	end: number
	indent?: string
	lead?: string
	head?: string
	insertAt?: number
}

export interface Diagnostic {
	severity: 'error' | 'warning'
	line: number
	message: string
}

export interface SubjectSummary {
	name: string
	subjectType: string
	from: Path
	id: Path
	line: number
	properties: Array<{
		display: string
		path: Path
		pathText: string
		line?: number
		used: boolean
	}>
}

export interface DocContext {
	constants: Record<string, unknown[]>
	substitutes: Record<string, Check>
	properties: Record<string, PropertyDef[]>
	all: PropertyDef[]
	subjectOf: Record<string, string>
}

export interface Analysis {
	blocks: Block[]
	anchors: Anchor[]
	context: DocContext
	subjects: SubjectSummary[]
	substitutes: string[]
	constants: string[]
	requirements: Record<string, unknown>
	diagnostics: Diagnostic[]
	ok: boolean
}

export interface CustomOp {
	phrase: string
	expression: string
	inputs: Array<{subject: string[]} | {each: string[]}>
}

export type CustomOpRegistry = Record<string, CustomOp>
