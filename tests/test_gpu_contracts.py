import copy
import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "gpu_contracts", ROOT / "scripts/check_gpu_contracts.py")
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class GpuContractTests(unittest.TestCase):
    def test_repository_contract(self):
        data, errors = CHECKER.validate(ROOT)
        self.assertEqual(errors, [])
        self.assertEqual(list(data["requirements"]), ["H13", "H21", "H22", "H23"])

    def test_release_checks_cannot_disappear(self):
        data, _ = CHECKER.validate(ROOT)
        checks = copy.deepcopy(data["requirements"]["H13"]["checks"])
        checks["bounds"]["release"] = "off"
        self.assertNotEqual(checks["bounds"]["release"], "fault")

    def test_completion_tokens_name_only_past_work(self):
        data, errors = CHECKER.validate(ROOT)
        self.assertEqual(errors, [])
        h21 = data["requirements"]["H21"]
        self.assertEqual(h21["token_states"],
                         ["queued", "running", "complete", "lost", "stale"])
        self.assertEqual(h21["cancellation"], "not_in_v1")

    def test_cost_contract_never_mixes_clocks_or_grows_staging(self):
        data, errors = CHECKER.validate(ROOT)
        self.assertEqual(errors, [])
        h22 = data["requirements"]["H22"]
        self.assertFalse(h22["timeline"]["cross_clock_subtraction"])
        self.assertEqual(h22["staging"]["on_full"], "wait_oldest")
        self.assertIn("safety_policy", h22["cache_key"])
        self.assertIn("numerical_policy", h22["cache_key"])

    def test_numerical_rows_name_every_backend_and_limit(self):
        data, errors = CHECKER.validate(ROOT)
        self.assertEqual(errors, [])
        rows = data["requirements"]["H23"]["matrix"]
        self.assertEqual(len(rows), 21)
        for row in rows:
            self.assertEqual(set(row["backends"]), {"cpu", "spv", "ptx"})
            self.assertIsInstance(row["subgroup_dependent"], bool)
            self.assertIsInstance(row["nondeterministic"], bool)
        denormal = next(row for row in rows if row["id"] == "denormal_preserve")
        self.assertIn("DenormPreserve", denormal["capabilities"])

    def test_closure_is_design_only_and_runtime_evidence_stays_pending(self):
        data, errors = CHECKER.validate(ROOT)
        self.assertEqual(errors, [])
        self.assertEqual(data["scope"], "m25_design_only")
        self.assertTrue(all(item["runtime_status"] == "pending_m3"
                            for item in data["requirements"].values()))
        self.assertEqual(sum(len(item["fixtures"])
                             for item in data["requirements"].values()), 32)


if __name__ == "__main__":
    unittest.main()
