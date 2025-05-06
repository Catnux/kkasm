const std = @import("std");
const kk2 = @import("libkk2.zig");
const prepend_zon: struct {
    prepend: []const []const u8,
} = @import("prepend.zon");
const prepend = prepend_zon.prepend;
const rh = std.hash.CityHash32.hash;

const MarkUsage = struct {
    index: usize,
    mark_name: []const u8,
    subtract: u40,
};
pub const AssemblyContext = struct {
    code: std.ArrayList(u40),
    marks: std.StringHashMap(u40),
    register_aliases: std.StringHashMap(u4),
    constants: std.StringHashMap(u40),
    mark_usages: std.ArrayList(MarkUsage),
    fn init(allocator: std.mem.Allocator) AssemblyContext {
        return AssemblyContext {
            .code = std.ArrayList(u40).init(allocator),
            .marks = std.StringHashMap(u40).init(allocator),
            .register_aliases = std.StringHashMap(u4).init(allocator),
            .constants = std.StringHashMap(u40).init(allocator),
            .mark_usages = std.ArrayList(MarkUsage).init(allocator),
        };
    }
    fn toText(self: *AssemblyContext, allocator: std.mem.Allocator) ![]u8 {
        var out_text = std.ArrayList(u8).init(allocator);
        for (self.code.items) |bite| {
            var astext: [12]u8 = undefined;
            _ = try std.fmt.bufPrint(&astext, "{d:012}", .{bite});
            try out_text.appendSlice(&astext);
        }
        return try out_text.toOwnedSlice();
    }
    fn parseLine(self: *AssemblyContext, line: []const u8) !?u40 {
        var trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) return null;
        const sigil = trimmed[0];
        //std.debug.print("Sigil: {c}\n", .{sigil});

        switch (sigil) {
            '%' => {
                var alias_len: usize = 1;
                for (trimmed[1..]) |c| {
                    if (std.ascii.isWhitespace(c)) {
                        break;
                    } else {
                        alias_len += 1;
                    }
                }
                const alias_name = trimmed[1..alias_len];
                trimmed = std.mem.trim(u8, trimmed[alias_len..], &std.ascii.whitespace);
                //std.debug.print("Register: {s}, Name: '{s}'\n", .{trimmed[0..1], alias_name});
                try self.register_aliases.put(alias_name, try std.fmt.parseInt(u4, trimmed[0..1], 10));
                return null;
            },
            '.' => {
                var const_len: usize = 1;
                for (trimmed[1..]) |c| {
                    if (std.ascii.isWhitespace(c)) {
                        break;
                    } else {
                        const_len += 1;
                    }
                }
                const const_name = trimmed[1..const_len];
                trimmed = std.mem.trim(u8, trimmed[const_len..], &std.ascii.whitespace);
                try self.constants.put(const_name, try std.fmt.parseInt(u40, trimmed, 10));
                return null;
            },
            '#' => {
                var mark_len: usize = 1;
                for (trimmed[1..]) |c| {
                    if (std.ascii.isWhitespace(c)) {
                        break;
                    } else {
                        mark_len += 1;
                    }
                }
                const mark_name = trimmed[1..mark_len];
                trimmed = std.mem.trim(u8, trimmed[mark_len..], &std.ascii.whitespace);
                try self.marks.put(mark_name, @intCast(self.code.items.len));
                return null;
            },
            '+' => {
                var val_len: usize = 1;
                for (trimmed[1..]) |c| {
                    if (std.ascii.isWhitespace(c)) {
                        break;
                    } else {
                        val_len += 1;
                    }
                }
                const val = trimmed[1..val_len];
                trimmed = std.mem.trim(u8, trimmed[val_len..], &std.ascii.whitespace);
                try self.code.append(try std.fmt.parseInt(u40, val, 10));
                return self.code.items[self.code.items.len - 1];
            },
            else => { // No sigil
                if (std.meta.stringToEnum(kk2.InstructionType, trimmed[0..3])) |instruction_type| {
                    trimmed = std.mem.trim(u8, trimmed[3..], &std.ascii.whitespace);
                    var register: u4 = 0;
                    if (trimmed[0] == '%') {
                        var alias: []const u8 = trimmed[1..2];
                        while (true) {
                            trimmed = trimmed[1..];
                            if (std.ascii.isWhitespace(trimmed[0])) break;
                            alias.len += 1;
                        }
                        alias.len -= 1;
                        //std.debug.print("Alias: '{s}'\n", .{alias});
                        if (self.register_aliases.get(alias)) |reg| {
                            register = reg;
                        } else {
                            std.debug.print("'Register alias {s}' has not been defined yet!\n", .{alias});
                            return error.UndefinedRegister;
                        }
                    } else {
                        register = try std.fmt.parseInt(u4, trimmed[0..1], 10);
                        trimmed = trimmed[1..];
                        if (std.ascii.isDigit(trimmed[0])) {
                            std.debug.print("'{c}' is not a valid register! Please use an alias starting with % or a number 0-9\n", .{trimmed[0]});
                            return error.InvalidRegister;
                        }
                    }
                    trimmed = std.mem.trim(u8, trimmed, &std.ascii.whitespace);
                    const instruction = kk2.Instruction{ .type = instruction_type, .register = register, .input = switch (instruction_type) {
                        .LOD => .{ .StaticValue = sv: {
                            if (std.ascii.isDigit(trimmed[0])) {
                                break :sv try std.fmt.parseInt(u40, trimmed, 10);
                            } else if (trimmed[0] == '#') {
                                if (self.marks.get(trimmed[1..])) |mark_value| {
                                    break :sv mark_value;
                                } else {
                                    try self.mark_usages.append(.{
                                        .index = self.code.items.len,
                                        .mark_name = trimmed[1..],
                                        .subtract = 0,
                                    });
                                    break :sv 0;
                                }
                            } else if (trimmed[0] == '.') {
                                if (self.constants.get(trimmed[1..])) |const_value| {
                                    break :sv const_value;
                                } else {
                                    std.debug.print("Constant: '{s}' has not been defined yet!\n", .{trimmed[1..]});
                                    return error.InvalidConstant;
                                }
                            } else {
                                std.debug.print("Sigil '{c}' is not valid!\n", .{trimmed[0]});
                                return error.InvalidSigil;
                            }
                        } },
                        else => .{ .Register = rv: {
                            if (std.ascii.isDigit(trimmed[0])) {
                                break :rv try std.fmt.parseInt(u4, trimmed, 10);
                            } else if (trimmed[0] == '%') {
                                if (self.register_aliases.get(trimmed[1..])) |alias_value| {
                                    break :rv alias_value;
                                } else {
                                    return error.InvalidRegister;
                                }
                            } else {
                                std.debug.print("Sigil '{c}' is not valid!\n", .{trimmed[0]});
                                return error.InvalidSigil;
                            }
                        } },
                    } };
                    try self.code.append(instruction.toDecimal());
                    return self.code.items[self.code.items.len - 1];
                } else {
                    std.debug.print("Instruction: {s} is not valid!\n", .{trimmed[0..3]});
                    return error.InvalidInstruction;
                }
            },
        }
    }
    fn resolveMarks(self: *AssemblyContext) !void {
        while (self.mark_usages.pop()) |usage| {
            if (self.marks.get(usage.mark_name)) |value| {
                self.code.items[usage.index] += value - usage.subtract;
            } else {
                std.debug.print("Mark '{s}' does not exist!\n", .{usage.mark_name});
                return error.InvalidMark;
            }
        }
    }
};

var cl_opts: struct {
    prepend_header: bool = true,
    check_only: bool = false,
    out_file: ?[]const u8 = null,
    stdout: bool = false,
} = .{};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    var args_it = try std.process.argsWithAllocator(allocator);
    var source_files = std.ArrayList([]const u8).init(allocator);
    defer source_files.deinit();
    var is_in_option = false;
    var co: u8 = 0;
    _ = args_it.next();
    while (args_it.next()) |arg| {
        if (arg[0] == '-') {
            if (arg[1] == '-') {
                switch (rh(arg[2..])) {
                    rh("no-prepend-header") => {
                        cl_opts.prepend_header = false;
                    },
                    rh("check-only") => {
                        cl_opts.check_only = true;
                    },
                    rh("stdout") => {
                        cl_opts.stdout = true;
                    },
                    rh("output") => {
                        is_in_option = true;
                        co = 'o';
                    },
                    else => {
                        std.debug.print("Unknown option: --{s}\n", .{arg[2..]});
                        return error.UnknownOption;
                    },
                }
            } else {
                for (arg[1..]) |option| {
                    switch (option) {
                        'p' => {
                            cl_opts.prepend_header = false;
                        },
                        'c' => {
                            cl_opts.check_only = true;
                        },
                        'o' => {
                            is_in_option = true;
                            co = 'o';
                        },
                        else => {
                            std.debug.print("Unknown option: -{c}\n", .{option});
                            return error.UnknownOption;
                        },
                    }
                }
            }
        } else if (is_in_option) {
            if (co == 'o') {
                cl_opts.out_file = arg;
            }
            is_in_option = false;
            co = 0;
        } else {
            try source_files.append(arg);
        }
    }

    var ctx = AssemblyContext.init(allocator);

    if (cl_opts.prepend_header) {
        for (prepend) |line| {
            _ = try ctx.parseLine(std.mem.trimRight(u8, line, &std.ascii.whitespace));
        }
    }

    for (source_files.items) |filepath| {
        const file = try std.fs.cwd().openFile(filepath, .{});
        const file_contents = try file.readToEndAlloc(allocator, std.math.pow(usize, 1024, 3));
        defer allocator.free(file_contents);
        var it = std.mem.splitScalar(u8, file_contents, ';');
        while (it.next()) |line| {
            if (line.len == 0) break;
            _ = try ctx.parseLine(std.mem.trimRight(u8, line, &std.ascii.whitespace));
        }
        try ctx.resolveMarks();
    }

    if (cl_opts.check_only) {
        _ = try ctx.toText(allocator);
        return;
    }

    if (cl_opts.stdout) {
        try stdout.writeAll(try ctx.toText(allocator));
    } else if (cl_opts.out_file) |out_file| {
        const of = try std.fs.cwd().createFile(out_file, .{});
        try of.writeAll(try ctx.toText(allocator));
    } else if (source_files.items.len == 1) {
        const is_kk = std.mem.endsWith(u8, source_files.items[0], ".kk");

        var name = try allocator.alloc(u8, source_files.items[0].len + @as(usize, if (is_kk) 1 else 4));
        std.mem.copyForwards(u8, name, source_files.items[0]);
        if (is_kk) {
            name[name.len - 1] = 'o';
        } else {
            @memcpy(name[name.len - 4..], ".kko");
        }

        const of = try std.fs.cwd().createFile(name, .{});
        try of.writeAll(try ctx.toText(allocator));
    } else if (source_files.items.len == 0) {
        std.debug.print("You need to actually assemble something.", .{});
        return error.NoSourceFilesProvided;
    } else {
        std.debug.print("If you provide more than one source file, you must also provide an output file using -o [file] or --output [file], or use --stdout\n", .{});
        return error.NoGoodOutputName;
    }
}
