// usage: pomodoro [seconds=1500] [sound=/System/Library/Sounds/Glass.aiff]
const std = @import("std");

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();
    const secs = try std.fmt.parseInt(u64, args.next() orelse "1500", 10);
    const sound = args.next() orelse "/System/Library/Sounds/Glass.aiff";
    while (true) {
        std.Thread.sleep(secs * std.time.ns_per_s);
        std.debug.print("bip\n", .{});
        var p = std.process.Child.init(&.{ "afplay", sound }, std.heap.page_allocator);
        _ = try p.spawnAndWait();
    }
}
