
const std = @import("std");
const print = std.debug.print;

const mq = @import("message-queue.zig");
const MessageDispatcher = mq.MessageDispatcher;
const MessageQueue = mq.MessageQueue;
const Message = mq.Message;

pub const StageMachine = struct {

    const Self = @This();
    const Error = error {
        IsAlreadyRunning,
        HasNoStates,
        StageHasNoReflexes,
    };

    name: []const u8 = undefined,
    namebuf: [32]u8 = undefined,
    is_running: bool = false,

    stages: [8]Stage = undefined,
    // if you need more consider decomposing your machine
    n_stages: usize = 0,
    current: usize = 0, // number of current state

    md: *MessageDispatcher,

    pub const Stage = struct {

        const reactFnPtr = *const fn(me: *StageMachine, src: ?*StageMachine, data: ?*anyopaque) void;
        const enterFnPtr = *const fn(me: *StageMachine) void;
        const leaveFnPtr = enterFnPtr;

        const ReflexKind = enum {
            action,
            transition,
        };

        pub const Reflex = union(ReflexKind) {
            action: reactFnPtr,
            transition: usize,
        };

        const esk_tags = "MDSTF";
        /// number of rows in reflex matrix
        // const nrows = @typeInfo(EventSource.Kind).Enum.fields.len;
        const nrows = esk_tags.len;
        /// number of columns in reflex matrix
        const ncols = 16;
        /// name of a stage
        name: []const u8,
        /// called when machine enters a stage
        enter: ?enterFnPtr = null,
        /// called when machine leaves a stage
        leave: ?leaveFnPtr = null,

        /// reflex matrix
        /// row 0: M0 M1 M2 ... M15 : internal messages
        /// row 1: D0 D1 D2         : i/o (POLLIN, POLLOUT, POLLERR)
        /// row 2: S0 S1 S2 ... S15 : signals
        /// row 3: T0 T1 T2 ... T15 : timers
        /// row 4: F0 F1 F2 ... F15 : file system events
        reflexes: [nrows][ncols]?Reflex = [nrows][ncols]?Reflex {
            [_]?Reflex{null} ** ncols,
            [_]?Reflex{null} ** ncols,
            [_]?Reflex{null} ** ncols,
            [_]?Reflex{null} ** ncols,
            [_]?Reflex{null} ** ncols,
        },

//        sm: *StageMachine = undefined,

        pub fn setReflex(self: *Stage, code: u8, refl: Reflex) void {
            const row: u8 = code >> 4;
            const col: u8 = code & 0x0F;
            // const sm = @fieldParentPtr(StageMachine, "stages", self);
            if (self.reflexes[row][col]) |_| {
//                print("{s}/{s} already has relfex for '{c}{}'\n", .{self.sm.name, self.name, esk_tags[row], seqn});
                // return error ?
                unreachable;
            }
            self.reflexes[row][col] = refl;
        }
    };

    pub fn init(md: *MessageDispatcher, name: []const u8, stages: []const Stage) StageMachine {
        var sm = StageMachine {
            .name = name,
            .md = md,
        };
        for (stages) |stage, k| {
            sm.stages[k] = stage;
        }
        sm.n_stages = stages.len;
        return sm;
    }

    /// state machine engine
    pub fn reactTo(self: *Self, msg: Message) void {
        const row = msg.code >> 4;
        const col = msg.code & 0x0F;
        const current = self.current;

        var sender = if (msg.src) |s| s.name else "OS";
        if (msg.src == self) sender = "SELF";

        print (
            "{s} @ {s} got '{c}{}' from {s}\n",
            .{self.name, self.stages[current].name, Stage.esk_tags[row], col, sender}
        );

        if (self.stages[current].reflexes[row][col]) |refl| {
            switch (refl) {
                .action => |func| func(self, msg.src, msg.ptr),
                .transition => |next| {
                    if (self.stages[current].leave) |func| {
                        func(self);
                    }
                    self.current = next;
                    if (self.stages[next].enter) |func| {
                        func(self);
                    }
                },
            }
        } else {
            print (
                "\n{s} @ {s} : no reflex for '{c}{}'\n",
                .{self.name, self.stages[current].name, Stage.esk_tags[row], col}
            );
            unreachable;
        }
    }

    pub fn msgTo(self: *Self, dst: ?*Self, code: u4, data: ?*anyopaque) void {
        const msg = Message {
            .src = self,
            .dst = dst,
            .code = code,
            .ptr = data,
        };
        // message buffer is not growable so this will panic
        // when there is no more space left in the buffer
        self.md.mq.put(msg) catch unreachable;
    }

    pub fn run(self: *Self) !void {

        if (0 == self.n_stages)
            return Error.HasNoStates;
        if (self.is_running)
            return Error.IsAlreadyRunning;

        var k: u32 = 0;
        while (k < self.n_stages) : (k += 1) {
            const stage = &self.stages[k];
            var row: u8 = 0;
            var cnt: u8 = 0;
            while (row < Stage.nrows) : (row += 1) {
                var col: u8 = 0;
                while (col < Stage.ncols) : (col += 1) {
                    if (stage.reflexes[row][col] != null)
                        cnt += 1;
                }
            }
            if (0 == cnt) {
                print("stage '{s}' of '{s}' has no reflexes\n", .{stage.name, self.name});
                return Error.StageHasNoReflexes;
            }
        }

        if (self.stages[self.current].enter) |hello| {
            hello(self);
        }
        self.is_running = true;
    }
};
