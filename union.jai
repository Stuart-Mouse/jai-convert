
/*
    For use in cases where a union's type is determined by some tag in the parent struct.
    
    Some_Struct :: struct {
        union_type: enum  { ... };
        some_union: union { ... };
    }
    
    TODO: write a proc to generate the lookup Resolve_Union_By_Tag_Data for Tagged_Union
    
    I should document this because I forgot it and then had to figure out why I did it this way again...
    So the reason there's a union_info passed in here is because we can't actually match on src type, since it may be some dynamically loaded type info
    So we want to match the dst union type to what is in the user data and then just verify that the src type is also a union
    In cases where we know we can use src type, we will just have to pass it as union_info as well
*/
resolve_union_by_external_tag : Resolve_Union_Proc : (union_info: *Type_Info, src: Any_With_Context, data: *void) -> *Type_Info_Struct_Member {
    user_data := data.(*Resolve_Union_By_Tag_Data);
    
    if union_info != user_data.union_type  return null;
    if src.parent.value_pointer == null  return null;
    if data                     == null  return null;
    
    src_struct_info := src.data.type.(*Type_Info_Struct);
    assert(is_union_type(src_struct_info));
    
    dst_tag := Any_Number.{ user_data.tag_type };
    
    src_tag_field := get_field(xx src.parent.type, user_data.tag_member_name);
    src_tag_any   := get_member_any(src.parent.value_pointer, src_tag_field);
    if !remap_enum(to_any(*dst_tag), src_tag_any)  return null;
    
    src_member_name: string;
    for user_data.lookup {
        if it.tag_value == dst_tag.value {
            src_member_name = it.member_name;
            break;
        }
    }
    if !src_member_name  return null;
    
    for *src_struct_info.members {
        if it.flags & .CONSTANT  continue;
        if it.name == src_member_name {
            return it;
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
resolve_union_by_internal_tag : Resolve_Union_Proc : (union_info: *Type_Info, src: Any_With_Context, data: *void) -> *Type_Info_Struct_Member {
    user_data := data.(*Resolve_Union_By_Tag_Data);
    
    if union_info != user_data.union_type  return null;
    if data == null  return null;
    
    src_struct_info := src.type.(*Type_Info_Struct);
    assert(is_union_type(src_struct_info));
    
    dst_tag := Any_Number.{ type = user_data.tag_type };
    
    src_tag_field := get_field(xx src.type, user_data.tag_member_name);
    src_tag_any   := get_member_any(src.value_pointer, src_tag_field);
    if !remap_enum(to_any(*dst_tag), src_tag_any)  return null;
    
    src_member_name: string;
    for user_data.lookup {
        if it.tag_value == dst_tag.value {
            src_member_name = it.member_name;
            break;
        }
    }
    if !src_member_name  return null;
    
    for *src_struct_info.members {
        if it.flags & .CONSTANT  continue;
        if it.name == src_member_name {
            return it;
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
