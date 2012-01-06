BEGIN {
  print "#define OFFSET(s_type, field) OFFSET_ ## field"
  print "#define FIELD_SIZE(s_type, field) FIELD_SIZE_ ## field"
  print "#define TYPE_SIZE(type) TYPE_SIZE_ ## type"
}

/^0[0-9a-zA-Z]* C _*associate\$/ {
  sub(/_*sizeof__1_/, "", $3)
  split($3, arr, "$")
  print "// " arr[3] " = " arr[2]
  assoc[arr[3]] = arr[2]
  next
}

/^0[0-9a-zA-Z]* C _*sizeof__1_[_0-9a-zA-Z]*$/ {
  sub(/_*sizeof__1_/, "", $3)
  print "#define OFFSET_" $3 " 0x" $1
  next
}

{ print "// " $0 }
