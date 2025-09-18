const std = @import("std");
const reg = @import("regolith");

const Node = reg.Node;
const div = reg.div;
const span = reg.span;
const svg = reg.svg;
const path = reg.path;
const h1 = reg.h1;
const p = reg.p;
const button = reg.button;

// Formal Feature component descriptor
const Feature = reg.Component([]const u8){
    .name = "Feature",
    .build = &buildFeature,
};

pub fn buildFeature(alloc: std.mem.Allocator, text: []const u8) !Node {
    return try reg.root(alloc, .div, .{ .class = "p-2 sm:w-1/2 w-full" }, .{
        div(.{ .class = "bg-gray-800 rounded flex p-4 h-full items-center" }, .{
            svg(
                .{
                    .fill = "none",
                    .stroke = "currentColor",
                    .stroke_linecap = "round",
                    .stroke_linejoin = "round",
                    .stroke_width = 3,
                    .class = "text-indigo-400 w-6 h-6 flex-shrink-0 mr-4",
                    .viewBox = "0 0 24 24",
                },
                .{
                    path(.{ .d = "M22 11.08V12a10 10 0 11-5.93-9.14" }, .{}),
                    path(.{ .d = "M22 4L12 14.01l-3-3" }, .{}),
                },
            ),
            span(.{ .class = "title-font font-medium text-white" }, .{text}),
        }),
    });
}

pub fn featuresSection(alloc: std.mem.Allocator) !Node {
    // Simulate data provided externally: allocate an array of feature strings with the provided allocator
    var features = try alloc.alloc([]const u8, 6);
    defer alloc.free(features);
    features[0] = "Authentic Cliche Forage";
    features[1] = "Kinfolk Chips Snackwave";
    features[2] = "Coloring Book Ethical";
    features[3] = "Typewriter Polaroid Cray";
    features[4] = "Pack Truffaut Blue";
    features[5] = "The Catcher In The Rye";

    // Build the section root once with a fully declarative structure
    return try reg.root(alloc, .section, .{ .class = "text-gray-400 bg-gray-900 body-font" }, .{
        div(.{ .class = "container px-5 py-24 mx-auto" }, .{
            div(.{ .class = "text-center mb-20" }, .{
                h1(.{ .class = "sm:text-3xl text-2xl font-medium text-center title-font text-white mb-4" }, .{
                    "Raw Denim Heirloom Man Braid",
                }),
                p(.{ .class = "text-base leading-relaxed xl:w-2/4 lg:w-3/4 mx-auto" }, .{
                    "Blue bottle crucifix vinyl post-ironic four dollar toast vegan taxidermy. Gastropub indxgo juice poutine, ramps microdosing banh mi pug.",
                }),
            }),
            // Only the reused feature item is a component, repeated over the input features.
            div(.{ .class = "flex flex-wrap lg:w-4/5 sm:mx-auto sm:mb-2 -mx-2" }, .{
                reg.repeat(Feature, features),
            }),
            button(.{ .class = "flex mx-auto mt-16 text-white bg-indigo-500 border-0 py-2 px-8 focus:outline-none hover:bg-indigo-600 rounded text-lg" }, .{
                "Button",
            }),
        }),
    });
}

fn expectedHtml() []const u8 {
    return "<section class=\"text-gray-400 bg-gray-900 body-font\"><div class=\"container px-5 py-24 mx-auto\"><div class=\"text-center mb-20\"><h1 class=\"sm:text-3xl text-2xl font-medium text-center title-font text-white mb-4\">Raw Denim Heirloom Man Braid</h1><p class=\"text-base leading-relaxed xl:w-2/4 lg:w-3/4 mx-auto\">Blue bottle crucifix vinyl post-ironic four dollar toast vegan taxidermy. Gastropub indxgo juice poutine, ramps microdosing banh mi pug.</p></div><div class=\"flex flex-wrap lg:w-4/5 sm:mx-auto sm:mb-2 -mx-2\"><div class=\"p-2 sm:w-1/2 w-full\"><div class=\"bg-gray-800 rounded flex p-4 h-full items-center\"><svg fill=\"none\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"3\" class=\"text-indigo-400 w-6 h-6 flex-shrink-0 mr-4\" viewBox=\"0 0 24 24\"><path d=\"M22 11.08V12a10 10 0 11-5.93-9.14\"></path><path d=\"M22 4L12 14.01l-3-3\"></path></svg><span class=\"title-font font-medium text-white\">Authentic Cliche Forage</span></div></div><div class=\"p-2 sm:w-1/2 w-full\"><div class=\"bg-gray-800 rounded flex p-4 h-full items-center\"><svg fill=\"none\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"3\" class=\"text-indigo-400 w-6 h-6 flex-shrink-0 mr-4\" viewBox=\"0 0 24 24\"><path d=\"M22 11.08V12a10 10 0 11-5.93-9.14\"></path><path d=\"M22 4L12 14.01l-3-3\"></path></svg><span class=\"title-font font-medium text-white\">Kinfolk Chips Snackwave</span></div></div><div class=\"p-2 sm:w-1/2 w-full\"><div class=\"bg-gray-800 rounded flex p-4 h-full items-center\"><svg fill=\"none\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"3\" class=\"text-indigo-400 w-6 h-6 flex-shrink-0 mr-4\" viewBox=\"0 0 24 24\"><path d=\"M22 11.08V12a10 10 0 11-5.93-9.14\"></path><path d=\"M22 4L12 14.01l-3-3\"></path></svg><span class=\"title-font font-medium text-white\">Coloring Book Ethical</span></div></div><div class=\"p-2 sm:w-1/2 w-full\"><div class=\"bg-gray-800 rounded flex p-4 h-full items-center\"><svg fill=\"none\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"3\" class=\"text-indigo-400 w-6 h-6 flex-shrink-0 mr-4\" viewBox=\"0 0 24 24\"><path d=\"M22 11.08V12a10 10 0 11-5.93-9.14\"></path><path d=\"M22 4L12 14.01l-3-3\"></path></svg><span class=\"title-font font-medium text-white\">Typewriter Polaroid Cray</span></div></div><div class=\"p-2 sm:w-1/2 w-full\"><div class=\"bg-gray-800 rounded flex p-4 h-full items-center\"><svg fill=\"none\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"3\" class=\"text-indigo-400 w-6 h-6 flex-shrink-0 mr-4\" viewBox=\"0 0 24 24\"><path d=\"M22 11.08V12a10 10 0 11-5.93-9.14\"></path><path d=\"M22 4L12 14.01l-3-3\"></path></svg><span class=\"title-font font-medium text-white\">Pack Truffaut Blue</span></div></div><div class=\"p-2 sm:w-1/2 w-full\"><div class=\"bg-gray-800 rounded flex p-4 h-full items-center\"><svg fill=\"none\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"3\" class=\"text-indigo-400 w-6 h-6 flex-shrink-0 mr-4\" viewBox=\"0 0 24 24\"><path d=\"M22 11.08V12a10 10 0 11-5.93-9.14\"></path><path d=\"M22 4L12 14.01l-3-3\"></path></svg><span class=\"title-font font-medium text-white\">The Catcher In The Rye</span></div></div></div><button class=\"flex mx-auto mt-16 text-white bg-indigo-500 border-0 py-2 px-8 focus:outline-none hover:bg-indigo-600 rounded text-lg\">Button</button></div></section>";
}

test "featuresSection renders expected HTML" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var node = try featuresSection(alloc);
    defer node.deinit();

    const html = try reg.renderToString(alloc, &node);
    defer alloc.free(html);

    try std.testing.expectEqualStrings(expectedHtml(), html);
}
