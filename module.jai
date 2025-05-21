
Conversion_Types :: enum_flags u64 {
    NO_CONVERSION_REQUIRED :: 0;
    UNKNOWN_CONVERSION     :: 1;
    
    INT_TO_INT;
    INT_NARROWING;
    
    FLOAT_TO_FLOAT;
    FLOAT_NARROWING;
    
    INT_TO_FLOAT;
    FLOAT_TO_INT;
    
    ENUM_TO_INT;
    INT_TO_ENUM;
    ENUM_TO_FLOAT;
    FLOAT_TO_ENUM;
    
    ENUM_BY_NAME;
    ENUM_BY_VALUE;
    // ENUM_TO_FLAGS;   // not yet supported
    
    // NOTE: there are not yet any flags for conversions to or from bool, 
    //       since both any_to_bool and bool_to_any are kind of outliers, 
    //       in that they are the only utility conversion procs that accept multiple src/dst types.
    
    // Conversions from string to other types are not yet supported.
    // I'm a bit conflicted on how extensively I actually want to support doing that in the first place, 
    // since most applications will need to parse things in their own way.
    // STRING_TO_CSTRING;
    // STRING_TO_INT;
    // STRING_TO_ENUM;
    // STRING_TO_FLOAT;
    
    
    /*
        In order to reduce the number of flags required for all of the array permutations, 
        resizable arrays and array views are often lumped together as 'variable' arrays.
        
        More settings will surely be needed in the future for handling arrays, 
        in particular for allowing the user to specify how allocations occur and with what allocators.
    */
    ARRAY_FIXED_TO_VARIABLE;
    ARRAY_VARIABLE_TO_FIXED;
    
    ARRAY_RESIZABLE_TO_VIEW;
    ARRAY_VIEW_TO_RESIZABLE;
    
    WIDEN_FIXED_ARRAY;
    TRUNCATE_FIXED_ARRAY;
    
    // allows treating a single instance of T as if it were a [1] T 
    // will currently permit conversion to any array type
    // perhaps in the future this will be more granular
    SINGLE_TO_ARRAY;
    
    // allows converting a string to any array type
    // perhaps in the future this will be more granular
    STRING_TO_ARRAY;
    ARRAY_TO_STRING;
    
    // TODO: come up with a proper way to control allocations
    // COPY_STRING;
    // COPY_VIEW; // copy the actual underlying data pointed to by array views, so that dst view owns the underlying data.
    
    REMAP_STRUCT;
    REMAP_UNION;
    
    RECAST_POINTER;
    SHALLOW_COPY_POINTER;
    REMAP_THROUGH_POINTER;
    
    ALL :: 0xFFFF_FFFF_FFFF_FFFF;
}


default_conversion_settings := DEFAULT_CONVERSION_SETTINGS;
DEFAULT_CONVERSION_SETTINGS :: Conversion_Settings.{
    allowed_conversions   = .ALL,
    float_to_int_rounding = .TRUNCATE,
};

#add_context conversion_settings: *Conversion_Settings = *default_conversion_settings; // by pointer so that user can switch out conversion settings trivially

Conversion_Settings :: struct {
    allowed_conversions:    Conversion_Types;
    float_to_int_rounding:  enum { TRUNCATE; FLOOR; CEILING; NEAREST; };
    pointer_recast_procs:   [..] struct { proc: Pointer_Recast_Proc; data: *void; };
    get_union_type_procs:   [..] struct { proc: Resolve_Union_Proc;  data: *void; };
    
    // TODO: probably add some more in-depth rules for struct remapping.
    //       and probably allow overloading these on a per-struct basis
    //       maybe we check for certain notes on the struct/members?
    //       we could use notes for some aspects of arrays (views owning data, allocator for resizable arrays) idk
    //       better than notes would actually be just using the member data LUT thing I do in GON parser. (though this is still cope for not having structured notes)
}

// the Any's passed in and out must be pointers
// returns true if the type has been recast, false if not
// this is only for casting down to a more specific type (e.g.: casting a *Type_Info down to a *Type_Info_Enum)
Pointer_Recast_Proc :: #type (ptr: Any_With_Context, user_data: *void) -> (Any, bool);

// Union types are resolved by returning the type info struct member for the union member that is valid.
// The union_ti parameter is used during remapping to pass the type info for the dst union's type info, 
//     since we usually want to match on this rather than on the src type (which is probably dynamically loaded type info).
Resolve_Union_Proc :: #type (union_ti: *Type_Info, src: Any_With_Context, user_data: *void) -> *Type_Info_Struct_Member;


// TODO: generalized remap callback that will completely override remapping for a given dst type
//       peraps that was even th emore wise/simple way to go for unions, but whatever
//       if we did that generally for unions, we would have to always pass src_parent to any_to_any

// TODO: consider also casting up to more general type? This is more of something we can do in a LUT I think.

// TODO: also consider what to do about procedure pointers
//       maybe we can give user a way to store procedures as a string or enum value in data packer, then deconvert on parse?
//       or we can use another flag to denote proc pointer in Packed_Pointer_Flags and let the user map other 32 bits to a proc pointer
//       we may not need to use a bitflag in in packed pointer, since we can already differentiate pointer from procedure in type info.
//       but maybe that's just easier anyhow?

is_allowed :: inline (conversion_type: Conversion_Types) -> bool { 
    return context.conversion_settings.allowed_conversions & conversion_type == conversion_type;
}

log_disallowed_conversion :: inline (conversion: Conversion_Types, proc_name: string, loc := #caller_location) {
    log("Error: disallowed conversion % in % (line: %)", conversion, proc_name, loc.line_number);
}

log_unsupported_conversion :: inline (conversion: Conversion_Types, proc_name: string, loc := #caller_location) {
    log("Error: unsupported conversion % in % (line: %)", conversion, proc_name, loc.line_number);
}

/*
    TODO: explain/document this structure better
*/
Any_With_Context :: struct {
    data:                 Any;
    parent:               Any;                        // if data is a struct member or array element, this points to the struct or array.
    struct_member_info:   *Type_Info_Struct_Member;   // if data is a struct member, this is the info for that. may be null.
}


// convenience proc for doing conversions more inline with a static dst type
any_to :: inline ($T: Type, src: Any) -> T, bool {
    dst: T;
    ok := any_to_any(dst, src);
    return dst, ok;
}

// similar to the above, but the dst type is dynamic, and dst value is dynamically allocated
any_to_new :: inline (T: *Type_Info, src: Any) -> Any, bool {
    dst := New_Any(T);
    ok := any_to_any(dst, src);
    return dst, ok;
}

// the most general remapping procedure, handles any dst and src types
any_to_any :: (_dst: Any, _src: Any) -> bool {
    dst := _dst;
    src := _src;
    
    // TODO: allow user to callback on dst and src types before unwrapping variants.
    //       maybe even check for special handling each time we unwrap nested variants?
    // NOTE: the loops are there because I assumed variants could be nested, but maybe this is not the case..?
    while dst.type.type == .VARIANT { dst.type = dst.type.(*Type_Info_Variant).variant_of; }
    while src.type.type == .VARIANT { src.type = src.type.(*Type_Info_Variant).variant_of; }
    
    if dst.type.type == {
      case .STRING;
        if src.type.type == .STRING {
            // TODO: we would like to have an option as to whether this should copy
            dst.value_pointer.(*string).* = copy_string(src.value_pointer.(*string).*);
            return true;
        }
        if is_allowed(.ARRAY_TO_STRING) {
            if src.type.type == .ARRAY {
                // cannot just compare array element type to type_info(u8), since src.type could be dynamically loaded
                // so instead we assume that any type with runtime size of 1 is probably u8... 
                ti_array := src.type.(*Type_Info_Array);
                if ti_array.element_type.runtime_size == 1  return false; 
                if ti_array.array_type == .FIXED {
                    dst_string := dst.value_pointer.(*string);
                    memcpy(dst_string.data, src.value_pointer, ti_array.array_count);
                    dst_string.count = ti_array.array_count;
                } else {
                    // TODO: we would like to have an option as to whether this should copy
                    dst.value_pointer.(*string).* = copy_string(src.value_pointer.(*string).*);
                }
                return true;
            }
        }
        return false;
        
      case .BOOL;
        return any_to_bool(dst, src);
        
      case .INTEGER;
        return any_to_int(dst, src);
        
      case .FLOAT;
        return any_to_float(dst, src);
        
      case .STRUCT;
        // currently, we only do struct -> struct
        // maybe in the future we will allow other types to coerce to structs
        if src.type.type != dst.type.type  return false; 
        return remap_struct(dst, src);
        
      case .ENUM;
        return remap_enum(dst, src);
        
      case .ARRAY;
        return remap_array(dst, src);
        
      case .POINTER;
        // Two methods of handling pointers:
        //   1. copy the pointer itself (requires that the src and dst type match, or that they can cast to the same base type)
        //   2. copy and remap the data through the pointer (requires allocating space for dst type)
        
        // TODO: user should probably also be able to set which types get remapped through and which ones get shallow copied.
        //       we will need something like GON's IO_Data struct eventually to handle things like this better.
        //       and perhaps we can use that structure to clean up the union stuff too.
        //       It's just a bit more complex here because we also have the context stuff, but oh well.
        if is_allowed(.REMAP_THROUGH_POINTER) {
            // TODO: add option to configure allocator to use for a given type
            if src.value_pointer == null  return true;
            
            src_derefed := dereference_any_pointer(src);
            if src_derefed.value_pointer == null  return true;
            
            dst_derefed := dereference_any_pointer(dst);
            if dst_derefed.value_pointer == null {
                dst_derefed.value_pointer = Dynamic_New(dst_derefed.type);
                dst.value_pointer.(**void).* = dst_derefed.value_pointer;
            }
            
            // TODO: if this fails, we should deallocate the dynamic_new'd item
            return any_to_any(dst_derefed, src_derefed);
        } 
        
        // only attempt shallow copy if remapping through pointer is not allowed
        if is_allowed(.SHALLOW_COPY_POINTER) {
            // TODO: make this more powerful by allowing recasting of pointers to common type.
            // e.g.: dst is *Type_Info and src is *Type_Info_Struct, should be allowed
            
            
            
            if src.type == dst.type {
                dst.value_pointer.(**void).* = src.value_pointer.(**void).*;
            }
            return true;
        }
        
        // I guess this one will just silently 'fail' for now?
        // Doesn't feel right to throw an error just because user may not want to do pointers...
        return true;
    }
    
    return true;
}

remap_struct :: (dst: Any, src: Any) -> bool {
    assert(src.type.type == .STRUCT);
    assert(dst.type.type == .STRUCT);
    
    if !is_allowed(.REMAP_STRUCT) {
        log_unsupported_conversion(.REMAP_STRUCT, "remap_struct");
        return false;
    }
    
    dst_ti := dst.type.(*Type_Info_Struct);
    src_ti := src.type.(*Type_Info_Struct);
    
    /*
        NOTE: ignoring #place struct members
        
        If we do not ignore #place members, we will end up doing a lot of duplicate work.
        
        I am not sure if we will ever have very nice handling for #place struct members, since they are highly problematic to remapping.
        Generally, most #place members are used to provide an alternative way of accessing the data held in a struct, for example:
            'xy' and 'yz' members in a Vector3
            'floats' and 'coefs' members in a mat4
        These are essentially 0-cost getters, or an alternative interface to the same underlying data.
        
        This is unlike a union, because a union is typically storing two different pieces of data in the same memory space.
        I am sure there is probably some niche use case for #place where the members actually serve to encode unique data, but since it is uncommon, I have not really considered how to make affordances for that use case.
    */
    
    // TODO: once we have union working, we can go back to using <= in the below #place checks
    
    // remap elements by name
    last_dst_member_offset := -1;
    for dst_member: dst_ti.members {
        if dst_member.flags & .CONSTANT  continue;
        if dst_member.offset_in_bytes < last_dst_member_offset  {
            break; // ignoring #place members. Wish there were a better way to do this.
        }
        last_dst_member_offset = dst_member.offset_in_bytes;
        
        // TODO: I am probably not handling the case where a using is on a union, but aaaaaahhhhh 
        
        // use of get_field here should probably not result in any unintentional redundant copying of fields I think?
        // but maybe if we have some memory leak show up at some point, this is a place to keep in mind...
        src_member := get_field(src_ti, dst_member.name);
        if src_member == null {
            // I'm not sure if this could have unintended side-effects,
            // but the idea here is that if we can't find a match for a member that has a using on it, 
            // then we will fallback to trying to look for the members of the using'd member in the top level of src struct
            // this should allow the remapper to catch cases where you factor out some member into a another struct and then 'using' that new struct in the old struct 
            if dst_member.flags & .USING {
                print("remapping src to using'd member % (%)\n", dst_member.name, as_type(dst_member.type));
            
                dst_member_any := Any.{ dst_member.type, dst.value_pointer + dst_member.offset_in_bytes };
                if !any_to_any(dst_member_any, src)  {
                    log("Error: failed while remapping struct member %!", dst_member.name);
                    return false;
                }
            }
            continue;
        }
        if src_member.flags & .CONSTANT  continue;
        
        // print("remapping member % to % (%)\n", src_member.name, dst_member.name, as_type(dst_member.type));
        
        dst_member_any := Any.{ dst_member.type, dst.value_pointer + dst_member.offset_in_bytes };
        src_member_any := Any.{ src_member.type, src.value_pointer + src_member.offset_in_bytes };
        
        if type_is_union(dst_member.type) {
            if !remap_union(dst_member_any, src_member_any, src, src_member)  {
                log("Error: failed while remapping struct member (union) %!", dst_member.name);
                return false;
            }
        } else {
            // TODO: what if src is union, but dst is not?
            if !any_to_any(dst_member_any, src_member_any)  {
                log("Error: failed while remapping struct member %!", dst_member.name);
                return false;
            }
        }
    }
    
    return true;
}

// union is just a struct where we want to only copy one member
// if we map one union to another, we actually want to map by the name of union member
// so we could just do a remap_struct, with an extra parameter for union_member, passing the 


/*
    Remapping Unions
    
    sometimes, the union itself contains all of the necessary information required to figure out the union should be treated as.
    (e.g.: a union of Entity types where all members of union contain the same base type as first member)
    
    But, many times we require more context, either in the form of an external type tag or enum value.
    If the parent_any is not provided, then 
    
    
    The parent Any may not be provided in the user callback, so the user needs to be aware of this and handle this case.
    src_member_ti will be provided if and only if src_parent is provided
    
    TODO: should we pass Data with context for src data here?
*/
remap_union :: (dst: Any, src: Any, src_parent: Any, src_member_info: *Type_Info_Struct_Member) -> bool {
    settings := context.conversion_settings;
    
    assert(dst.type.type == .STRUCT);
    dst_ti := dst.type.(*Type_Info_Struct);
    assert(dst_ti.textual_flags & .UNION == .UNION);
    
    if !is_allowed(.REMAP_UNION) {
        log_unsupported_conversion(.REMAP_UNION, "remap_struct");
        return false;
    }
    
    // TODO: probably should support this, shouldn't be too hard
    if !type_is_union(src.type) {
        log("Error: Conversion from non-union type to union is not supported.");
        return false;
    }
    
    src_member: *Type_Info_Struct_Member;
    for settings.get_union_type_procs {
        src_member = it.proc(dst.type, .{ src, src_parent, src_member_info }, it.data);
        if src_member  break;
    }
    if !src_member  {
        // log("Warning: failed to resolve union member in remap_struct.");
        return true;
    }
    assert(src_member.flags & .CONSTANT == 0);
    
    // search for dst member matching src member
    last_dst_member_offset := -1;
    for dst_member: dst_ti.members {
        if dst_member.flags & .CONSTANT  continue;
        if dst_member.name == src_member.name {
            if !any_to_any(
                Any.{ dst_member.type, dst.value_pointer + dst_member.offset_in_bytes }, 
                Any.{ src_member.type, src.value_pointer + src_member.offset_in_bytes }
            )  return false;
            
            return true;
        }
    }
    
    return true; // TODO?
}



type_is_union :: (ti: *Type_Info) -> bool {
    return ti.type == .STRUCT && (ti.(*Type_Info_Struct).textual_flags & .UNION);
}


/*
    remap_array implementation notes


    What happens if we have some kind of change in type like
        [N] T to [M][N] T
    
    We would probably want the [N]u8 to map to the first row (M = 0) of the [M][N]u8
    But what we would actually get would be that the [N]u8's elements get spread across the M columns.
    So in order ot resolve this we would actually need to first calculate how much indirection there is in each case
        and then map the types so that the base type is what matches up.
    
    This is starting to get a bit complicated, and we also still can't really check ahead of time if the base types even *actually* match up or not
    All we have to go off of here is the number of levels of indirection, and the array types/counts
    We could implement some basic heuristics, but if we then want it to be configurable, it could be a bit much.
    
    But, we also don't want to just give up on arrays altogether...
    and going from a single value to an array of values is still very useful.
    
    current logic for single to array will actually probably work just fine
    but when it comes to nest arrays, things get tricky.
    pre-cheking level of indireciton is probably not a bad idea
    
    but then we have to think about array types as well, and that could get messy
    like for example
        [M][N] T -> [][N] T
        or 
        [M][N] T -> [M][..] T
        
    
    
    
    All array conversions are essentailly just view -> view, but each dst type has some distinct concerns
    
    if dst is 
        fixed
            we may be forced to lengthen or truncate src array
            and we don't currently have a means to store the actual length that was filled in here
        view
            need to consider whether we want a clone of the src, or just duplicate the view onto src's underlying data
            for now, we only do the copy, since this was created first to use with the data packer
        resizable
            need to consider setting the array's allocator
                we can't assume the allocator is already set, because the resizable array itself may have been dynamically created by the remapper
                should we do some lookup on array type that user specifies?
                should it be handled in a callback?
                we can't copy the allocator from src, because that's a pointer which will not be valid if src was from a file
*/

// TODO: consider how allocators / allocations should work and what settings to implement
// Shallow copy vs deep copy options?
remap_array :: (dst: Any, src: Any) -> bool {
    /*
        remap_array is probably the most complex remapping case, since we need to handle not only the three array types, 
            but we also support remapping a single-element of a given type T to an array with element type T.
        
        Because of this, we need to pull out the type, value_pointer, and element_type from dst and src, 
            and then manually override those in certain cases. 
        So for the sake of keeping the code legible, dst and src should not be used directly at all beyond this header section.
    */
    
    // NOTE: src does not necessarily have to be an array here
    assert(dst.type.type == .ARRAY);
    
    
    // TODO: we can probably clean up a lot of these extra variables by just creating a new Type_Info_Array on the stack for src which is a copy of the src type info, and then modifying it as needed.
    //       but since we may get various src type infos, perhaps we need an Any_Type_Info which has union space for any type info we could get...
    
    src_type := src.type;
    dst_type := dst.type.(*Type_Info_Array);
    
    src_value_pointer := src.value_pointer;
    dst_value_pointer := dst.value_pointer;
    
    src_element_type: *Type_Info; // we figure this out later, once we can be sure src_type is an array
    dst_element_type := dst_type.element_type;
    
    src_array_type: Type_Info_Array.Array_Type;
    
    conversion_type := Conversion_Types.UNKNOWN_CONVERSION;
    
    // remap string to array of u8
    if src_type.type == .STRING {
        if !is_allowed(.STRING_TO_ARRAY) {
            log_disallowed_conversion (conversion_type, "remap_array");
            return false;
        }
        
        if dst_type.element_type.runtime_size != 1 {
            log("Error: cannot convert from string to %.", as_type(dst_type));
        }
        
        src_string_pointer := src_value_pointer.(*string);
        if dst_type.array_type == {
          case .FIXED;
            count := min(dst_type.array_count, src_string_pointer.count);
            memcpy(dst_value_pointer, src_string_pointer.data, count);
          case .VIEW;
            // TODO: this just overwrites the existing value without checking... perhaps we should not do that...
            // TODO: we would like to have an option as to whether this should copy
            dst_value_pointer.(*string).* = copy_string(src_string_pointer.*);
          case .RESIZABLE;
            array := dst_value_pointer.(*[..]u8);
            array_add(array, ..src_string_pointer.(*[]u8).*);
        }
        return true;
    }
    
    // now we determine src_element_type and conversion_type, as well as get src data and count
    src_count: int   = ---;
    src_data:  *void = ---;
    
    if src_type.type == .ARRAY {
        src_element_type    = src_type.(*Type_Info_Array).element_type;
        src_array_type      = src_type.(*Type_Info_Array).array_type;
        src_count, src_data = get_array_count_and_data(src_value_pointer, xx src_type);
    } else {
        // for single-to-array, we treat the one element T as a [1] T
        conversion_type  = .SINGLE_TO_ARRAY;
        src_element_type = src_type;
        src_count        = 1;
        src_data         = src_value_pointer;
        src_array_type   = .FIXED;
    } 
    
    // we OR in the array conversion type since we may have something like `SINGLE_TO_ARRAY | ARRAY_FIXED_TO_VARIABLE` if we are going from `T` to `[] T`
    if dst_type.array_type == {
      case .FIXED;
        if src_array_type == {
          case .FIXED; 
            // TODO: we should probably notify the user if fixed array gets widened or truncated
            if      src_count > dst_type.array_count then conversion_type |= .TRUNCATE_FIXED_ARRAY;
            else if src_count < dst_type.array_count then conversion_type |= .WIDEN_FIXED_ARRAY;
            else    conversion_type |= .NO_CONVERSION_REQUIRED;
          case .VIEW;       conversion_type |= .ARRAY_VARIABLE_TO_FIXED;
          case .RESIZABLE;  conversion_type |= .ARRAY_VARIABLE_TO_FIXED;
        }
      case .VIEW;
        if src_array_type == {
          case .FIXED;      conversion_type |= .ARRAY_FIXED_TO_VARIABLE;
          case .VIEW;       conversion_type |= .NO_CONVERSION_REQUIRED;
          case .RESIZABLE;  conversion_type |= .ARRAY_RESIZABLE_TO_VIEW;
        }
      case .RESIZABLE;
        if src_array_type == {
          case .FIXED;      conversion_type |= .ARRAY_FIXED_TO_VARIABLE; 
          case .VIEW;       conversion_type |= .ARRAY_VIEW_TO_RESIZABLE;
          case .RESIZABLE;  conversion_type |= .NO_CONVERSION_REQUIRED;
        }
    }
    
    if !is_allowed(conversion_type) {
        if conversion_type == .UNKNOWN_CONVERSION
            then log_unsupported_conversion(conversion_type, "remap_array");
            else log_disallowed_conversion (conversion_type, "remap_array");
        return false;
    }
    
    // if we have nothing to copy from src, then just return success
    if src_data == null || src_count == 0  return true;
    
    
    // we have to do a bit more work when getting dst data and count, 
    // since we actually want to allocate for the view and resizable cases
    dst_count: int   = ---;
    dst_data:  *void = ---;
    
    if dst_type.array_type == {
      case .FIXED;
        dst_data  = dst_value_pointer;
        dst_count = dst_type.array_count;
        
      case .VIEW;
        raw_array := dst_value_pointer.(*Array_View_64);
        
        // NOTE: we only allocate new data for the array view if it is currently null, 
        //       otherwise, we assume that user pre-allocated a set amount of space.
        if raw_array.data == null {
            assert(raw_array.count == 0, "dst_count was %", raw_array.count);
            // TODO: give the user the ability to set allocators for array views' data
            raw_array.count = src_count;
            raw_array.data  = alloc(src_count * dst_type.element_type.runtime_size);
            memset(raw_array.data, 0, src_count * dst_type.element_type.runtime_size);
        } else {
            log("Warning: array view data was non-null in remap_array: data %, count %", raw_array.data, raw_array.count);
        }
        dst_count = raw_array.count;
        dst_data  = raw_array.data;
        
      case .RESIZABLE;
        raw_array := dst_value_pointer.(*Resizable_Array);
        
        // TODO: should we only reserve space when resizable array is empty, like in .VIEW case above?
        array_reserve_nonpoly(xx raw_array, src_count, dst_element_type.runtime_size);
        assert(raw_array.allocated == src_count);
        raw_array.count = src_count;
        
        dst_count = raw_array.count;
        dst_data  = raw_array.data;
    }
    
    if dst_data == null || dst_count == 0 {
        log("Error: dst array was null or empty in remap_array.");
        print_stack_trace(context.stack_trace, to_standard_error = false);
        return false;
    }
    
    
    // COPY ARRAY DATA
    
    // TODO: probably log some warning when array counts don't match?
    min_count       := min(src_count, dst_count);
    src_element_any := Any.{ src_element_type, src_data };
    dst_element_any := Any.{ dst_element_type, dst_data };
    
    for 0..min_count-1 {
        if !any_to_any(dst_element_any, src_element_any) {
            log("Error: unable to remap data");
            return false;
        }
        src_element_any.value_pointer += src_element_type.runtime_size;
        dst_element_any.value_pointer += dst_element_type.runtime_size;
    }
    
    return true;
}

// check if we are allowed do it by name, else do it by value
remap_enum :: (dst: Any, src: Any) -> bool { 
    settings := *context.conversion_settings;

    assert(src.type.type == .ENUM);
    assert(dst.type.type == .ENUM);
    
    src_ti := src.type.(*Type_Info_Enum);
    dst_ti := dst.type.(*Type_Info_Enum);
    
    // TODO: should we skip this if both src and dst are #specified?
    conversion := Conversion_Types.ENUM_BY_NAME;
    if is_allowed(conversion) {
        // if we are remapping by name, then it really doesn't make sense to map an enum to enum_flags, does it?
        // for now, we will prohibit it
        if (dst_ti.enum_type_flags & .FLAGS) != (src_ti.enum_type_flags & .FLAGS) {
            log_disallowed_conversion(conversion, "remap_enum");
            return false;
        }
        
        if dst_ti.enum_type_flags & .FLAGS {
            src_s64, dst_s64: s64;
            enum_to_int(src_s64, src);
            
            for src_ti.values {
                if (it & src_s64) == it {
                    src_name := src_ti.names[it_index];
                    for dst_ti.names {
                        if it == src_name {
                            dst_s64 |= dst_ti.values[it_index];
                            break;
                        }
                    }
                }
            }
            
            int_to_enum(dst, dst_s64);
            return true;
        }
        else {
            src_s64: s64;
            enum_to_int(src_s64, src);
            
            src_value_name: string;
            for src_ti.values {
                if it == src_s64 {
                    src_value_name = src_ti.names[it_index];
                    break;
                }
            }
            
            if src_value_name {
                for dst_ti.names {
                    if it == src_value_name {
                        int_to_enum(dst, dst_ti.values[it_index]);
                        return true;
                    }
                }
            }
            
            // For now, if we are not able to match by name, we will still fallback to trying to match by value.
            // log("Error: unable to match enum value by name in %", conversion, proc_name);
            // return false;
        }
    }
    
    conversion = .ENUM_BY_VALUE;
    if is_narrowing_int(dst_ti.internal_type, src_ti.internal_type)  conversion |= .INT_NARROWING;
    if !is_allowed(conversion) {
        log_disallowed_conversion(conversion, "remap_enum");
        return false;
    }
    
    enum_to_enum(dst, src);
    return true;
}

any_to_int :: (dst: Any, src: Any) -> bool {
    settings := *context.conversion_settings;
    
    assert(dst.type.type == .INTEGER);
    
    if src.type.type == {
      case .ENUM; 
        conversion := Conversion_Types.ENUM_TO_INT;
        if is_narrowing_int(xx dst.type, src.type.(*Type_Info_Enum).internal_type)  conversion |= .INT_NARROWING;
        if !is_allowed(conversion) {
            log_disallowed_conversion(conversion, "any_to_int");
            return false;
        }
        enum_to_int(dst, src);
        return true;
        
      case .INTEGER;
        conversion := Conversion_Types.INT_TO_INT;
        if is_narrowing_int(xx dst.type, xx src.type)  conversion |= .INT_NARROWING;
        if !is_allowed(conversion) {
            log_disallowed_conversion(conversion, "any_to_int");
            return false;
        }
        return int_to_int(dst, src);
        
      case .FLOAT; 
        conversion := Conversion_Types.FLOAT_TO_INT;
        if !is_allowed(conversion) {
            log_disallowed_conversion(conversion, "any_to_int");
            return false;
        }
        float_to_int(dst, src);
        return true;
        
      case .BOOL;
        return bool_to_any(dst, src);
    }
    
    return false;
}

any_to_float :: (dst: Any, src: Any) -> bool {
    settings := *context.conversion_settings;

    assert(dst.type.type == .FLOAT);
    
    if src.type.type == {
      case .ENUM; 
        conversion := Conversion_Types.ENUM_TO_FLOAT;
        if !is_allowed(conversion) {
            log_disallowed_conversion(conversion, "any_to_float");
            return false;
        }
        enum_to_float(dst, src);
        return true;
        
      case .INTEGER;
        conversion := Conversion_Types.INT_TO_FLOAT;
        if !is_allowed(conversion) {
            log_disallowed_conversion(conversion, "any_to_float");
            return false;
        }
        int_to_float(dst, src);
        return true;
        
      case .FLOAT; 
        conversion := Conversion_Types.FLOAT_TO_FLOAT;
        if is_narrowing_float(xx dst.type, xx src.type)  conversion |= .FLOAT_NARROWING;
        if !is_allowed(conversion) {
            log_disallowed_conversion(conversion, "any_to_float");
            return false;
        }
        float_to_float(dst, src);
        return true;
        
      case .BOOL;
        return bool_to_any(dst, src);
    }
    
    return false;
}


// ========== Utility Conversions ==========

bool_to_any :: (dst: Any, src: Any) -> bool {
    assert(src.type.type == .BOOL);
    if dst.type.type == {
      case .BOOL;
        dst.value_pointer.(*bool).* = src.value_pointer.(*bool).*;
        return true;
        
      case .ENUM; #through;
      case .INTEGER;
        memset(src.value_pointer, 0, src.type.runtime_size);
        src.value_pointer.(*bool).* = dst.value_pointer.(*bool).*; // NOTE: little endian assumed?
        return true;
        
      case .FLOAT;
        f64_value: float64 = ifx src.value_pointer.(*bool).* then 1.0 else 0.0;
        if dst.type.runtime_size == {
          case 4; src.value_pointer.(*float32).* = f64_value.(float32);
          case 8; src.value_pointer.(*float64).* = f64_value;
        }
    }
    return false;
}

any_to_bool :: (dst: Any, src: Any) -> bool {
    assert(dst.type.type == .BOOL);
    if src.type.type == {
      case .BOOL; 
        dst.value_pointer.(*bool).* = src.value_pointer.(*bool).*;
        return true;
        
      case .ENUM; #through;
      case .INTEGER;
        ptr := (*src.value_pointer).(*u8);
        for 0..src.type.runtime_size-1 {
            if ptr.* != 0 {
                dst.value_pointer.(*bool).* = true;
                break;
            }
            ptr += 1;
        }
        return true;
        
      case .FLOAT;
        f64_value: float64;
        if src.type.runtime_size == {
          case 4; f64_value = src.value_pointer.(*float32).*.(float64);
          case 8; f64_value = src.value_pointer.(*float64).*;
        }
        if f64_value then dst.value_pointer.(*bool).* = true;
        return true;
    }
    return false;
}

is_narrowing_int :: (dst_ti: *Type_Info_Integer, src_ti: *Type_Info_Integer) -> bool {
    if src_ti.runtime_size > dst_ti.runtime_size  return true;
    if src_ti.signed {
        if !dst_ti.signed  return true;
    } else {
        if dst_ti.signed && src_ti.runtime_size == dst_ti.runtime_size  return true;
    }
    return false;
}

// returns false if cast result would be out-of-range for destination type and clamping is not enabled
int_to_int :: (dst: Any, src: Any, should_clamp := false) -> bool {
    assert(src.type.type == .INTEGER);
    assert(dst.type.type == .INTEGER);
    
    src_ti := src.type.(*Type_Info_Integer);
    dst_ti := dst.type.(*Type_Info_Integer);
    
    // don't just compare type info pointers directly because we may be using external type infos
    if src_ti.signed == dst_ti.signed && src_ti.runtime_size == dst_ti.runtime_size {
        memcpy(dst.value_pointer, src.value_pointer, dst_ti.runtime_size);
        return true;
    }
    
    // we use u64 as intermediate and an extra boolean to represent that number is negative
    u64_value, is_negative := int_to_abs_and_sign(src);
    return range_check_and_store(dst, u64_value, is_negative, should_clamp);
}

// get absolute value of any int type, and a boolean representing whether the value was negative
int_to_abs_and_sign :: (src: Any) -> (abs: u64, sign: bool) {
    assert(src.type.type == .INTEGER);
    info := src.type.(*Type_Info_Integer);
    
    u64_value: u64;
    is_negative := false;
    
    if info.signed {
        s64_value: s64;
        if info.runtime_size == {
          case 1; s64_value = xx src.value_pointer.(*s\8).*;
          case 2; s64_value = xx src.value_pointer.(*s16).*;
          case 4; s64_value = xx src.value_pointer.(*s32).*;
          case 8; s64_value = xx src.value_pointer.(*s64).*;
        }
        is_negative = s64_value < 0;
        u64_value = ifx is_negative 
            then abs(s64_value + 1).(u64) + 1 // compensate for two's complement asymmetry
            else s64_value.(u64);
    } else {
        if info.runtime_size == {
          case 1; u64_value = xx src.value_pointer.(*u\8).*;
          case 2; u64_value = xx src.value_pointer.(*u16).*;
          case 4; u64_value = xx src.value_pointer.(*u32).*;
          case 8; u64_value = xx src.value_pointer.(*u64).*;
        }
    }
    
    return u64_value, is_negative;
}

range_check_and_store :: (dst: Any, abs_value_u64: u64, is_negative: bool, should_clamp := false) -> bool {
    assert(dst.type.type == .INTEGER);
    info := dst.type.(*Type_Info_Integer);
    
    vmin: s64;
    vmax: u64;
    abs_vmin: u64;
    if info.signed {
        if info.runtime_size == {
          case 1; vmin, vmax = S\8_MIN.(s64), xx S\8_MAX;
          case 2; vmin, vmax = S16_MIN.(s64), xx S16_MAX;
          case 4; vmin, vmax = S32_MIN.(s64), xx S32_MAX;
          case 8; vmin, vmax = S64_MIN.(s64), xx S64_MAX;
        }
        abs_vmin = abs(vmin+1).(u64)+1;
    } else {
        if info.runtime_size == {
          case 1; vmax = xx U\8_MAX;
          case 2; vmax = xx U16_MAX;
          case 4; vmax = xx U32_MAX;
          case 8; vmax = xx U64_MAX;
        }
        abs_vmin = 0;
    }
    assert(vmax != 0);
    
    if is_negative {
        if abs_value_u64 > abs_vmin {
            if should_clamp {
                log_clamped_value_warning(-(abs_value_u64-1).(s64) - 1, info, vmin, vmax, vmin);
                abs_value_u64 = abs_vmin;
            } else {
                log_range_error(-(abs_value_u64-1).(s64) - 1, info, vmin, vmax, vmin);
                return false;
            }
        }
        if info.signed {
            s64_value := -(abs_value_u64-1).(s64) - 1;
            if info.runtime_size == {
              case 1; dst.value_pointer.(*s\8).* = xx,no_check s64_value;
              case 2; dst.value_pointer.(*s16).* = xx,no_check s64_value;
              case 4; dst.value_pointer.(*s32).* = xx,no_check s64_value;
              case 8; dst.value_pointer.(*s64).* = xx,no_check s64_value;
            }
        } else {
            // We can just memset to 0 here as all unsigned values have a min of 0.
            memset(dst.value_pointer, 0, info.runtime_size);
        }
    } else {
        if abs_value_u64 > vmax.(u64) {
            if should_clamp {
                log_clamped_value_warning(abs_value_u64, info, vmin, vmax, vmax);
                abs_value_u64 = vmax.(u64);
            } else {
                log_range_error(abs_value_u64, info, vmin, vmax, vmax);
                return false;
            }
        }
        // We can just memcpy for all integer types here, since we already know the value is in range and is positive.
        memcpy(dst.value_pointer, *abs_value_u64, info.runtime_size);
    }
    return true;
}

#scope_file // where weird helper procs belong

// Any is used for int values in below procs since types may vary and there's no reason to make this polymorphic.
log_clamped_value_warning :: (value: Any, type: *Type_Info, min: s64, max: u64, clamped: Any) {
    log("Warning: value of % cannot be assigned to type %. (Valid range is [% - %]) Clamping to % as a fallback.", value, as_type(type), min, max, clamped);
}
log_range_error :: (value: Any, type: *Type_Info, min: s64, max: u64, clamped: Any) {
    log("Error: value of % cannot be assigned to type %. (Valid range is [% - %].)", value, as_type(type), min, max);
}

#scope_export



enum_as_int :: inline (src: Any) -> Any {
    assert(src.type.type == .ENUM);
    return Any.{ src.type.(*Type_Info_Enum).internal_type, src.value_pointer };
}

// for convenience
int_to_enum   :: inline (dst: Any, src: Any) { int\ _to_int   ( enum_as_int(dst), src              ); }
enum_to_int   :: inline (dst: Any, src: Any) { int\ _to_int   ( dst,              enum_as_int(src) ); }
enum_to_enum  :: inline (dst: Any, src: Any) { int\ _to_int   ( enum_as_int(dst), enum_as_int(src) ); }
float_to_enum :: inline (dst: Any, src: Any) { float_to_int   ( enum_as_int(dst), src              ); }
enum_to_float :: inline (dst: Any, src: Any) { int\ _to_float ( dst,              enum_as_int(src) ); }


is_narrowing_float :: inline (dst_ti: *Type_Info_Float, src_ti: *Type_Info_Float) -> bool {
    return src_ti.runtime_size > dst_ti.runtime_size;
} 

float_to_float :: (dst: Any, src: Any) {
    assert(src.type.type == .FLOAT);
    assert(dst.type.type == .FLOAT);
    
    // nested switch here because there's only four cases; no point using an intermediate value
    if src.type.runtime_size == {
      case 4;
        if dst.type.runtime_size == {
          case 4; dst.value_pointer.(*float32).* = src.value_pointer.(*float32).*;
          case 8; dst.value_pointer.(*float64).* = src.value_pointer.(*float32).*.(float64);
        }
      case 8;
        if dst.type.runtime_size == {
          case 4; dst.value_pointer.(*float32).* = src.value_pointer.(*float64).*.(float32);
          case 8; dst.value_pointer.(*float64).* = src.value_pointer.(*float64).*;
        }
    }
}


float_to_int :: (dst: Any, src: Any) {
    assert(src.type.type == .FLOAT);
    assert(dst.type.type == .INTEGER);
    
    s64_value: s64;
    if src.type.runtime_size == {
        case 4; s64_value = src.value_pointer.(*float32).*.(s64);
        case 8; s64_value = src.value_pointer.(*float64).*.(s64);
    }
    if dst.type.(*Type_Info_Integer).signed {
        if dst.type.runtime_size == {
          case 1; dst.value_pointer.(*s8 ).* = s64_value.(s8 );
          case 2; dst.value_pointer.(*s16).* = s64_value.(s16);
          case 4; dst.value_pointer.(*s32).* = s64_value.(s32);
          case 8; dst.value_pointer.(*s64).* = s64_value.(s64);
        }
    } else {
        if dst.type.runtime_size == {
          case 1; dst.value_pointer.(*u8 ).* = s64_value.(u8 );
          case 2; dst.value_pointer.(*u16).* = s64_value.(u16);
          case 4; dst.value_pointer.(*u32).* = s64_value.(u32);
          case 8; dst.value_pointer.(*u64).* = s64_value.(u64);
        }
    }
}

int_to_float :: (dst: Any, src: Any) {
    assert(src.type.type == .INTEGER);
    assert(dst.type.type == .FLOAT);
    
    // TODO: provide some kind of range checking...
    
    f64_value: float64;
    if src.type.runtime_size == {
        case 1; f64_value = src.value_pointer.(*s8 ).*.(float64);
        case 2; f64_value = src.value_pointer.(*s16).*.(float64);
        case 4; f64_value = src.value_pointer.(*s32).*.(float64);
        case 8; f64_value = src.value_pointer.(*s64).*.(float64);
    }
    
    if dst.type.runtime_size == {
        case 4; dst.value_pointer.(*float32).* = f64_value.(float32);
        case 8; dst.value_pointer.(*float64).* = f64_value.(float64);
    }
}

// ========== String Stuff ==========

/*
    While I don't want to put too much parsing stuff in this module, I think it makes sense to have at least a few basics.
    To that end, a dynamic string_to_int and an improved version of Reflection.jai's set_value_from_string are provided.
*/

string_to_int :: (dst: Any, src: string, should_clamp := false) -> success: bool, remainder: string {
    str := src;
    
    negate := false;
    if str && str[0] == #char "-" {
        negate = true;
        advance(*str, 1);
    }
    
    base: u64 = 10;
    if str[0] == #char "0" && str.count >= 2 {
        if str[1] == {
          case #char "b"; 
            advance(*str, 2);
            base = 2;
            
          case #char "x"; 
            advance(*str, 2);
            base = 16;
            
          // case #char "h";
          //   advance(*str, 2);
          //   base = 16;
          //   is_hex_float = true;
          //   // verify that input string is exactly 4, 8, or 16 characters
        }
    }
    
    u64_value, ok, remainder := string_to_u64(str, base);
    if !ok {
        log("Error: failed to parse integer from '%'.", s);
        return false, remainder;
    }
    
    return range_check_and_store(dst, u64_value, negate, should_clamp), remainder;
}
#scope_export

set_value_from_string :: (dst: Any, text: string, should_copy_strings := true) -> bool {
    if text.count <= 0  return true; // empty string -> return true
    
    if dst.type.type == {
      case .INTEGER;
        // TODO: do we care that value may still get set in the error case if there is some remainder? Probably not...
        ok, remainder := string_to_int(dst, text);
        return ok && !remainder;
        
        
      case .FLOAT;
        value, ok, remainder := string_to_float64(text);
        if !ok || remainder  {
            return false;
        }
        if dst.type.runtime_size == {
          case 4; dst.value_pointer.(*float32).* = value.(float32);
          case 8; dst.value_pointer.(*float64).* = value;
        }
        return true;
        
        
      case .BOOL;
        if text == {
          case "true";   dst.value_pointer.(*bool).* = true;
          case "false";  dst.value_pointer.(*bool).* = false;
          case;
            log("Error: unable to parse bool value from string: '%'", text);
            return false;
        }
        return true;
        
        
      case .STRING;
        if should_copy_strings
            then dst.value_pointer.(*string).* = copy_string(text);
            else dst.value_pointer.(*string).* = text;
        return true;
        
        
      case .ENUM;
        // NOTE: The logic here is a bit weird since, whether we get the value by name or as an int,
        //       we want to OR in the parsed value for enum_flags instead of overwriting the existing value.
        
        enum_type := dst.type.(*Type_Info_Enum);  
        value := Any_Number.{ dst.type };
        success := false;
        
        for enum_type.names {
            if it == text {
                if enum_type.runtime_size == {
                    case 1; value.value_number.as_s\8 = enum_type.values[it_index].(s\8); 
                    case 2; value.value_number.as_s16 = enum_type.values[it_index].(s16); 
                    case 4; value.value_number.as_s32 = enum_type.values[it_index].(s32); 
                    case 8; value.value_number.as_s64 = enum_type.values[it_index].(s64); 
                }
                success = true;
                break;
            }
        }
        if !success {
            success = set_value_from_string(Any.{ enum_type.internal_type, *value.value_bytes }, text);
        }
        if !success {
            log("Error: failed to parse enum value from string '%'", text);
            return false;
        }
        
        if enum_type.enum_type_flags & .FLAGS {
            old_value := Any_Number.from(dst);
            value.value_number.as_u64 |= old_value.value_number.as_u64;
            memcpy_any(dst, to_any(*value));
        } else {
            memcpy_any(dst, to_any(*value));
        }
        return true;
    }

    log("Error: unsupported type in set_value_from_string()");
    return false;
}


// ========== Resolving Unions ==========

/*
    For use in cases where a union's type is determined by some tag in the parent struct.
    
    Some_Struct :: struct {
        union_type: enum  { ... };
        some_union: union { ... };
    }
    
    TODO: write a proc to generate the lookup Resolve_Union_By_Tag_Data for Tagged_Union
    
    I should document this because I forgot it and then had to figure out why I did it this way again...
    So the reason there's a union_ti passed in here is because we can't actually match on src type, since it may be some dynamically loaded type info
    So we want to match the dst union type to what is in the user data and then just verify that the src type is also a union
    In cases where we know we can use src type, we will just have to pass it as union_ti as well
*/
resolve_union_by_external_tag : Resolve_Union_Proc : (union_ti: *Type_Info, src: Any_With_Context, data: *void) -> *Type_Info_Struct_Member {
    user_data := data.(*Resolve_Union_By_Tag_Data);
    
    if union_ti != user_data.union_type  return null;
    if src.parent.value_pointer == null  return null;
    if data                     == null  return null;
    
    src_ti := src.data.type.(*Type_Info_Struct);
    assert(src_ti.type == .STRUCT);
    assert(src_ti.textual_flags & .UNION == .UNION);
    
    dst_tag_any := Any_Number.{ user_data.tag_type };
    
    src_tag_field := get_field(xx src.parent.type, user_data.tag_member_name);
    src_tag_any   := get_member_any(src.parent.value_pointer, src_tag_field);
    if !any_to_any(dst_tag_any, src_tag_any)  return null;
    
    src_member_name: string;
    for user_data.lookup {
        if it.tag_value == dst_tag_s64.value_number {
            src_member_name = it.member_name;
            break;
        }
    }
    if !src_member_name  return null;
    
    for *src_member: src_ti.members {
        if src_member.flags & .CONSTANT  continue;
        if src_member.name == src_member_name {
            return src_member;
        }
    }
    
    return null;
}

/*
    For when all union members share some common base type, and that base type contains the type tag for the union.
    
    Entity_Type :: enum { .KNIGHT; .GOBLIN; ... };
    Entity_Base :: struct {
        entity_type:    Entity_Type;
        health:         int;
        ...
    }
    Knight :: struct { 
        using #as base: Entity_Base;
        ...
    }
    Goblin :: struct { 
        using #as base: Goblin;
        ...
    }
    Entity_Union :: union {
        using #as base: Entity_Base;
        knight:         Knight;
        goblin:         Goblin;
        ...
    }
    
    resolve_entity_union_data := Resolve_Union_By_Tag_Data.{ "type", type_info(Entity_Union), type_info(Entity_Type), .[
        .{ #run Number_Union.from(Entity_Type.KNIGHT),  "knight" },
        .{ #run Number_Union.from(Entity_Type.GOBLIN),  "goblin" },
    ]};
    array_add(*context.conversion_settings.get_union_type_procs, .{ resolve_union_by_tag, resolve_entity_union_data });
    
    
    The need to use a #run on Number_Union.from() is less than ideal, but I have more confidence after switching 
        to using the Number_Union that the code is correct and won't fail for enums with smaller backing integer sizes.
    And the rest of this is also not really ideal anyhow, so I'm not gonna worry about making it 2% nicer 
        until I figure out a way to make the 98% of union remapping less clunky and horrible.
*/
resolve_union_by_internal_tag : Resolve_Union_Proc : (union_ti: *Type_Info, src: Any_With_Context, data: *void) -> *Type_Info_Struct_Member {
    user_data := data.(*Resolve_Union_By_Tag_Data);
    
    if union_ti != user_data.union_type  return null;
    if data == null  return null;
    
    src_ti := src.data.type.(*Type_Info_Struct);
    assert(src_ti.type == .STRUCT);
    assert(src_ti.textual_flags & .UNION == .UNION);
    
    dst_tag_any := Any_Number.{ type = user_data.tag_type };
    
    src_tag_field := get_field(xx src.data.type, user_data.tag_member_name);
    src_tag_any   := get_member_any(src.data.value_pointer, src_tag_field);
    if !any_to_any(dst_tag_any, src_tag_any)  return null;
    
    src_member_name: string;
    for user_data.lookup {
        if it.tag_value == dst_tag_any.value {
            src_member_name = it.member_name;
            break;
        }
    }
    if !src_member_name  return null;
    
    for *src_member: src_ti.members {
        if src_member.flags & .CONSTANT  continue;
        if src_member.name == src_member_name {
            return src_member;
        }
    }
    
    return null;
}

Resolve_Union_By_Tag_Data :: struct {
    tag_member_name:    string;
    tag_type:           *Type_Info_Enum;
    union_type:         *Type_Info;
    lookup:             [] struct { tag_value: Number_Union; member_name: string; };
}



#scope_module

#import "Basic";
#import "Reflection";
#import "Math";

// As usual, I dislike that I have a dependency on my utils module here, but for now IIWII.
#import "Utils";

