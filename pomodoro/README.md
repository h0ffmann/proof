# pomodoro

A Zig interval timer for macOS in under 30 lines. Every launch opens two native dialogs, one for
the interval in seconds and one for the beep sound, pre-filled with your last answers. Then the
sound plays every interval until Ctrl-C.

## Build

Needs Zig (0.13 or newer). From the repo root:

```bash
just build-mac        # Apple Silicon binary at pomodoro/pomodoro
```

The recipe runs `zig build-exe -target aarch64-macos -O ReleaseSmall`, so it also cross-compiles
from Linux. The binary depends only on macOS itself.

## Run

```bash
pomodoro/pomodoro
```

1. **Interval in seconds**: default 1500 (25 minutes).
2. **Beep sound**: a path to any file `afplay` can play; default `/System/Library/Sounds/Glass.aiff`.
   You can drag a file from Finder into the text field. The stock sounds live in
   `/System/Library/Sounds/` (Glass, Ping, Pop, Purr, Submarine, ...).

Cancel in either dialog quits. The answers are saved to `~/.pomodoro` (two lines: seconds, path)
and become the defaults next time; delete that file to reset.

## How it stays small

The dialogs are AppleScript's `display dialog`, run through `osascript`, and the sound goes
through the `afplay` command. Both ship with macOS, so the program needs no GUI toolkit, no audio
library and no SDK to link against.
