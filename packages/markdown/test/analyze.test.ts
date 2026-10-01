import {test} from 'node:test'
import assert from 'node:assert/strict'
import {analyze} from '../src/core/index.ts'
import type {CustomOpRegistry} from '../src/core/types.ts'
import {errors} from './helpers.ts'

const DEPLOYMENT = `A **deployment** is each of \`deployments\`, identified by its \`name\`.

| Property    | Path                     |
| ----------- | ------------------------ |
| environment | \`environment\`            |
| approver    | \`approved_by\`            |
| approved at | \`approved_at\`            |
| built at    | \`built_at\`               |
| CI checks   | \`ci_checks\`              |
| conclusion  | \`ci_checks[].conclusion\` |
| PR state    | \`attestations[type=pull_request].state\` |
| reviews     | \`pull_requests[].reviews[]\` |
`

const policy = (body: string, head = DEPLOYMENT): string => `${head}
## Deploys \`deploys\`

${body}
`

const deploys = (markdown: string, customOps: CustomOpRegistry = {}): Record<string, unknown> => {
	const result = analyze(markdown, {customOps})
	assert.deepEqual(
		result.diagnostics.filter((d) => d.severity === 'error'),
		[],
	)
	return (result.requirements as Record<string, Record<string, unknown>>)['deploys']!
}

const checksOf = (markdown: string, customOps: CustomOpRegistry = {}): Record<string, Record<string, unknown>> =>
	deploys(markdown, customOps)['checks'] as Record<string, Record<string, unknown>>

test('a rule becomes a check with its description', () => {
	const checks = checksOf(policy('Must hold:\n\n- `approved` — the **approver** must be a non-empty string.\n  Someone approved it.'))
	assert.deepEqual(checks['approved'], {op: 'non_empty_string', path: ['approved_by'], description: 'Someone approved it'})
})

test('a subject declaration fills subject_type, from and id', () => {
	const req = deploys(policy('Must hold:\n\n- `approved` — the **approver** must be present.'))
	assert.equal(req['subject_type'], 'deployment')
	assert.deepEqual(req['from'], ['deployments'])
	assert.deepEqual(req['id'], ['name'])
})

test('a named list with no lead-in is an error rather than being dropped', () => {
	assert.match(errors(policy('- `approved` — the **approver** must be present.'))[0]!, /"Must hold:" for checks, "In scope:" for a scope filter/)
})

test('in scope bullets become applies_to', () => {
	const req = deploys(policy('In scope:\n\n- `is_prod` — the **environment** must be `prod`.\n\nMust hold:\n\n- `approved` — the **approver** must be present.'))
	assert.deepEqual(req['applies_to'], {is_prod: {op: 'equals', path: ['environment'], value: 'prod'}})
})

test('rationale may say must without becoming a rule', () => {
	const result = analyze(policy('Everyone must be careful here.\n\nMust hold:\n\n- `approved` — the **approver** must be present.'))
	assert.deepEqual(result.diagnostics, [])
})

test('a sentence that nearly makes a rule is reported as a warning', () => {
	const result = analyze(policy('The **approver** must be lovely.\n\nMust hold:\n\n- `approved` — the **approver** must be present.'))
	assert.equal(result.ok, true)
	assert.match(result.diagnostics[0]!.message, /looks like a rule but matches no operator/)
})

test('a bullet whose sentence matches no operator is an error', () => {
	assert.match(errors(policy('Must hold:\n\n- `approved` — the **approver** must be lovely.'))[0]!, /approved: no operator matches/)
})

test('a full stop inside a code span does not end the sentence', () => {
	const checks = checksOf(policy('Must hold:\n\n- `v` — the **environment** must be `a. b`. The version.'))
	assert.equal(checks['v']!['value'], 'a. b')
	assert.equal(checks['v']!['description'], 'The version')
})

test('true, false, null and numbers are read as values, not strings', () => {
	const checks = checksOf(
		policy(
			'Must hold:\n\n- `a` — the **environment** must be `true`.\n- `b` — the **environment** must be `false`.\n- `c` — the **environment** must be `null`.\n- `d` — the **environment** must be `42`.\n- `e` — the **environment** must be `1.5`.',
		),
	)
	assert.deepEqual(
		['a', 'b', 'c', 'd', 'e'].map((k) => checks[k]!['value']),
		[true, false, null, 42, 1.5],
	)
})

test('the full stop at the end of a description is dropped', () => {
	const checks = checksOf(policy('Must hold:\n\n- `approved` — the **approver** must be present. First part. Second part.'))
	assert.equal(checks['approved']!['description'], 'First part. Second part')
})

test('every leaf operator has a sentence', () => {
	const checks = checksOf(
		policy(`Must hold:

- \`p\` — the **approver** must be present.
- \`x\` — the **approver** must exist.
- \`r\` — the **environment** must be between \`1\` and \`3\`.
- \`i\` — the **CI checks** must include \`lint\`.
- \`e\` — the **CI checks** must not include \`skip\`.
- \`m\` — the **approver** must match one of \`^a\`, \`^b\`.
- \`n\` — the **approver** must match none of \`^bot\`.
- \`c\` — the **approved at** must be at least the **built at**.
- \`t\` — the **approved at** must be after the **built at**.`),
	)
	assert.deepEqual(checks['p'], {op: 'present', path: ['approved_by']})
	assert.deepEqual(checks['x'], {op: 'present', path: ['approved_by']})
	assert.deepEqual(checks['r'], {op: 'range', path: ['environment'], min: 1, max: 3})
	assert.deepEqual(checks['i'], {op: 'includes', path: ['ci_checks'], value: 'lint'})
	assert.deepEqual(checks['e'], {op: 'excludes', path: ['ci_checks'], value: 'skip'})
	assert.deepEqual(checks['m'], {op: 'matches_any', path: ['approved_by'], patterns: ['^a', '^b']})
	assert.deepEqual(checks['n'], {op: 'not_matches_any', path: ['approved_by'], patterns: ['^bot']})
	assert.deepEqual(checks['c'], {op: 'compare', left: ['approved_at'], right: ['built_at'], cmp: 'gte'})
	assert.deepEqual(checks['t'], {op: 'compare_time', left: ['approved_at'], right: ['built_at'], cmp: 'gt'})
})

test('a comparison with an undeclared property is an error', () => {
	assert.match(errors(policy('Must hold:\n\n- `c` — the **approved at** must be after the **deployed at**.'))[0]!, /no declared property named "deployed at"/)
})

test('a rule about an undeclared property is an error', () => {
	assert.match(errors(policy('Must hold:\n\n- `c` — the **reviewer** must be present.'))[0]!, /no declared property named "reviewer"/)
})

test('every and some quantify over a collection', () => {
	const checks = checksOf(
		policy(`Must hold:

- \`green\` — every **CI check** must have a **conclusion** of \`success\`.
- \`one\` — at least one **CI check** must have a **conclusion** that must match one of \`^succ\`.
- \`some\` — some **CI check** must be present.`),
	)
	assert.deepEqual(checks['green'], {op: 'all', path: ['ci_checks'], check: {op: 'equals', path: ['conclusion'], value: 'success'}})
	assert.deepEqual(checks['one'], {op: 'any', path: ['ci_checks'], check: {op: 'matches_any', path: ['conclusion'], patterns: ['^succ']}})
	assert.deepEqual(checks['some'], {op: 'any', path: ['ci_checks'], check: {op: 'present', path: []}})
})

test('an element property that is not declared is an error', () => {
	assert.match(errors(policy('Must hold:\n\n- `g` — every **CI check** must have a **duration** of `1`.'))[0]!, /no declared property named "duration"/)
	assert.match(errors(policy('Must hold:\n\n- `g` — every **CI check** must have a **duration** that must be present.'))[0]!, /no declared property named "duration"/)
	assert.match(errors(policy('Must hold:\n\n- `g` — every **build** must be present.'))[0]!, /no declared property named "build"/)
	assert.match(errors(policy('Must hold:\n\n- `g` — some **build** must be present.'))[0]!, /no declared property named "build"/)
})

test('a path with two collection boundaries becomes all with each', () => {
	const checks = checksOf(policy('Must hold:\n\n- `r` — every **review** must be present.'))
	assert.deepEqual(checks['r'], {op: 'all', path: ['pull_requests'], each: ['reviews'], check: {op: 'present', path: []}})
})

test('a selector in a path becomes a where step', () => {
	const checks = checksOf(policy('Must hold:\n\n- `s` — the **PR state** must be `MERGED`.'))
	assert.deepEqual(checks['s']!['path'], ['attestations', {where: {type: 'pull_request'}}, 'state'])
})

test('rules read in the singular when the table declares a plural, and the other way round', () => {
	const head = DEPLOYMENT.replace('| approver    |', '| approvers   |')
	const checks = checksOf(policy('Must hold:\n\n- `a` — the **approver** must be present.\n- `b` — every **CI checks** must be present.', head))
	assert.deepEqual(checks['a']!['path'], ['approved_by'])
	assert.deepEqual(checks['b']!['path'], ['ci_checks'])
})

test('a constant holds patterns a rule can name', () => {
	const checks = checksOf(policy('Must hold:\n\n- `human` — the **approver** must match none of **bots**.') + '\n**Bots** are authors matching any of:\n\n- `\\[bot\\]$`\n- `^svc_`\n')
	assert.deepEqual(checks['human']!['patterns'], ['\\[bot\\]$', '^svc_'])
})

test('naming a constant nobody declared is an error', () => {
	assert.match(errors(policy('Must hold:\n\n- `human` — the **approver** must match none of **bots**.'))[0]!, /no constant named "bots"/)
})

test('a match with neither patterns nor a constant is an error', () => {
	assert.match(errors(policy('Must hold:\n\n- `human` — the **approver** must match none of nothing.'))[0]!, /expected a list of patterns/)
})

test('a list of patterns separated from its constant sentence is an error', () => {
	const head = `${DEPLOYMENT}\n**Bots** are authors matching any of:\n\nSomething in between.\n\n- \`^svc_\`\n`
	const markdown = policy('Must hold:\n\n- `a` — the **approver** must be present.', head)
	assert.match(errors(markdown)[0]!, /has to come straight after the sentence that names the constant/)
})

test('a sentence ending in a colon is only a constant when patterns follow it', () => {
	const result = analyze(policy('**Note** is this:\n\nMust hold:\n\n- `a` — the **approver** must be present.'))
	assert.deepEqual(result.constants, [])
	assert.equal(result.ok, true)
})

test('a substitute is declared outside any requirement and named with or else', () => {
	const markdown = `${DEPLOYMENT}
- \`emergency\` — the **environment** must be \`hotfix\`.

${policy('Must hold:\n\n- `approved` — the **approver** must be present, or else `emergency`.', '')}`
	const checks = checksOf(markdown)
	assert.deepEqual(checks['approved']!['substitute'], {op: 'equals', path: ['environment'], value: 'hotfix'})
	assert.deepEqual(analyze(markdown).substitutes, ['emergency'])
})

test('naming a substitute nobody declared is an error', () => {
	assert.match(errors(policy('Must hold:\n\n- `approved` — the **approver** must be present, or else `emergency`.'))[0]!, /no substitute named "emergency"/)
})

test('a bullet with no name is an error', () => {
	assert.match(errors(policy('Must hold:\n\n- `a` — the **approver** must be present.\n- the **approver** must be present.'))[0]!, /a rule needs a name/)
})

test('a named bullet with no sentence is an error', () => {
	assert.match(errors(policy('Must hold:\n\n- `a`'))[0]!, /a: no rule sentence/)
})

test('two checks with one name is an error', () => {
	assert.match(errors(policy('Must hold:\n\n- `a` — the **approver** must be present.\n- `a` — the **environment** must be present.'))[0]!, /a: already defined/)
})

test('a requirement with no checks is an error', () => {
	assert.match(errors(policy('Nothing to see.')).join('\n'), /deploys: declares no checks/)
})

test('a document with no subject is an error', () => {
	assert.match(errors('## Deploys `deploys`\n\nMust hold:\n\n- `a` — the **approver** must be present.\n').join('\n'), /no subject declared/)
})

test('a property table before any subject is an error', () => {
	assert.match(errors('| Property | Path |\n| --- | --- |\n| approver | `approved_by` |\n').join('\n'), /declare a subject before its properties/)
})

test('a broken path in the property table is an error', () => {
	assert.match(errors(DEPLOYMENT.replace('`approved_by`', '`approvals[x]`')).join('\n'), /selector "x" is not key=value/)
})

test('a table whose second column holds no paths is prose, not properties', () => {
	const markdown = policy('| Team | Owner |\n| --- | --- |\n| infra | alice |\n\nMust hold:\n\n- `a` — the **approver** must be present.')
	const result = analyze(markdown)
	assert.equal(result.ok, true)
	assert.equal(result.blocks.filter((b) => b.kind === 'properties').length, 1)
})

test('directives set min_subjects and require', () => {
	assert.equal(deploys(policy('At least one **deployment** must be in scope.\n\nMust hold:\n\n- `a` — the **approver** must be present.'))['min_subjects'], 1)
	assert.equal(deploys(policy('At least 3 **deployments** must be in scope.\n\nMust hold:\n\n- `a` — the **approver** must be present.'))['min_subjects'], 3)
	assert.equal(deploys(policy('No minimum: an empty list is fine.\n\nMust hold:\n\n- `a` — the **approver** must be present.'))['min_subjects'], 0)
	assert.equal(deploys(policy('One **deployment** must satisfy all of these.\n\nMust hold:\n\n- `a` — the **approver** must be present.'))['require'], 'some')
})

test('a declaration may come after the requirement that uses it', () => {
	const markdown = `## Deploys \`deploys\`\n\nMust hold:\n\n- \`a\` — the **approver** must be present.\n\n# Declarations\n\n${DEPLOYMENT}`
	assert.deepEqual(checksOf(markdown)['a'], {op: 'present', path: ['approved_by']})
})

test('a deeper heading stays inside the requirement, and one at the same level closes it', () => {
	const markdown = policy('### Detail\n\nMust hold:\n\n- `a` — the **approver** must be present.\n\n## Elsewhere\n\nMust hold:\n\n- `b` — the **environment** must be present.')
	const result = analyze(markdown)
	assert.deepEqual(Object.keys((result.requirements['deploys'] as {checks: object}).checks), ['a'])
	assert.deepEqual(result.substitutes, ['b'])
})

const PULL_REQUEST = `A **pull request** is each of \`pull_requests\`, identified by its \`url\`.

| Property  | Path         |
| --------- | ------------ |
| base      | \`base_ref\`   |
`

test('with several subjects, each requirement says which one it is about', () => {
	const markdown = `${DEPLOYMENT}\n${PULL_REQUEST}\n## Reviewed \`reviewed\`\n\nFor each **pull request**.\n\nMust hold:\n\n- \`main\` — the **base** must be \`main\`.\n`
	const result = analyze(markdown)
	assert.equal(result.ok, true)
	assert.equal((result.requirements['reviewed'] as Record<string, unknown>)['subject_type'], 'pull request')
})

test('with several subjects, a requirement that names none is an error', () => {
	const markdown = `${DEPLOYMENT}\n${PULL_REQUEST}\n## Reviewed \`reviewed\`\n\nMust hold:\n\n- \`main\` — the **approver** must be present.\n`
	assert.match(errors(markdown).join('\n'), /several subjects are declared, so say which one/)
})

test('declaring the same subject twice is an error', () => {
	assert.match(errors(`${DEPLOYMENT}\n${DEPLOYMENT}`).join('\n'), /a subject named "deployment" is already declared/)
})

test('a property is only reachable from its own subject', () => {
	const markdown = `${DEPLOYMENT}\n${PULL_REQUEST}\n## Reviewed \`reviewed\`\n\nFor each **pull request**.\n\nMust hold:\n\n- \`main\` — the **approver** must be present.\n`
	assert.match(errors(markdown).join('\n'), /no declared property named "approver"/)
})

test('a records sentence adds an input', () => {
	const checks = checksOf(policy('Must hold:\n\n- `green` — every **CI check** must have a **conclusion** of `success`.\n  Records the **CI checks**\' `name`.'))
	assert.deepEqual(checks['green']!['inputs'], [{path: ['ci_checks'], each: ['name']}])
})

test('a records sentence about an undeclared property is an error', () => {
	assert.match(errors(policy('Must hold:\n\n- `a` — the **approver** must be present.\n  Records the **builds**\' `name`.'))[0]!, /no declared property named "builds"/)
})

const OPS: CustomOpRegistry = {
	independently_approved: {
		phrase: 'be independently approved',
		expression: 'some approver is not an author',
		inputs: [{subject: ['name']}, {each: ['approvers']}],
	},
}

test('a custom operator is picked by its phrase and brings its expression and inputs', () => {
	const head = DEPLOYMENT.replace('| reviews ', '| pull requests | `pull_requests` |\n| reviews ')
	const markdown = policy('Must hold:\n\n- `four_eyes` — some **pull request** must be independently approved, treating **bots** as explained.', head) + '\n**Bots** are authors matching any of:\n\n- `\\[bot\\]$`\n'
	assert.deepEqual(checksOf(markdown, OPS)['four_eyes'], {
		op: 'independently_approved',
		expression: 'some approver is not an author',
		path: ['pull_requests'],
		patterns: ['\\[bot\\]$'],
		inputs: [['name'], {path: ['pull_requests'], each: ['approvers']}],
	})
})

test('a custom operator on an undeclared property is an error', () => {
	assert.match(errors(policy('Must hold:\n\n- `x` — some **build** must be independently approved.'), OPS)[0]!, /no declared property named "build"/)
})

test('treating an undeclared constant as explained is an error', () => {
	assert.match(errors(policy('Must hold:\n\n- `x` — some **review** must be independently approved, treating **bots** as explained.'), OPS)[0]!, /no constant named "bots"/)
})

test('a property nothing reads is shown as unused', () => {
	const result = analyze(policy('Must hold:\n\n- `a` — the **approver** must be present.'))
	const used = Object.fromEntries(result.subjects[0]!.properties.map((p) => [p.display, p.used]))
	assert.equal(used['approver'], true)
	assert.equal(used['environment'], false)
	assert.equal(result.subjects[0]!.properties.find((p) => p.display === 'conclusion')!.pathText, 'ci_checks[].conclusion')
})

test('a bullet that does not start like a rule is an error', () => {
	assert.match(errors(policy('Must hold:\n\n- `a` — approvals are nice.'))[0]!, /a: "approvals are nice\." matches no operator/)
})

test('a check that has no way back into prose still compiles', () => {
	const result = analyze(policy('Must hold:\n\n- `odd` — every **CI check** must have a **PR state** of `open`.'))
	assert.equal(result.ok, true)
	assert.deepEqual((result.requirements['deploys'] as {checks: Record<string, unknown>}).checks['odd'], {
		op: 'all',
		path: ['ci_checks'],
		check: {op: 'equals', path: ['attestations', {where: {type: 'pull_request'}}, 'state'], value: 'open'},
	})
})
