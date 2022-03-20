const std = @import("std");
const marble = @import("main.zig");

const SinusTest = struct {
    const tolerance = std.math.epsilon(f64) * 20;

    /// This test has a single value, but you could also design the test to take an
    /// array as input. The transformations, check and execute functions would then
    /// loop through them all. Alternatively, the test can be run multiple times
    /// with different inputs.
    value: f64,

    /// The mathematical property "sin(x) = sin(π − x)" must hold
    pub fn transformPi(self: *SinusTest) void {
        self.value = std.math.pi - self.value;
    }

    /// Adding half the epsilon must still cause the relation to hold given the tolerance
    pub fn transformEpsilon(self: *SinusTest) void {
        self.value = self.value + std.math.epsilon(f64) / 2.0;
    }

    /// A metamorphic relation is a relation between outputs in different executions.
    /// This relation must hold after every execution of transformation combinations.
    pub fn check(_: *SinusTest, original_output: f64, transformed_output: f64) bool {
        return std.math.approxEqAbs(f64, original_output, transformed_output, tolerance);
    }

    /// Called initially to compute the baseline output, and after every transformation combination
    pub fn execute(self: *SinusTest) f64 {
        return std.math.sin(self.value);
    }
};

test "sinus" {
    var i: f64 = 1;
    while (i < 100) : (i += 1) {
        var t = SinusTest{ .value = i };
        try std.testing.expect(try marble.run(SinusTest, &t, .{}));
    }
}

/// Input to a query
const Query = struct {
    term: []const u8 = "test",
    ascending: bool = false,
    page_size: usize = 50,
};

// This is an example of a "conditional relations" test where the metamorphic relationship
// depends on which transformations are applied in the current combination.
const QueryTest = struct {
    value: Query,
    additional_term: bool = false,

    /// Reset the additional_term flag before each combination. It will be
    /// flipped on for combinations including `transformAdditionalTerm`.
    pub fn before(self: *QueryTest, phase: marble.Phase) void {
        if (phase == .Combination) self.additional_term = false;
    }

    /// Sorting shouldn't affect total count
    pub fn transformSort(self: *QueryTest) void {
        self.value.ascending = true;
    }

    /// Page count shouldn't affect total count
    pub fn transformPageCount(self: *QueryTest) void {
        self.value.page_size = 25;
    }

    /// Our search engine is case insensitive
    pub fn transformCase(self: *QueryTest) void {
        self.value.term = "TEST";
    }

    /// Another term reduces the number of hits
    pub fn transformAdditionalTerm(self: *QueryTest) void {
        self.additional_term = true;
        self.value.term = "test another";
    }

    /// Number of total hits shouldn't change when changing sort order, page count and casing.
    /// However, we do expect multiple search terms to reduce the number of hits.
    /// These are two metamorphic relations, one of which is checked conditionally.
    pub fn check(self: *QueryTest, untransformed_hits: usize, hits_after_transformations: usize) bool {
        if (self.additional_term) return untransformed_hits >= hits_after_transformations;
        return untransformed_hits == hits_after_transformations;
    }

    /// Execute the query, returning the total number of hits. A real-world test could do a mocked REST call.
    pub fn execute(self: *QueryTest) usize {
        // Emulate fewer hits when additional search terms are added
        return if (self.additional_term) 50 else 100;
    }
};

test "query" {
    var query_test = QueryTest{ .value = .{} };
    try std.testing.expect(try marble.run(QueryTest, &query_test, .{ .skip_combinations = false, .verbose = false }));
}
