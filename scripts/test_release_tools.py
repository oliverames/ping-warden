#!/usr/bin/env python3
"""Regression tests using isolated feeds and buyer-content fixtures."""
import copy
import io
import plistlib
import subprocess
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

import publish_gumroad as gumroad
import update_appcast as appcast


@unittest.skipUnless(sys.platform == "darwin", "release metadata uses macOS PlistBuddy")
class SentryReleaseTests(unittest.TestCase):
    def release_id(self, version="4.1.10", build="411000", bundle_id="com.amesvt.pingwarden", name="Ping Warden.app"):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / name
            (app / "Contents").mkdir(parents=True)
            with (app / "Contents/Info.plist").open("wb") as stream:
                plistlib.dump({"CFBundleIdentifier": bundle_id,
                              "CFBundleShortVersionString": version,
                              "CFBundleVersion": build}, stream)
            script = Path(__file__).resolve().parent / "release_validation.sh"
            return subprocess.run(["bash", "-c", 'source "$1"; sentry_release_for_app "$2"',
                                   "sentry-test", str(script), str(app)], capture_output=True, text=True)

    def test_matches_runtime_version_and_build(self):
        result = self.release_id()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "com.amesvt.pingwarden@4.1.10+411000")

    def test_prerelease_filename_does_not_replace_runtime_version(self):
        result = self.release_id(version="4.2.0", build="42000", name="PingWarden-4.2.0-beta.1.app")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "com.amesvt.pingwarden@4.2.0+42000")
        self.assertNotEqual(result.stdout, self.release_id(version="4.2.0", build="42001").stdout)

    def test_rejects_incomplete_or_invalid_metadata(self):
        for arguments in [{"bundle_id": "wrong"}, {"version": ""}, {"build": ""}, {"build": "beta"}]:
            result = self.release_id(**arguments)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")


class AppcastTests(unittest.TestCase):
    def item(self, version, build):
        return ET.fromstring(f'''<item xmlns:sparkle="{appcast.SPARKLE}">
          <sparkle:version>{build}</sparkle:version>
          <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
          <description>Changes</description><enclosure url="https://example.invalid/{version}.dmg" />
        </item>''')

    def test_paid_boundary_and_notice_survive_patch_releases(self):
        item = self.item("4.0.2", "40002")
        appcast.normalize(item)
        self.assertEqual(item.findtext(f"{{{appcast.SPARKLE}}}minimumAutoupdateVersion"), "40000")
        once = ET.tostring(item)
        appcast.normalize(item)
        self.assertEqual(ET.tostring(item), once)
        free = self.item("3.1.0", "30100")
        appcast.normalize(free)
        self.assertIsNone(free.find(f"{{{appcast.SPARKLE}}}minimumAutoupdateVersion"))

    def test_remove_coupon_from_github_rendered_notes(self):
        item = self.item("4.0.0", "40000")
        item.find("description").text = 'Donors receive a license via a hidden 100% off code (<code class="notranslate">PRIVATE-CODE</code>).'
        appcast.normalize(item)
        self.assertNotIn("PRIVATE-CODE", item.findtext("description"))

    def test_beta_keeps_prereleases_and_receives_stable_idempotently(self):
        with tempfile.TemporaryDirectory() as directory:
            stable, beta, entry = (Path(directory) / name for name in ("appcast.xml", "appcast-beta.xml", "item.xml"))
            ET.ElementTree(self.item("4.1.0-beta.1", "40100")).write(entry)
            appcast.update(stable, beta, entry, beta_release=True)
            ET.ElementTree(self.item("4.0.2", "40002")).write(entry)
            appcast.update(stable, beta, entry)
            first = (stable.read_bytes(), beta.read_bytes())
            appcast.update(stable, beta, entry)
            self.assertEqual(first, (stable.read_bytes(), beta.read_bytes()))
            versions = [appcast.value(i, "shortVersionString") for i in ET.parse(beta).findall("channel/item")]
            self.assertEqual(versions, ["4.1.0-beta.1", "4.0.2"])
            self.assertEqual(len(ET.parse(stable).findall("channel/item")), 1)

    def test_build_comparison_handles_legacy_and_current_formats(self):
        self.assertGreater(appcast.build_key("40002"), appcast.build_key("40001"))
        self.assertGreater(appcast.build_key("40000"), appcast.build_key("3.1.0"))
        with self.assertRaises(ValueError):
            appcast.build_key("4.0.2-beta")


class GumroadContentTests(unittest.TestCase):
    def test_upload_waits_for_metadata_to_settle(self):
        pending = {"product": {"files": [{"name": "release.dmg", "size": 0}]}}
        ready = {"product": {"files": [{"name": "release.dmg", "size": 123, "url": "https://example.invalid/release"}]}}
        with patch.object(gumroad, "gumroad", side_effect=[pending, ready]) as api:
            self.assertEqual(gumroad.wait_for_upload("product", "release.dmg", 123, attempts=2, delay=0), ready["product"])
            self.assertEqual(api.call_count, 2)

    def test_default_upload_wait_covers_slow_gumroad_processing(self):
        # 4.1.8 (2026-09-14): a 60-second window failed the release's last step
        # while Gumroad was still settling the file. Keep the default at five
        # minutes or more, and keep the override arithmetic honest.
        self.assertGreaterEqual(gumroad.DEFAULT_WAIT_SECONDS, 300)
        default_attempts = gumroad.wait_for_upload.__defaults__[0]
        self.assertGreaterEqual(default_attempts * gumroad.POLL_DELAY_SECONDS, gumroad.DEFAULT_WAIT_SECONDS)
        self.assertEqual(gumroad.attempts_for(300, delay=5), 60)
        self.assertEqual(gumroad.attempts_for(7, delay=5), 2)
        self.assertEqual(gumroad.attempts_for(0, delay=5), 1)

    def test_incomplete_upload_times_out_without_content_write(self):
        with patch.object(gumroad, "gumroad", return_value={"product": {"files": []}}) as api:
            with self.assertRaisesRegex(ValueError, "did not become ready"):
                gumroad.wait_for_upload("product", "release.dmg", 123, attempts=2, delay=0)
            self.assertEqual(api.call_count, 2)
            self.assertTrue(all(call.args == ("products", "view", "product") for call in api.call_args_list))

    def test_same_size_wrong_download_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "release.dmg"
            path.write_bytes(b"actual")
            with patch.object(gumroad.urllib.request, "urlopen", return_value=io.BytesIO(b"stale!")):
                with self.assertRaisesRegex(ValueError, "bytes do not match"):
                    gumroad.verify_download({"size": 6, "url": "https://example.invalid/release"}, path)

    def test_only_versioned_dmgs_are_replaced_and_license_content_survives(self):
        embed = lambda identifier: {"type": "fileEmbed", "attrs": {"id": identifier}}
        pages = [{"id": "first", "description": {"type": "doc", "content": [embed("old"), {"type": "licenseKey"}, {"type": "paragraph", "content": [{"text": "Activation instructions"}]}]}},
                 {"id": "second", "description": {"type": "doc", "content": [embed("guide"), embed("latest")]}}]
        files = [{"id": "old", "name": "PingWarden-4.0.1.dmg"}, {"id": "latest", "name": "PingWarden-4.0.2.dmg"}, {"id": "guide", "name": "Guide.pdf"}]
        original = copy.deepcopy(pages)
        updated, identifier = gumroad.replace_download(pages, files, "PingWarden-4.0.2.dmg")
        self.assertEqual(pages, original)
        self.assertEqual(identifier, "latest")
        self.assertEqual(updated[0]["description"]["content"][0], embed("latest"))
        self.assertEqual([n["attrs"]["id"] for n in gumroad.nodes(updated) if n.get("type") == "fileEmbed"], ["latest", "guide"])
        self.assertEqual([p["id"] for p in updated], ["first", "second"])
        self.assertEqual(sum(n.get("type") == "licenseKey" for n in gumroad.nodes(updated)), 1)
        self.assertEqual(gumroad.replace_download(updated, files, "PingWarden-4.0.2.dmg")[0], updated)

    def test_missing_license_or_wrong_product_blocks_publication(self):
        with self.assertRaises(ValueError):
            gumroad.validate({"id": gumroad.PRODUCT_ID, "published": True}, [])
        with self.assertRaises(ValueError):
            gumroad.validate({"id": "wrong", "published": True}, [{"type": "licenseKey"}])


if __name__ == "__main__":
    unittest.main()
