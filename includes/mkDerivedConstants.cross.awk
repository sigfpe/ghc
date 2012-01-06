## This script rewrites normal C structs into successively
## greater ones so that field offset computation becomes a
## sizeof lookup and thus amenable to compile-time computations.

## Usage: pipe stg/Regs.h into 'awk' running this script
##        to obtain a .c file that can be compiled to .o
##        with the gcc from the cross toolchain. Then
##        use another 'awk' script to process the 'nm'
##        output of the object file.

## Motivation: since in general we can not run executables
##             created by the cross toolchain, we need another
##             way of finding out field offsets and type sizes
##             of the target platform.

BEGIN {
  interesting = 0
  seed = 0
  print "/* this file is generated by mkDerivedConstants.cross.awk, do not touch */"
  print "/* needs to be compiled with the target gcc */"
  print ""
  print "#include \"includes/ghcautoconf.h\""
  print "#include \"includes/stg/Types.h\""
  print "#include \"includes/stg/Regs.h\""
  print "#include \"rts/Capability.h\""
  print ""
}

!interesting {
  struct_name = "__" seed "_"
  offset_struct_name = ""
  past_members = ""
}

## kill comments
/\/\*.*\*\// {
    gsub(/\/\*.*\*\//, "")
}

/\/\/.*$/ {
    sub(/\/\/.*$/, "")
}

## kill empty line
/^[ \t]*$/ {
  next
}

/^#/ {
  print
  next
}

/^typedef struct[ \t][ \t]*[_0-9a-zA-Z]*[ \t]*{[ \t]*$/ {
  interesting = 1

print "############# INTERESTING" $3
  next
}

/^struct[ \t][ \t]*[_0-9a-zA-Z]*[ \t]*{[ \t]*$/ {
  interesting = 1

print "############# INTERESTING" $2
  next
}

## end of struct
##
interesting && /^[ \t]*}[ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*[ \t]*;[ \t]*$/ || /^[ \t]*}[ \t]*$/ {
  sub(/;$/, "", $2)
  
  print "char SIZEOF" offset_struct_name "[sizeof(" $2 ")];"

  print "typedef char verify" offset_struct_name "[sizeof(struct " offset_struct_name ") == sizeof(" $2 ") ? 1 : -1];"
  print ""
  print ""
  ++seed
  interesting = 0
}

## (pointer) member of struct
##
interesting && /^[ \t]*struct[ \t][ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*[ \t]*\*[ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*[ \t]*;[ \t]*$/ {
  sub(/;$/, "", $4)

  new_offset_struct_name = struct_name $4
  print "struct " new_offset_struct_name " {"
  if (past_members) print past_members
  new_member = "  struct " $2 " * " $4 ";"
  print new_member
  if (past_members) {
    past_members = past_members "\n" new_member
  } else {
    past_members = new_member
  }
  print "};"
  print ""
  offset_struct_name = new_offset_struct_name

  print "char sizeof" offset_struct_name "[sizeof(struct " offset_struct_name ")];"
  print ""
  print ""
  next
}

## member of struct
##
interesting && /^[ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*[ \t][ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*;[ \t]*$/ {
  sub(/;$/, "", $2)

  new_offset_struct_name = struct_name $2
  print "struct " new_offset_struct_name " {"
  if (past_members) print past_members
  new_member = "  " $1 " " $2 ";"
  print new_member
  if (past_members) {
    past_members = past_members "\n" new_member
  } else {
    past_members = new_member
  }
  print "};"
  print ""
  offset_struct_name = new_offset_struct_name

  print "char sizeof" offset_struct_name "[sizeof(struct " offset_struct_name ")];"
  print ""
  print ""
  next
}

