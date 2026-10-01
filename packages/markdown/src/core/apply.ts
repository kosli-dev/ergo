import {parse as fromYaml} from 'yaml'
import {analyze} from './index.ts'
import {applyRequirements, differences} from './patch.ts'
import type {CustomOpRegistry} from './types.ts'

export interface ApplyResult {
	markdown: string
	changes: string[]
	refusals: string[]
	touched: string[]
	drift: string[]
	ok: boolean
	error?: string
}

export function applyYaml(markdown: string, yamlText: string, customOps: CustomOpRegistry = {}): ApplyResult {
	const stop = (error: string): ApplyResult => ({markdown, changes: [], refusals: [], touched: [], drift: [], ok: false, error})

	let target: Record<string, unknown>
	try {
		const doc = fromYaml(yamlText) as {requirements?: Record<string, unknown>} | null
		if (!doc || typeof doc !== 'object' || !('requirements' in doc)) return stop('no `requirements:` here, so there is nothing to apply')
		target = (doc.requirements ?? {}) as Record<string, unknown>
		if (typeof target !== 'object' || Array.isArray(target)) throw new Error('`requirements` must be a mapping')
	} catch (e) {
		return stop((e as Error).message)
	}

	const before = analyze(markdown, {customOps})
	if (!before.ok) return stop('fix the Markdown first: a document that does not compile has nothing to compare against')
	const patched = applyRequirements(markdown, before, target, customOps)
	const after = analyze(patched.markdown, {customOps})
	const drift = differences(after.requirements, target)

	return {
		markdown: patched.markdown,
		changes: patched.changes,
		refusals: patched.refusals,
		touched: patched.touched,
		drift,
		ok: drift.length === 0 && after.ok,
	}
}
