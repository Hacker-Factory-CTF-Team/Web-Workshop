import unittest
from unittest import mock

from pentestlab import isolation
from tests.helpers import NETWORK, TempConfigMixin


def container(nets, dns=None):
    return {"NetworkSettings": {"Networks": {n: {} for n in nets}}, "HostConfig": {"Dns": dns}}


class ProbeDnsTest(TempConfigMixin):
    """The probe must reproduce the DNS the lab containers really use
    (Docker's embedded DNS forwards external queries from the host netns)."""

    def setUp(self):
        self.lab = self.make_config({"network": NETWORK}).labs["dvwa"]

    def dns_for(self, containers, network):
        with mock.patch.object(isolation.docker, "project_containers", return_value=containers):
            return isolation._network_dns(self.lab, network)

    def test_edge_with_loopback_dns(self):
        cs = [container(["plab-dvwa_edge", "plab-dvwa_front"], ["127.0.0.1"]), container(["plab-dvwa_front"])]
        self.assertEqual(self.dns_for(cs, "plab-dvwa_edge"), ["127.0.0.1"])

    def test_worst_case_when_containers_differ(self):
        cs = [container(["plab-dvwa_front"], ["127.0.0.1"]), container(["plab-dvwa_front"])]
        self.assertEqual(self.dns_for(cs, "plab-dvwa_front"), [])

    def test_default_dns_when_unset(self):
        self.assertEqual(self.dns_for([container(["plab-dvwa_data"])], "plab-dvwa_data"), [])

    def test_probe_passes_dns_to_docker_run(self):
        cfg = self.make_config({"network": NETWORK})
        fake = mock.Mock(returncode=0, stdout="dns example.com closed\negress 1.1.1.1:443 closed\n", stderr="")
        with mock.patch.object(isolation.docker, "docker", return_value=fake) as run:
            res = isolation._probe(cfg, "plab-dvwa_edge", [], [], ["127.0.0.1"])
        args = run.call_args.args
        self.assertIn("--dns", args)
        self.assertEqual(args[args.index("--dns") + 1], "127.0.0.1")
        self.assertIn("--cap-drop", args)
        self.assertEqual(res["dns"], {"example.com": False})
        self.assertEqual(res["egress"], {"1.1.1.1:443": False})


if __name__ == "__main__":
    unittest.main()
