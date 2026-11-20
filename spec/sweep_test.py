import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sweep


def write(directory, pairs):
    path = os.path.join(directory, "pairs.json")
    with open(path, "w") as handle:
        json.dump(pairs, handle)
    return path


def report(*messages):
    return {"results": [{"requirement": "r", "check": "c", "subject": "t", "passed": False, "message": m} for m in messages]}


class PairsTest(unittest.TestCase):
    def test_a_pair_gets_the_current_spec_and_empty_params(self):
        with tempfile.TemporaryDirectory() as directory:
            path = write(directory, [{"name": "n", "policy": {"subjects": {}}, "input": {}}])
            [built] = sweep.load_pairs(path)
        self.assertEqual(built["policy"], {"subjects": {}, "ergo_spec": sweep.spec_version()})
        self.assertEqual(built["params"], {})
        self.assertEqual(built["name"], "n")
        self.assertIsNone(built["want"])

    def test_a_pair_without_a_name_policy_or_input_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            path = write(directory, [{"name": "n", "policy": {}}])
            with self.assertRaises(SystemExit):
                sweep.load_pairs(path)

    def test_two_pairs_with_one_name_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            pair = {"name": "n", "policy": {}, "input": {}}
            path = write(directory, [pair, pair])
            with self.assertRaises(SystemExit):
                sweep.load_pairs(path)

    def test_an_engine_says_the_wanted_message_when_a_failed_row_has_it_exactly(self):
        self.assertTrue(sweep.says(report("a", "b"), "b"))
        self.assertFalse(sweep.says(report("a; b"), "b"))
        self.assertFalse(sweep.says({"error": "boom"}, "b"))

    def test_the_pairs_in_the_repo_are_valid_and_every_want_is_text(self):
        pairs = sweep.load_pairs(os.path.join(sweep.ROOT, ".github", "sweep-pairs.json"))
        self.assertGreater(len(pairs), 100)
        for pair in pairs:
            self.assertTrue(pair["want"] is None or isinstance(pair["want"], str), pair["name"])


if __name__ == "__main__":
    unittest.main()
