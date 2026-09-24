# Targets native layout

Author: Oliver Ames  
Date: September 24, 2026

## Scope and task list

Oliver requested that the Targets tab remain and match the app's other settings pages. The separate issue-review task released ownership of Targets layout after its functional fixes in a344c0c. This task preserves those fixes.

- [x] Compare Targets with General, License, Automation, and Advanced.
- [x] Replace the custom dashboard cards and fixed label columns with a grouped Form and native Sections.
- [x] Build the production app with Xcode.
- [x] Inspect native previews in light and dark appearance, including the add form and minimum width.
- [x] Complete Oliver's requested independent regression review before committing. No actionable regression findings.
- [ ] Record live click and keyboard acceptance in #90 when desktop automation is available.
- [x] Record visual evidence and the independent review.
- [ ] Commit, push, and record the result in existing #90 tracking.

The application changes are limited to Targets composition in DashboardView.swift and its existing scroll-edge modifier at the SettingsContentView call site. The tab, target selection, update intervals, automatic target selection, validation, add/cancel/save, and removal remain available. The older unused DashboardControlRow is removed.

## Verification and evidence

The production app builds successfully through Xcode's native build tool after the final source edit. The final build reported no errors on September 24 at 14:17. All 26 existing actual-source presentation checks passed. A before/after source comparison confirmed that the begin-add, cancel, save, and validation-error methods are unchanged.

Xcode rendered the actual settings views in a separate fixture on macOS 27.2. It uses unique bundle identifiers, in-memory preferences, a separate file root, and inert helper, keychain, licensing, telemetry, login-item, discovery, and probe boundaries. The installed app and its data were not replaced. The preview name controls its window title.

| Appearance and size | Observed result | Capture |
| --- | --- | --- |
| Light, 980 × 720 points | Native shaded groups, external headings, trailing pickers, sidebar Targets retained | [Targets](images/targets-native-2026-09-24/light.png) |
| Dark, 760 × 520 points | Target, interval, and add controls fit at the minimum size | [Minimum dark](images/targets-native-2026-09-24/minimum-dark.png) |
| Add server, light, 980 × 720 points | Name, host, port, Cancel, and disabled empty Save all visible | [Add form](images/targets-native-2026-09-24/add-server-light.png) |
| Add server, dark, 760 × 520 points | Fields and actions fit, with no clipped labels or duplicate port label | [Minimum add form](images/targets-native-2026-09-24/add-server-minimum-dark.png) |

The add-form preview initially exposed a duplicate “53” label. Hiding the nested TextField label corrected it while retaining the enclosing Port label and explicit accessibility label. The corrected layout was rendered again and the production app rebuilt successfully.

These are rendered previews. The add form was opened using fixture state, not by a successful click. Computer Use failed initialization with error -10005, so live picker interaction, Return/Escape, focus changes, and removal were not observed here. Those acceptance items remain in [#90](https://github.com/oliverames/ping-warden/issues/90). This does not imply a known runtime defect. Broader signed-release and system accessibility checks remain in their existing issues.

These verification captures are excluded from Product Hunt. The gallery leads with the real screenshot currently used on the landing page.

## Design basis

Targets previously reused dashboard cards with manual label widths, padding, and separators. The other settings panes use grouped Forms. Applying their existing pattern lets macOS provide consistent row spacing, section backgrounds, picker placement, and dividers.

Xcode's local Apple documentation archive recommends Form for settings and preference interfaces, with platform-specific controls. Its Picker documentation supports composing a label from a title and supporting text. Sources: [Form](https://developer.apple.com/documentation/swiftui/form), [Picker](https://developer.apple.com/documentation/swiftui/picker).

## Independent review plan, September 24

Review the current app diff against 5839f30 for changes to target selection, saved targets, validation, focus, keyboard actions, loading/error states, and deployment-target compatibility. Verify that a344c0c behavior remains intact. Reviewers must provide tool-backed evidence and actionable findings, without touching the installed app, personal preferences, real network configuration, or licensing. Root will finish launch copy and evidence documentation concurrently, then resolve findings and commit only after review.

## Independent review result

The separate reviewer found no actionable regressions after inspecting the full two-file diff, target selection and saved-selection fallback, picker bindings, retry actions, busy states, removal identifiers, focus bindings, Return/Escape shortcuts, and macOS availability guards. The existing a344c0c fixes remain intact. The reviewer also inspected the light, dark, minimum-width, and add-form previews.

The reviewer independently ran 18 existing focused tests: 11 CustomPingTargetStoreTests, three SettingsCorrectionTests, and four TelemetryDemandResolverTests. All executed with zero failures and zero skips. Root inspected the successful output. Tests used scratch compiler caches and isolated preference suites. No production state was involved.

The review found stale launch-document metadata in WORKLOG. The maker comment is now correctly recorded as 185 words, with the intervention-counter clarification in the gallery caption. This was corrected and rechecked. No further application source changes were needed after the review.
