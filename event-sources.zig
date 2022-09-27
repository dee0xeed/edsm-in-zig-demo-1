
const std = @import("std");

const timerFd = std.os.timerfd_create;
const timerFdSetTime = std.os.timerfd_settime;
const TimeSpec = std.os.linux.timespec;
const ITimerSpec = std.os.linux.itimerspec;

const signalFd  = std.os.signalfd;
const sigProcMask = std.os.sigprocmask;
const SigSet = std.os.sigset_t;
const SIG = std.os.SIG;
const SigInfo = std.os.linux.signalfd_siginfo;

const edsm = @import("edsm.zig");
const StageMachine = edsm.StageMachine;
const ecap = @import("event-capture.zig");

pub const EventSourceKind = enum {
    sm,
    io,
    sg,
    tm,
    fs,
};

/// this is for i/o kind
pub const EventSourceSubKind = enum {
    none,
    x,
    y,
    z,
};

pub const IoInfo = struct {
    bytes_avail: u32 = 0,
};

pub const TimerInfo = struct {
    nexp: u64 = 0,
};

pub const SignalInfo = struct {
    sig_info: SigInfo = undefined,
};

pub const EventSourceInfo = union(EventSourceKind) {
    sm: void,
    io: IoInfo,
    sg: SignalInfo,
    tm: TimerInfo,
    fs: void,
};

pub const EventSource = struct {

    const Self = @This();
    kind: EventSourceKind,
    subkind: EventSourceSubKind,
    id: i32 = -1, // fd in most cases, but not always
    owner: *StageMachine,
    seqn: u4 = 0,
    info: EventSourceInfo,

    pub fn init(
        owner: *StageMachine,
        esk: EventSourceKind,
        essk: EventSourceSubKind,
        seqn: u4
    ) EventSource {
        if ((esk != .io) and (essk != .none)) unreachable;
        return EventSource {
            .kind = esk,
            .subkind = essk,
            .owner = owner,
            .seqn = seqn,
            .info = switch (esk) {
                .io => EventSourceInfo{.io = IoInfo{}},
                .sg => EventSourceInfo{.sg = SignalInfo{}},
                .tm => EventSourceInfo{.tm = TimerInfo{}},
                else => unreachable,
            }
        };
    }

    fn getTimerId() !i32 {
        return try timerFd(std.os.CLOCK.REALTIME, 0);
    }

    fn getSignalId(signo: u6) !i32 {
        var sset: SigSet = std.os.empty_sigset;
        // block the signal
        std.os.linux.sigaddset(&sset, signo);
        sigProcMask(SIG.BLOCK, &sset, null);
        return signalFd(-1, &sset, 0);
    }

    pub fn getId(self: *Self, args: anytype) !void {
        self.id = switch (self.kind) {
            .io => 0,
            .sg => if (1 == args.len) try getSignalId(args[0]) else unreachable,
            .tm => if (0 == args.len) try getTimerId() else unreachable,
            else => unreachable,
        };
    }

    fn setTimer(id: i32, msec: u32) !void {
        const its = ITimerSpec {
            .it_interval = TimeSpec {
                .tv_sec = 0,
                .tv_nsec = 0,
            },
            .it_value = TimeSpec {
                .tv_sec = msec / 1000,
                .tv_nsec = (msec % 1000) * 1000 * 1000,
            },
        };
        try timerFdSetTime(id, 0, &its, null);
    }

    pub fn enable(self: *Self, eq: *ecap.EventQueue, args: anytype) !void {
        try eq.enableCanRead(self);
        if (self.kind == .tm)
            if (1 == args.len)
                try setTimer(self.id, args[0])
            else
                unreachable;
    }

    fn readTimerInfo(self: *Self) !void {
        var p1 = switch (self.kind) {
            .tm => &self.info.tm.nexp,
            else => unreachable,
        };
        var p2 = @ptrCast([*]u8, @alignCast(@alignOf([*]u8), p1));
        var buf = p2[0..@sizeOf(TimerInfo)];
        _ = try std.os.read(self.id, buf[0..]);
    }

    fn readSignalInfo(self: *Self) !void {
        var p1 = switch (self.kind) {
            .sg => &self.info.sg.sig_info,
            else => unreachable,
        };
        var p2 = @ptrCast([*]u8, @alignCast(@alignOf([*]u8), p1));
        var buf = p2[0..@sizeOf(SigInfo)];
        _ = try std.os.read(self.id, buf[0..]);
    }

    pub fn readInfo(self: *Self) !void {
        switch (self.kind) {
            .sg => try readSignalInfo(self),
            .tm => try readTimerInfo(self),
            else => return,
        }
    }
};
