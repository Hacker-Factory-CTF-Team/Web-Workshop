import unittest
from unittest import mock

from pentestlab import lifecycle, ui
from pentestlab.errors import EXIT_ABORTED, Aborted, LabError
from tests.helpers import NETWORK, TempConfigMixin


def container(service, status, health=None):
    state = {"Status": status}
    if health:
        state["Health"] = {"Status": health}
    return {"Config": {"Labels": {"com.docker.compose.service": service}}, "State": state}


class ManagerTest(TempConfigMixin):
    def setUp(self):
        self.mgr = lifecycle.Manager(self.make_config({"network": NETWORK}))
        self.lab = self.mgr.cfg.labs["dvwa"]
        # Nothing in these tests may reach Docker.
        p = mock.patch.object(lifecycle.Manager, "compose", side_effect=AssertionError("compose llamado"))
        self.compose = p.start()
        self.addCleanup(p.stop)
        # Nor write state/<lab>.env in the repository.
        p = mock.patch.object(lifecycle.Manager, "_ensure_env")
        p.start()
        self.addCleanup(p.stop)

    def test_logs_unknown_service(self):
        """Regression: an unknown service exited 0 silently."""
        with self.assertRaises(LabError) as ctx:
            self.mgr.logs(self.lab, follow=False, tail=10, service="nope")
        self.assertIn("edge, dvwa, db", ctx.exception.hint)

    def test_status_shows_container_state_when_stopped(self):
        """Regression: stopped containers showed their stale health 'unhealthy'."""
        cs = [container("edge", "exited", "unhealthy"), container("db", "running", "healthy"),
              container("dvwa", "running")]
        rows = []
        with mock.patch.object(self.mgr, "state", return_value=("parcial", cs)), \
             mock.patch.object(self.mgr, "is_running", return_value=False), \
             mock.patch.object(ui, "table", side_effect=lambda headers, r: rows.extend(r)), \
             mock.patch.object(ui, "warn"):
            self.mgr.status([self.lab])
        self.assertEqual(rows[0][3], "edge:exited db:healthy dvwa:running")

    def test_destructive_operations_need_confirmation(self):
        for op in (self.mgr.reset_data, self.mgr.reset):
            with self.subTest(op=op.__name__), \
                 mock.patch.object(ui, "ASSUME_YES", False), mock.patch.object(ui, "interactive", return_value=False):
                with self.assertRaises(Aborted) as ctx:
                    op([self.lab])
                self.assertEqual(ctx.exception.exit_code, EXIT_ABORTED)
        self.compose.assert_not_called()

    def test_wrong_confirmation_text_cancels(self):
        with mock.patch.object(ui, "ASSUME_YES", False), mock.patch.object(ui, "interactive", return_value=True), \
             mock.patch.object(ui, "ask", return_value="juice-shop"), mock.patch.object(ui, "warn"), \
             self.assertRaises(Aborted):
            self.mgr.reset_data([self.lab])
        self.compose.assert_not_called()

    def test_reset_data_only_touches_its_own_project(self):
        calls = []
        self.compose.side_effect = lambda lab, *args, **kw: calls.append((lab.project, args)) or mock.Mock(returncode=0)
        with mock.patch.object(ui, "ASSUME_YES", True), mock.patch.object(self.mgr, "start"), \
             mock.patch.object(ui, "step"):
            self.mgr.reset_data([self.lab])
        self.assertEqual(calls, [("plab-dvwa", ("down", "--volumes", "--remove-orphans"))])

    def test_allowed_publish_ips(self):
        self.assertEqual(self.mgr.allowed_ips(), {"127.0.0.1", "192.168.57.1"})


if __name__ == "__main__":
    unittest.main()
