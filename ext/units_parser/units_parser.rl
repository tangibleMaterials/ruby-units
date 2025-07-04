%%{
  machine units_parser;
  
  # Basic character classes
  my_digit = [0-9];
  my_alpha = [a-zA-Z];
  my_space = [ \t\n];
  my_sign = [+\-];
  
  # Numbers - comprehensive support for all ruby-units number formats
  integer = my_digit+;
  decimal = my_digit* '.' my_digit+;
  scientific = (integer | decimal) [eE] my_sign? my_digit+;
  
  # Rational numbers: 1/2, 1 2/3, -1/2, (1/2)
  rational = ('(' my_space*)? 
             (my_sign? (integer | decimal) my_space+ )?  # proper part (optional)
             my_sign? (integer | decimal) '/' my_sign? (integer | decimal)
             (my_space* ')')?;
  
  # Complex numbers: 1+2i, 1.0+2.0i, -1-1i, 2i
  complex = ((integer | decimal) my_sign?)? my_sign? (integer | decimal) 'i';
  
  # Time format: 12:34:56.78
  time_format = my_digit{1,2} ':' my_digit{2} (':' my_digit{2} ('.' my_digit+)?)?;
  
  # Feet/inches: 5'6", 5 ft 6 in, 5 feet 6 inches
  feet_inch = my_sign? integer my_space* ("'"|'ft'|'feet') my_space*
              (rational | scientific | integer | decimal)? my_space*
              ('"'|'in'|'inch'|'inches')?;
  
  # Pounds/ounces: 5 lbs 6 oz, 5 pounds 6 ounces, 5# 6oz
  lbs_oz = my_sign? integer my_space* ('#'|'lb'|'lbs'|'pound'|'pounds'|'pound-mass') my_space* ','? my_space*
           (rational | integer | decimal)? my_space*
           ('oz'|'ozs'|'ounce'|'ounces')?;
  
  # Stone/pounds: 10 st 5 lbs, 10 stones 5 pounds
  stone_lbs = my_sign? integer my_space* ('st'|'sts'|'stone'|'stones') my_space* ','? my_space*
              (rational | integer | decimal)? my_space*
              ('#'|'lb'|'lbs'|'pound'|'pounds'|'pound-mass')?;
  
  # Complete number (any of the above)
  number = my_sign? (complex | rational | scientific | decimal | integer | 
                     time_format | feet_inch | lbs_oz | stone_lbs);
  
  # Units - handle all special characters ruby-units supports
  unit_char = my_alpha | [°'"$%#];
  unit_name = unit_char+ ('-' unit_char+)*;  # Handle hyphenated units
  
  # Exponents: ^2, **-1, ^-2
  exponent = ('^' | '**') my_sign? integer;
  unit_with_exp = unit_name exponent?;
  
  # Compound units - simplified to avoid recursion issues
  multiply_op = '*';
  divide_op = '/';
  
  # Simple compound units without full parentheses support for now
  unit_factor = unit_with_exp;
  unit_product = unit_factor (my_space* multiply_op my_space* unit_factor)*;
  unit_expr = unit_product;
  
  # Actions for data capture
  action start_number { number_start = fpc; }
  action end_number { number_end = fpc; }
  action start_numerator { numerator_start = fpc; }
  action end_numerator { numerator_end = fpc; }
  action start_denominator { denominator_start = fpc; }
  action end_denominator { denominator_end = fpc; }
  action found_divide { found_division = 1; }
  
  # Main expression with comprehensive unit parsing
  main := my_space* 
          (number >start_number %end_number)? 
          my_space* 
          (unit_expr >start_numerator %end_numerator
           (my_space* divide_op @found_divide my_space* unit_expr >start_denominator %end_denominator)?
          )? 
          my_space*;
  
}%%

#include <ruby.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>

%% write data;

typedef struct {
    VALUE scalar;
    VALUE numerator;
    VALUE denominator;
    int success;
    const char* error;
} ParseResult;

static VALUE rb_mRubyUnits;
static VALUE rb_cUnitsParser;

// Helper function to split unit string into array
VALUE split_units(const char* units_str, int len) {
    VALUE result = rb_ary_new();
    if (len == 0) return result;
    
    char* str = malloc(len + 1);
    strncpy(str, units_str, len);
    str[len] = '\0';
    
    // Simple splitting on * for now - can be enhanced
    char* token = strtok(str, "*");
    while (token != NULL) {
        // Trim whitespace
        while (*token == ' ' || *token == '\t') token++;
        char* end = token + strlen(token) - 1;
        while (end > token && (*end == ' ' || *end == '\t')) end--;
        end[1] = '\0';
        
        if (strlen(token) > 0) {
            rb_ary_push(result, rb_str_new_cstr(token));
        }
        token = strtok(NULL, "*");
    }
    
    free(str);
    return result;
}

ParseResult parse_unit_string(const char* data, int len) {
    ParseResult result = {Qnil, Qnil, Qnil, 0, NULL};
    
    const char* p = data;
    const char* pe = data + len;
    const char* eof = pe;
    int cs;
    
    // Capture positions
    const char* number_start = NULL;
    const char* number_end = NULL;
    const char* numerator_start = NULL;
    const char* numerator_end = NULL;
    const char* denominator_start = NULL;
    const char* denominator_end = NULL;
    int found_division = 0;
    
    %% write init;
    %% write exec;
    
    if (cs >= units_parser_first_final) {
        result.success = 1;
        
        // Extract scalar
        if (number_start && number_end) {
            int num_len = (int)(number_end - number_start);
            char* num_str = malloc(num_len + 1);
            strncpy(num_str, number_start, num_len);
            num_str[num_len] = '\0';
            
            result.scalar = rb_str_new_cstr(num_str);
            free(num_str);
        } else {
            result.scalar = rb_str_new_cstr("1");
        }
        
        // Extract numerator units
        if (numerator_start && numerator_end) {
            int num_len = (int)(numerator_end - numerator_start);
            result.numerator = split_units(numerator_start, num_len);
        } else {
            result.numerator = rb_ary_new();
        }
        
        // Extract denominator units
        if (found_division && denominator_start && denominator_end) {
            int den_len = (int)(denominator_end - denominator_start);
            result.denominator = split_units(denominator_start, den_len);
        } else {
            result.denominator = rb_ary_new();
        }
        
        // Don't add unity placeholder - let the Unit class handle it
        // Keep numerator and denominator empty for pure scalars
        
    } else {
        result.success = 0;
        result.error = "Parse error";
    }
    
    return result;
}

static VALUE units_parser_parse(VALUE self, VALUE input_str) {
    Check_Type(input_str, T_STRING);
    
    const char* input = RSTRING_PTR(input_str);
    int len = (int)RSTRING_LEN(input_str);
    
    ParseResult result = parse_unit_string(input, len);
    
    if (result.success) {
        VALUE hash = rb_hash_new();
        rb_hash_aset(hash, rb_str_new_cstr("scalar"), result.scalar);
        rb_hash_aset(hash, rb_str_new_cstr("numerator"), result.numerator);
        rb_hash_aset(hash, rb_str_new_cstr("denominator"), result.denominator);
        rb_hash_aset(hash, rb_str_new_cstr("success"), Qtrue);
        return hash;
    } else {
        VALUE hash = rb_hash_new();
        rb_hash_aset(hash, rb_str_new_cstr("success"), Qfalse);
        rb_hash_aset(hash, rb_str_new_cstr("error"), rb_str_new_cstr(result.error));
        return hash;
    }
}

static VALUE units_parser_benchmark(VALUE self, VALUE input_str, VALUE iterations) {
    Check_Type(input_str, T_STRING);
    Check_Type(iterations, T_FIXNUM);
    
    const char* input = RSTRING_PTR(input_str);
    int len = (int)RSTRING_LEN(input_str);
    int iter_count = FIX2INT(iterations);
    
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    
    for (int i = 0; i < iter_count; i++) {
        parse_unit_string(input, len);
    }
    
    clock_gettime(CLOCK_MONOTONIC, &end);
    
    double elapsed = (end.tv_sec - start.tv_sec) + 
                     (end.tv_nsec - start.tv_nsec) / 1000000000.0;
    
    return rb_float_new(elapsed);
}

void Init_units_parser(void) {
    rb_mRubyUnits = rb_define_module("RubyUnits");
    rb_cUnitsParser = rb_define_class_under(rb_mRubyUnits, "UnitsParser", rb_cObject);
    
    rb_define_singleton_method(rb_cUnitsParser, "parse", units_parser_parse, 1);
    rb_define_singleton_method(rb_cUnitsParser, "benchmark", units_parser_benchmark, 2);
}