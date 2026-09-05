import importlib.util
import json
from pathlib import Path
import sys
import threading
import unittest
from urllib.request import urlopen
from urllib.error import HTTPError


RUNNER = Path(__file__).parents[1] / "benchmarks" / "llm_edit" / "run.py"
SPEC = importlib.util.spec_from_file_location("llm_edit_benchmark", RUNNER)
benchmark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(benchmark)


class BenchmarkScoringTests(unittest.TestCase):
    def test_search_requires_exact_answer(self):
        task = {"kind": "search", "expected": "sensor_cmp"}
        self.assertTrue(benchmark.score(task, "", "", "sensor_cmp\n")[0])
        self.assertFalse(benchmark.score(task, "", "", "The answer is sensor_cmp")[0])

    def test_update_checks_content_and_edit_budget(self):
        task = {
            "kind": "update", "checks": [{"pattern": r"VALUE = 2", "count": 1}],
            "max_changed_lines": 2,
        }
        self.assertTrue(benchmark.score(task, "VALUE = 1\n", "VALUE = 2\n", "")[0])
        self.assertFalse(benchmark.score(task, "VALUE = 1\n", "VALUE = 3\n", "")[0])

    def test_changed_lines_counts_removed_and_added_lines(self):
        self.assertEqual(benchmark.changed_lines("a\nb\n", "a\nc\n"), 2)

    def test_extracts_codex_reported_tokens(self):
        semantic_path = Path(__file__).parents[1] / "benchmarks" / "llm_edit" / "semantic.py"
        spec = importlib.util.spec_from_file_location("semantic_benchmark", semantic_path)
        semantic = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(semantic)
        output = "agent response\ntokens used\n\n22,778\n"
        self.assertEqual(semantic.reported_tokens(output), 22778)

    def test_audits_observable_agent_activity(self):
        semantic_path = Path(__file__).parents[1] / "benchmarks" / "llm_edit" / "semantic.py"
        spec = importlib.util.spec_from_file_location("semantic_audit", semantic_path)
        semantic = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(semantic)
        transcript = (
            "exec\nrg adjust src\\module_0013.e\n"
            "exec\nGet-Content src\\module_0013.e\n"
            "// generated e filler line 0001\napply patch\n"
        )
        audit = semantic.transcript_audit(transcript)
        self.assertEqual(audit["tool_calls"], 3)
        self.assertEqual(audit["read_commands"], 1)
        self.assertEqual(audit["patch_operations"], 1)
        self.assertEqual(audit["source_paths_observed"], 1)

    def test_hard_context_server_enforces_read_limit(self):
        path = Path(__file__).parents[1] / "benchmarks" / "llm_edit" / "hard_context.py"
        spec = importlib.util.spec_from_file_location("hard_context_benchmark", path)
        hard = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = hard
        spec.loader.exec_module(hard)
        corpus = hard.build_corpus("e", seed=7, read_limit=3)
        server = hard.server_for(corpus)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            host, port = server.server_address
            base = f"http://{host}:{port}"
            matches = json.loads(urlopen(f"{base}/search?q={corpus.api}").read())
            self.assertEqual(len(matches["matches"]), 9)
            indexed = json.loads(urlopen(f"{base}/index?q={corpus.api}").read())
            self.assertEqual(len(indexed["records"]), 9)
            urlopen(f"{base}/read?path=src/calibration.e&start=1&end=3").read()
            with self.assertRaises(HTTPError) as error:
                urlopen(f"{base}/read?path=src/calibration.e&start=1&end=4").read()
            self.assertEqual(error.exception.code, 429)
            self.assertEqual(corpus.read_lines, 3)
        finally:
            server.shutdown()
            server.server_close()

    def test_hard_context_supports_javascript_and_typescript(self):
        path = Path(__file__).parents[1] / "benchmarks" / "llm_edit" / "hard_context.py"
        spec = importlib.util.spec_from_file_location("hard_context_web_benchmark", path)
        hard = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = hard
        spec.loader.exec_module(hard)
        for language, signature, body in (
            ("js", "export function adjust_sensor_", "return reading * gain + offset;"),
            ("ts", "export function adjust_sensor_", "return reading * gain + offset;"),
        ):
            corpus = hard.build_corpus(language, seed=7, read_limit=500)
            api_path = f"src/calibration.{language}"
            old = corpus.files[api_path]
            if language == "js":
                new = old.replace("(reading, offset)", "(reading, gain, offset)").replace(
                    "return reading + offset;", body)
            else:
                new = old.replace("(reading: number, offset: number): number",
                                  "(reading: number, gain: number, offset: number): number").replace(
                    "return reading + offset;", body)
            corpus.files[api_path] = new
            for module in corpus.callers:
                caller_path = f"src/module_{module:04d}.{language}"
                corpus.files[caller_path] = corpus.files[caller_path].replace(
                    f"{corpus.api}(41.7, 0.25);", f"{corpus.api}(41.7, 1.0, 0.25);")
            passed, detail = hard.evaluate(corpus)
            self.assertTrue(passed, f"{language}: {detail}")
            self.assertIn(signature, corpus.files[api_path])


if __name__ == "__main__":
    unittest.main()
