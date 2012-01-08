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

END {
    ## some indirect offsets
    print "#define OFFSET_StgHeader_prof_ccs (OFFSET_StgHeader_prof + OFFSET_StgProfHeader_ccs)"
    print "#define OFFSET_StgHeader_prof_hp_ldvw (OFFSET_StgHeader_prof + OFFSET_StgProfHeader_hp + 0)"
    print "#define OFFSET_StgTSO_prof_cccs (OFFSET_StgTSO_prof + OFFSET_StgTSOProfInfo_cccs)"

    print "#define OFFSET_RTS_FLAGS_ProfFlags_showCCSOnException (OFFSET_RTS_FLAGS_ProfFlags + OFFSET_PROF_FLAGS_showCCSOnException)"


    print "#define OFFSET_RTS_FLAGS_DebugFlags_apply (OFFSET_RTS_FLAGS_DebugFlags + OFFSET_DEBUG_FLAGS_apply)"
    print "#define OFFSET_RTS_FLAGS_DebugFlags_sanity (OFFSET_RTS_FLAGS_DebugFlags + OFFSET_DEBUG_FLAGS_sanity)"
    print "#define OFFSET_RTS_FLAGS_DebugFlags_weak (OFFSET_RTS_FLAGS_DebugFlags + OFFSET_DEBUG_FLAGS_weak)"
    print "#define OFFSET_RTS_FLAGS_GcFlags_initialStkSize (OFFSET_RTS_FLAGS_GcFlags + OFFSET_GC_FLAGS_initialStkSize)"
    print "#define OFFSET_RTS_FLAGS_MiscFlags_tickInterval (OFFSET_RTS_FLAGS_MiscFlags + OFFSET_MISC_FLAGS_tickInterval)"

    print "#define OFFSET_StgFunInfoExtraFwd_b_bitmap (OFFSET_StgFunInfoExtraFwd_b + 0)"
    print "#define OFFSET_StgFunInfoExtraRev_b_bitmap (OFFSET_StgFunInfoExtraRev_b + 0)"

    ## FIXME:
    print "#define OFFSET_PROF_FLAGS_showCCSOnException 0"
    print "#define OFFSET_DEBUG_FLAGS_apply 0"
    print "#define OFFSET_DEBUG_FLAGS_sanity 0"
    print "#define OFFSET_DEBUG_FLAGS_weak 0"
    print "#define OFFSET_GC_FLAGS_initialStkSize 0"
    print "#define OFFSET_MISC_FLAGS_tickInterval 0"
}
