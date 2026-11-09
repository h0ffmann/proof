# The pomodoro shell (`nix develop .#pomodoro`, then `just build-mac`): Zig, which cross-compiles
# pomodoro/pomodoro.zig for Apple Silicon from any host. 0.14 is the last release whose standard
# library has the calls the file uses (std.mem.trimRight).
{ pkgs }:
pkgs.mkShell {
  packages = [ pkgs.zig_0_14 pkgs.just ];
}
