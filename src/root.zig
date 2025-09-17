const std = @import("std");

// Minimal core: Node type, declarative builders (el/text/br), and renderer to HTML.
// Root allocator is stored on each node for simpler deinit() without passing an allocator.

pub const Tag = enum {
    div,
    span,
    strong,
    a,
    ul,
    li,
    p,
    h1,
    h2,
    h3,
    h4,
    h5,
    h6,
    img,
    br,
    input,
};

fn tagName(t: Tag) []const u8 {
    return switch (t) {
        .div => "div",
        .span => "span",
        .strong => "strong",
        .a => "a",
        .ul => "ul",
        .li => "li",
        .p => "p",
        .h1 => "h1",
        .h2 => "h2",
        .h3 => "h3",
        .h4 => "h4",
        .h5 => "h5",
        .h6 => "h6",
        .img => "img",
        .br => "br",
        .input => "input",
    };
}

fn isVoidTag(t: Tag) bool {
    return switch (t) {
        .img, .br, .input => true,
        else => false,
    };
}

pub const Attr = struct {
    // key is owned by node allocator
    key: []u8,
    // if value is null, it is a boolean attribute and is rendered without ="..."
    value: ?[]u8,
};

pub const Node = struct {
    alloc: std.mem.Allocator,
    tag: ?Tag = null, // null => text node
    text: []u8 = &[_]u8{}, // owned when text node
    attrs: []Attr = &[_]Attr{},
    children: []Node = &[_]Node{},

    pub fn deinit(self: *Node) void {
        const alloc = self.alloc;
        // Free children first (post-order)
        for (self.children) |*child| {
            child.deinit();
        }
        if (self.children.len > 0) alloc.free(self.children);

        // Free attributes
        for (self.attrs) |a| {
            alloc.free(a.key);
            if (a.value) |v| alloc.free(v);
        }
        if (self.attrs.len > 0) alloc.free(self.attrs);

        // Free text content
        if (self.tag == null and self.text.len > 0) alloc.free(self.text);

        // Clear slices to avoid double free if called again erroneously
        self.children = &[_]Node{};
        self.attrs = &[_]Attr{};
        self.text = &[_]u8{};
    }
};

// ---- Declarative specs ----
// These are lightweight values consumed at compile time by the root builder.

pub fn text(content: []const u8) SpecText {
    return .{ .content = content };
}

pub fn br() SpecVoidEl {
    return .{ .tag = .br, .attrs = .{} };
}

pub fn el(comptime tag: Tag, attrs: anytype, comptime children: anytype) SpecEl(@TypeOf(attrs), @TypeOf(children)) {
    return .{ .tag = tag, .attrs = attrs, .children = children };
}

pub fn img(attrs: anytype) SpecVoidElWithAttrs(@TypeOf(attrs)) {
    return .{ .tag = .img, .attrs = attrs };
}

pub fn input(attrs: anytype) SpecVoidElWithAttrs(@TypeOf(attrs)) {
    return .{ .tag = .input, .attrs = attrs };
}

pub fn div(attrs: anytype, comptime children: anytype) SpecEl(@TypeOf(attrs), @TypeOf(children)) {
    return el(.div, attrs, children);
}

pub fn strong(attrs: anytype, comptime children: anytype) SpecEl(@TypeOf(attrs), @TypeOf(children)) {
    return el(.strong, attrs, children);
}

// Spec types
pub fn SpecEl(comptime TAttrs: type, comptime TChildren: type) type {
    return struct { tag: Tag, attrs: TAttrs, children: TChildren };
}

pub const SpecText = struct { content: []const u8 };

pub fn SpecVoidElWithAttrs(comptime TAttrs: type) type {
    return struct { tag: Tag, attrs: TAttrs };
}

pub const SpecVoidEl = SpecVoidElWithAttrs(@TypeOf(.{}));

// Root builder: build a Node tree from a top-level element spec.
// API: elRoot(alloc, tag, attrs, children) to match README intent while keeping nested el() for children.
pub fn elRoot(alloc: std.mem.Allocator, comptime tag: Tag, attrs: anytype, comptime children: anytype) !Node {
    var node: Node = .{ .alloc = alloc, .tag = tag };
    node.attrs = try buildAttrs(alloc, attrs);
    node.children = try buildChildren(alloc, children);
    return node;
}

// Convert attrs struct to []Attr
fn buildAttrs(alloc: std.mem.Allocator, attrs: anytype) ![]Attr {
    const T = @TypeOf(attrs);
    switch (@typeInfo(T)) {
        .@"struct" => {},
        else => return error.InvalidAttributes,
    }

    var tmp: std.ArrayListUnmanaged(Attr) = .{};
    errdefer tmp.deinit(alloc);

    inline for (std.meta.fields(T)) |f| {
        const V = @field(attrs, f.name);
        const VT = @TypeOf(V);
        if (VT == bool) {
            // Boolean attribute: include only when true
            if (V) {
                const key_copy = try alloc.dupe(u8, f.name);
                try tmp.append(alloc, .{ .key = key_copy, .value = null });
            }
        } else if (isStringType(VT)) {
            // String-like
            const key_copy = try alloc.dupe(u8, f.name);
            const val_copy = try alloc.dupe(u8, asConstSlice(V));
            try tmp.append(alloc, .{ .key = key_copy, .value = val_copy });
        } else switch (@typeInfo(VT)) {
            // Numbers -> stringified (incl. comptime variants)
            .int, .float, .comptime_int, .comptime_float => {
                const key_copy = try alloc.dupe(u8, f.name);
                var buf: std.ArrayListUnmanaged(u8) = .{};
                defer buf.deinit(alloc);
                try std.fmt.format(buf.writer(alloc), "{}", .{V});
                const val_copy = try buf.toOwnedSlice(alloc);
                try tmp.append(alloc, .{ .key = key_copy, .value = val_copy });
            },
            else => |ti| {
                _ = ti;
                // Ignore unsupported types for now
            },
        }
    }
    return tmp.toOwnedSlice(alloc);
}

fn isStringType(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |p| blk: {
            if (p.size == .slice and p.child == u8) break :blk true;
            // handle *const [N]u8 and *const [N:0]u8
            switch (@typeInfo(p.child)) {
                .array => |a| return a.child == u8,
                else => return false,
            }
        },
        .array => |a| a.child == u8,
        else => false,
    };
}

fn asConstSlice(v: anytype) []const u8 {
    const T = @TypeOf(v);
    return switch (@typeInfo(T)) {
        .pointer => |p| {
            if (p.size == .slice) return v;
            // *[N]u8 or *[N:0]u8
            switch (@typeInfo(p.child)) {
                .array => return v[0..],
                else => return &[_]u8{},
            }
        },
        .array => v[0..],
        else => &[_]u8{},
    };
}

// Build children from a tuple of specs
fn buildChildren(alloc: std.mem.Allocator, children: anytype) ![]Node {
    const T = @TypeOf(children);
    const ti = @typeInfo(T);
    switch (ti) {
        .@"struct" => |s| {
            if (!s.is_tuple) {
                if (s.fields.len == 0) return alloc.alloc(Node, 0);
                return error.InvalidChildren;
            }
        },
        else => return error.InvalidChildren,
    }

    var out: std.ArrayListUnmanaged(Node) = .{};
    errdefer {
        for (out.items) |*n| n.deinit();
        out.deinit(alloc);
    }

    inline for (std.meta.fields(T)) |f| {
        const child = @field(children, f.name);
        const node = try buildOne(alloc, child);
        try out.append(alloc, node);
    }

    return out.toOwnedSlice(alloc);
}

fn buildOne(alloc: std.mem.Allocator, item: anytype) !Node {
    const IT = @TypeOf(item);
    // text spec
    if (comptime hasField(IT, "content")) {
        const content = @field(item, "content");
        var n: Node = .{ .alloc = alloc, .tag = null };
        n.text = try alloc.dupe(u8, content);
        return n;
    } else if (comptime (hasField(IT, "tag") and hasField(IT, "children"))) {
        // element spec
        const tag = @field(item, "tag");
        const attrs = @field(item, "attrs");
        const kids = @field(item, "children");
        var n: Node = .{ .alloc = alloc, .tag = tag };
        n.attrs = try buildAttrs(alloc, attrs);
        n.children = try buildChildren(alloc, kids);
        return n;
    } else if (comptime (hasField(IT, "tag") and !hasField(IT, "children"))) {
        // void element with attrs
        const tag = @field(item, "tag");
        const attrs = @field(item, "attrs");
        var n: Node = .{ .alloc = alloc, .tag = tag };
        n.attrs = try buildAttrs(alloc, attrs);
        n.children = try alloc.alloc(Node, 0);
        return n;
    } else if (comptime isStringType(IT)) {
        // If a raw string is provided, treat as text
        var n: Node = .{ .alloc = alloc, .tag = null };
        n.text = try alloc.dupe(u8, asConstSlice(item));
        return n;
    }

    return error.UnknownChildSpec;
}

fn hasField(comptime T: type, comptime name: []const u8) bool {
    inline for (std.meta.fields(T)) |f| if (std.mem.eql(u8, f.name, name)) return true;
    return false;
}

// Renderer
pub fn renderToString(alloc: std.mem.Allocator, root: *const Node) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(alloc);
    try renderNode(buf.writer(alloc), root);
    return buf.toOwnedSlice(alloc);
}

fn renderNode(writer: anytype, node: *const Node) !void {
    if (node.tag == null) {
        try writeEscapedText(writer, node.text);
        return;
    }
    const tag = node.tag.?;
    try writer.print("<{s}", .{tagName(tag)});
    // attributes
    for (node.attrs) |a| {
        if (a.value) |v| {
            try writer.writeAll(" ");
            try writer.writeAll(a.key);
            try writer.writeAll("=\"");
            try writeEscapedAttr(writer, v);
            try writer.writeAll("\"");
        } else {
            try writer.writeAll(" ");
            try writer.writeAll(a.key);
        }
    }
    try writer.writeAll(">");
    if (isVoidTag(tag)) {
        // Void tags render without closing tag content
        return;
    }
    // children
    for (node.children) |*child| try renderNode(writer, child);
    try writer.print("</{s}>", .{tagName(tag)});
}

fn writeEscapedText(writer: anytype, s: []const u8) !void {
    for (s) |c| switch (c) {
        '&' => try writer.writeAll("&amp;"),
        '<' => try writer.writeAll("&lt;"),
        '>' => try writer.writeAll("&gt;"),
        else => try writer.writeByte(c),
    };
}

fn writeEscapedAttr(writer: anytype, s: []const u8) !void {
    for (s) |c| switch (c) {
        '&' => try writer.writeAll("&amp;"),
        '<' => try writer.writeAll("&lt;"),
        '>' => try writer.writeAll("&gt;"),
        '"' => try writer.writeAll("&quot;"),
        '\'' => try writer.writeAll("&#39;"),
        else => try writer.writeByte(c),
    };
}

// ---- Tests ----

test "render simple nested with boolean and text" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var root = try elRoot(alloc, .div, .{ .class = "container" }, .{
        text("Hello, "),
        el(.strong, .{}, .{text("world & <zig>")}),
        br(),
    });
    defer root.deinit();

    const html = try renderToString(alloc, &root);
    defer alloc.free(html);

    try std.testing.expectEqualStrings(
        "<div class=\"container\">Hello, <strong>world &amp; &lt;zig&gt;</strong><br></div>",
        html,
    );
}

test "void elements and attributes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var root = try elRoot(alloc, .div, .{}, .{
        img(.{ .src = "/x.png", .width = 10, .height = 20, .draggable = true }),
        input(.{ .type = "checkbox", .checked = true, .disabled = false }),
    });
    defer root.deinit();

    const html = try renderToString(alloc, &root);
    defer alloc.free(html);

    try std.testing.expectEqualStrings(
        "<div><img src=\"/x.png\" width=\"10\" height=\"20\" draggable><input type=\"checkbox\" checked></div>",
        html,
    );
}
