const std = @import("std");
const zipp = @import("zipp");

const XML = union(enum) {
    elt: Elt,
    txt: []const u8,

    const Self = @This();

    fn width() zipp.Width {
        switch (Self) {
            .txt => |t| t.len,
            .elt => |e| e.width(),
        }
    }

    fn print(state: *zipp.State, writer: anytype) zipp.Error!void {
        
    }

    const Elt = struct {
        name: []const u8,
        att: []Att,
        xml: []Self,

        fn width() zipp.Width {
            var w = 
                for (e.att) |a| w += a.width(); 
                for (e.xml) |x| w += x.width(); 
            }
    };

    const Att = struct {
        name: []const u8,
        value: []const u8,
    };
};

test "xml" {
    const xml = .{
        .elt = .{
            .name = "p",
            .att = [_]XML.Att{
                .{ .name = "color", .value = "red" },
                .{ .name = "font", .value = "Times" },
                .{ .name = "size", .value = "10" },
            },
            .xml = []XML{
                .{ .txt = "Here is some" },
                .{
                    .elt = .{
                        .name = "em",
                        .att = .{},
                        .xml = .{ .txt = "emphasized" },
                    },
                },
                .{ .txt = "text" },
                .{ .txt = "Here is a" },
                .{
                    .elt = .{
                        .name = "a",
                        .att = .{.{ .name = "href", .value = "http://www.foo.com" }},
                        .xml = .{ .txt = "link" },
                    },
                },
                .{ .txt = "elsewhere" },
            },
        },
    };
}
