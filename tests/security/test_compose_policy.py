"""Security policy on the REAL rendered Compose models (`docker compose config`).

Needs the docker CLI with the compose plugin (no daemon access, no containers
are created). Skipped otherwise.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

from pentestlab import policy
from tests.helpers import NETWORK, TempConfigMixin

LAB_IP = NETWORK["lab_host_ip"]
ALLOWED = {"127.0.0.1", LAB_IP}


def _compose_available() -> bool:
    if not shutil.which("docker"):
        return False
    return subprocess.run(["docker", "compose", "version"], capture_output=True).returncode == 0


@unittest.skipUnless(_compose_available(), "docker compose no disponible")
class RenderedComposeTest(TempConfigMixin):
    def setUp(self):
        self.cfg = self.make_config({"network": NETWORK})
        self.tmp = Path(tempfile.mkdtemp(prefix="plab-sec-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def render(self, lab, override: str | None = None) -> dict:
        env = self.tmp / f"{lab.id}.env"
        env.write_text("".join(f"{k}={v}\n" for k, v in self.cfg.render_env(lab, LAB_IP).items()))
        cmd = ["docker", "compose", "--project-name", lab.project, "--file", str(lab.compose_file)]
        if override:
            o = self.tmp / f"{lab.id}.override.yaml"
            o.write_text(textwrap.dedent(override))
            cmd += ["--file", str(o)]
        cmd += ["--env-file", str(env), "config", "--format", "json"]
        proc = subprocess.run(cmd, capture_output=True, text=True, cwd=lab.dir, timeout=60)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return json.loads(proc.stdout)

    def test_every_lab_complies(self):
        for lab in self.cfg.labs.values():
            with self.subTest(lab=lab.id):
                model = self.render(lab)
                self.assertEqual(policy.check(model, ALLOWED), [])
                published = {(p["host_ip"], int(p["published"]))
                             for p in model["services"]["edge"].get("ports", [])}
                expected = {(ip, ep.port) for ep in lab.endpoints.values() for ip in sorted(ALLOWED)}
                self.assertEqual(published, expected, "solo los puertos documentados, en 127.0.0.1 y la IP de laboratorio")

    def test_hostile_overrides_are_detected(self):
        lab = self.cfg.labs["dvwa"]
        cases = {
            "0.0.0.0": """
                services:
                  db:
                    ports: ["3306:3306"]
            """,
            "socket": """
                services:
                  dvwa:
                    volumes: ["/var/run/docker.sock:/var/run/docker.sock"]
            """,
            "privileged": """
                services:
                  dvwa:
                    privileged: true
            """,
            "internal: true": """
                networks:
                  front:
                    internal: false
            """,
            "dns": """
                services:
                  edge:
                    dns: ["1.1.1.1"]
            """,
        }
        for fragment, override in cases.items():
            with self.subTest(case=fragment):
                v = policy.check(self.render(lab, override), ALLOWED)
                self.assertTrue(any(fragment in x for x in v), v)


if __name__ == "__main__":
    unittest.main()
