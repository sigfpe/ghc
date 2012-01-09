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
  print "#include \"Rts.h\""
  print "#include \"Capability.h\""
  print ""
  ## these do not have a proper typedef; supply them here
  print "#define FLAG_STRUCT_TYPE(IT) typedef struct IT ## _FLAGS IT ## _FLAGS"
  print "FLAG_STRUCT_TYPE(GC);"
  print "FLAG_STRUCT_TYPE(DEBUG);"
  print "FLAG_STRUCT_TYPE(COST_CENTRE);"
  print "FLAG_STRUCT_TYPE(PROFILING);"
  print "FLAG_STRUCT_TYPE(TRACE);"
  print "FLAG_STRUCT_TYPE(CONCURRENT);"
  print "FLAG_STRUCT_TYPE(MISC);"
  print "FLAG_STRUCT_TYPE(PAR);"
  print "FLAG_STRUCT_TYPE(TICKY);"
  ## these we do know how to get the field size,
  ## so do not bother mining it
  print "#define DO_NOT_MINE_UNION_MEMBER(STRUCT, NESTED_MEMBER, ID) char nestedfieldsize$ ## STRUCT ## $ ## ID [sizeof ((STRUCT*)0)->NESTED_MEMBER]"
  print "DO_NOT_MINE_UNION_MEMBER(StgHeader, prof.hp.ldvw, prof_hp_ldvw);"
  print "DO_NOT_MINE_UNION_MEMBER(StgFunInfoExtraFwd, b.bitmap, b_bitmap);"
  print "DO_NOT_MINE_UNION_MEMBER(StgFunInfoExtraRev, b.bitmap, b_bitmap);"
}

## pass through embedded unions
eat_union && /^[ \t]*}[ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*[ \t]*;[ \t]*$/ {
  past_members = past_members "\n" $0

  sub(/^[ \t]*}[ \t]*/, "")
  sub(/[ \t]*;[ \t]*$/, "")
  new_offset_struct_name = struct_name $0

  print "struct " new_offset_struct_name " {"
  if (past_members) print past_members

  eat_union = 0
  print "};"
  print ""
  offset_struct_name = new_offset_struct_name

  print "char sizeof" offset_struct_name "[sizeof(struct " offset_struct_name ")];"
  next
}

eat_union {
  past_members = past_members "\n" $0
  next
}

/# [0-9]* "rts\// {
  ours = 1
  next
}

/# [0-9]* "includes\// {
  ours = 1
  next
}

## filter out non-ghc headers
/# [0-9]* "/ {
  ours = 0
  next
}

!ours {
  next
}


/#if IN_STG_CODE/ {
  nextfile
}

!interesting {
  struct_name = "$" seed "$"
  offset_struct_name = ""
  past_members = ""
  known_struct_name = ""
  eat_union = 0
}

## kill empty line
/^[ \t]*$/ {
  next
}

/^# [0-9]/ {
  print
  next
}

/^typedef struct[ \t][ \t]*[_0-9a-zA-Z]*[ \t]*{[ \t]*$/ {
  if (interesting) error "previous struct not closed?"
  interesting = 1
  print ""
  print "/* ### Creating offset structs for " $3 " ### */"
  next
}

/^struct[ \t][ \t]*[_0-9a-zA-Z]*[ \t]*{[ \t]*$/ {
  if (interesting) error "previous struct not closed?"
  interesting = 1
  known_struct_name = $2
  sub(/_$/, "", known_struct_name);
  print ""
  print "/* ### Creating offset structs for " known_struct_name " ### */"
  print "char associate$" known_struct_name "$" seed ";"
  next
}

## end of struct
##
interesting && /^[ \t]*}[ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*[ \t]*;[ \t]*$/{
  sub(/;$/, "", $2)

  print "char associate$" $2 "$" seed ";"

  
  print "char SIZEOF$" seed "[sizeof(" $2 ")];"

  print "typedef char verify" offset_struct_name "[sizeof(struct " offset_struct_name ") == sizeof(" $2 ") ? 1 : -1];"
  print ""
  print ""
  ++seed
  interesting = 0
}

## Ptr-typedef
interesting && /^[ \t]*}[ \t]*\*[_0-9a-zA-Z][_0-9a-zA-Z]*Ptr[ \t]*;[ \t]*$/{
  sub(/Ptr;$/, "", $2)
  sub(/^\*/, "", $2)

  print "char associate$" $2 "$" seed ";"

  
  print "char SIZEOF$" seed "[sizeof(" $2 ")];"

  print "typedef char verify" offset_struct_name "[sizeof(struct " offset_struct_name ") == sizeof(" $2 ") ? 1 : -1];"
  print ""
  print ""
  ++seed
  interesting = 0
}

interesting && /^[ \t]*}[; \t]*$/ {
  print "char SIZEOF$" seed "[sizeof(" known_struct_name ")];"

  if (known_struct_name == "Capability") {
      offset_struct_name = "aligned$" offset_struct_name
      print "struct " offset_struct_name " {"
      if (past_members) print past_members
      print "} ATTRIBUTE_ALIGNED(64);"
  }

  print "typedef char verify" offset_struct_name "[sizeof(struct " offset_struct_name ") == sizeof(" known_struct_name ") ? 1 : -1];"
  print ""
  print ""
  ++seed
  interesting = 0
}

# collapse whitespace after '*'
interesting {
  # normalize some types
  sub(/struct StgClosure_[ \t]*\*/, "StgClosure *")
  gsub(/\*[ \t]*volatile/, "*")
  # group stars together
  gsub(/\*[ \t]*/, "*")
  sub(/\*/, " *")
  print "//   " $0
  # remove volatile
  sub(/[ \t]volatile[ \t]/, " ")
  # remove const
  sub(/[ \t]const[ \t]/, " ")
}

## (pointer to struct) member of struct
##
interesting && /^[ \t]*struct[ \t][ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*[ \t]*\*[ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*[ \t]*;[ \t]*$/ {
  if (!$4) {
    sub(/^\*/, "", $3)
    $4 = $3
  }
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
  print "char fieldsize" offset_struct_name "[sizeof(struct " $2 "*)];"
  print ""
  print ""
  next
}

## (simple pointer) member of struct
##
interesting && /^[ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*[ \t][ \t]*\*\**[_0-9a-zA-Z][_0-9a-zA-Z]*[ \t]*;[ \t]*$/ {
  sub(/;$/, "", $2)
  sub(/^\**/, "", $2)

  new_offset_struct_name = struct_name $2
  print "struct " new_offset_struct_name " {"
  if (past_members) print past_members
  new_member = "  " $1 " * " $2 ";"
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
  print "char fieldsize" offset_struct_name "[sizeof(" $1 "*)];"
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
  print "char fieldsize" offset_struct_name "[sizeof(" $1 ")];"
  print ""
  print ""
  next
}

## struct member of struct
##
interesting && /^[ \t]*struct[ \t][ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*[ \t][ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*;[ \t]*$/ {
  sub(/;$/, "", $3)

  new_offset_struct_name = struct_name $3
  print "struct " new_offset_struct_name " {"
  if (past_members) print past_members
  new_member = "  struct " $2 " " $3 ";"
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
  print "char fieldsize" offset_struct_name "[sizeof(struct " $2 ")];"
  print ""
  print ""
  next
}

## embedded union
interesting && /^[ \t]*union[ \t]*{[ \t]*$/ {
  if (past_members) {
    past_members = past_members "\n" $0
  } else {
    past_members = $0
  }
  eat_union = 1
  next
}

## array member
interesting && /^[ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*[ \t][ \t]*\**[_0-9a-zA-Z][_0-9a-zA-Z]*\[.*\];[ \t]*$/ {
  sub(/;[ \t]*$/, "", $0)

  full = $0
  sub(/^[ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*[ \t][ \t]*/, "", full)
  split(full, parts, "[")
  mname = parts[1]
  sub(/^\**/, "", mname)

  new_offset_struct_name = struct_name mname
  print "struct " new_offset_struct_name " {"
  if (past_members) print past_members
  new_member = "  " $1 " " full ";"
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


## padded member of struct
##   of this form: StgHalfInt slow_apply_offset; StgHalfWord __pad_slow_apply_offset;;
##
interesting && /^[ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*[ \t][ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*;[ \t]*[_0-9a-zA-Z][_0-9a-zA-Z]*[ \t][ \t]*__pad_[a-zA-Z][_0-9a-zA-Z]*;;*[ \t]*$/ {
  mname = $2
  sub(/;$/, "", mname)

  new_offset_struct_name = struct_name mname
  print "struct " new_offset_struct_name " {"
  if (past_members) print past_members
  new_member = $0
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

interesting && /;[ \t]*$/ {
  print "Member not recognized: " $0 > "/dev/stderr"
  exit 1
}