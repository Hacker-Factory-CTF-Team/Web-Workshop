import ipaddress
import unittest
from unittest import mock

from pentestlab import hostenv
from pentestlab.hostenv import Interface


class LabIpTest(unittest.TestCase):
    def test_accepts_private_addresses(self):
        for ip in ("192.168.57.1", "192.168.157.1", "10.10.10.1", "172.16.5.1"):
            self.assertIsNone(hostenv.validate_lab_ip(ip), ip)

    def test_rejects_dangerous_addresses(self):
        for ip, fragment in (("0.0.0.0", "0.0.0.0"), ("127.0.0.1", "loopback"), ("8.8.8.8", "privada"),
                             ("169.254.1.1", "privada"), ("not-an-ip", "IPv4"), ("192.168.57.300", "IPv4")):
            with self.subTest(ip=ip):
                self.assertIn(fragment, hostenv.validate_lab_ip(ip) or "")


class SubnetConflictTest(unittest.TestCase):
    def _ifaces(self):
        mk = lambda name, *cidrs: Interface(name, [ipaddress.IPv4Interface(c) for c in cidrs], True)
        return [mk("lo", "127.0.0.1/8"), mk("enp5s0", "192.168.1.33/24"),
                mk("vboxnet1", "192.168.57.1/24"), mk("docker0", "192.168.0.1/16")]

    def test_overlaps_are_reported_except_own_interface(self):
        with mock.patch.object(hostenv, "list_interfaces", return_value=self._ifaces()):
            conflicts = hostenv.subnet_conflicts("192.168.57.1", 24, "vboxnet1")
        self.assertEqual(conflicts, ["docker0 (192.168.0.1/16)"])

    def test_no_conflicts(self):
        with mock.patch.object(hostenv, "list_interfaces", return_value=self._ifaces()[:3]):
            self.assertEqual(hostenv.subnet_conflicts("192.168.57.1", 24, "vboxnet1"), [])


if __name__ == "__main__":
    unittest.main()
