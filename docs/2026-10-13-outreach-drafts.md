# Ping Warden outreach drafts, October 13, 2026

Prepared for Oliver Ames. Nothing here has been sent, posted, submitted, or registered. Contact routes and rules were checked against live pages on 2026-10-13 where the page could be read. Anything I could not read is marked UNVERIFIED.

## Read first

**Do not send or post anything until these gates are clear.**

1. **The proof image is not live.** `https://pingwarden.app/before-after.png` and the `.webp` variants return 404 today. The file exists at `Site/public/before-after.png` on `release-4.3.3`, `messaging-4.3.3`, and `site-backlog-4.3.3`, but not on `origin/main`. PR #123 (4.3.3) is open. Every draft below links the image, so send only after it resolves.
2. **4.3.3 is not released yet.** GitHub's latest release is v4.3.2 (2026-10-09), and the Homebrew cask in `oliverames/homebrew-tap` is still at version 4.3.2. The drafts say "4.3.3 is out today," so send only after the release and the cask bump (`scripts/bump_homebrew_tap.sh` is untracked in this worktree) are done. If you send first, swap in "4.3.2."
3. **Create the free licenses before you send.** Each press, YouTube, and review offer promises a free license. Generate one per recipient in Gumroad (or a 100% offer code) so you can reply the same day. Do not put a license key in a first email to 9to5Mac, because its tips page treats a submission as permission to publish and syndicate.
4. **Reddit text could not be read directly.** Reddit is blocked from the built-in browser and Chrome tools here, and Firecrawl cannot fetch it. I read the October App Pile thread and the r/MacOS rules post through TinyFish. I could not read the r/GeForceNOW or current r/MacOS rules pages. Confirm both rule texts in your own browser before sending the modmails.

**Show HN and r/BoosteroidCommunity ban AI-written text, so you need to write those yourself.** Facts and angle only, no prose, below.

### Show HN outline (you write it)

- Angle: a technical write-up of one narrow Mac problem, not a product announcement. Lead with what AWDL is and why it can cause periodic Wi-Fi latency spikes.
- Facts to include:
  - Ping Warden is a macOS menu bar app. Source is MIT at github.com/oliverames/ping-warden.
  - First commit 2025-10-26. It was called AWDL Control before the rename. It credits James Howard's AWDLControl and jamestut's awdlkiller.
  - A privileged helper reacts to awdl0 coming back up and takes it down again, rather than polling on a timer. Say how you measured it, or say you haven't.
  - The dashboard graphs latency and jitter. Same Mac and network: off, spikes to 168 ms and 18.4 ms jitter; on, worst 83 ms and 6.1 ms jitter. Results vary.
  - The intervention counter increments before the helper attempts to lower AWDL. It counts attempts, not spikes prevented (PingWardenMonitor.m, around lines 297-303).
  - Honest limits: AWDL is one possible contributor, Ethernet users don't need it, and AirDrop, AirPlay, and Handoff are unavailable while protection is on.
  - Money: free dashboard, $15 one-time license for Ping Protection, 46 sales since Sept 3. Say so plainly.
  - macOS 13+, Intel and Apple silicon, Developer ID notarized, Sparkle updates.
- What to ask the readers: results on different routers and Wi-Fi generations, and whether anyone sees a safer way to bring awdl0 down than the helper approach.
- Show HN conditions to check yourself: readers must be able to try it without signing up (the free dashboard and the open source cover that), and no asking for upvotes.

### r/BoosteroidCommunity outline (you write it)

- Rules (from the 2026-09-14 audit, wording not re-read today): AI-assisted posts and comments are prohibited, and advertising needs approval. Send the mods a short human-written modmail first, as with r/GeForceNOW.
- Angle: Mac users streaming Boosteroid over Wi-Fi who see periodic spikes.
- Facts to include:
  - What AWDL is, and that this only addresses AWDL-related Wi-Fi interference.
  - Game Mode recognizes a frontmost game app, so for browser streaming the user turns protection on manually before playing.
  - Free dashboard, $15 one-time for Ping Protection, MIT source, and the before and after numbers above.
  - AirDrop, AirPlay, and Handoff are off while protection is on.
- Ask: whether anyone on Boosteroid sees the same pattern, and what their graph looks like on and off.

---

## Contact route verification

| Outlet | Route | Status |
| --- | --- | --- |
| 9to5Mac | tips@9to5mac.com (page shows "tips [at] 9to5mac.com", mailto is tips+contact@9to5mac.com) | Verified on https://9to5mac.com/contact/. No pitch policy published. |
| The Sweet Setup | desk@blancmedia.org | Verified indirectly. The page hides it behind Cloudflare email protection, and the fetch tool decoded it. Page says nothing on pitches. Homepage featured items date from 2024, so confirm the site is still publishing. |
| Mac Gamer HQ | Contact form at https://www.macgamerhq.com/contact/ (goes to the founder's personal email) | Verified. No email address and no pitch policy. Newest posts I could see on the homepage look like 2025. |
| MacStories | viticci@macstories.net (Federico Viticci) or voorhees@macstories.net (John Voorhees) | Verified on https://www.macstories.net/about/ (obfuscated, decoded). No tips or press address is listed. |
| ifun.de | ifun.de@gmail.com | Verified on https://www.ifun.de/impressum/ ("questions and tips"). Company contact info@aketo.de is for the publisher, not editorial. Site is actively publishing. |
| Andrew Tsai (YouTube) | andrewtsai@intheblackmedia.com | Verified in the channel description at https://www.youtube.com/@Andytizer/about ("Business enquiries please contact"). |
| AlternativeTo | Submission form | UNVERIFIED. It sits behind a sign-in, so field names and category labels below are my best match. |
| r/macapps | October App Pile thread | Verified: https://www.reddit.com/r/macapps/comments/1wuoav5/megathread_the_app_pile_october_2026/ |
| r/MacOS | Modmail | UNVERIFIED current rules (see below). |
| r/GeForceNOW | Modmail | UNVERIFIED rule wording. |

Send from oliver@ames.consulting, which is your support identity for Ping Warden.

---

## 1. Press pitches

Common conditions: offer the license with no expectation of coverage, keep it to one email each, and do not follow up more than once. Don't bring up price in the subject line.

### 1a. 9to5Mac

**Destination:** tips@9to5mac.com

**Rule to respect:** The contact page has no pitch guidelines. It says "Submitting a tip constitutes permission to publish and syndicate," so include nothing private and no license key in this email. Offer the license and send it on request.

**Subject:** Ping Warden, a Mac menu bar app for Wi-Fi lag spikes in cloud gaming

Hi 9to5Mac team,

I'm Oliver Ames, and I make Ping Warden, a Mac menu bar app that measures your Wi-Fi latency and pauses AWDL, the interface behind AirDrop, AirPlay, and Handoff, while you stream games. On some Macs AWDL's background channel hopping shows up as periodic lag spikes in GeForce NOW and Xbox Cloud Gaming, and that's the specific problem it targets.

Here's one before and after on the same Mac and network: https://pingwarden.app/before-after.png. With it off, the graph spiked to 168 ms with 18.4 ms of jitter. With it on, the worst reading was 83 ms with 6.1 ms of jitter. Your results will vary, and it does nothing for lag that comes from your ISP or the game server. AirDrop and AirPlay are unavailable while it's on.

The dashboard is free, and Ping Protection is a one-time $15 license. The source is MIT at https://github.com/oliverames/ping-warden, it needs macOS 13 or later, and it runs on Intel and Apple silicon. Builds are Developer ID notarized, and 4.3.3 is out today with fixes for Game Mode and Repair edge cases and clearer setup guidance. You can try it at https://pingwarden.app or with `brew install --cask oliverames/tap/ping-warden`.

If you'd like to test it for a story or a roundup, I'm happy to send a free license. Coverage is entirely up to you.

Best,
Oliver

### 1b. The Sweet Setup

**Destination:** desk@blancmedia.org

**Rule to respect:** No pitch policy is published. Fit is weak, since the site leans toward productivity apps and its homepage looks stale. Treat this as optional, and skip it if the site no longer posts new reviews.

**Subject:** Ping Warden, a small Mac utility for Wi-Fi lag in game streaming

Hi Sweet Setup team,

I'm Oliver Ames, and I make Ping Warden, a Mac menu bar app that measures Wi-Fi latency and pauses AWDL (the interface behind AirDrop, AirPlay, and Handoff) while you stream games. On some Macs AWDL shows up as periodic lag spikes in GeForce NOW and Xbox Cloud Gaming.

It's a narrow tool, so I'll be upfront that it doesn't fix every kind of lag. On the same Mac and network, the worst reading went from 168 ms to 83 ms and jitter from 18.4 ms to 6.1 ms (https://pingwarden.app/before-after.png). Results vary, and AirDrop and AirPlay stay off while protection is on.

The dashboard is free, Ping Protection is a one-time $15 license, and the source is MIT on GitHub. It needs macOS 13 or later and runs on Intel and Apple silicon. Everything is at https://pingwarden.app, and 4.3.3 is out today.

If you'd like to try it, I'll send a free license. There's no expectation of coverage.

Best,
Oliver

### 1c. Mac Gamer HQ

**Destination:** Contact form at https://www.macgamerhq.com/contact/ (email address, subject, message). Messages go straight to the founder's personal email, and the page says he replies to all of them.

**Rule to respect:** No pitch policy is published. The form has no attachment field, so link the image. Fit is good on topic, but recent site activity looks low, so keep expectations modest.

**Subject:** Free license: Ping Warden for Wi-Fi lag spikes in cloud gaming on Mac

Hi,

I'm Oliver Ames, and I make Ping Warden, a Mac menu bar app for people who play GeForce NOW or Xbox Cloud Gaming over Wi-Fi. It measures your latency and pauses AWDL, the interface behind AirDrop and AirPlay, because on some Macs AWDL's background channel hopping causes periodic lag spikes.

On my Mac and network, the worst reading went from 168 ms with protection off to 83 ms with it on, and jitter went from 18.4 ms to 6.1 ms: https://pingwarden.app/before-after.png. That's one setup, so your results will vary, and it won't help with lag from your ISP or the game server. AirDrop and AirPlay don't work while it's on.

The dashboard is free and Ping Protection is a one-time $15 license. The source is MIT at https://github.com/oliverames/ping-warden, and the install is also a one-liner with Homebrew: `brew install --cask oliverames/tap/ping-warden`. It needs macOS 13 or later and supports Intel and Apple silicon. Version 4.3.3 is out today.

I'd be glad to send you a free license if you want to test it. Whether you write about it is up to you.

Best,
Oliver

### 1d. MacStories

**Destination:** voorhees@macstories.net (John Voorhees, Managing Editor). My recommendation, which is inference: Federico Viticci's inbox is likely the busier one. Either address is verified.

**Rule to respect:** The About page says MacStories will "only write about apps if we have personally tested them" and has "never done and never will do paid reviews." So the license is only there so they can test it. Don't ask for coverage, don't mention a sponsorship, and do not send a second email.

**Subject:** Ping Warden, a Mac menu bar app for AWDL-related Wi-Fi lag (free license if you want to test)

Hi John,

I know MacStories only writes about apps it has tested, so I'm offering a free license for exactly that, with no expectation of coverage.

I make Ping Warden, a Mac menu bar app that measures Wi-Fi latency and pauses AWDL, the interface behind AirDrop, AirPlay, and Handoff, to reduce lag spikes in cloud gaming. In one same-Mac, same-network comparison the worst reading dropped from 168 ms to 83 ms and jitter from 18.4 ms to 6.1 ms (https://pingwarden.app/before-after.png). Results vary, and it can't fix lag from your ISP or the game server.

The dashboard is free, Ping Protection is a one-time $15 license, and the source is MIT on GitHub. It needs macOS 13 or later, runs on Intel and Apple silicon, and is Developer ID notarized. The free dashboard works without a license if you'd like to look at it first: https://pingwarden.app. Version 4.3.3 is out today.

Best,
Oliver

### 1e. ifun.de

**Destination:** ifun.de@gmail.com

**Rule to respect:** The Impressum offers this address for questions and tips and says the team can't provide technical support for products it covers. The site regularly covers free and freemium Mac apps, so the fit is good. Short English is fine.

**Subject:** Ping Warden: Mac app against AWDL lag spikes (free license on request)

Hi ifun.de team,

I'm Oliver Ames, and I make Ping Warden, a Mac menu bar app that measures Wi-Fi latency and pauses AWDL, the interface behind AirDrop, AirPlay, and Handoff, to reduce lag spikes in GeForce NOW, Xbox Cloud Gaming, and other streaming.

Same Mac and network: with protection off the graph spiked to 168 ms with 18.4 ms of jitter, and with it on the worst reading was 83 ms with 6.1 ms of jitter (https://pingwarden.app/before-after.png). Results vary, and AirDrop and AirPlay are off while it's running.

The dashboard is free, Ping Protection costs $15 once, and the source is MIT on GitHub. It needs macOS 13 or later and runs on Intel and Apple silicon. More at https://pingwarden.app, or `brew install --cask oliverames/tap/ping-warden`. Version 4.3.3 is out today.

If you'd like to test it, I'll send a free license. Thanks for your time.

Best,
Oliver

---

## 2. AlternativeTo listing

**Destination:** https://alternativeto.net (submit a new application; requires sign-in).

**Rules to respect:** The form is behind a sign-in, so I could not read its rules. Treat the field names and category labels as my best match and adjust on screen. I did not find existing AlternativeTo pages for AWDLControl, awdlkiller, AWDL Toggle, or Ping Warden. My slug guesses returned not found, which does not prove they are absent, so search the site before listing. Only mark Ping Warden as an alternative to entries that already exist, and don't create competitor entries to hang it on. No links in the description. English only.

**Name:** Ping Warden

**One-line (tagline):** Menu bar app that measures Wi-Fi latency and pauses AWDL to reduce lag spikes when streaming games on a Mac.

**Description (no links):**

Ping Warden is a macOS menu bar app that measures your Wi-Fi latency and jitter and pauses AWDL, the interface behind AirDrop, AirPlay, and Handoff, to reduce lag spikes while you stream games on a Mac. On some Macs AWDL hops between Wi-Fi channels in the background, which can show up as periodic spikes in GeForce NOW, Xbox Cloud Gaming, and other streaming. While protection is on, Ping Warden watches for the interface coming back up and takes it down again.

It includes a live latency and jitter dashboard with session history, Game Mode that turns protection on when a recognized game is the frontmost app, a ten-minute pause for when you need AirDrop, and a Control Center toggle on macOS 26 or later. AirDrop, AirPlay, and Handoff don't work while protection is on, and it doesn't help with lag caused by your ISP or the game server. Results vary by setup.

The dashboard and diagnostics are free. Ping Protection, the part that pauses AWDL, is a one-time $15 license with no subscription. The source code is MIT-licensed. It requires macOS 13 or later, runs on Intel and Apple silicon, is Developer ID notarized, and updates through Sparkle. Formerly called AWDL Control.

**Category (UNVERIFIED labels):** Network utilities or network monitoring as the primary category, with system utility as a second if the form allows. Check the live category list rather than relying on these names.

**License type:** Commercial with a free version. On AlternativeTo's data model this appears as Freemium (cost) and Proprietary. Because the source is MIT, also tick Open Source if the form lets you choose both. If it forces one choice, pick Freemium as you asked, and the description already states the MIT license.

**Platforms:** Mac, and Homebrew (AlternativeTo lists Homebrew as a platform). Don't tick iPhone, iPad, Windows, or Online.

**Website:** https://pingwarden.app

**Alternative to (only if the entry exists):**

- AWDLControl by James Howard
- awdlkiller by jamestut
- AWDL Toggle by yay

Don't list it as an alternative to AirDrop. It turns AWDL off, so it isn't a replacement.

**Disclosure note:** Submit as the developer and say so in any comment you add. Keep the comparison to facts, like Developer ID notarization, the dashboard, and Game Mode, and say plainly that the three above are free.

---

## 3. r/macapps October App Pile comment

**Destination:** https://www.reddit.com/r/macapps/comments/1wuoav5/megathread_the_app_pile_october_2026/ (top-level comment). Thread posted by u/Mstormer on or about 2026-10-01; 201 comments when I last saw it.

**Rules to respect (read from the thread today):**

- Promotion must follow the PCP format: App Name/Title, Problem, Comparison, Pricing. Non-compliant comments are removed.
- Comparison must explicitly name a competitor or two and say what yours does better. The mod suggests also naming something a competitor does better.
- Pricing must give amounts for every tier plus the app website. No direct .zip or .dmg links.
- A screenshot or video is required for top-3 consideration. The thread doesn't say whether images work in comments, so add the before and after image only if the comment box allows it.
- "The shorter the better."
- This counts toward the 30-day limited promotion limit (Rule 3). Your September App Pile comment is p9s75my in thread 1w4brkd. Check its original posting date. If it was posted fewer than 30 days ago, wait.
- Reddit auto-removes the first link comment 90% of the time if your profile email isn't verified, and the thread advises 10 karma before linking.
- AI-assisted text is more likely to be removed, and the thread names em dashes. These drafts have none. Retype or lightly edit them in your own words before posting.
- A mod said open source on GitHub does not count as "Transparency" for the main feed. It means developer identity and contact details. That's why this draft names you and links the site.

**Text:**

**Ping Warden: menu bar app that pauses AWDL to cut Wi-Fi lag spikes when you stream games on a Mac**

I'm the developer, Oliver Ames.

**Problem:** On some Macs, AWDL (the interface behind AirDrop, AirPlay, and Handoff) hops Wi-Fi channels in the background, which can show up as periodic lag spikes in GeForce NOW, Xbox Cloud Gaming, and other streaming. Ping Warden measures your latency and keeps AWDL down while protection is on. On one Mac and network, the worst reading dropped from 168 ms to 83 ms and jitter from 18.4 ms to 6.1 ms. Results vary, and it can't fix lag from your ISP or the game server. AirDrop and AirPlay are unavailable while protection is on.

**Comparison:** AWDLControl (by James Howard), awdlkiller, and AWDL Toggle are all free and also bring AWDL down, so if you only want it off, one of those may be enough, and I'd rather you not pay for something you don't need. Ping Warden adds a live latency and jitter graph so you can tell whether it's helping, Game Mode that turns protection on for a recognized game, a ten-minute pause for when you need AirDrop, signed and notarized builds with Sparkle updates, and macOS 13 support. AWDL Toggle needs macOS 26.

**Pricing:** The dashboard and diagnostics are free. Ping Protection is a one-time $15 license, no subscription. The source is MIT on GitHub. macOS 13 or later, Intel and Apple silicon. https://pingwarden.app

---

## 4. r/MacOS: Saturday developer post and modmail

**Destination:** Modmail to r/MacOS first, and the post only if the mods say yes. Next Saturdays: October 17 and October 24 (checked: Oct 13, 2026 is a Tuesday).

**What I know about the rules, and what I don't:**

- The r/MacOS mod post "New Rules for App Self Promotion" (https://www.reddit.com/r/MacOS/comments/1ntopuw/new_rules_for_app_self_promotion/, about a year old) says self-promotion is allowed only for apps in the Mac App Store, and that other apps belong in r/macapps. Ping Warden is Developer ID distributed, not in the Mac App Store.
- The 2026-09-14 audit in this repo recorded the sidebar rule as permitting promotion only on Saturdays. I could not read the current rules page today, so I can't reconcile the two. This is the conflict the modmail resolves.
- Your September post (1wg8jwg) shows an explicit moderator-removal notice with no stated reason.
- Honest read, which is inference: a non-App Store app likely belongs in r/macapps, so a "no" is a real possibility. The modmail is written so a no costs nothing.

### Modmail

**Subject:** Question about a Saturday developer post for a non-App Store Mac app

Hi mods,

I'm Oliver Ames, the developer of Ping Warden, a Mac menu bar app that measures Wi-Fi latency and pauses AWDL to reduce lag spikes in cloud gaming. It's Developer ID notarized and distributed outside the Mac App Store, and the source is MIT on GitHub.

I posted about it in mid-September and a moderator removed the post. The notice didn't give a reason, and I'm not asking you to reverse it. I'd like to know the rule before I try again so I don't waste your time. Is a Saturday developer post allowed for an app that isn't on the Mac App Store? If it is, is there a flair or format you want me to use?

If the answer is that it belongs in r/macapps, that's fine, and I'll post it there.

Thanks,
Oliver

### Saturday post (only after a yes; confirm flair and format with them)

**Title:** I made a menu bar app that measures Wi-Fi latency and pauses AWDL to reduce lag spikes in game streaming (developer post)

I'm the developer. Ping Warden watches for awdl0, the interface behind AirDrop, AirPlay, and Handoff, coming back up and takes it down again while protection is on. On some Macs AWDL's background channel hopping shows up as periodic lag spikes in GeForce NOW and Xbox Cloud Gaming. The app also graphs your latency and jitter so you can see whether it's doing anything on your setup.

Here's one before and after on the same Mac and network: https://pingwarden.app/before-after.png. With protection off, the graph spiked to 168 ms with 18.4 ms of jitter. With it on, the worst reading was 83 ms with 6.1 ms of jitter, and the app recorded 12 attempts to turn AWDL off. That counter shows attempts, not spikes prevented. Your results will differ, and it won't help with lag from your ISP, the game server, or a congested network. AirDrop and AirPlay don't work while protection is on.

The dashboard and diagnostics are free, and Ping Protection is a one-time $15 license. The source is MIT: https://github.com/oliverames/ping-warden. It needs macOS 13 or later, runs on Intel and Apple silicon, and isn't on the Mac App Store. Site: https://pingwarden.app

If you try it, I'd like to know your Mac, your router, and what the graph looks like with protection on and off.

---

## 5. r/GeForceNOW modmail (rule 6)

**Destination:** Modmail to r/GeForceNOW. Do not make a post until they answer.

**Rule to respect:** You identified rule 6 as requiring permission for promotion. I couldn't read the rules page, so I don't have its exact wording, and the modmail avoids quoting it. Open the sidebar once and confirm the rule number and wording before sending. This is separate from the NVIDIA forum approval request already pending.

### Modmail

**Subject:** Permission to post a developer announcement (rule 6)

Hi mods,

I'm Oliver Ames, the developer of Ping Warden, a Mac menu bar app that measures Wi-Fi latency and pauses AWDL to reduce lag spikes in GeForce NOW on Mac. I understand rule 6 means I should ask before posting anything promotional, so I'm asking first.

I've answered questions about it as the developer in a few existing threads, and I haven't made a standalone post. If you approve one, here is what it would say. It would explain what AWDL is and how the app measures latency and jitter. It would show one before and after graph from my own Mac and say plainly that results vary. It would state the cost, which is a free dashboard and a one-time $15 license for Ping Protection, with the source on GitHub under MIT.

It would also say that the app only addresses AWDL-related Wi-Fi spikes and that AirDrop and AirPlay are off while it's on. Would a single post like that be OK? If you'd rather I use a particular thread, flair, or day, I'll follow that. If the answer is no, that's fine, and I'll keep answering questions where people already mention it.

Best,
Oliver

### 3-line summary of the post (not the post itself)

1. Mac users on Wi-Fi can get periodic GeForce NOW spikes from AWDL; Ping Warden measures latency and keeps AWDL down while protection is on.
2. One same-Mac before and after (168 ms to 83 ms worst reading, jitter 18.4 ms to 6.1 ms), with the caveats that results vary and AirDrop and AirPlay are off.
3. Free dashboard, $15 one-time for Ping Protection, MIT source, macOS 13+, with an explicit disclosure that I'm the developer.

---

## 6. YouTube creator email

**Destination:** andrewtsai@intheblackmedia.com (Andrew Tsai, https://www.youtube.com/@Andytizer, "Mac gamer and founder of PCGamingWiki," per the channel description).

**Rules and conditions to respect:**

- That address is the channel's business-enquiries address, so he may assume a sponsorship request. The email says it is not one.
- A free license and an affiliate link are both material connections. The email asks him to disclose them the way he normally does. Don't ask for a positive review.
- Gumroad affiliate mechanics (read from https://gumroad.com/help/article/333-affiliates-on-gumroad today): you can set a commission from 1% to 75% per product, and the affiliate needs a Gumroad account with a confirmed email before you can add them. Your own affiliates get a 30-day cookie, and payout is available 7 days after the sale. At 25% of a $15 sale the gross commission is $3.75, and Gumroad splits fees in proportion to the commission. Add him in the Affiliates dashboard only after he says yes.
- Verified route is Andrew Tsai only. For other Mac gaming channels, swap the greeting and look up each business-contact route on the channel's About page. I did not verify any others.

**Subject:** Free Ping Warden license, a Mac tool for cloud gaming lag spikes

Hi Andrew,

I'm Oliver Ames, and I make Ping Warden, a Mac menu bar app that measures Wi-Fi latency and pauses AWDL, the interface behind AirDrop and AirPlay, to reduce lag spikes in cloud gaming like GeForce NOW and Xbox Cloud Gaming. I'm writing because you cover gaming on the Mac, and this is aimed at people playing over Wi-Fi.

This isn't a sponsorship request. I'd like to send you a free license so you can try it on your own Mac and say what you find, good or bad. On my Mac and network the worst reading dropped from 168 ms with protection off to 83 ms with it on, and jitter went from 18.4 ms to 6.1 ms: https://pingwarden.app/before-after.png. That's one setup, so results vary a lot, and it does nothing for lag from your ISP or the game server. It also turns off AirDrop and AirPlay while it's on, which viewers should know.

The dashboard is free and Ping Protection is a one-time $15 license. The source is MIT at https://github.com/oliverames/ping-warden, it needs macOS 13 or later, and it runs on Intel and Apple silicon. Version 4.3.3 is out today, and you can also install it with `brew install --cask oliverames/tap/ping-warden`.

One optional extra: if you do cover it, I can set you up as a Gumroad affiliate at 25% with your own link for the description. That's entirely up to you, and skipping it is fine if you'd rather keep things simple. If you use a link or the free license, please disclose it the way you normally do.

Best,
Oliver

---

## Checks run on these drafts

- Facts match the brief: $15 one-time, free dashboard, MIT, macOS 13+, Intel and Apple silicon, Developer ID notarized, 168/18.4 off and 83/6.1 on, 12 attempts, Homebrew command. The cask file `Casks/ping-warden.rb` exists in `oliverames/homebrew-tap`, at version 4.3.2 for now.
- The brief's other statistics (46 sales since Sept 3, three 5-star reviews) are used only in the Show HN outline. I left them out of the pitches, since they add little for an editor.
- The intervention counter is described as attempts, not spikes prevented, in line with the 2026-09-14 corrections.
- No em dashes, no double hyphens in prose, no NVIDIA knowledge-base reference, and contractions throughout.
- Not verified: AlternativeTo form fields, r/GeForceNOW rule wording, current r/MacOS rules, whether you can attach an image in an App Pile comment, and any contact route other than the ones in the table.
