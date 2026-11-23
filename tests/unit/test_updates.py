import unittest
from unittest import mock

from pentestlab import updates
from tests.helpers import NETWORK, TempConfigMixin


class NaturalSortTest(unittest.TestCase):
    def test_versions_sort_numerically(self):
        tags = ["v2026.5", "v2026.10", "v2026.9"]
        self.assertEqual(sorted(tags, key=updates._natural), ["v2026.5", "v2026.9", "v2026.10"])
        self.assertGreater(updates._natural("1.38.0"), updates._natural("1.37.0"))


class CheckTest(TempConfigMixin):
    """`update --check` must only read registries; mocked, so no network."""

    def setUp(self):
        self.cfg = self.make_config({"network": NETWORK})
        self.images = self.cfg.versions["images"]

    def _status(self, rows, var):
        return next(r[2] for r in rows if r[0] == var)

    def test_reports_newer_matching_tag_only(self):
        current = self.images["HELPER_IMAGE"]["tag"]
        fake = [{"name": current}, {"name": "1.99.0"}, {"name": "latest"}, {"name": "1.99.0-musl"}]
        with mock.patch.object(updates, "dockerhub_tags", return_value=fake), \
             mock.patch.object(updates, "ghcr_latest_digest", return_value=self.images["DVWA_IMAGE"]["digest"]):
            rows = updates.check(self.cfg, [])
        self.assertEqual(self._status(rows, "HELPER_IMAGE"), "disponible 1.99.0")
        self.assertEqual(self._status(rows, "DVWA_IMAGE"), "al día")

    def test_up_to_date_and_changed_ghcr(self):
        with mock.patch.object(updates, "dockerhub_tags", return_value=[]), \
             mock.patch.object(updates, "ghcr_latest_digest", return_value="sha256:" + "b" * 64):
            rows = updates.check(self.cfg, ["dvwa"])
        self.assertTrue(all(r[2] == "al día" for r in rows if r[0] != "DVWA_IMAGE"))
        self.assertIn("ha cambiado", self._status(rows, "DVWA_IMAGE"))
        self.assertNotIn("JUICE_SHOP_IMAGE", [r[0] for r in rows])  # filtered by lab

    def test_network_errors_are_reported_not_raised(self):
        with mock.patch.object(updates, "dockerhub_tags", side_effect=OSError("offline")), \
             mock.patch.object(updates, "ghcr_latest_digest", side_effect=OSError("offline")):
            rows = updates.check(self.cfg, [])
        self.assertTrue(rows)
        self.assertTrue(all(r[2].startswith("no se pudo consultar") for r in rows))

    def test_check_never_touches_versions_file(self):
        before = (self.repo_versions()).read_bytes()
        with mock.patch.object(updates, "dockerhub_tags", return_value=[{"name": "999.0.0"}]), \
             mock.patch.object(updates, "ghcr_latest_digest", return_value=None):
            updates.check(self.cfg, [])
        self.assertEqual(self.repo_versions().read_bytes(), before)

    @staticmethod
    def repo_versions():
        from tests.helpers import REPO_CONFIG_DIR
        return REPO_CONFIG_DIR / "versions.json"


if __name__ == "__main__":
    unittest.main()
