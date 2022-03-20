//! Marble is a Metamorphic Testing library for Zig
//! https://github.com/cryptocode/marble

const std = @import("std");

/// Generate an (n take r) list of transformer indices
/// Number of combinations returned is n! / (r! (n-r)!)
fn generateCombinations(n: usize, r: usize, allocator: std.mem.Allocator) !std.ArrayList(std.ArrayList(usize)) {
    var combinations = std.ArrayList(std.ArrayList(usize)).init(allocator);
    var combination = std.ArrayList(usize).init(allocator);

    // Start with the smallest lexicographic combination
    {
        var i: usize = 0;
        while (i < r) : (i += 1) {
            try combination.append(i);
        }
    }

    while (combination.items[r - 1] < n) {
        try combinations.append(try combination.clone());

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
    var res = std.ArrayList(std.ArrayList(usize)).init(allocator);
    var i: usize = 1;
    while (i <= transformation_count) : (i += 1) {
        try res.appendSlice((try generateCombinations(transformation_count, i, allocator)).items[0..]);
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

/// Returns a container type to hold metamorphic testing functions after analyzing a test case
fn MetamorphicTest(comptime TestType: type, comptime OutputType: type) type {
    return struct {
        transformers: []const fn (*TestType) void,
        transformer_names: []const []const u8,
        check_function: fn (*TestType, OutputType, OutputType) bool,
        execute_function: fn (*TestType) OutputType,
        before_function: ?fn (*TestType, Phase) void = null,
        after_function: ?fn (*TestType, Phase) void = null,
    };
}

/// Extracts the `execute` function return type
fn OutputTypeOf(comptime T: type) type {
    const functions = @typeInfo(T).Struct.decls;
    inline for (functions) |f| {
        if (comptime std.mem.eql(u8, f.name, "execute")) {
            return @typeInfo(@TypeOf(@field(T, f.name))).Fn.return_type.?;
        }
    }

    @compileError("Missing 'execute' function in metamorphic test");
}

/// Analyze a test case type to discover metamorphic functions and validate
/// that it's well-formed.
/// Returns an instance of MetamorphicTest(TestcaseType, OutputType)
fn analyzeTest(comptime T: type) MetamorphicTest(T, OutputTypeOf(T)) {
    const OutputType = OutputTypeOf(T);
    const functions = @typeInfo(T).Struct.decls;
    comptime var transformer_function_count: usize = 0;
    comptime var transformer_functions: [functions.len]fn (*T) void = undefined;
    comptime var transformer_function_names: [functions.len][]const u8 = undefined;
    comptime var check_function: fn (*T, OutputType, OutputType) bool = undefined;
    comptime var execute_function: fn (*T) OutputType = undefined;
    comptime var before_function: ?fn (*T, Phase) void = null;
    comptime var after_function: ?fn (*T, Phase) void = null;

    inline for (functions) |f| {
        if (comptime std.mem.startsWith(u8, f.name, "transform")) {
            transformer_functions[transformer_function_count] = @field(T, f.name);
            transformer_function_names[transformer_function_count] = f.name;
            transformer_function_count += 1;
        } else if (comptime std.mem.eql(u8, f.name, "check")) {
            check_function = @field(T, f.name);
        } else if (comptime std.mem.eql(u8, f.name, "execute")) {
            execute_function = @field(T, f.name);
        } else if (comptime std.mem.eql(u8, f.name, "before")) {
            before_function = @field(T, f.name);
        } else if (comptime std.mem.eql(u8, f.name, "after")) {
            after_function = @field(T, f.name);
        } else if (comptime f.is_pub) {
            @compileError("Invalid name of public " ++ @typeName(T) ++ " member: " ++ f.name);
        }
    }

    return MetamorphicTest(T, OutputTypeOf(T)){
        .transformers = transformer_functions[0..transformer_function_count],
        .transformer_names = transformer_function_names[0..transformer_function_count],
        .check_function = check_function,
        .execute_function = execute_function,
        .before_function = before_function,
        .after_function = after_function,
    };
}

/// Configuration of a test run
pub const RunConfiguration = struct {
    /// If set to true, only run each transformation once separately
    skip_combinations: bool = false,
    /// If true, print detailed information during the run
    verbose: bool = false,
};

/// Run a testcase, returns true if all succeed
pub fn run(comptime T: type, testcase: *T, config: RunConfiguration) !bool {
    if (config.verbose) std.debug.print("\n", .{});
    comptime var metamorphicTest = analyzeTest(T);
    if (metamorphicTest.before_function != null) {
        testcase.before(Phase.Test);
    }

    var initial_value = testcase.value;

    // Execute on the initial value. The result is used as the baseline to check if a relation
    // holds after transformations.
    var org_output = testcase.execute();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var combinations = try generateAllCombinations(metamorphicTest.transformers.len, arena.allocator());
    for (combinations.items) |combination| {
        if (combination.items.len > 1 and config.skip_combinations) {
            if (config.verbose) std.debug.print("Skipping transformation combinations\n", .{});
            break;
        }

        // Reset to initial value for each transformer combination
        testcase.value = initial_value;

        // The before-function is free to update the inital value set above
        if (metamorphicTest.before_function != null) {
            testcase.before(Phase.Combination);
        }

        if (config.verbose) std.debug.print(">> Combination\n", .{});

        // Run through all value transformations
        for (combination.items) |transformer_index| {
            const tr = metamorphicTest.transformers[transformer_index];
            if (config.verbose) std.debug.print("  >> {s}\n", .{metamorphicTest.transformer_names[transformer_index]});
            @call(.{}, tr, .{testcase});
        }

        // Execute
        var transformed_output = testcase.execute();

        // Check if relation still holds
        if (!testcase.check(org_output, transformed_output)) {
            std.debug.print("Test case failed with transformation(s):\n", .{});
            for (combination.items) |transformer_index| {
                std.debug.print("  >> {s}\n", .{metamorphicTest.transformer_names[transformer_index]});
            }

            return false;
        }

        if (metamorphicTest.after_function != null) {
            testcase.after(Phase.Combination);
        }
    }

    if (metamorphicTest.after_function != null) {
        testcase.after(Phase.Test);
    }

    for (combinations.items) |*combination| {
        combination.deinit();
    }
    combinations.deinit();
    return true;
}
