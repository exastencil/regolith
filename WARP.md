WARP: Project Guide for Regolith

Context

- Terminal: Warp on macOS
- Zig: 0.15.1

Common commands

- Format: zig fmt .
- Build library and example exe: zig build
- Run example exe: zig build run
- Run tests: zig build test

Repository layout (initial)

- build.zig – package build script that defines a library module "regolith" and a small example executable
- build.zig.zon – Zig package manifest
- src/root.zig – library root (public API surface)
- src/main.zig – example executable entry point
- README.md – project goals, design, roadmap (README-driven design)
- WARP.md – this guide

Conventions

- Allocator
  - The root component receives the allocator. All children use the same allocator.
  - The root owns its subtree and must deinit it before the allocator is torn down.
- Ownership
  - Parents own their children; deinit recurses.
  - Returned strings from renderToString are owned by the caller and must be freed with the same allocator.

Workflow tips

- Use README-driven design: update README first, then implement the minimal feature to satisfy it.
- Keep tests small and allocator-safe. Use std.testing.allocator or a dedicated GPA for tests.
- Prefer no global singletons; pass allocators explicitly.

Next steps

- Implement v0.0.1 Minimal core from README:
  - Node type (element/text), children storage, attributes
  - Renderer to string with escaping
  - A few tag helpers
- Add examples/ with a minimal serverless render demo once core exists.
