# Ping Warden 2.1.2

## Documentation improvements

- Expanded "Why Not Just Run `sudo ifconfig awdl0 down`?" section with detailed explanation of why polling scripts don't work—AWDL performs a channel scan each time it comes up, so even sub-second polling still introduces latency spikes.
- Added new "Other Sources of WiFi Latency" section covering Location Services WiFi scanning and manual mitigations.
- Added "Will Apple Fix This in Hardware?" section summarizing current research (including RIPE 91 October 2025 findings) on whether newer Apple chips might address this at the hardware level.
- Updated troubleshooting guide with Location Services diagnostics and workarounds.

## Code quality

- Fixed Swift 6 actor isolation warnings in MonitoringStateStore.
- Updated user-facing strings from "AWDLControl" to "Ping Warden" for consistency.
