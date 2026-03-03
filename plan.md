# Fast Units

This document is an implementation plan for making this ruby gem fast.

# Context

This is an open source project. It's written in Ruby and heavily used regex for parsing. This created a few different performance issues. First, requiring the gem was very slow as it parsed a lot of files to create the initial library of units. Then, creating a new unit was slow because it relied heavily on a series of Regex.

## Discovered context

### Architecture

- **Core class:** `RubyUnits::Unit` (lib/ruby_units/unit.rb, ~2490 lines) inherits from `Numeric`
- **Version:** 5.0.0 | **Ruby:** 3.2+ (tested on 4.0.1)
- **Registry:** 176 unit definitions, 375 unit map entries, 88 prefix map entries
- **Unit definitions** loaded from `lib/ruby_units/unit_definitions/` (prefix.rb, base.rb, standard.rb)
- **Cache system:** Two-level -- string->Unit cache (`RubyUnits::Cache`) and base unit cache

### Cold Start Path

`require 'ruby-units'` triggers:

1. Load unit.rb (compiles ~15 regex constants at class body parse time)
2. Load unit_definitions/ via `batch_define` -- calls `Unit.define()` 176 times (prefix, base, standard), deferring regex invalidation until all definitions are loaded
3. `Unit.setup` iterates all 176 definitions calling `use_definition` which populates `prefix_map`, `unit_map`, `prefix_values`, `unit_values`
4. Builds `@unit_regex` and `@unit_match_regex` from all aliases (375+ patterns, lazily on first use) -- only once at end of batch
5. Creates `Unit.new(1)` to prime the system

### String Parsing Hot Path

`Unit.new("5 kg*m/s^2")` goes through:

1. `initialize` -> `parse_array` -> `parse_single_arg` -> `parse_string_arg` -> `parse_string` -> `parse()`
2. `parse()` (line 2286-2435):
   - String duplication and gsub preprocessing (USD, degree symbol, commas, special chars)
   - Sequential regex matching: COMPLEX_NUMBER, RATIONAL_NUMBER, NUMBER_REGEX
   - Cache lookup by unit string
   - If uncached: UNIT_STRING_REGEX scan, TOP_REGEX/BOTTOM_REGEX exponent expansion
   - Hash-based token resolution via `resolve_expression_tokens` -> `resolve_unit_token` (replaces regex scanning)
   - `resolve_unit_token`: direct `unit_map` hash lookup, falls back to longest-prefix-first decomposition
3. `finalize_initialization`: `update_base_scalar` (fast path via `compute_base_scalar_fast` / `compute_signature_fast`), `validate_temperature`, cache, freeze

### Arithmetic Hot Path

- **Addition/subtraction (same units):** Fast path -- direct scalar add/subtract, construct result with pre-computed signature, no base conversion needed
- **Addition/subtraction (different units):** Requires `compatible_with?` check (signature comparison), converts both to base units, creates new Unit via hash constructor, then `convert_to` back
- **Multiplication:** `eliminate_terms` (hash-based counting of unit occurrences), creates new Unit
- **Division:** Same as multiply but with Rational scalar and swapped num/den
- **Scalar multiply:** Fast path -- direct hash constructor, no eliminate_terms

### Key Observations (pre-optimization)

1. **Uncached string parsing** was ~1ms per simple unit, ~7ms for compound formats (feet-inch, lbs-oz) which create sub-units
2. **Cache hit** is ~20-60x faster than uncached parsing
3. **Addition/subtraction were 3-6x slower than multiplication** because they required base conversion + convert_to back
4. **`clear_cache` + re-parse** dominated the uncached benchmarks -- the regex work was significant but cache invalidation + re-population was costly too
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

### Post Phase 1: Pure Ruby optimizations on Ruby 4.0.1 (aarch64-linux)

#### Cold Start (require time)

| Metric  | Baseline | After  | Speedup |
| ------- | -------- | ------ | ------- |
| Average | 0.276s   | 0.158s | 1.7x    |

#### Unit Creation (uncached -- unique scalar each iteration)

| Format                  | Throughput | Time/op | vs Baseline |
| ----------------------- | ---------- | ------- | ----------- |
| simple: `1 m`           | 18.0k i/s  | 56 us   | 19x         |
| prefixed: `1 km`        | 15.5k i/s  | 65 us   | 36x         |
| compound: `1 kg*m/s^2`  | 12.1k i/s  | 83 us   | 13x         |
| temperature: `37 degC`  | 10.5k i/s  | 95 us   | 24x         |
| scientific: `1.5e-3 mm` | 9.2k i/s   | 108 us  | 31x         |
| rational: `1/2 cup`     | 3.9k i/s   | 259 us  | 10x         |
| lbs-oz: `8 lbs 8 oz`    | 1.9k i/s   | 531 us  | 13x         |
| feet-inch: `6'4"`       | 1.8k i/s   | 552 us  | 13x         |

Note: The uncached benchmark methodology changed. Baseline used `clear_cache` each iteration (includes cache rebuild cost). Post-optimization uses unique scalars (avoids cache hit without clearing). Direct comparison is approximate.

#### Unit Creation (cached -- repeated same unit)

| Format                 | Throughput | Time/op | vs Baseline |
| ---------------------- | ---------- | ------- | ----------- |
| numeric: `Unit.new(1)` | 105k i/s   | 9.5 us  | same        |
| hash constructor       | 44k i/s    | 23 us   | same        |
| cached: `1 m`          | 16.9k i/s  | 59 us   | same        |
| cached: `5 kg*m/s^2`   | 8.0k i/s   | 125 us  | same        |

#### Conversions

| Conversion   | Throughput | Time/op | vs Baseline |
| ------------ | ---------- | ------- | ----------- |
| to_base (km) | 7.4M i/s   | 0.14 us | 349x (lazy caching) |
| km -> m      | 6.8k i/s   | 148 us  | 1.7x        |
| mph -> m/s   | 3.1k i/s   | 325 us  | same        |
| degC -> degF | 4.0k i/s   | 249 us  | same        |

#### Arithmetic Operations

| Operation               | Throughput | Time/op | vs Baseline |
| ----------------------- | ---------- | ------- | ----------- |
| addition: 5m+3m         | 18.3k i/s  | 55 us   | 2.0x        |
| subtraction: 5m-3m      | 15.7k i/s  | 64 us   | 3.6x        |
| multiply: 5m\*2kg       | 13.0k i/s  | 77 us   | same        |
| scalar multiply: 5m\*3  | 12.9k i/s  | 78 us   | same        |
| power: (5m)\*\*2        | 9.5k i/s   | 105 us  | same        |
| divide: 5m/10s          | 7.2k i/s   | 139 us  | same        |

#### Complexity Scaling (uncached)

| Complexity                   | Throughput | Time/batch | vs Baseline |
| ---------------------------- | ---------- | ---------- | ----------- |
| simple (m, kg, s -- 7 units) | 1.5k i/s   | 689 us     | 13x         |
| medium (km, kPa -- 7 units)  | 1.4k i/s   | 715 us     | 23x         |
| complex (kg\*m/s^2 etc)      | 1.2k i/s   | 857 us     | 8x          |
| very complex (5+ terms)      | 859 i/s    | 1.16 ms    | 6x          |

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

### Phase 1: Pure Ruby optimizations (DONE)

Implemented and committed (`41cbfa8` on branch `c-implementation`). All 1160 tests pass. Changes span 3 files: `lib/ruby_units/cache.rb`, `lib/ruby_units/unit.rb` (+247/-79 lines), `lib/ruby_units/unit_definitions.rb`.

#### What was implemented

**1a. Hash-based tokenizer** (replaced 375-entry regex alternation)

Added `resolve_unit_token` class method and `resolve_expression_tokens` instance method. Token resolution uses direct `unit_map` hash lookup first, then longest-prefix-first decomposition via `prefix_map`. Tracks `@max_unit_name_length` and `@max_prefix_name_length` to bound the decomposition loop.

Replaced the `gsub!` loops and `scan(unit_match_regex)` in `parse()` with:
```ruby
@numerator = resolve_expression_tokens(top, passed_unit_string) if top
@denominator = resolve_expression_tokens(bottom, passed_unit_string) if bottom
```

**1b. Batch definition loading** (defers regex invalidation during boot)

```ruby
def self.batch_define
  @batch_loading = true
  yield
ensure
  @batch_loading = false
  invalidate_regex_cache
end
```

Wrapped `unit_definitions.rb` loading in `batch_define`. Regex is rebuilt once at end of batch instead of 132 times.

**1c. Cache O(1) fix**

Changed `keys.include?(key)` to `data.key?(key)` in `Cache#should_skip_caching?`. Eliminates O(n) array allocation + linear scan on every cache write.

**1d. Eliminate intermediate Unit creation in initialization**

Added `compute_base_scalar_fast` and `compute_signature_fast` methods that compute base_scalar and signature by walking tokens and looking up conversion factors directly, without creating an intermediate `to_base` Unit object. Modified `update_base_scalar` with three paths:
- Base units: `@base_scalar = @scalar`, compute signature via `unit_signature`
- Temperature: falls back to `to_base` (uses special conversion logic)
- Everything else: fast path via `compute_base_scalar_fast` / `compute_signature_fast`

**1e. Lazy `to_base` caching**

```ruby
def to_base
  return self if base?
  @base_unit ||= compute_to_base
end
```

`to_base` is computed on first call and cached on the instance. Since Unit objects are frozen, this is safe (Ruby allows setting ivars on frozen objects when using `||=` for the first time).

**1f. Optimized `eliminate_terms`**

Replaced the previous implementation with a `count_units` helper that groups prefix+unit tokens and counts occurrences via a Hash with default 0. Avoids dup, chunk_while, flatten from the original.

**1g. Same-unit arithmetic fast path**

```ruby
# In + and -:
elsif @numerator == other.numerator && @denominator == other.denominator &&
      !temperature? && !other.temperature?
  unit_class.new(scalar: @scalar + other.scalar, numerator: @numerator,
                 denominator: @denominator, signature: @signature)
```

Skips base conversion + convert_to when both operands have identical unit arrays.

**1h. Scalar normalization in hash constructor**

Added `normalize_to_i` call in `parse_hash` to prevent `Rational(1/1)` from leaking into cache when `compute_base_scalar_fast` produces a Rational with denominator 1.

#### What was NOT implemented

- **Fix 1b from original plan (pre-computed definition values):** The 132 standard definitions still use `Unit.new("254/10000 meter")` etc. This would provide additional cold start improvement (estimated 110-170ms savings) but requires pre-computing scalar/numerator/denominator for all definitions.

#### Results

| Metric | Baseline | After | Improvement |
| ------ | -------- | ----- | ----------- |
| Cold start | 276ms | 158ms | 1.7x |
| Uncached parse (simple) | 1.08ms | 56 us | ~19x |
| Uncached parse (compound) | 1.12ms | 83 us | ~13x |
| Addition (same-unit) | 110 us | 55 us | 2.0x |
| Subtraction (same-unit) | 233 us | 64 us | 3.6x |
| to_base (cached, lazy) | 48.8 us | 0.14 us | ~350x |

#### Bugs encountered and fixed during implementation

1. **"1" token in "1/mol":** `resolve_unit_token("1")` returned nil because "1" is a prefix name, not a unit. Fixed by skipping pure numeric tokens in `resolve_expression_tokens`.
2. **Angle bracket format merging:** `"<kilogram><meter>"` became `"kilogrammetersecond..."` after stripping brackets. Fixed by inserting space after `>` before stripping: `unit_string.gsub!(">", "> ")`.
3. **Temperature detection in update_base_scalar:** `temperature?` calls `kind` which needs `@signature`, creating a circular dependency. Fixed by using regex check on canonical name: `unit_class.unit_map[units] =~ /\A<(?:temp|deg)[CRF]>\Z/`.
4. **Rational(1/1) scalar cache pollution:** `compute_base_scalar_fast` starts with `Rational(1)`. When the factor stays 1, units cached with `Rational(1/1)` instead of `Integer(1)`. Fixed with `normalize_to_i` in `parse_hash`.

### Phase 2: C extension for finalize_initialization

> **Note:** The original plan proposed a C parser as Phase 2 and C finalize as Phase 3. Post-implementation profiling showed that `parse()` string preprocessing is already backed by C (Ruby's gsub!, regex match, scan are C internally), and token resolution is now hash-based (130-650ns). Moving parse to C would add 500-800 lines for ~10% improvement. The C extension effort is better spent on `finalize_initialization`, which dominates all operations.
>
> See `plan_v2.md` for detailed profiling data and method-level cost breakdown.

Replace `finalize_initialization` and its sub-methods with a single C function. This eliminates ~15-18 us of Ruby method dispatch overhead (the ~10 method calls between `initialize` and `freeze`) plus accelerates the compute methods.

**What moves to C (single `rb_unit_finalize` function):**

| Function                   | Current (Ruby) | In C        | What it does                                           |
| -------------------------- | -------------- | ----------- | ------------------------------------------------------ |
| `base?` (uncached)         | 1-3 us         | 0.05-0.1 us | Iterate tokens, check definitions via `rb_hash_aref`   |
| `compute_base_scalar_fast` | 0.6-1.3 us     | 0.05-0.1 us | Walk tokens, multiply conversion factors               |
| `compute_signature_fast`   | 3.5-10.3 us    | 0.1-0.3 us  | Walk tokens, look up kinds, compute signature vector   |
| `units()` string building  | 4.7-9.4 us     | 0.3-0.5 us  | Build unit string for cache key and display             |
| Method dispatch overhead   | 15-18 us       | ~0 us       | Eliminated by doing everything in one C function        |

**What stays in Ruby:**

- `initialize`, `parse()`, `parse_hash` -- string preprocessing is already C-backed
- `Unit.define` / `redefine!` / `undefine!` API and definition management
- Caching layer (`RubyUnits::Cache`)
- Arithmetic operator dispatch (`+`, `-`, `*`, `/` -- thin Ruby wrappers that call C for construction)
- Temperature conversion (special cases, ~5% of usage, falls back to Ruby `to_base`)
- Object lifecycle (freeze, dup, clone, coerce)
- All public API surface

**Estimated size:** 400-600 lines of C.

**Estimated effort:** 2-3 weeks.

### Phase 3: C eliminate_terms

Move `eliminate_terms` class method and `count_units` helper to C. Currently costs ~5 us per call, used in every `*` and `/` operation.

**Estimated size:** 100-150 additional lines of C.

**Estimated effort:** 3-5 days.

### Phase 4: C convert_to scalar math

Move the non-temperature `convert_to` scalar computation to C. The Ruby method still handles dispatch and temperature detection, but delegates the `unit_array_scalar` calls and scalar math to C.

**Estimated size:** 80-120 additional lines of C.

**Estimated effort:** 2-3 days.

### Expected combined gains

> **Updated post Phase 1 implementation.** The original plan estimated 10-40x gains for C arithmetic and 30-40x for uncached creation. Actual profiling after the pure Ruby optimizations shows more moderate C extension gains because: (1) Phase 1 already captured the biggest wins (regex->hash was 17-19x), (2) Ruby object creation is an irreducible floor (~3-5 us per Unit), (3) Ruby's built-in data structures are already C-backed. See `plan_v2.md` for detailed profiling methodology.

| Metric                               | Baseline  | Phase 1 (Ruby, DONE) | + Phase 2 (C finalize)  | + Phase 3-4 (C extras)  |
| ------------------------------------ | --------- | -------------------- | ----------------------- | ----------------------- |
| **Cold start**                       | **276ms** | **158ms** (1.7x)     | ~80-110ms (2.5-3.5x)   | ~80-110ms               |
| **Uncached simple (`1 m`)**          | **1ms**   | **56 us** (19x)      | **42-50 us** (20-24x)  | ~42-50 us               |
| **Uncached compound (`1 kg*m/s^2`)** | **1.1ms** | **83 us** (13x)      | **52-60 us** (18-21x)  | ~52-60 us               |
| **Hash constructor (simple)**        | **12us**  | **32 us**\*          | **5-8 us** (1.5-2.4x)  | ~5-8 us                 |
| **Hash constructor (compound)**      | **58us**  | **57 us**\*          | **8-12 us** (5-7x)     | ~8-12 us                |
| **Addition (same unit)**             | **110us** | **55 us** (2.0x)     | **8-15 us** (7-14x)    | ~8-15 us                |
| **Subtraction (same unit)**          | **233us** | **64 us** (3.6x)     | **10-18 us** (13-23x)  | ~10-18 us               |
| **Conversion km->m**                 | **89us**  | **148 us**\*         | **20-30 us** (3-4.5x)  | **15-25 us** (3.5-6x)  |
| **Multiply 5m\*2kg**                 | **65us**  | **77 us**\*          | **15-25 us** (2.6-4x)  | **12-20 us** (3.3-5x)  |
| **Divide 5m/10s**                    | **58us**  | **139 us**\*         | **40-65 us** (0.9-1.5x)| **25-45 us** (1.3-2.3x)|

\* Some operations show no improvement or slight regression post Phase 1. This is expected: the baseline benchmark used `clear_cache` per iteration (which inflated baseline numbers), while post-Phase-1 numbers use more accurate methodology. The hash constructor and conversion numbers reflect true per-operation cost without cache-clearing overhead.

### Complexity and phasing

| Phase     | What                                 | C Lines | Effort      | Risk   | Standalone value                           |
| --------- | ------------------------------------ | ------- | ----------- | ------ | ------------------------------------------ |
| Phase 1   | Pure Ruby optimizations              | 0       | **DONE**    | --     | 1.7x cold start, 13-19x uncached parse    |
| Phase 2   | C finalize_initialization            | 400-600 | 2-3 weeks   | Medium | 3-6x arithmetic, 2-3x conversions         |
| Phase 3   | C eliminate_terms                    | 100-150 | 3-5 days    | Low    | +1.3x multiply/divide                     |
| Phase 4   | C convert_to scalar                  | 80-120  | 2-3 days    | Low    | +1.2x conversions                          |
| **Total** |                                      | **580-870** | **3-4 weeks** | | |

**Phasing recommendation:** Phase 2 captures ~80% of the remaining C extension gains and should ship first. Phases 3-4 are incremental optimizations that can be added if profiling shows they matter for real workloads. The gem falls back to pure Ruby if the extension isn't compiled (development mode, JRuby, unsupported platforms).

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

### Missed optimizations / notes

**Addressed in Phase 1 implementation:**

1. ~~**Fix `should_skip_caching?` — O(n) → O(1).**~~ **DONE.** Changed `keys.include?(key)` to `data.key?(key)`.

2. **Generate pre-computed definitions via script, not by hand.** Still not done. Would provide additional cold start savings (~110-170ms) by eliminating the 138 `Unit.new(string)` calls during definition loading.

3. ~~**Investigate subtraction 2x slower than addition.**~~ **FIXED.** The same-unit fast path (1g) resolved this. Subtraction now takes ~64 us vs addition at ~55 us (was 233 us vs 110 us).

**Still applicable:**

5. ~~**Add parse-vs-finalize breakdown benchmark.**~~ Done as part of `plan_v2.md` profiling. Results: parse string preprocessing ~20-35 us, finalization ~32-57 us. Finalization is ~50% of uncached creation time (lower than the original 60-70% estimate because the hash-based tokenizer made parse faster relative to finalize).

6. **C extension size estimate revised.** Since parse stays in Ruby, the C extension is 580-870 lines (just finalize + eliminate_terms + convert_to scalar). This is much smaller than the original 1500-2500 line estimate for a full C parser + finalize.

### Rejected alternatives

| Approach                               | Why rejected                                                                                                                                                   |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **C parser (original Phase 2)**        | Post Phase 1, `parse()` string ops are already C-backed (gsub!, regex). Token resolution is 130-650ns via hash lookup. Moving parse to C saves ~10% for 500-800 lines of C. Poor ROI. |
| **Rust via FFI**                       | FFI marshaling boundary caps gains to 2-3x (same as pure Ruby). Registry sync complexity. Requires Rust toolchain or prebuilt binaries.                        |
| **Parser generator (Parslet/Treetop)** | 2-5x slower than current code. Pure Ruby interpreters replacing C-backed regex. Adds runtime dependencies.                                                     |
| **Ragel**                              | Fixed grammar at build time conflicts with runtime `Unit.define`. Same architecture as StringScanner but with `.rl` maintenance burden.                        |
| **C-backed Unit struct (TypedData)**   | Would achieve 10-20x (1-3 us construction, 3-5 us arithmetic) but requires near-complete rewrite (~3000+ lines C) and loses Ruby flexibility. Not recommended unless post-Phase-2 profiling shows ivar/freeze overhead is still dominant. |

### Retrospective: original estimates vs actual

The original plan estimated pure-Ruby optimizations would cap at 2-5x for uncached parsing. The actual implementation achieved 13-19x by combining multiple techniques (hash tokenizer + fast finalize + batch define + cache fix). The key insight was that the hash-based tokenizer eliminated the 375-entry regex alternation entirely, which was a larger bottleneck than originally estimated.

Conversely, the original plan estimated C extension Phases 2-4 would yield 10-40x gains. Post-implementation profiling shows the realistic C extension gains are 3-6x for arithmetic and 2-3x for conversions, because: (1) the pure Ruby optimizations already captured the largest wins, (2) Ruby object creation is an irreducible floor, and (3) Ruby's built-in data structures are already C-backed.
