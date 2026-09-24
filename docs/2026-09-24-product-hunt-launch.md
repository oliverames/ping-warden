# Ping Warden Product Hunt launch

Prepared for Oliver Ames on September 24, 2026.

## Status and task list

- [x] Inspect repository state and coordinate with the active issue-review task.
- [x] Verify the public landing page and latest release.
- [x] Read current Product Hunt submission and community guidance.
- [ ] Verify Product Hunt account access and check for an existing listing or draft.
- [x] Prepare accurate listing fields, maker comment, and gallery assets.
- [x] Bring the app's Targets tab into line with the other grouped settings forms and verify native previews. Broader click and keyboard acceptance remains in #90.
- [ ] Verify the submission preview and launch timing.
- [ ] Submit and verify the resulting Product Hunt state.

## Publication hold and resume point

Oliver subsequently requested wrap-up and a Claude handoff before releasing to existing users or Product Hunt. Publication is now on hold and tracked in [#93](https://github.com/oliverames/ping-warden/issues/93). Do not create or schedule the Product Hunt submission during this closeout. Resume only after Claude reviews release readiness and Oliver resumes publication.

## Work scope

This task owns this launch document, launch assets, and its WORKLOG entry. Oliver subsequently requested a native Targets layout correction. The separate issue-review task explicitly released Targets layout ownership to this task after committing its functional changes in a344c0c. Keep those changes intact. The app's Targets tab remains available, with its appearance brought into line with the other settings forms. No storefront behavior changes are part of this task.

The in-app browser loaded Product Hunt but showed Sign in. Chrome's navigation timed out. A recovery attempt returned `Browser is not available: chrome`. The working in-app browser is open at Product Hunt's sign-in dialog. Oliver was asked to sign in to his personal account and choose launch timing. No Product Hunt draft or submission has been created.

The launch date is unset. Choose a future day after release readiness is established when Oliver can respond to comments. Use the scheduler's midnight Pacific start for a full day. The earlier September 25 suggestion was never selected and must not be treated as scheduled.

Public web search found no indexed result for `Ping Warden`, `Ping-Warden`, `AWDL Control`, or `pingwarden.app` on producthunt.com. This does not establish that no listing or draft exists. Check the authenticated submission flow before creating anything.

After the publication hold is resolved and sign-in is available: verify the personal profile and maker identity, inspect existing products/drafts, enter the fields below, upload the ordered gallery, review the preview, select the agreed date, submit, and record the resulting URL and status here. Oliver's later instruction defers publication until after the Claude handoff and review. Preserve that hold.

## Verified product facts

The public landing page on September 24 states that Ping Warden targets AWDL-related Wi-Fi stutter for Mac cloud gaming. Dashboard, latency history, diagnostics, and updates are free. Ping Protection costs $15 USD once. It temporarily makes AirDrop, AirPlay, Handoff, and other AWDL-dependent features unavailable. The app requires macOS 13 or later and supports Intel and Apple silicon. Source remains MIT.

GitHub's live release API identifies v4.2.0, published September 21, 2026 at 17:09:08 UTC, as the latest release. Its DMG is 5,845,407 bytes. Source fixes and isolated review screenshots must not be presented as a newer published release.

The live Gumroad listing also showed $15, the purchase button, signed/notarized download, one key for the Macs the buyer owns, all future updates, and no subscription. Checkout was not completed and license delivery was not retested.

Sources: [Public website](https://pingwarden.app/), [Gumroad listing](https://amesconsulting.gumroad.com/l/pingwarden), [release 4.2.0](https://github.com/oliverames/ping-warden/releases/tag/v4.2.0), and the current repository README.

## Submission fields

| Field | Prepared value |
| --- | --- |
| Name | Ping Warden |
| Product URL | https://pingwarden.app/ |
| Tagline | Reduce Wi-Fi lag while cloud gaming on your Mac |
| Pricing | Paid with a free plan, using the equivalent label in the form |
| Launch tags | Mac, Gaming, Open Source, subject to the current picker |
| Maker | Oliver Ames, exact personal username to verify after sign-in |
| Optional source link | https://github.com/oliverames/ping-warden |
| Optional download link | https://github.com/oliverames/ping-warden/releases/latest |
| Promo code | None. Existing $15 pricing remains in effect. |
| Video | Omit. No finished public video is available in this launch kit. |

The tagline is 47 characters. The description below is 419 characters. The pricing selection reflects the permanently free dashboard. Do not describe the 90-day existing-user transition as a trial for new users.

### Description

Ping Warden helps reduce AWDL-related Wi-Fi stutter in GeForce NOW, Xbox Cloud Gaming, Moonlight and Parsec. It pauses Apple's nearby-device networking while you play and graphs your latency. AirDrop, AirPlay and Handoff pause while protection is on. Free dashboard, latency history and diagnostics. Ping Protection is $15 once, with no subscription. Native macOS app for Intel and Apple silicon. Open source under MIT.

### First maker comment

Hi Product Hunt, I'm Oliver, the maker of Ping Warden. It already has paying customers, and I'm bringing it here to reach more Mac cloud gamers.

Apple Wireless Direct Link (AWDL) powers AirDrop, AirPlay and Handoff. Its background activity can interrupt latency-sensitive Wi-Fi traffic. Turning it off once does not keep it off because macOS can bring it back.

Ping Warden keeps AWDL paused while Ping Protection is on, helping reduce Wi-Fi stutter in GeForce NOW, Xbox Cloud Gaming, Moonlight and Parsec. The dashboard shows latency, jitter and history, with automatic protection available for gaming sessions.

AirDrop, AirPlay and Handoff pause while protection is on. Turn protection off or use the 10-minute pause when you need them.

The dashboard, latency history, diagnostics and updates are free. Ping Protection is $15 once, with no subscription. One key covers the Macs you own and all future updates. The signed, notarized app runs on Intel and Apple silicon with macOS 13 or later. The source remains MIT.

Which cloud gaming service do you use on your Mac, and what would make Ping Warden more useful for your setup?

Editorial note for Oliver: the closing feedback question and the launch framing are proposed here. Product behavior and pricing come from the current public documentation. Oliver confirmed on September 24 that the app already has substantial sales. The paying-customer statement comes from him. No sales count, personal origin story, or performance benchmark has been invented.

## Gallery and thumbnail

1. [Real dashboard screenshot](../Site/public/dashboard-v4.png). The unmodified screenshot used on the live landing page, verified September 24. Lead with the actual app. Suggested caption: "The Ping Warden dashboard, as shown on the landing page. Intervention counts record attempts to pause AWDL."
2. [Cloud gaming introduction](product-hunt-2026-09-24/01-cloud-gaming.png). Generated illustration and verified product copy. No simulated app interface or benchmark.
3. [Sharing tradeoff](product-hunt-2026-09-24/03-sharing-tradeoff.png). Generated explanatory graphic with accurate protection and pause behavior.
4. [Automation screenshot](images/ping-warden-4-automation.png). Existing, unmodified product screenshot showing the Game Mode option and optional fullscreen-detection permission.

Use the existing [app icon](../Site/public/app-icon.png) as the thumbnail. It is square at 256 × 256, close to Product Hunt's 240 × 240 recommendation. All selected images are PNG files below 3 MB. The generated cards preserve the recommended gallery proportions. Original app screenshots retain their native dimensions and need preview checks for legibility.

Oliver selected the actual landing-page dashboard screenshot and asked to omit Targets because its design feels separate from the app. The dashboard contains older intervention-counter wording. Keep the image authentic and clarify the counter in its gallery caption. The September 21 isolated review captures show unshipped source changes and remain excluded. This launch introduces an established paid app to Product Hunt. Verifying the launch fields and changed layout does not require revalidating the product or its sales.

The Targets design observation is part of the existing #90 native-design review. Oliver clarified that the app's tab must remain, and explicitly requested a consistent native layout. This task owns that follow-up. Its isolated verification and release status must be recorded separately from the Product Hunt submission.

The [machine-readable fields](product-hunt-2026-09-24/listing.json) mirror this copy. The [image prompt record](product-hunt-2026-09-24/image-prompts.md) records the built-in image-generation prompts. Generated artwork supplements actual screenshots and is not presented as product UI.

## Launch-day priorities

Before the scheduled start, confirm the maker profile, URLs, thumbnail, image order, price, first comment, and date in the Product Hunt preview. Check whether the account has completed required onboarding. Product Hunt's older launch guide mentions a one-week wait, while its posting help emphasizes onboarding, so use the account's current eligibility message. [Posting help](https://help.producthunt.com/en/articles/479557-how-to-post-a-product)

On launch day, respond to substantive comments promptly and ask about the person's Mac, streaming service, and symptoms when relevant. Judge the launch by useful feedback, qualified visits, downloads, and purchases visible in existing tools. Do not add tracking systems for this submission.

Promotion outside Product Hunt requires a separate request naming the channel. If Oliver chooses to share the launch, use communities where he already participates and follow their self-promotion rules. No external outreach was sent. [Sharing guidance](https://www.producthunt.com/launch/sharing-your-launch)

## Product Hunt guidance

Use the direct product URL without tracking parameters, a plain product name, a tagline under 60 characters, and a description under 500 characters. Choose up to three relevant launch tags. Use a square thumbnail, ideally 240 × 240 and under 3 MB, and at least two gallery images, ideally 1270 × 760. A first maker comment should explain the use case and invite feedback. Video is optional. Product Hunt permits scheduling up to one month ahead and does not identify a universally best launch day. [Preparing for launch](https://www.producthunt.com/launch/preparing-for-launch)

Use Oliver's personal maker profile. Ask for feedback rather than votes. Do not buy votes, incentivize votes, or mass-message members. [Community guidelines](https://help.producthunt.com/en/articles/3615694-community-guidelines)

Product Hunt's daily cycle resets at midnight Pacific time. Check the scheduler's displayed time before committing a date. [Getting started](https://help.producthunt.com/en/articles/2305333-getting-started)
