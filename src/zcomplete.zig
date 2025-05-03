pub const options = @import("options");
pub const backend = switch (options.backend) {
    .clap => @import("backend"),
    .no_backend => struct {},
};
const std = @import("std");
pub const linker_section_name = ".zcomplete";

pub const AutoComplete = struct {
    id: i32,
    allocator: std.mem.Allocator,
    args: []const [:0]const u8,
    response: Response.Options = .unknown,

    pub fn respond(self: *@This(), opt: Response.Options) void {
        self.response = opt;
    }
    pub fn serialize(self: *@This()) *Response.Serialized {
        return self.response.serialize(self.allocator);
    }
};

pub const Run = fn (*AutoComplete) void;

pub const Args = packed struct {
    offset: i32,
    len: i32,
};

pub const Response = struct {
    pub const Options = union(enum(i32)) {
        unknown,
        fill_options: []const []const u8,
        _,

        pub fn fillOptions(fo: []const []const u8) @This() {
            return .{ .fill_options = fo };
        }

        pub fn serialize(self: *@This(), gpa: std.mem.Allocator) *Serialized {
            const header_size = @sizeOf(Serialized);
            var acc = std.ArrayListUnmanaged(u8).initCapacity(
                gpa,
                header_size,
            ) catch unreachable;
            acc.appendNTimesAssumeCapacity(0, header_size);
            const res: *Serialized = @alignCast(@ptrCast(acc.items.ptr));
            res.offset = header_size;
            acc.appendSlice(gpa, &@as([4]u8, @bitCast(@intFromEnum(self.*)))) catch unreachable;
            switch (self.*) {
                .unknown => {},
                .fill_options => |opts| {
                    for (opts) |opt| {
                        acc.appendSlice(gpa, opt) catch unreachable;
                        acc.append(gpa, 0) catch unreachable;
                    }
                },
                else => {},
            }
            res.len = @intCast(acc.items.len - header_size);
            return res;
        }
    };
    pub const Serialized = packed struct {
        offset: i32,
        len: i32,
        pub fn parse(self: *@This(), gpa: std.mem.Allocator) *Options {
            const acc = gpa.create(Options) catch unreachable;
            acc.* = .unknown;
            var ptr: [*]u8 = @alignCast(@ptrCast(self));
            const slice = ptr[@intCast(self.offset)..@intCast(self.offset + self.len)];
            std.log.err("xxxx: {x}", .{slice});
            const tag: i32 = @as(*i32, @alignCast(@ptrCast(slice[0..4]))).*;
            const tag_enum: std.meta.Tag(Options) = @enumFromInt(tag);
            switch (tag_enum) {
                .unknown => acc.* = .unknown,
                .fill_options => {
                    var array = std.ArrayListUnmanaged([]const u8).empty;
                    var last_zero: usize = 0;
                    for (slice[4..], 0..) |c, i| {
                        if (c == 0) {
                            array.append(gpa, slice[4 + last_zero .. 4 + i]) catch unreachable;
                            last_zero = i;
                        }
                    }
                    acc.* = .{ .fill_options = array.toOwnedSlice(gpa) catch unreachable };
                },
                else => {},
            }
            return acc;
        }
    };
};

pub fn pack_args(args: []const []const u8, out: []u8) void {
    var pos: usize = 0;
    for (args) |arg| {
        @memcpy(out[pos .. pos + arg.len], arg);
        pos += arg.len;
        out[pos] = 0;
        pos += 1;
    }
}
