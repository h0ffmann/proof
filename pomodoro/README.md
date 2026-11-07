# pomodoro

A 13-line Zig timer. It sleeps for an interval, plays a sound, and repeats until Ctrl-C.

## Build

Needs Zig (0.13 or newer). From the repo root:

```bash
just build-mac        # Apple Silicon binary at pomodoro/pomodoro
```

The recipe runs `zig build-exe -target aarch64-macos -O ReleaseSmall`, so it also cross-compiles
from Linux. The binary depends only on macOS itself.

## Run

```bash
pomodoro/pomodoro                                          # every 25 min, Glass.aiff
pomodoro/pomodoro 300                                      # every 5 min
pomodoro/pomodoro 1500 /System/Library/Sounds/Ping.aiff    # another stock sound
pomodoro/pomodoro 1500 ~/Music/gong.mp3                    # any file afplay can play
```

Argument 1 is the interval in seconds, argument 2 the sound file. The sound plays through the
macOS `afplay` command, which is why the program needs no audio library. The stock sounds live in
`/System/Library/Sounds/`.
