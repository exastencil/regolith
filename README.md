# Regolith

Status: scaffolding in place; README-driven design will guide the first implementation.

Purpose

- Regolith is a Zig library for building an HTML component tree on the server and rendering it to a string.
- Components form a tree. Each component owns its children; the root node is owned by the caller.
- The root component receives an allocator; all children use this allocator when they need to allocate.
- The library provides helpers to render a tree to HTML as a string and prebuilt helpers for common HTML tags.
- You can define reusable components (similar to React/Vue/Svelte) that accept options/state and build a subtree at runtime.

Design overview

- Ownership and lifetime
  - The root node is created by the caller with an allocator and is responsible for deinit.
  - Each node owns its children; deinit on a parent recursively deinitializes its subtree.
  - No node may outlive the root’s allocator lifetime. Callers own values passed into the tree unless explicitly transferred.
- Allocation model
  - The root’s allocator is the single allocator used by all children to keep lifetime simple and predictable.
  - Rendering to a string returns an owned slice allocated with the same allocator (caller frees it).
- Rendering
  - Helpers render a subtree to HTML into a growable buffer, returning a single string (with proper escaping).
  - A future streaming API may write to an arbitrary writer to avoid large allocations for very large trees.
- Tag helpers
  - Prebuilt helpers for common tags like div, span, a, ul/li, img, input, etc.
  - Attribute handling includes boolean, string, numeric, and data-\* attributes with proper escaping.
- Components
  - Components are functions that accept an allocator plus props/state and return a node (or append into a parent).
  - Components can compose other components and tag helpers to build trees.

Quickstart

- Requirements: Zig 0.15.1
- Build: zig build
- Test: zig build test
- Run example binary (scaffold): zig build run

Hypothetical usage (target API – subject to change)

```zig path=null start=null
const std = @import("std");
const reg = @import("regolith");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var root = try reg.node(alloc, .div, .{ .class = "container" });
    defer root.deinit();

    try root.child(reg.text("Hello, "));
    try root.child(reg.tag(.strong, .{}, .{ reg.text("world") }));
    try root.child(reg.tag(.br, .{}, .{}));

    const html = try reg.renderToString(alloc, &root);
    defer alloc.free(html);

    std.debug.print("{s}\n", .{html});
}
```

README-driven roadmap

- v0.0.1 Minimal core
  - Node struct (element, text) with children storage and owned attributes
  - Renderer to string with escaping
  - A handful of tag helpers (div, span, a, ul, li, p, h1–h6, img, br)
- v0.0.2 Components API
  - Component functions with props/state and subtree construction
  - Convenience builder for attributes
  - More tag helpers and attribute coverage
- v0.0.3 Quality and ergonomics
  - Streaming renderer to any writer
  - Examples directory and docs
  - Benchmarks and basic fuzzing of escaping

Contributing

- Use zig fmt to keep formatting consistent: zig fmt .
- Add tests alongside features; prefer allocator-safe, leak-free tests.
- Prefer a single allocator per tree rooted at the caller.

License

- MIT
