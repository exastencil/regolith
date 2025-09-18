const std = @import("std");

// Minimal core: Node type and renderer to HTML.
// Each Node has either an allocator (root) or a parent; allocator may be retrieved recursively.

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
    svg,
    path,
    br,
    input,
    section,
    button,
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
        .svg => "svg",
        .path => "path",
        .br => "br",
        .input => "input",
        .section => "section",
        .button => "button",
    };
}

fn isVoidTag(t: Tag) bool {
    return switch (t) {
        .img, .br, .input => true,
        else => false,
    };
}

pub const Attr = struct {
    key: []u8, // owned by node allocator
    value: ?[]u8, // null means boolean attribute
};

pub const Node = struct {
    // Either alloc is set (root) or parent is set; allocator is obtained recursively.
    alloc: ?std.mem.Allocator = null,
    parent: ?*Node = null,

    tag: ?Tag = null, // null => text node
    text: []u8 = &[_]u8{}, // owned when text node
    attrs: []Attr = &[_]Attr{},
    children: []Node = &[_]Node{},

    pub fn getAllocator(self: *const Node) std.mem.Allocator {
        if (self.alloc) |alloc_| return alloc_;
        if (self.parent) |parent_ptr| return parent_ptr.getAllocator();
        @panic("Node has neither allocator nor parent");
    }

    pub fn deinit(self: *Node) void {
        const alloc_ = self.getAllocator();
        // Free children first (post-order)
        for (self.children) |*child| {
            child.deinit();
        }
        if (self.children.len > 0) alloc_.free(self.children);

        // Free attributes
        for (self.attrs) |attr| {
            alloc_.free(attr.key);
            if (attr.value) |v| alloc_.free(v);
        }
        if (self.attrs.len > 0) alloc_.free(self.attrs);

        // Free text content
        if (self.tag == null and self.text.len > 0) alloc_.free(self.text);

        // Clear slices to avoid double free if called again erroneously
        self.children = &[_]Node{};
        self.attrs = &[_]Attr{};
        self.text = &[_]u8{};
    }

    // Constructors
    pub fn newElementRoot(alloc: std.mem.Allocator, tag: Tag) Node {
        return .{ .alloc = alloc, .tag = tag };
    }

    pub fn newElementWithParent(parent: *Node, tag: Tag) Node {
        return .{ .parent = parent, .alloc = parent.getAllocator(), .tag = tag };
    }

    pub fn newTextRoot(alloc: std.mem.Allocator, content: []const u8) !Node {
        var n: Node = .{ .alloc = alloc, .tag = null };
        n.text = try alloc.dupe(u8, content);
        return n;
    }

    pub fn newTextWithParent(parent: *Node, content: []const u8) !Node {
        const alloc_ = parent.getAllocator();
        var n: Node = .{ .parent = parent, .alloc = alloc_, .tag = null };
        n.text = try alloc_.dupe(u8, content);
        return n;
    }

    // Mutators
    pub fn addAttr(self: *Node, key: []const u8, value: ?[]const u8) !void {
        const alloc_ = self.getAllocator();
        const key_copy = try alloc_.dupe(u8, key);
        const val_copy = if (value) |v| try alloc_.dupe(u8, v) else null;
        const old_len = self.attrs.len;
        const new_slice = try alloc_.alloc(Attr, old_len + 1);
        if (old_len > 0) {
            @memcpy(new_slice[0..old_len], self.attrs);
            alloc_.free(self.attrs);
        }
        new_slice[old_len] = .{ .key = key_copy, .value = val_copy };
        self.attrs = new_slice;
    }

    fn addAttrOwned(self: *Node, key_owned: []u8, value_owned: ?[]u8) !void {
        const alloc_ = self.getAllocator();
        const old_len = self.attrs.len;
        const new_slice = try alloc_.alloc(Attr, old_len + 1);
        if (old_len > 0) {
            @memcpy(new_slice[0..old_len], self.attrs);
            alloc_.free(self.attrs);
        }
        new_slice[old_len] = .{ .key = key_owned, .value = value_owned };
        self.attrs = new_slice;
    }

    pub fn addAttrsFrom(self: *Node, attrs: anytype) !void {
        const T = @TypeOf(attrs);
        switch (@typeInfo(T)) {
            .@"struct" => {},
            else => return, // ignore non-struct
        }
        const alloc_ = self.getAllocator();
        inline for (std.meta.fields(T)) |f| {
            const V = @field(attrs, f.name);
            const VT = @TypeOf(V);
            if (VT == bool) {
                if (V) {
                    const key_copy = try normalizeAttrName(alloc_, f.name);
                    try self.addAttrOwned(key_copy, null);
                }
            } else if (isStringType(VT)) {
                const key_copy = try normalizeAttrName(alloc_, f.name);
                const val_copy = try alloc_.dupe(u8, asConstSlice(V));
                try self.addAttrOwned(key_copy, val_copy);
            } else switch (@typeInfo(VT)) {
                .int, .float, .comptime_int, .comptime_float => {
                    const key_copy = try normalizeAttrName(alloc_, f.name);
                    var buf: std.ArrayListUnmanaged(u8) = .{};
                    defer buf.deinit(alloc_);
                    try std.fmt.format(buf.writer(alloc_), "{}", .{V});
                    const val_copy = try buf.toOwnedSlice(alloc_);
                    try self.addAttrOwned(key_copy, val_copy);
                },
                else => {},
            }
        }
    }

    pub fn appendChildren(self: *Node, children: anytype) !void {
        const T = @TypeOf(children);
        switch (@typeInfo(T)) {
            .@"struct" => |s| {
                if (!s.is_tuple) return;
            },
            else => return,
        }
        inline for (std.meta.fields(T)) |f| {
            const child = @field(children, f.name);
            try self.appendChildAny(child);
        }
    }

    fn appendChildAny(self: *Node, item: anytype) !void {
        const IT = @TypeOf(item);
        if (IT == Node) {
            try self.appendChild(item);
            return;
        }
        if (isStringType(IT)) {
            const txt = try Node.newTextWithParent(self, asConstSlice(item));
            try self.appendChild(txt);
            return;
        }
        // Tag wrapper: materialize under this parent (no allocator at call site)
        if (comptime (hasField(IT, "tag") and hasField(IT, "children") and hasField(IT, "attrs"))) {
            var child = Node.newElementWithParent(self, @field(item, "tag"));
            try child.addAttrsFrom(@field(item, "attrs"));
            try child.appendChildren(@field(item, "children"));
            try self.appendChild(child);
            return;
        }
        // Component use: { comp, props }
        if (comptime (hasField(IT, "comp") and hasField(IT, "props"))) {
            const alloc_ = self.getAllocator();
            const built = try item.comp.build(alloc_, item.props);
            try self.appendChild(built);
            return;
        }
        // Component repeat: { comp, items }
        if (comptime (hasField(IT, "comp") and hasField(IT, "items"))) {
            const alloc_ = self.getAllocator();
            for (item.items) |props| {
                const built = try item.comp.build(alloc_, props);
                try self.appendChild(built);
            }
            return;
        }
        // unsupported child kind; ignore for now
    }

    fn reparentRecursive(n: *Node) void {
        // Set each child's parent pointer to n and recurse.
        for (n.children) |*ch| {
            ch.parent = n;
            reparentRecursive(ch);
        }
    }

    pub fn appendChild(self: *Node, child: Node) !void {
        const alloc_ = self.getAllocator();
        const old_len = self.children.len;
        const new_slice = try alloc_.alloc(Node, old_len + 1);
        if (old_len > 0) {
            @memcpy(new_slice[0..old_len], self.children);
            alloc_.free(self.children);
            // Reparent all existing children to their new stored locations
            var i: usize = 0;
            while (i < old_len) : (i += 1) {
                var existing: *Node = &new_slice[i];
                existing.parent = self;
                // keep allocator as-is
                reparentRecursive(existing);
            }
        }
        // Place the new child by value, then fix up parent pointers to the canonical stored location
        new_slice[old_len] = child;
        var stored: *Node = &new_slice[old_len];
        stored.parent = self;
        // keep stored.alloc as-is (likely root allocator), non-root is determined by having a parent
        reparentRecursive(stored);
        self.children = new_slice;
    }
};

// Helpers for declarative builders
fn normalizeAttrName(alloc: std.mem.Allocator, name: []const u8) ![]u8 {
    var need_copy = false;
    for (name) |c| {
        if (c == '_') {
            need_copy = true;
            break;
        }
    }
    if (!need_copy) return alloc.dupe(u8, name);
    var out = try alloc.alloc(u8, name.len);
    for (name, 0..) |c, i| out[i] = if (c == '_') '-' else c;
    return out;
}

fn isStringType(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |ptr| blk: {
            if (ptr.size == .slice and ptr.child == u8) break :blk true;
            switch (@typeInfo(ptr.child)) {
                .array => |arr| return arr.child == u8,
                else => return false,
            }
        },
        .array => |arr| arr.child == u8,
        else => false,
    };
}

fn asConstSlice(v: anytype) []const u8 {
    const T = @TypeOf(v);
    return switch (@typeInfo(T)) {
        .pointer => |ptr| {
            if (ptr.size == .slice) return v;
            switch (@typeInfo(ptr.child)) {
                .array => return v[0..],
                else => return &[_]u8{},
            }
        },
        .array => v[0..],
        else => &[_]u8{},
    };
}

fn hasField(comptime T: type, comptime name: []const u8) bool {
    const ti = @typeInfo(T);
    switch (ti) {
        .@"struct" => |s| {
            inline for (s.fields) |f| if (std.mem.eql(u8, f.name, name)) return true;
            return false;
        },
        else => return false,
    }
}

// Declarative Node builders
pub fn root(alloc: std.mem.Allocator, comptime tag: Tag, attrs: anytype, children: anytype) !Node {
    var n = Node.newElementRoot(alloc, tag);
    try n.addAttrsFrom(attrs);
    try n.appendChildren(children);
    return n;
}

// Declarative Node builder for an element: builds a Node immediately with the given allocator
pub fn element(alloc: std.mem.Allocator, comptime tag: Tag, attrs: anytype, children: anytype) !Node {
    var n = Node.newElementRoot(alloc, tag);
    try n.addAttrsFrom(attrs);
    try n.appendChildren(children);
    return n;
}

// Tag wrapper types and helpers for allocator-free declarative usage
pub fn TagCall(comptime TAttrs: type, comptime TChildren: type) type {
    return struct { tag: Tag, attrs: TAttrs, children: TChildren };
}

fn tagCall(comptime t: Tag, attrs: anytype, children: anytype) TagCall(@TypeOf(attrs), @TypeOf(children)) {
    return .{ .tag = t, .attrs = attrs, .children = children };
}

pub fn div(attrs: anytype, children: anytype) TagCall(@TypeOf(attrs), @TypeOf(children)) {
    return tagCall(.div, attrs, children);
}
pub fn span(attrs: anytype, children: anytype) TagCall(@TypeOf(attrs), @TypeOf(children)) {
    return tagCall(.span, attrs, children);
}
pub fn strong(attrs: anytype, children: anytype) TagCall(@TypeOf(attrs), @TypeOf(children)) {
    return tagCall(.strong, attrs, children);
}
pub fn a(attrs: anytype, children: anytype) TagCall(@TypeOf(attrs), @TypeOf(children)) {
    return tagCall(.a, attrs, children);
}
pub fn ul(attrs: anytype, children: anytype) TagCall(@TypeOf(attrs), @TypeOf(children)) {
    return tagCall(.ul, attrs, children);
}
pub fn li(attrs: anytype, children: anytype) TagCall(@TypeOf(attrs), @TypeOf(children)) {
    return tagCall(.li, attrs, children);
}
pub fn p(attrs: anytype, children: anytype) TagCall(@TypeOf(attrs), @TypeOf(children)) {
    return tagCall(.p, attrs, children);
}
pub fn h1(attrs: anytype, children: anytype) TagCall(@TypeOf(attrs), @TypeOf(children)) {
    return tagCall(.h1, attrs, children);
}
pub fn svg(attrs: anytype, children: anytype) TagCall(@TypeOf(attrs), @TypeOf(children)) {
    return tagCall(.svg, attrs, children);
}
pub fn path(attrs: anytype, children: anytype) TagCall(@TypeOf(attrs), @TypeOf(children)) {
    return tagCall(.path, attrs, children);
}
pub fn section(attrs: anytype, children: anytype) TagCall(@TypeOf(attrs), @TypeOf(children)) {
    return tagCall(.section, attrs, children);
}
pub fn button(attrs: anytype, children: anytype) TagCall(@TypeOf(attrs), @TypeOf(children)) {
    return tagCall(.button, attrs, children);
}

pub fn text(parent: *Node, content: []const u8) !Node {
    return Node.newTextWithParent(parent, content);
}

pub fn Component(comptime TProps: type) type {
    return struct {
        name: []const u8,
        // Build returns a Node using the provided allocator. The builder will adopt it as root or as a child.
        build: *const fn (std.mem.Allocator, TProps) anyerror!Node,
        render: ?*const fn (std.mem.Allocator, TProps) anyerror!Node = null,
    };
}

pub fn UseType(comptime CompT: type, comptime PropsT: type) type {
    return struct { comp: CompT, props: PropsT };
}

pub fn RepeatType(comptime CompT: type, comptime ItemsT: type) type {
    return struct { comp: CompT, items: ItemsT };
}

pub fn use(comp: anytype, props: anytype) UseType(@TypeOf(comp), @TypeOf(props)) {
    return .{ .comp = comp, .props = props };
}

pub fn repeat(comp: anytype, items: anytype) RepeatType(@TypeOf(comp), @TypeOf(items)) {
    return .{ .comp = comp, .items = items };
}

// Renderer
pub fn renderToString(alloc: std.mem.Allocator, nroot: *const Node) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(alloc);
    try renderNode(buf.writer(alloc), nroot);
    return buf.toOwnedSlice(alloc);
}

fn renderNode(writer: anytype, n: *const Node) !void {
    if (n.tag == null) {
        try writeEscapedText(writer, n.text);
        return;
    }
    const tag = n.tag.?;
    try writer.print("<{s}", .{tagName(tag)});
    // attributes
    for (n.attrs) |attr_entry| {
        if (attr_entry.value) |v| {
            try writer.writeAll(" ");
            try writer.writeAll(attr_entry.key);
            try writer.writeAll("=\"");
            try writeEscapedAttr(writer, v);
            try writer.writeAll("\"");
        } else {
            try writer.writeAll(" ");
            try writer.writeAll(attr_entry.key);
        }
    }
    try writer.writeAll(">");
    if (isVoidTag(tag)) {
        // Void tags render without closing tag content
        return;
    }
    // children
    for (n.children) |*child| try renderNode(writer, child);
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

    var r = Node.newElementRoot(alloc, .div);
    try r.addAttr("class", "container");

    const hello = try Node.newTextWithParent(&r, "Hello, ");
    try r.appendChild(hello);

    var strong_node = Node.newElementWithParent(&r, .strong);
    const strong_text = try Node.newTextWithParent(&strong_node, "world & <zig>");
    try strong_node.appendChild(strong_text);
    try r.appendChild(strong_node);

    const br = Node.newElementWithParent(&r, .br);
    try r.appendChild(br);

    defer r.deinit();

    const html = try renderToString(alloc, &r);
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

    var r = Node.newElementRoot(alloc, .div);

    var img = Node.newElementWithParent(&r, .img);
    try img.addAttr("src", "/x.png");
    try img.addAttr("width", "10");
    try img.addAttr("height", "20");
    try img.addAttr("draggable", null);
    try r.appendChild(img);

    var input = Node.newElementWithParent(&r, .input);
    try input.addAttr("type", "checkbox");
    try input.addAttr("checked", null);
    // disabled = false -> do not render
    try r.appendChild(input);

    defer r.deinit();

    const html = try renderToString(alloc, &r);
    defer alloc.free(html);

    try std.testing.expectEqualStrings(
        "<div><img src=\"/x.png\" width=\"10\" height=\"20\" draggable><input type=\"checkbox\" checked></div>",
        html,
    );
}
