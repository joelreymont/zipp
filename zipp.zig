const std = @import("std");

const io = std.io;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;

const zipp = @This();

pub const Error = error{InvalidNewline} || mem.Allocator.Error;

pub fn Pretty(comptime _T: type) type {
    return struct {
        const T = _T;
        const Self = @This();

        pp: T,

        fn width(self: Self) Width {
            return self.pp.width();
        }

        fn print(self: Self, state: *State, writer: anytype) Error!void {
            return self.pp.print(state, writer);
        }
    };
}

const State = struct {
    width: usize,
    ribbon: usize,
    last_indent: usize,
    line: usize,
    column: usize,
    flatten: bool,

    const Self = @This();

    pub fn init(frac: f32, width: usize) Self {
        const w = @as(f32, @floatFromInt(width));
        const fw = @as(usize, @intFromFloat(@trunc(w * frac)));
        return .{
            .last_indent = 0,
            .flatten = false,
            .line = 0,
            .column = 0,
            .width = width,
            .ribbon = @max(0, @min(width, fw)),
        };
    }
};

const Empty = struct {
    const Self = @This();

    fn width(_: Self) Width {
        return .{ .width = 0 };
    }

    fn print(_: Self, _: *State, _: anytype) Error!void {}
};

const empty = Pretty(Empty){ .pp = Empty{} };

const Char = struct {
    c: u8,

    const Self = @This();

    fn width(_: Self) Width {
        return .{ .width = 1 };
    }

    fn print(self: Self, state: *State, writer: anytype) Error!void {
        const s = [_]u8{self.c};
        _ = try writer.write(&s);
        state.column += 1;
    }
};

pub fn char(comptime c: u8) Pretty(Char) {
    if (c == '\n')
        @compileError("Newline is invalid!");
    return Pretty(Char){ .pp = Char{ .c = c } };
}

pub const space = char(' ');

const Text = struct {
    s: []const u8,

    const Self = @This();

    fn width(self: Self) Width {
        return .{ .width = self.s.len };
    }

    fn print(self: Self, state: *State, writer: anytype) Error!void {
        _ = try writer.write(self.s);
        state.column += self.s.len;
    }
};

pub fn text(comptime s: []const u8) Pretty(Text) {
    return Pretty(Text){ .pp = Text{ .s = s } };
}

const Hardline = struct {
    const Self = @This();

    fn width(_: Self) Width {
        return .infinity;
    }

    fn print(_: Self, state: *State, writer: anytype) Error!void {
        std.debug.assert(!state.flatten);
        writer.write([_]u8{'\n'});
        blanks(writer, state.indent);
        state.line += 1;
        state.column = state.indent;
    }
};

const hardline = Pretty(Hardline){ .pp = Hardline{} };

const Blank = struct {
    n: usize,

    const Self = @This();

    fn width(self: Self) Width {
        return Width{ .width = self.n };
    }

    fn print(self: Self, state: *State, writer: anytype) Error!void {
        blanks(writer, self.n);
        state.column += self.n;
    }
};

pub fn blank(comptime n: usize) Pretty(Blank) {
    return Pretty(Blank){ .pp = Blank{ .n = n } };
}

pub fn Group(comptime printers: anytype) type {
    return struct {
        const Self = @This();

        fn width(_: Self) Width {
            var w = Width{ .width = 0 };
            inline for (printers) |p| {
                w.add(p.width());
            }
            return w;
        }

        fn print(self: Self, state: *State, writer: anytype) Error!void {
            const flatten = state.flatten;
            defer state.flatten = flatten;
            var w = Width{ .width = state.column };
            w.add(self.width());
            const column = w.width;
            state.flatten = state.flatten or
                (column <= state.width and column <= state.last_indent + state.ribbon);
            inline for (printers) |p| {
                try p.print(state, writer);
            }
        }
    };
}

pub fn group(comptime printers: anytype) Pretty(Group(printers)) {
    const T = Group(printers);
    return Pretty(T){ .pp = T{} };
}

test "group" {
    const a = testing.allocator;
    const L = std.ArrayList(u8);
    var list = L.init(a);
    defer list.deinit();
    const pp = group(.{ text("["), char(' '), text("]") });
    var state = State.init(0.5, 80);
    try pp.print(&state, list.writer());
    try testing.expectEqual(3, list.items.len);
    const expect = "[ ]";
    try testing.expectEqualSlices(u8, expect, list.items);
}

pub fn Concat(comptime printers: anytype) type {
    return struct {
        const Self = @This();

        fn width(_: Self) Width {
            var w = Width{ .width = 0 };
            inline for (printers) |p| {
                w.add(p.width());
            }
            return w;
        }

        fn print(_: Self, state: *State, writer: anytype) Error!void {
            inline for (printers) |p| {
                try p.print(state, writer);
            }
        }
    };
}

pub fn concat(comptime printers: anytype) Pretty(Concat(printers)) {
    const T = Concat(printers);
    return Pretty(T){ .pp = T{} };
}

test "concat empty" {
    const a = testing.allocator;
    const L = std.ArrayList(u8);
    var list = L.init(a);
    defer list.deinit();
    const pp = concat(.{empty});
    var state = State.init(0.5, 80);
    try pp.print(&state, list.writer());
    try testing.expectEqual(0, list.items.len);
}

pub fn IfFlat(comptime left: anytype, comptime right: anytype) type {
    return struct {
        const Self = @This();

        fn width(_: Self) Width {
            return left.width();
        }

        fn print(_: Self, state: *State, writer: anytype) Error!void {
            const pp = if (state.flatten) left else right;
            pp.print(state, writer);
        }
    };
}

pub fn ifflat(comptime left: anytype, comptime right: anytype) Pretty(IfFlat(left, right)) {
    const T = IfFlat(left, right);
    return Pretty(T){ .pp = T{} };
}

pub fn newline(comptime n: usize) Pretty(IfFlat(Blank, Hardline)) {
    return ifflat(blank(n), hardline);
}

pub fn Nest(comptime n: usize, pp: anytype) type {
    return struct {
        const Self = @This();

        fn width() Width {
            return pp.width();
        }

        fn print(_: Self, state: *State, writer: anytype) Error!void {
            const indent = state.indent;
            defer state.indent = indent;
            state.indent += n;
            try pp.print(state, writer);
        }
    };
}

pub fn nest(comptime n: usize, pp: anytype) Pretty(Nest(n, pp)) {
    const T = Nest(n, pp);
    return Pretty(T){ .pp = T{} };
}

pub fn Lineup(comptime pp: anytype) type {
    return struct {
        const Self = @This();

        fn width(_: Self) Width {
            return pp.width();
        }

        fn print(_: Self, state: *State, writer: anytype) Error!void {
            const indent = state.indent;
            defer state.indent = indent;
            state.indent = state.column;
            try pp.print(state, writer);
        }
    };
}

pub fn lineup(comptime pp: anytype) Pretty(Lineup(pp)) {
    const T = Lineup(pp);
    return Pretty(T){ .pp = T{} };
}

pub fn twice(comptime pp: Pretty) Pretty(Concat(.{ pp, pp })) {
    return concat(.{ pp, pp });
}

pub fn Repeat(comptime n: usize, comptime pp: anytype) type {
    const T = @TypeOf(pp);
    comptime var a: [n]T = undefined;
    for (0..n) |i|
        a[i] = pp;
    return Concat(a);
}

pub fn repeat(comptime n: usize, comptime pp: anytype) Pretty(Repeat(n, pp)) {
    const T = Repeat(n, pp);
    return Pretty(T){ .pp = T{} };
}

test "repeat" {
    const a = testing.allocator;
    const L = std.ArrayList(u8);
    var list = L.init(a);
    defer list.deinit();
    const pp = repeat(2, space);
    var state = State.init(0.5, 80);
    try pp.print(&state, list.writer());
    try testing.expectEqual(2, list.items.len);
}

fn sepTypes(comptime sep: anytype, comptime printers: anytype) []const type {
    if (printers.len == 0)
        @compileError("No printers supplied!");

    var types: []const type = &[_]type{};

    if (printers.len == 1) {
        types = types ++ [_]type{@TypeOf(printers[0])};
        return types;
    }

    const len = printers.len;

    for (0..len - 1) |i| {
        types = types ++ [_]type{@TypeOf(printers[i])};
        types = types ++ [_]type{@TypeOf(sep)};
    }

    return types ++ [_]type{@TypeOf(printers[len - 1])};
}

pub fn Separate(comptime sep: anytype, comptime printers: anytype) type {
    return Concat(sepTypes(sep, printers));
}

pub fn separate(comptime sep: anytype, comptime printers: anytype) Pretty(Separate(sep, printers)) {
    const T = Concat(sepTypes(sep, printers));
    return Pretty(T){ .pp = T{} };
}

test "separate" {
    const a = testing.allocator;
    const L = std.ArrayList(u8);
    var list = L.init(a);
    const pp1 = separate(space, .{text("1")});
    var state1 = State.init(0.5, 80);
    try pp1.print(&state1, list.writer());
    try testing.expectEqual(1, list.items.len);
    const expect1 = "1";
    try testing.expectEqualSlices(u8, expect1, list.items);
    list.deinit();
    list = L.init(a);
    const pp2 = separate(space, .{ text("1"), text("2") });
    var state2 = State.init(0.5, 80);
    try pp2.print(&state2, list.writer());
    try testing.expectEqual(3, list.items.len);
    const expect2 = "1 2";
    try testing.expectEqualSlices(u8, expect2, list.items);
    list.deinit();
}

const Width = union(enum) {
    width: usize,
    infinity: void,

    const Self = @This();

    fn add(self: *Self, w: Self) void {
        if (self.* == .infinity or w == .infinity)
            self.* = .infinity
        else
            self.* = .{ .width = self.width + w.width };
    }
};

const blank_len = 80;

const blank_buf = [_]u8{' '} ** blank_len;

fn blanks(writer: anytype, n: usize) !void {
    var x = n;
    while (x > blank_len) : (x -= blank_len) {
        _ = try writer.write(&blank_buf);
    }
    if (x == 0)
        return;
    _ = try writer.write(blank_buf[0..x]);
}

test "blanks" {
    const a = testing.allocator;
    const L = std.ArrayList(u8);
    var list = L.init(a);
    try blanks(list.writer(), 0);
    try testing.expectEqual(0, list.items.len);
    list.deinit();
    list = L.init(a);
    try blanks(list.writer(), blank_len);
    try testing.expectEqualSlices(u8, &blank_buf, list.items);
    list.deinit();
    list = L.init(a);
    try blanks(list.writer(), blank_len + 10);
    const want = [_]u8{' '} ** (blank_len + 10);
    try testing.expectEqualSlices(u8, &want, list.items);
    list.deinit();
}
