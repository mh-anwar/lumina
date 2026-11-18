# Handoff

State of Lumina for the next agent, as of `main` at `48f378a`. Read CLAUDE.md first; this file adds what's in flight. Delete it once everything here is done.

## CI status
The last runs on `main` were cancelled by newer pushes or hung before the hang fix. `48f378a` (the hang fix) is the first run expected to pass end to end. Check it with `gh run list -R mh-anwar/lumina --branch main`. Locally, `flutter analyze` is clean, and the formerly hanging tests pass in about 4 s.

**Three tests fail on `main`** (seen in run 44263071118). All three come from restore now connecting at once:
1. `test/ui/features/home/view_models/home_view_model_test.dart`, "remove, scenes, backup and forgetting all lights say what happened": the status is now "BLE Bulb_7B2E was reset. …" instead of "No lights found…". The new message is correct; update the expectation. `ux-viewmodel` already does.
2. `test/data/repositories/home_repository_test.dart`, "backup and restore round trip, with a SEQ margin": SEQ is the old value + 100,000 + 65, because connecting sends messages. Assert `>=` instead of equality.
3. `test/data/repositories/home_repository_test.dart`, "SEQ never goes backwards across restarts": an expectation is false. This is probably the same auto-connect effect; investigate first, since SEQ must only go up.

Fix these first, in one PR.

## How to work here

- **Every change gets a PR**, squash-merged right after it's opened.
  - Write the PR description for the next agent: what changed and why, files touched, decisions, what's untested (especially real-bulb checks), and follow-ups.
  - Leave out session links, anything about the owner or the conversation, and real device identifiers. Use made-up values like `AA:01` and `BLE Bulb_7B2E`.
- **CI runs on pushes to `main` only**, not on PRs. See `.github/workflows/ci.yml`.
  - A newer push cancels the older run.
  - Docs-only pushes (`*.md`, `docs/**`) are skipped.
  - Job limit is 15 min; each test gets `--timeout 2m`.
  - Formatting and freezed failures print the diff to apply.
  - Fix failures forward with a new PR.
- **Flutter 3.47.5 is installed locally** at `~/development/flutter/bin`. Run `export PATH="$HOME/development/flutter/bin:$PATH"`, then `dart format lib test tool`, `flutter analyze`, and `flutter test <changed test files>` before merging. Run slow commands in the background.
- **Don't waste time waiting.** No `sleep`, polling loops or `timeout` wrappers, and no blocking on CI. Put this rule in every subagent brief.
- **Keep tests few.** At most one focused test per behavior that could realistically regress. The owner thinks there are too many tests.
- **Releases:** follow CLAUDE.md. Bump `pubspec.yaml` (`X.Y.Z+N`, always raising `N`), make an annotated tag (`git tag -a vX.Y.Z -m ...`; plain tags fail here) and push it. The tag push starts `release.yml`. The last release is v1.1.0 (`1.1.0+2`). Everything after it is unreleased: color, the palette, auto-connect and more. The owner wants a release to test on a phone, so the next one should be v1.2.0.

## Done since v1.1.0, on `main`

- **Auto-connect** (PR #4): commands connect first, drops reconnect, and a failed connection gets up to 3 tries (Android GATT 133).
- **Color** (PR #5): Light HSL is bound and set via `Msg.hslSet`. A light's sheet has a White/Color switch, hue and saturation sliders, and swatches.
  - Some Sengled color firmware sends Composition Data page 0 with a nonzero page byte, so `Composition.parse` no longer checks it.
- **Palette** (PR #5): neutral system grays, gray off tiles, near-white lit tiles, Figtree titles.
- **Other PR #5 items:**
  - resizable widgets
  - Add a light keeps scanning while open
  - restoring a backup connects at once
  - "Start over" renamed to "Forget all lights" (code: `forgetAll`)
  - test cleanup
- **CI changes** (PRs #8 and the hang fix): concurrency cancellation and the timeouts above.
- **Hang fix** (`48f378a`): the Add a light rescan loop and the endless spinner hung tests.
  - The rescan now waits `rescanPause` (1 s) before starting again.
  - The spinner is replaced by a static icon.

## In flight

**Update:** `ux-bluetooth` is now merged into `main` as `6048b84` (rebased; `flutter analyze` clean). Its CI run on `main` is the first to compile the new Kotlin, so check it. Only `ux-viewmodel` remains: rebase it the same way. Expect conflicts in `home_view_model.dart` and its test, since `ux-bluetooth` added the Bluetooth-ready hook, `ConnectBusy` and the `ToggleLightAction` case there.

## Branch details

Both branches are on GitHub, branched from `3079e57` (an old `color` commit). To merge each one:
1. Rebase onto `main`: `git fetch upstream && git rebase --onto upstream/main 3079e57 <branch>`. Expect small conflicts in `home_view_model.dart`, `home_view_model_test.dart`, `light_repository.dart` and `dependencies.dart`, since both branches touch them.
2. Run `dart format`, `flutter analyze` and the changed tests locally.
3. Open a detailed PR and merge it.

Merge `ux-bluetooth` first; it's smaller in the view model.

### `ux-bluetooth`: 3 commits, tip `2a5bbec`
Analyze is clean and its 21 changed tests pass. The Kotlin was never compiled.
- **Bluetooth ready:** `BleService.readyChanges` → `ConnectionRepository.bluetoothReady` → the view model reconnects when Bluetooth turns on. `BluetoothUnavailableReason` is added, and `openSettings()` exists but no UI calls it yet.
- **Scans:** a `ScanHold` shared via `dependencies.dart` makes `connect()` return the new `ConnectBusy` result during an Add a light scan. Connect no longer stops that scan.
- **Widget direction:** the last on/off is stored under the `lastOn` key, and the `_shown` cache is removed with updates queued.
- **One light widget** (`OneLightWidget` and `OneLightConfigureActivity`):
  - URI: `luminar://light?addr=0x0010` → `ToggleLightAction`.
  - Light list: `syncLights` saves the lights' addresses and names.
  - Per-light state key: `light_<addr>_on`.
- **Failures:** a widget showing Retry opens the app, and shortcuts toast when they fail.
- **Timings:** everything is in `Timings` except `light_repository.dart`'s 2 s node reset (`ux-viewmodel` changes that).
- **Other:** `homeViewModel` is now created lazily in `Dependencies`. The README widgets section and "Lights and scenes" strings are updated.
- **Check in CI or with a build:**
  - `HomeWidgetPlugin.getData` in the new Kotlin.
  - The `onDeleted` override and the `%04x` address formatting in `LuminarWidgets.kt`.
  - The `lateinit` listener in `ShortcutActivity.kt`.
  - `widgetFeatures` in `widget_light_info.xml`.

### `ux-viewmodel`: 1 commit, `6590ea0`
Analyze is clean, and 45 tests pass in `home_view_model_test` and `light_repository_test`. `home_screen_test` hasn't run since the hang fix on `main`.
- **Remove:** `LightRepository.remove` returns whether the bulb acknowledged the reset, and `forget` removes without one. The sheet asks "Remove anyway?" if the bulb doesn't answer.
- **Connect waiting:** one shared future per connect and per add replaces the polling, and buttons stay enabled during a connect.
- **Auto-connect:** saving scenes, the power-on setting and deleting scenes connect first.
- **Disconnected sliders:** they update at once and send once after connecting.
- **Messages:** info messages clear after `infoLinger` (4 s). Sheet errors stay in their sheet.
- **Plain-language errors.**
- **Reset and setup:** a light that misses setup is retried in the background, and there's a **Set up all again** button.
- **New scene:** cancelling restores the lights.
- **Names:** unique default names, and duplicates are refused.
- **Last seen:** tiles show "Last seen …" while disconnected. A light marked not responding is queried again after a command.
- **Settings:** the Disconnect button is gone, and **Try again** shows only after a failed connect.
- **Restore:** the code is checked inside the dialog, it pre-fills from the clipboard, and "Copied" is a SnackBar.
- **Changed expectation:** after restoring the removed bulb, the status is now "… was reset" instead of "No lights found".
- **Not done:** the "Reset; adds it back as <name>" wording in `add_light_view_model.dart`.

## To do after those merge (the owner asked for all of these)

1–4. Done on `ux-viewmodel`: Set up all again, the New scene revert, unique names, Last seen and the not-responding query.
5. **Wording:** the add-light row says "Was reset, sets it up again"; also handle a rename to an empty name.
6. **(Done on `ux-bluetooth`.) Scans fighting:** pause automatic reconnects while Add a light is open. Today `ConnectionRepository.connect`'s `stopScan` kills the add-light scan.
7. **(Done on `ux-bluetooth`.) Failed widget taps:** when a widget is unavailable, a tap opens the app (`PendingIntent.getActivity`). Shortcuts report failure.
8. **(Done on `ux-bluetooth`.) Stale widget status:** fix the `WidgetRepository._shown` cache across isolates (re-read `lastStatus` before skipping).
9. **(Mostly done on `ux-bluetooth`; `light_repository`'s node reset is left.) Timings:** move the hardcoded durations into `Timings`, keeping their values:
   - `reactive_ble_service.dart`: 3 s, 10 s, 12 s, 15 s, 400 ms
   - `provisioning_repository.dart`: 30 s
   - `light_repository.dart`: 2 s node reset
   - `widget_repository.dart`: 30 s
   - `widget_entry.dart`: 400 ms
   - `AddLightViewModel.rescanPause`
10. **(Backend done on `ux-bluetooth`; the button isn't wired.) Permissions:** an "Open settings" button for a permanently denied permission (`permission_handler`'s `openAppSettings`) and for Location being off.
11. **Smaller items:**
    - Drop bulbs that stop advertising from the add-light list.
    - **Forget all lights** offers to reset connected bulbs first.
    - Dragging the All-lights tile shouldn't turn on lights that are off unless all of them are off.
    - Widgets and shortcuts offer the user's own scenes.
12. **Prune tests** after the branches merge; the owner wants fewer. Candidates:
    - `light_repository_test`: "a white bulb ignores a hue".
    - `home_view_model_test`:
      - "lists several reset lights by name" (wording)
      - "mentions reset lights after connecting through another" (overlaps `connection_repository_test`)
      - "explains a provisioning failure" (string mapping)
    - `home_test`: "updateLight replaces one light" (trivial).
    - `add_light_view_model_test`: "describes signal strength" (wording).
13. **README cleanup:** remove trivia like widget tap timings, and keep it about what the app does.

## Needs a real phone with bulbs (only the owner can do these)

- Color: remove and re-add a color bulb so it binds HSL, then try Color in its sheet. `Msg.hslSet` (`0x8277`) has only been sent to the simulated bulb.
- The automatic reconnect and GATT retry, the One light widget, and the Remove acknowledgement.

## Watch out for

- `pumpAndSettle` never returns while an indeterminate progress indicator is on screen. Don't show endless spinners in sheets that stay open.
- In `Home`, the bare name `presets` resolves to the top-level built-in list, not the field. Use `this.presets`.
- Changing a `freezed` model needs `dart run build_runner build --delete-conflicting-outputs`, which now works locally, and the generated files must be committed.
- Keep the `luminar://` scheme, `app.luminar.luminar`, the `luminar.home.v2` storage key and the `LuminarWidgets` class name. Installed copies depend on them.
