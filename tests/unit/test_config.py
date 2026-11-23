import json
import unittest

from pentestlab import config as config_mod
from pentestlab.config import deep_merge, parse_memory, validate_cpus, validate_port
from pentestlab.errors import LabError
from tests.helpers import NETWORK, TempConfigMixin

LAB_IDS = {"dvwa", "juice-shop", "mutillidae", "webgoat"}


class ParsersTest(unittest.TestCase):
    def test_parse_memory(self):
        self.assertEqual(parse_memory("512m"), 512 * 1024 ** 2)
        self.assertEqual(parse_memory("2G"), 2 * 1024 ** 3)
        for bad in ("2k", "512", "m", "-1m", "1.5g", ""):
            with self.subTest(bad=bad), self.assertRaises(LabError):
                parse_memory(bad)

    def test_validate_port(self):
        validate_port(1024)
        validate_port(65535)
        for bad in (80, 1023, 65536, "4280", 4280.0):
            with self.subTest(bad=bad), self.assertRaises(LabError):
                validate_port(bad)

    def test_validate_cpus(self):
        validate_cpus(0.25)
        validate_cpus(2)
        for bad in (0, -1, 999, "1"):
            with self.subTest(bad=bad), self.assertRaises(LabError):
                validate_cpus(bad)

    def test_deep_merge_does_not_mutate(self):
        base = {"a": {"b": 1, "c": 2}, "x": [1]}
        out = deep_merge(base, {"a": {"b": 9}, "x": [2]})
        self.assertEqual(out, {"a": {"b": 9, "c": 2}, "x": [2]})
        self.assertEqual(base, {"a": {"b": 1, "c": 2}, "x": [1]})


class ConfigTest(TempConfigMixin):
    def test_repository_defaults_are_valid(self):
        cfg = self.make_config({"network": NETWORK})
        self.assertEqual(set(cfg.labs), LAB_IDS)
        self.assertEqual(cfg.validate(), [])

    def test_invalid_local_json_is_reported(self):
        self.make_config()  # patches LOCAL_FILE to a temp file
        self.local_file.write_text("{not json", encoding="utf-8")
        with self.assertRaises(LabError):
            self.make_config_from_existing()

    def test_default_ports_are_unique_and_documented(self):
        cfg = self.make_config({"network": NETWORK})
        ports = {(lab.id, ep.key): ep.port for lab in cfg.labs.values() for ep in lab.endpoints.values()}
        self.assertEqual(ports, {("dvwa", "http"): 4280, ("juice-shop", "http"): 3000,
                                 ("mutillidae", "http"): 8081, ("mutillidae", "https"): 8443,
                                 ("webgoat", "http"): 8080, ("webgoat", "webwolf"): 9090})

    def test_duplicate_port_is_rejected(self):
        cfg = self.make_config({"network": NETWORK})
        cfg.set_port(cfg.labs["dvwa"], "http", 3000)
        self.assertTrue(any("duplicado" in p for p in cfg.validate()))

    def test_lab_interface_with_reserved_prefix_is_rejected(self):
        cfg = self.make_config({"network": {**NETWORK, "lab_interface": "plabsim-h"}})
        self.assertTrue(any("plab" in p for p in cfg.validate()))
        for ok in ("vboxnet1", "virbr-plab", "simlab-h"):
            cfg = self.make_config({"network": {**NETWORK, "lab_interface": ok}})
            self.assertEqual(cfg.validate(), [], ok)

    def test_nat_interface_validation(self):
        for bad in ("plabnat", "virbr-plab", "bad name!"):
            cfg = self.make_config({"network": {**NETWORK, "lab_interface": "virbr-plab", "nat_interface": bad}})
            self.assertTrue(any("NAT" in p for p in cfg.validate()), bad)
        cfg = self.make_config({"network": {**NETWORK, "lab_interface": "virbr-plab", "nat_interface": "virbr0"}})
        self.assertEqual(cfg.validate(), [])
        self.assertEqual(cfg.nat_interface, "virbr0")
        cfg.set_network(nat_interface="")
        self.assertIsNone(cfg.nat_interface)

    def test_set_port_unknown_endpoint(self):
        cfg = self.make_config({"network": NETWORK})
        with self.assertRaises(LabError):
            cfg.set_port(cfg.labs["dvwa"], "https", 4443)

    def test_set_persistence(self):
        cfg = self.make_config({"network": NETWORK})
        cfg.set_persistence(cfg.labs["dvwa"], "ephemeral")
        self.assertEqual(cfg.labs["dvwa"].persistence, "ephemeral")
        with self.assertRaises(LabError):
            cfg.set_persistence(cfg.labs["dvwa"], "bogus")
        # Juice Shop regenerates its database on every start: ephemeral only.
        with self.assertRaises(LabError):
            cfg.set_persistence(cfg.labs["juice-shop"], "persistent")

    def test_set_resources_and_render_env(self):
        cfg = self.make_config({"network": NETWORK})
        lab = cfg.labs["dvwa"]
        cfg.set_resources(lab, "db", 0.75, "384m")
        env = cfg.render_env(lab, "192.168.57.1")
        self.assertEqual(env["DVWA_DB_CPUS"], "0.75")
        self.assertEqual(env["DVWA_DB_MEMORY"], "384m")
        self.assertEqual(env["LAB_HOST_IP"], "192.168.57.1")
        self.assertEqual(env["COMPOSE_PROJECT_NAME"], "plab-dvwa")
        self.assertIn("@sha256:", env["DVWA_IMAGE"])
        with self.assertRaises(LabError):
            cfg.set_resources(lab, "nope", 1, None)

    def test_save_writes_only_local_overrides(self):
        cfg = self.make_config({"network": NETWORK})
        cfg.set_port(cfg.labs["dvwa"], "http", 4281)
        cfg.save()
        saved = json.loads(self.local_file.read_text(encoding="utf-8"))
        self.assertEqual(saved["labs"]["dvwa"]["ports"], {"http": 4281})
        self.assertNotIn("juice-shop", saved.get("labs", {}))
        self.assertEqual(self.make_config_from_existing().labs["dvwa"].endpoints["http"].port, 4281)

    def test_resolve_labs(self):
        cfg = self.make_config({"network": NETWORK})
        self.assertEqual({l.id for l in cfg.resolve_labs(None)}, LAB_IDS)
        self.assertEqual({l.id for l in cfg.resolve_labs(["all"])}, LAB_IDS)
        self.assertEqual([l.id for l in cfg.resolve_labs(["dvwa"])], ["dvwa"])
        with self.assertRaises(LabError):
            cfg.resolve_labs(["nolab"])


class VersionsTest(TempConfigMixin):
    def test_every_image_is_pinned_by_tag_and_digest(self):
        cfg = self.make_config({"network": NETWORK})
        for var, img in cfg.versions["images"].items():
            with self.subTest(var=var):
                self.assertNotEqual(img["tag"], "latest")
                self.assertRegex(img["digest"], r"^sha256:[0-9a-f]{64}$")

    def test_every_lab_image_is_defined(self):
        cfg = self.make_config({"network": NETWORK})
        for lab in cfg.labs.values():
            for var in lab.images:
                with self.subTest(lab=lab.id, var=var):
                    self.assertIn(var, cfg.versions["images"])


if __name__ == "__main__":
    unittest.main()
