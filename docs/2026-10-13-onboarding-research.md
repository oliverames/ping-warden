# Helper onboarding research and design proposal, October 13, 2026

Design work for [issue 124](https://github.com/oliverames/ping-warden/issues/124): a guided setup flow for helper approval, reused by Repair. Research and a clickable mockup only. No app code changed.

Clickable mockup: `docs/onboarding-mockup-4.4.html` (open it in a browser; the panel and the live-state bar drive the simulated macOS state).

## How to read the evidence

- **SEEN**: someone on this review read the primary page, source file, or image. **TEXT**: only text was readable. **NOT SEEN**: no primary evidence found, and no claim is made.
- Two research subagents gathered most of the product evidence. I spot-checked the load-bearing claims myself: the Rogue Amoeba background-item article, the Loopback install post, Apple's Login Items guide pages for macOS 13, 14, 15, 26 and 27, and the Login Items strings on this Mac (macOS 27.2).
- Window sizes quoted for apps come from source code or image pixel sizes, not from running the apps.
- The exact text of the macOS "Background Items Added" notification has no Apple primary source. The only wording found is in community posts, so the mockup banner is a paraphrase.

## Findings that change the plan

1. **The section name changes on macOS 26 and later.** The issue says "Allow in the Background" for macOS 15 and later. Apple's own guide says that on macOS 26 and 27 the switch section is **App Background Activity**, and "Allow in the Background" on 13 to 15. The Login Items settings extension on this Mac (macOS 27.2) agrees: its English strings contain "App Background Activity" and "Login Items & Extensions" and no "Allow in the Background". The pane name is "Login Items" on 13 and 14 and "Login Items & Extensions" on 15 and later. `SystemSettingsCopy` currently varies only the pane name, so the section needs a third variant. Sources: [macOS 27 guide](https://support.apple.com/guide/mac-help/mtusr003/27/mac/27), [macOS 26 guide](https://support.apple.com/guide/mac-help/mtusr003/26/mac/26), [macOS 15 guide](https://support.apple.com/guide/mac-help/mtusr003/15.0/mac/15.0), [macOS 14 guide](https://support.apple.com/guide/mac-help/mtusr003/14.0/mac/14.0), [macOS 13 guide](https://support.apple.com/guide/mac-help/mtusr003/13.0/mac/13.0). The local check read `/System/Library/ExtensionKit/Extensions/LoginItems.appex/Contents/Resources` with `strings`. The macOS 26 evidence is Apple's guide only; confirm on a 26 machine before shipping.
2. **Rogue Amoeba removed the approval from most of its products, and its closest remaining pattern is a single background-item window.** Its current setup (ARK) needs no System Settings toggle, no restart, and no security-policy change. Loopback and SoundSource ask for one administrator password. Audio Hijack, Piezo and Airfoil ask for none. The pattern closest to ours is the "Enable Background Item" window described below. Ping Warden's daemon cannot avoid the approval, but Docker and iStat Menus show the same lesson: ask as late as possible.
3. **Nobody in the sample ships a floating guide window beside System Settings, an animated toggle hint, or a live preview of the pane.** The one floating-panel example is a library ([PermissionFlow](https://github.com/jaywcjlove/PermissionFlow), README only), not a shipping app. The common pattern is a card or dialog in the app, then macOS opens System Settings, then the app watches state.
4. **There is no documented approval callback for `SMAppService`.** The documentation lists register, unregister, status and `openSystemSettingsLoginItems()`, and no observer or notification. That is an inference from absence. The app must poll `status`, which the monitor already does once a second.

## Part 1: What polished Mac apps do

### Rogue Amoeba (Audio Hijack, Loopback, SoundSource)

**Current flow (ARK), SEEN.** Source: the official 32-second install video ([mp4](https://weblog.rogueamoeba.com/wp-content/uploads/2024-06-loopback/timed-install.mp4)) from the post [Now You Can Install Loopback in Under One Minute](https://weblog.rogueamoeba.com/2024/06/07/now-you-can-install-loopback-in-under-one-minute/), and the manual pages for [Loopback permissions](https://rogueamoeba.com/support/manuals/loopback/?page=Permissions) and [Audio Hijack permissions](https://rogueamoeba.com/support/manuals/audiohijack/?page=Permissions).

- **Step structure:** one "Permissions" window, not a wizard. A left panel carries the icon and a headline. A right panel is a vertical stack of cards, each with an icon, a title, two or three lines, a Required or Optional tab, and an Enable button.
- **Gating:** only the active card is highlighted. The others are dimmed with disabled buttons. Enable swaps to a spinner, then to a green check and "Enabled", and the next card lights up. The Continue button stays disabled until the required cards are done.
- **System Settings preview:** none for ARK. The administrator password sheet and the standard permission prompts appear over the window.
- **Live detection:** yes, shown in the video frames. The card changes state on its own and Continue activates.
- **Text density:** low, one to three lines per card.
- **Window size:** about 760 by 685 points in the manual screenshot (Audio Hijack 760 by 676).
- **Failure and retry:** no failure state in the video. The Permissions window can be reopened from the app menu, and the manual shows a "Relaunch" prompt after a denied microphone permission.
- **Claim check:** the blog post says setup takes under 60 seconds and no restart, and that Loopback asks for the administrator password then grants permissions (SEEN, my check).

**Enable Background Item window (older ACE flow), SEEN.** Source: [About background processes used by Audio Hijack](https://rogueamoeba.com/support/knowledgebase/?showArticle=Misc-AboutBackgroundItems&product=Audio+Hijack). This is the closest analogue to Ping Warden's switch.

- **Structure:** one small modal, titled "Enable Background Item". A large all-caps headline says the component needs to run in the background. Beneath it is a cropped screenshot of the Login Items pane, showing only the "Open at Login" and "Allow in the Background" sections. The target row has a blue glow and a white arrow points at its toggle. Two sentences follow, with "Open System Settings" as a link, and the footer has Quit and Continue.
- **Preview style:** cropped real screenshot with a glow and an arrow. A second, light-mode crop shows the disabled state.
- **Re-enable path:** the in-app prompt links to System Settings, the user flips the switch, authenticates with an administrator password, then returns to the app. The app re-shows the prompt at launch while the item is disabled.
- **Auto-advance:** NOT SEEN. The window tells the user to click Continue, so whether Continue is gated on detection is unknown.
- **Window size:** about 620 by 486 (image pixels).
- **Section naming:** the article says Ventura and later use the "Allow in the Background" section. Rogue Amoeba's own copy will need the same macOS 26 update.

**Legacy ACE installer on Apple Silicon, SEEN (support slides).** [ACE step by step](https://rogueamoeba.com/support/knowledgebase/?showArticle=ACE-StepByStep) is archived. A welcome slide shows a three-icon row: click Install, enter your password, acknowledge the alert. The Apple Silicon path was about 19 slides including Recovery mode and two restarts. That is the flow Rogue Amoeba abandoned. Its lasting lessons are the three-icon "what will happen" row and the highlighted real-screenshot crops. Auto-advance is NOT SEEN because these are static slides.

Positioning sources: [Ridiculously Easy Setup (2024-09)](https://rogueamoeba.com/company/lists/archives/macos/2024-09-simplifiedsetup.html) and the [ACE deprecation note](https://rogueamoeba.com/support/knowledgebase/?showArticle=ACE-Legacy&product=SoundSource), both TEXT.

### Little Snitch and LuLu (system extension approval)

**Little Snitch 6, SEEN.** Source: [Install guide](https://help.obdev.at/littlesnitch6/intro-install).

- **Structure:** a welcome window (icon, title, "The installation needs to be completed.", three short lines, one centered Install button), then a license screen, then macOS prompts, then System Settings at Privacy & Security on macOS 14, then a "Background Items Added" notification with an explanation of its two items.
- **Preview:** a real screenshot with the target row boxed in an orange rounded outline. No arrow, no animation.
- **Recovery:** the guide warns twice that macOS makes the wrong button the default ("OK" instead of "Open System Settings"). If the user clicks OK by mistake, Little Snitch offers a window explaining the procedure with a button to open System Settings.
- **Little Snitch Mini variant, SEEN:** [installation guide](https://help.obdev.at/littlesnitchmini/installation) uses a stylized grey skeleton of the pane with numbered orange callouts instead of a real screenshot. Of everything checked, this is the cleanest illustration and the closest to what we propose.
- **Live detection:** NOT SEEN. Release notes mention updated first-time instructions for macOS 15 and "illustrated" guidance in 5.3.1 ([6.x notes](https://www.obdev.at/littlesnitch/releasenotes.html), [5.x notes](https://www.obdev.at/products/littlesnitch/releasenotes5.html), TEXT).
- **Window size:** about 900 by 420 as rendered in the image.

**LuLu, SEEN.** Source: [LuLu page](https://objective-see.org/products/lulu.html). A dark welcome window (about 700 by 378) with a Next button. The page calls approval "a multi-step process driven by macOS": a macOS prompt where "OK" is the default, then Network Extensions in System Settings, then authentication, then Allow. There is no in-app illustration of the pane. Live detection is NOT SEEN. The page notes that steps may vary by macOS version.

### Tailscale (standalone macOS client)

Sources: [system extension doc](https://tailscale.com/docs/concepts/macos-sysext) (SEEN images) and the [changelog](https://tailscale.com/changelog) (TEXT).

- **Structure:** a standard alert titled "System Extension Approval Required" with two paragraphs and two buttons, Ignore and Open Settings. No picture of System Settings.
- **Recovery:** a menu bar item "System Extension Approval Required..." with a warning triangle stays available after Ignore.
- **Live detection:** the changelog says onboarding advances automatically once the device connects (1.60.0), alerts with troubleshooting when the extension fails to start, and detects a manually disabled extension and shows a notice (1.80.0).
- **Naming care:** a changelog entry says the row in System Settings was renamed to "Tailscale Network Extension" to reduce user confusion.
- **Not seen:** the full onboarding window, its size, and its button wording.

### Bartender, CleanShot X, iStat Menus, 1Password, Docker Desktop

- **Bartender, TEXT:** [permission info](https://www.macbartender.com/Bartender5/PermissionInfo/) explains why Screen Recording and Accessibility are needed and stresses it does not record the screen. [Permission issues](https://www.macbartender.com/Bartender5/PermissionIssues/) is a manual escalation ladder (remove and re-add, `tccutil reset`, support). Onboarding window and live detection: NOT SEEN.
- **CleanShot X, TEXT (transcript only):** the 2022 official video [First steps with CleanShot X](https://www.youtube.com/watch?v=F4DMNp-Vt3A) describes a short wizard (license, activation, replace shortcuts, optional cloud, stats) and says Screen Recording is prompted at first use. Layouts, Accessibility onboarding and detection: NOT SEEN. The video predates recent macOS permission changes.
- **iStat Menus, TEXT:** the [helper page](https://bjango.com/help/istatmenus7/helper/) and [version history](https://bjango.com/mac/istatmenus/versionhistory/) show 7.0 made the helper optional and installable without a password. The [Login Items troubleshooting page](https://bjango.com/help/istatmenus7/loginitems) is a recovery recipe. First-launch prompt and detection: NOT SEEN.
- **Docker Desktop, TEXT:** the [install page](https://docs.docker.com/desktop/setup/install/mac-install/) and [permission requirements](https://docs.docker.com/desktop/setup/install/mac-permission-requirements/) say current versions ask for no password at first run and move privileged access to Settings, Advanced, on demand. Older versions offered "Use recommended settings (requires password)". No Allow in the Background flow is described. No screenshots.
- **1Password, TEXT:** the [Universal Autofill page](https://support.1password.com/mac-universal-autofill/) points users to the Accessibility pane with a plus-button fallback and describes no separate wizard. In-app permission screen: NOT SEEN.

### Accessibility-permission apps (Rectangle, Moom, Magnet, Ice, Raycast, others)

- **Rectangle, SEEN in source** ([AccessibilityView.swift](https://github.com/rxhanson/Rectangle/blob/c7d9ed2f5c/Rectangle/AccessibilityAuthorization/AccessibilityView.swift), [AccessibilityAuthorization.swift](https://github.com/rxhanson/Rectangle/blob/c7d9ed2f5c/Rectangle/AccessibilityAuthorization/AccessibilityAuthorization.swift)): one 320 by 380 window with an icon, one sentence, a text path hint, and an "Open System Settings" button. A timer checks every 0.3 seconds and the window closes itself on grant, then the Welcome window appears. Closing the window quits the app. No illustration of the pane. The rendered window is NOT SEEN.
- **Ice, SEEN in source** ([PermissionsView.swift](https://github.com/jordanbaird/Ice/blob/11edd39115/Ice/Permissions/PermissionsView.swift)): one fixed window of cards, one per permission, with a "Grant Permission" button that becomes a green "Permission Granted" label. It re-checks every second and re-activates the app after the user returns. Continue stays disabled until the required permission is granted, and becomes "Continue in Limited Mode" for an optional miss. No pane illustration. Rendered window NOT SEEN.
- **AltTab, SEEN in source** ([PermissionsWindow.swift](https://github.com/lwouis/alt-tab-macos/blob/eb63ac1520/src/secondary-windows/permission-window/PermissionsWindow.swift), [PermissionFlowSpecs.md](https://github.com/lwouis/alt-tab-macos/blob/eb63ac1520/src/secondary-windows/permission-window/PermissionFlowSpecs.md)): the strongest flow found. One 470-point-wide window of numbered step cards, one live at a time. The live card has one justification sentence and an illustration drawn in code, so it follows the accent color and appearance. Done cards collapse to "Allowed". The window has no close button, because closing used to quit the app silently. Detection uses a Darwin notification plus a direct permission read, with retries, and the window closes itself when complete. The code notes that the first system signal can arrive before the permission is written, so reading immediately can return the old value. Rendered window NOT SEEN.
- **Loop, SEEN in source** ([AccessibilityManager.swift](https://github.com/MrKai77/Loop/blob/573ace3071/Loop/Utilities/AccessibilityManager.swift)): a modal alert with one "Open System Settings" button. It resets its own permission entry before asking, which is risky and should not be copied on a live product.
- **Raycast, TEXT:** the [manual](https://manual.raycast.com/llms-full.txt) says permissions are requested the first time a command needs them, and [Screen Awareness setup](https://manual.raycast.com/ai/screen-awareness.md) grants permissions from a setup view and resumes after the app restarts. First-run screens and the System Settings preview: NOT SEEN.
- **Moom, TEXT plus static images:** [setup page](https://manytricks.com/moom/help/setup.html) uses cropped screenshots with a blue outline around the row. In-app first-run dialog and detection: NOT SEEN.
- **Magnet and Rectangle Pro:** only a Magnet FAQ remove-and-re-add recipe was found ([FAQ](https://magnet.crowdcafe.com/faq.html)). The Rectangle Pro docs have no permission content. In-app flows: NOT SEEN.
- **Alfred, BetterTouchTool, Screen Studio:** official help pages use static screenshots ([Alfred](https://www.alfredapp.com/help/getting-started/permissions/), [BTT](https://docs.folivora.ai/docs/1_installation.html), [Screen Studio](https://screen.studio/guide/setting-up-permissions)). Live detection and animation: NOT SEEN.
- **Rename on macOS 27:** Raycast and BetterTouchTool docs say Accessibility was renamed "Device Control and Data Access" on macOS 27 ([Raycast](https://manual.raycast.com/troubleshooting.md), [BTT](https://docs.folivora.ai/docs/1_installation.html)). Apple's own macOS 27 guide page still says Accessibility. This does not affect Ping Warden, but it shows how often pane names move.

### Apple guidance (SEEN)

- **Onboarding** ([HIG](https://developer.apple.com/design/human-interface-guidelines/onboarding)): keep any prerequisite flow brief, make it optional, do not repeat it after it is skipped but keep it findable, teach the app and not the system, and request private-data access in onboarding only when the app cannot work without it, explaining the benefit.
- **Requesting permission** ([HIG Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)): ask only for what is needed and as late as possible. For a custom screen before a system alert, show one button that clearly opens the alert, avoid "Allow", and do not offer a way to leave without seeing the alert. Those pre-alert rules name camera, microphone, location and similar, not Login Items, so applying them here is my inference. They conflict with the onboarding page's "optional", so the proposal keeps Back and Cancel.
- **Offering help** ([HIG](https://developer.apple.com/design/human-interface-guidelines/offering-help)): tie help to the task, make it easy to dismiss, prefer graphics over long text for unusual controls.
- **Launching** ([HIG](https://developer.apple.com/design/human-interface-guidelines/launching)): restore previous state so people can continue where they left off. This supports resuming Finish Setup at the first incomplete step.
- **SMAppService** ([docs](https://developer.apple.com/documentation/servicemanagement/smappservice)): `status` values are notRegistered, enabled, requiresApproval and notFound ([status](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.property)). `openSystemSettingsLoginItems()` opens the Login Items pane ([docs](https://developer.apple.com/documentation/servicemanagement/smappservice/opensystemsettingsloginitems())). The article [Updating helper executables from earlier versions of macOS](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos) tells apps to explain what the helper is for, check status at launch, and call `openSystemSettingsLoginItems()`. [WWDC22 What's new in privacy](https://developer.apple.com/videos/play/wwdc2022/10096/) says users are notified and that clicking the notification opens the Login Items pane.

### Comparison table

| Product | Steps | Preview of System Settings | Live detection | Button wording | Text | Failure or retry | Window |
|---|---|---|---|---|---|---|---|
| Audio Hijack, Loopback (ARK) | One window of cards | None for ARK | Yes, card turns green | Enable, Continue | Low | Reopen from app menu | about 760 by 685 |
| Rogue Amoeba Enable Background Item | One modal | Cropped real screenshot, glow, arrow | NOT SEEN | Open System Settings link, Continue | Low | Re-prompts at launch | about 620 by 486 |
| Little Snitch 6 | Welcome, license, 2 prompts, Settings | Real screenshot, orange outline | NOT SEEN | Install | Low | Re-offer window | about 900 by 420 |
| Little Snitch Mini | Same | Grey skeleton, numbered callouts | NOT SEEN | Start using | Low | Same | NOT SEEN |
| LuLu | Welcome, 4 macOS steps | None in app | NOT SEEN | Next | Low | In-app error | about 700 by 378 |
| Tailscale | One alert | None | Yes (advances on connect) | Open Settings, Ignore | Medium | Menu bar item | alert |
| Rectangle | One window | None, text path | Yes, 0.3 s timer | Open System Settings | Very low | Menu item reopens | 320 by 380 |
| Ice | One window of cards | None | Yes, 1 s timer | Grant Permission, Continue | Medium | None | content sized |
| AltTab | One window, step cards | Code-drawn illustration of the effect | Yes, notification plus read | Grant permission | Low | Skipped step can be undone | 470 wide |
| Docker Desktop | None now | None | Not applicable | Not applicable | Not applicable | Opt-in later | Not applicable |

## Part 2: Recommended design for Ping Warden

### Principles taken from the evidence

1. One window, one primary button per screen, content that fits without scrolling at the default size (Rogue Amoeba, Rectangle, AltTab).
2. Show the System Settings step as a drawn illustration with the target highlighted, not a screenshot (Rogue Amoeba's glow and arrow, Little Snitch Mini's skeleton, AltTab's code-drawn art). A drawn version follows light and dark appearance, scales with Dynamic Type, can be versioned in code per macOS release, and never goes stale as a bitmap.
3. Detect the change and advance on its own, then bring the window forward (Rectangle, Ice, AltTab).
4. Always leave a recovery path (Tailscale's menu item, Rogue Amoeba's re-prompt, Little Snitch's re-offer).
5. Name the exact pane and section for the running macOS version.
6. Ask for the approval as late as possible and only when it can be used (Docker, iStat Menus, HIG).
7. Skip the floating guide window. No shipping app does it, it adds window-management complexity (Spaces, Stage Manager, full screen), and the app already opens System Settings itself and keeps its own window visible.

### Screens and states

First run (the license step appears only when `canEnableProtection` is false):

1. **Welcome.** Icon, title, one sentence, one reassurance line, Continue, Not Now.
2. **What Ping Protection does.** A short illustration comparing ping with AWDL active and with protection on, two sentences, Back, Continue.
3. **License** (conditional). Key field, Activate, Buy, a one-line price, a donor note, Skip for Now.
4. **Approve the helper.** The reusable step. Three preview cards, a breadcrumb line, a live status line, one trust line, Back, Approve Helper.
5. **Done.** Check mark, state-aware title and sentence, a drawn menu bar hint, Open Dashboard.

Approve step phases (all driven by live state):

| Phase | Trigger | Cards | Status line | Buttons |
|---|---|---|---|---|
| Ready | status notRegistered | all neutral | "Ready when you are. Nothing changes until you click Approve Helper." | Back, Approve Helper |
| Earlier request waiting | status requiresApproval on entry | card 1 done, card 2 active | "An earlier request is waiting. It only needs the switch turned on." | Back, Open System Settings |
| Waiting | register() sent, status requiresApproval | card 1 done, card 2 active (toggle hint loops) | "Waiting for your approval" plus a sub-line | Cancel, Open System Settings |
| Handoff | 10 s elapsed, still pending | unchanged | sub-line becomes "Opened System Settings for you. Turn on Ping Warden, then confirm." | unchanged |
| Late | 45 s elapsed | unchanged | sub-line adds "Still waiting. This stops in a few seconds." | unchanged |
| Approved | status enabled | all done | "Approved" then "Checking that the helper answers…" | disabled |
| Timed out | 60 s elapsed | unchanged | "Approval did not arrive" plus what to do | Open System Settings, Try Again |
| Failed | register() error | unchanged | existing failure copy | Try Again |

Two behaviors worth keeping from the mockup:

- **A late approval still advances.** After the 60 second timeout the screen keeps reading `status` while it is visible, so a user who flips the switch at 70 seconds is not stranded. This is cheap (the monitor already reads status) and consistent with Ice and AltTab.
- **Entry shortcuts.** If status is already enabled when the user reaches the step, the step skips straight to Done. Finish Setup from the menu resumes at the first incomplete step (License if needed, otherwise Approve), not at the Welcome screen.

### Repair

Repair is not a wizard. It is a check that escalates to the same Approve step only when needed.

1. User chooses Repair in Settings or the menu bar. The existing confirmation appears (shortened).
2. The window shows "Checking the helper…" while the app confirms the helper answers.
3. **Helper answers:** the window closes and a notification-style confirmation says "Helper Is Responding" with the protection state. Nothing else.
4. **Helper needs approval again:** the Approve step opens with a Repair badge and the line "macOS needs your approval again. Your settings and history stay as they are." Back becomes Cancel and the dots are hidden. The user presses Approve Helper, so any macOS notification follows an explanation.
5. **Still fails after approval:** one calm failure screen using the existing `RepairResultCopy` text.

Implementation consequence: `repairHelperRegistration` currently checks, unregisters and registers in one go. The flow above needs a probe that stops after "does the helper answer", and a separate re-register that runs when the user presses Approve Helper. Without that split, macOS would announce the helper before the app has explained anything.

### License step placement

Recommended: after "What Ping Protection does" and before "Approve the helper", shown only when `canEnableProtection` is false.

- Approving a helper the user cannot yet use adds a system prompt for no benefit, which the HIG and Docker's change both argue against.
- By screen 3 the user has seen what protection does, which is the best moment to ask for $15.
- Skip for Now ends the flow on a "set up for the free dashboard" screen. Finish Setup in the menu and in Settings resumes at the approval step after a license is added.
- Licensed users and users inside the 90-day transition never see the step, so their flow is four screens.

Alternative (not recommended): License after Done. It lets everyone approve first, but unlicensed users hit a screen saying protection is off right after granting a system permission, which feels like a bait and switch.

### Copy

Plain, no em dashes. Ping Warden's helper only toggles `awdl0`, accepts requests only from Ping Warden, never reads traffic, and never connects to the internet (README line 86).

| Where | Copy |
|---|---|
| Welcome title | Welcome to Ping Warden |
| Welcome line | Keep your Wi‑Fi steady while you cloud game on a Mac. |
| Welcome reassurance | Setup takes about a minute and needs one approval from macOS. |
| How, body | AirDrop and AirPlay use a wireless interface called AWDL. When it wakes up, your Wi‑Fi can stutter. Ping Protection keeps it paused while you play. |
| How, caption | Illustration. Other causes of lag can still affect your connection. Pause protection any time to use AirDrop, AirPlay, and Handoff. |
| License title and body | Add your license. Ping Protection is a one-time $15 purchase. The latency dashboard stays free. |
| Approve title | Approve the helper (Repair: Approve the helper again) |
| Approve subtitle | Ping Warden needs your approval once. Here is what macOS will show. |
| Card captions | macOS announces the helper. Turn on Ping Warden. Confirm with Touch ID or password. |
| Breadcrumb | System Settings › General › Login Items & Extensions › App Background Activity (per macOS version) |
| Trust line | The helper only switches awdl0 off and on. It never reads your traffic or connects to the internet. More about the helper |
| Helper popover | Lowers awdl0 while Ping Protection is on, and raises it again when you pause or quit. Accepts requests only from Ping Warden. Never reads your traffic. Never connects to the internet. |
| Primary buttons | Continue. Approve Helper. Open System Settings. Try Again. Open Dashboard. |
| Done (licensed) | Ping Protection is on. Ping Warden lives in your menu bar. Click its icon to pause protection or open the dashboard. |
| Done (no license) | Helper is ready. Ping Protection turns on once you add a license. Until then, the dashboard shows your latency for free. |
| Repair confirm | Repair Helper Connection? Ping Warden will check that the helper answers. If it does not, you may need to approve it again in System Settings. Your protection preference, settings, and session history stay as they are. |
| Repair quiet finish | Helper Is Responding. Ping Protection is on. |

Button wording follows the HIG pre-alert advice to avoid "Allow", which macOS uses on its own prompts. "Approve Helper" names the thing being approved and does not imitate a system button.

### Visual assets per step

| Step | Asset | How to build it |
|---|---|---|
| Welcome | App icon, 92 points | Existing `applicationIconImage` |
| How | Latency comparison chart | SwiftUI `Canvas` or Swift Charts, labeled as an illustration, red spikes versus a steady green line, one scale for both |
| Approve card 1 | Miniature notification banner with the app icon and the words "Background Items Added" | SwiftUI shapes, hidden from VoiceOver |
| Approve card 2 | Miniature of the switch section with Ping Warden's row, toggle hint looping off to on while active | SwiftUI, version-aware header |
| Approve card 3 | Miniature authentication sheet with a fingerprint glyph | SwiftUI plus `touchid` SF Symbol |
| Done | Check mark that draws itself, a drawn menu bar strip with the Ping Warden icon highlighted | SwiftUI, respects Reduce Motion |

Version handling: a small `SystemSettingsCopy.Variant` (macOS 13 and 14, macOS 15, macOS 26 and later) feeds the breadcrumb, card 2 header, the timeout text and the Repair failure text. Draw the illustrations rather than shipping screenshots, so each variant is a string change. The mockup's System Settings window is a stylized stand-in. Replace it with captures from the 92test fixture on 13, 14, 15, 26 and 27 before finalizing any real screenshot reference. The row subtitle ("Oliver Ames") and the banner text in the mockup are unverified.

### Live states the app already exposes

| Source | Values | Use |
|---|---|---|
| `SMAppService.status` via `refreshHelperStatus()` | notRegistered, requiresApproval, enabled, notFound | Card states, phase, auto-advance |
| `isHelperRegistered` | Bool | Entry shortcut (skip approval), Repair path choice |
| Helper reply via `helperResponseHandler` and validation | Bool, "answers" | Approved confirmation, Repair probe, `helperSilent` |
| `isRepairingHelper`, `isHelperSetupInProgress`, `canRepairHelper` | Bool | Disable duplicate starts |
| `LicenseManager.canEnableProtection`, `hasValidPaidLicense`, `isGrandfathered` | Bool | License step visibility, Done copy |
| `isMonitoringActive` | Bool | Done title |

### Behavior constraints kept

- Login Items opens automatically 10 seconds after a fresh registration if approval is still pending. The mockup now says so in the UI ("Opened System Settings for you") so the window opening is explained rather than surprising. An earlier pending request opens Login Items at once, as `registerHelper()` does today.
- Registration polling times out at 60 seconds, once a second. The mockup adds a quiet hint at 45 seconds and a Try Again screen at 60 seconds, plus the passive late-approval watch.
- Launch never opens Login Items on its own. A saved intent to protect waits for Finish Setup.
- Closing the window is Not Now. Nothing is lost, and the welcome does not repeat (4.0.4 behavior).

### Window size and density

- Mockup uses a fixed 540 by 600 frame. The current Welcome is 540 by 680 with a 480 by 560 minimum. Keep the existing ScrollView for accessibility Dynamic Type sizes.
- Each screen holds one headline, at most two sentences, one visual, and one primary button. The mockup's densest screen is Approve, with three small cards and two short lines of text.
- The crash-report caption stays on the Welcome screen at caption size. It could move to the Done screen if Oliver prefers a shorter Welcome.

### Liquid Glass

Behind `@available(macOS 26, *)`: glass-prominent buttons and glass-backed cards. Earlier versions keep `.borderedProminent` and material backgrounds. The mockup uses translucent materials and a large window radius only, to stay restrained.

## Open decisions for Oliver

1. **License placement.** Recommended: before approval, conditional. Alternative: after Done. The mockup implements the recommendation and lets you switch license state in the panel.
2. **Section name text.** The issue says "Allow in the Background". On macOS 26 and later Apple names the section "App Background Activity". Confirm this on a macOS 26 machine and on the isolated fixture before copy is final.
3. **Crash-report caption.** Keep on Welcome (current) or move to Done.
4. **Repair split.** Approve the idea of probing first and re-registering only when the user presses Approve Helper. It changes `repairHelperRegistration`.
5. **Floating guide window.** Recommended: no. It can be revisited after the first implementation if testing shows people lose the app window.

## What I could not see

- Rendered onboarding windows for Bartender, CleanShot X, iStat Menus, 1Password, Raycast, Magnet, Rectangle Pro, and the macOS 11 and later first-run dialog of Moom.
- Whether Rogue Amoeba's Enable Background Item window advances on detection.
- Any live preview, animated hint, or floating helper window in a shipping Mac app.
- The exact English text of the "Background Items Added" notification from an Apple source.
- Any macOS 26 System Settings capture. The macOS 26 section name rests on Apple's guide.
- Ping Warden's real row in System Settings on any macOS version.

## Verification of the mockup

Loaded in a browser and exercised: Welcome, How (chart toggle and auto-switch), License (activate and skip), Approve (ready, waiting with the 10 second handoff, authentication sheet, approved, timed out, late approval), Done, free-dashboard end screen, menu bar entry for Finish Setup and Repair, and all three Repair outcomes. Checked for horizontal overflow at 390 points wide, and the console was clean. The mockup is a fragment written for the Artifact publisher (no doctype or head), so opened directly as a local file it renders in quirks mode. Wrapped in a standard HTML shell it behaved as described above.
