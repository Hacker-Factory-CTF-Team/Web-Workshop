"""Shared test helpers: a Config whose local overrides live in a temp dir."""
from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from pentestlab import config as config_mod


REPO_CONFIG_DIR = config_mod.CONFIG_DIR


class TempConfigMixin(unittest.TestCase):
    """Never reads or writes the developer's config/local.json."""

    def make_config(self, local: dict | None = None) -> config_mod.Config:
        tmp = Path(tempfile.mkdtemp(prefix="plab-test-"))
        self.addCleanup(shutil.rmtree, tmp, True)
        local_file = tmp / "local.json"
        if local is not None:
            local_file.write_text(json.dumps(local), encoding="utf-8")
        p = mock.patch.object(config_mod, "LOCAL_FILE", local_file)
        p.start()
        self.addCleanup(p.stop)
        with mock.patch.object(config_mod, "CONFIG_DIR", REPO_CONFIG_DIR):
            cfg = config_mod.Config()
        # save() writes next to LOCAL_FILE; keep defaults/versions from the repo.
        p = mock.patch.object(config_mod, "CONFIG_DIR", tmp)
        p.start()
        self.addCleanup(p.stop)
        self.local_file = local_file
        return cfg

    def make_config_from_existing(self) -> config_mod.Config:
        """A fresh Config reading the current temp local.json (after save())."""
        with mock.patch.object(config_mod, "CONFIG_DIR", REPO_CONFIG_DIR):
            return config_mod.Config()


NETWORK = {"platform": "linux-virtualbox", "lab_host_ip": "192.168.57.1", "lab_prefix": 24,
           "lab_interface": "vboxnet1"}
