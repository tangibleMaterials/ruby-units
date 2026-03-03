/*
 * ruby_units_ext.c - C extension for ruby-units
 *
 * Replaces hot-path Ruby methods with C implementations:
 *   - finalize_initialization (Phase 2)
 *   - eliminate_terms (Phase 3)
 *   - convert_scalar (Phase 4)
 *
 * The C code reads Ruby state directly via rb_ivar_get and rb_hash_aref.
 * No data is copied or synced -- everything lives in Ruby objects.
 */

#include <ruby.h>

/* Interned IDs for instance variables */
static ID id_iv_scalar;
static ID id_iv_numerator;
static ID id_iv_denominator;
static ID id_iv_base_scalar;
static ID id_iv_signature;
static ID id_iv_base;
static ID id_iv_base_unit;
static ID id_iv_unit_name;
static ID id_iv_output;

/* Interned IDs for hash keys (symbols) - unused, keeping sym_* VALUES below */

/* Interned IDs for method calls */
static ID id_definitions;
static ID id_prefix_values;
static ID id_unit_values;
static ID id_unit_map;
static ID id_definition;
static ID id_base_q;
static ID id_unity_q;
static ID id_prefix_q;
static ID id_kind;
static ID id_display_name;
static ID id_units;
static ID id_cached;
static ID id_base_unit_cache;
static ID id_set;
static ID id_get;
static ID id_to_unit;
static ID id_scalar;
static ID id_temperature_q;
static ID id_degree_q;
static ID id_to_base;
static ID id_convert_to;
static ID id_freeze;
static ID id_negative_q;
static ID id_special_format_regex;
static ID id_match_q;
static ID id_parse_into_numbers_and_units;
static ID id_unit_class;
static ID id_normalize_to_i;
static ID id_key_q;
static ID id_temp_regex;
static ID id_strip;

/* Ruby symbol values for hash keys */
static VALUE sym_scalar;
static VALUE sym_numerator;
static VALUE sym_denominator;
static VALUE sym_kind;
static VALUE sym_signature;

/* SIGNATURE_VECTOR kind symbols */
static VALUE sym_length;
static VALUE sym_time;
static VALUE sym_temperature;
static VALUE sym_mass;
static VALUE sym_current;
static VALUE sym_substance;
static VALUE sym_luminosity;
static VALUE sym_currency;
static VALUE sym_information;
static VALUE sym_angle;

#define SIGNATURE_VECTOR_SIZE 10

/* Map from kind symbol to vector index */
static VALUE signature_kind_symbols[SIGNATURE_VECTOR_SIZE];

/* Cached UNITY string */
static VALUE str_unity;       /* "<1>" */
static VALUE str_empty;       /* "" */

/* Temperature units are handled by the Ruby fallback path */

/* Cached class references */
static VALUE cUnit;

/* Forward declarations */
static int is_unity(VALUE token);
static VALUE get_unit_class(VALUE self);
static int check_base(VALUE unit_class, VALUE numerator, VALUE denominator);
static VALUE compute_base_scalar_c(VALUE unit_class, VALUE scalar, VALUE numerator, VALUE denominator);
static long compute_signature_c(VALUE unit_class, VALUE numerator, VALUE denominator);
static VALUE build_units_string(VALUE unit_class, VALUE numerator, VALUE denominator);
/* temperature is handled by Ruby fallback */

/*
 * Check if a token is the unity token "<1>"
 */
static int is_unity(VALUE token) {
    return rb_str_equal(token, str_unity) == Qtrue;
}

/*
 * Get the unit_class for an instance (handles subclassing)
 */
static VALUE get_unit_class(VALUE self) {
    return rb_funcall(self, id_unit_class, 0);
}

/*
 * Check if all tokens in numerator and denominator are base units.
 * Equivalent to Ruby's base? method.
 */
static int check_base(VALUE unit_class, VALUE numerator, VALUE denominator) {
    long i, len;
    VALUE token, defn;

    len = RARRAY_LEN(numerator);
    for (i = 0; i < len; i++) {
        token = rb_ary_entry(numerator, i);
        if (is_unity(token)) continue;

        defn = rb_funcall(unit_class, id_definition, 1, token);
        if (NIL_P(defn)) return 0;

        /* definition must be unity? or base? */
        if (rb_funcall(defn, id_unity_q, 0) == Qtrue) continue;
        if (rb_funcall(defn, id_base_q, 0) == Qtrue) continue;
        return 0;
    }

    len = RARRAY_LEN(denominator);
    for (i = 0; i < len; i++) {
        token = rb_ary_entry(denominator, i);
        if (is_unity(token)) continue;

        defn = rb_funcall(unit_class, id_definition, 1, token);
        if (NIL_P(defn)) return 0;

        if (rb_funcall(defn, id_unity_q, 0) == Qtrue) continue;
        if (rb_funcall(defn, id_base_q, 0) == Qtrue) continue;
        return 0;
    }

    return 1;
}

/*
 * Compute base_scalar without creating intermediate Unit objects.
 * Equivalent to Ruby's compute_base_scalar_fast.
 */
static VALUE compute_base_scalar_c(VALUE unit_class, VALUE scalar, VALUE numerator, VALUE denominator) {
    VALUE prefix_vals = rb_funcall(unit_class, id_prefix_values, 0);
    VALUE unit_vals = rb_funcall(unit_class, id_unit_values, 0);
    VALUE factor = rb_rational_new(INT2FIX(1), INT2FIX(1));
    long i, len;
    VALUE token, pv, uv, uv_scalar;

    len = RARRAY_LEN(numerator);
    for (i = 0; i < len; i++) {
        token = rb_ary_entry(numerator, i);
        if (is_unity(token)) continue;

        pv = rb_hash_aref(prefix_vals, token);
        if (!NIL_P(pv)) {
            factor = rb_funcall(factor, '*', 1, pv);
        } else {
            uv = rb_hash_aref(unit_vals, token);
            if (!NIL_P(uv)) {
                uv_scalar = rb_hash_aref(uv, sym_scalar);
                if (!NIL_P(uv_scalar)) {
                    factor = rb_funcall(factor, '*', 1, uv_scalar);
                }
            }
        }
    }

    len = RARRAY_LEN(denominator);
    for (i = 0; i < len; i++) {
        token = rb_ary_entry(denominator, i);
        if (is_unity(token)) continue;

        pv = rb_hash_aref(prefix_vals, token);
        if (!NIL_P(pv)) {
            factor = rb_funcall(factor, '/', 1, pv);
        } else {
            uv = rb_hash_aref(unit_vals, token);
            if (!NIL_P(uv)) {
                uv_scalar = rb_hash_aref(uv, sym_scalar);
                if (!NIL_P(uv_scalar)) {
                    factor = rb_funcall(factor, '/', 1, uv_scalar);
                }
            }
        }
    }

    return rb_funcall(scalar, '*', 1, factor);
}

/*
 * Expand tokens into signature vector, accumulating with sign.
 * This replaces expand_tokens_to_signature.
 */
static void expand_tokens_to_signature_c(VALUE unit_class, VALUE tokens, int vector[SIGNATURE_VECTOR_SIZE], int sign) {
    VALUE prefix_vals = rb_funcall(unit_class, id_prefix_values, 0);
    VALUE unit_vals = rb_funcall(unit_class, id_unit_values, 0);
    long i, len, j;
    VALUE token, uv, base_arr, bt, defn, kind_sym;

    len = RARRAY_LEN(tokens);
    for (i = 0; i < len; i++) {
        token = rb_ary_entry(tokens, i);
        if (is_unity(token)) continue;

        /* skip prefix tokens */
        if (rb_funcall(prefix_vals, id_key_q, 1, token) == Qtrue) continue;

        uv = rb_hash_aref(unit_vals, token);
        if (!NIL_P(uv)) {
            /* Has a unit_values entry -- expand its base numerator/denominator */
            base_arr = rb_hash_aref(uv, sym_numerator);
            if (!NIL_P(base_arr)) {
                long blen = RARRAY_LEN(base_arr);
                for (j = 0; j < blen; j++) {
                    bt = rb_ary_entry(base_arr, j);
                    defn = rb_funcall(unit_class, id_definition, 1, bt);
                    if (NIL_P(defn)) continue;
                    kind_sym = rb_funcall(defn, id_kind, 0);
                    int k;
                    for (k = 0; k < SIGNATURE_VECTOR_SIZE; k++) {
                        if (rb_equal(kind_sym, signature_kind_symbols[k]) == Qtrue) {
                            vector[k] += sign;
                            break;
                        }
                    }
                }
            }
            base_arr = rb_hash_aref(uv, sym_denominator);
            if (!NIL_P(base_arr)) {
                long blen = RARRAY_LEN(base_arr);
                for (j = 0; j < blen; j++) {
                    bt = rb_ary_entry(base_arr, j);
                    defn = rb_funcall(unit_class, id_definition, 1, bt);
                    if (NIL_P(defn)) continue;
                    kind_sym = rb_funcall(defn, id_kind, 0);
                    int k;
                    for (k = 0; k < SIGNATURE_VECTOR_SIZE; k++) {
                        if (rb_equal(kind_sym, signature_kind_symbols[k]) == Qtrue) {
                            vector[k] -= sign;
                            break;
                        }
                    }
                }
            }
        } else {
            /* Direct base unit token */
            defn = rb_funcall(unit_class, id_definition, 1, token);
            if (!NIL_P(defn)) {
                kind_sym = rb_funcall(defn, id_kind, 0);
                int k;
                for (k = 0; k < SIGNATURE_VECTOR_SIZE; k++) {
                    if (rb_equal(kind_sym, signature_kind_symbols[k]) == Qtrue) {
                        vector[k] += sign;
                        break;
                    }
                }
            }
        }
    }
}

/*
 * Compute signature from numerator/denominator without creating intermediate objects.
 * Returns the integer signature.
 */
static long compute_signature_c(VALUE unit_class, VALUE numerator, VALUE denominator) {
    int vector[SIGNATURE_VECTOR_SIZE];
    int i;
    long signature = 0;
    long power = 1;

    for (i = 0; i < SIGNATURE_VECTOR_SIZE; i++) vector[i] = 0;

    expand_tokens_to_signature_c(unit_class, numerator, vector, 1);
    expand_tokens_to_signature_c(unit_class, denominator, vector, -1);

    /* Validate power range: same check as Ruby's unit_signature_vector */
    for (i = 0; i < SIGNATURE_VECTOR_SIZE; i++) {
        if (abs(vector[i]) >= 20) {
            rb_raise(rb_eArgError, "Power out of range (-20 < net power of a unit < 20)");
        }
    }

    for (i = 0; i < SIGNATURE_VECTOR_SIZE; i++) {
        signature += vector[i] * power;
        power *= 20;
    }

    return signature;
}

/*
 * Build the units string from numerator/denominator arrays.
 * Equivalent to Ruby's units() method (with default format).
 */
static VALUE build_units_string(VALUE unit_class, VALUE numerator, VALUE denominator) {
    long num_len = RARRAY_LEN(numerator);
    long den_len = RARRAY_LEN(denominator);

    /* Quick check for unitless */
    if (num_len == 1 && den_len == 1 &&
        is_unity(rb_ary_entry(numerator, 0)) &&
        is_unity(rb_ary_entry(denominator, 0))) {
        return str_empty;
    }

    VALUE output_num = rb_ary_new();
    VALUE output_den = rb_ary_new();
    long i;
    VALUE token, defn, display, current_str;
    int is_prefix;

    /* Process numerator: group prefixes with their units */
    if (!(num_len == 1 && is_unity(rb_ary_entry(numerator, 0)))) {
        current_str = Qnil;
        for (i = 0; i < num_len; i++) {
            token = rb_ary_entry(numerator, i);
            defn = rb_funcall(unit_class, id_definition, 1, token);
            if (NIL_P(defn)) continue;

            display = rb_funcall(defn, id_display_name, 0);
            is_prefix = (rb_funcall(defn, id_prefix_q, 0) == Qtrue);

            if (is_prefix) {
                current_str = rb_str_dup(display);
            } else {
                if (!NIL_P(current_str)) {
                    rb_str_append(current_str, display);
                    rb_ary_push(output_num, current_str);
                    current_str = Qnil;
                } else {
                    rb_ary_push(output_num, rb_str_dup(display));
                }
            }
        }
    }

    /* Process denominator: same grouping */
    if (!(den_len == 1 && is_unity(rb_ary_entry(denominator, 0)))) {
        current_str = Qnil;
        for (i = 0; i < den_len; i++) {
            token = rb_ary_entry(denominator, i);
            defn = rb_funcall(unit_class, id_definition, 1, token);
            if (NIL_P(defn)) continue;

            display = rb_funcall(defn, id_display_name, 0);
            is_prefix = (rb_funcall(defn, id_prefix_q, 0) == Qtrue);

            if (is_prefix) {
                current_str = rb_str_dup(display);
            } else {
                if (!NIL_P(current_str)) {
                    rb_str_append(current_str, display);
                    rb_ary_push(output_den, current_str);
                    current_str = Qnil;
                } else {
                    rb_ary_push(output_den, rb_str_dup(display));
                }
            }
        }
    }

    /* If numerator is empty, use "1" */
    if (RARRAY_LEN(output_num) == 0) {
        rb_ary_push(output_num, rb_str_new_cstr("1"));
    }

    /* Format: collect unique elements with exponents */
    /* Build numerator string */
    VALUE result = rb_str_buf_new(64);
    VALUE seen = rb_hash_new();
    long total;

    total = RARRAY_LEN(output_num);
    int first = 1;
    for (i = 0; i < total; i++) {
        VALUE elem = rb_ary_entry(output_num, i);
        if (rb_hash_aref(seen, elem) != Qnil) continue;

        /* Count occurrences */
        long count = 0;
        long j;
        for (j = 0; j < total; j++) {
            if (rb_str_equal(rb_ary_entry(output_num, j), elem) == Qtrue) count++;
        }
        rb_hash_aset(seen, elem, Qtrue);

        if (!first) rb_str_cat_cstr(result, "*");
        first = 0;

        VALUE stripped = rb_funcall(elem, id_strip, 0);
        rb_str_append(result, stripped);
        if (count > 1) {
            rb_str_cat_cstr(result, "^");
            char buf[12];
            snprintf(buf, sizeof(buf), "%ld", count);
            rb_str_cat_cstr(result, buf);
        }
    }

    /* Build denominator string */
    total = RARRAY_LEN(output_den);
    if (total > 0) {
        rb_str_cat_cstr(result, "/");
        seen = rb_hash_new();
        first = 1;
        for (i = 0; i < total; i++) {
            VALUE elem = rb_ary_entry(output_den, i);
            if (rb_hash_aref(seen, elem) != Qnil) continue;

            long count = 0;
            long j;
            for (j = 0; j < total; j++) {
                if (rb_str_equal(rb_ary_entry(output_den, j), elem) == Qtrue) count++;
            }
            rb_hash_aset(seen, elem, Qtrue);

            if (!first) rb_str_cat_cstr(result, "*");
            first = 0;

            VALUE stripped = rb_funcall(elem, id_strip, 0);
            rb_str_append(result, stripped);
            if (count > 1) {
                rb_str_cat_cstr(result, "^");
                char buf[12];
                snprintf(buf, sizeof(buf), "%ld", count);
                rb_str_cat_cstr(result, buf);
            }
        }
    }

    return rb_funcall(result, id_strip, 0);
}

/*
 * Phase 2: rb_unit_finalize - replaces finalize_initialization
 *
 * Called from Ruby's initialize after parsing is complete.
 * Computes base?, base_scalar, signature, builds units string, caches, and freezes.
 *
 * call-seq:
 *   unit._c_finalize(options_first_arg) -> self
 */
static VALUE rb_unit_finalize(VALUE self, VALUE options_first) {
    VALUE unit_class = get_unit_class(self);
    VALUE scalar = rb_ivar_get(self, id_iv_scalar);
    VALUE numerator = rb_ivar_get(self, id_iv_numerator);
    VALUE denominator = rb_ivar_get(self, id_iv_denominator);
    VALUE signature = rb_ivar_get(self, id_iv_signature);

    int is_base;
    VALUE base_scalar_val;
    long sig_val;

    /* 1. Compute base?, base_scalar, signature */
    if (!NIL_P(signature)) {
        /* Signature was pre-supplied (e.g., from arithmetic fast-path) */
        is_base = check_base(unit_class, numerator, denominator);
        if (is_base) {
            base_scalar_val = scalar;
        } else {
            base_scalar_val = compute_base_scalar_c(unit_class, scalar, numerator, denominator);
        }
        sig_val = NUM2LONG(signature);
    } else {
        is_base = check_base(unit_class, numerator, denominator);
        if (is_base) {
            base_scalar_val = scalar;
            /* For base units, compute signature via the vector method */
            sig_val = compute_signature_c(unit_class, numerator, denominator);
        } else {
            /* Non-base, non-temperature (temperature is handled by Ruby fallback) */
            base_scalar_val = compute_base_scalar_c(unit_class, scalar, numerator, denominator);
            sig_val = compute_signature_c(unit_class, numerator, denominator);
        }
    }

    rb_ivar_set(self, id_iv_base, is_base ? Qtrue : Qfalse);
    rb_ivar_set(self, id_iv_base_scalar, base_scalar_val);
    rb_ivar_set(self, id_iv_signature, LONG2NUM(sig_val));

    /* Temperature units are handled by the Ruby fallback path, so no
     * temperature validation is needed here. */

    /* 2. Build units string and cache */
    VALUE unary_unit = build_units_string(unit_class, numerator, denominator);
    rb_ivar_set(self, id_iv_unit_name, unary_unit);

    /* Cache the unit if appropriate */
    if (RB_TYPE_P(options_first, T_STRING)) {
        /* Cache from string parse */
        VALUE parse_result = rb_funcall(unit_class, id_parse_into_numbers_and_units, 1, options_first);
        VALUE opt_units = rb_ary_entry(parse_result, 1);
        if (!NIL_P(opt_units) && RSTRING_LEN(opt_units) > 0) {
            VALUE cache = rb_funcall(unit_class, id_cached, 0);
            VALUE one = INT2FIX(1);
            if (rb_funcall(scalar, rb_intern("=="), 1, one) == Qtrue) {
                rb_funcall(cache, id_set, 2, opt_units, self);
            } else {
                VALUE unit_from_str = rb_funcall(opt_units, id_to_unit, 0);
                rb_funcall(cache, id_set, 2, opt_units, unit_from_str);
            }
        }
    }

    /* Cache unary unit */
    if (RSTRING_LEN(unary_unit) > 0) {
        VALUE cache = rb_funcall(unit_class, id_cached, 0);
        VALUE one = INT2FIX(1);
        if (rb_funcall(scalar, rb_intern("=="), 1, one) == Qtrue) {
            rb_funcall(cache, id_set, 2, unary_unit, self);
        } else {
            VALUE unit_from_str = rb_funcall(unary_unit, id_to_unit, 0);
            rb_funcall(cache, id_set, 2, unary_unit, unit_from_str);
        }
    }

    /* 4. Freeze instance variables */
    rb_funcall(scalar, id_freeze, 0);
    rb_funcall(numerator, id_freeze, 0);
    rb_funcall(denominator, id_freeze, 0);
    rb_funcall(base_scalar_val, id_freeze, 0);
    VALUE sig_obj = rb_ivar_get(self, id_iv_signature);
    rb_funcall(sig_obj, id_freeze, 0);
    VALUE base_obj = rb_ivar_get(self, id_iv_base);
    rb_funcall(base_obj, id_freeze, 0);

    return self;
}

/*
 * Phase 2: rb_unit_units_string - replaces units() for the common case (no args)
 *
 * call-seq:
 *   unit._c_units_string -> String
 */
static VALUE rb_unit_units_string(VALUE self) {
    VALUE unit_class = get_unit_class(self);
    VALUE numerator = rb_ivar_get(self, id_iv_numerator);
    VALUE denominator = rb_ivar_get(self, id_iv_denominator);
    return build_units_string(unit_class, numerator, denominator);
}

/*
 * Phase 2: rb_unit_base_check - replaces base? (uncached check)
 *
 * call-seq:
 *   unit._c_base_check -> true/false
 */
static VALUE rb_unit_base_check(VALUE self) {
    VALUE unit_class = get_unit_class(self);
    VALUE numerator = rb_ivar_get(self, id_iv_numerator);
    VALUE denominator = rb_ivar_get(self, id_iv_denominator);
    return check_base(unit_class, numerator, denominator) ? Qtrue : Qfalse;
}

/*
 * Phase 3: rb_unit_eliminate_terms - replaces eliminate_terms class method
 *
 * call-seq:
 *   Unit._c_eliminate_terms(scalar, numerator, denominator) -> Hash
 */
static VALUE rb_unit_eliminate_terms(VALUE klass, VALUE scalar, VALUE numerator, VALUE denominator) {
    /*
     * Count prefix+unit groups.
     * A "group" is a consecutive sequence of prefix tokens followed by a unit token.
     * We use a Ruby Hash for counting: key=group (array of tokens), value=count (+/-)
     */
    VALUE combined = rb_hash_new();
    VALUE unity = str_unity;
    long i, len;
    VALUE token, defn;

    /* Count numerator groups */
    VALUE current_group = rb_ary_new();
    len = RARRAY_LEN(numerator);
    for (i = 0; i < len; i++) {
        token = rb_ary_entry(numerator, i);
        if (rb_str_equal(token, unity) == Qtrue) continue;

        rb_ary_push(current_group, token);
        defn = rb_funcall(klass, id_definition, 1, token);
        if (NIL_P(defn) || rb_funcall(defn, id_prefix_q, 0) != Qtrue) {
            /* End of group - increment count */
            VALUE existing = rb_hash_aref(combined, current_group);
            long val = NIL_P(existing) ? 0 : NUM2LONG(existing);
            rb_hash_aset(combined, current_group, LONG2NUM(val + 1));
            current_group = rb_ary_new();
        }
    }

    /* Count denominator groups */
    current_group = rb_ary_new();
    len = RARRAY_LEN(denominator);
    for (i = 0; i < len; i++) {
        token = rb_ary_entry(denominator, i);
        if (rb_str_equal(token, unity) == Qtrue) continue;

        rb_ary_push(current_group, token);
        defn = rb_funcall(klass, id_definition, 1, token);
        if (NIL_P(defn) || rb_funcall(defn, id_prefix_q, 0) != Qtrue) {
            /* End of group - decrement count */
            VALUE existing = rb_hash_aref(combined, current_group);
            long val = NIL_P(existing) ? 0 : NUM2LONG(existing);
            rb_hash_aset(combined, current_group, LONG2NUM(val - 1));
            current_group = rb_ary_new();
        }
    }

    /* Build result arrays */
    VALUE result_num = rb_ary_new();
    VALUE result_den = rb_ary_new();

    VALUE keys = rb_funcall(combined, rb_intern("keys"), 0);
    long keys_len = RARRAY_LEN(keys);
    for (i = 0; i < keys_len; i++) {
        VALUE key = rb_ary_entry(keys, i);
        long val = NUM2LONG(rb_hash_aref(combined, key));
        long j;
        if (val > 0) {
            for (j = 0; j < val; j++) {
                rb_funcall(result_num, rb_intern("concat"), 1, key);
            }
        } else if (val < 0) {
            for (j = 0; j < -val; j++) {
                rb_funcall(result_den, rb_intern("concat"), 1, key);
            }
        }
    }

    /* Default to UNITY_ARRAY if empty */
    VALUE unity_array = rb_ary_new_from_args(1, str_unity);
    if (RARRAY_LEN(result_num) == 0) result_num = unity_array;
    if (RARRAY_LEN(result_den) == 0) result_den = rb_ary_new_from_args(1, str_unity);

    VALUE result = rb_hash_new();
    rb_hash_aset(result, sym_scalar, scalar);
    rb_hash_aset(result, sym_numerator, result_num);
    rb_hash_aset(result, sym_denominator, result_den);
    return result;
}

/*
 * Phase 4: rb_unit_convert_scalar - computes conversion factor between two units
 *
 * call-seq:
 *   Unit._c_convert_scalar(self_unit, target_unit) -> Numeric
 *
 * Returns the converted scalar value.
 */
static VALUE rb_unit_convert_scalar(VALUE klass, VALUE self_unit, VALUE target_unit) {
    VALUE prefix_vals = rb_funcall(klass, id_prefix_values, 0);
    VALUE unit_vals = rb_funcall(klass, id_unit_values, 0);
    VALUE self_num = rb_ivar_get(self_unit, id_iv_numerator);
    VALUE self_den = rb_ivar_get(self_unit, id_iv_denominator);
    VALUE target_num = rb_ivar_get(target_unit, id_iv_numerator);
    VALUE target_den = rb_ivar_get(target_unit, id_iv_denominator);
    VALUE self_scalar = rb_ivar_get(self_unit, id_iv_scalar);

    /* Compute unit_array_scalar for each array */
    long i, len;
    VALUE token, pv, uv, uv_scalar;

    /* Helper: compute scalar product of a unit array */
    #define COMPUTE_ARRAY_SCALAR(arr, result_var) do { \
        result_var = INT2FIX(1); \
        len = RARRAY_LEN(arr); \
        for (i = 0; i < len; i++) { \
            token = rb_ary_entry(arr, i); \
            pv = rb_hash_aref(prefix_vals, token); \
            if (!NIL_P(pv)) { \
                result_var = rb_funcall(result_var, '*', 1, pv); \
            } else { \
                uv = rb_hash_aref(unit_vals, token); \
                if (!NIL_P(uv)) { \
                    uv_scalar = rb_hash_aref(uv, sym_scalar); \
                    if (!NIL_P(uv_scalar)) { \
                        result_var = rb_funcall(result_var, '*', 1, uv_scalar); \
                    } \
                } \
            } \
        } \
    } while(0)

    VALUE self_num_scalar, self_den_scalar, target_num_scalar, target_den_scalar;

    COMPUTE_ARRAY_SCALAR(self_num, self_num_scalar);
    COMPUTE_ARRAY_SCALAR(self_den, self_den_scalar);
    COMPUTE_ARRAY_SCALAR(target_num, target_num_scalar);
    COMPUTE_ARRAY_SCALAR(target_den, target_den_scalar);

    #undef COMPUTE_ARRAY_SCALAR

    /* numerator_factor = self_num_scalar * target_den_scalar */
    VALUE numerator_factor = rb_funcall(self_num_scalar, '*', 1, target_den_scalar);
    /* denominator_factor = target_num_scalar * self_den_scalar */
    VALUE denominator_factor = rb_funcall(target_num_scalar, '*', 1, self_den_scalar);

    /* Convert integer scalars to rational to preserve precision */
    VALUE conversion_scalar;
    if (RB_TYPE_P(self_scalar, T_FIXNUM) || RB_TYPE_P(self_scalar, T_BIGNUM)) {
        conversion_scalar = rb_funcall(self_scalar, rb_intern("to_r"), 0);
    } else {
        conversion_scalar = self_scalar;
    }

    VALUE converted = rb_funcall(conversion_scalar, '*', 1, numerator_factor);
    converted = rb_funcall(converted, '/', 1, denominator_factor);

    /* normalize_to_i */
    converted = rb_funcall(klass, id_normalize_to_i, 1, converted);

    return converted;
}

/*
 * Module init
 */
void Init_ruby_units_ext(void) {
    /* Intern IDs for instance variables */
    id_iv_scalar = rb_intern("@scalar");
    id_iv_numerator = rb_intern("@numerator");
    id_iv_denominator = rb_intern("@denominator");
    id_iv_base_scalar = rb_intern("@base_scalar");
    id_iv_signature = rb_intern("@signature");
    id_iv_base = rb_intern("@base");
    id_iv_base_unit = rb_intern("@base_unit");
    id_iv_unit_name = rb_intern("@unit_name");
    id_iv_output = rb_intern("@output");

    /* Intern IDs for methods */
    id_definitions = rb_intern("definitions");
    id_prefix_values = rb_intern("prefix_values");
    id_unit_values = rb_intern("unit_values");
    id_unit_map = rb_intern("unit_map");
    id_definition = rb_intern("definition");
    id_base_q = rb_intern("base?");
    id_unity_q = rb_intern("unity?");
    id_prefix_q = rb_intern("prefix?");
    id_kind = rb_intern("kind");
    id_display_name = rb_intern("display_name");
    id_units = rb_intern("units");
    id_cached = rb_intern("cached");
    id_base_unit_cache = rb_intern("base_unit_cache");
    id_set = rb_intern("set");
    id_get = rb_intern("get");
    id_to_unit = rb_intern("to_unit");
    id_scalar = rb_intern("scalar");
    id_temperature_q = rb_intern("temperature?");
    id_degree_q = rb_intern("degree?");
    id_to_base = rb_intern("to_base");
    id_convert_to = rb_intern("convert_to");
    id_freeze = rb_intern("freeze");
    id_negative_q = rb_intern("negative?");
    id_special_format_regex = rb_intern("special_format_regex");
    id_match_q = rb_intern("match?");
    id_parse_into_numbers_and_units = rb_intern("parse_into_numbers_and_units");
    id_unit_class = rb_intern("unit_class");
    id_normalize_to_i = rb_intern("normalize_to_i");
    id_key_q = rb_intern("key?");
    id_temp_regex = rb_intern("temp_regex");
    id_strip = rb_intern("strip");

    /* Create symbol values for hash keys */
    sym_scalar = ID2SYM(rb_intern("scalar"));
    sym_numerator = ID2SYM(rb_intern("numerator"));
    sym_denominator = ID2SYM(rb_intern("denominator"));
    sym_kind = ID2SYM(rb_intern("kind"));
    sym_signature = ID2SYM(rb_intern("signature"));

    /* SIGNATURE_VECTOR kind symbols */
    sym_length = ID2SYM(rb_intern("length"));
    sym_time = ID2SYM(rb_intern("time"));
    sym_temperature = ID2SYM(rb_intern("temperature"));
    sym_mass = ID2SYM(rb_intern("mass"));
    sym_current = ID2SYM(rb_intern("current"));
    sym_substance = ID2SYM(rb_intern("substance"));
    sym_luminosity = ID2SYM(rb_intern("luminosity"));
    sym_currency = ID2SYM(rb_intern("currency"));
    sym_information = ID2SYM(rb_intern("information"));
    sym_angle = ID2SYM(rb_intern("angle"));

    signature_kind_symbols[0] = sym_length;
    signature_kind_symbols[1] = sym_time;
    signature_kind_symbols[2] = sym_temperature;
    signature_kind_symbols[3] = sym_mass;
    signature_kind_symbols[4] = sym_current;
    signature_kind_symbols[5] = sym_substance;
    signature_kind_symbols[6] = sym_luminosity;
    signature_kind_symbols[7] = sym_currency;
    signature_kind_symbols[8] = sym_information;
    signature_kind_symbols[9] = sym_angle;

    /* Mark all symbols as GC roots */
    rb_gc_register_address(&sym_scalar);
    rb_gc_register_address(&sym_numerator);
    rb_gc_register_address(&sym_denominator);
    rb_gc_register_address(&sym_kind);
    rb_gc_register_address(&sym_signature);
    rb_gc_register_address(&sym_length);
    rb_gc_register_address(&sym_time);
    rb_gc_register_address(&sym_temperature);
    rb_gc_register_address(&sym_mass);
    rb_gc_register_address(&sym_current);
    rb_gc_register_address(&sym_substance);
    rb_gc_register_address(&sym_luminosity);
    rb_gc_register_address(&sym_currency);
    rb_gc_register_address(&sym_information);
    rb_gc_register_address(&sym_angle);

    /* Frozen string constants */
    str_unity = rb_str_freeze(rb_str_new_cstr("<1>"));
    rb_gc_register_address(&str_unity);

    str_empty = rb_str_freeze(rb_str_new_cstr(""));
    rb_gc_register_address(&str_empty);

    /* Temperature units are handled entirely in Ruby */

    /* Get the Unit class and define methods */
    VALUE mRubyUnits = rb_define_module("RubyUnits");
    cUnit = rb_define_class_under(mRubyUnits, "Unit", rb_cNumeric);

    /* Instance methods */
    rb_define_private_method(cUnit, "_c_finalize", rb_unit_finalize, 1);
    rb_define_method(cUnit, "_c_units_string", rb_unit_units_string, 0);
    rb_define_method(cUnit, "_c_base_check", rb_unit_base_check, 0);

    /* Class methods */
    rb_define_singleton_method(cUnit, "_c_eliminate_terms", rb_unit_eliminate_terms, 3);
    rb_define_singleton_method(cUnit, "_c_convert_scalar", rb_unit_convert_scalar, 2);
}
