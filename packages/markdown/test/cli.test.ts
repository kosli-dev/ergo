import {test} from 'node:test'
import assert from 'node:assert/strict'
import {spawnSync} from 'node:child_process'
import {mkdtempSync, readFileSync, writeFileSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {parse as parseYaml, stringify as toYaml} from 'yaml'
import {PACKAGE, read} from './helpers.ts'

const POLICY = 'examples/prod_deploy/policy.ergo.md'
const COMPILED = 'examples/prod_deploy/data.yaml'

const ergo = (...args: string[]): {status: number | null; stdout: string; stderr: string} => {
	const run = spawnSync(process.execPath, ['src/cli.ts', ...args], {cwd: PACKAGE, encoding: 'utf8'})
	return {status: run.status, stdout: run.stdout, stderr: run.stderr}
}

const scratch = (): string => mkdtempSync(join(tmpdir(), 'ergo-markdown-'))

const copy = (file: string, dir: string, name: string): string => {
	const to = join(dir, name)
	writeFileSync(to, read(file))
	return to
}

test('compile prints the requirements object', () => {
	const run = ergo('compile', POLICY)
	assert.equal(run.status, 0)
	assert.equal(run.stdout, read(COMPILED))
})

test('compile -o writes the requirements object to a file', () => {
	const out = join(scratch(), 'data.yaml')
	const run = ergo('compile', POLICY, '-o', out)
	assert.equal(run.status, 0)
	assert.equal(run.stdout, `${out}: 1 requirements\n`)
	assert.equal(readFileSync(out, 'utf8'), read(COMPILED))
})

test('compile fails and says why when the policy has errors', () => {
	const dir = scratch()
	const policy = join(dir, 'policy.ergo.md')
	writeFileSync(policy, read(POLICY).replace('**approver** must be', '**approver** must lovingly be'))
	const run = ergo('compile', policy)
	assert.equal(run.status, 1)
	assert.match(run.stderr, /error: .*policy\.ergo\.md:\d+: approved: no operator matches/)
})

test('check passes when the committed object is up to date', () => {
	const run = ergo('check', POLICY)
	assert.equal(run.status, 0)
	assert.equal(run.stdout, `${COMPILED}: up to date with ${POLICY}\n`)
})

test('check names a check that no longer compiles, one that is new, and one that changed', () => {
	const dir = scratch()
	const committed = parseYaml(read(COMPILED)) as {requirements: {prod_deploy: {checks: Record<string, unknown>}}}
	const checks = committed.requirements.prod_deploy.checks
	checks['gone'] = {op: 'present', path: ['x']}
	delete checks['approved']
	const target = join(dir, 'data.yaml')
	writeFileSync(target, toYaml(committed, {lineWidth: 0}))
	const run = ergo('check', POLICY, target)
	assert.equal(run.status, 1)
	assert.match(run.stderr, /check "prod_deploy\.gone" no longer compiles/)
	assert.match(run.stderr, /check "prod_deploy\.approved" is new and not committed/)
})

test('check notices a change nested inside a check', () => {
	const dir = scratch()
	const target = join(dir, 'data.yaml')
	writeFileSync(target, read(COMPILED).replace('value: success', 'value: neutral'))
	const run = ergo('check', POLICY, target)
	assert.equal(run.status, 1)
	assert.match(run.stderr, /check "prod_deploy\.ci_green" changed/)
})

test('check notices a difference outside the checks', () => {
	const dir = scratch()
	const target = join(dir, 'data.yaml')
	writeFileSync(target, read(COMPILED).replace('- name', '- id'))
	const run = ergo('check', POLICY, target)
	assert.equal(run.status, 1)
	assert.match(run.stderr, /differs from a fresh compile/)
})

test('explain shows what each block became, with the expression ergo will report', () => {
	const run = ergo('explain', POLICY)
	assert.equal(run.status, 0)
	assert.match(run.stdout, /rule\s+approved\s+non_empty_string\n\s+"approved_by is a non-empty string"/)
	assert.match(run.stdout, /2 checks, 1 scope filter, 0 substitutes, 0 unclaimed sentences that look like rules/)
})

test('explain fails on a policy with errors', () => {
	const dir = scratch()
	const policy = join(dir, 'policy.ergo.md')
	writeFileSync(policy, read(POLICY).replace('**approver** must be', '**approver** must lovingly be'))
	const run = ergo('explain', policy)
	assert.equal(run.status, 1)
	assert.match(run.stderr, /approved: no operator matches/)
})

test('lint accepts a valid object and rejects a broken one', () => {
	assert.equal(ergo('lint', COMPILED).stdout, `${COMPILED}: valid\n`)
	const dir = scratch()
	const broken = join(dir, 'data.yaml')
	writeFileSync(broken, read(COMPILED).replace('op: non_empty_string', 'op: non_empty'))
	const run = ergo('lint', broken)
	assert.equal(run.status, 1)
	assert.match(run.stderr, /unknown operator "non_empty"/)
})

test('lint knows the custom operators given with --ops', () => {
	const dir = scratch()
	const spec = join(dir, 'data.yaml')
	writeFileSync(spec, 'requirements:\n  r:\n    checks:\n      c: {op: even, path: [n]}\n')
	const ops = join(dir, 'ops.json')
	writeFileSync(ops, JSON.stringify({even: {phrase: 'be even', expression: 'n is even', inputs: []}}))
	assert.match(ergo('lint', spec, '--ops', ops).stderr, /custom operator "even" declares no expression/)
	assert.match(ergo('lint', spec).stderr, /unknown operator "even"/)
})

test('apply writes an edited object back into the Markdown', () => {
	const dir = scratch()
	const policy = copy(POLICY, dir, 'policy.ergo.md')
	const spec = join(dir, 'edited.yaml')
	writeFileSync(spec, read(COMPILED).replace('A named approver signed off on the deployment', 'Someone else signed off'))
	const run = ergo('apply', policy, spec)
	assert.equal(run.status, 0)
	assert.equal(run.stdout, '  rewrote prod_deploy.approved\n')
	assert.match(readFileSync(policy, 'utf8'), /Someone else\s+signed off\./)
	assert.equal(ergo('apply', policy, spec).stdout, `${policy}: already says this\n`)
})

test('apply leaves the Markdown alone when it cannot write the edit', () => {
	const dir = scratch()
	const policy = copy(POLICY, dir, 'policy.ergo.md')
	const spec = join(dir, 'edited.yaml')
	writeFileSync(spec, read(COMPILED).replace('op: non_empty_string', 'op: any_of'))
	const run = ergo('apply', policy, spec)
	assert.equal(run.status, 1)
	assert.match(run.stderr, /no prose writes the operator "any_of"/)
	assert.match(run.stderr, /not written/)
	assert.equal(readFileSync(policy, 'utf8'), read(POLICY))
})

test('apply refuses an edit that would not read back as asked', () => {
	const dir = scratch()
	const policy = copy(POLICY, dir, 'policy.ergo.md')
	const spec = join(dir, 'edited.yaml')
	writeFileSync(spec, read(COMPILED).replace('    id:\n      - name\n', '    id:\n      - name\n    extra: true\n'))
	const run = ergo('apply', policy, spec)
	assert.equal(run.status, 1)
	assert.match(run.stderr, /prod_deploy\.extra does not come back from the patched document/)
	assert.equal(readFileSync(policy, 'utf8'), read(POLICY))
})

test('a wrong command, a missing file or an unknown option prints the usage', () => {
	for (const args of [[], ['build', POLICY], ['compile'], ['apply', POLICY], ['compile', POLICY, '--fast'], ['compile', POLICY, '-o']]) {
		const run = ergo(...args)
		assert.equal(run.status, 2, args.join(' '))
		assert.match(run.stderr, /usage:\n {2}ergo compile/)
	}
})

test('explain still works without opa, showing the shape of each check', () => {
	const run = spawnSync(process.execPath, ['src/cli.ts', 'explain', POLICY], {cwd: PACKAGE, encoding: 'utf8', env: {PATH: ''}})
	assert.equal(run.status, 0)
	assert.match(run.stdout, /rule\s+approved\s+non_empty_string\n\s+"non_empty_string approved_by"/)
	assert.match(run.stdout, /rule\s+ci_green\s+all\n\s+"all ci_checks -> conclusion == success"/)
})
