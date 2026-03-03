# Fast Units

This document in an implementation plan for making this ruby gem fast.

# Context

This is an open source project. It's written in Ruby and heavily uses regex for parsing. This creates a few different performance issues. First, requiring the gem is very slow as it parses the a lot of files to create this initiaal library of units. Then, creating a new unit is slow because it relies heavily on a series of Regex.

## Discovered context

<!--- Coding agent should keep this updated with relevant finding about the repos and the problem -->

### Architecture

- **Core class:** `RubyUnits::Unit` (lib/ruby_units/unit.rb, 2324 lines) inherits from `Numeric`
- **Version:** 5.0.0 | **Ruby:** 3.2+ (tested on 4.0.1)
- **Registry:** 176 unit definitions, 375 unit map entries, 88 prefix map entries
- **Unit definitions** loaded from `lib/ruby_units/unit_definitions/` (prefix.rb, base.rb, standard.rb)
- **Cache system:** Two-level -- string->Unit cache (`RubyUnits::Cache`) and base unit cache

### Cold Start Path

`require 'ruby-units'` triggers:

1. Load unit.rb (compiles ~15 regex constants at class body parse time)
2. Load unit_definitions/ -- calls `Unit.define()` 176 times (prefix, base, standard)
3. `Unit.setup` iterates all 176 definitions calling `use_definition` which populates `prefix_map`, `unit_map`, `prefix_values`, `unit_values`
4. Builds `@unit_regex` and `@unit_match_regex` from all aliases (375+ patterns, lazily on first use)
5. Creates `Unit.new(1)` to prime the system

### String Parsing Hot Path

`Unit.new("5 kg*m/s^2")` goes through:

1. `initialize` -> `parse_array` -> `parse_single_arg` -> `parse_string_arg` -> `parse_string` -> `parse()`
2. `parse()` (line 2121-2292) is the bottleneck:
   - String duplication and gsub preprocessing (USD, degree symbol, commas, special chars)
   - Sequential regex matching: COMPLEX_NUMBER, RATIONAL_NUMBER, NUMBER_REGEX
   - Cache lookup by unit string
   - If uncached: prefix/unit regex collapsing via `gsub!` loops (`unit_regex`, `unit_match_regex`)
   - UNIT_STRING_REGEX scan, TOP_REGEX/BOTTOM_REGEX expansion
   - `unit_match_regex` scan for numerator/denominator
   - `prefix_map`/`unit_map` lookups to resolve aliases to canonical names
3. `finalize_initialization`: `update_base_scalar` -> `unit_signature`, `validate_temperature`, cache, freeze

### Arithmetic Hot Path

- **Addition/subtraction:** Requires `compatible_with?` check (signature comparison), converts both to base units, creates new Unit via hash constructor, then `convert_to` back
- **Multiplication:** `eliminate_terms` (builds hash counting unit occurrences), creates new Unit
- **Division:** Same as multiply but with Rational scalar and swapped num/den
- **Scalar multiply:** Fast path -- direct hash constructor, no eliminate_terms

### Key Observations

1. **Uncached string parsing** is ~1ms per simple unit, ~7ms for compound formats (feet-inch, lbs-oz) which create sub-units
2. **Cache hit** is ~20-60x faster than uncached parsing
3. **Addition/subtraction are 3-6x slower than multiplication** because they require base conversion + convert_to back
4. **`clear_cache` + re-parse** dominates the uncached benchmarks -- the regex work is significant but cache invalidation + re-population is costly too
5. **Parenthesized syntax** like `kg/(m*s^2)` is not supported -- must use negative exponents: `kg*m*s^-2`
6. **Temperature units** bypass the standard cache, making them slower for repeated operations

# Benchmark

Create a benchmark that tests the performance of a cold start (requiring the gem) and creating a new unit. This will help us understand the current performance and track improvements.

Also, create a benchmark that parses large amounts of complex units to see how the performance scales with complexity.

The benchmark should be a reusable script we can easily invoke (or a set of scripts)

## Benchmark Scripts

- `spec/benchmarks/cold_start.rb` -- measures `require 'ruby-units'` time (subprocess per iteration)
  - Run: `ruby spec/benchmarks/cold_start.rb`
- `spec/benchmarks/unit_operations.rb` -- comprehensive benchmark-ips suite covering creation, caching, conversion, arithmetic, and complexity scaling
  - Run: `ruby -I lib spec/benchmarks/unit_operations.rb`

## Benchmark Results

<!--- Coding agent should keep this updated with benchmark results for various versions. -->

### Baseline: v5.0.0 on Ruby 4.0.1 (aarch64-linux)

#### Cold Start (require time)

| Metric  | Time   |
| ------- | ------ |
| Average | 0.276s |
| Min     | 0.261s |
| Max     | 0.292s |

#### Unit Creation (uncached -- cache cleared each iteration)

| Format                  | Throughput | Time/op |
| ----------------------- | ---------- | ------- |
| simple: `1 m`           | 922 i/s    | 1.08 ms |
| compound: `1 kg*m/s^2`  | 891 i/s    | 1.12 ms |
| temperature: `37 degC`  | 441 i/s    | 2.27 ms |
| prefixed: `1 km`        | 431 i/s    | 2.32 ms |
| rational: `1/2 cup`     | 381 i/s    | 2.62 ms |
| scientific: `1.5e-3 mm` | 299 i/s    | 3.35 ms |
| lbs-oz: `8 lbs 8 oz`    | 141 i/s    | 7.08 ms |
| feet-inch: `6'4"`       | 140 i/s    | 7.14 ms |

#### Unit Creation (cached -- repeated same unit)

| Format                 | Throughput | Time/op |
| ---------------------- | ---------- | ------- |
| numeric: `Unit.new(1)` | 189k i/s   | 5.3 us  |
| hash constructor       | 81k i/s    | 12.3 us |
| cached: `1 m`          | 39k i/s    | 25.4 us |
| cached: `5 kg*m/s^2`   | 17k i/s    | 57.7 us |

#### Conversions

| Conversion   | Throughput | Time/op |
| ------------ | ---------- | ------- |
| to_base (km) | 20.5k i/s  | 48.8 us |
| km -> m      | 11.2k i/s  | 89.0 us |
| mph -> m/s   | 11.1k i/s  | 90.2 us |
| m -> km      | 5.3k i/s   | 188 us  |
| degC -> degF | 4.2k i/s   | 240 us  |

#### Arithmetic Operations

| Operation              | Throughput | Time/op |
| ---------------------- | ---------- | ------- |
| scalar multiply: 5m\*3 | 27.7k i/s  | 36 us   |
| power: (5m)\*\*2       | 20.3k i/s  | 49 us   |
| divide: 5m/10s         | 17.4k i/s  | 58 us   |
| multiply: 5m\*2kg      | 15.3k i/s  | 65 us   |
| addition: 5m+3m        | 9.1k i/s   | 110 us  |
| subtraction: 5m-3m     | 4.3k i/s   | 233 us  |

#### Complexity Scaling (batch of 5-7 units, uncached)

| Complexity                   | Throughput | Time/batch |
| ---------------------------- | ---------- | ---------- |
| complex (kg\*m/s^2 etc)      | 153 i/s    | 6.6 ms     |
| very complex (5+ terms)      | 140 i/s    | 7.1 ms     |
| simple (m, kg, s -- 7 units) | 108 i/s    | 9.2 ms     |
| medium (km, kPa -- 7 units)  | 60 i/s     | 16.7 ms    |

# Requirements

- We want a drop-in replacement to the gem.
- All tests should continue to pass without modification.
- Performance should improve significantly, ideally by an order of magnitude for string parsing and arithmetic.
- The code should remain maintainable and not introduce excessive complexity or dependencies.

# Solutions

## C extension for the computational core + pure-Ruby cold start fixes

Two-pronged approach: a C extension (via Ruby's native C API) that owns the hot computational paths -- parsing, `to_base`, `unit_signature`, `eliminate_terms`, `convert_to` scalar math -- and pure-Ruby cold start optimizations that eliminate redundant work during `require`.

### Why C extension over other approaches

We evaluated StringScanner + hash (pure Ruby), Parslet/Treetop (parser generators), Rust via FFI, Ragel, and single-pass refactoring. All parser-only approaches hit the same ceiling: `finalize_initialization` accounts for ~60-70% of Unit creation time, and arithmetic creates 1-3 intermediate Unit objects per operation. Pure-Ruby optimizations cap at 2-5x for uncached parsing with zero improvement on cached creation or arithmetic.

A C extension using Ruby's native C API (`rb_define_method`, `VALUE`, `rb_hash_aref`) avoids the marshaling boundary that capped Rust FFI gains. C code operates on Ruby objects directly -- no serialization, no data copying, no registry sync. This means the entire computational pipeline (parse + `to_base` + signature + `eliminate_terms`) can run in C while reading the Ruby-side registry hashes natively.

**C vs Rust for this problem:**

| Factor              | Rust via FFI                    | C extension                      |
| ------------------- | ------------------------------- | -------------------------------- |
| Call Ruby methods   | FFI callback (~1-5us)           | `rb_funcall` (~0.1us)            |
| Access Ruby hashes  | Marshal across boundary         | `rb_hash_aref` -- direct         |
| Create Ruby objects | Build + marshal back            | `rb_obj_alloc` + set ivars       |
| Temperature lambdas | Can't call Ruby procs easily    | `rb_proc_call` -- trivial        |
| Registry access     | Must copy/sync to Rust          | Read Ruby Hash objects in C      |
| Build toolchain     | Cargo + cross-compile           | `mkmf` -- standard `gem install` |
| Installation        | Needs Rust or prebuilt binaries | Every Ruby has a C compiler      |

### Architecture

**C extension (~500-800 lines) handles:**

- String parsing (replaces `parse()`) -- single-pass tokenizer with hash-based unit lookup
- `to_base` computation -- walk tokens, look up conversion factors via `rb_hash_aref` on `prefix_values`/`unit_values`
- `unit_signature` computation -- walk tokens, look up definition kinds
- `base?` check -- iterate tokens, check definitions
- `eliminate_terms` -- count unit occurrences, rebuild numerator/denominator
- `convert_to` scalar math -- compute conversion factor between unit pairs

**Ruby retains:**

- `Unit.define` / `redefine!` / `undefine!` API and definition management
- Caching layer (`RubyUnits::Cache`)
- Arithmetic operator dispatch (`+`, `-`, `*`, `/` method definitions that call C helpers)
- Object lifecycle (freeze, dup, clone)
- All public API surface

**The C functions read Ruby state directly:**

```c
// Example: to_base computation in C
VALUE rb_unit_compute_base_scalar(VALUE self) {
    VALUE klass = rb_obj_class(self);
    VALUE prefix_vals = rb_funcall(klass, rb_intern("prefix_values"), 0);
    VALUE unit_vals = rb_funcall(klass, rb_intern("unit_values"), 0);
    VALUE numerator = rb_ivar_get(self, id_numerator);
    VALUE denominator = rb_ivar_get(self, id_denominator);
    VALUE scalar = rb_ivar_get(self, id_scalar);

    // Walk tokens, multiply/divide conversion factors
    // All hash lookups via rb_hash_aref -- native speed, no copying
    VALUE base_scalar = compute_conversion(scalar, numerator, denominator,
                                           prefix_vals, unit_vals);
    rb_ivar_set(self, id_base_scalar, base_scalar);
    return base_scalar;
}
```

No registry sync needed. Dynamic `Unit.define` just mutates the Ruby hashes -- the C code reads them on next call.

### Phase 1: Cold start optimization (pure Ruby, 276ms -> ~60-90ms)

Independent of the C extension. Ships first since it's pure Ruby with zero build complexity.

**Cost breakdown of 276ms boot:**

| Component                                                         | Estimated Time | Percentage  |
| ----------------------------------------------------------------- | -------------- | ----------- |
| Ruby VM + stdlib loading                                          | ~30-50ms       | ~11-18%     |
| File loading (require_relative chain)                             | ~10-15ms       | ~4-5%       |
| **Unit.new string parsing in definition blocks (~138 calls)**     | **~80-120ms**  | **~29-43%** |
| **Regex rebuilds (132x each of 4 patterns)**                      | **~35-60ms**   | **~13-22%** |
| **to_base cascades from definition= setter**                      | **~30-50ms**   | **~11-18%** |
| Hash constructor Units + finalize_initialization                  | ~20-30ms       | ~7-11%      |
| cache.set overhead (special_format_regex in should_skip_caching?) | ~10-20ms       | ~4-7%       |

**Root cause:** Each of the 132 standard definitions calls `Unit.define`, which runs a block containing `Unit.new("254/10000 meter")` or similar. Each `Unit.new` triggers full string parsing. Then `use_definition` calls `invalidate_regex_cache`, clearing the memoized regexes. The NEXT definition's `Unit.new` rebuilds them -- now one entry larger. This happens 132 times.

**Fix 1a: Batch definition loading (~35-60ms savings)**

Wrap definition loading in a `batch_define` mode that defers regex invalidation. Don't nil out `@unit_regex`/`@unit_match_regex` during batch loading -- let them be stale. Definition blocks only reference previously-defined units, so a stale regex is sufficient. Build all regexes once at end of batch.

```ruby
def self.batch_define
  @loading = true
  yield
ensure
  @loading = false
  invalidate_regex_cache
end
```

Risk: Very low. Definitions are ordered so each only references previously-defined units.

**Fix 1b: Pre-compute definition values (~110-170ms savings)**

Replace `definition=` calls that use `Unit.new(string)` with pre-computed scalar/numerator/denominator values. Eliminates ~138 `Unit.new` string parsing calls and ~132 `to_base` cascades during boot.

Current:

```ruby
RubyUnits::Unit.define("inch") do |inch|
  inch.definition = RubyUnits::Unit.new("254/10000 meter")
end
```

Optimized:

```ruby
RubyUnits::Unit.define("inch") do |inch|
  inch.scalar = Rational(254, 10000)
  inch.numerator = %w[<meter>]
  inch.denominator = %w[<1>]
end
```

Risk: Medium. Requires pre-computing base-unit representations for 132 definitions. Mitigated by a CI verification script that loads both ways and compares all values.

**Combined Phase 1 result: ~60-90ms boot** (3-4x improvement). The floor is Ruby VM startup (~30ms) + file loading (~15ms) + lightweight hash assignments (~10ms).

### Phase 2: C extension for parsing (uncached ~30-40x faster)

Replace the 170-line `parse()` method with a C function that does a single left-to-right scan. Uses `rb_hash_aref` to look up units/prefixes in the existing Ruby hashes -- no 375-way regex alternation.

**What the C parser does:**

1. Normalize input (dollar signs, degree symbols, separators, special chars) -- character-level, one pass
2. Detect number format (complex, rational, scientific, integer) -- returns a Ruby Numeric via `rb_rational_new`, `rb_complex_new`, `rb_float_new`, or `INT2NUM`
3. Detect compound formats (time, feet-inch, lbs-oz, stone-lb) -- return structured data for Ruby to handle recursion
4. Tokenize unit expression -- walk left-to-right, resolve each token via hash lookup (longest match in `unit_map`, fall back to prefix+unit decomposition)
5. Handle exponents inline -- `s^2` emits `s` twice, no string expansion
6. Return scalar + numerator array + denominator array

**Prefix-unit disambiguation in C:**

```c
// Try longest match in unit_map first
for (int len = remaining; len > 0; len--) {
    VALUE substr = rb_str_new(pos, len);
    VALUE canonical = rb_hash_aref(unit_map, substr);
    if (canonical != Qnil) { /* found unit, no prefix needed */ }
}
// Fall back to prefix + unit decomposition
for (int plen = max_prefix_len; plen > 0; plen--) {
    VALUE prefix_str = rb_str_new(pos, plen);
    VALUE prefix_canonical = rb_hash_aref(prefix_map, prefix_str);
    if (prefix_canonical != Qnil) {
        // try remaining as unit...
    }
}
```

Hash lookups are O(1) each. The whole parse is O(input_length \* max_unit_name_length) in the worst case, which for typical inputs (~10-30 chars, max unit name ~20 chars) is trivially fast.

**Expected parse time:** ~1-5us (vs current ~500-600us for the parse step alone).

### Phase 3: C extension for finalize_initialization (cached/arithmetic ~10-40x faster)

Move `update_base_scalar`, `unit_signature`, `base?`, and `eliminate_terms` into C. These currently dominate the post-parse cost.

**What moves to C:**

| Function                   | Current cost | In C     | What it does                                           |
| -------------------------- | ------------ | -------- | ------------------------------------------------------ |
| `base?`                    | ~3-8us       | ~0.1us   | Iterate tokens, check definitions via `rb_hash_aref`   |
| `to_base`                  | ~20-50us     | ~1-3us   | Walk tokens, multiply conversion factors, build result |
| `unit_signature`           | ~5-10us      | ~0.5us   | Walk tokens, look up kinds, compute signature vector   |
| `eliminate_terms`          | ~5-15us      | ~0.5-1us | Count token occurrences, rebuild arrays                |
| `convert_to` (scalar math) | ~15-30us     | ~1-2us   | Compute conversion factor between unit pairs           |

**Temperature handling:** Temperature definitions store conversion lambdas. The C code calls them via `rb_proc_call` -- no special handling needed.

**What stays in Ruby:**

- `validate_temperature` -- trivial check, not worth C overhead
- `cache_unit_if_needed` -- interacts with Ruby Cache object
- `freeze_instance_variables` -- Ruby concept
- Arithmetic operator dispatch -- Ruby methods that call C helpers for the math

### Phase 4: C-accelerated arithmetic (same-unit and cross-unit)

**Same-unit fast path in C:**

```c
VALUE rb_unit_add(VALUE self, VALUE other) {
    // Compare numerator/denominator arrays (pointer equality for frozen arrays)
    if (rb_equal(num_self, num_other) && rb_equal(den_self, den_other)) {
        // Same units: just add scalars, construct result directly
        VALUE new_scalar = rb_funcall(scalar_self, '+', 1, scalar_other);
        return rb_unit_new_from_parts(klass, new_scalar, num_self, den_self, sig_self);
    }
    // Different units: compute base scalars in C, convert back in C
    // ...
}
```

**Cross-unit multiply/divide in C:**
`eliminate_terms` + result construction happens in C. Only the final `Unit.new` allocation returns to Ruby.

### Expected combined gains

> **NOTE:** Phase 2 only replaces `parse()`. Since `finalize_initialization` is ~60-70% of uncached creation time (~600-700us), Phase 2 alone yields only ~1.5-2x for uncached creation. The large uncached gains require Phase 3 (C finalize). Cached creation and arithmetic also require Phase 3-4.

| Metric                               | Current   | Phase 1 (Ruby) | + Phase 2 (C parse) | + Phase 3 (C finalize) | + Phase 4 (C arith) |
| ------------------------------------ | --------- | -------------- | ------------------- | ---------------------- | ------------------- |
| **Cold start**                       | **276ms** | **~60-90ms**   | ~60-90ms            | ~60-90ms               | ~60-90ms            |
| **Uncached simple (`1 m`)**          | **1ms**   | ~1ms           | **~600-700us**      | **~15-30us**           | ~15-30us            |
| **Uncached compound (`1 kg*m/s^2`)** | **1.1ms** | ~1.1ms         | **~700-800us**      | **~20-40us**           | ~20-40us            |
| **Uncached special (`6'4"`)**        | **7ms**   | ~7ms           | ~5-6ms              | **~0.1-0.3ms**         | ~0.1-0.3ms          |
| **Cached `1 m`**                     | **25us**  | ~25us          | ~25us               | **~3-5us**             | ~3-5us              |
| **Cached `5 kg*m/s^2`**              | **58us**  | ~58us          | ~58us               | **~5-8us**             | ~5-8us              |
| **Addition (same unit)**             | **110us** | ~110us         | ~110us              | ~60-80us               | **~3-8us**          |
| **Subtraction (same unit)**          | **233us** | ~233us         | ~233us              | ~80-120us              | **~3-8us**          |
| **Conversion km->m**                 | **89us**  | ~89us          | ~89us               | **~5-10us**            | ~5-10us             |
| **Multiply 5m\*2kg**                 | **65us**  | ~65us          | ~65us               | ~30-40us               | **~5-10us**         |
| **Hash constructor**                 | **12us**  | ~12us          | ~12us               | **~2-4us**             | ~2-4us              |

### Complexity and phasing

| Phase     | What                                 | Effort         | Risk       | Ships independently?            | Standalone value?      |
| --------- | ------------------------------------ | -------------- | ---------- | ------------------------------- | ---------------------- |
| Phase 1   | Cold start + cache fixes (pure Ruby) | 3-5 days       | Low-Medium | Yes                             | High (3-4x cold start) |
| Phase 2   | C parser                             | 2-3 weeks      | Medium     | Marginal alone (~1.5x uncached) | Low without Phase 3    |
| Phase 3   | C finalize_initialization            | 2-3 weeks      | Medium     | Yes (with Phase 2)              | High (30-40x uncached) |
| Phase 4   | C arithmetic fast paths              | 3-5 days       | Low        | Yes (with Phase 3)              | Medium (10-30x arith)  |
| **Total** |                                      | **6-10 weeks** |            |                                 |                        |

**Phasing recommendation:** Phase 1 ships first as a pure-Ruby improvement. Phase 2 should NOT ship alone — its ~1.5x uncached improvement doesn't justify the C extension maintenance cost. Bundle Phases 2+3 as a single deliverable. Phases 2-4 build the C extension incrementally — each phase adds functions to the same `ext/` directory, and the gem falls back to pure Ruby if the extension isn't compiled (development mode, unsupported platforms).

### Build and distribution

- **Extension setup:** Standard `ext/ruby_units/extconf.rb` using `mkmf`. No external dependencies beyond a C compiler (which every `gem install` already requires for gems like `json`, `psych`, `strscan`).
- **Fallback:** Pure-Ruby implementation remains for development and platforms without a compiler. A `RubyUnits.native?` flag lets users check.
- **CI:** Add `rake compile` step before tests. Test both native and pure-Ruby paths.
- **Gem distribution:** `gem install ruby-units` compiles the extension automatically via `mkmf`. Pre-compiled native gems can be published for common platforms via `rake-compiler-dock` if desired.

### Risks

- **C memory safety:** No borrow checker. Mitigated by keeping the C code simple (~500-800 lines), using Ruby's GC-safe allocation APIs, and testing with `ASAN`/`Valgrind` in CI.
- **Contributor accessibility:** Contributors need basic C familiarity. Mitigated by keeping C code focused on computation (no complex data structures, no manual memory management beyond Ruby's API). Many popular Ruby gems have C extensions (nokogiri, pg, msgpack, oj, redcarpet).
- **JRuby incompatibility:** C extensions don't work on JRuby. The pure-Ruby fallback path handles this. JRuby users get current performance; CRuby users get the acceleration.
- **Maintenance surface:** Two implementations of the hot path (C and Ruby fallback). Mitigated by comprehensive test suite (400+ tests) run against both paths in CI.
- **Rational/Complex arithmetic in C:** Must use `rb_rational_new`/`rb_complex_new` and Ruby's arithmetic methods. More verbose than Ruby but straightforward -- the C code delegates to Ruby's numeric layer via `rb_funcall`.

### Missed optimizations to add

**Phase 1 additions (pure Ruby, easy wins):**

1. **Fix `should_skip_caching?` — O(n) → O(1).** `cache.rb:38-39` calls `keys.include?(key)` which allocates an Array via `data.keys` then does linear scan. Replace with `data.key?(key)` for O(1) hash lookup. The `special_format_regex` check could also be replaced with a frozen `Set` of known special keys. This affects every `cache.set` call.

2. **Generate pre-computed definitions via script, not by hand.** Phase 1b proposes manually converting 132 definitions. Instead: write a Ruby script that loads current definitions, captures computed scalar/numerator/denominator values, and generates the optimized file. More maintainable, less error-prone. Add a CI step that verifies generated output matches runtime computation.

3. **Investigate subtraction 2x slower than addition.** Benchmark shows 233us vs 110us for identical-looking code paths (non-zero, non-temperature, compatible units). Profile to find root cause — could reveal a pure-Ruby fix worth 2x for subtraction before the C extension.

**Phase 1 stretch (pure Ruby, medium effort):**

**Benchmark additions:**

5. **Add parse-vs-finalize breakdown benchmark.** The 60-70% finalize claim is central to phasing but unmeasured. Instrument `parse()` and `finalize_initialization()` separately using `Process.clock_gettime` to validate the split. This directly informs whether Phase 2 alone is worth shipping or should be bundled with Phase 3.

**C extension notes:**

6. **C extension size is likely 1500-2500 lines, not 500-800.** Parse alone (~170 lines Ruby) becomes ~500-800 lines C with all number formats, compound detection, Unicode, error handling. Adding to_base, unit_signature, eliminate_terms, convert_to, base? adds another ~700-1500 lines. This impacts Phases 2-3 effort estimates — total is likely 6-10 weeks rather than 4-7.

### Rejected alternatives

| Approach                               | Why rejected                                                                                                                                                   |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **StringScanner + hash (pure Ruby)**   | Caps at 2-5x for uncached parsing, zero improvement on cached/arithmetic. `finalize_initialization` remains the bottleneck.                                    |
| **Rust via FFI**                       | FFI marshaling boundary caps gains to 2-3x (same as pure Ruby). Registry sync complexity. Requires Rust toolchain or prebuilt binaries.                        |
| **Parser generator (Parslet/Treetop)** | 2-5x slower than current code. Pure Ruby interpreters replacing C-backed regex. Adds runtime dependencies.                                                     |
| **Ragel**                              | Fixed grammar at build time conflicts with runtime `Unit.define`. Same architecture as StringScanner but with `.rl` maintenance burden.                        |
| **Single-pass Ruby refactor**          | Same approach as StringScanner. 30-50% improvement -- subsumed by C extension.                                                                                 |
| **Pure-Ruby holistic (3-phase)**       | Caps at 2-5x uncached, 3-10x arithmetic. Good but an order of magnitude less than C extension for the hot paths. Cold start phase (Phase 1) is retained as-is. |
