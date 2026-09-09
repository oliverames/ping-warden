# Issue and pull request review, September 9, 2026

Author: Oliver Ames

## Task list

- Complete: merge dependency pull requests #42, #53, #56, #59, and #60. GitHub confirms all five are merged.
- Complete: remove the orphaned donation-prompt policy, annotate historical release notes, and correct the inventory for #61.
- Complete: create and privately store a replacement donor offer for #62.
- Verified locally: 131 remaining core tests, 9 release-tool tests, complete unsigned Release build, and website build/check.
- Complete: push the verified changes to main. GitHub confirms both original issues are closed and all five original pull requests are merged. Wrap-up verification follow-ups are tracked separately below.
- Hosted validation: [Build Verification](https://github.com/oliverames/ping-warden/actions/workflows/build.yml), [CodeQL](https://github.com/oliverames/ping-warden/actions/workflows/codeql.yml), and [Website Verification](https://github.com/oliverames/ping-warden/actions/workflows/site.yml) provide current run results.

## Dependency review

The two CodeQL pull requests failed because initialization and analysis used different action versions. Run 33918458228 reports: `Loaded a configuration file for version '4.37.1', but running version '4.37.9'`. Both steps now use the same pinned 4.37.9 commit.

Sparkle 2.9.6 and Sentry 9.26.0 were already resolved on main. Their pull requests align the minimum-version settings with those pins. Checkout moves to 7.0.1, including the website workflow added after #42 opened.

The combined dependency changes passed 140 core tests and a complete unsigned Release build before the merge commit.

## Donation prompt

The old launch-donation policy has no app caller. Its removal preserves the licensed model and the separate transition reminder. The old beta notes refer to a historical release. The signed feeds remain historical artifacts and are not rewritten to describe current behavior. The licensing inventory now explains this distinction.

## Donor offer

The published product matches the app's product ID. The existing 100% offer was disabled after public disclosure on September 4. It remains disabled. The replacement offer and private URL must not appear in this repository or public issues.

The replacement was read back from Gumroad and verified as 100% off, product-specific, with no redemption cap and zero uses. The code and private URL were read back from 1Password and matched. The code is absent from the public product page. No order was placed.

## Delivery boundary

The changes are committed and pushed to main. No new app release or website deployment was performed. GitHub accepted the direct push using the existing owner bypass and reported the combined merge commit against its linear-history rule, along with pre-push status checks. Repository rules and permissions were not changed.

## Wrap-up verification follow-ups

Hosted build, Linux core tests, and shell checks passed for `31fc177`. Website verification passed for `954f74b`. CodeQL is still running and is tracked in [#63](https://github.com/oliverames/ping-warden/issues/63). The previously documented live-game validation gap is carried forward in [#64](https://github.com/oliverames/ping-warden/issues/64). Neither item is a confirmed new defect. The worklog records both outcomes and next steps.
