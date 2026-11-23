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

    def refused(self, version, tree):
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop(sweep.ALLOW_STALE, None)
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

    def test_an_old_binary_without_a_commit_is_accepted_when_old_ones_are_allowed(self):
        with tempfile.TemporaryDirectory() as directory:
            tree, _ = self.make_tree(directory)
            sweep.check_commit("ergo 0.5.0-dev", tree, allow_old=True)

    def test_allowing_old_binaries_still_stops_on_another_commit_and_on_unknown(self):
        with tempfile.TemporaryDirectory() as directory:
            tree, _ = self.make_tree(directory)
            with mock.patch.dict(os.environ, {}, clear=False):
                os.environ.pop(sweep.ALLOW_STALE, None)
                for version in ("ergo 0.5.0-dev (commit " + "a" * 40 + ")", "ergo 0.5.0-dev (commit unknown)"):
                    with self.assertRaises(SystemExit):
                        sweep.check_commit(version, tree, allow_old=True)

    def test_running_the_rust_engine_goes_on_with_an_old_binary_when_old_ones_are_allowed(self):
        with tempfile.TemporaryDirectory() as directory:
            tree, _ = self.make_tree(directory)
            seen = []

            def fake(argv, shell, script):
                seen.append(script)
                if len(seen) > 1:
                    raise RuntimeError("cells")
                return mock.Mock(stdout="ergo 0.5.0-dev\n")

            with mock.patch.object(sweep, "run_command", side_effect=fake), \
                    mock.patch.dict(os.environ, {}, clear=False):
                os.environ.pop(sweep.ALLOW_STALE, None)
                with self.assertRaises(RuntimeError):
                    sweep.run_rust("sh -s", ["0"], tree, allow_old=True)
        self.assertEqual(len(seen), 2)

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


def one_row(passed=True, cause="satisfied", message="m", check="c"):
    return {"requirement": "r", "check": check, "subject": "t", "passed": passed, "cause": cause, "message": message}


def whole(*rows, compliant=True, status="pass"):
    return {"compliant": compliant, "requirements": {"r": {"status": status}}, "results": list(rows)}


class KindTest(unittest.TestCase):
    def test_equal_reports_are_no_difference(self):
        self.assertEqual(sweep.kind(whole(one_row()), whole(one_row())), 0)

    def test_a_row_that_passes_in_one_engine_and_fails_in_the_other_is_type_1(self):
        self.assertEqual(sweep.kind(whole(one_row()), whole(one_row(passed=False))), 1)

    def test_compliant_differing_is_type_1(self):
        self.assertEqual(sweep.kind(whole(one_row(), compliant=True), whole(one_row(), compliant=False)), 1)

    def test_a_requirement_status_differing_is_type_1(self):
        self.assertEqual(sweep.kind(whole(one_row(), status="pass"), whole(one_row(), status="fail")), 1)

    def test_a_row_in_one_engine_only_is_type_1(self):
        self.assertEqual(sweep.kind(whole(one_row(), one_row(check="d")), whole(one_row())), 1)

    def test_an_error_in_one_engine_only_is_type_1(self):
        self.assertEqual(sweep.kind(whole(one_row()), {"error": "boom"}), 1)

    def test_only_a_row_cause_differing_is_type_2(self):
        self.assertEqual(sweep.kind(whole(one_row(False, "value")), whole(one_row(False, "missing"))), 2)

    def test_only_a_message_differing_is_type_3(self):
        self.assertEqual(sweep.kind(whole(one_row(False, "value", "a")), whole(one_row(False, "value", "b"))), 3)

    def test_two_different_errors_are_type_3(self):
        self.assertEqual(sweep.kind({"error": "a"}, {"error": "b"}), 3)

    def test_a_duplicate_row_in_one_engine_only_is_type_1(self):
        self.assertEqual(sweep.kind(whole(one_row(), one_row()), whole(one_row())), 1)

    def test_rows_with_one_key_and_swapped_verdicts_are_type_1(self):
        left = whole(one_row(True), one_row(False, "value"))
        right = whole(one_row(False, "value"), one_row(False, "value"))
        self.assertEqual(sweep.kind(left, right), 1)

    def test_a_verdict_difference_wins_over_a_cause_difference(self):
        left = whole(one_row(False, "value"), one_row(check="d"))
        right = whole(one_row(False, "missing"), one_row(passed=False, check="d"))
        self.assertEqual(sweep.kind(left, right), 1)


class SummaryTest(unittest.TestCase):
    def test_the_summary_counts_each_type_and_names_the_cells_of_types_1_and_2(self):
        found = {1: ["a | cell 1"], 2: ["b | cell 2", "c | cell 3"], 3: ["d"] * 4}
        lines = sweep.type_lines(found)
        self.assertIn("type 1 (verdict differs): 1", lines)
        self.assertIn("type 2 (a row's cause differs): 2", lines)
        self.assertIn("type 3 (anything else): 4", lines)
        self.assertIn("- a | cell 1", lines)
        self.assertIn("- c | cell 3", lines)
        self.assertNotIn("- d", lines)

    def test_requiring_no_type_1_fails_only_when_one_is_left(self):
        self.assertEqual(sweep.type_exit({1: ["a"], 2: [], 3: []}, True), 1)
        self.assertEqual(sweep.type_exit({1: [], 2: ["a"], 3: ["b"]}, True), 0)
        self.assertEqual(sweep.type_exit({1: ["a"], 2: [], 3: []}, False), 0)


if __name__ == "__main__":
    unittest.main()
