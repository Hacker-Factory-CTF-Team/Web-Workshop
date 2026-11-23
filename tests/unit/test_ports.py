import socket
import time
import unittest
from unittest import mock

from pentestlab import ports
from pentestlab.errors import LabError
from tests.helpers import NETWORK, TempConfigMixin


def _listener(ip: str = "127.0.0.1", port: int = 0) -> socket.socket:
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)  # like docker-proxy (Go)
    s.bind((ip, port))
    s.listen()
    return s


class IsFreeTest(unittest.TestCase):
    def test_listener_makes_port_busy(self):
        with _listener() as srv:
            port = srv.getsockname()[1]
            self.assertFalse(ports.is_free("127.0.0.1", port))
            self.assertFalse(ports.free_everywhere(port, ["127.0.0.1"]))

    def test_wildcard_listener_makes_specific_ip_busy(self):
        with _listener("0.0.0.0") as srv:
            port = srv.getsockname()[1]
            self.assertFalse(ports.is_free("127.0.0.1", port))

    @unittest.skipIf(hasattr(socket, "SO_EXCLUSIVEADDRUSE"), "TIME_WAIT semantics differ on Windows")
    def test_time_wait_leftovers_do_not_block(self):
        """Regression: `restart` failed right after `stop` because of TIME_WAIT."""
        srv = _listener()
        port = srv.getsockname()[1]
        cli = socket.create_connection(("127.0.0.1", port))
        conn, _ = srv.accept()
        conn.close()          # server side closes first -> TIME_WAIT on `port`
        time.sleep(0.05)
        cli.close()
        srv.close()
        time.sleep(0.05)
        self.assertTrue(ports.is_free("127.0.0.1", port))


class ConflictTest(TempConfigMixin):
    def setUp(self):
        self.cfg = self.make_config({"network": NETWORK})
        self.lab = self.cfg.labs["dvwa"]
        self.saved_before = self.local_file.read_text()
        for obj, attr, fake in ((ports, "free_everywhere", lambda port, ips: port != 4280),
                                (ports.hostenv, "port_owner", lambda port: "python3 (pid 1)"),
                                (ports.ui, "warn", lambda msg: None), (ports.ui, "ok", lambda msg: None)):
            p = mock.patch.object(obj, attr, side_effect=fake)
            p.start()
            self.addCleanup(p.stop)

    def test_own_running_lab_is_not_a_conflict(self):
        ports.resolve_conflicts(self.cfg, self.lab, ["127.0.0.1"], own_running=True)
        self.assertEqual(self.lab.endpoints["http"].port, 4280)

    def test_suggestion_skips_ports_of_other_labs(self):
        self.cfg.set_port(self.lab, "http", 4280)
        with mock.patch.object(ports, "free_everywhere", return_value=True):
            self.cfg.set_port(self.cfg.labs["juice-shop"], "http", 4281)
            self.assertEqual(ports.suggest(self.cfg, 4280, ["127.0.0.1"], ("dvwa", "http")), 4282)

    def test_busy_port_non_interactive_is_refused(self):
        with mock.patch.object(ports.ui, "interactive", return_value=False), self.assertRaises(LabError) as ctx:
            ports.resolve_conflicts(self.cfg, self.lab, ["127.0.0.1"], own_running=False)
        self.assertIn("4281", ctx.exception.hint)  # tells the user the exact command
        self.assertEqual(self.lab.endpoints["http"].port, 4280)
        self.assertEqual(self.local_file.read_text(), self.saved_before)

    def test_busy_port_declined_interactively(self):
        with mock.patch.object(ports.ui, "interactive", return_value=True), \
             mock.patch.object(ports.ui, "confirm", return_value=False), self.assertRaises(LabError):
            ports.resolve_conflicts(self.cfg, self.lab, ["127.0.0.1"], own_running=False)
        self.assertEqual(self.local_file.read_text(), self.saved_before)

    def test_explicit_acceptance_saves_new_port(self):
        ports.resolve_conflicts(self.cfg, self.lab, ["127.0.0.1"], own_running=False, accept_suggestions=True)
        self.assertEqual(self.lab.endpoints["http"].port, 4281)
        self.assertIn('"http": 4281', self.local_file.read_text())


if __name__ == "__main__":
    unittest.main()
