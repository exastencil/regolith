const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const mod = b.addModule("regolith", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Example tests: examples/components/reusable.zig imports "regolith"
    const example_mod = b.addModule("examples", .{
        .root_source_file = b.path("examples/components/reusable.zig"),
        .target = target,
    });
    example_mod.addImport("regolith", mod);
    const example_tests = b.addTest(.{ .root_module = example_mod });
    const run_example_tests = b.addRunArtifact(example_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_example_tests.step);
}
