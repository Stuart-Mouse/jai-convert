

## TODO

### tests.jai

move numeric conversions tests from GON
    int_to_int needs testing for valid ranges
    float_to_int needs testing of rounding modes
    enum_to_enum of course needs a test
        should probably test explicitly sized enum/enum_flags with u64 values greater than s64 max
    

### example.jai

provide examples of various types of conversions, with both passing and failing cases


### Documentation

Need to document the conversion settings much better, and update the readme for that
    document how conversion settings should be pushed in the context (since it's by pointer, need valid storage duration for settings struct)


### Conversion Settings

verify and clarify functionality of conversion settings

### Built-In Support for Tagged_Union





## Implementation Notes

Everything below here is gonna just be really messy notes



### general considerations


how useful are most of the options in allowed conversions?
    most of the time user jsut wants .ALL or not to od the allocating ones
    probably fine to leave it more granular, but we really do just need ot figure out the allocator stuff for both this and GON
    

should we really use arrays of callbacks for union resolution and user remappings?
    if we do something like IO data, maybe we can clean these up for things that actually pertain to specific types, 
    and then we can provide just a single callback proc on the context struct for actual special case handling


the current union situation is really gross
    but then again for remapping from an Any where we don't have the concrete type to cast to means it's just gonna be kinda gross no matter what


### remap_array 


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



### pointer stuff

pointer recasting considerations are a bit different than in the dat packer, since we have to think about both src and dst

maybe we want to recast both pointers up to some common base type
maybe we want to cast just one or the other 

need to know 


also procedure pointers
    probably just leave this entirely up to user, have not even though of a need for this other than in combination with data packer
    but for that use case I will probably just do some local data pointer thing and skip Convert.jai entirely
    
    
