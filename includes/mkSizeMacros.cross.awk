BEGIN {
  print "#define OFFSET(s_type, field) OFFSET_ ## s_type ## _ ## field"
  print "#define FIELD_SIZE(s_type, field) FIELD_SIZE_ ## field"
  print "#define TYPE_SIZE(type) TYPE_SIZE_ ## type"
  print ""
}

/^0[0-9a-zA-Z]* C _*associate\$/ {
  sub(/_*associate\$/, "", $3)
  split($3, arr, "$")
  #print "// " arr[2] " = " arr[1]
  assoc[arr[2]] = arr[1]
  #print "// assoc[arr[1]]: " assoc[arr[1]]
  next
}

/^0[0-9a-zA-Z]* C _*sizeof\$[0-9]*\$[_0-9a-zA-Z]*$/ {
  sub(/_*sizeof\$/, "", $3)
  split($3, arr, "$")
  sub(/^0*/, "", $1)
  print "#define OFFSET_" assoc[arr[1]] "_" arr[2] " 0x" $1
  next
}

/^0[0-9a-zA-Z]* C _*SIZEOF\$[0-9]*$/ {
  sub(/_*SIZEOF\$/, "", $3)
  sub(/^0*/, "", $1)
  print "#define TYPE_SIZE_" assoc[$3] " 0x" $1
  next
}

{ print "// " $0 }
