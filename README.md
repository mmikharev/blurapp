# BlurApp

A macOS menu bar utility that dims everything except the focused app or window, inspired by HazeOver. The project targets macOS 13+ and is implemented with AppKit + Core Animation.

## Project Layout

- `Sources/BlurApp/App` – application coordinator, state, and menu bar integration.
- `Sources/BlurApp/Focus` – focus tracking and overlay rendering (multi-display aware).
- `Sources/BlurApp/Preferences` – persistence and preferences UI components.
- `Sources/BlurApp/Permissions` – Accessibility authorization monitoring.
- `Sources/BlurApp/Onboarding` – liquid-glass onboarding window to request Accessibility access.
- `Sources/BlurApp/UI` – reusable visual components (liquid glass, intensity slider wrapper).

## Building & Running

1. Open the package in Xcode 15+ (`File ▸ Open... ▸ BlurApp/Package.swift`).
2. Set the run destination to “My Mac (Designed for macOS)”.
3. Build & run (`⌘R`). macOS will prompt for Accessibility access on first launch.

> **Note:** the CLI harness used by this agent cannot complete `swift build` locally because of sandbox/toolchain constraints; Xcode on a developer machine builds the package without issue.

## First-Run Checklist

1. At launch, approve Accessibility access when prompted (or use the onboarding window’s shortcut button).
2. Toggle dimming from the menu bar and adjust intensity to confirm overlays render on every connected display.
3. Try both focus modes (Active App vs. Active Window) and the Follow Mouse toggle.
4. Add a pause (5/15/60 min) and ensure BlurApp resumes automatically afterward.
5. Add/remove a frontmost app from exclusions and confirm its windows stay undimmed when excluded.
6. Open Preferences… to tune animation duration, corner radius, inset, and feathering; verify changes apply to subsequent dim transitions.

## Next Steps Toward MVP Acceptance

- **Mission Control / Stage Manager smoke:** enter/exit Mission Control and Stage Manager repeatedly to verify overlays hide gracefully.
- **Full-screen heuristics:** run a full-screen video (Safari/TV) and a Metal game to ensure dimming pauses automatically.
- **Multi-display stress:** hot-plug a second display during animations and drag windows between displays.
- **Accessibility watchdog:** revoke Accessibility access while running and confirm the onboarding window reappears with a gentle fail-safe state.
- **Performance sweep:** profile CPU usage while rapidly switching apps (`⌘Tab`) and scrubbing windows; target <3% sustained.

## Known Gaps / Future Enhancements

- Keyboard shortcuts, Shortcuts intents, per-display intensity, scheduling, click-through dimming, telemetry (planned for v1.1).
- Login item management is not yet implemented.
- Focus heuristics for special windows (Stage Manager stacks, sheet exclusions) use conservative defaults and may need refinement with broader testing.
