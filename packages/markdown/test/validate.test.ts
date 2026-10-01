import {test} from 'node:test'
import assert from 'node:assert/strict'
import {validateRequirements} from '../src/core/validate.ts'

const messages = (requirements: unknown, customOps: string[] = []): string[] => validateRequirements(requirements, new Set(customOps)).map((d) => d.message)

const one = (check: unknown): unknown => ({r: {checks: {c: check}}})

test('a well-formed policy has nothing to report', () => {
	assert.deepEqual(messages(one({op: 'equals', path: ['a'], value: 1})), [])
})

test('requirements that are not an object are an error', () => {
	assert.deepEqual(messages(null), ['requirements is not an object'])
	assert.deepEqual(messages({r: 1}), ['r: not an object'])
})

test('a requirement with no checks asserts nothing', () => {
	assert.deepEqual(messages({r: {checks: {}}}), ['r: declares no checks, so it asserts nothing'])
})

test('require must be every or some', () => {
	assert.deepEqual(messages({r: {require: 'all', checks: {c: {op: 'present', path: ['a']}}}}), ['r: require must be "every" or "some"'])
})

test('names starting with $ belong to ergo', () => {
	assert.deepEqual(messages({r: {checks: {$mine: {op: 'present', path: ['a']}}}}), ['r.$mine: names beginning with $ are the library\'s'])
})

test('a misspelled operator is an error, because ergo would accept it and never pass it', () => {
	assert.match(messages(one({op: 'equal', path: ['a'], value: 1}))[0]!, /unknown operator "equal"/)
	assert.deepEqual(messages(one({path: ['a']})), ['r.c: no operator'])
})

test('a missing or unexpected field is an error', () => {
	assert.deepEqual(messages(one({op: 'equals', path: ['a']})), ['r.c: operator "equals" needs "value"'])
	assert.deepEqual(messages(one({op: 'equals', path: ['a'], values: [1], value: 1})), ['r.c: operator "equals" does not read "values"'])
})

test('cmp must be a known comparison', () => {
	assert.match(messages(one({op: 'compare', left: ['a'], right: ['b'], cmp: 'bigger'}))[0]!, /"bigger" is not a comparison/)
})

test('the check inside all, any_of options and substitutes are checked too', () => {
	assert.deepEqual(messages(one({op: 'all', path: ['xs'], check: {op: 'equals', path: ['a']}})), ['r.c > element: operator "equals" needs "value"'])
	assert.deepEqual(messages(one({op: 'present', path: ['a'], substitute: {op: 'nope'}})).length, 1)
	assert.deepEqual(messages(one({op: 'any_of', options: {x: [{op: 'equals', path: ['a']}]}})), ['r.c > x: operator "equals" needs "value"'])
})

test('an any_of option must be a non-empty list of leaf checks', () => {
	assert.match(messages(one({op: 'any_of', options: {x: []}}))[0]!, /any_of option "x" is not a non-empty list/)
	assert.match(messages(one({op: 'any_of', options: {x: [{op: 'all', path: ['xs'], check: {op: 'present', path: []}}]}}))[0]!, /contains "all"/)
})

test('a custom operator must bring an expression and say what it reads', () => {
	assert.deepEqual(messages(one({op: 'even'}), ['even']), ['r.c: custom operator "even" declares no expression', 'r.c: custom operator "even" declares neither inputs nor path'])
	assert.deepEqual(messages(one({op: 'even', expression: 'n is even', path: ['n']}), ['even']), [])
})
