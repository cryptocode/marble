<img align="right" width="320" src="https://user-images.githubusercontent.com/34946442/159163318-432052e3-69c7-4598-aaac-74d54f67c8b4.png">

Marble is an experimental [metamorphic testing](https://en.wikipedia.org/wiki/Metamorphic_testing) library for Zig.

Metamorphic testing is a powerful technique that provides additional test coverage by applying a number of transformations to test input, and then checking if certain relations still hold between the outputs. Marble will automatically run through all possible combinations of these transformations.

Metamorphic testing does not aspire to replace oracle based input/output testing, but should rather be viewed as a new gadget in the toolbox. While it requires some creativity and effort to come up with a good metamorphic test, you might be rewarded with the uncovering of issues that would otherwise go unnoticed. This applies not only to correctness tests, but also non-functional tests such as performance.

This library tracks Zig master until Zig 1.0 is released.

## Resources
* [Hillel Wayne's blog post on Metamorphic Testing (highly recommended)](https://www.hillelwayne.com/post/metamorphic-testing/)
* [Test your Machine Learning Algorithm with Metamorphic Testing](https://medium.com/trustableai/testing-ai-with-metamorphic-testing-61d690001f5c)
* [Original paper by T.Y. Chen et al](https://www.cse.ust.hk/~scc/publ/CS98-01-metamorphictesting.pdf)
* [Case study T.Y. Chen et al](http://grise.upm.es/rearviewmirror/conferencias/jiisic04/Papers/25.pdf)
* [Metamorphic Testing and Beyond T.Y. Chen et al](https://www.cs.hku.hk/data/techreps/document/TR-2003-06.pdf)
* [Survey on Metamorphic Testing](http://www.cs.ecu.edu/reu/reufiles/read/metamorphicTesting-16.pdf)
* [Performance Metamorphic Testing](http://www.lsi.us.es/~jtroya/publications/NIER17_at_ICSE17.pdf)
* [Experiences from Three Fuzzer Tools](https://johnwickerson.github.io/papers/dreamingup_MET21.pdf)
* [Monarch, a similar library for Rust](https://github.com/zmitchell/monarch/blob/master/src/runner.rs)

## Building

To build and run test examples:

```bash
zig build
zig build test
```

## Importing the library
Add Marble as a Zig package in your build file, or simply import it directly after vendoring/adding a submodule:

```zig
const marble = @import("marble/main.zig");
```

## Writing tests

A metamorphic Zig test looks something like this:

```zig
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
```

You will get compile time errors if the requirements for a metamorphic test are not met. Even making a typo like `transfrmPi` will be caught (you can add other non-public functions though)

In short, you must provide a `value` field, a `check` function, an `execute` function and one or more `transform...` functions.

### Writing transformations
Add one more functions starting with `transform...` 

Marble will execute all combinations of the transformation functions. After every
combination, `execute` is called followed by `check`.

Transformations should change the `value` property - Marble will remember what it was originally. The transformations must be such that `check`
succeeds. That is, the relations between the inital output and the transformed output must still hold.

### Checking if relations still hold
You must provide a `check` function to see if one or more relations hold, and return true if so. If false is returned, the test fails with a print-out of the current transformation-combination.

Relation checks may be conditional; check out the tests for examples on how this works.

### Executing
You must provide an `execute` function that computes a result based on the current value. The simplest form will simply return the current value, but you can
do any arbitrary operation here. This function is called before any transformations to form a baseline. This baseline is passed as the first argument to `check`

### Optional before/after calls

Before and after the test, and every combination, `before(...)` and `after(...)` is called if present. This is useful to reset state, initialize test cases, and perform clean-up.

### What happens during a test run?

Using the example above, the following pseudocode runs will be performed:

```
baseline = execute()

// First combination
transformPi()
out = execute()
check(baseline, out)

// Second combination
transformEpsilon()
out = execute()
check(baseline, out)

// Third combination
transformPi()
transformEpsilon()
out = execute()
check(baseline, out)
```

### Configuring runs

The `run` function takes a `RunConfiguration`:

```zig
/// If set to true, only run each transformation once separately
skip_combinations: bool = false,

/// If true, print detailed information during the run
verbose: bool = false,
```

### Error reporting

If a test fails, the current combination being executed is printed. For instance, the following tells us that the combination of `transformAdditionalTerm` and `transformCase` caused the metamorphic relation to fail:

```
Test [2/2] test "query"... Test case failed with transformation(s):
  >> transformAdditionalTerm
  >> transformCase
```

### Terminology

* Source test case output: The output produced by `execute()` on the initial input. This is also known as the baseline.
* Derived test case output: The output produced by `execute()` after applying a specific combination of transformations.
* Metamorphic relation: A property that must hold when considering a source test case and a derived test case.
