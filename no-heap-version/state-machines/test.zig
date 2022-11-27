
const std = @import("std");
const os = std.os;
const print = std.debug.print;

const mq = @import("../engine/message-queue.zig");
const MessageDispatcher = mq.MessageDispatcher;
const MessageQueue = mq.MessageQueue;
const Message = mq.Message;

const esrc = @import("../engine//event-sources.zig");
const EventSource = esrc.EventSource;
const Signal = esrc.Signal;
const Timer = esrc.Timer;
const FileSystem = esrc.FileSystem;
const InOut = esrc.InOut;

const edsm = @import("../engine/edsm.zig");
const StageMachine = edsm.StageMachine;
const Stage = StageMachine.Stage;
const util = @import("../util.zig");

pub const TestMachine = struct {

    const M0_WORK = Message.M0;

    sm: StageMachine,
    tm0: Timer = undefined,
    interval: u32,
    cnt: u64 = 0,
    sg0: Signal = undefined,
    sg1: Signal = undefined,
    io0: InOut = undefined,

    pub fn init(md: *MessageDispatcher) TestMachine {

        var ctor = Stage{.name = "INIT", .enter = &initEnter, .leave = null};
        var work = Stage{.name = "WORK", .enter = &workEnter, .leave = &workLeave};

        ctor.setReflex(Message.M0, .{.transition = 1});
        work.setReflex(Message.T0, .{.action = &workT0});
        work.setReflex(Message.S0, .{.action = &workS0});
        work.setReflex(Message.S1, .{.action = &workS0});
        work.setReflex(Message.D0, .{.action = &workD0});

        return TestMachine {
            .sm = StageMachine.init(md, "TestMachine", &.{ctor, work}),
            .interval = 3000,
        };
    }

    fn initEnter(sm: *StageMachine) void {
        var me = @fieldParentPtr(TestMachine, "sm", sm);
        me.tm0 = Timer.init(sm, Message.T0) catch unreachable;
        me.sg0 = Signal.init(sm, os.SIG.INT, Message.S0) catch unreachable;
        me.sg1 = Signal.init(sm, os.SIG.TERM, Message.S1) catch unreachable;
        me.io0 = InOut.init(sm, 0);
        sm.msgTo(sm, M0_WORK, null);
    }

    fn workEnter(sm: *StageMachine) void {
        var me = @fieldParentPtr(TestMachine, "sm", sm);
        me.sg0.es.enable() catch unreachable;
        me.sg1.es.enable() catch unreachable;
        me.tm0.es.enable() catch unreachable;
        me.tm0.start(me.interval) catch unreachable;
        me.io0.es.enable() catch unreachable;
    }

    fn workT0(sm: *StageMachine, src: ?*StageMachine, dptr: ?*anyopaque) void {
        var me = @fieldParentPtr(TestMachine, "sm", sm);
        _ = src;
        me.cnt += 1;
        print("tick #{}\n", .{me.cnt});
        var es = util.opaqPtrTo(dptr, *EventSource);
        var tm = @fieldParentPtr(Timer, "es", es);
        es.enable() catch unreachable;
        tm.start(me.interval) catch unreachable;
    }

    fn workD0(sm: *StageMachine, src: ?*StageMachine, dptr: ?*anyopaque) void {
        var me = @fieldParentPtr(TestMachine, "sm", sm);
        _ = me;
        _ = src;
        var es = util.opaqPtrTo(dptr, *EventSource);
        var io = @fieldParentPtr(InOut, "es", es);
        var buf: [64]u8 = undefined;
        const nr = io.bytes_avail;
        if (0 == nr) { // ^D
            print("EOT\n", .{});
            os.raise(os.SIG.TERM) catch unreachable;
            return;
        }
        print("have {} bytes\n", .{nr});
        _ = std.os.read(es.id, buf[0..nr]) catch unreachable;
        std.debug.print("you entered '{s}'\n", .{buf[0..nr-1]});
        es.enable() catch unreachable;
    }

    fn workS0(sm: *StageMachine, src: ?*StageMachine, dptr: ?*anyopaque) void {
        _ = src;
        var es = util.opaqPtrTo(dptr, *EventSource);
        var sg = @fieldParentPtr(Signal, "es", es);
        print("got signal #{} from PID {}\n", .{sg.info.signo, sg.info.pid});
        sm.msgTo(null, Message.M0, null);
    }

    fn workLeave(sm: *StageMachine) void {
        var me = @fieldParentPtr(TestMachine, "sm", sm);
        _ = me;
        print("Bye!\n", .{});
    }
};
