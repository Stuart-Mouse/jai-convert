
#import "Basic";
#import "Convert";
#import "Math";
#import "Utils";

main :: () {
    settings := context.conversion_settings;
    
    
    // int_to_int
    {
        
    }
    
    
    // float_to_int
    {
        test_float_to_int :: (float_value: float, int_expected: int, rounding_mode: Float_Rounding_Mode) {
            int_value: int;
            float_to_int(int_value, float_value, rounding_mode);
            
            if int_value != int_expected {
                log("test_float_to_int FAILED:\n\tfloat_value = %\n\tint_value = %\n\tint_expected = %\n\trounding_mode = %", float_value, int_value, int_expected, rounding_mode);
            }
        }
        
        test_float_to_int( 5.0,  5, .TRUNCATE);
        test_float_to_int( 5.5,  5, .TRUNCATE);
        test_float_to_int(-5.5, -5, .TRUNCATE);
        
        test_float_to_int( 5.0,  5, .FLOOR);
        test_float_to_int( 5.5,  5, .FLOOR);
        test_float_to_int(-5.5, -6, .FLOOR);
        
        test_float_to_int( 5.0,  5, .CEILING);
        test_float_to_int( 5.5,  6, .CEILING);
        test_float_to_int(-5.5, -5, .CEILING);
    }
    
    
}


NUMBER_LIMITS :: struct { 
    type:           Type;
    min:            string;
    min_minus_one:  string;
    max:            string;
    max_plus_one:   string;
}.[
    .{ u\8, "0", "-1",                  "255",                  "256" },
    .{ u16, "0", "-1",                "65535",                "65536" },
    .{ u32, "0", "-1",           "4294967295",           "4294967296" },
    .{ u64, "0", "-1", "18446744073709551615", "18446744073709551616" },
    
    .{ s\8,                 "-128",                 "-129",                 "127",                 "128" },
    .{ s16,               "-32768",               "-32769",               "32767",               "32768" },
    .{ s32,          "-2147483648",          "-2147483649",          "2147483647",          "2147483648" },
    .{ s64, "-9223372036854775808", "-9223372036854775809", "9223372036854775807", "9223372036854775808" },
];