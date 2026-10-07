import json

from . import _ergo


class Operators:
    def __init__(self, definitions):
        self._json = json.dumps(definitions)
        _ergo.check_operators(self._json)


def report(input, requirements, params=None, operators=None):
    text = _ergo.report(
        json.dumps(input),
        json.dumps(requirements),
        None if params is None else json.dumps(params),
        None if operators is None else operators._json,
    )
    return json.loads(text)


def violations(report):
    return json.loads(_ergo.violations(json.dumps(report)))
