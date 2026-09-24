import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.request import urlopen
from urllib.error import HTTPError


RUNNER = Path(__file__).parents[1] / "benchmarks" / "llm_edit" / "run.py"
SPEC = importlib.util.spec_from_file_location("llm_edit_benchmark", RUNNER)
benchmark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(benchmark)


def load_bonsai(name="bonsai_driver_security"):
    path = Path(__file__).parents[1] / "scripts" / "bonsai_driver.py"
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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

    def test_basic_runner_extracts_codex_reported_tokens(self):
        self.assertEqual(benchmark.reported_tokens("tokens used\n\n22,778\n"), 22778)

    def test_jev_router_uses_fast_only_above_threshold(self):
        path = Path(__file__).parents[1] / "benchmarks" / "llm_edit" / "jev_router.py"
        spec = importlib.util.spec_from_file_location("jev_router_benchmark", path)
        router = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(router)
        payload = {
            "model": "jev-test",
            "answers": {
                "agent_tier": {
                    "type": "choice", "choice": "fast", "confidence": 0.79,
                    "probabilities": {"fast": 0.9, "strong": 0.1},
                },
                "task_risk": {"type": "score", "score": 0.5},
            },
            "usage": {"input_tokens": 123, "output_tokens": 10},
            "provider": "TypeSafe",
            "id": "decision-1",
        }
        low = router.interpret_response(payload, 0.8)
        self.assertEqual(low["selected_agent"], "strong")
        self.assertIsNotNone(low["fallback_reason"])
        payload["answers"]["agent_tier"]["confidence"] = 0.8
        high = router.interpret_response(payload, 0.8)
        self.assertEqual(high["selected_agent"], "fast")
        self.assertEqual(high["input_tokens"], 123)
        self.assertEqual(high["provider"], "TypeSafe")
        self.assertEqual(high["request_id"], "decision-1")

    def test_jev_router_fails_closed_on_invalid_response(self):
        path = Path(__file__).parents[1] / "benchmarks" / "llm_edit" / "jev_router.py"
        spec = importlib.util.spec_from_file_location("jev_router_invalid", path)
        router = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(router)
        decision = router.interpret_response({"answers": {}}, 0.8)
        self.assertEqual(decision["selected_agent"], "strong")
        self.assertIn("invalid Jev response", decision["fallback_reason"])

    def test_jev_router_does_not_send_source_text(self):
        path = Path(__file__).parents[1] / "benchmarks" / "llm_edit" / "jev_router.py"
        spec = importlib.util.spec_from_file_location("jev_router_state", path)
        router = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(router)
        source = Path(__file__).parents[1] / "examples" / "sample.e"
        state = router.route_state({"kind": "search", "prompt": "find it"}, source)
        serialized = json.dumps(state)
        self.assertNotIn(source.read_text(encoding="utf-8"), serialized)
        self.assertEqual(state["source"]["file_count"], 1)

    def test_model_endpoint_policy(self):
        jev_path = Path(__file__).parents[1] / "benchmarks" / "llm_edit" / "jev_router.py"
        jev_spec = importlib.util.spec_from_file_location("jev_router_urls", jev_path)
        jev = importlib.util.module_from_spec(jev_spec)
        jev_spec.loader.exec_module(jev)
        bonsai = load_bonsai("bonsai_driver_urls")
        for allowed in ("https://api.example/v1", "http://localhost:8080/v1",
                        "http://127.0.0.1:8080/v1", "http://[::1]:8080/v1"):
            self.assertTrue(jev.api_url_allowed(allowed))
            self.assertTrue(bonsai.endpoint_allowed(allowed))
        for refused in ("http://api.example/v1", "file:///tmp/key", "https://user@api.example/v1",
                        "https://api.example/v1?redirect=elsewhere", "not-a-url"):
            self.assertFalse(jev.api_url_allowed(refused))
            self.assertFalse(bonsai.endpoint_allowed(refused))

    def test_bonsai_model_tools_are_safe_by_default(self):
        bonsai = load_bonsai()
        tools, schemas = bonsai.exposed_tools()
        self.assertEqual(set(tools), {"read_lines", "search", "edit"})
        self.assertNotIn('"run"', json.dumps(schemas))
        unsafe_tools, unsafe_schemas = bonsai.exposed_tools(unsafe_compatibility=True)
        self.assertIn("run", unsafe_tools)
        self.assertIn('"run"', json.dumps(unsafe_schemas))

    def test_bonsai_read_and_search_paths_stay_in_checkout(self):
        bonsai = load_bonsai("bonsai_driver_paths")
        with tempfile.TemporaryDirectory() as temp:
            parent = Path(temp)
            root = parent / "repo"
            root.mkdir()
            (root / "inside.txt").write_text("inside\n", encoding="utf-8")
            (parent / "secret.txt").write_text("secret\n", encoding="utf-8")
            bonsai.ROOT = root
            self.assertIn("inside", bonsai.read_lines("inside.txt"))
            with self.assertRaisesRegex(ValueError, "path escapes repository"):
                bonsai.read_lines("../secret.txt")
            with self.assertRaisesRegex(ValueError, "path escapes repository"):
                bonsai.search("secret", "..")

    def test_bonsai_secure_mode_does_not_execute_model_changes(self):
        bonsai = load_bonsai("bonsai_driver_execution")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            task = root / "task.md"
            task.write_text("# candidate\n", encoding="utf-8")
            bonsai.ROOT = root
            bonsai.LOGS = root / "logs"
            bonsai.STATE = root / "state.json"
            argv = ["bonsai_driver.py", "--endpoint", "http://localhost:8080/v1"]
            with (patch.object(sys, "argv", argv),
                  patch.object(bonsai, "next_task", return_value=("candidate", task)),
                  patch.object(bonsai, "endpoint_up", return_value=True),
                  patch.object(bonsai, "session", return_value="done"),
                  patch.object(bonsai, "touched_paths", side_effect=[[], ["candidate.e"]]),
                  patch.object(bonsai, "suites") as suites,
                  patch.object(bonsai, "commit") as commit,
                  patch.object(bonsai, "revert") as revert):
                bonsai.main()
            suites.assert_not_called()
            commit.assert_not_called()
            revert.assert_not_called()

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
