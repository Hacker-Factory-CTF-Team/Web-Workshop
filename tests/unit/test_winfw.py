"""Windows Defender Firewall rules: spec generation and verification (no Windows needed)."""
from __future__ import annotations

import ipaddress
import json
import unittest
from unittest import mock

from pentestlab import isolation
from tests.helpers import TempConfigMixin

WIN_NETWORK = {"platform": "windows-virtualbox", "lab_host_ip": "192.168.57.1", "lab_prefix": 24,
               "lab_interface": "Ethernet 3"}


def as_windows_reports(spec: list[dict]) -> list[dict]:
    """Mimic Get-NetFirewall* output: masks instead of prefixes, scalars for single values."""
    out = []
    for r in spec:
        remote = [f"{n.network_address}/{n.netmask}" for n in map(ipaddress.ip_network, r["remote_address"])]
        out.append({
            "name": r["name"], "enabled": "True", "action": r["action"], "direction": r["direction"],
            "protocol": r["protocol"],
            "local_port": r["local_port"][0] if len(r["local_port"]) == 1 else r["local_port"],
            "icmp_type": r["icmp_type"], "local_address": r["local_address"][0],
            "remote_address": remote[0] if len(remote) == 1 else remote,
            "interface_alias": r["interface_alias"],
        })
    return out


class WindowsFirewallSpecTest(TempConfigMixin):
    def setUp(self):
        self.cfg = self.make_config({"network": WIN_NETWORK})
        self.spec = isolation.windows_firewall_spec(self.cfg)
        self.by_name = {r["name"]: r for r in self.spec}

    def test_rule_names_are_ascii_and_include_the_documented_ones(self):
        for r in self.spec:
            self.assertTrue(r["name"].isascii(), r["name"])
            self.assertEqual(r["group"], "PentestLab")
        self.assertIn(isolation.WIN_RULE_BLOCK_OUTSIDE, self.by_name)
        self.assertIn(isolation.WIN_RULE_ALLOW_KALI, self.by_name)

    def test_outside_block_covers_everything_but_the_lab_subnet(self):
        outside = [ipaddress.ip_network(n) for n in self.by_name[isolation.WIN_RULE_BLOCK_OUTSIDE]["remote_address"]]
        lab = ipaddress.ip_network("192.168.57.0/24")
        self.assertFalse(any(n.overlaps(lab) for n in outside))
        self.assertEqual(list(ipaddress.collapse_addresses(outside + [lab])), [ipaddress.ip_network("0.0.0.0/0")])

    def test_kali_allow_and_block_split_the_port_space(self):
        allow = self.by_name[isolation.WIN_RULE_ALLOW_KALI]
        block = self.by_name[isolation.WIN_RULE_BLOCK_KALI_TCP]
        self.assertEqual(allow["interface_alias"], "Ethernet 3")
        lab_ports = {int(p) for p in allow["local_port"]}
        self.assertEqual(lab_ports, {4280, 3000, 8080, 9090, 8081, 8443})
        blocked = set()
        for item in block["local_port"]:
            lo, _, hi = item.partition("-")
            blocked |= set(range(int(lo), int(hi or lo) + 1))
        self.assertFalse(blocked & lab_ports)
        self.assertEqual(blocked | lab_ports, set(range(1, 65536)))

    def test_complement_ports_edges(self):
        self.assertEqual(isolation._complement_ports([1, 65535]), ["2-65534"])
        self.assertEqual(isolation._complement_ports([2, 3, 5]), ["1", "4", "6-65535"])

    def test_spec_matches_windows_formatted_report(self):
        self.assertEqual(isolation.compare_windows_rules(self.spec, as_windows_reports(self.spec)), [])

    def test_stale_port_is_detected(self):
        reports = as_windows_reports(self.spec)
        cfg = self.make_config({"network": WIN_NETWORK, "labs": {"dvwa": {"ports": {"http": 4281}}}})
        problems = isolation.compare_windows_rules(isolation.windows_firewall_spec(cfg), reports)
        self.assertTrue(any(isolation.WIN_RULE_ALLOW_KALI in p for p in problems), problems)

    def test_missing_disabled_duplicate_and_extra_rules(self):
        reports = as_windows_reports(self.spec)
        self.assertTrue(isolation.compare_windows_rules(self.spec, reports[1:]))
        disabled = [dict(r) for r in reports]
        disabled[0]["enabled"] = "False"
        self.assertTrue(isolation.compare_windows_rules(self.spec, disabled))
        self.assertTrue(isolation.compare_windows_rules(self.spec, reports + [reports[0]]))
        extra = reports + [{"name": "PentestLab - abrir todo", "action": "Allow"}]
        self.assertTrue(any("no esperada" in p for p in isolation.compare_windows_rules(self.spec, extra)))

    def test_windows_firewall_check_parses_powershell_json(self):
        payload = json.dumps({"disabled": [], "rules": as_windows_reports(self.spec)})
        proc = mock.Mock(stdout=payload, returncode=0)
        with mock.patch.object(isolation.hostenv, "powershell", return_value=proc):
            checks = isolation.windows_firewall(self.cfg)
        self.assertTrue(all(c.ok for c in checks), [(c.name, c.detail) for c in checks])
        payload = json.dumps({"disabled": "Public", "rules": as_windows_reports(self.spec)[0]})
        with mock.patch.object(isolation.hostenv, "powershell", return_value=mock.Mock(stdout=payload)):
            checks = isolation.windows_firewall(self.cfg)
        self.assertFalse(any(c.ok for c in checks))


if __name__ == "__main__":
    unittest.main()
