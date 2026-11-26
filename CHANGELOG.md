# Changelog

## Unreleased

### Added

- Remember a preferred Dock display per combination of connected screens, including the MacBook screen when active. Connection order and screen arrangement do not change the saved choice.
- Restore known setups automatically after three seconds of stable screen layout on startup or display changes, using the existing cancelable pointer gesture. Opening the menu cancels a pending restore; unavailable edges are skipped silently.
- Show whether the current setup has a saved display choice. New setups wait for a choice; the previous global preference is imported into the first matching setup.
- Self-checks for setup preference migration, persistence, independent choices, connection order, and restore scheduling during layout changes and disconnects.

## 1.0.4 — 2026-11-26

### Added

- Selecting a display now briefly moves the pointer to its bottom edge to bring the Dock there, then returns it. Selecting the same display again repeats the gesture.
- Automatic Dock movement stops when you move, click, or scroll. Covered bottom edges are skipped; partially covered edges use an exposed segment.

### Changed

- The Dock inside the menu bar icon stays filled in both states. The padlock is visible only while protection is active and disappears when paused or otherwise inactive.
- Updated setup instructions and the menu bar artwork preview.

### Fixed

- Improved bottom-edge handling during rapid downward movement while preserving immediate upward escape.
- Synthetic pointer movement permits real mouse and keyboard input. macOS mouse-filter safety shutdowns cancel automatic movement and leave protection inactive until the app restarts.

### Validation

- Passed eleven edge-policy checks, nine Dock movement checks, input safety checks, two menu icon checks (including pixel assertions), and four login-item status checks.
- Decoded all ten app icon representations, compared small icon pixels with the source artwork, and verified the app bundle signature.
- Real multi-display interaction, sleep/wake, reconnecting displays, and startup after logout/login still require hands-on testing.

## 1.0.3 — 2026-11-25

### Added

- Optional **Start at Login** setting in the menu bar.
- Login-item status reporting, System Settings access when approval is required, and registration error messages.

### Changed

- Updated setup, privacy, and removal instructions.

## 1.0.2 — 2026-11-25

- Initial public preview release.
