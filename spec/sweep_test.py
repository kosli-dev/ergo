import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

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

    def run_pairs_with(self, rust):
        with tempfile.TemporaryDirectory() as directory:
            path = write(directory, [{"name": "n", "policy": {}, "input": {}}])
            args = mock.Mock(pairs=path, opa="opa", rust="rust")
            with mock.patch.object(sweep.subprocess, "run"), \
                    mock.patch.object(sweep, "run_rego", return_value=[report("a")]), \
                    mock.patch.object(sweep, "run_rust", **rust):
                try:
                    sweep.run_pairs(args)
                except RuntimeError:
                    pass

    def test_a_pairs_run_leaves_no_sweep_folder_in_dist(self):
        self.run_pairs_with({"return_value": ("v", [report("a")])})
        self.assertFalse(os.path.exists(sweep.WORK))

    def test_a_failed_pairs_run_leaves_no_sweep_folder_in_dist(self):
        self.run_pairs_with({"side_effect": RuntimeError("boom")})
        self.assertFalse(os.path.exists(sweep.WORK))


class StaleBinaryTest(unittest.TestCase):
    def make_tree(self, directory):
        tree = os.path.join(directory, "tree")
        os.makedirs(tree)
        env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
        for argv in (["init", "-q"], ["commit", "-q", "--allow-empty", "-m", "one"]):
            subprocess.run(["git", "-C", tree] + argv, check=True, env=env)
        head = subprocess.run(["git", "-C", tree, "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()
        return tree, head

    def refused(self, version, tree, environ=None):
        with mock.patch.dict(os.environ, environ or {}, clear=False):
            os.environ.pop(sweep.ALLOW_STALE, None) if not environ else None
            with self.assertRaises(SystemExit) as caught:
                sweep.check_commit(version, tree)
        return str(caught.exception)

    def test_a_binary_built_from_the_commit_of_the_tree_is_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            tree, head = self.make_tree(directory)
            sweep.check_commit(f"ergo 0.5.0-dev (commit {head})", tree)

    def test_a_binary_built_from_another_commit_stops_with_both_commits_and_the_way_to_skip(self):
        with tempfile.TemporaryDirectory() as directory:
            tree, head = self.make_tree(directory)
            message = self.refused("ergo 0.5.0-dev (commit " + "a" * 40 + ")", tree)
        self.assertIn("a" * 40, message)
        self.assertIn(head, message)
        self.assertIn(sweep.ALLOW_STALE, message)
        self.assertIn("rebuild", message.lower())

    def test_a_binary_that_does_not_say_its_commit_stops(self):
        with tempfile.TemporaryDirectory() as directory:
            tree, _ = self.make_tree(directory)
            self.assertIn("commit", self.refused("ergo 0.5.0-dev", tree))
            self.assertIn("unknown", self.refused("ergo 0.5.0-dev (commit unknown)", tree))

    def test_the_variable_in_the_message_lets_a_stale_binary_run(self):
        with tempfile.TemporaryDirectory() as directory:
            tree, _ = self.make_tree(directory)
            with mock.patch.dict(os.environ, {sweep.ALLOW_STALE: "1"}):
                sweep.check_commit("ergo 0.5.0-dev (commit " + "a" * 40 + ")", tree)
                sweep.check_commit("ergo 0.5.0-dev", tree)

    def test_a_dirty_tree_is_said_in_the_message_and_only_the_commit_is_compared(self):
        with tempfile.TemporaryDirectory() as directory:
            tree, head = self.make_tree(directory)
            with open(os.path.join(tree, "new.txt"), "w") as handle:
                handle.write("x")
            sweep.check_commit(f"ergo 0.5.0-dev (commit {head})", tree)
            message = self.refused("ergo 0.5.0-dev (commit " + "a" * 40 + ")", tree)
        self.assertIn("uncommitted changes", message)

    def test_a_clean_tree_does_not_mention_uncommitted_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            tree, _ = self.make_tree(directory)
            self.assertNotIn("uncommitted", self.refused("ergo 0.5.0-dev (commit " + "a" * 40 + ")", tree))

    def test_running_the_rust_engine_stops_before_any_cell_when_the_binary_is_stale(self):
        with tempfile.TemporaryDirectory() as directory:
            tree, _ = self.make_tree(directory)
            seen = []

            def fake(argv, shell, script):
                seen.append(script)
                return mock.Mock(stdout="ergo 0.5.0-dev (commit " + "a" * 40 + ")\n")

            with mock.patch.object(sweep, "run_command", side_effect=fake), \
                    mock.patch.dict(os.environ, {}, clear=False):
                os.environ.pop(sweep.ALLOW_STALE, None)
                with self.assertRaises(SystemExit):
                    sweep.run_rust("sh -s", ["0"], tree)
        self.assertEqual(seen, ["ergo --version"])


if __name__ == "__main__":
    unittest.main()
