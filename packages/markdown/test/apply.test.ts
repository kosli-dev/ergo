import {test} from 'node:test'
import assert from 'node:assert/strict'
import {analyze} from '../src/core/index.ts'
import {applyYaml} from '../src/core/apply.ts'
import {applyRequirements} from '../src/core/patch.ts'
import {wrap, writeBullet} from '../src/core/render.ts'
import type {CustomOpRegistry} from '../src/core/types.ts'
import {clone, read, yamlOf} from './helpers.ts'

const PROD = read('examples/prod_deploy/policy.ergo.md')

type Spec = Record<string, Record<string, unknown> & {checks: Record<string, Record<string, unknown>>; applies_to?: Record<string, Record<string, unknown>>}>

const spec = (markdown = PROD, customOps: CustomOpRegistry = {}): Spec => clone(analyze(markdown, {customOps}).requirements) as Spec

const refusals = (edit: (s: Spec) => void, markdown = PROD): string[] => {
	const s = spec(markdown)
	edit(s)
	return applyYaml(markdown, yamlOf(s)).refusals
}

test('yaml without a requirements key is refused rather than read as an empty policy', () => {
	const result = applyYaml(PROD, 'checks: {}\n')
	assert.equal(result.ok, false)
	assert.match(result.error!, /no `requirements:` here/)
	assert.equal(result.markdown, PROD)
})

test('yaml whose requirements are not a mapping is refused', () => {
	assert.match(applyYaml(PROD, 'requirements: [1]\n').error!, /must be a mapping/)
	assert.match(applyYaml(PROD, 'requirements: [\n').error!, /.+/)
})

test('a document that does not compile is not patched', () => {
	const broken = PROD.replace('Must hold:', '')
	const result = applyYaml(broken, yamlOf(spec()))
	assert.match(result.error!, /fix the Markdown first/)
	assert.equal(result.markdown, broken)
})

test('a description ending in a full stop is refused, because it would come back without it', () => {
	assert.match(refusals((s) => (s['prod_deploy']!.checks['approved']!['description'] = 'Signed off.'))[0]!, /drop the trailing full stop/)
})

test('the string "true" is refused, because prose would read it back as a boolean', () => {
	assert.match(refusals((s) => (s['prod_deploy']!.applies_to!['is_prod']!['value'] = 'true'))[0]!, /would be read back as boolean, not string/)
})

test('a value prose would read back differently is refused', () => {
	assert.match(refusals((s) => (s['prod_deploy']!.applies_to!['is_prod']!['value'] = ' padded '))[0]!, /would be read back as "padded"/)
})

test('a path segment holding a dot is refused, because the table could not hold it', () => {
	assert.match(refusals((s) => (s['prod_deploy']!.checks['approved']!['path'] = ['approved.by']))[0]!, /cannot be declared/)
})

test('a description with Markdown characters in it is escaped and reads back the same', () => {
	const s = spec()
	s['prod_deploy']!.checks['approved']!['description'] = 'A *starred* `ticked` [bracketed] claim'
	const result = applyYaml(PROD, yamlOf(s))
	assert.deepEqual([...result.refusals, ...result.drift], [])
	assert.equal(result.ok, true)
})

test('removing the last check does not turn the paragraph after it into a description', () => {
	const tight = PROD.replace('deployment.\n\n- `ci_green`', 'deployment.\n- `ci_green`')
	const s = spec(tight)
	delete s['prod_deploy']!.checks['ci_green']
	const result = applyYaml(tight, yamlOf(s))
	assert.equal(result.ok, true)
	const after = analyze(result.markdown).requirements as Spec
	assert.equal(after['prod_deploy']!.checks['approved']!['description'], 'A named approver signed off on the deployment')
	assert.match(result.markdown, /\n\nA deployment with no approver/)
})

test('emptying the scope filter removes its "In scope:" line too', () => {
	const s = spec()
	delete s['prod_deploy']!.applies_to
	const result = applyYaml(PROD, yamlOf(s))
	assert.equal(result.ok, true)
	assert.doesNotMatch(result.markdown, /In scope:/)
	assert.ok(result.changes.some((c) => c.includes('which now heads nothing')))
})

test('adding a scope filter to a requirement without one writes "In scope:" before "Must hold:"', () => {
	const bare = PROD.replace(/In scope:\n\n- `is_prod`[^\n]*\n\n/, '')
	const s = spec(bare)
	s['prod_deploy']!.applies_to = {is_prod: {op: 'equals', path: ['environment'], value: 'prod'}}
	const result = applyYaml(bare, yamlOf(s))
	assert.equal(result.ok, true)
	assert.ok(result.markdown.indexOf('In scope:') < result.markdown.indexOf('Must hold:'))
})

test('rewriting a check keeps the quantifier the author wrote', () => {
	const markdown = PROD.replace('every **CI check** must have', 'at least one **CI check** must have')
	const s = spec(markdown)
	s['prod_deploy']!.checks['ci_green']!['description'] = 'Reworded'
	const result = applyYaml(markdown, yamlOf(s))
	assert.equal(result.ok, true)
	assert.match(result.markdown, /at least one \*\*CI check\*\* must have/)
})

test('subject_type, from and id are changed in the subject sentence, not here', () => {
	assert.match(refusals((s) => (s['prod_deploy']!['from'] = ['releases']))[0]!, /`from` is declared in the Subjects section/)
})

test('min_subjects and require are written as sentences', () => {
	const s = spec()
	s['prod_deploy']!['min_subjects'] = 2
	s['prod_deploy']!['require'] = 'some'
	const added = applyYaml(PROD, yamlOf(s))
	assert.equal(added.ok, true)
	assert.match(added.markdown, /At least 2 \*\*deployment\*\* must be in scope\./)
	assert.match(added.markdown, /One \*\*deployment\*\* must satisfy all of these\./)

	const t = spec(added.markdown)
	t['prod_deploy']!['min_subjects'] = 0
	delete t['prod_deploy']!['require']
	const changed = applyYaml(added.markdown, yamlOf(t))
	assert.equal(changed.ok, true)
	assert.match(changed.markdown, /No minimum\./)
	assert.doesNotMatch(changed.markdown, /must satisfy all of these/)
})

test('a requirement can be added whole, and removed with the prose under it', () => {
	const s = spec()
	s['signed'] = {
		subject_type: 'deployment',
		from: ['deployments'],
		id: ['name'],
		min_subjects: 1,
		applies_to: {is_prod: {op: 'equals', path: ['environment'], value: 'prod'}},
		checks: {named: {op: 'non_empty_string', path: ['approved_by']}},
	}
	const added = applyYaml(PROD, yamlOf(s))
	assert.equal(added.ok, true)
	assert.match(added.markdown, /## signed `signed`/)

	delete s['prod_deploy']
	const removed = applyYaml(added.markdown, yamlOf(s))
	assert.equal(removed.ok, true)
	assert.doesNotMatch(removed.markdown, /prod_deploy|A deployment with no approver/)
})

test('a requirement with no checks cannot be added', () => {
	assert.match(refusals((s) => (s['empty'] = {subject_type: 'deployment', from: ['deployments'], id: ['name'], checks: {}}))[0]!, /asserts nothing/)
})

test('a substitute the document does not declare is refused', () => {
	assert.match(refusals((s) => (s['prod_deploy']!.checks['approved']!['substitute'] = {op: 'present', path: ['x']}))[0]!, /substitute that is not declared/)
})

test('an operator with no sentence is refused', () => {
	assert.match(refusals((s) => (s['prod_deploy']!.checks['approved'] = {op: 'any_of', options: {}}))[0]!, /no prose writes the operator "any_of"/)
})

const OPS: CustomOpRegistry = {
	independently_approved: {phrase: 'be independently approved', expression: 'some approver is not an author', inputs: [{each: ['approvers']}]},
}

const CUSTOM = `A **change** is each of \`changes\`, identified by its \`id\`.

| Property      | Path            |
| ------------- | --------------- |
| pull requests | \`pull_requests\` |

## Reviewed \`reviewed\`

Must hold:

- \`four_eyes\` — some **pull request** must be independently approved.
  Someone else approved it.
`

test('a custom operator is written back with its phrase', () => {
	const s = spec(CUSTOM, OPS)
	s['reviewed']!.checks['four_eyes']!['description'] = 'Reworded'
	const result = applyYaml(CUSTOM, yamlOf(s), OPS)
	assert.equal(result.ok, true)
	assert.match(result.markdown, /some \*\*pull request\*\* must be independently approved\.\s+Reworded\./)
})

test('a custom operator whose expression differs from its definition is refused', () => {
	const s = spec(CUSTOM, OPS)
	s['reviewed']!.checks['four_eyes']!['expression'] = 'something else'
	assert.match(applyYaml(CUSTOM, yamlOf(s), OPS).refusals[0]!, /carries an `expression` the registry does not define/)
})

test('a custom operator whose inputs do not follow its path is refused', () => {
	const s = spec(CUSTOM, OPS)
	s['reviewed']!.checks['four_eyes']!['inputs'] = []
	assert.match(applyYaml(CUSTOM, yamlOf(s), OPS).refusals[0]!, /reads `inputs` the registry does not derive/)
})

test('wrapping never breaks inside a code span', () => {
	const text = `\`name\` — the **approver** must match one of \`${'a '.repeat(50)}\`.`
	const lines = wrap(text, '').split('\n')
	assert.equal(lines.filter((l) => l.includes('`a ')).length, 1)
})

test('wrapping never starts a line with something that would start a new block', () => {
	const words = Array.from({length: 40}, (_, i) => (i % 5 === 4 ? '-' : i % 7 === 6 ? '#1' : i % 9 === 8 ? '3.' : 'word'))
	for (const line of wrap(words.join(' '), '').split('\n').slice(1)) assert.doesNotMatch(line.trimStart(), /^(?:[-+>#]|\d+[.)])/)
})

test('a check name holding a backtick is fenced with two', () => {
	const ctx = {props: [{display: 'approver', path: ['approved_by'], splits: []}], constants: {}, substitutes: {}, customOps: {}}
	assert.match(writeBullet(ctx, 'odd`name', {op: 'present', path: ['approved_by']}), /^- `` odd`name `` — the \*\*approver\*\* must be present\.$/)
})

test('one check out and a different one in is read as a rename with an edit, so the bullet stays in place', () => {
	const s = spec()
	delete s['prod_deploy']!.checks['approved']
	s['prod_deploy']!.checks['signed_off'] = {op: 'present', path: ['approved_by']}
	const result = applyYaml(PROD, yamlOf(s))
	assert.equal(result.ok, true)
	assert.deepEqual(result.changes, ['renamed prod_deploy.approved to signed_off'])
	assert.ok(result.markdown.indexOf('`signed_off`') < result.markdown.indexOf('`ci_green`'))
})

test('a new check that cannot be written is refused and leaves the table alone', () => {
	const s = spec()
	s['prod_deploy']!.checks['extra'] = {op: 'any_of', options: {}}
	const result = applyYaml(PROD, yamlOf(s))
	assert.match(result.refusals[0]!, /prod_deploy\.extra: no prose writes the operator "any_of"/)
})

test('a new path whose every name is taken is named after the whole path', () => {
	const s = spec()
	s['prod_deploy']!.checks['extra'] = {op: 'present', path: ['approver']}
	const result = applyYaml(PROD, yamlOf(s))
	assert.equal(result.ok, true)
	assert.match(result.markdown, /\| approver path +\| `approver` +\|/)
})

test('a description that starts like a heading is escaped harder and still reads back', () => {
	const s = spec()
	s['prod_deploy']!.checks['approved']!['description'] = '# not a heading'
	const result = applyYaml(PROD, yamlOf(s))
	assert.equal(result.ok, true)
	assert.equal((analyze(result.markdown).requirements as Spec)['prod_deploy']!.checks['approved']!['description'], '# not a heading')
})

test('a description Markdown cannot hold is refused', () => {
	assert.match(refusals((s) => (s['prod_deploy']!.checks['approved']!['description'] = 'two\nlines'))[0]!, /cannot be written as Markdown without changing what it says/)
})

test('a time comparison with no sentence is refused', () => {
	const markdown = PROD.replace('| conclusion ', '| approved at | `approved_at` |\n| built at    | `built_at`    |\n| conclusion ').replace(
		'Must hold:\n',
		'Must hold:\n\n- `late` — the **approved at** must be after the **built at**.\n',
	)
	assert.match(refusals((s) => (s['prod_deploy']!.checks['late']!['cmp'] = 'eq'), markdown)[0]!, /no phrase for comparison "eq"/)
})

test('an edit is refused when the analysis does not say where things were written', () => {
	const analysis = analyze(PROD)
	const blind = {...analysis, anchors: []}
	const s = spec()
	s['prod_deploy']!.checks['approved']!['description'] = 'Reworded'
	s['prod_deploy']!['min_subjects'] = 2
	assert.deepEqual(applyRequirements(PROD, blind, s, {}).refusals, [
		'prod_deploy: cannot find where to write `min_subjects`',
		'prod_deploy.approved: cannot find where it was written',
	])
	const withMinimum = PROD.replace('In scope:', 'At least one **deployment** must be in scope.\n\nIn scope:')
	const t = spec(withMinimum)
	t['prod_deploy']!['min_subjects'] = 2
	assert.deepEqual(applyRequirements(withMinimum, {...analyze(withMinimum), anchors: []}, t, {}).refusals, ['prod_deploy: cannot find where `min_subjects` was written'])
})

test('a new scope filter goes at the end of the requirement when there is no checks list to put it in front of', () => {
	const analysis = analyze(PROD)
	const only = {...analysis, anchors: analysis.anchors.filter((a) => a.kind === 'requirement')}
	const s = spec()
	s['prod_deploy']!.applies_to!['named'] = {op: 'present', path: ['environment']}
	const result = applyRequirements(PROD, only, s, {})
	assert.deepEqual(result.refusals, [])
	assert.match(result.markdown, /fix them\.\n\nIn scope:\n\n- `named` — the \*\*environment\*\* must be present\.\n/)
	assert.deepEqual(applyRequirements(PROD, {...analysis, anchors: []}, s, {}).refusals, ['prod_deploy.named: cannot find where to write it'])
})

test('removing a check or naming a new path is refused when the analysis does not say where they were written', () => {
	const blind = {...analyze(PROD), anchors: []}
	const s = spec()
	delete s['prod_deploy']!.checks['ci_green']
	s['prod_deploy']!.applies_to!['tagged'] = {op: 'present', path: ['tag']}
	assert.deepEqual(applyRequirements(PROD, blind, s, {}).refusals, [
		'prod_deploy.tagged: cannot find where to write it',
		'prod_deploy.ci_green: cannot find where it was written',
		'deployment: has no property table, so `tag` cannot be named',
	])
})
