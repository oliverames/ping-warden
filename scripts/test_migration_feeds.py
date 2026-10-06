#!/usr/bin/env python3
"""Synthetic standard-library fixtures. No Sparkle, app, Keychain or network runs."""

import argparse
import contextlib
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest

import validate_migration_feeds as guard


# Hypothetical fixture numbers, not proposed release numbers.
CANDIDATE = 60000
BRIDGE = 50000
S = guard.PREFIX


def item(build, *, minimum=None, autoupdate=None, informational=None,
         link="https://example.invalid/migration", enclosure=True, extra=""):
    fields = [f"<sparkle:version>{build}</sparkle:version>"]
    if minimum is not None:
        fields.append(f"<sparkle:minimumUpdateVersion>{minimum}</sparkle:minimumUpdateVersion>")
    if autoupdate is not None:
        fields.append(f"<sparkle:minimumAutoupdateVersion>{autoupdate}</sparkle:minimumAutoupdateVersion>")
    if informational is not None:
        fields.append(f"<sparkle:informationalUpdate>{informational}</sparkle:informationalUpdate>")
    if link is not None:
        fields.append(f"<link>{link}</link>")
    if enclosure:
        fields.append(f'<enclosure url="https://example.invalid/{build}.dmg" sparkle:version="{build}" />')
    return "<item>" + "".join(fields) + extra + "</item>"


def candidate(**kwargs):
    return item(CANDIDATE, minimum=BRIDGE, **kwargs)


def feed(*items):
    return f'<rss version="2.0" xmlns:sparkle="{guard.SPARKLE}"><channel><title>Fixture</title>{"".join(items)}</channel></rss>'


class FeedGuardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ping-warden-feed-fixture-")
        self.addCleanup(self.temporary.cleanup)
        self.stable = Path(self.temporary.name) / "stable.xml"
        self.beta = Path(self.temporary.name) / "beta.xml"

    def validate(self, stable, beta=None, **kwargs):
        self.stable.write_text(stable, encoding="utf-8")
        self.beta.write_text(beta if beta is not None else stable, encoding="utf-8")
        before = [hashlib.sha256(path.read_bytes()).hexdigest() for path in (self.stable, self.beta)]
        report = guard.validate(self.stable, self.beta, candidate_build=CANDIDATE,
                                required_bridge_build=BRIDGE, **kwargs)
        after = [hashlib.sha256(path.read_bytes()).hexdigest() for path in (self.stable, self.beta)]
        self.assertEqual(before, after, "validator must not rewrite either input")
        return report

    def codes(self, report):
        return {finding.code for finding in report.findings}

    def test_hold_first_feed_passes_and_keeps_mandatory_hosts(self):
        report = self.validate(feed(candidate(), item(BRIDGE, informational=""), item("3.1.0")), extra_hosts=[41000])
        self.assertEqual(report.findings, [])
        self.assertEqual(report.result()["status"], "PASS_CONSERVATIVE_HOLD")
        self.assertEqual(report.hosts, [40000, 40001, 41000, 43100, 49999, 50000, 50001, 59999])
        self.assertEqual(report.parsed_items, {"stable": 3, "beta": 3})

    def test_newest_boundary_does_not_hide_older_unsafe_fallback(self):
        report = self.validate(feed(candidate(), item(43100, autoupdate=40000)))
        fallback = [f for f in report.findings if f.code == "unreviewed_fallback" and f.host == 40000]
        self.assertEqual({(f.feed, f.item) for f in fallback}, {("stable", "43100"), ("beta", "43100")})

    def test_minimum_autoupdate_cannot_replace_minimum_update(self):
        report = self.validate(feed(item(CANDIDATE, autoupdate=BRIDGE)))
        self.assertIn("candidate_boundary", self.codes(report))
        self.assertTrue(any(f.code == "candidate_bypasses_bridge" and f.host == 40000 for f in report.findings))

    def test_boundary_requires_exact_bridge_including_equality(self):
        for minimum in (BRIDGE - 1, BRIDGE + 1):
            with self.subTest(minimum=minimum):
                report = self.validate(feed(item(CANDIDATE, minimum=minimum)))
                self.assertIn("candidate_boundary", self.codes(report))
        self.assertEqual(self.validate(feed(candidate())).findings, [])

    def test_bridge_build_is_not_a_fallback_approval(self):
        report = self.validate(feed(candidate(), item(BRIDGE)))
        self.assertTrue(any(f.code == "unreviewed_fallback" and f.item == str(BRIDGE) and f.host == 40000 for f in report.findings))

    def test_informational_exact_scope_is_not_global(self):
        scope = "<sparkle:version>40000</sparkle:version>"
        report = self.validate(feed(candidate(), item(43100, informational=scope)))
        self.assertFalse(any(f.host == 40000 for f in report.findings))
        self.assertTrue(any(f.code == "unreviewed_fallback" and f.host == 40001 for f in report.findings))

    def test_host_probes_find_holes_between_known_shipped_builds(self):
        scopes = "".join(f"<sparkle:version>{host}</sparkle:version>" for host in guard.BASE_HOSTS)
        report = self.validate(feed(candidate(), item(45000, informational=scopes)))
        self.assertTrue(any(f.code == "unreviewed_fallback" and f.host == 40002 for f in report.findings))

    def test_fractional_numeric_boundary_includes_next_integer_host(self):
        report = self.validate(feed(candidate(), item(45000, minimum="40001.1")))
        self.assertFalse(any(f.code == "unreviewed_fallback" and f.host == 40001 for f in report.findings))
        self.assertTrue(any(f.code == "unreviewed_fallback" and f.host == 40002 for f in report.findings))

    def test_informational_exact_scope_uses_strings(self):
        scope = "<sparkle:version>40000.0</sparkle:version>"
        report = self.validate(feed(candidate(), item(40001, informational=scope)))
        self.assertTrue(any(f.code == "unreviewed_fallback" and f.host == 40000 for f in report.findings))

    def test_informational_scope_whitespace_fails_closed(self):
        for name in ("version", "belowVersion"):
            with self.subTest(scope=name):
                scope = f"<sparkle:{name}> 40000 </sparkle:{name}>"
                report = self.validate(feed(candidate(), item(40001, informational=scope)))
                self.assertIn("unsupported_item", self.codes(report))

    def test_informational_namespace_alias_fails_closed(self):
        scope = '<s:version>40000</s:version><sparkle:version>40001</sparkle:version>'
        source = feed(candidate(), item(40002, informational=scope))
        source = source.replace('<rss version="2.0"', f'<rss version="2.0" xmlns:s="{guard.SPARKLE}"')
        self.assertIn("unsupported_feed", self.codes(self.validate(source)))

    def test_non_utf8_declaration_fails_closed(self):
        for encoding in ("iso-8859-1", "US-ASCII", "UTF-16"):
            with self.subTest(encoding=encoding):
                source = f'<?xml version="1.0" encoding="{encoding}"?>' + feed(candidate())
                self.assertIn("unsupported_feed", self.codes(self.validate(source)))
        source = '<?xml version="1.0" encoding="UTF-8"?>' + feed(candidate())
        self.assertEqual(self.validate(source).findings, [])

    def test_below_scope_is_strict_at_boundary(self):
        scope = "<sparkle:belowVersion>40001</sparkle:belowVersion>"
        report = self.validate(feed(candidate(), item(43100, informational=scope)))
        self.assertFalse(any(f.host == 40000 for f in report.findings))
        self.assertTrue(any(f.host == 40001 for f in report.findings))

    def test_information_without_enclosure_is_supported(self):
        self.assertEqual(self.validate(feed(candidate(), item(BRIDGE, enclosure=False))).findings, [])

    def test_informational_update_requires_usable_link(self):
        for link in (None, "file:///tmp/installer", "https://", "https://user:password@example.invalid/"):
            with self.subTest(link=link):
                report = self.validate(feed(candidate(), item(BRIDGE, informational="", link=link)))
                self.assertIn("unsupported_item", self.codes(report))

    def test_candidate_cannot_be_informational_for_bridge(self):
        report = self.validate(feed(candidate(informational="")))
        self.assertIn("candidate_not_installable", self.codes(report))

    def test_checks_beta_older_fallback_even_when_stable_is_clear(self):
        report = self.validate(feed(candidate()), feed(candidate(), item(43100)))
        self.assertTrue(report.findings)
        self.assertEqual({f.feed for f in report.findings}, {"beta"})

    def test_requires_candidate_in_both_complete_feeds(self):
        report = self.validate(feed(candidate()), feed(item(BRIDGE, informational="")))
        self.assertTrue(any(f.feed == "beta" and f.code == "candidate_missing" for f in report.findings))

    def test_rejects_newer_item_even_if_informational(self):
        self.assertIn("newer_than_candidate", self.codes(self.validate(feed(candidate(), item(CANDIDATE + 1, informational="")))))

    def test_rejects_different_item_and_enclosure_versions(self):
        bad = candidate().replace(f'sparkle:version="{CANDIDATE}"', 'sparkle:version="40001"')
        self.assertIn("unsupported_item", self.codes(self.validate(feed(bad))))

    def test_rejects_duplicate_items_and_numeric_aliases(self):
        for extra in (candidate(), item("60000.0", minimum=BRIDGE)):
            with self.subTest(extra=extra):
                self.assertIn("unsupported_item", self.codes(self.validate(feed(candidate(), extra))))

    def test_rejects_unknown_selection_constructs(self):
        for extra in (
            "<sparkle:deltas />", "<sparkle:channel>beta</sparkle:channel>",
            "<sparkle:hardwareRequirements />", "<sparkle:phasedRolloutInterval>86400</sparkle:phasedRolloutInterval>",
            "<sparkle:criticalUpdate />", "<minimumUpdateVersion>50000</minimumUpdateVersion>",
            "<sparkle:informationalUpdate><sparkle:unknown>40000</sparkle:unknown></sparkle:informationalUpdate>",
        ):
            with self.subTest(extra=extra):
                self.assertIn("unsupported_item", self.codes(self.validate(feed(candidate(), item(43100, extra=extra)))))

    def test_os_restriction_is_never_treated_as_safe_exclusion(self):
        extra = "<sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion>"
        report = self.validate(feed(candidate(), item(43100, extra=extra)))
        self.assertIn("unreviewed_fallback", self.codes(report))

    def test_rejects_version_suffixes_and_implicit_versions(self):
        for bad in (item("4.0.1-beta"), item("040001"), item("4.0.1.1"), item("40001").replace("<sparkle:version>40001</sparkle:version>", "").replace(' sparkle:version="40001"', "")):
            with self.subTest(bad=bad):
                self.assertIn("unsupported_item", self.codes(self.validate(feed(candidate(), bad))))

    def test_old_numeric_version_comparison(self):
        self.assertLess(guard.version("3.10.0"), guard.version("40000"))
        self.assertGreater(guard.version("3.10"), guard.version("3.9.9"))
        self.assertEqual(guard.version("3.1"), guard.version("3.1.0"))

    def test_duplicate_and_misplaced_boundary_rejected(self):
        bad = candidate(extra="<sparkle:minimumUpdateVersion>50000</sparkle:minimumUpdateVersion>")
        self.assertIn("unsupported_item", self.codes(self.validate(feed(bad))))
        bad = candidate().replace('<enclosure url=', '<enclosure sparkle:minimumUpdateVersion="50000" url=')
        self.assertIn("unsupported_item", self.codes(self.validate(feed(bad))))

    def test_malformed_root_and_entities_fail_closed(self):
        for source in ("<rss", '<rss version="2.0"><channel /><channel /></rss>', '<!DOCTYPE rss [<!ENTITY x "value">]>' + feed(candidate())):
            with self.subTest(source=source):
                self.assertIn("unsupported_feed", self.codes(self.validate(source)))

    def test_utf16_and_missing_file_fail_closed(self):
        self.stable.write_bytes(feed(candidate()).encode("utf-16"))
        report = guard.validate(self.stable, self.beta, candidate_build=CANDIDATE, required_bridge_build=BRIDGE)
        self.assertEqual({f.feed for f in report.findings if f.code == "unsupported_feed"}, {"stable", "beta"})

    def test_same_file_cannot_stand_in_for_both_feeds(self):
        self.stable.write_text(feed(candidate()), encoding="utf-8")
        report = guard.validate(self.stable, self.stable, candidate_build=CANDIDATE, required_bridge_build=BRIDGE)
        self.assertIn("same_feed", self.codes(report))

    def test_build_arguments_and_order_fail_closed(self):
        for candidate_build, bridge_build in ((BRIDGE, CANDIDATE), (CANDIDATE, 40000), (BRIDGE, BRIDGE), ("60000-beta", BRIDGE)):
            with self.subTest(candidate=candidate_build, bridge=bridge_build):
                with self.assertRaises((ValueError, argparse.ArgumentTypeError)):
                    guard.validate(self.stable, self.beta, candidate_build=candidate_build, required_bridge_build=bridge_build)

    def test_cli_requires_both_explicit_builds(self):
        for arguments in ([], ["--migration-candidate-build", str(CANDIDATE)], ["--required-bridge-build", str(BRIDGE)]):
            with self.subTest(arguments=arguments), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    guard.main(["--stable", str(self.stable), "--beta", str(self.beta)] + arguments)
                self.assertEqual(raised.exception.code, 2)

    def test_cli_json_and_exit_codes(self):
        for source, expected_exit, expected_status in ((feed(candidate()), 0, "PASS_CONSERVATIVE_HOLD"), (feed(candidate(), item(43100)), 1, "FAIL")):
            with self.subTest(status=expected_status):
                self.stable.write_text(source, encoding="utf-8")
                self.beta.write_text(source, encoding="utf-8")
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    code = guard.main(["--stable", str(self.stable), "--beta", str(self.beta), "--migration-candidate-build", str(CANDIDATE), "--required-bridge-build", str(BRIDGE)])
                self.assertEqual(code, expected_exit)
                self.assertEqual(json.loads(output.getvalue())["status"], expected_status)


if __name__ == "__main__":
    unittest.main(verbosity=2)
