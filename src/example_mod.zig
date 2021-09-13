const main = @import("./example.zig");
const pymodule = @import("./pymodule.zig");

comptime {
    pymodule.createModule("example_zig", main);
}
