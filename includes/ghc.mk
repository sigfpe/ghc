# -----------------------------------------------------------------------------
#
# (c) 2009-2012 The University of Glasgow
#
# This file is part of the GHC build system.
#
# To understand how the build system works and how to modify it, see
#      http://hackage.haskell.org/trac/ghc/wiki/Building/Architecture
#      http://hackage.haskell.org/trac/ghc/wiki/Building/Modifying
#
# -----------------------------------------------------------------------------

#
# Header files built from the configure script's findings
#
# XXX: these should go in includes/dist/build?
includes_H_CONFIG   = includes/ghcautoconf.h
includes_H_PLATFORM = includes/ghcplatform.h

#
# All header files are in includes/{one of these subdirectories}
#
includes_H_SUBDIRS += .
includes_H_SUBDIRS += rts
includes_H_SUBDIRS += rts/prof
includes_H_SUBDIRS += rts/storage
includes_H_SUBDIRS += stg

includes_H_FILES := $(wildcard $(patsubst %,includes/%/*.h,$(includes_H_SUBDIRS)))
# This isn't necessary, but it makes the paths look a little prettier
includes_H_FILES := $(subst /./,/,$(includes_H_FILES))

#
# Options
#
ifeq "$(GhcUnregisterised)" "YES"
includes_CC_OPTS += -DNO_REGS -DUSE_MINIINTERPRETER
endif

ifeq "$(GhcEnableTablesNextToCode) $(GhcUnregisterised)" "YES NO"
includes_CC_OPTS += -DTABLES_NEXT_TO_CODE
endif

includes_CC_OPTS += -Iincludes
includes_CC_OPTS += -Iincludes/dist-derivedconstants/header
includes_CC_OPTS += -Iincludes/dist-ghcconstants/header
includes_CC_OPTS += -Irts

ifneq "$(GhcWithSMP)" "YES"
includes_CC_OPTS += -DNOSMP
endif

# The fptools configure script creates the configuration header file and puts it
# in fptools/mk/config.h. We copy it down to here (without any PACKAGE_FOO
# definitions to avoid clashes), prepending some make variables specifying cpp
# platform variables.

ifneq "$(BINDIST)" "YES"

ifeq "$(PORTING_HOST)" "YES"

$(includes_H_CONFIG) :
	@echo "*** Cross-porting: please copy $(includes_H_CONFIG) from the target system"
	@exit 1

else

$(includes_H_CONFIG) : mk/config.h mk/config.mk includes/ghc.mk
	@echo "Creating $@..."
	@echo "#ifndef __GHCAUTOCONF_H__"  >$@
	@echo "#define __GHCAUTOCONF_H__" >>$@
#	Turn '#define PACKAGE_FOO "blah"' into '/* #undef PACKAGE_FOO */'.
	@sed 's,^\([	 ]*\)#[	 ]*define[	 ][	 ]*\(PACKAGE_[A-Z]*\)[	 ][ 	]*".*".*$$,\1/* #undef \2 */,' mk/config.h >> $@
	@echo "#endif /* __GHCAUTOCONF_H__ */"          >> $@
	@echo "Done."

endif

$(includes_H_PLATFORM) : includes/Makefile
	$(call removeFiles,$@)
	@echo "Creating $@..."
	@echo "#ifndef __GHCPLATFORM_H__"  >$@
	@echo "#define __GHCPLATFORM_H__" >>$@
	@echo >> $@
	@echo "#define BuildPlatform_TYPE  $(HostPlatform_CPP)" >> $@
	@echo "#define HostPlatform_TYPE   $(TargetPlatform_CPP)" >> $@
	@echo >> $@
	@echo "#define $(HostPlatform_CPP)_BUILD  1" >> $@
	@echo "#define $(TargetPlatform_CPP)_HOST  1" >> $@
	@echo >> $@
	@echo "#define $(HostArch_CPP)_BUILD_ARCH  1" >> $@
	@echo "#define $(TargetArch_CPP)_HOST_ARCH  1" >> $@
	@echo "#define BUILD_ARCH  \"$(HostArch_CPP)\"" >> $@
	@echo "#define HOST_ARCH  \"$(TargetArch_CPP)\"" >> $@
	@echo >> $@
	@echo "#define $(HostOS_CPP)_BUILD_OS  1" >> $@
	@echo "#define $(TargetOS_CPP)_HOST_OS  1" >> $@
	@echo "#define BUILD_OS  \"$(HostOS_CPP)\"" >> $@
	@echo "#define HOST_OS  \"$(TargetOS_CPP)\"" >> $@
ifeq "$(HostOS_CPP)" "irix"
	@echo "#ifndef $(IRIX_MAJOR)_HOST_OS" >> $@  
	@echo "#define $(IRIX_MAJOR)_HOST_OS  1" >> $@  
	@echo "#endif" >> $@  
endif
	@echo >> $@
	@echo "#define $(HostVendor_CPP)_BUILD_VENDOR  1" >> $@
	@echo "#define $(TargetVendor_CPP)_HOST_VENDOR  1" >> $@
	@echo "#define BUILD_VENDOR  \"$(HostVendor_CPP)\"" >> $@
	@echo "#define HOST_VENDOR  \"$(TargetVendor_CPP)\"" >> $@
ifeq "$(CC_LLVM_BACKEND)" "1"
	@echo >> $@
	@echo "#define llvm_CC_FLAVOR 1" >> $@
endif
	@echo >> $@
	@echo "/* These TARGET macros are for backwards compatibily... DO NOT USE! */" >> $@
	@echo "#define TargetPlatform_TYPE $(TargetPlatform_CPP)" >> $@
	@echo "#define $(TargetPlatform_CPP)_TARGET  1" >> $@
	@echo "#define $(TargetArch_CPP)_TARGET_ARCH  1" >> $@
	@echo "#define TARGET_ARCH  \"$(TargetArch_CPP)\"" >> $@
	@echo "#define $(TargetOS_CPP)_TARGET_OS  1" >> $@  
	@echo "#define TARGET_OS  \"$(TargetOS_CPP)\"" >> $@
	@echo "#define $(TargetVendor_CPP)_TARGET_VENDOR  1" >> $@
	@echo >> $@
	@echo "#endif /* __GHCPLATFORM_H__ */"          >> $@
	@echo "Done."

endif

# ---------------------------------------------------------------------------
# Make DerivedConstants.h for the compiler

includes_DERIVEDCONSTANTS = includes/dist-derivedconstants/header/DerivedConstants.h

ifeq "$(PORTING_HOST)" "YES"

DerivedConstants.h :
	@echo "*** Cross-porting: please copy DerivedConstants.h from the target system"
	@exit 1

else

ifneq "$(TARGETPLATFORM)dd" "$(HOSTPLATFORM)"
includes/dist-derivedconstants/build/Capability.cross.h: rts/Capability.h | $$(dir $$@)/.
	$(CC_STAGE1) -E -DPROFILING -DTHREADED_RTS $(CONF_CPP_OPTS_STAGE1) $(rts_CC_OPTS) $< > $@
includes/dist-derivedconstants/build/Rts.cross.h: includes/Rts.h | $$(dir $$@)/.
	$(CC_STAGE1) -E -DPROFILING -DTHREADED_RTS $(CONF_CPP_OPTS_STAGE1) $(includes_CC_OPTS) $< > $@
includes/dist-derivedconstants/build/mkDerivedConstants.cross.c: includes/mkDerivedConstants.cross.awk
includes/dist-derivedconstants/build/mkDerivedConstants.cross.c: includes/dist-derivedconstants/build/Rts.cross.h includes/dist-derivedconstants/build/Capability.cross.h
	awk -f includes/mkDerivedConstants.cross.awk $^ > $@
includes/dist-derivedconstants/build/mkDerivedConstants.cross.o: includes/dist-derivedconstants/build/mkDerivedConstants.cross.c
	$(CC_STAGE1) -c -DPROFILING -DTHREADED_RTS $(CONF_CPP_OPTS_STAGE1) $(rts_CC_OPTS) $(includes_CC_OPTS) -fcommon $< -o $@
includes/dist-derivedconstants/build/SizeMacros.h: includes/mkSizeMacros.cross.awk
includes/dist-derivedconstants/build/SizeMacros.h: includes/dist-derivedconstants/build/mkDerivedConstants.cross.o | $$(dir $$@)/.
	$(NM) $< | $(SORT) | awk -f includes/mkSizeMacros.cross.awk > $@

includes_dist-derivedconstants_C_SRCS = mkDerivedConstants.c
# XXX NM_STAGE1 AWK
includes_dist-derivedconstants_PROG   = mkDerivedConstants$(exeext)

includes/dist-derivedconstants/build/mkDerivedConstants$(exeext) : includes/dist-derivedconstants/build/SizeMacros.h
includes/dist-derivedconstants/build/mkDerivedConstants$(exeext) : includes/mkDerivedConstants.c
	$(CC_STAGE0) $(CONF_CPP_OPTS_STAGE0) $(rts_CC_OPTS) $(includes_CC_OPTS) $< -o $@

$(INPLACE_BIN)/mkDerivedConstants$(exeext) : includes/dist-ghcconstants/build/mkDerivedConstants$(exeext)
	$(CP) $< $@
else
includes/dist-derivedconstants/build/SizeMacros.h : | $$(dir $$@)/.
	@echo "#define OFFSET(s_type, field) ((size_t)&(((s_type*)0)->field))" > $@
	@echo "#define FIELD_SIZE(s_type, field) ((unsigned long)sizeof(((s_type*)0)->field))" >> $@
	@echo "#define TYPE_SIZE(type) (sizeof(type))" >> $@
	@echo "#define prof_ccs prof.ccs" >> $@
	@echo "#define prof_cccs prof.cccs" >> $@
	@echo "#define prof_hp_ldvw prof.hp.ldvw" >> $@
	@echo "#define DebugFlags_apply DebugFlags.apply" >> $@
	@echo "#define DebugFlags_sanity DebugFlags.sanity" >> $@
	@echo "#define DebugFlags_weak DebugFlags.weak" >> $@
	@echo "#define GcFlags_initialStkSize GcFlags.initialStkSize" >> $@
	@echo "#define MiscFlags_tickInterval MiscFlags.tickInterval" >> $@
	@echo "#define b_bitmap b.bitmap" >> $@
	@echo >> $@

includes_dist-derivedconstants_C_SRCS = mkDerivedConstants.c
includes_dist-derivedconstants_CC_OPTS = -Iincludes/dist-derivedconstants/build
includes_dist-derivedconstants_PROG   = mkDerivedConstants$(exeext)

$(eval $(call build-prog,includes,dist-derivedconstants,0))

$(includes_dist-derivedconstants_depfile_c_asm) : $(includes_H_CONFIG) $(includes_H_PLATFORM) $(includes_H_FILES) $$(rts_H_FILES)
includes/dist-derivedconstants/build/mkDerivedConstants.o : includes/dist-derivedconstants/build/SizeMacros.h $(includes_H_CONFIG) $(includes_H_PLATFORM)
endif

ifneq "$(BINDIST)" "YES"
$(includes_DERIVEDCONSTANTS) : $(INPLACE_BIN)/mkDerivedConstants$(exeext) | $$(dir $$@)/.
	./$< >$@
endif

endif

# -----------------------------------------------------------------------------
#

includes_GHCCONSTANTS = includes/dist-ghcconstants/header/GHCConstants.h

ifeq "$(PORTING_HOST)" "YES"

$(includes_GHCCONSTANTS) :
	@echo "*** Cross-porting: please copy DerivedConstants.h from the target system"
	@exit 1

else

ifneq "$(TARGETPLATFORM)dd" "$(HOSTPLATFORM)"
includes/dist-ghcconstants/build/mkDerivedConstants$(exeext) : includes/dist-derivedconstants/build/SizeMacros.h
includes/dist-ghcconstants/build/mkDerivedConstants$(exeext) : includes/mkDerivedConstants.c
	$(CC_STAGE0) -DGEN_HASKELL -Iincludes/dist-derivedconstants/build $(CONF_CPP_OPTS_STAGE0) $(rts_CC_OPTS) $(includes_CC_OPTS) $< -o $@
$(INPLACE_BIN)/mkGHCConstants$(exeext) : includes/dist-ghcconstants/build/mkDerivedConstants$(exeext)
	$(CP) $< $@
else
includes_dist-ghcconstants_C_SRCS = mkDerivedConstants.c
includes_dist-ghcconstants_PROG   = mkGHCConstants$(exeext)
includes_dist-ghcconstants_CC_OPTS = -DGEN_HASKELL -Iincludes/dist-derivedconstants/build

$(eval $(call build-prog,includes,dist-ghcconstants,0))

ifneq "$(BINDIST)" "YES"
$(includes_dist-ghcconstants_depfile_c_asm) : $(includes_H_CONFIG) $(includes_H_PLATFORM) $(includes_H_FILES) $$(rts_H_FILES)

includes/dist-ghcconstants/build/mkDerivedConstants.o : includes/dist-derivedconstants/build/SizeMacros.h $(includes_H_CONFIG) $(includes_H_PLATFORM)

endif

endif

$(includes_GHCCONSTANTS) : $(INPLACE_BIN)/mkGHCConstants$(exeext) | $$(dir $$@)/.
	./$< >$@

endif

# ---------------------------------------------------------------------------
# Install all header files

$(eval $(call clean-target,includes,,\
  $(includes_H_CONFIG) $(includes_H_PLATFORM) \
  $(includes_GHCCONSTANTS) $(includes_DERIVEDCONSTANTS)))

$(eval $(call all-target,includes,,\
  $(includes_H_CONFIG) $(includes_H_PLATFORM) \
  $(includes_GHCCONSTANTS) $(includes_DERIVEDCONSTANTS)))

install: install_includes

.PHONY: install_includes
install_includes :
	$(call INSTALL_DIR,"$(DESTDIR)$(ghcheaderdir)")
	$(foreach d,$(includes_H_SUBDIRS), \
	    $(call INSTALL_DIR,"$(DESTDIR)$(ghcheaderdir)/$d") && \
	    $(call INSTALL_HEADER,$(INSTALL_OPTS),includes/$d/*.h,"$(DESTDIR)$(ghcheaderdir)/$d/") && \
	) true
	$(call INSTALL_HEADER,$(INSTALL_OPTS),$(includes_H_CONFIG) $(includes_H_PLATFORM) $(includes_GHCCONSTANTS) $(includes_DERIVEDCONSTANTS),"$(DESTDIR)$(ghcheaderdir)/")

