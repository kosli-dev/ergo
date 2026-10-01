import {readFileSync} from 'node:fs'
import {dirname, join} from 'node:path'
import {fileURLToPath} from 'node:url'
import {stringify as toYaml} from 'yaml'
import {analyze} from '../src/core/index.ts'
import type {CustomOpRegistry} from '../src/core/types.ts'

export const PACKAGE = join(dirname(fileURLToPath(import.meta.url)), '..')

export const read = (file: string): string => readFileSync(join(PACKAGE, file), 'utf8')

export const EXAMPLES: Array<{file: string; ops: CustomOpRegistry}> = [
	{file: 'examples/prod_deploy/policy.ergo.md', ops: {}},
	{file: 'examples/multi_subject/policy.ergo.md', ops: {}},
	{file: 'examples/four_eyes/policy.ergo.md', ops: JSON.parse(read('examples/four_eyes/custom_ops.json')) as CustomOpRegistry},
]

export const yamlOf = (requirements: unknown): string => toYaml({requirements}, {lineWidth: 0})

export const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v)) as T

export function proseOf(markdown: string, customOps: CustomOpRegistry = {}): string[] {
	const lines = markdown.split('\n')
	return analyze(markdown, {customOps})
		.blocks.filter((b) => b.kind === 'prose')
		.map((b) => lines.slice(b.line - 1, b.endLine).join('\n').trim())
		.filter((t) => t.length > 40)
}

export const errors = (markdown: string, customOps: CustomOpRegistry = {}): string[] =>
	analyze(markdown, {customOps})
		.diagnostics.filter((d) => d.severity === 'error')
		.map((d) => d.message)
