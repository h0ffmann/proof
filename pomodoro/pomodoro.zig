// pomodoro: two macOS dialogs ask the interval and the beep sound (remembered in ~/.pomodoro),
// then the sound plays every interval until Ctrl-C.
const std = @import("std");
const a = std.heap.page_allocator;

// A native text dialog through osascript. Cancel quits the app.
fn ask(prompt: []const u8, default: []const u8) ![]const u8 {
    const script = try std.fmt.allocPrint(a, "text returned of (display dialog \"{s}\" default answer \"{s}\")", .{ prompt, default });
    const r = try std.process.Child.run(.{ .allocator = a, .argv = &.{ "osascript", "-e", script } });
    if (r.term != .Exited or r.term.Exited != 0) std.process.exit(0);
    return std.mem.trimRight(u8, r.stdout, "\n");
}

pub fn main() !void {
    const path = try std.fmt.allocPrint(a, "{s}/.pomodoro", .{std.posix.getenv("HOME") orelse "."});
    var buf: [1024]u8 = undefined;
    const saved = if (std.fs.cwd().openFile(path, .{})) |f| buf[0..try f.read(&buf)] else |_| "1500\n/System/Library/Sounds/Glass.aiff";
    var it = std.mem.splitScalar(u8, saved, '\n');
    const secs = try ask("Interval in seconds", it.first());
    const sound = try ask("Beep sound (path; drag a file here)", it.next() orelse "");
    try (try std.fs.cwd().createFile(path, .{})).writeAll(try std.fmt.allocPrint(a, "{s}\n{s}", .{ secs, sound }));
    const n = try std.fmt.parseInt(u64, secs, 10);
    while (true) {
        std.Thread.sleep(n * std.time.ns_per_s);
        var p = std.process.Child.init(&.{ "afplay", sound }, a);
        _ = try p.spawnAndWait();
    }
}
