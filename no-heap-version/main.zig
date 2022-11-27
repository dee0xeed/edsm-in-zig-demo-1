
const std = @import("std");
const mque = @import("engine/message-queue.zig");
const eque = @import("engine/event-capture.zig");
const Test = @import("state-machines/test.zig").TestMachine;

pub fn main() !void {

    var mq = mque.MessageQueue{};
    var eq = try eque.EventQueue.init(&mq);
    var md = mque.MessageDispatcher.init(&mq, &eq);
    var t = Test.init(&md);
    try t.sm.run();

    try md.loop();
    md.eq.fini();
}
