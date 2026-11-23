"""Static checks on the lab definitions shipped in labs/."""
import json
import re
import unittest
from pathlib import Path

from pentestlab import LABS_DIR

EDGE = LABS_DIR / "_common" / "edge" / "edge.compose.yaml"


class LabDefinitionsTest(unittest.TestCase):
    def labs(self):
        for meta in sorted(LABS_DIR.glob("*/lab.json")):
            yield json.loads(meta.read_text(encoding="utf-8")), meta.parent

    def test_project_and_bridge_naming(self):
        for meta, d in self.labs():
            with self.subTest(lab=meta["id"]):
                self.assertEqual(meta["project"], f"plab-{meta['id']}")
                compose = (d / "compose.yaml").read_text(encoding="utf-8")
                names = re.findall(r"com\.docker\.network\.bridge\.name:\s*\"?([\w.-]+)", compose)
                self.assertTrue(names)
                for n in names:
                    self.assertRegex(n, r"^plab[ei]-")
                    self.assertLessEqual(len(n), 15, f"{n}: Linux limits interface names to 15 chars")

    def test_images_come_from_pinned_variables(self):
        for meta, d in self.labs():
            compose = (d / "compose.yaml").read_text(encoding="utf-8")
            for ref in re.findall(r"^\s*image:\s*(\S+)", compose, re.M):
                with self.subTest(lab=meta["id"], ref=ref):
                    self.assertRegex(ref, r"^\$\{[A-Z_]+:\?.*\}$")

    def test_edge_proxy_uses_loopback_dns(self):
        """Regression: Docker's embedded DNS resolved external names for the proxy."""
        self.assertRegex(EDGE.read_text(encoding="utf-8"), r'dns:\s*\["127\.0\.0\.1"\]')

    def test_post_start_hooks_are_well_formed(self):
        for meta, _ in self.labs():
            for hook in meta.get("post_start", []):
                with self.subTest(lab=meta["id"], hook=hook["description"]):
                    run = hook["run"]
                    self.assertIn(run["type"], ("http", "exec"))
                    if run["type"] == "exec":
                        self.assertIn(run["service"], meta["services"])
                    if "check" in hook:
                        self.assertIn(hook["check"]["service"], meta["services"])

    def test_dvwa_creates_its_database(self):
        """Regression: DVWA does not create its tables on its own (needs setup.php)."""
        meta = json.loads((LABS_DIR / "dvwa" / "lab.json").read_text(encoding="utf-8"))
        hook = next(h for h in meta["post_start"] if "setup.php" in " ".join(h["run"]["command"]))
        self.assertIn("users", " ".join(hook["check"]["command"]))  # only when the table is missing
        self.assertIn("user_token", " ".join(hook["run"]["command"]))


if __name__ == "__main__":
    unittest.main()
