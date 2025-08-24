//! Marble is a Metamorphic Testing library for Zig
//! https://github.com/cryptocode/marble

const std = @import("std");

/// Generate an (n take r) list of transformer indices
/// Number of combinations returned is n! / (r! (n-r)!)
fn generateCombinations(n: usize, r: usize, allocator: std.mem.Allocator) !std.ArrayList(std.ArrayList(usize)) {
    var combinations = std.ArrayList(std.ArrayList(usize)).empty;
    var combination = std.ArrayList(usize).empty;

    // Start with the smallest lexicographic combination
    {
        var i: usize = 0;
        while (i < r) : (i += 1) {
            try combination.append(allocator, i);
        }
    }

    while (combination.items[r - 1] < n) {
        try combinations.append(allocator, try combination.clone(allocator));

        // Next combination in lexicographic order
        var k = r - 1;
        while (k != 0 and combination.items[k] == n - r + k) {
            k -= 1;
        }
        combination.items[k] += 1;

        var j: usize = k + 1;
        while (j < r) : (j += 1) {
            combination.items[j] = combination.items[j - 1] + 1;
        }
    }

    return combinations;
}

/// Generate the combinations for every n = 0..count-1 and r = 1..count
fn generateAllCombinations(transformation_count: usize, allocator: std.mem.Allocator) !std.ArrayList(std.ArrayList(usize)) {
    var res = std.ArrayList(std.ArrayList(usize)).empty;
    var i: usize = 1;
    while (i <= transformation_count) : (i += 1) {
        try res.appendSlice(allocator, (try generateCombinations(transformation_count, i, allocator)).items[0..]);
    }
    return res;
}

/// Phase indicator for the `before` and `after` functions
pub const Phase = enum {
    /// Before or after a test `run`
    Test,
    /// Before or after a transformation combination
    Combination,
};

/// Returns the type representing a discovered transformer function
fn Transformer(comptime TestType: type) type {
    return struct {
        function: *const fn (*TestType) void,
        name: []const u8,
    };
}

/// A metamorphic test-case is expected to have a number of functions whose name
/// starts with "transform". Combinations of these functions will be executed
/// during test runs.
fn findTransformers(comptime T: type) []const Transformer(T) {
    const functions = @typeInfo(T).@"struct".decls;
    var transformers: []const Transformer(T) = &[_]Transformer(T){};
    inline for (functions) |f| {
        if (std.mem.startsWith(u8, f.name, "transform")) {
            transformers = transformers ++ &[_]Transformer(T){.{
                .function = @field(T, f.name),
                .name = f.name,
            }};
        }
    }
    return transformers;
}

/// Configuration of a test run
pub const RunConfiguration = struct {
    /// If set to true, only run each transformation once separately
    skip_combinations: bool = false,
    /// If true, print detailed information during the run
    verbose: bool = false,
};

/// Run a testcase, returns true if all succeed
pub fn run(comptime T: type, testcase: *T, allocator: std.mem.Allocator, config: RunConfiguration) !bool {
    if (config.verbose) std.debug.print("\n", .{});
    const metamorphicTest = comptime findTransformers(T);
    if (@hasDecl(T, "before")) testcase.before(Phase.Test);

    const initial_value = testcase.value;

    // Execute on the initial value. The result is used as the baseline to check if a relation
    // holds after transformations.
    const org_output = testcase.execute();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const combinations = try generateAllCombinations(metamorphicTest.len, arena.allocator());
    for (combinations.items) |combination| {
        if (combination.items.len > 1 and config.skip_combinations) {
            if (config.verbose) std.debug.print("Skipping transformation combinations\n", .{});
            break;
        }

        // Reset to initial value for each transformer combination
        testcase.value = initial_value;

        // The before-function is free to update the inital value set above
        if (@hasDecl(T, "before")) testcase.before(Phase.Combination);

        if (config.verbose) std.debug.print(">> Combination\n", .{});

        // Run through all value transformations
        for (combination.items) |transformer_index| {
            const tr = metamorphicTest[transformer_index];
            if (config.verbose) std.debug.print("  >> {s}\n", .{tr.name});

            @call(.auto, tr.function, .{testcase});
        }

        // Execute
        const transformed_output = testcase.execute();

        // Check if relation still holds
        if (!testcase.check(org_output, transformed_output)) {
            std.debug.print("Test case failed with transformation(s):\n", .{});
            for (combination.items) |transformer_index| {
                const tr = metamorphicTest[transformer_index];
                std.debug.print("  >> {s}\n", .{tr.name});
            }

            return false;
        }

        if (@hasDecl(T, "after")) testcase.after(Phase.Combination);
    }

    if (@hasDecl(T, "after")) testcase.after(Phase.Test);

    return true;
}
