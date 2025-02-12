# -----------------------------------------------------------------------------
#
# (c) 2009 The University of Glasgow
#
# This file is part of the GHC build system.
#
# To understand how the build system works and how to modify it, see
#      http://hackage.haskell.org/trac/ghc/wiki/Building/Architecture
#      http://hackage.haskell.org/trac/ghc/wiki/Building/Modifying
#
# -----------------------------------------------------------------------------

ghc_USES_CABAL = YES
ghc_PACKAGE = ghc-bin

ghc_stage1_CONFIGURE_OPTS += --flags=stage1
ghc_stage2_CONFIGURE_OPTS += --flags=stage2
ghc_stage3_CONFIGURE_OPTS += --flags=stage3

ifeq "$(GhcWithInterpreter)" "YES"
ghc_stage2_CONFIGURE_OPTS += --flags=ghci
ghc_stage3_CONFIGURE_OPTS += --flags=ghci
endif

ghc_stage1_MORE_HC_OPTS = $(GhcStage1HcOpts)
ghc_stage2_MORE_HC_OPTS = $(GhcStage2HcOpts)
ghc_stage3_MORE_HC_OPTS = $(GhcStage3HcOpts)

# We need __GLASGOW_HASKELL__ in hschooks.c, so we have to build C
# sources with GHC:
ghc_stage1_UseGhcForCC = YES
ghc_stage2_UseGhcForCC = YES
ghc_stage3_UseGhcForCC = YES

ghc_stage1_C_FILES_NODEPS = ghc/hschooks.c

ghc_stage2_MKDEPENDC_OPTS = -DMAKING_GHC_BUILD_SYSTEM_DEPENDENCIES
ghc_stage3_MKDEPENDC_OPTS = -DMAKING_GHC_BUILD_SYSTEM_DEPENDENCIES
ifneq "$(TARGETPLATFORM)" "$(HOSTPLATFORM)"
ghc_stage2_MKDEPENDC_OPTS += -DCOMPILING_GHC
endif

ifeq "$(GhcDebugged)" "YES"
ghc_stage1_MORE_HC_OPTS += -debug
ghc_stage2_MORE_HC_OPTS += -debug
ghc_stage3_MORE_HC_OPTS += -debug
endif

ifeq "$(GhcDynamic)" "YES"
ghc_stage2_MORE_HC_OPTS += -dynamic
ghc_stage3_MORE_HC_OPTS += -dynamic
endif

ifeq "$(GhcThreaded)" "YES"
# Use threaded RTS with GHCi, so threads don't get blocked at the prompt.
ghc_stage2_MORE_HC_OPTS += -threaded
ghc_stage3_MORE_HC_OPTS += -threaded
endif

ifeq "$(GhcProfiled)" "YES"
ghc_stage2_MORE_HC_OPTS += -prof
endif

ghc_stage1_PROG = ghc-stage1$(exeext)
ghc_stage2_PROG = ghc-stage2$(exeext)
ghc_stage3_PROG = ghc-stage3$(exeext)

ghc_stage1_SHELL_WRAPPER = YES
ghc_stage2_SHELL_WRAPPER = YES
ghc_stage3_SHELL_WRAPPER = YES
ifneq "$(TARGETPLATFORM)" "$(HOSTPLATFORM)"
ghc_stage1_SHELL_WRAPPER_NAME = ghc/ghc-cross.wrapper
ghc_stage2_SHELL_WRAPPER_NAME = ghc/ghc-cross.wrapper
else
ghc_stage1_SHELL_WRAPPER_NAME = ghc/ghc.wrapper
ghc_stage2_SHELL_WRAPPER_NAME = ghc/ghc.wrapper
ghc_stage3_SHELL_WRAPPER_NAME = ghc/ghc.wrapper
endif

ghc_stage$(INSTALL_GHC_STAGE)_INSTALL_SHELL_WRAPPER = YES
ghc_stage$(INSTALL_GHC_STAGE)_INSTALL_SHELL_WRAPPER_NAME = ghc-$(ProjectVersion)

# We override the program name to be ghc, rather than ghc-stage2.
# This means the right program name is used in error messages etc.
define ghc_stage$(INSTALL_GHC_STAGE)_INSTALL_SHELL_WRAPPER_EXTRA
echo 'executablename="$$exedir/ghc"' >> "$(WRAPPER)"
endef

# if stage is set to something other than "1" or "", disable stage 1
ifneq "$(filter-out 1,$(stage))" ""
ghc_stage1_NOT_NEEDED = YES
endif

ifneq "$(TARGETPLATFORM)" "$(HOSTPLATFORM)"
ghc_stage2_NOT_NEEDED = YES
ghc_stage3_NOT_NEEDED = YES
else
# if stage is set to something other than "2" or "", disable stage 2
ifneq "$(filter-out 2,$(stage))" ""
ghc_stage2_NOT_NEEDED = YES
endif
# stage 3 has to be requested explicitly with stage=3
ifneq "$(stage)" "3"
ghc_stage3_NOT_NEEDED = YES
endif
endif

$(eval $(call build-prog,ghc,stage1,0))
$(eval $(call build-prog,ghc,stage2,1))
$(eval $(call build-prog,ghc,stage3,2))

ifneq "$(BINDIST)" "YES"

ghc/stage1/build/tmp/$(ghc_stage1_PROG) : $(BOOT_LIBS)
ifeq "$(GhcProfiled)" "YES"
ghc/stage2/build/tmp/$(ghc_stage2_PROG) : $(compiler_stage2_p_LIB)
ghc/stage2/build/tmp/$(ghc_stage2_PROG) : $(foreach lib,$(PACKAGES_STAGE1),$(libraries/$(lib)_dist-install_p_LIB))
endif

# Modules here import HsVersions.h, so we need ghc_boot_platform.h
$(ghc_stage1_depfile_haskell) : compiler/stage1/$(PLATFORM_H)
$(ghc_stage2_depfile_haskell) : compiler/stage2/$(PLATFORM_H)
$(ghc_stage3_depfile_haskell) : compiler/stage3/$(PLATFORM_H)

all_ghc_stage1 : $(GHC_STAGE1)
all_ghc_stage2 : $(GHC_STAGE2)
all_ghc_stage3 : $(GHC_STAGE3)

$(INPLACE_LIB)/settings : settings
	"$(CP)" $< $@

# The GHC programs need to depend on all the helper programs they might call,
# and the settings files they use

$(GHC_STAGE1) : | $(UNLIT) $(INPLACE_LIB)/settings
$(GHC_STAGE2) : | $(UNLIT) $(INPLACE_LIB)/settings
$(GHC_STAGE3) : | $(UNLIT) $(INPLACE_LIB)/settings

ifeq "$(GhcUnregisterised)" "NO"
$(GHC_STAGE1) : | $(SPLIT)
$(GHC_STAGE2) : | $(SPLIT)
$(GHC_STAGE3) : | $(SPLIT)
endif

ifeq "$(Windows)" "YES"
$(GHC_STAGE1) : | $(TOUCHY)
$(GHC_STAGE2) : | $(TOUCHY)
$(GHC_STAGE3) : | $(TOUCHY)
endif

ifeq "$(BootingFromHc)" "YES"
$(GHC_STAGE2) : $(ALL_STAGE1_LIBS)
ghc_stage2_OTHER_OBJS += $(compiler_stage2_v_LIB) $(ALL_STAGE1_LIBS) $(ALL_STAGE1_LIBS) $(ALL_STAGE1_LIBS) $(ALL_RTS_LIBS) $(libffi_STATIC_LIB)
endif

endif

INSTALL_LIBS += settings

ifeq "$(Windows)" "NO"
install: install_ghc_link
.PNONY: install_ghc_link
install_ghc_link: 
	$(call removeFiles,"$(DESTDIR)$(bindir)/ghc")
	$(LN_S) ghc-$(ProjectVersion) "$(DESTDIR)$(bindir)/ghc"
else
# On Windows we install the main binary as $(bindir)/ghc.exe
# To get ghc-<version>.exe we have a little C program in driver/ghc
install: install_ghc_post
.PHONY: install_ghc_post
install_ghc_post: install_bins
	$(call removeFiles,$(DESTDIR)$(bindir)/ghc.exe)
	"$(MV)" -f $(DESTDIR)$(bindir)/ghc-stage$(INSTALL_GHC_STAGE).exe $(DESTDIR)$(bindir)/ghc.exe
endif

