# What awdl0 is, and whether it's causing your ping spikes

You found `awdl0` in `ifconfig` output or in a network tool, you noticed it appears and disappears on its own, and you're wondering whether it explains the latency spikes you've been chasing. It might. It's a real cause of periodic Wi-Fi latency on a Mac, it's easy to test, and it's also easy to blame for spikes it had nothing to do with.

This page covers what the interface is, how to prove or rule it out with a measurement, why taking it down doesn't stay down, what a polling script does and doesn't catch, and what suppressing it costs you.

## What the interface is

AWDL is Apple Wireless Direct Link. It's the peer-to-peer link macOS uses for AirDrop, AirPlay, Handoff, and Sidecar, and `awdl0` is the virtual interface those features talk to. It doesn't have its own radio. It shares the Wi-Fi chipset with your infrastructure connection, so while it's active the radio is splitting time between your access point's channel and AWDL's own channel sequence.

That split is the mechanism. You're not losing bandwidth to AirDrop traffic, because usually there isn't any. You're losing the radio's undivided attention to channel switching, which shows up as latency rather than as throughput loss. That's why a speed test looks fine while your ping graph looks terrible.

## Prove it before you fix it

Check whether the interface is up:

```bash
ifconfig awdl0
```

Flags containing `UP` and `RUNNING` mean it's active right now. That's a snapshot, not a diagnosis, so run a continuous ping alongside it and take the interface down partway through:

```bash
ping -i 0.2 <your-gateway-or-game-server>
```

In a second terminal:

```bash
sudo ifconfig awdl0 down
```

If your spikes stop at the moment the interface goes down and return when macOS brings it back, you have your answer. If the graph looks the same either way, AWDL isn't your problem and the rest of this page won't help you.

Pick your ping target carefully. A public DNS resolver tells you about the path to that resolver, which isn't the path your game or call is using. Your gateway isolates the Wi-Fi hop, which is the part AWDL affects, so it's the better target for this particular test.

Ping Warden's dashboard does this measurement without the terminal, and it's free with no license and no privileged helper. It shows live latency, jitter, probe failures, a rolling history window with zoom, a timeline of spikes, and the current AWDL state, and it exports a diagnostics snapshot with custom hostnames redacted if you want a record of a bad session.

If you stream games rather than play them locally, this is the same interface behind stutter in GeForce NOW, Xbox Cloud Gaming, and self-hosted Moonlight or Parsec sessions. The measurement above is the way to tell those apart from a slow link.

## Why it comes back

macOS brings `awdl0` back up on its own, often within seconds of you taking it down. It also returns after sleep, after a network change, and after a reboot. So `sudo ifconfig awdl0 down` is a measurement tool, not a fix.

The obvious workaround is a loop: check the flags on a timer, take the interface down whenever it's up, repeat. [jamestut/awdlkiller](https://github.com/jamestut/awdlkiller) does that, [james-howard/AWDLControl](https://github.com/james-howard/AWDLControl) covers the privileged-helper side of the problem, and both are free and worth reading. A polling script genuinely works, and if you already know your way around a LaunchDaemon you can be done in an afternoon.

What polling can't do is close the window. The script only sees the interface after it's up, so the time between macOS raising AWDL and the next poll is time the radio has already started dividing. Shrinking the interval narrows the window and raises the wakeup cost, and it never reaches zero.

Ping Warden's helper takes the other approach. It blocks on `poll()` against an `AF_ROUTE` socket, so the kernel hands it the `RTM_IFINFO` event when `awdl0` changes state, and it clears `IFF_UP` through `SIOCSIFFLAGS` in response to the event rather than on a schedule. It's the same ioctl a shell command would run, reached from an event instead of a timer. The [technical documentation covers the full path](../../PingWarden/README.md#2-why-not-just-run-sudo-ifconfig-awdl0-down), including the XPC boundary between the app and the privileged helper, the code-signing checks the helper enforces, and why the intervention counter is presented as a count of actions taken rather than as proof that a specific spike was avoided.

## What suppressing AWDL costs

AirDrop, AirPlay, Handoff, and Sidecar stop working while the interface is down. That applies equally to the shell command, the free scripts, and Ping Warden, because they all end up in the same place. Bring the interface back up and those features return.

If you'd rather not think about it, the practical answer is to scope the suppression to the times you care about, whether that's a script you run before a match or an app that engages when a game comes to the front and restores everything afterward.

## Where else Mac latency spikes come from

AWDL is one cause among several, and the measurement above is what separates them. Worth checking:

- Location Services triggers Wi-Fi scans that touch the same radio, and suppressing AWDL does nothing about them. Test with Location Services off under System Settings, Privacy and Security, Location Services, or disable it per app and per system service.
- VPN clients, packet filters, and other network-control software change your routing and can add their own variance.
- Interference on a crowded channel, a weak signal, and a busy access point all produce spikes that look similar on a graph.
- Bufferbloat on your uplink shows up as latency under load. A speed test that reports latency during the transfer will tell you.

The [troubleshooting guide lists the same checks](../../PingWarden/TROUBLESHOOTING.md#other-sources-of-wi-fi-latency) with the commands to run. If cloud gaming is what brought you here, the [GeForce NOW stutter page](geforce-now-mac-stutter.md) covers the same problem from the symptom end.

## If you want the app

Ping Warden is MIT licensed, so building it yourself and running the whole thing for free is a supported path rather than a loophole. The prebuilt signed build is free to download too, and the dashboard, the diagnostics, and the latency sessions work without paying. Enabling Ping Protection in that build takes a one-time $15 license, which pays for signing, notarization, and keeping it working across macOS releases.

If you're the kind of person who went looking for `awdl0` in the first place, you can probably solve this with a script and twenty minutes, and that's a fine outcome. The part worth doing either way is the measurement, because guessing at a latency problem is how people end up replacing a router that was never broken.
