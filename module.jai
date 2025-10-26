
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
    allowed_conversions = .ALL,
    float_rounding_mode = .TRUNCATE,
};

#add_context conversion_settings: *Conversion_Settings = *default_conversion_settings; // by pointer so that user can switch out conversion settings trivially

Float_Rounding_Mode :: enum { TRUNCATE; FLOOR; CEILING; /*NEAREST;*/ };

Conversion_Settings :: struct {
    allowed_conversions:    Conversion_Types;
    float_rounding_mode:    Float_Rounding_Mode;
    
    get_union_type_procs:   [..] struct { proc: Resolve_Union_Proc;  data: *void; };
    user_remap_procs:       [..] struct { proc: User_Remap_Proc;     data: *void; };
    
    // should this just be a flag in Conversion_Types? Or should we make a separate flags member for things like this?
    // or, maybe we just change the function of INT_NARROWING to permit clamping?   I dunno...
    clamp_int_to_int:       bool;
    
    // TODO: maybe add something like IO Data from GON so user can override certain behavior without the need for user remap procs.
}

// Union types are resolved by returning the type info struct member for the union member that is valid.
// The union_info parameter is used during remapping to pass the dst union's type info, since we usually want to match on this rather than on the src type.
Resolve_Union_Proc :: #type (union_info: *Type_Info, data_node: *Data_Node, user_data: *void) -> *Type_Info_Struct_Member;

User_Remap_Proc_Result :: enum { ERROR; UNHANDLED; HANDLED; }
User_Remap_Proc :: #type (dst: Any, src: Any, user_data: *void) -> User_Remap_Proc_Result;


#scope_file
is_allowed :: inline (conversion_type: Conversion_Types) -> bool { 
    return context.conversion_settings.allowed_conversions & conversion_type == conversion_type;
}

log_disallowed_conversion :: inline (conversion: Conversion_Types, proc_name: string, loc := #caller_location) {
    log("Error: disallowed conversion % in % (line: %)", conversion, proc_name, loc.line_number);
}

log_unsupported_conversion :: inline (conversion: Conversion_Types, proc_name: string, loc := #caller_location) {
    log("Error: unsupported conversion % in % (line: %)", conversion, proc_name, loc.line_number);
}
#scope_export


// TODO: maybe disambiguate struct member and union member
Data_Node :: struct {
    any:        Any;
    parent:     *Data_Node;
    
    Kind :: enum { NO_CONTEXT; STRUCT_MEMBER; ARRAY_INDEX; DEREFERENCE; };
    kind:   Kind;
    union {
        name:           string; // used when kind is .ROOT
        member_info:    *Type_Info_Struct_Member;
        index:          int;
    }
    
    // NOTE: this is because we can't 'using' an Any
    #place any;
        type:           *Type_Info;
        value_pointer:  *void;
}

format_data_trace :: (node: *Data_Node) -> string {
    builder: String_Builder;
    init_string_builder(*builder);
    format_data_trace(*builder, node);
    return builder_to_string(*builder);
}

format_data_trace :: (builder: *String_Builder, node: *Data_Node) {
    if node.parent != null {
        format_data_trace(builder, node.parent);
    }
    
    if #complete node.kind == {
      case .NO_CONTEXT;
        append(builder, node.name);
      case .STRUCT_MEMBER;
        print(builder, ".%", node.member_info.name);
      case .ARRAY_INDEX;
        print(builder, "[%]", node.index);
      case .DEREFERENCE;
        append(builder, ".*");
    }
}

// push_data_trace_node :: (packer: *Data_Packer, node: Data_Node) #expand {
//     node.parent = packer.data_trace_node;
//     packer.data_trace_node = *node;
//     `defer packer.data_trace_node = node.parent;
// }

// push_data_trace_struct_member :: (packer: *Data_Packer, member_info: *Type_Info_Struct_Member) #expand {
//     node := Data_Node.{ kind = .STRUCT_MEMBER, member_info = member_info };
//     node.parent = packer.data_trace_node;
//     packer.data_trace_node = *node;
//     `defer packer.data_trace_node = node.parent;
// }

// push_data_trace_array_index :: (packer: *Data_Packer, index: int) #expand {
//     node := Data_Node.{ kind = .ARRAY_INDEX, index = index };
//     node.parent = packer.data_trace_node;
//     packer.data_trace_node = *node;
//     `defer packer.data_trace_node = node.parent;
// }

// push_data_trace_dereference :: (packer: *Data_Packer) #expand {
//     node := Data_Node.{ kind = .DEREFERENCE };
//     node.parent = packer.data_trace_node;
//     packer.data_trace_node = *node;
//     `defer packer.data_trace_node = node.parent;
// }


// ========== Remapping Procedures ==========

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
any_to_any :: (dst: Any, src: Any) -> bool {
    dst_node := Data_Node.{ kind = .NO_CONTEXT, name = "dst", any = dst };
    src_node := Data_Node.{ kind = .NO_CONTEXT, name = "src", any = src };
    return remap_data(*dst_node, *src_node);
}

remap_data :: (dst_node: *Data_Node, src_node: *Data_Node) -> bool {
    for context.conversion_settings.user_remap_procs {
        if it.proc(dst_node.any, src_node.any, it.data) == {
          case .UNHANDLED;  // no op
          case .HANDLED;    return true;
          case .ERROR;      return false;
        }
    }
    
    // log("=====");
    // log("dst: %", format_data_trace(dst_node));
    // log("src: %", format_data_trace(src_node));
    
    // copy data nodes so that we can modify type if need be
    _dst_node := dst_node.*;
    _src_node := src_node.*;
    
    // TODO: we should have some proper get_base_type proc that we use for cases like this
    // NOTE: the loops are there because I assumed variants could be nested, but maybe this is not the case..?
    while _dst_node.type.type == .VARIANT { _dst_node.type = _dst_node.type.(*Type_Info_Variant).variant_of; }
    while _src_node.type.type == .VARIANT { _src_node.type = _src_node.type.(*Type_Info_Variant).variant_of; }
    
    if _dst_node.type.type == {
      case .STRING;
        if _src_node.type.type == .STRING {
            // TODO: we would like to have an option as to whether this should copy
            _dst_node.value_pointer.(*string).* = copy_string(_src_node.value_pointer.(*string).*);
            return true;
        }
        if is_allowed(.ARRAY_TO_STRING) {
            if _src_node.type.type == .ARRAY {
                // cannot just compare array element type to type_info(u8), since src.type could be dynamically loaded
                // so instead we assume that any type with runtime size of 1 is probably u8... 
                array_info := _src_node.type.(*Type_Info_Array);
                if array_info.element_type.runtime_size == 1  return false; 
                if array_info.array_type == .FIXED {
                    dst_string := _dst_node.value_pointer.(*string);
                    memcpy(dst_string.data, _src_node.value_pointer, array_info.array_count);
                    dst_string.count = array_info.array_count;
                } else {
                    // TODO: we would like to have an option as to whether this should copy
                    _dst_node.value_pointer.(*string).* = copy_string(_src_node.value_pointer.(*string).*);
                }
                return true;
            }
        }
        return false;
        
      case .BOOL;
        return any_to_bool(_dst_node.any, _src_node.any);
        
      case .INTEGER;
        return any_to_int(_dst_node.any, _src_node.any);
        
      case .FLOAT;
        return any_to_float(_dst_node.any, _src_node.any);
        
      case .ENUM;
        return remap_enum(_dst_node.any, _src_node.any);
        
      case .STRUCT;
        return remap_struct(*_dst_node, *_src_node);
        
      case .ARRAY;
        return remap_array(*_dst_node, *_src_node);
        
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
            if _src_node.value_pointer.(**void).* == null  return true;
            
            src_dereferenced := dereference_any_pointer(_src_node.any);
            src_dereferenced_node := Data_Node.{ kind = .DEREFERENCE, any = src_dereferenced, parent = *_src_node };
            
            dst_dereferenced := dereference_any_pointer(_dst_node.any);
            dst_dereferenced_node := Data_Node.{ kind = .DEREFERENCE, any = dst_dereferenced, parent = *_dst_node };
            
            // allocate dst value if need be and set the dst pointers according
            if dst_dereferenced_node.value_pointer == null {
                dst_dereferenced_node.value_pointer = Dynamic_New(dst_dereferenced_node.type);
                _dst_node.value_pointer.(**void).*  = dst_dereferenced_node.value_pointer;
            }
            
            // TODO: if this fails, we should probably deallocate the dynamic_new'd item?
            return remap_data(*dst_dereferenced_node, *src_dereferenced_node);
        }
        
        // only attempt shallow copy if remapping through pointer is not allowed
        if is_allowed(.SHALLOW_COPY_POINTER) {
            // TODO: make this more powerful by allowing recasting of pointers to common type.
            // e.g.: dst is *Type_Info and src is *Type_Info_Struct, should be allowed
            if _src_node.type == _dst_node.type {
                _dst_node.value_pointer.(**void).* = _src_node.value_pointer.(**void).*;
            }
            return true;
        }
        
        // I guess this one will just silently 'fail' for now?
        // Doesn't feel right to throw an error just because user may not want to do pointers...
        return true;
    }
    
    return true;
}

remap_struct :: (dst_node: *Data_Node, src_node: *Data_Node) -> bool {
    assert(dst_node.type.type == .STRUCT);
    if src_node.type.type != .STRUCT  return false;
    
    if is_union_type(dst_node.type) {
        return remap_union(dst_node, src_node);
    }
    
    if !is_allowed(.REMAP_STRUCT) {
        log_disallowed_conversion(.REMAP_STRUCT, "remap_struct");
        return false;
    }
    
    iterate_struct_members(dst_node.any, .SKIP_CONSTANT | .SKIP_PLACE, #code {
        // TODO: I am probably not properly handling the case where a using is on a union
        dst_member_node := Data_Node.{ kind = .STRUCT_MEMBER, member_info = it_info, any = it, parent = dst_node };
        
        // NOTE: get_member calls get_field, which searches recursively through usings
        //       maybe we should make this a parameter so that we can toggle this behavior
        found, src_member, src_member_info := get_member(src_node.any, it_info.name);
        if !found {
            /*
                I'm not sure if this could have unintended side-effects,
                but the idea here is that if we can't find a match for a member that has a using on it, 
                then we will fallback to trying to look for the members of the using'd member in the top level of src struct
                this should allow the remapper to catch cases where you factor out some member into a another struct and then 'using' that new struct in the old struct 
            */
            if it_info.flags & .USING {
                log("remapping src to using'd member % (%)", it_info.name, as_type(it_info.type));
                if !remap_data(*dst_member_node, src_node)  {
                    log("Error: failed while remapping struct member %!", it_info.name);
                    return false;
                }
            }
            continue;
        }
        if src_member_info.flags & .CONSTANT  continue;
        
        src_member_node := Data_Node.{ kind = .STRUCT_MEMBER, member_info = src_member_info, any = src_member, parent = src_node };
        
        if is_union_type(dst_member_node.type) {
            if !remap_union(*dst_member_node, *src_member_node) {
                log("Error: failed while remapping struct member (union) %!", it_info.name);
                return false;
            }
        } else {
            // TODO: what if src is union, but dst is not?
            if !remap_data(*dst_member_node, *src_member_node)  {
                log("Error: failed while remapping struct member %!", it_info.name);
                return false;
            }
        }
    });
    
    return true;
}

/*
    NOTE: 
    On its own, remap_union cannot actually figure out which union member is valid. 
    For that, a user callback must be provided in context.conversion_settings.get_union_type_procs.
    See union.jai for some relevant helper procs and examples.
    
    // TODO: dst really should be an Any_With_Context as well so that the resolve_union_proc can set an external tag accordingly (if need be).
             (technically, this doesn't need to be the case as an external tag should already be set by remapping the parent struct, but it seems wise to set the value explicitly...)
*/
remap_union :: (dst_node: *Data_Node, src_node: *Data_Node) -> bool {
    settings := context.conversion_settings;
    
    dst_struct_info := dst_node.type.(*Type_Info_Struct);
    assert(is_union_type(dst_struct_info));
    
    if !is_allowed(.REMAP_UNION) {
        log_unsupported_conversion(.REMAP_UNION, "remap_struct");
        return false;
    }
    
    // NOTE: this feature is not usable when remapping from dynamically generated type infos to native type infos, as we do in data packer, since the type infos muct be an exact match
    if !is_union_type(src_node.type) {
        if union_contains_type(dst_struct_info, src_node.type) {
            // TODO: should we just shallowly memcpy since types match exactly?
            //       the fact that I have to ask this means allocations are too confusing right now...
            return any_to_any(Any.{ src_node.type, dst_node.value_pointer }, src_node.any);
        }
        log("Error: unable to remap type % to %. src type is not a member of dst union.", as_type(src_node.type), as_type(dst_node.type));
        return false;
    }
    
    src_member_info: *Type_Info_Struct_Member;
    for settings.get_union_type_procs {
        src_member_info = it.proc(dst_node.type, src_node, it.data);
        if src_member_info  break;
    }
    if !src_member_info  {
        // log("Warning: failed to resolve union member in remap_struct.");
        return true;
    }
    assert(src_member_info.flags & .CONSTANT == 0);
    
    src_member := get_member(src_node.any, src_member_info);
    dst_member_found, dst_member := get_member(dst_node.any, src_member_info.name);
    
    if dst_member_found {
        return any_to_any(dst_member, src_member);
    }
    
    // log that dst member was not found?
    return true; // TODO?
}


// TODO: consider how allocators / allocations should work and what settings to implement
// Shallow copy vs deep copy options?
remap_array :: (dst_node: *Data_Node, src_node: *Data_Node) -> bool {
    dst_array := Any_Array.from(dst_node.any);  // asserts that dst is actually an array type 
    
    // remap string to array of u8
    if src_node.type.type == .STRING {
        if !is_allowed(.STRING_TO_ARRAY) {
            log_disallowed_conversion(.STRING_TO_ARRAY, "remap_array");
            return false;
        }
        
        if dst_array.element_type.runtime_size != 1 {
            log("Error: cannot convert from string to %.", as_type(dst_array.array_info));
        }
        
        src_string_pointer := src_node.value_pointer.(*string);
        if dst_array.array_type == {
          case .FIXED;
            count := min(dst_array.array_count, src_string_pointer.count);
            memcpy(dst_array.value_pointer, src_string_pointer.data, count);
          case .VIEW;
            // TODO: this just overwrites the existing value without checking... perhaps we should not do that...
            // TODO: we would like to have an option as to whether this should copy
            dst_array.value_pointer.(*string).* = copy_string(src_string_pointer.*);
          case .RESIZABLE;
            array := dst_array.value_pointer.(*[..]u8);
            array_add(array, ..src_string_pointer.(*[]u8).*);
        }
        return true;
    }
    
    
    // src_array has to be constructed manually, since src may not actually be an array in the first place
    // we also create a Type_Info_Array on the stack here so that we can just make up a new type if need be
    src_array_info: Type_Info_Array;
    src_array := Any_Array.{
        array_info    = *src_array_info,
        value_pointer = src_node.value_pointer,
    };
    
    conversion_type := Conversion_Types.UNKNOWN_CONVERSION;
    
    if src_node.type.type == .ARRAY {
        // if source type is actually an array, just point at that instead of the made up type
        src_array.array_info = src_node.type.(*Type_Info_Array);
    } else {
        // for single-to-array, we treat the one element T as a [1] T
        conversion_type = .SINGLE_TO_ARRAY;
        src_array_info = .{
            type         = .ARRAY,
            runtime_size = src_node.type.runtime_size,
            element_type = src_node.type,
            array_type   = .FIXED,
            array_count  = 1,
        };
    }
    src_count, src_data := get_count_and_data(src_array);
    
    
    // we OR in the array conversion type since we may have something like `SINGLE_TO_ARRAY | ARRAY_FIXED_TO_VARIABLE` if we are going from `T` to `[] T`
    if dst_array.array_type == {
      case .FIXED;
        if src_array.array_type == {
          case .FIXED; 
            // TODO: we should probably notify the user if fixed array gets widened or truncated
            if      src_count > dst_array.array_count then conversion_type |= .TRUNCATE_FIXED_ARRAY;
            else if src_count < dst_array.array_count then conversion_type |= .WIDEN_FIXED_ARRAY;
            else    conversion_type |= .NO_CONVERSION_REQUIRED;
          case .VIEW;       conversion_type |= .ARRAY_VARIABLE_TO_FIXED;
          case .RESIZABLE;  conversion_type |= .ARRAY_VARIABLE_TO_FIXED;
        }
      case .VIEW;
        if src_array.array_type == {
          case .FIXED;      conversion_type |= .ARRAY_FIXED_TO_VARIABLE;
          case .VIEW;       conversion_type |= .NO_CONVERSION_REQUIRED;
          case .RESIZABLE;  conversion_type |= .ARRAY_RESIZABLE_TO_VIEW;
        }
      case .RESIZABLE;
        if src_array.array_type == {
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
    
    
    // maybe allocate for VIEW and RESIZABLE
    if dst_array.array_type != .FIXED {
        raw_array := dst_array.value_pointer.(*Resizable_Array);
        
        // TODO: give the user the ability to set allocators for array views' data
        
        // NOTE: we only allocate new data for the array view if it is currently null, 
        //       otherwise, we assume that user pre-allocated a set amount of space.
        if raw_array.data == null {
            assert(raw_array.count == 0, "dst_count was %", raw_array.count);
            resize(dst_array, src_count);
            memset(raw_array.data, 0, src_count * dst_array.element_type.runtime_size);
        } else {
            log("Warning: array view data was non-null in remap_array: data %, count %", raw_array.data, raw_array.count);
        }
    }
    
    dst_count, dst_data := get_count_and_data(dst_array);
    
    if dst_data == null || dst_count == 0 {
        log("Error: dst array was null or empty in remap_array.");
        print_stack_trace(context.stack_trace, to_standard_error = false);
        return false;
    }
    
    
    
    // TODO: probably log some warning when array counts don't match?
    if src_count != dst_count {
        log("Warning: src and dst array count do not match! % vs %", src_count, dst_count);
    }
    
    min_count   := min(src_count, dst_count);
    src_element := Any.{ src_array.element_type, src_data };
    dst_element := Any.{ dst_array.element_type, dst_data };
    
    for 0..min_count-1 {
        dst_element_node := Data_Node.{ kind = .ARRAY_INDEX, any = dst_element, parent = dst_node };
        src_element_node := Data_Node.{ kind = .ARRAY_INDEX, any = src_element, parent = src_node };
        if !remap_data(*dst_element_node, *src_element_node)  return false;
        src_element.value_pointer += src_array.element_type.runtime_size;
        dst_element.value_pointer += dst_array.element_type.runtime_size;
    }
    
    return true;
}

// check if we are allowed do it by name, else do it by value
remap_enum :: (dst: Any, src: Any) -> bool { 
    settings := context.conversion_settings;

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
            
            int_to_enum(dst, dst_s64, settings.clamp_int_to_int);
            return true;
        }
        else {
            src_s64: s64;
            enum_to_int(src_s64, src, settings.clamp_int_to_int);
            
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
                        int_to_enum(dst, dst_ti.values[it_index], settings.clamp_int_to_int);
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
    
    enum_to_enum(dst, src, settings.clamp_int_to_int);
    return true;
}

any_to_int :: (dst: Any, src: Any) -> bool {
    settings := context.conversion_settings;
    
    assert(dst.type.type == .INTEGER);
    
    if src.type.type == {
      case .ENUM; 
        conversion := Conversion_Types.ENUM_TO_INT;
        if is_narrowing_int(xx dst.type, src.type.(*Type_Info_Enum).internal_type)  conversion |= .INT_NARROWING;
        if !is_allowed(conversion) {
            log_disallowed_conversion(conversion, "any_to_int");
            return false;
        }
        enum_to_int(dst, src, settings.clamp_int_to_int);
        return true;
        
      case .INTEGER;
        conversion := Conversion_Types.INT_TO_INT;
        if is_narrowing_int(xx dst.type, xx src.type)  conversion |= .INT_NARROWING;
        if !is_allowed(conversion) {
            log_disallowed_conversion(conversion, "any_to_int");
            return false;
        }
        return int_to_int(dst, src, settings.clamp_int_to_int);
        
      case .FLOAT; 
        conversion := Conversion_Types.FLOAT_TO_INT;
        if !is_allowed(conversion) {
            log_disallowed_conversion(conversion, "any_to_int");
            return false;
        }
        float_to_int(dst, src, settings.float_rounding_mode);
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
        if src.type.runtime_size == {
            case 1; dst.value_pointer.(*bool).* = src.value_pointer.(*u\8).* != 0;
            case 2; dst.value_pointer.(*bool).* = src.value_pointer.(*u16).* != 0;
            case 4; dst.value_pointer.(*bool).* = src.value_pointer.(*u32).* != 0;
            case 8; dst.value_pointer.(*bool).* = src.value_pointer.(*u64).* != 0;
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
                log_clamped_value_warning(abs_value_u64, true, info, vmin, vmax, abs_vmin, abs_vmin != 0);
                abs_value_u64 = abs_vmin;
            } else {
                log_range_error(abs_value_u64, true, info, vmin, vmax);
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
                log_clamped_value_warning(abs_value_u64, false, info, vmin, vmax, vmax, false);
                abs_value_u64 = vmax.(u64);
            } else {
                log_range_error(abs_value_u64, false, info, vmin, vmax);
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
log_clamped_value_warning :: (abs_value: u64, negative: bool, type: *Type_Info, min: s64, max: u64, abs_clamped: u64, clamped_negative: bool) {
    log("Warning: value of %0% cannot be assigned to type %. (Valid range is [% - %]) Clamping to %0% as a fallback.", ifx negative then "-", abs_value, as_type(type), min, max, ifx clamped_negative then "-", abs_clamped);
}
log_range_error :: (abs_value: u64, negative: bool, type: *Type_Info, min: s64, max: u64) {
    log("Error: value of %0% cannot be assigned to type %. (Valid range is [% - %].)", ifx negative then "-", abs_value, as_type(type), min, max);
}

#scope_export



enum_as_int :: inline (src: Any) -> Any {
    assert(src.type.type == .ENUM);
    return Any.{ src.type.(*Type_Info_Enum).internal_type, src.value_pointer };
}

// for convenience
enum_to_enum  :: inline (dst: Any, src: Any, should_clamp := false) { 
    int_to_int(enum_as_int(dst), enum_as_int(src), should_clamp); 
}
enum_to_int   :: inline (dst: Any, src: Any, should_clamp := false) { 
    int_to_int(dst, enum_as_int(src), should_clamp); 
}
int_to_enum   :: inline (dst: Any, src: Any, should_clamp := false) { 
    int_to_int(enum_as_int(dst), src, should_clamp); 
}
enum_to_float :: inline (dst: Any, src: Any) { 
    int_to_float(dst, enum_as_int(src)); 
}
float_to_enum :: inline (dst: Any, src: Any, rounding_mode := Float_Rounding_Mode.TRUNCATE) { 
    float_to_int(enum_as_int(dst), src, rounding_mode);
}


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


float_to_int :: (dst: Any, src: Any, rounding_mode := Float_Rounding_Mode.TRUNCATE) {
    assert(src.type.type == .FLOAT);
    assert(dst.type.type == .INTEGER);
    
    s64_value: s64;
    if rounding_mode == {
      case .TRUNCATE;
        if src.type.runtime_size == {
            case 4; s64_value = src.value_pointer.(*float32).*.(s64);
            case 8; s64_value = src.value_pointer.(*float64).*.(s64);
        }
      case .FLOOR;
        if src.type.runtime_size == {
            case 4; s64_value = floor(src.value_pointer.(*float32).*).(s64);
            case 8; s64_value = floor(src.value_pointer.(*float64).*).(s64);
        }
      case .CEILING;
        if src.type.runtime_size == {
            case 4; s64_value = ceil(src.value_pointer.(*float32).*).(s64);
            case 8; s64_value = ceil(src.value_pointer.(*float64).*).(s64);
        }
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
        log("Error: failed to parse integer from '%'.", str);
        return false, remainder;
    }
    
    return range_check_and_store(dst, u64_value, negate, should_clamp), remainder;
}


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
        new_value := Any_Number.{ type = enum_type };
        success := false;
        
        for enum_type.names {
            if it == text {
                if enum_type.runtime_size == {
                    case 1; new_value.as_s\8 = enum_type.values[it_index].(s\8); 
                    case 2; new_value.as_s16 = enum_type.values[it_index].(s16); 
                    case 4; new_value.as_s32 = enum_type.values[it_index].(s32); 
                    case 8; new_value.as_s64 = enum_type.values[it_index].(s64); 
                }
                success = true;
                break;
            }
        }
        if !success {
            success = set_value_from_string(Any.{ enum_type.internal_type, *new_value.value }, text);
        }
        if !success {
            log("Error: failed to parse enum value from string '%'", text);
            return false;
        }
        
        if enum_type.enum_type_flags & .FLAGS {
            old_value := Any_Number.from(dst);
            new_value.as_u64 |= old_value.as_u64;
            memcpy_any(dst, to_any(*new_value));
        } else {
            memcpy_any(dst, to_any(*new_value));
        }
        return true;
    }

    log("Error: unsupported type in set_value_from_string()");
    return false;
}


#scope_module

#load "union.jai";

#import "Basic";
#import "Reflection";
#import "Math";

// As usual, I dislike that I have a dependency on my utils module here, but for now IIWII.
#import "Utils";

