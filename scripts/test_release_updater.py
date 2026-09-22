"""Exercise the actual release scripts against an isolated Paper API fixture."""
import functools
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


class ReleaseUpdaterTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        shutil.copytree(Path(__file__).parent, self.root / 'scripts')
        self.props = self.root / 'gradle.properties'
        self.output = self.root / 'output'
        self.api = self.root / 'api'
        self.api.mkdir()
        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0),
            functools.partial(QuietHandler, directory=self.api))
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.env = dict(os.environ, PAPER_API=f'http://127.0.0.1:{self.server.server_port}/project',
                        PAPER_CHANNEL='STABLE', GITHUB_OUTPUT=str(self.output))

    def pin(self, version='26.2', build='121-stable'):
        self.props.write_text(f'# Keep this comment\npluginVersion=1.0.34\npaperApiVersion={version}\n'
                             f'paperApiDependencyVersion={version}.build.{build}\n'
                             'hangarProjectId=NoVillagerSpawnedGolems\n\ncustom=value=with=equals\n')
        return self.props.read_bytes()

    def fixture(self, versions):
        project = self.api / 'project'
        project.mkdir()
        (project / 'index.html').write_text(json.dumps({'versions': {'26': list(versions)}}))
        for version, builds in versions.items():
            folder = project / 'versions' / version
            folder.mkdir(parents=True)
            (folder / 'builds').write_text(json.dumps([
                {'id': number, 'channel': channel} for number, channel in builds]))

    def run_script(self, script='update-to-latest-paper.sh', *args, success=True):
        result = subprocess.run(['bash', str(self.root / 'scripts' / script), *args],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_upgrade_preserves_configuration_and_second_run_is_noop(self):
        before = self.pin()
        self.fixture({'26.2': [(123, 'STABLE'), (122, 'STABLE')]})
        self.run_script()
        expected = before.replace(b'1.0.34', b'1.0.35').replace(b'121-stable', b'123-stable')
        self.assertEqual(self.props.read_bytes(), expected)
        self.assertIn('changed=true', self.output.read_text())
        self.output.unlink()
        self.run_script()
        self.assertEqual(self.props.read_bytes(), expected)
        self.assertIn('changed=false', self.output.read_text())

    def test_stable_cannot_downgrade_alpha_version(self):
        before = self.pin('26.3', '32-alpha')
        self.fixture({'26.3': [(32, 'ALPHA')], '26.2': [(127, 'STABLE')]})
        self.run_script()
        self.assertEqual(self.props.read_bytes(), before)
        self.assertIn('changed=false', self.output.read_text())

    def test_stable_cannot_downgrade_build(self):
        before = self.pin('26.3', '32-alpha')
        self.fixture({'26.3': [(31, 'STABLE'), (32, 'ALPHA')]})
        self.run_script()
        self.assertEqual(self.props.read_bytes(), before)

    def test_newer_stable_can_replace_alpha(self):
        self.pin('26.3', '32-alpha')
        self.fixture({'26.3': [(33, 'STABLE')]})
        self.run_script()
        self.assertIn('26.3.build.33-stable', self.props.read_text())
        self.assertIn('hangarProjectId=', self.props.read_text())

    def test_release_sorts_after_prerelease(self):
        self.pin('26.2', '121-stable')
        self.fixture({'26.3-pre1': [(99, 'STABLE')], '26.3': [(1, 'STABLE')]})
        self.run_script()
        self.assertIn('paperApiDependencyVersion=26.3.build.1-stable', self.props.read_text())

    def test_missing_eligible_build_does_not_modify_file(self):
        before = self.pin()
        self.fixture({'26.3': [(32, 'ALPHA')]})
        self.run_script(success=False)
        self.assertEqual(self.props.read_bytes(), before)
        self.assertFalse(self.output.exists())

    def test_api_failure_does_not_modify_file(self):
        before = self.pin()
        self.run_script(success=False)
        self.assertEqual(self.props.read_bytes(), before)
        self.assertFalse(self.output.exists())

    def test_duplicate_version_property_rejected(self):
        self.pin()
        with self.props.open('a') as handle:
            handle.write('pluginVersion=1.0.34\n')
        before = self.props.read_bytes()
        self.fixture({'26.2': [(123, 'STABLE')]})
        self.run_script(success=False)
        self.assertEqual(self.props.read_bytes(), before)
        self.assertFalse(self.output.exists())

    def test_explicit_mismatched_dependency_rejected(self):
        before = self.pin()
        self.run_script('update-to-paper-version.sh', '--paper-version', '26.3',
                        '--paper-dependency-version', '26.2.build.127-stable', success=False)
        self.assertEqual(self.props.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
