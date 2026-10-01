import {test} from 'node:test'
import assert from 'node:assert/strict'
import {analyze} from '../src/core/index.ts'
import {applyYaml} from '../src/core/apply.ts'
import {EXAMPLES, clone, proseOf, read, yamlOf} from './helpers.ts'

type Spec = Record<string, Record<string, Record<string, Record<string, unknown>>>>

for (const file of EXAMPLES) {
	const markdown = read(file)
	const analysis = analyze(markdown)

	test(`${file} compiles`, () => {
		assert.deepEqual(analysis.diagnostics, [])
	})

	test(`${file}: applying its own requirements changes nothing`, () => {
		const identity = applyYaml(markdown, yamlOf(analysis.requirements))
		assert.equal(identity.markdown, markdown)
		assert.deepEqual(identity.changes, [])
		assert.deepEqual(identity.refusals, [])
	})

	test(`${file}: every check can be written back and reads the same`, () => {
		const target = clone(analysis.requirements) as Spec
		let touched = 0
		for (const req of Object.values(target))
			for (const field of ['checks', 'applies_to'])
				for (const check of Object.values(req[field] ?? {})) check['description'] = `rewritten by the round trip ${++touched}`
		const rewritten = applyYaml(markdown, yamlOf(target))
		assert.deepEqual(rewritten.refusals, [])
		assert.deepEqual(rewritten.drift, [])
		assert.equal(rewritten.changes.length, touched)

		const bold = (text: string): string[] => (text.match(/\*\*[^*]+\*\*/g) ?? []).sort()
		assert.deepEqual(bold(rewritten.markdown), bold(markdown))
		assert.deepEqual(
			proseOf(markdown).filter((p) => !rewritten.markdown.includes(p)),
			[],
		)
	})

	test(`${file}: a check on an undeclared path adds a row to the property table`, () => {
		const grown = clone(analysis.requirements) as Record<string, {checks: Record<string, unknown>}>
		const host = Object.keys(grown)[0]!
		grown[host]!.checks['round_trip_probe'] = {op: 'non_empty_string', path: ['probe', 'undeclared_field'], description: 'A field nobody named in the table'}
		const added = applyYaml(markdown, yamlOf(grown))
		assert.deepEqual(added.refusals, [])
		assert.deepEqual(added.drift, [])
		assert.match(added.markdown, /\|\s*`probe\.undeclared_field`\s*\|/)
		assert.deepEqual(
			proseOf(markdown).filter((p) => !added.markdown.includes(p)),
			[],
		)
	})

	test(`${file}: editing a path three times repoints one row instead of adding three`, () => {
		const rows = (text: string): number => text.split('\n').filter((l) => /^\s*\|/.test(l)).length
		let spot: [string, string] | undefined
		for (const [req, body] of Object.entries(analysis.requirements as Record<string, {checks?: Record<string, {path?: unknown[]}>}>))
			for (const [check, def] of Object.entries(body.checks ?? {}))
				if (!spot && Array.isArray(def.path) && typeof def.path[def.path.length - 1] === 'string') spot = [req, check]
		assert.ok(spot)
		const [req, check] = spot
		let doc = markdown
		for (const suffix of ['z', 'zz', '_2']) {
			const spec = clone(analyze(doc).requirements) as Record<string, {checks: Record<string, {path: string[]}>}>
			const path = spec[req]!.checks[check]!.path
			path[path.length - 1] = String(path[path.length - 1]).replace(/(z|zz|_2)$/, '') + suffix
			const step = applyYaml(doc, yamlOf(spec))
			assert.ok(step.ok, [...step.refusals, ...step.drift].join('; '))
			doc = step.markdown
		}
		assert.equal(rows(doc), rows(markdown))
	})

	test(`${file}: renaming a check keeps its bullet in place`, () => {
		const renaming = clone(analysis.requirements) as Record<string, {checks: Record<string, unknown>; applies_to?: Record<string, unknown>}>
		const host = Object.keys(renaming)[0]!
		const field = renaming[host]!.applies_to ? 'applies_to' : 'checks'
		const table = renaming[host]![field] as Record<string, unknown>
		const was = Object.keys(table)[0]!
		table[`${was}_renamed`] = table[was]
		delete table[was]
		const order = (text: string): string[] => (text.match(/^\s*- `[\w-]+`/gm) ?? []).map((l) => l.trim())
		const renamed = applyYaml(markdown, yamlOf(renaming))
		assert.deepEqual([...renamed.refusals, ...renamed.drift], [])
		assert.equal(order(renamed.markdown).length, order(markdown).length)
		assert.equal(order(renamed.markdown).indexOf(`- \`${was}_renamed\``), order(markdown).indexOf(`- \`${was}\``))
		assert.deepEqual(
			proseOf(markdown).filter((p) => !renamed.markdown.includes(p)),
			[],
		)
	})

	test(`${file}: removing a check removes its bullet and no prose`, () => {
		const first = Object.keys(analysis.requirements)[0]!
		const cut = clone(analysis.requirements) as Record<string, {checks: Record<string, unknown>}>
		const names = Object.keys(cut[first]!.checks)
		delete cut[first]!.checks[names[names.length - 1]!]
		const removed = applyYaml(markdown, yamlOf(cut))
		assert.deepEqual(removed.drift, [])
		assert.doesNotMatch(removed.markdown, new RegExp(`- \`${names[names.length - 1]}\``))
		assert.deepEqual(
			proseOf(markdown).filter((p) => !removed.markdown.includes(p)),
			[],
		)
	})
}
