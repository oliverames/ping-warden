# Future Ideas and Experiments

This document captures ideas for future development that have been discussed but not yet implemented.

---

## v2.0 Implementation Complete

**Note**: The following options discussed in earlier versions have been implemented in v2.0:
- **SMAppService + XPC architecture** is now the foundation of Ping Warden
- Password prompts eliminated - only one-time system approval required
- Helper daemon is bundled inside the app for clean uninstall
- Helper exits when app quits, automatically restoring AWDL

---

## Control Center Widget Improvements

- Test widget appearance on physical macOS 26 (Tahoe) device
- Consider adding widget configuration options
- Investigate widget state synchronization timing

## Game Mode Detection Enhancements

- Use actual macOS Game Mode API if/when Apple provides public APIs
- Add configurable list of "game" applications
- Reduce polling interval or use event-based detection via NSWorkspace notifications
- Consider using CGWindowListCopyWindowInfo less frequently (every 5s instead of 2s)

## UI/UX Improvements

- Add onboarding tutorial for first-time users
- Localization support (German, French, Japanese, etc.)
- Keyboard shortcuts for common actions
- VoiceOver accessibility improvements

## Performance Optimizations

- Profile helper daemon memory usage over long running periods
- Investigate if AF_ROUTE socket filter can reduce message volume
- Consider using dispatch_source for file descriptor monitoring instead of poll()

## Security Enhancements

- Add option for stricter XPC code signing requirements
- Consider certificate pinning for release builds
- Audit for potential TOCTOU race conditions in permission checks

## Distribution

- Notarize app for distribution outside Mac App Store
- Create DMG installer with proper background image
- Consider Homebrew Cask formula

---

*Last updated: 2026*
