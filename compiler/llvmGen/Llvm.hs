-- ----------------------------------------------------------------------------
-- | This module supplies bindings to generate Llvm IR from Haskell
-- (<http://www.llvm.org/docs/LangRef.html>).
--
-- Note: this module is developed in a demand driven way. It is no complete
-- LLVM binding library in Haskell, but enough to generate code for GHC.
--
-- This code is derived from code taken from the Essential Haskell Compiler
-- (EHC) project (<http://www.cs.uu.nl/wiki/Ehc/WebHome>).
--

module Llvm (

        -- * Modules, Functions and Blocks
        LlvmModule(..),

        LlvmFunction(..), LlvmFunctionDecl(..),
        LlvmFunctions, LlvmFunctionDecls,
        LlvmStatement(..), LlvmExpression(..),
        LlvmBlocks, LlvmBlock(..), LlvmBlockId,
        LlvmParamAttr(..), LlvmParameter,

        -- * Call Handling
        LlvmCallConvention(..), LlvmCallType(..), LlvmParameterListType(..),
        LlvmLinkageType(..), LlvmFuncAttr(..),

        -- * Operations and Comparisons
        LlvmCmpOp(..), LlvmMachOp(..), LlvmCastOp(..),

        -- * Variables and Type System
        LlvmVar(..), LlvmStatic(..), LlvmLit(..), LlvmType(..),
        LlvmAlias, LMGlobal, LMString, LMSection, LMAlign,

        -- ** Some basic types
        i64, i32, i16, i8, i1, i8Ptr, llvmWord, llvmWordPtr,

        -- ** Metadata types
        LlvmMetaVal(..), LlvmMetaUnamed(..), LlvmMeta(..), MetaData,

        -- ** Operations on the type system.
        isGlobal, getLitType, getLit, getName, getPlainName, getVarType,
        getLink, getStatType, getGlobalVar, getGlobalType, pVarLift, pVarLower,
        pLift, pLower, isInt, isFloat, isPointer, llvmWidthInBits,

        -- * Pretty Printing
        ppLlvmModule, ppLlvmComments, ppLlvmComment, ppLlvmGlobals,
        ppLlvmGlobal, ppLlvmFunctionDecls, ppLlvmFunctionDecl, ppLlvmFunctions,
        ppLlvmFunction, ppLlvmAlias, ppLlvmAliases, ppLlvmMetas, ppLlvmMeta,
        llvmSDoc

    ) where

import Llvm.AbsSyn
import Llvm.PpLlvm
import Llvm.Types

