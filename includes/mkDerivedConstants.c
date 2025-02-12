/* --------------------------------------------------------------------------
 *
 * (c) The GHC Team, 1992-2012
 *
 * mkDerivedConstants.c
 *
 * Basically this is a C program that extracts information from the C
 * declarations in the header files (primarily struct field offsets)
 * and generates a header file that can be #included into non-C source
 * containing this information.
 *
 * ------------------------------------------------------------------------*/

#define IN_STG_CODE 0

/*
 * We need offsets of profiled and threaded things... better be
 * careful that this doesn't affect the offsets of anything else.
 */

#define PROFILING
#define THREADED_RTS

#include "Rts.h"
#include "Stable.h"
#include "Capability.h"
#include "SizeMacros.h"

#pragma GCC poison sizeof

#include <stdio.h>

#define str(a,b) #a "_" #b

#if defined(GEN_HASKELL)
#define def_offset(str, offset)                          \
    printf("oFFSET_" str " :: Int\n");                   \
    printf("oFFSET_" str " = %lu\n", (unsigned long)offset);
#else
#define def_offset(str, offset) \
    printf("#define OFFSET_" str " %lu\n", (unsigned long)offset);
#endif

#if defined(GEN_HASKELL)
#define ctype(type) /* nothing */
#else
#define ctype(type) \
    printf("#define SIZEOF_" #type " %lu\n", (unsigned long)TYPE_SIZE(type));
#endif

#if defined(GEN_HASKELL)
#define field_type_(str, s_type, field) /* nothing */
#define field_type_gcptr_(str, s_type, field) /* nothing */
#else
/* Defining REP_x to be b32 etc
   These are both the C-- types used in a load
      e.g.  b32[addr]
   and the names of the CmmTypes in the compiler
      b32 :: CmmType
*/
#define field_type_(str, s_type, field) \
    printf("#define REP_" str " b"); \
    printf("%lu\n", FIELD_SIZE(s_type, field) * 8);
#define field_type_gcptr_(str, s_type, field) \
    printf("#define REP_" str " gcptr\n");
#endif

#define field_type(s_type, field) \
    field_type_(str(s_type,field),s_type,field);

#define field_offset_(str, s_type, field) \
    def_offset(str, OFFSET(s_type,field));

#define field_offset(s_type, field) \
    field_offset_(str(s_type,field),s_type,field);

/* An access macro for use in C-- sources. */
#define struct_field_macro(str) \
    printf("#define " str "(__ptr__)  REP_" str "[__ptr__+OFFSET_" str "]\n");

/* Outputs the byte offset and MachRep for a field */
#define struct_field(s_type, field)		\
    field_offset(s_type, field);		\
    field_type(s_type, field);			\
    struct_field_macro(str(s_type,field))

#define struct_field_(str, s_type, field)	\
    field_offset_(str, s_type, field);		\
    field_type_(str, s_type, field);		\
    struct_field_macro(str)

#if defined(GEN_HASKELL)
#define def_size(str, size)                \
    printf("sIZEOF_" str " :: Int\n");     \
    printf("sIZEOF_" str " = %lu\n", (unsigned long)size);
#else
#define def_size(str, size) \
    printf("#define SIZEOF_" str " %lu\n", (unsigned long)size);
#endif

#if defined(GEN_HASKELL)
#define def_closure_size(str, size) /* nothing */
#else
#define def_closure_size(str, size) \
    printf("#define SIZEOF_" str " (SIZEOF_StgHeader+%lu)\n", (unsigned long)size);
#endif

#define struct_size(s_type) \
    def_size(#s_type, TYPE_SIZE(s_type));

/*
 * Size of a closure type, minus the header, named SIZEOF_<type>_NoHdr
 * Also, we #define SIZEOF_<type> to be the size of the whole closure for .cmm.
 */
#define closure_size(s_type) \
    def_size(#s_type "_NoHdr", TYPE_SIZE(s_type) - TYPE_SIZE(StgHeader)); \
    def_closure_size(#s_type, TYPE_SIZE(s_type) - TYPE_SIZE(StgHeader));

#define thunk_size(s_type) \
    def_size(#s_type "_NoThunkHdr", TYPE_SIZE(s_type) - TYPE_SIZE(StgThunkHeader)); \
    closure_size(s_type)

/* An access macro for use in C-- sources. */
#define closure_field_macro(str) \
    printf("#define " str "(__ptr__)  REP_" str "[__ptr__+SIZEOF_StgHeader+OFFSET_" str "]\n");

#define closure_field_offset_(str, s_type,field) \
    def_offset(str, OFFSET(s_type,field) - TYPE_SIZE(StgHeader));

#define closure_field_offset(s_type,field) \
    closure_field_offset_(str(s_type,field),s_type,field)

#define closure_payload_macro(str) \
    printf("#define " str "(__ptr__,__ix__)  W_[__ptr__+SIZEOF_StgHeader+OFFSET_" str " + WDS(__ix__)]\n");

#define closure_payload(s_type,field) \
    closure_field_offset_(str(s_type,field),s_type,field); \
    closure_payload_macro(str(s_type,field));

/* Byte offset and MachRep for a closure field, minus the header */
#define closure_field_(str, s_type, field) \
    closure_field_offset_(str,s_type,field) \
    field_type_(str, s_type, field); \
    closure_field_macro(str)

#define closure_field(s_type, field) \
    closure_field_(str(s_type,field),s_type,field)

/* Byte offset and MachRep for a closure field, minus the header */
#define closure_field_gcptr_(str, s_type, field) \
    closure_field_offset_(str,s_type,field) \
    field_type_gcptr_(str, s_type, field); \
    closure_field_macro(str)

#define closure_field_gcptr(s_type, field) \
    closure_field_gcptr_(str(s_type,field),s_type,field)

/* Byte offset for a TSO field, minus the header and variable prof bit. */
#define tso_payload_offset(s_type, field) \
    def_offset(str(s_type,field), OFFSET(s_type,field) - TYPE_SIZE(StgHeader) - TYPE_SIZE(StgTSOProfInfo));

/* Full byte offset for a TSO field, for use from Cmm */
#define tso_field_offset_macro(str) \
    printf("#define TSO_OFFSET_" str " (SIZEOF_StgHeader+SIZEOF_OPT_StgTSOProfInfo+OFFSET_" str ")\n");

#define tso_field_offset(s_type, field) \
    tso_payload_offset(s_type, field);  	\
    tso_field_offset_macro(str(s_type,field));

#define tso_field_macro(str) \
    printf("#define " str "(__ptr__)  REP_" str "[__ptr__+TSO_OFFSET_" str "]\n")
#define tso_field(s_type, field)		\
    field_type(s_type, field);			\
    tso_field_offset(s_type,field);		\
    tso_field_macro(str(s_type,field))
  
#define opt_struct_size(s_type, option)					\
    printf("#ifdef " #option "\n");					\
    printf("#define SIZEOF_OPT_" #s_type " SIZEOF_" #s_type "\n");	\
    printf("#else\n");							\
    printf("#define SIZEOF_OPT_" #s_type " 0\n");			\
    printf("#endif\n\n");

#define FUN_OFFSET(sym) (OFFSET(Capability,f) + OFFSET(StgFunTable,sym) - OFFSET(Capability,r))


int
main(int argc, char *argv[])
{
#ifndef GEN_HASKELL
    printf("/* This file is created automatically.  Do not edit by hand.*/\n\n");

    printf("#define STD_HDR_SIZE   %lu\n", (unsigned long)sizeofW(StgHeader) - sizeofW(StgProfHeader));
    /* grrr.. PROFILING is on so we need to subtract sizeofW(StgProfHeader) */
    printf("#define PROF_HDR_SIZE  %lu\n", (unsigned long)sizeofW(StgProfHeader));

    printf("#define BLOCK_SIZE   %u\n", BLOCK_SIZE);
    printf("#define MBLOCK_SIZE   %u\n", MBLOCK_SIZE);
    printf("#define BLOCKS_PER_MBLOCK  %lu\n", (lnat)BLOCKS_PER_MBLOCK);
    // could be derived, but better to save doing the calculation twice

    printf("\n\n");
#endif

    field_offset(StgRegTable, rR1);
    field_offset(StgRegTable, rR2);
    field_offset(StgRegTable, rR3);
    field_offset(StgRegTable, rR4);
    field_offset(StgRegTable, rR5);
    field_offset(StgRegTable, rR6);
    field_offset(StgRegTable, rR7);
    field_offset(StgRegTable, rR8);
    field_offset(StgRegTable, rR9);
    field_offset(StgRegTable, rR10);
    field_offset(StgRegTable, rF1);
    field_offset(StgRegTable, rF2);
    field_offset(StgRegTable, rF3);
    field_offset(StgRegTable, rF4);
    field_offset(StgRegTable, rD1);
    field_offset(StgRegTable, rD2);
    field_offset(StgRegTable, rL1);
    field_offset(StgRegTable, rSp);
    field_offset(StgRegTable, rSpLim);
    field_offset(StgRegTable, rHp);
    field_offset(StgRegTable, rHpLim);
    field_offset(StgRegTable, rCCCS);
    field_offset(StgRegTable, rCurrentTSO);
    field_offset(StgRegTable, rCurrentNursery);
    field_offset(StgRegTable, rHpAlloc);
    struct_field(StgRegTable, rRet);
    struct_field(StgRegTable, rNursery);

    def_offset("stgEagerBlackholeInfo", FUN_OFFSET(stgEagerBlackholeInfo));
    def_offset("stgGCEnter1", FUN_OFFSET(stgGCEnter1));
    def_offset("stgGCFun", FUN_OFFSET(stgGCFun));

    field_offset(Capability, r);
    struct_field(Capability, no);
    struct_field(Capability, mut_lists);
    struct_field(Capability, context_switch);
    struct_field(Capability, interrupt);
#ifdef THREADED_RTS
    /* THREADED_RTS is actually always defined, see top of this file */
    field_offset(Capability, lock);
    struct_field(Capability, sparks);
#endif

    struct_field(bdescr, start);
    struct_field(bdescr, free);
    struct_field(bdescr, blocks);
    struct_field(bdescr, gen_no);
    struct_field(bdescr, link);

    struct_size(generation);
    struct_field(generation, n_new_large_words);

    struct_size(CostCentreStack);
    struct_field(CostCentreStack, ccsID);
    struct_field(CostCentreStack, mem_alloc);
    struct_field(CostCentreStack, scc_count);
    struct_field(CostCentreStack, prevStack);

    struct_field(CostCentre, ccID);
    struct_field(CostCentre, link);

    struct_field(StgHeader, info);
    struct_field_("StgHeader_ccs",  StgHeader, prof_ccs);     // member prof.ccs, see SizeMacros.h
    struct_field_("StgHeader_ldvw", StgHeader, prof_hp_ldvw); // member prof.hp.ldvw, see SizeMacros.h

    struct_size(StgSMPThunkHeader);

    closure_payload(StgClosure,payload);

    struct_field(StgEntCounter, allocs);
    struct_field(StgEntCounter, registeredp);
    struct_field(StgEntCounter, link);
    struct_field(StgEntCounter, entry_count);

    closure_size(StgUpdateFrame);
    closure_size(StgCatchFrame);
    closure_size(StgStopFrame);

    closure_size(StgMutArrPtrs);
    closure_field(StgMutArrPtrs, ptrs);
    closure_field(StgMutArrPtrs, size);

    closure_size(StgArrWords);
    closure_field(StgArrWords, bytes);
    closure_payload(StgArrWords, payload);

    closure_field(StgTSO, _link);
    closure_field(StgTSO, global_link);
    closure_field(StgTSO, what_next);
    closure_field(StgTSO, why_blocked);
    closure_field(StgTSO, block_info);
    closure_field(StgTSO, blocked_exceptions);
    closure_field(StgTSO, id);
    closure_field(StgTSO, cap);
    closure_field(StgTSO, saved_errno);
    closure_field(StgTSO, trec);
    closure_field(StgTSO, flags);
    closure_field(StgTSO, dirty);
    closure_field(StgTSO, bq);
    closure_field_("StgTSO_cccs", StgTSO, prof_cccs); // member prof.cccs, see SizeMacros.h
    closure_field(StgTSO, stackobj);

    closure_field(StgStack, sp);
    closure_field_offset(StgStack, stack);
    closure_field(StgStack, stack_size);
    closure_field(StgStack, dirty);

    struct_size(StgTSOProfInfo);

    opt_struct_size(StgTSOProfInfo,PROFILING);

    closure_field(StgUpdateFrame, updatee);

    closure_field(StgCatchFrame, handler);
    closure_field(StgCatchFrame, exceptions_blocked);

    closure_size(StgPAP);
    closure_field(StgPAP, n_args);
    closure_field_gcptr(StgPAP, fun);
    closure_field(StgPAP, arity);
    closure_payload(StgPAP, payload);

    thunk_size(StgAP);
    closure_field(StgAP, n_args);
    closure_field_gcptr(StgAP, fun);
    closure_payload(StgAP, payload);

    thunk_size(StgAP_STACK);
    closure_field(StgAP_STACK, size);
    closure_field_gcptr(StgAP_STACK, fun);
    closure_payload(StgAP_STACK, payload);

    thunk_size(StgSelector);

    closure_field_gcptr(StgInd, indirectee);

    closure_size(StgMutVar);
    closure_field(StgMutVar, var);

    closure_size(StgAtomicallyFrame);
    closure_field(StgAtomicallyFrame, code);
    closure_field(StgAtomicallyFrame, next_invariant_to_check);
    closure_field(StgAtomicallyFrame, result);

    closure_field(StgInvariantCheckQueue, invariant);
    closure_field(StgInvariantCheckQueue, my_execution);
    closure_field(StgInvariantCheckQueue, next_queue_entry);

    closure_field(StgAtomicInvariant, code);

    closure_field(StgTRecHeader, enclosing_trec);

    closure_size(StgCatchSTMFrame);
    closure_field(StgCatchSTMFrame, handler);
    closure_field(StgCatchSTMFrame, code);

    closure_size(StgCatchRetryFrame);
    closure_field(StgCatchRetryFrame, running_alt_code);
    closure_field(StgCatchRetryFrame, first_code);
    closure_field(StgCatchRetryFrame, alt_code);

    closure_field(StgTVarWatchQueue, closure);
    closure_field(StgTVarWatchQueue, next_queue_entry);
    closure_field(StgTVarWatchQueue, prev_queue_entry);

    closure_field(StgTVar, current_value);

    closure_size(StgWeak);
    closure_field(StgWeak,link);
    closure_field(StgWeak,key);
    closure_field(StgWeak,value);
    closure_field(StgWeak,finalizer);
    closure_field(StgWeak,cfinalizer);

    closure_size(StgDeadWeak);
    closure_field(StgDeadWeak,link);

    closure_size(StgMVar);
    closure_field(StgMVar,head);
    closure_field(StgMVar,tail);
    closure_field(StgMVar,value);

    closure_size(StgMVarTSOQueue);
    closure_field(StgMVarTSOQueue, link);
    closure_field(StgMVarTSOQueue, tso);

    closure_size(StgBCO);
    closure_field(StgBCO, instrs);
    closure_field(StgBCO, literals);
    closure_field(StgBCO, ptrs);
    closure_field(StgBCO, arity);
    closure_field(StgBCO, size);
    closure_payload(StgBCO, bitmap);

    closure_size(StgStableName);
    closure_field(StgStableName,sn);

    closure_size(StgBlockingQueue);
    closure_field(StgBlockingQueue, bh);
    closure_field(StgBlockingQueue, owner);
    closure_field(StgBlockingQueue, queue);
    closure_field(StgBlockingQueue, link);

    closure_size(MessageBlackHole);
    closure_field(MessageBlackHole, link);
    closure_field(MessageBlackHole, tso);
    closure_field(MessageBlackHole, bh);

    struct_field_("RtsFlags_ProfFlags_showCCSOnException",
		  RTS_FLAGS, ProfFlags_showCCSOnException); // member ProfFlags.showCCSOnException, see SizeMacros.h
    struct_field_("RtsFlags_DebugFlags_apply",
		  RTS_FLAGS, DebugFlags_apply);             // member DebugFlags.apply, see SizeMacros.h
    struct_field_("RtsFlags_DebugFlags_sanity",
		  RTS_FLAGS, DebugFlags_sanity);            // member DebugFlags.sanity, see SizeMacros.h
    struct_field_("RtsFlags_DebugFlags_weak",
		  RTS_FLAGS, DebugFlags_weak);              // member DebugFlags.weak, see SizeMacros.h
    struct_field_("RtsFlags_GcFlags_initialStkSize",
		  RTS_FLAGS, GcFlags_initialStkSize);       // member GcFlags.initialStkSize, see SizeMacros.h
    struct_field_("RtsFlags_MiscFlags_tickInterval",
		  RTS_FLAGS, MiscFlags_tickInterval);       // member MiscFlags.tickInterval, see SizeMacros.h

    struct_size(StgFunInfoExtraFwd);
    struct_field(StgFunInfoExtraFwd, slow_apply);
    struct_field(StgFunInfoExtraFwd, fun_type);
    struct_field(StgFunInfoExtraFwd, arity);
    struct_field_("StgFunInfoExtraFwd_bitmap", StgFunInfoExtraFwd, b_bitmap); // member b.bitmap, see SizeMacros.h

    struct_size(StgFunInfoExtraRev);
    struct_field(StgFunInfoExtraRev, slow_apply_offset);
    struct_field(StgFunInfoExtraRev, fun_type);
    struct_field(StgFunInfoExtraRev, arity);
    struct_field_("StgFunInfoExtraRev_bitmap", StgFunInfoExtraRev, b_bitmap); // member b.bitmap, see SizeMacros.h

    struct_field(StgLargeBitmap, size);
    field_offset(StgLargeBitmap, bitmap);

    struct_size(snEntry);
    struct_field(snEntry,sn_obj);
    struct_field(snEntry,addr);

#ifdef mingw32_HOST_OS
    struct_size(StgAsyncIOResult);
    struct_field(StgAsyncIOResult, reqID);
    struct_field(StgAsyncIOResult, len);
    struct_field(StgAsyncIOResult, errCode);
#endif

    return 0;
}
