#!/usr/bin/env python3
"""Offline release-reporting tests. No app launch, publication, or service writes."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import linear_release as lr
import report_linear_release as reporter


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.asset = self.root / 'release.dmg'
        self.asset.write_bytes(b'actual app artifact')
        self.feed = self.root / 'appcast.xml'
        self.feed.write_text(f'''<rss xmlns:sparkle="{lr.SPARKLE[1:-1]}"><channel><item>
          <sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>
          <enclosure url="https://example.invalid/release.dmg" length="19" sparkle:edSignature="signed" />
        </item></channel></rss>''')

    def test_wrong_bytes_block_even_with_same_file_size(self):
        with patch.object(lr, 'download', side_effect=lambda url, dest, **kw: Path(dest).write_bytes(b'wrong app artifact!')):
            with self.assertRaisesRegex(ValueError, 'Served bytes'):
                lr.verify_download('https://example.invalid/dmg', self.asset)

    def test_received_feed_and_enclosure_both_must_match(self):
        with patch.object(lr, 'download', side_effect=lambda url, dest, **kw: Path(dest).write_bytes(self.feed.read_bytes())):
            lr.verify_feed('https://example.invalid/feed', self.feed, '1.2.3', 'https://example.invalid/release.dmg', self.asset)
            for version, url in [('1.2.4', 'https://example.invalid/release.dmg'), ('1.2.3', 'https://example.invalid/wrong.dmg')]:
                with self.assertRaisesRegex(ValueError, 'exactly one enclosure'):
                    lr.verify_feed('https://example.invalid/feed', self.feed, version, url, self.asset)

    def test_missing_signature_or_wrong_length_blocks(self):
        original = self.feed.read_text()
        for broken in [original.replace('sparkle:edSignature="signed"', ''), original.replace('length="19"', 'length="18"')]:
            self.feed.write_text(broken)
            with patch.object(lr, 'verify_download'):
                with self.assertRaisesRegex(ValueError, 'signature or enclosure length'):
                    lr.verify_feed('feed', self.feed, '1.2.3', 'https://example.invalid/release.dmg', self.asset)

    def test_source_only_draft_and_wrong_channel_are_rejected(self):
        baseline = {'draft': False, 'prerelease': False, 'published_at': '2026-10-07', 'assets': [{'name': 'release.dmg'}]}
        for change in [{'assets': []}, {'draft': True}, {'published_at': None}, {'prerelease': True}]:
            with patch.object(lr, 'run', return_value=json.dumps(dict(baseline, **change))):
                with self.assertRaises(ValueError):
                    lr.github_release('fixture', '1.2.3', ['release.dmg'])

    def test_retry_checks_only_until_received_bytes_match(self):
        with patch.object(lr.time, 'sleep') as sleep:
            action = unittest.mock.Mock(side_effect=[ValueError('stale feed'), 'verified'])
            self.assertEqual(lr.retry(action, attempts=3, delay=0), 'verified')
            self.assertEqual(action.call_count, 2)
            sleep.assert_called_once_with(0)

    def test_failed_delivery_never_reaches_linear(self):
        with patch.object(lr, 'source_commit', return_value='a' * 40), patch.object(reporter, 'verify_delivery', side_effect=ValueError('not delivered')), patch.object(lr, 'report') as report:
            with self.assertRaises(ValueError):
                reporter.main(['--version', '1.2.3', '--artifacts', str(self.root), '--attempts', '1'])
            report.assert_not_called()


class ClientTests(unittest.TestCase):
    def test_dry_run_needs_no_cli_or_credential(self):
        with patch.object(lr, 'install_cli') as installer, patch.object(lr, 'run') as command:
            lr.report(Path('.'), 'fixture', 'Fixture', '1.2.3', 'a' * 40, 'https://example.invalid', dry_run=True)
            installer.assert_not_called()
            command.assert_not_called()

    def test_failed_subprocess_does_not_expose_key(self):
        result = subprocess.CompletedProcess([], 1, stdout='secret-value', stderr='secret-value')
        with patch.object(lr.subprocess, 'run', return_value=result):
            with self.assertRaises(RuntimeError) as error:
                lr.run(['linear-release', 'sync'], env={'LINEAR_ACCESS_KEY': 'secret-value'})
            self.assertNotIn('secret-value', str(error.exception))

    def test_cached_cli_with_wrong_checksum_never_executes(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(lr.Path, 'home', return_value=Path(directory)), patch.object(lr.platform, 'system', return_value='Darwin'), patch.object(lr.platform, 'machine', return_value='arm64'):
            target = Path(directory) / 'Library/Caches/ames-release/linear-release/v0.18.0/linear-release-darwin-arm64'
            target.parent.mkdir(parents=True)
            target.write_bytes(b'wrong binary')
            with self.assertRaisesRegex(ValueError, 'checksum mismatch'), patch.object(lr, 'download') as download:
                lr.install_cli()
            download.assert_not_called()

    def test_download_checksum_failure_is_not_installed(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(lr.Path, 'home', return_value=Path(directory)), patch.object(lr.platform, 'system', return_value='Darwin'), patch.object(lr.platform, 'machine', return_value='arm64'), patch.object(lr, 'download', side_effect=lambda url, dest: Path(dest).write_bytes(b'wrong binary')):
            with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                lr.install_cli()
            self.assertFalse(list(Path(directory).rglob('linear-release-darwin-arm64')))

    def exercise_report(self, *, wrong_sync=False, empty_first=False, wrong_complete=False, env_key=True, check_access=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'repo'
            root.mkdir()
            original_run = lr.run
            original_run(['git', 'init', '--quiet'], cwd=root)
            original_run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '--allow-empty', '-m', 'AME-123 delivered'], cwd=root)
            delivered = original_run(['git', 'rev-parse', 'HEAD'], cwd=root)
            original_run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '--allow-empty', '-m', 'Later unrelated work'], cwd=root)
            current = original_run(['git', 'rev-parse', 'HEAD'], cwd=root)
            calls = []
            op_calls = []
            def command(args, *, cwd=None, env=None):
                if str(args[0]) == 'op':
                    op_calls.append(args)
                    return 'secret-fixture'
                if str(args[0]) != '/fake/linear-release':
                    return original_run(args, cwd=cwd, env=env)
                self.assertEqual(original_run(['git', 'rev-parse', 'HEAD'], cwd=cwd), delivered)
                self.assertEqual(original_run(['git', 'remote', 'get-url', 'origin'], cwd=cwd), 'https://github.com/oliverames/fixture.git')
                self.assertEqual(env['LINEAR_ACCESS_KEY'], 'secret-fixture')
                self.assertNotIn('secret-fixture', str(args))
                self.assertNotIn('LINEAR_API_URL', env)
                calls.append(args)
                if empty_first and len(calls) == 1:
                    return '{"release":null}'
                version = 'wrong' if (wrong_sync and args[1] == 'sync') or (wrong_complete and args[1] == 'complete') else '1.2.3'
                return json.dumps({'release': {'id': 'one-release', 'version': version}})
            env = {'LINEAR_API_URL': 'https://wrong.invalid'}
            if env_key:
                env['LINEAR_ACCESS_KEY'] = 'secret-fixture'
            with patch.dict(os.environ, env, clear=True), patch.object(lr, 'install_cli', return_value=Path('/fake/linear-release')), patch.object(lr, 'run', side_effect=command):
                if wrong_sync or wrong_complete:
                    with self.assertRaises(ValueError):
                        lr.report(root, 'fixture', 'Fixture', '1.2.3', delivered, 'https://example.invalid', dry_run=check_access, check_access=check_access)
                else:
                    lr.report(root, 'fixture', 'Fixture', '1.2.3', delivered, 'https://example.invalid', dry_run=check_access, check_access=check_access)
            self.assertEqual(original_run(['git', 'rev-parse', 'HEAD'], cwd=root), current)
            self.assertEqual(original_run(['git', 'status', '--porcelain'], cwd=root), '')
            if not env_key:
                self.assertEqual(op_calls, [['op', 'read', 'op://Development/Linear Release - fixture/credential']])
            else:
                self.assertFalse(op_calls)
            return calls, delivered

    def test_reports_delivered_commit_without_switching_source_checkout(self):
        calls, _ = self.exercise_report()
        self.assertEqual([c[1] for c in calls], ['sync', 'complete'])
        self.assertIn('--no-branch-ref-detection', calls[0])
        self.assertTrue(all('--release-version=1.2.3' in c for c in calls))

    def test_empty_sync_uses_explicit_empty_baseline_before_completion(self):
        calls, sha = self.exercise_report(empty_first=True)
        self.assertEqual([c[1] for c in calls], ['sync', 'sync', 'complete'])
        self.assertIn('--base-ref=' + sha, calls[1])

    def test_wrong_sync_release_never_completes(self):
        calls, _ = self.exercise_report(wrong_sync=True)
        self.assertEqual([c[1] for c in calls], ['sync'])

    def test_wrong_completion_is_not_claimed_success(self):
        self.exercise_report(wrong_complete=True)

    def test_live_access_dry_run_never_calls_complete(self):
        calls, _ = self.exercise_report(check_access=True)
        self.assertEqual([c[1] for c in calls], ['sync'])
        self.assertIn('--dry-run', calls[0])

    def test_explicit_source_cannot_override_a_different_published_tag(self):
        with patch.object(lr, 'run', return_value='b' * 40):
            with self.assertRaisesRegex(ValueError, 'does not match'):
                lr.source_commit(Path('.'), 'fixture', '1.2.3', 'a' * 40)

    def test_shallow_history_blocks_before_credentials(self):
        with patch.object(lr, 'run', return_value='true'), patch.object(lr, 'install_cli') as installer:
            with self.assertRaisesRegex(ValueError, 'full local Git history'):
                lr.report(Path('.'), 'fixture', 'Fixture', '1.2.3', 'a'*40, 'https://example.invalid')
            installer.assert_not_called()

    def test_inherited_git_directory_cannot_redirect_source_metadata(self):
        result = subprocess.CompletedProcess([], 0, stdout='ok', stderr='')
        with patch.object(lr.subprocess, 'run', return_value=result) as command:
            lr.run(['git', 'status'], env={'GIT_DIR': '/unrelated', 'GIT_WORK_TREE': '/unrelated', 'PATH': '/usr/bin'})
            self.assertEqual(command.call_args.kwargs['env'], {'PATH': '/usr/bin'})

    def test_exact_onepassword_reference_is_runtime_fallback(self):
        self.exercise_report(env_key=False)

class ProjectDeliveryTests(unittest.TestCase):
    def args(self, directory, version='1.2.3'):
        return argparse.Namespace(version=version, artifacts=Path(directory), feed=Path(directory)/'appcast.xml',
                                  asset_name=None, dmg=None)

    def test_skips_cannot_claim_stable_completion_but_beta_does_not_need_gumroad(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(lr, 'github_release'), patch.object(lr, 'verify_download'), patch.object(lr, 'verify_feed'), patch.object(lr, 'run') as command:
            for flag in ['SKIP_GH_PAGES', 'SKIP_GUMROAD']:
                with patch.dict(os.environ, {flag: '1'}, clear=True), self.assertRaises(ValueError):
                    reporter.verify_delivery(self.args(directory))
            with patch.dict(os.environ, {'SKIP_GUMROAD': '1'}, clear=True):
                reporter.verify_delivery(self.args(directory, '1.2.3-beta.1'))
            command.assert_not_called()
            with patch.dict(os.environ, {}, clear=True):
                reporter.verify_delivery(self.args(directory))
            self.assertIn('--verify-only', command.call_args.args[0])





if __name__ == '__main__':
    unittest.main()
