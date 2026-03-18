const std = @import("std");
const preview = @import("preview.zig");

comptime {
    _ = preview;
}

extern fn merrow_studio_main(argc: c_int, argv: [*]const [*:0]const u8) callconv(.c) c_int;

pub fn main() u8 {
    const argv_slice = std.os.argv;
    const argc: c_int = @intCast(argv_slice.len);
    const result = merrow_studio_main(argc, @ptrCast(argv_slice.ptr));
    return if (result == 0) 0 else 1;
}
