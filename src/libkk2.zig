const std = @import("std");
const log10_2 = @log10(2.0);
const expect = std.testing.expect;

pub const InstructionType = enum(u4) {
    LOD = 0,
    MOV = 1,
    ADD = 2,
    MUL = 3,
    DIV = 4,
    SUB = 5,
    SET = 6,
    GET = 7,
    JWC = 8,
    CEQ = 9,
    CTX,
    LCX,
};
pub const InstructionInput = union(enum) {
    Register: u4,
    StaticValue: u40,
};
pub const Instruction = struct {
    type: InstructionType,
    register: u4,
    input: InstructionInput,
    pub fn toDecimal(self: *const Instruction) u40 {
        return switch (self.type) {
            .LCX => LCX: {
                var decimal: u40 = 701000000000;
                decimal += self.register * std.math.pow(u40, 10, 10);
                decimal += self.input.StaticValue;

                break :LCX decimal;
            },
            .CTX => CTX: {
                var decimal: u40 = 801000000000;

                decimal += self.register * std.math.pow(u40, 10, 10);
                decimal += self.input.StaticValue;

                break :CTX decimal;
            },
            else => normal: {
                var decimal: u40 = switch (self.type) {
                    .LOD => @intCast(self.input.StaticValue),
                    else => @intCast(self.input.Register),
                };

                decimal += self.register * std.math.pow(u40, 10, 10);
                decimal += @intFromEnum(self.type) * std.math.pow(u40, 10, 11);

                break :normal decimal;
            },
        };
    }
    fn toDecimalText(self: *const Instruction) void {
        var buf = [12]u8;
        try std.fmt.bufPrint(&buf, "{d:012}", .{self.toDecimal()});
    }
};

pub fn getIntSize(bits: usize) usize {
    const bits_as_float: f32 = @floatFromInt(bits);
    return @intFromFloat(@ceil((bits_as_float * log10_2) / 12));
}

pub fn simulate(code: []u40) ![12]u40 {
    var ptr: usize = 0;
    var regs = std.mem.zeroes([12]u40);
    while (true) {
        var instr = code[ptr];
        const opcode = instr / std.math.pow(u40,10,11);
        instr -= opcode * std.math.pow(u40,10,11);
        const register = instr / std.math.pow(u40, 10, 10);
        const input = instr - (register * std.math.pow(u40, 10, 10));
        
        //std.debug.print("opcode: {d}, register: {d}, input: {d} regs: {any}\n", .{opcode, register, input, regs});
        switch (opcode) {
            0 => {
                regs[@intCast(register)] = input;
            },
            1 => {
                regs[@intCast(register)] = regs[@intCast(input)];
            },
            2 => {
                regs[@intCast(register)] += regs[@intCast(input)];
            },
            3 => {
                regs[@intCast(register)] *= regs[@intCast(input)];
            },
            4 => {
                regs[@intCast(register)] /= regs[@intCast(input)];
            },
            5 => {
                regs[@intCast(register)] -= regs[@intCast(input)];
            },
            6 => {
                code[@intCast(regs[@intCast(input)])] = regs[@intCast(register)];
            },
            7 => {
                const sd = input / std.math.pow(u40, 10, 9);
                if (sd == 1) {
                    return error.ContextsNotSupported;
                } else {
                    regs[@intCast(register)] = code[@intCast(regs[@intCast(input)])];
                }
            },
            8 => {
                const sd = input / std.math.pow(u40, 10, 9);
                if (sd == 1) {
                    return error.ContextsNotSupported;
                } else if (regs[@intCast(register)] > 0) {
                    ptr = regs[@intCast(input)] - 1;
                }
            },
            9 => {
                regs[9] = @intFromBool(regs[@intCast(register)] == regs[@intCast(input)]);
            },
            else => {
                return error.InvalidOpcode;
            }
        }
        ptr += 1;
        if (ptr >= code.len) {
            break;
        }
    }
    return regs;
}

test "Integer size" {
    try expect(getIntSize(8) == 1);
    try expect(getIntSize(16) == 1);
    try expect(getIntSize(32) == 1);
    try expect(getIntSize(64) == 2);
    try expect(getIntSize(128) == 4);
    try expect(getIntSize(256) == 7);
}

test "Instruction representations" {
    const LOD_0_69 = Instruction{ .type = .LOD, .register = 0, .input = .{ .StaticValue = 69 } };
    const MOV_3_4 = Instruction{ .type = .MOV, .register = 3, .input = .{ .Register = 4 } };
    const ADD_9_7 = Instruction{ .type = .ADD, .register = 9, .input = .{ .Register = 7 } };
    const CTX_2_55 = Instruction{ .type = .CTX, .register = 2, .input = .{ .StaticValue = 55 } };

    try expect(LOD_0_69.toDecimal() == 69);
    try expect(MOV_3_4.toDecimal() == 130000000004);
    try expect(ADD_9_7.toDecimal() == 290000000007);
    try expect(CTX_2_55.toDecimal() == 821000000055);
}

test "Simulation test" {
    var code = [_]u40 {
        1,
        10000000001,
        20000000042,
        40000000001,
        50000000005,
        130000000001,
        210000000000,
        100000000001,
        100000000003,
        520000000004,
        820000000005,
    };
    const regs = try simulate(&code);
    std.debug.print("Regs: {any}\n", .{regs});
    try expect(regs[0] == 433494437);
}
