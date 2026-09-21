# Why GeForce NOW stutters on a MacBook

If your GeForce NOW session hitches repeatedly over Wi-Fi, your Mac's `awdl0` interface is one possible contributor. Compare the connection with AWDL active and suppressed before deciding whether it explains your stutter.

This page covers what the stutter looks like, how to investigate whether AWDL contributes, the free ways to deal with it, what you give up when you do, and where to look when AWDL turns out to be innocent.

## Does this match what you're seeing?

AWDL-related interruptions can appear as periodic stutter. The stream may look fine, briefly smear or respond slowly, and then recover. Other network problems can produce similar symptoms. Compare GeForce NOW's network overlay with your latency readings instead of diagnosing the cause from the pattern alone.

Two more tells worth checking. The stutter shows up on Wi-Fi and disappears on Ethernet, and it bothers the Mac while a Windows PC or a console on the same network is fine. AWDL is an Apple feature, so it only affects Apple hardware.

## What AWDL is and why your game cares

AWDL is Apple Wireless Direct Link, the interface macOS uses for AirDrop, AirPlay, Handoff, and Sidecar. Those features need to find nearby devices without going through your router, so macOS keeps the interface available, and it can bring `awdl0` back up on its own after it has been taken down.

The catch is that AWDL shares your Mac's Wi-Fi radio. While it's active, the radio isn't giving your router's channel its full attention, and that channel switching can contribute to stutter. Cloud gaming notices it more than most things do, because every frame and every input is riding that link in real time.

## Confirm it before you change anything

Open Terminal and run this while a session is going:

```bash
ifconfig awdl0
```

Look at the flags on the first line. If they include `UP` and `RUNNING`, AWDL is active right now. That alone doesn't prove it's causing your stutter, so do the actual test:

```bash
sudo ifconfig awdl0 down
```

Play for a few minutes and compare the hitching and latency readings. Check whether macOS has raised AWDL again during the test. Repeatable improvement while AWDL stays down supports it as a contributor. If you see no improvement, investigate the other causes in the last section.

You can watch the same thing without the command line. Ping Warden's dashboard is free, it needs no license and no privileged helper, and it puts live latency, jitter, probe failures, a rolling history chart, and the current AWDL state in one window. Point it at a GeForce NOW zone rather than a public DNS server, because a DNS server isn't on the path your game traffic takes.

## Why the command doesn't stay

After `sudo ifconfig awdl0 down`, macOS can bring the interface back up on its own, including after sleep, network changes, or a reboot. A single command does not keep AWDL suppressed throughout a session.

The usual next step is a script that checks `awdl0` on a timer and knocks it down again whenever it finds it up. [jamestut/awdlkiller](https://github.com/jamestut/awdlkiller) does exactly that, it's free, and it works. If you're comfortable with a LaunchAgent and a plist, it's a legitimate answer and I'd rather you use it than pay for something you don't need.

The difference is in the gap. A polling script only reacts after the interface is already up, so there's a window between macOS raising AWDL and the script noticing, and that window is when the radio is already dividing its attention. Ping Warden's helper waits on kernel route and interface events through an `AF_ROUTE` socket instead of checking on a timer, so it acts on the event itself rather than on the next poll. The [technical guide explains that in more detail](../../PingWarden/README.md#2-why-not-just-run-sudo-ifconfig-awdl0-down), including why the app counts interventions without claiming that any single one saved you from a specific spike.

## What you give up

This is the real cost, and it isn't small. While AWDL is down, AirDrop, AirPlay, Handoff, and Sidecar stop working. That's true of the Terminal command, of the free scripts, and of Ping Warden, because they're all doing the same thing to the same interface. Nothing can suppress AWDL and keep those features working at the same time.

What you can change is how long you live with it. Turning the interface back up restores everything, and Ping Warden adds a ten-minute pause for when you need to send a file mid-session, plus detection that only engages protection when a game is frontmost. It skips that detection on Ethernet, where there's no reason to break AirDrop in the first place.

AWDL can also affect other latency-sensitive streams over Wi-Fi. If you use Xbox Cloud Gaming, Moonlight, or Parsec, the comparison above can help investigate those sessions too. Nothing here is specific to GeForce NOW except the choice of ping target.

## When it isn't AWDL

Plenty of Mac stutter has nothing to do with AWDL. If repeated comparisons show no improvement while `awdl0` stays down, work through these:

- Location Services asks macOS to scan nearby Wi-Fi networks, and those scans affect the same radio. You can turn Location Services off temporarily under System Settings, Privacy and Security, Location Services, or disable it for individual apps and system services. Ping Warden doesn't block those scans.
- VPN clients and other network-control tools change how your traffic is routed. Quit them and test again.
- A congested router, a distant access point, or a crowded 2.4 GHz band will hurt a cloud gaming session no matter what your Mac is doing.
- GeForce NOW itself has capacity limits, and a busy zone at peak time isn't your Mac's fault. Try a different one.

The [troubleshooting guide](../../PingWarden/TROUBLESHOOTING.md#ping-protection-is-active-but-latency-still-spikes) walks through the same list in more depth, and if you want the interface-level version of all this, there's a separate page on [what `awdl0` is and how to measure it](awdl0-ping-spikes.md).

## What it costs

Ping Warden is free to download and the source is MIT, so building it yourself and skipping the payment is a supported path. In the prebuilt app the dashboard, the diagnostics, and your past session recaps are free. Turning on Ping Protection takes a one-time $15 license that covers signing, notarization, and testing across macOS releases, and starting a Latency Session needs the same license or an active transition because the session turns protection on for its duration.

You can investigate AWDL without buying the app. Compare repeated measurements with the interface active and suppressed, then choose a remedy based on the results.
