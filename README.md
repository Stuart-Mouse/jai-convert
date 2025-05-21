# Convert.jai

## Overview

This module features a wide range of data conversion utilities, from simple numeric casts to recursive struct and array remapping.
This module was originally part of my Data Packer module as remap.jai, but I've separated it out into its own module since I found myself importing data Packer just to use the data conversion/remapping functionality quite often.

I've made an effort to clean up much of the code, but be warned there is still some mess, partcularly surrounding unions and arrays.


## Functionality

Procedures are *mostly* named intuitively, in the format of `X_to_Y`, where `X` is the source data type and `Y` is the destination data type.
These procedures are structured very hierarchically, with the broad procedures calling down into the more specific ones.
The most broad procedure is `any_to_any`, which will essentially just switch on the destination data type to get to a more specific case.
Most of the main procedures in the module match the signature `(dst: Any, src: Any) -> success: bool`, with some exceptions for optional parameters.

Conversion settings can be configured in the global context so that different parts of a program may enforce different rules about how to handle certain conversion types, or which conversion types are even allowed in the first place.
These settings also give the user the ability to exert some control over which conversion types will be allowed when calling any_to_any, which could otherwise do some *very* dynamic things that perhaps the user does not want to do.

Procedures can be broadly classified as either utility conversions or remapping procedures.
The utility conversions do not make use of the context's conversion settings, since they are considered as sort of fundamental conversions whose operation should not depend on some implicit context being properly configured.
The remapping procedures do consule the conversion settings, since they are more broad in functionality and users may wish to disable, modify, or augment some of that functionality.


### Utility Conversions

The following functions are provided to convert between all type of integer, float, and enum values:
```
int_to_int
int_to_float
float_to_float
float_to_int

enum_as_int
int_to_enum
enum_to_int
enum_to_enum
float_to_enum
enum_to_float

any_to_bool
bool_to_any
```
Procedures in which the source/destination type is named explicitly will assert that the Any's type tag matches what is expected.
If you are completely unsure what the source/destination type will be, use any_to_any instead.

Int-to-int conversions will perform a dynamic range check on the source value before attempting to store that value to the destination type.
If caught, any out-of-range value can then either be clamped (and logged as a warning), or return an error.


### Remapping Procedures

Handling of structs, arrays, and unions gets a bit more complex, but the interface remains essentially the same.
```
any_to_int
any_to_float

remap_enum
remap_struct
remap_array
remap_union
```

Remapping procedures, unlike the basic utility conversions, need to do a bit more work, but are also more versatile.
These procedures also consult the conversion settings in the context, so that they don't do something funky that you don't want them to do.

`remap_enum` will remap from one enum to another based on the name assigned to the value.
`remap_struct` will recursively remap all struct members, based on the names of the members.
`remap_array` will do, well, a lot of stuff. Better to just have a whole section on that...

Union handling is still not ideal, and it requires some more setup on the part of the user.
A couple of basic utility procedures are provided to handle the most simple cases. 
Unions probably deserve their own whole little section as well, but I'll probably wait until I finish some refactoring on unions to document them more thoroughly.

#### Array Remapping

Remapping can occur between any combination of array types (fixed, view, or resizable), with settings flags to control which of those converisons are allowed.

A single element of type T can also be remapped to an array with element type T (if permitted by conversion settings, of course).

We also support remapping between strings and arrays where the element type has a runtime size of 1 byte.


### Conversion Settings in the Context



I would encourage users to be wary of how pointers are currently handled. I probably haven't done my due diligence to make the handling sufficiently configurable yet, since I have been the only user.

