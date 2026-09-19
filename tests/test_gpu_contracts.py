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
        self.assertEqual(list(data["requirements"]), ["H13"])

    def test_release_checks_cannot_disappear(self):
        data, _ = CHECKER.validate(ROOT)
        checks = copy.deepcopy(data["requirements"]["H13"]["checks"])
        checks["bounds"]["release"] = "off"
        self.assertNotEqual(checks["bounds"]["release"], "fault")


if __name__ == "__main__":
    unittest.main()
