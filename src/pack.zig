//! These algorithms are messy and written by trial and error.
//! I wrote as many tests as I could but watch out for weird edge cases.

const std = @import("std");

/// Running with comptime-known argument is strongly recommended.
pub fn packSizeNeeded(unpacked_size: usize) usize {
    return std.math.divCeil(usize, unpacked_size * 8, 7) catch unreachable;
}

/// Running with comptime-known argument is strongly recommended.
pub fn unpackSizeNeeded(packed_size: usize) usize {
    return std.math.divCeil(usize, packed_size * 7, 8) catch unreachable;
}

/// Caller must make sure `buffer` has enough room.
pub fn pack(data: []const u8, buffer: []u8) []u8 {
    var p = Packer.init(buffer);
    p.write(data);
    return p.getWritten();
}

/// Caller must make sure `buffer` has enough room.
pub fn unpack(data: []const u8, buffer: []u8) []u8 {
    var u = Unpacker.init(buffer);
    u.write(data);
    return u.getWritten();
}

/// 7-bit to 8-bit converter.
pub const Unpacker = struct {
    buffer: []u8,
    index: usize,
    bit_index: u3,

    pub fn init(buffer: []u8) Unpacker {
        return .{ .buffer = buffer, .index = 0, .bit_index = 7 };
    }

    pub fn write(self: *Unpacker, data: []const u8) void {
        for (data) |byte| {
            if (self.bit_index != 7) {
                self.buffer[self.index - 1] |= byte >> self.bit_index;
            }
            if (self.bit_index != 0) {
                self.buffer[self.index] = byte << (7 - self.bit_index + 1);
                self.index += 1;
            }
            self.bit_index -%= 1;
        }
    }

    pub fn writeByte(self: *Unpacker, byte: u8) void {
        self.write(std.mem.asBytes(&byte));
    }

    pub fn getWritten(self: Unpacker) []u8 {
        return self.buffer[0..self.index];
    }
};

/// 8-bit to 7-bit converter.
pub const Packer = struct {
    buffer: []u8,
    index: usize,
    bit_index: u3,

    pub fn init(buffer: []u8) Packer {
        return .{ .buffer = buffer, .index = 1, .bit_index = 1 };
    }

    pub fn write(self: *Packer, data: []const u8) void {
        for (data) |byte| {
            if (self.bit_index == 1) {
                self.buffer[self.index - 1] = 0;
            }
            self.buffer[self.index - 1] |= byte >> self.bit_index;
            if (self.bit_index != 7) {
                self.buffer[self.index] = (byte << (7 - self.bit_index + 1)) >> 1;
                self.bit_index += 1;
            } else {
                self.buffer[self.index] = byte & 0x7f;
                self.bit_index = 1;
                self.index += 1;
            }
            self.index += 1;
        }
    }

    pub fn writeByte(self: *Packer, byte: u8) void {
        self.write(std.mem.asBytes(&byte));
    }

    pub fn getWritten(self: Packer) []u8 {
        return self.buffer[0 .. self.index - @boolToInt(self.bit_index == 1)];
    }
};

/// -- Tests --
/// 'Even' means an array of 8n 7-bit bytes OR an array of 7n 8-bit bytes.
/// Un/packing even arrays is invertible, i.e. pack(unpack(even_array)) == unpack(pack(even_array)) == even_array.
usingnamespace struct {
    const testing = std.testing;

    const test_packed_even = [_]u8{ 0b01100000, 0b00110000, 0b00011000, 0b00001100, 0b00000110, 0b00000011, 0b00000001, 0b01000000 };
    const test_unpacked_even = [_]u8{0xc0} ** 7;

    const test_packed_uneven = [_]u8{ 0b0_0011001, 0b0_1001100, 0b0_1100000 };
    const test_packed_uneven_expected = [_]u8{ 0b0011_0011, 0b0011_0011, 0b0000_0000 };

    const test_unpacked_uneven = [_]u8{ 0b1111_0000, 0b0110_0110, 0b1010_1010 };
    const test_unpacked_uneven_expected = [_]u8{ 0b0_1111000, 0b0_0011001, 0b0_1010101, 0b0_0100000 };

    fn testUnpack(input: []const u8, expected: []const u8, mode: enum { write, writeByte }) !void {
        var buffer = try testing.allocator.alloc(u8, unpackSizeNeeded(input.len));
        defer testing.allocator.free(buffer);
        const unpacked = switch (mode) {
            .write => unpack(input, buffer),
            .writeByte => blk: {
                var u = Unpacker.init(buffer);
                for (input) |b| u.writeByte(b);
                break :blk u.getWritten();
            },
        };
        try testing.expectEqualSlices(u8, expected, unpacked);
        try testing.expectEqualSlices(u8, expected, buffer[0..]);
    }

    fn testPack(input: []const u8, expected: []const u8, mode: enum { write, writeByte }) !void {
        var buffer = try testing.allocator.alloc(u8, packSizeNeeded(input.len));
        defer testing.allocator.free(buffer);
        const packed_ = switch (mode) {
            .write => pack(input, buffer),
            .writeByte => blk: {
                var p = Packer.init(buffer);
                for (input) |b| p.writeByte(b);
                break :blk p.getWritten();
            },
        };
        try testing.expectEqualSlices(u8, expected, packed_);
        try testing.expectEqualSlices(u8, expected, buffer[0..]);
    }

    // Uneven data
    test "unpack uneven" {
        try testUnpack(test_packed_uneven[0..], test_packed_uneven_expected[0..], .write);
        try testUnpack(test_packed_uneven[0..], test_packed_uneven_expected[0..], .writeByte);
    }
    test "pack uneven" {
        try testPack(test_unpacked_uneven[0..], test_unpacked_uneven_expected[0..], .write);
        try testPack(test_unpacked_uneven[0..], test_unpacked_uneven_expected[0..], .writeByte);
    }

    // Even data
    test "unpack even" {
        try testUnpack(test_packed_even[0..], test_unpacked_even[0..], .write);
        try testUnpack(test_packed_even[0..], test_unpacked_even[0..], .writeByte);
    }
    test "pack even" {
        try testPack(test_unpacked_even[0..], test_packed_even[0..], .write);
        try testPack(test_unpacked_even[0..], test_packed_even[0..], .writeByte);
    }

    test "pack is invertible" {
        const input_size = 14;
        std.debug.assert(input_size % 7 == 0);

        // Random input
        const input = input: {
            var prng = std.rand.DefaultPrng.init(blk: {
                var seed: u64 = undefined;
                try std.os.getrandom(std.mem.asBytes(&seed));
                break :blk seed;
            });
            const rand = &prng.random;
            var buffer: [input_size]u8 = undefined;
            rand.bytes(buffer[0..]);
            break :input buffer;
        };

        var pack_buffer: [packSizeNeeded(input_size)]u8 = undefined;
        var unpack_buffer: [input_size]u8 = undefined;

        std.debug.assert(unpack_buffer.len == unpackSizeNeeded(pack_buffer.len));

        const packed_ = pack(input[0..], pack_buffer[0..]);
        const unpacked = unpack(packed_, unpack_buffer[0..]);

        try testing.expectEqualSlices(u8, input[0..], unpacked);
    }

    test "unpack is invertible" {
        const input_size = 16;
        std.debug.assert(input_size % 8 == 0);

        // Random input
        const input = input: {
            var prng = std.rand.DefaultPrng.init(blk: {
                var seed: u64 = undefined;
                try std.os.getrandom(std.mem.asBytes(&seed));
                break :blk seed;
            });
            const rand = &prng.random;
            var buffer: [input_size]u8 = undefined;
            rand.bytes(buffer[0..]);
            for (buffer) |*b| b.* &= 0x7f;
            break :input buffer;
        };

        var unpack_buffer: [unpackSizeNeeded(input_size)]u8 = undefined;
        var pack_buffer: [input_size]u8 = undefined;

        std.debug.assert(pack_buffer.len == packSizeNeeded(unpack_buffer.len));

        const unpacked = unpack(input[0..], unpack_buffer[0..]);
        const packed_ = pack(unpacked, pack_buffer[0..]);

        try testing.expectEqualSlices(u8, input[0..], packed_);
    }
};
