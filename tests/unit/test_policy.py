"""Static Compose policy: one valid model, then each violation injected alone."""
import copy
import unittest

from pentestlab import policy

IMG = "nginx:1.30.7-alpine@sha256:" + "a" * 64
ALLOWED = {"127.0.0.1", "192.168.57.1"}


def valid_model() -> dict:
    hardened = {"security_opt": ["no-new-privileges:true"], "restart": "no", "mem_limit": "536870912"}
    return {
        "networks": {
            "edge": {"driver": "bridge", "driver_opts": {"com.docker.network.bridge.name": "plabe-test"}},
            "front": {"driver": "bridge", "internal": True,
                      "driver_opts": {"com.docker.network.bridge.name": "plabi-test-f"}},
        },
        "services": {
            "edge": {**copy.deepcopy(hardened), "image": IMG, "read_only": True, "cap_drop": ["ALL"],
                     "dns": ["127.0.0.1"], "networks": {"edge": None, "front": None},
                     "ports": [{"host_ip": "127.0.0.1", "published": "4280", "target": 4280, "protocol": "tcp"},
                               {"host_ip": "192.168.57.1", "published": "4280", "target": 4280, "protocol": "tcp"}]},
            "app": {**copy.deepcopy(hardened), "image": IMG, "networks": {"front": None}},
        },
    }


class PolicyTest(unittest.TestCase):
    def assertViolation(self, model: dict, fragment: str):
        v = policy.check(model, ALLOWED)
        self.assertTrue(any(fragment in x for x in v), f"'{fragment}' no detectado; violaciones: {v}")

    def test_valid_model_passes(self):
        self.assertEqual(policy.check(valid_model(), ALLOWED), [])

    def test_port_without_ip_publishes_everywhere(self):
        m = valid_model()
        del m["services"]["edge"]["ports"][0]["host_ip"]
        self.assertViolation(m, "0.0.0.0")

    def test_port_on_lan_ip(self):
        m = valid_model()
        m["services"]["edge"]["ports"][1]["host_ip"] = "192.168.1.33"
        self.assertViolation(m, "192.168.1.33")

    def test_udp_port(self):
        m = valid_model()
        m["services"]["edge"]["ports"][0]["protocol"] = "udp"
        self.assertViolation(m, "TCP")

    def test_only_edge_publishes(self):
        m = valid_model()
        m["services"]["app"]["ports"] = [{"host_ip": "127.0.0.1", "published": "3306", "target": 3306}]
        self.assertViolation(m, "solo el proxy 'edge' puede publicar")

    def test_only_edge_on_edge_network(self):
        m = valid_model()
        m["services"]["app"]["networks"]["edge"] = None
        self.assertViolation(m, "solo el proxy 'edge' puede estar")

    def test_non_internal_network(self):
        m = valid_model()
        m["networks"]["front"]["internal"] = False
        self.assertViolation(m, "internal: true")

    def test_bridge_names(self):
        m = valid_model()
        m["networks"]["front"]["driver_opts"]["com.docker.network.bridge.name"] = "br-random"
        self.assertViolation(m, "plabi-")
        m = valid_model()
        del m["networks"]["edge"]["driver_opts"]
        self.assertViolation(m, "plabe-")

    def test_external_and_ipv6_and_driver(self):
        for key, value, fragment in (("external", True, "externas"), ("enable_ipv6", True, "IPv6"),
                                     ("driver", "macvlan", "driver bridge")):
            m = valid_model()
            m["networks"]["front"][key] = value
            with self.subTest(key=key):
                self.assertViolation(m, fragment)

    def test_image_pinning(self):
        for image, fragment in (("nginx:1.30.7-alpine", "digest"), ("nginx:latest@sha256:" + "a" * 64, "latest"),
                                ("nginx@sha256:" + "a" * 64, "latest")):
            m = valid_model()
            m["services"]["app"]["image"] = image
            with self.subTest(image=image):
                self.assertViolation(m, fragment)

    def test_privileged_host_namespaces_devices(self):
        cases = (("privileged", True, "privileged"), ("network_mode", "host", "network_mode"),
                 ("pid", "host", "pid: host"), ("ipc", "host", "ipc: host"), ("devices", ["/dev/kvm"], "dispositivos"))
        for key, value, fragment in cases:
            m = valid_model()
            m["services"]["app"][key] = value
            with self.subTest(key=key):
                self.assertViolation(m, fragment)

    def test_capabilities(self):
        m = valid_model()
        m["services"]["app"]["cap_add"] = ["NET_ADMIN"]
        self.assertViolation(m, "cap_add")
        # CHOWN is only allowed for the one-shot, network-less volume init helper.
        m = valid_model()
        m["services"]["app"]["cap_add"] = ["CHOWN"]
        self.assertViolation(m, "cap_add")
        m["services"]["app"]["network_mode"] = "none"
        m["services"]["app"].pop("networks")
        self.assertEqual(policy.check(m, ALLOWED), [])

    def test_security_options(self):
        m = valid_model()
        m["services"]["app"]["security_opt"] = []
        self.assertViolation(m, "no-new-privileges")
        m = valid_model()
        m["services"]["app"]["security_opt"].append("seccomp:unconfined")
        self.assertViolation(m, "unconfined")

    def test_restart_policy(self):
        m = valid_model()
        m["services"]["app"]["restart"] = "unless-stopped"
        self.assertViolation(m, "restart")

    def test_memory_limit(self):
        m = valid_model()
        del m["services"]["app"]["mem_limit"]
        self.assertViolation(m, "memoria")

    def test_docker_socket_and_writable_bind(self):
        m = valid_model()
        m["services"]["app"]["volumes"] = [{"type": "bind", "source": "/var/run/docker.sock",
                                            "target": "/var/run/docker.sock", "read_only": True}]
        self.assertViolation(m, "socket")
        m = valid_model()
        m["services"]["app"]["volumes"] = [{"type": "bind", "source": "/home/user", "target": "/x"}]
        self.assertViolation(m, "solo lectura")

    def test_extra_hosts(self):
        m = valid_model()
        m["services"]["app"]["extra_hosts"] = ["host.docker.internal:host-gateway"]
        self.assertViolation(m, "extra_hosts")

    def test_edge_hardening(self):
        for key, value, fragment in (("read_only", False, "read_only"), ("cap_drop", [], "cap_drop"),
                                     ("dns", None, "dns"), ("dns", ["1.1.1.1"], "dns")):
            m = valid_model()
            m["services"]["edge"][key] = value
            with self.subTest(key=key, value=value):
                self.assertViolation(m, fragment)
        m = valid_model()
        m["services"]["edge"]["networks"] = {"front": None}
        self.assertViolation(m, "el proxy debe estar en la red")


if __name__ == "__main__":
    unittest.main()
