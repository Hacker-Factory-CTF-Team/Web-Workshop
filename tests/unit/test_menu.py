import unittest
from unittest import mock

from pentestlab import menu
from pentestlab.errors import LabError
from tests.helpers import NETWORK, TempConfigMixin


class SetPortsInteractiveTest(TempConfigMixin):
    def setUp(self):
        self.cfg = self.make_config({"network": NETWORK})
        self.saved_before = self.local_file.read_text()

    def run_with_answers(self, lab_id, answers):
        it = iter(answers)
        with mock.patch.object(menu.ui, "ask", side_effect=lambda prompt, default=None: next(it)):
            menu.set_ports_interactive(self.cfg, self.cfg.labs[lab_id])

    def ports(self, lab_id):
        return {e.key: e.port for e in self.cfg.labs[lab_id].endpoints.values()}

    def test_valid_change_is_saved(self):
        self.run_with_answers("dvwa", ["4290"])
        self.assertEqual(self.ports("dvwa"), {"http": 4290})
        self.assertIn('"http": 4290', self.local_file.read_text())

    def test_duplicate_port_is_rolled_back(self):
        """Regression: a rejected port stayed active for the rest of the menu session."""
        with self.assertRaises(LabError):
            self.run_with_answers("dvwa", ["3000"])
        self.assertEqual(self.ports("dvwa"), {"http": 4280})
        self.assertEqual(self.cfg.validate(), [])
        self.assertEqual(self.local_file.read_text(), self.saved_before)

    def test_error_on_second_endpoint_rolls_back_the_first(self):
        with self.assertRaises(LabError):
            self.run_with_answers("mutillidae", ["8082", "80"])
        self.assertEqual(self.ports("mutillidae"), {"http": 8081, "https": 8443})
        self.assertEqual(self.local_file.read_text(), self.saved_before)


if __name__ == "__main__":
    unittest.main()
