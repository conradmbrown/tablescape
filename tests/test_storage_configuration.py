#!/usr/bin/env python3
"""Storage guard regression; its own temporary files stay on configured storage."""
import importlib.util
import os
import pathlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('storage', pathlib.Path(__file__).resolve().parents[1] / 'scripts/validate-storage.py')
storage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(storage)
BUILD = storage.validate()
BUILD.mkdir(parents=True, exist_ok=True)

class StorageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='storage-check-', dir=BUILD)
        self.addCleanup(self.temp.cleanup)
        self.disk = pathlib.Path(self.temp.name)
        self.env = {'SCAPE_STORAGE_ROOT': str(self.disk), 'SCAPE_WORKSPACE': str(self.disk/'work'), 'SCAPE_BUILD_ROOT': str(self.disk/'build'), 'SCAPE_SOURCE_ROOT': str(self.disk/'source')}
        self.mount = patch.object(pathlib.Path, 'is_mount', lambda p: p == self.disk)
        self.mount.start(); self.addCleanup(self.mount.stop)
        self.vars = patch.dict(os.environ, self.env, clear=True)
        self.vars.start(); self.addCleanup(self.vars.stop)

    def test_valid_config(self):
        self.assertEqual(storage.validate(), self.disk/'build')
    def test_missing_setting(self):
        del os.environ['SCAPE_STORAGE_ROOT']
        with self.assertRaises(ValueError): storage.validate()
    def test_unmounted(self):
        os.environ['SCAPE_STORAGE_ROOT'] = str(self.disk/'absent')
        with self.assertRaises(ValueError): storage.validate()
    def test_system_root(self):
        os.environ['SCAPE_STORAGE_ROOT'] = '/'
        with self.assertRaises(ValueError): storage.validate()
    def test_relative_paths(self):
        for key in self.env:
            with self.subTest(key=key), patch.dict(os.environ, {key:'relative'}):
                with self.assertRaises(ValueError): storage.validate()
    def test_escape_configured_paths(self):
        for key in ('SCAPE_WORKSPACE','SCAPE_BUILD_ROOT','SCAPE_SOURCE_ROOT'):
            with self.subTest(key=key), patch.dict(os.environ, {key:str(self.disk.parent/'outside')}):
                with self.assertRaises(ValueError): storage.validate()
    def test_symlink_output_escape(self):
        link = self.disk/'redirect'; link.symlink_to(self.disk.parent, target_is_directory=True)
        with self.assertRaises(ValueError): storage.validate([str(link/'output')])
    def test_contained_extra_output(self):
        storage.validate([str(self.disk/'build'/'Suite'/'Artifacts')])
    def test_sibling_prefix_rejected(self):
        with self.assertRaises(ValueError): storage.validate([str(self.disk)+'-other/file'])

if __name__ == '__main__': unittest.main()
