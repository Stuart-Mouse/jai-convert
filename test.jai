#import "Basic"()(MEMORY_DEBUGGER=true);
#import "Math";
#import "Reflection";

#import "Utils";
using Convert :: #import "Convert";

main :: () {
    settings := context.conversion_settings;
    
    // int_to_int
    {
        _u\8: u\8;
        _u16: u16;
        _u32: u32;
        _u64: u64;
    
        _s\8: s\8;
        _s16: s16;
        _s32: s32;
        _s64: s64;
        
        // unsigned min
        assert(int_to_int(_u\8, 0) == true);
        assert(int_to_int(_u16, 0) == true);
        assert(int_to_int(_u32, 0) == true);
        assert(int_to_int(_u64, 0) == true);
        
        // unsigned min - 1
        assert(int_to_int(_u\8, -1) == false);
        assert(int_to_int(_u16, -1) == false);
        assert(int_to_int(_u32, -1) == false);
        assert(int_to_int(_u64, -1) == false);
        
        // unsigned max
        assert(int_to_int(_u\8, 255) == true);
        assert(int_to_int(_u16, 65535) == true);
        assert(int_to_int(_u32, 4294967295) == true);
        
        log("%, %", (18446744073709551615).(u64), type_of((18446744073709551615).(u64)));
        assert(int_to_int(_u64, (18446744073709551615).(u64)) == true);
        
        // unsigned max + 1
        assert(int_to_int(_u\8, 256) == false);
        assert(int_to_int(_u16, 65536) == false);
        assert(int_to_int(_u32, 4294967296) == false);
        // assert(int_to_int(_u64, 18446744073709551616) == false);
        
        // unsigned min - 1 with clamp
        assert(int_to_int(_u\8, -1, should_clamp = true) == true);
        assert(_u\8 == 0);
        
        assert(int_to_int(_u16, -1, should_clamp = true) == true);
        assert(_u16 == 0);
        
        assert(int_to_int(_u32, -1, should_clamp = true) == true);
        assert(_u32 == 0);
        
        assert(int_to_int(_u64, -1, should_clamp = true) == true);
        assert(_u64 == 0);
        
        // unsigned max + 1 with clamp
        assert(int_to_int(_u\8, 256, should_clamp = true) == true);
        assert(_u\8 == 255);
        
        assert(int_to_int(_u16, 65536, should_clamp = true) == true);
        assert(_u16 == 65535);
        
        assert(int_to_int(_u32, 4294967296, should_clamp = true) == true);
        assert(_u32 == 4294967295);
        
        // assert(int_to_int(_u64, 18446744073709551616, should_clamp = true) == true);
        // assert(_u32 == 18446744073709551615);
        
        
        // signed min
        assert(int_to_int(_s\8, -128) == true);
        assert(int_to_int(_s16, -32768) == true);
        assert(int_to_int(_s32, -2147483648) == true);
        assert(int_to_int(_s64, -9223372036854775808) == true);
        
        // signed min - 1
        assert(int_to_int(_s\8, -129) == false);
        assert(int_to_int(_s16, -32769) == false);
        assert(int_to_int(_s32, -2147483649) == false);
        // assert(int_to_int(_s64, -9223372036854775809) == false);
        
        // signed max
        assert(int_to_int(_s\8, 127) == true);
        assert(int_to_int(_s16, 32767) == true);
        assert(int_to_int(_s32, 2147483647) == true);
        assert(int_to_int(_s64, 9223372036854775807) == true);
        
        // signed max + 1
        assert(int_to_int(_s\8, 128) == false);
        assert(int_to_int(_s16, 32768) == false);
        assert(int_to_int(_s32, 2147483648) == false);
        assert(int_to_int(_s64, (9223372036854775808).(u64)) == false);
        
        // signed min - 1 with clamp
        assert(int_to_int(_s\8, -129, should_clamp = true) == true);
        assert(_s\8 == -128);
        
        assert(int_to_int(_s16, -32769, should_clamp = true) == true);
        assert(_s16 == -32768);
        
        assert(int_to_int(_s32, -2147483649, should_clamp = true) == true);
        assert(_s32 == -2147483648);
        
        // assert(int_to_int(_s64, -9223372036854775809, should_clamp = true) == true);
        // assert(_s64 == -9223372036854775808);
        
        
        // signed max + 1 with clamp
        assert(int_to_int(_s\8, 128, should_clamp = true) == true);
        assert(_s\8 == 127);
        
        assert(int_to_int(_s16, 32768, should_clamp = true) == true);
        assert(_s16 == 32767);
        
        assert(int_to_int(_s32, 2147483648, should_clamp = true) == true);
        assert(_s32 == 2147483647);
        
        assert(int_to_int(_s64, (9223372036854775808).(u64), should_clamp = true) == true);
        assert(_s64 == 9223372036854775807);
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
    
    // TODO: how to test int_to_float?
    // TODO: how to test float_to_float?
    
    // enum_to_enum
    {
        // enum
        {
            Enum_A :: enum { FOO; BAR; }
            Enum_B :: enum { BAR; FOO; BAZ; }
            
            enum_a: Enum_A;
            enum_b: Enum_B;
            
            enum_a = .BAR;
            assert(Convert.remap_enum(enum_b, enum_a) == true);
            assert(enum_b == .BAR);
            
            enum_b = .FOO;
            assert(Convert.remap_enum(enum_a, enum_b) == true);
            assert(enum_a == .FOO);
            
            enum_b = .BAZ;
            assert(Convert.remap_enum(enum_a, enum_b) == true);
            assert(enum_a == xx Enum_B.BAZ);
        }
        
        // enum_flags
        {
            Enum_A :: enum_flags { FOO; BAR; }
            Enum_B :: enum_flags { BAR; FOO; BAZ; }
            
            enum_a: Enum_A;
            enum_b: Enum_B;
            
            enum_a = .BAR;
            assert(remap_enum(enum_b, enum_a) == true);
            assert(enum_b == .BAR);
            
            enum_b |= .FOO;
            assert(remap_enum(enum_a, enum_b) == true);
            assert(enum_a == .FOO | .BAR);
            
            enum_b = .BAZ;
            assert(remap_enum(enum_a, enum_b) == true);
            assert(enum_a == 0);
        }
    }
    
    
    // remap_struct
    {
        Entity_V1 :: struct {
            position:       Vector2;
            health_points:  int;
            magic\_points:  int;
        }
        
        Entity_V2 :: struct {
            position:       Vector3;
            health_points:  s32;
            magic\_points:  float;
        }
        
        // simple case
        ev1: Entity_V1;
        ev2: Entity_V2;
        
        ev1 = .{ .{ 7, 13 }, 420, 69 };
        assert(remap_struct(ev2, ev1));
        assert(ev2.position == .{ 7, 13, 0 });
        assert(ev2.health_points == 420);
        assert(ev2.magic\_points == 69);
        
        // with using on src
        Entity_V3 :: struct {
            using position: Vector2;
            health_points:  int;
            magic\_points:  int;
        }
        ev3: Entity_V3;
        
        assert(remap_struct(ev3, ev1));
        assert(ev3.position == .{ 7, 13 });
        assert(ev3.health_points == 420);
        assert(ev3.magic\_points == 69);
        
        // with using on dst
        ev1 = .{};
        assert(remap_struct(ev1, ev3));
        assert(ev1.position == .{ 7, 13 });
        assert(ev1.health_points == 420);
        assert(ev1.magic\_points == 69);
    }
    
    // TODO: remap_union
        // by internal tag
        // by external tag
    
    // TODO: remap_array
    {
        fixed:       [8] int;
        view:         [] int;
        resizable:  [..] int;
        
        
        
    }
    
    // set_value_from_string
    #if false {
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
        
        // test all integer limits, inside and out
        // this is probably redundant with the above int_to_int tests
        for NUMBER_LIMITS {
            info := it.type.(*Type_Info_Integer);
            
            test :: (ti: *Type_Info, str: string, expect_success: bool) {
                number := Any_Number.{ type = ti };
                log("\t\tinput string: '%'", str);
                if Convert.set_value_from_string(to_any(*number), str) == expect_success {
                    log("\t\tTEST PASSED");
                } else {
                    log("\t\tTEST FAILED");
                }
                log("\t\toutput_value: % %", as_type(number.type), to_any(*number));
            }
            
            log("test %", it.type);
            
            log("\tmin");     test(info, it.min,           true);
            log("\tmin-1");   test(info, it.min_minus_one, false);
            log("\tmax");     test(info, it.max,           true);
            log("\tmax+1");   test(info, it.max_plus_one,  false);
        }
        
        // test float and double
        _float32: float32;
        assert(Convert.set_value_from_string(_float32, "3") == true);
        assert(Convert.set_value_from_string(_float32, "3.5") == true);
        assert(Convert.set_value_from_string(_float32, "text") == false);
        assert(Convert.set_value_from_string(_float32, "3.5text") == false);
        assert(Convert.set_value_from_string(_float32, "text3.5") == false);
        assert(Convert.set_value_from_string(_float32, "3.5.5") == false);
        
        _float64: float64;
        assert(Convert.set_value_from_string(_float64, "3") == true);
        assert(Convert.set_value_from_string(_float64, "3.5") == true);
        assert(Convert.set_value_from_string(_float64, "text") == false);
        assert(Convert.set_value_from_string(_float64, "3.5text") == false);
        assert(Convert.set_value_from_string(_float64, "text3.5") == false);
        assert(Convert.set_value_from_string(_float64, "3.5.5") == false);
    }
    
    report_memory_leaks();
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