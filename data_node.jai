/*
    The original purpose of the Data_Node struct was just to wrap an Any
    to contain some infomration about where the data is located within some larger data structure.
    
    The main benefit of this is being able to provide something like a stack trace so that when we have some error 
    deep down in code doing reflection stuff, we can see the context in which the error ocurred.
    
    I am now working on extending this structure to support many of the other reflection functionality from my utils module.
    Perhaps this structure will end up being a good all-in-one replacement for the Any for complex reflection code.
    
    TODO:
        From a design standpoint, I need to consider whether Data_Node should be this union-y type or whether we should have 
        a more pointer-cast-based layout like type info.
        The main benefit of doing the latter approach would be that we can put a using on member info, or on type-specific data.
        But there's a bit of extra complexity here in that we have both type and kind to consider, and they're totally orthogonal.
        
        Accessing the type-specific info through a using is more useful than the member info.
        So maybe we have like, Data_Node_Array, Data_Node_Struct, etc., and then just have the context union still be accessed without a using.
    
    
    TODO: for struct member, do we need some kind of flag to indicate that some member was retrieved by a using?
          or should we force the creation of an additional data node so that we can see the using'd member in the trace?
          (if we do the second option, we will have to do some kind of temp allocations...)
*/

Data_Node :: struct {
    type:           *Type_Info;
    value_pointer:  *void;
    parent:         *Data_Node;
    
    Context :: union kind: Kind {
        name:               string;                     // NO_CONTEXT
        member_info:        *Type_Info_Struct_Member;   // STRUCT_MEMBER
        _:                  *Type_Info_Struct_Member;   // UNION_MEMBER
        index:              int;                        // ARRAY_INDEX
        _:                  void;                       // DEREFERENCE
        
        Kind :: enum { NO_CONTEXT :: 0; STRUCT_MEMBER; UNION_MEMBER; ARRAY_INDEX; DEREFERENCE; };
    }
    
    using _context: Context;
    
    // TODO: maybe rename to as_any?
    #overlay(type) any: Any; // because we can't `using` an Any 
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
      case .UNION_MEMBER;
        print(builder, ".%", node.member_info.name);
      case .ARRAY_INDEX;
        print(builder, "[%]", node.index);
      case .DEREFERENCE;
        append(builder, ".*");
    }
}

// NOTE: macros are used to return a *Data_Node like this, since in most cases we want to allocate the Data_Node on the stack.
//       maybe in the future I will add some alternate procs that return something allocated with temp

// TODO: get_member should probably not act recursively here, since we then don't know the actual offset_in_bytes of the member if there was a using involved.
get_struct_member :: (data_node: *Data_Node, member_name: string) -> *Data_Node #expand {
    ok, any, member_info := get_struct_member(data_node.any, member_name);
    if !ok  return null;
    
    member_node := Data_Node.{ 
        kind        = .STRUCT_MEMBER, 
        parent      = data_node, 
        any         = any, 
        member_info = member_info,
    };
    return *member_node;
}

get_valid_union_member :: (data_node: *Data_Node) -> *Data_Node #expand {
    any, member_info := get_valid_union_member(data_node.any);
    if any.type == null  return null;
    
    member_node := Data_Node.{ 
        kind        = .UNION_MEMBER, 
        parent      = data_node, 
        any         = any, 
        member_info = member_info,
    };
    return *member_node;
}


// For expansions
// NOTE: data node iterator is always provided by pointer, not by value

/*
    NOTE: 
    The for_flags are maybe a bit unintuitive here, but I wanted the default to be the most common use case (iterating only non-constant, non-overlay members).
    
    The * now means 'include constant members'.
        Perhaps this is counter-intuitive, and it should indicate to exclude constants.
        But then we have a weird asymmetry in that one flag means 'include' and the other means 'exclude'.
        
    The < now means 'include #overlay members'.
        This one perhaps makes a bit more sense, because including overlay members means we sometimes jump backwards in the struct.
        
    Also of note, this iterator asserts that you haven't passed it a union, since iterating the members of a union is basically nonsense.
*/
members :: (parent: *Data_Node, body: Code, flags: For_Flags) #expand {
    ti_struct := parent.type.(*Type_Info_Struct);
    assert(ti_struct.type == .STRUCT);
    assert(ti_struct.textual_flags & .UNION == 0);
    
    member_node: Data_Node;
    `it := *member_node;
    
    // TODO: it_index here is not very meaningful...
    for *it_info, `it_index: ti_struct.members {
        #if flags & .POINTER == 0 {
            if it_info.flags & .CONSTANT  continue;
        }
        #if flags & .REVERSE == 0 {
            if it_info.flags & .OVERLAY  continue;
        }
        
        member_node.type          = it_info.type;
        member_node.value_pointer = parent.value_pointer + it_info.offset_in_bytes;
        member_node.member_info   = it_info;
        
        #insert body;
    }
}

// NOTE: for_flags are ignored here.
elements :: (parent: *Data_Node, body: Code, flags: For_Flags) #expand {
    array_info := parent.type.(*Type_Info_Array);
    assert(array_info.type == .ARRAY);
    assert(for_flags == xx 0);
    
    array_count, array_data := get_array_count_and_data(parent.value_pointer, array_info);
    element_node := Data_Node.{ 
        kind          = .STRUCT_MEMBER, 
        parent        = parent, 
        type          = it_info.type,
        value_pointer = array_data,
        member_info   = it_info,
    };
    
    `it       := *element_node;
    `it_index := 0;
    while it_index < array_count {
        defer {
            it.value_pointer += array_info.element_type.runtime_size;
            it.index += 1;
            it_index += 1;
        }
        #insert body;
    }
}
