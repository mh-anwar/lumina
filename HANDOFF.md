# Handoff

State of Lumina for the next agent. Read CLAUDE.md first. Delete this file once the items below are done.

## Status
- v1.2.0 (`1.2.0+3`) is released from `main`.
- Everything from the earlier handoff is merged: the restore test fixes (#16), `ux-viewmodel` (#17), and the remaining UX items and test pruning (#18).
- The old branches `ux-bluetooth`, `ux-viewmodel`, `ux-bluetooth-rebased` and the `worktree-agent-*` branches are stale and can be deleted.

## Left to do
- **User scenes in widgets and shortcuts:** widgets offer only the built-in presets. This needs the user's presets saved for the widget isolate (`WidgetRepository`) and a configure activity in Kotlin, like `OneLightConfigureActivity`.

## Needs a real phone with bulbs (only the owner can do these)
- **Color:** remove and re-add a color bulb so it binds HSL, then use Color in its sheet. `Msg.hslSet` (`0x8277`) has only been sent to the simulated bulb.
- **Connections:** the automatic reconnect, the GATT 133 retry, and reconnecting when Bluetooth turns on.
- **One light widget.**
- **Remove:** the Node Reset acknowledgement, and "Remove anyway".
- **Forget all → Reset and forget.**
- **All-lights slider with some lights off:** it sends direct messages, not the group message.
- **Open settings:** after the Bluetooth permission is denied for good.

## How to work here
- Follow CLAUDE.md for the workflow: a detailed PR for every change, squash-merged at once, with CI running on `main`.
- Flutter 3.47.5 is installed at `~/development/flutter/bin`, and the Android SDK at `~/Android/Sdk`.
- No `sleep`, polling loops or blocking waits; run slow commands in the background.
- Keep tests few.

## Watch out for
- `pumpAndSettle` never returns while an indeterminate progress indicator is on screen.
- In `Home`, the bare name `presets` resolves to the top-level list; use `this.presets`.
- Keep the `luminar://` scheme, `app.luminar.luminar`, the `luminar.home.v2` storage key and the `LuminarWidgets` class name. Installed copies depend on them.
- When a throttled send runs later, read the lights at send time, not when it was scheduled (see `LightRepository._sendLevelAll`).
