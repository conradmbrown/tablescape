"""Guard against malformed or incomplete locally supplied asset sets."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('asset_import', root/'scripts/import-game-assets.py')
assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)
spec = importlib.util.spec_from_file_location('asset_test_storage', root/'scripts/validate-storage.py')
storage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(storage)

class AssetImportTests(unittest.TestCase):
    def setUp(self):
        build = storage.validate()
        build.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=build)
        self.root = Path(self.temp.name)
        self.entry = {'path': 'LostCity274/models/0.ob2', 'bytes': 4, 'sha256': hashlib.sha256(b'test').hexdigest()}
    def tearDown(self):
        self.temp.cleanup()
    def test_rejects_unsafe_and_unexpected_paths(self):
        for path in ('../private', '/absolute', 'Scape/Client/overwrite.cs'):
            with self.subTest(path=path), self.assertRaises(ValueError):
                assets.checked_entries({'files': [{**self.entry, 'path': path}]})
    def test_rejects_duplicate_paths(self):
        with self.assertRaises(ValueError):
            assets.checked_entries({'files': [self.entry, self.entry]})
    def test_missing_and_corrupt_payload_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Missing asset'):
            assets.verify(self.root, [self.entry])
        path = self.root/self.entry['path']
        path.parent.mkdir(parents=True)
        path.write_bytes(b'bad!')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            assets.verify(self.root, [self.entry])
        path.write_bytes(b'test')
        assets.verify(self.root, [self.entry])
    def test_source_symlink_escape_rejected(self):
        source = self.root/'input'
        source.mkdir()
        path = source/self.entry['path']
        path.parent.mkdir(parents=True)
        outside = self.root/'outside'
        outside.write_bytes(b'test')
        path.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, 'symlink escapes'):
            assets.verify(source, [self.entry])

if __name__ == '__main__':
    unittest.main()
