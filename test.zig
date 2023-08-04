
const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const page_allocator = std.heap.page_allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const msgq = @import("message-queue.zig");
const Message = msgq.Message;
const MessageDispatcher = msgq.MessageDispatcher;

const esrc = @import("event-sources.zig");
const EventSourceKind = esrc.EventSourceKind;
const EventSourceSubKind = esrc.EventSourceSubKind;
const EventSource = esrc.EventSource;

const edsm = @import("edsm.zig");
const Reflex = edsm.Reflex;
const Stage = edsm.Stage;
const StageList = edsm.StageList;
const StageMachine = edsm.StageMachine;

const TestMachine = struct {

    const PrivateData = struct {
        tm0: EventSource,
        ticks: u64 = 0,
        sg0: EventSource,
        io0: EventSource,
        sg1: EventSource,
    };
    const interval: u32 = 1000; // msec

    fn onHeap(a: Allocator, md: *MessageDispatcher) !*StageMachine {

        var me = try StageMachine.onHeap(a, md, "TEST-SM", 2);
        me.stages[0] = .{.name = "INIT", .enter = &initEnter, .leave = null};
        me.stages[1] = .{.name = "WORK", .enter = &workEnter, .leave = &workLeave};

        var init = &me.stages[0];
        var work = &me.stages[1];

        init.setReflex(.sm, Message.M0, Reflex{.transition = work});
        work.setReflex(.tm, Message.T0, Reflex{.action = &workT0});
        work.setReflex(.io, Message.D0, Reflex{.action = &workD0});
        work.setReflex(.sg, Message.S0, Reflex{.action = &workS0});
        work.setReflex(.sg, Message.S1, Reflex{.action = &workS0});

        return me;
    }

    fn initEnter(me: *StageMachine) void {

        me.data = me.allocator.create(PrivateData) catch unreachable;
        var pd: *PrivateData = @ptrCast(@alignCast(me.data));

        me.initTimer(&pd.tm0, Message.T0) catch unreachable;
        pd.ticks = 0;

        me.initSignal(&pd.sg0, std.os.SIG.INT, Message.S0) catch unreachable;
        me.initSignal(&pd.sg1, std.os.SIG.TERM, Message.S1) catch unreachable;

        me.initIo(&pd.io0);
        pd.io0.id = 0; // stdin
        pd.io0.seqn = Message.D0;

        me.msgTo(me, Message.M0, null);
    }

    fn workEnter(me: *StageMachine) void {
        var pd: *PrivateData = @ptrCast(@alignCast(me.data));
        pd.tm0.enable(&me.md.eq, .{interval}) catch unreachable;
        pd.io0.enable(&me.md.eq, .{}) catch unreachable;
        pd.sg0.enable(&me.md.eq, .{}) catch unreachable;
        pd.sg1.enable(&me.md.eq, .{}) catch unreachable;
        print("\nHi! I am '{s}'. Press ^C to stop me.\n", .{me.name});
        print("You can also type something and press Enter\n\n", .{});
    }

    fn workT0(me: *StageMachine, src: ?*StageMachine, data: ?*anyopaque) void {
        var tm: *EventSource = @ptrCast(@alignCast(data));
        var pd: *PrivateData = @ptrCast(@alignCast(me.data));
        _ = src;
        pd.ticks += 1;
        print("tick #{} (nexp = {})\n", .{pd.ticks, tm.info.tm.nexp});
        tm.enable(&me.md.eq, .{interval}) catch unreachable;
    }

    fn workD0(me: *StageMachine, src: ?*StageMachine, data: ?*anyopaque) void {
        var io: *EventSource = @ptrCast(@alignCast(data));
        _ = src;
        var buf: [64]u8 = undefined;
        const nr = io.info.io.bytes_avail;
        if (0 == nr) { // ^D
            print("EOT\n", .{});
            std.os.raise(std.os.SIG.TERM) catch unreachable;
            return;
        }
        print("have {} bytes\n", .{nr});
        _ = std.os.read(io.id, buf[0..nr]) catch unreachable;
        std.debug.print("you entered '{s}'\n", .{buf[0..nr-1]});
        io.enable(&me.md.eq, .{}) catch unreachable;
    }

    fn workS0(me: *StageMachine, src: ?*StageMachine, data: ?*anyopaque) void {
        var pd: *PrivateData = @ptrCast(@alignCast(me.data));
        _ = src;
        var sg: *EventSource = @ptrCast(@alignCast(data));
        var si = sg.info.sg.sig_info;
        print("got signal #{} from PID {} after {} ticks\n", .{si.signo, si.pid, pd.ticks});
        // print("\n\n === {any} === \n", .{si});
        me.msgTo(null, Message.M0, null);
    }

    fn workLeave(me: *StageMachine) void {
        print("Bye! It was '{s}'.\n", .{me.name});
    }
};

pub fn main() !void {

    var arena = ArenaAllocator.init(page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var md = try MessageDispatcher.onStack(allocator, 5);
    var sm = try TestMachine.onHeap(allocator, &md);
    try sm.run();

    try md.loop();
    md.eq.fini();
    print("That's all for now\n", .{});
}
