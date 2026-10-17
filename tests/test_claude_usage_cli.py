from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import claude_usage_cli as cli
from claude_usage_cli import prepare_probe, UsageUnavailable


class ProbeDirectoryTests(unittest.TestCase):
    def test_missing_probe_directory_recovers_after_cleanup(self):
        with tempfile.TemporaryDirectory() as folder:
            probe = Path(folder) / 'state/usage-cli'
            prepare_probe(probe)
            self.assertTrue(probe.is_dir())
            self.assertEqual(probe.stat().st_mode & 0o777, 0o700)
            probe.rmdir()
            prepare_probe(probe)
            self.assertTrue(probe.is_dir())

    def test_probe_rejects_symlinks_and_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target = root / 'target'
            target.mkdir()
            probe = root / 'probe'
            probe.symlink_to(target)
            with self.assertRaisesRegex(UsageUnavailable, 'probe_directory_unavailable'):
                prepare_probe(probe)
            self.assertEqual(list(target.iterdir()), [])
            probe.unlink()
            probe.write_text('do not overwrite')
            with self.assertRaisesRegex(UsageUnavailable, 'probe_directory_unavailable'):
                prepare_probe(probe)
            self.assertEqual(probe.read_text(), 'do not overwrite')


class AuthStatusTests(unittest.TestCase):
    def test_official_boolean_only_is_used_with_the_probe_environment(self):
        result = Mock(returncode=0, stdout='{"loggedIn":true,"email":"private@example.test"}')
        with patch.object(cli, 'prepare_probe'), \
                patch.dict(cli.os.environ, {'CLAUDECODE': 'nested'}), \
                patch.object(cli.subprocess, 'run', return_value=result) as run:
            self.assertTrue(cli.auth_ready())
            self.assertEqual(run.call_args.args[0], [cli.BINARY, 'auth', 'status', '--json'])
            self.assertNotIn('CLAUDECODE', run.call_args.kwargs['env'])
            self.assertEqual(run.call_args.kwargs['timeout'], 5)
            self.assertEqual(run.call_args.kwargs['cwd'], cli.PROBE)

    def test_unavailable_auth_status_never_claims_recovery(self):
        for result in (Mock(returncode=1, stdout='{"loggedIn":true}'),
                       Mock(returncode=0, stdout='{"loggedIn":false}'),
                       Mock(returncode=0, stdout='{"loggedIn":"true"}'),
                       Mock(returncode=0, stdout='invalid')):
            with self.subTest(result=result.stdout), patch.object(cli, 'prepare_probe'), \
                    patch.object(cli.subprocess, 'run', return_value=result):
                self.assertFalse(cli.auth_ready())
        with patch.object(cli, 'prepare_probe'), \
                patch.object(cli.subprocess, 'run', side_effect=cli.subprocess.TimeoutExpired('claude', 5)):
            self.assertFalse(cli.auth_ready())


if __name__ == '__main__':
    unittest.main()
