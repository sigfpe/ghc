%
% (c) The University of Glasgow 2006
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%
\section[TcType]{Types used in the typechecker}

This module provides the Type interface for front-end parts of the 
compiler.  These parts 

	* treat "source types" as opaque: 
		newtypes, and predicates are meaningful. 
	* look through usage types

The "tc" prefix is for "TypeChecker", because the type checker
is the principal client.

\begin{code}
{-# OPTIONS -fno-warn-tabs #-}
-- The above warning supression flag is a temporary kludge.
-- While working on this module you are encouraged to remove it and
-- detab the module (please do the detabbing in a separate patch). See
--     http://hackage.haskell.org/trac/ghc/wiki/Commentary/CodingStyle#TabsvsSpaces
-- for details

module TcType (
  --------------------------------
  -- Types 
  TcType, TcSigmaType, TcRhoType, TcTauType, TcPredType, TcThetaType, 
  TcTyVar, TcTyVarSet, TcKind, TcCoVar,

  --------------------------------
  -- MetaDetails
  UserTypeCtxt(..), pprUserTypeCtxt,
  TcTyVarDetails(..), pprTcTyVarDetails, vanillaSkolemTv, superSkolemTv,
  MetaDetails(Flexi, Indirect), MetaInfo(..), 
  isImmutableTyVar, isSkolemTyVar, isMetaTyVar,  isMetaTyVarTy, isTyVarTy,
  isSigTyVar, isOverlappableTyVar,  isTyConableTyVar,
  isAmbiguousTyVar, metaTvRef, 
  isFlexi, isIndirect, isRuntimeUnkSkol,

  --------------------------------
  -- Builders
  mkPhiTy, mkSigmaTy, 

  --------------------------------
  -- Splitters  
  -- These are important because they do not look through newtypes
  tcView,
  tcSplitForAllTys, tcSplitPhiTy, tcSplitPredFunTy_maybe,
  tcSplitFunTy_maybe, tcSplitFunTys, tcFunArgTy, tcFunResultTy, tcSplitFunTysN,
  tcSplitTyConApp, tcSplitTyConApp_maybe, tcTyConAppTyCon, tcTyConAppArgs,
  tcSplitAppTy_maybe, tcSplitAppTy, tcSplitAppTys, repSplitAppTy_maybe,
  tcInstHeadTyNotSynonym, tcInstHeadTyAppAllTyVars,
  tcGetTyVar_maybe, tcGetTyVar,
  tcSplitSigmaTy, tcDeepSplitSigmaTy_maybe,  

  ---------------------------------
  -- Predicates. 
  -- Again, newtypes are opaque
  eqType, eqTypes, eqPred, cmpType, cmpTypes, cmpPred, eqTypeX,
  pickyEqType, eqKind, 
  isSigmaTy, isOverloadedTy,
  isDoubleTy, isFloatTy, isIntTy, isWordTy, isStringTy,
  isIntegerTy, isBoolTy, isUnitTy, isCharTy,
  isTauTy, isTauTyCon, tcIsTyVarTy, tcIsForAllTy, 
  isSynFamilyTyConApp,
  isPredTy, isTyVarClassPred,
  shallowPredTypePredTree,
  
  ---------------------------------
  -- Misc type manipulators
  deNoteType,
  orphNamesOfType, orphNamesOfDFunHead, orphNamesOfCo,
  getDFunTyKey,
  evVarPred_maybe, evVarPred,

  ---------------------------------
  -- Predicate types  
  mkMinimalBySCs, transSuperClasses, immSuperClasses,
  
  -- * Finding type instances
  tcTyFamInsts,

  -- * Finding "exact" (non-dead) type variables
  exactTyVarsOfType, exactTyVarsOfTypes,

  -- * Tidying type related things up for printing
  tidyType,      tidyTypes,
  tidyOpenType,  tidyOpenTypes,
  tidyOpenKind,
  tidyTyVarBndr, tidyFreeTyVars,
  tidyOpenTyVar, tidyOpenTyVars,
  tidyTyVarOcc,
  tidyTopType,
  tidyKind, 
  tidyCo, tidyCos,

  ---------------------------------
  -- Foreign import and export
  isFFIArgumentTy,     -- :: DynFlags -> Safety -> Type -> Bool
  isFFIImportResultTy, -- :: DynFlags -> Type -> Bool
  isFFIExportResultTy, -- :: Type -> Bool
  isFFIExternalTy,     -- :: Type -> Bool
  isFFIDynArgumentTy,  -- :: Type -> Bool
  isFFIDynResultTy,    -- :: Type -> Bool
  isFFIPrimArgumentTy, -- :: DynFlags -> Type -> Bool
  isFFIPrimResultTy,   -- :: DynFlags -> Type -> Bool
  isFFILabelTy,        -- :: Type -> Bool
  isFFIDotnetTy,       -- :: DynFlags -> Type -> Bool
  isFFIDotnetObjTy,    -- :: Type -> Bool
  isFFITy,	       -- :: Type -> Bool
  isFunPtrTy,          -- :: Type -> Bool
  tcSplitIOType_maybe, -- :: Type -> Maybe Type  

  --------------------------------
  -- Rexported from Kind
  Kind, typeKind,
  unliftedTypeKind, liftedTypeKind, argTypeKind,
  openTypeKind, constraintKind, mkArrowKind, mkArrowKinds, 
  isLiftedTypeKind, isUnliftedTypeKind, isSubOpenTypeKind, 
  isSubArgTypeKind, isSubKind, splitKindFunTys, defaultKind,
  mkMetaKindVar,

  --------------------------------
  -- Rexported from Type
  Type, PredType, ThetaType,
  mkForAllTy, mkForAllTys, 
  mkFunTy, mkFunTys, zipFunTys, 
  mkTyConApp, mkAppTy, mkAppTys, applyTy, applyTys,
  mkTyVarTy, mkTyVarTys, mkTyConTy,

  isClassPred, isEqPred, isIPPred,
  mkClassPred, mkIPPred,
  isDictLikeTy,
  tcSplitDFunTy, tcSplitDFunHead, 
  mkEqPred,

  -- Type substitutions
  TvSubst(..), 	-- Representation visible to a few friends
  TvSubstEnv, emptyTvSubst, 
  mkOpenTvSubst, zipOpenTvSubst, zipTopTvSubst, 
  mkTopTvSubst, notElemTvSubst, unionTvSubst,
  getTvSubstEnv, setTvSubstEnv, getTvInScope, extendTvInScope, 
  Type.lookupTyVar, Type.extendTvSubst, Type.substTyVarBndr,
  extendTvSubstList, isInScope, mkTvSubst, zipTyEnv,
  Type.substTy, substTys, substTyWith, substTheta, substTyVar, substTyVars, 

  isUnLiftedType,	-- Source types are always lifted
  isUnboxedTupleType,	-- Ditto
  isPrimitiveType, 

  tyVarsOfType, tyVarsOfTypes,
  tcTyVarsOfType, tcTyVarsOfTypes,

  pprKind, pprParendKind,
  pprType, pprParendType, pprTypeApp, pprTyThingCategory,
  pprTheta, pprThetaArrowTy, pprClassPred

  ) where

#include "HsVersions.h"

-- friends:
import Kind
import TypeRep
import Class
import Var
import ForeignCall
import VarSet
import Coercion
import Type
import TyCon

-- others:
import DynFlags
import Name hiding (varName)
import NameSet
import VarEnv
import PrelNames
import TysWiredIn
import BasicTypes
import Util
import Maybes
import ListSetOps
import Outputable
import FastString

import Data.List( mapAccumL )
import Data.IORef
\end{code}

%************************************************************************
%*									*
\subsection{Types}
%*									*
%************************************************************************

The type checker divides the generic Type world into the 
following more structured beasts:

sigma ::= forall tyvars. phi
	-- A sigma type is a qualified type
	--
	-- Note that even if 'tyvars' is empty, theta
	-- may not be: e.g.   (?x::Int) => Int

	-- Note that 'sigma' is in prenex form:
	-- all the foralls are at the front.
	-- A 'phi' type has no foralls to the right of
	-- an arrow

phi :: theta => rho

rho ::= sigma -> rho
     |  tau

-- A 'tau' type has no quantification anywhere
-- Note that the args of a type constructor must be taus
tau ::= tyvar
     |  tycon tau_1 .. tau_n
     |  tau_1 tau_2
     |  tau_1 -> tau_2

-- In all cases, a (saturated) type synonym application is legal,
-- provided it expands to the required form.

\begin{code}
type TcTyVar = TyVar  	-- Used only during type inference
type TcCoVar = CoVar  	-- Used only during type inference; mutable
type TcType = Type 	-- A TcType can have mutable type variables
	-- Invariant on ForAllTy in TcTypes:
	-- 	forall a. T
	-- a cannot occur inside a MutTyVar in T; that is,
	-- T is "flattened" before quantifying over a

-- These types do not have boxy type variables in them
type TcPredType     = PredType
type TcThetaType    = ThetaType
type TcSigmaType    = TcType
type TcRhoType      = TcType
type TcTauType      = TcType
type TcKind         = Kind
type TcTyVarSet     = TyVarSet
\end{code}


%************************************************************************
%*									*
\subsection{TyVarDetails}
%*									*
%************************************************************************

TyVarDetails gives extra info about type variables, used during type
checking.  It's attached to mutable type variables only.
It's knot-tied back to Var.lhs.  There is no reason in principle
why Var.lhs shouldn't actually have the definition, but it "belongs" here.


Note [Signature skolems]
~~~~~~~~~~~~~~~~~~~~~~~~
Consider this

  x :: [a]
  y :: b
  (x,y,z) = ([y,z], z, head x)

Here, x and y have type sigs, which go into the environment.  We used to
instantiate their types with skolem constants, and push those types into
the RHS, so we'd typecheck the RHS with type
	( [a*], b*, c )
where a*, b* are skolem constants, and c is an ordinary meta type varible.

The trouble is that the occurrences of z in the RHS force a* and b* to 
be the *same*, so we can't make them into skolem constants that don't unify
with each other.  Alas.

One solution would be insist that in the above defn the programmer uses
the same type variable in both type signatures.  But that takes explanation.

The alternative (currently implemented) is to have a special kind of skolem
constant, SigTv, which can unify with other SigTvs.  These are *not* treated
as rigid for the purposes of GADTs.  And they are used *only* for pattern
bindings and mutually recursive function bindings.  See the function
TcBinds.tcInstSig, and its use_skols parameter.


\begin{code}
-- A TyVarDetails is inside a TyVar
data TcTyVarDetails
  = SkolemTv      -- A skolem
       Bool       -- True <=> this skolem type variable can be overlapped
                  --          when looking up instances
                  -- See Note [Binding when looking up instances] in InstEnv

  | RuntimeUnk    -- Stands for an as-yet-unknown type in the GHCi
                  -- interactive context

  | FlatSkol TcType
           -- The "skolem" obtained by flattening during
    	   -- constraint simplification
    
           -- In comments we will use the notation alpha[flat = ty]
           -- to represent a flattening skolem variable alpha
           -- identified with type ty.
          
  | MetaTv MetaInfo (IORef MetaDetails)

vanillaSkolemTv, superSkolemTv :: TcTyVarDetails
-- See Note [Binding when looking up instances] in InstEnv
vanillaSkolemTv = SkolemTv False  -- Might be instantiated
superSkolemTv   = SkolemTv True   -- Treat this as a completely distinct type

data MetaDetails
  = Flexi  -- Flexi type variables unify to become Indirects  
  | Indirect TcType

instance Outputable MetaDetails where
  ppr Flexi         = ptext (sLit "Flexi")
  ppr (Indirect ty) = ptext (sLit "Indirect") <+> ppr ty

data MetaInfo
   = TauTv	   -- This MetaTv is an ordinary unification variable
     		   -- A TauTv is always filled in with a tau-type, which
		   -- never contains any ForAlls 

   | SigTv 	   -- A variant of TauTv, except that it should not be
		   -- unified with a type, only with a type variable
		   -- SigTvs are only distinguished to improve error messages
		   --      see Note [Signature skolems]        
		   --      The MetaDetails, if filled in, will 
		   --      always be another SigTv or a SkolemTv

   | TcsTv	   -- A MetaTv allocated by the constraint solver
     		   -- Its particular property is that it is always "touchable"
		   -- Nevertheless, the constraint solver has to try to guess
		   -- what type to instantiate it to

-------------------------------------
-- UserTypeCtxt describes the origin of the polymorphic type
-- in the places where we need to an expression has that type

data UserTypeCtxt
  = FunSigCtxt Name	-- Function type signature
			-- Also used for types in SPECIALISE pragmas
  | InfSigCtxt Name	-- Inferred type for function
  | ExprSigCtxt		-- Expression type signature
  | ConArgCtxt Name	-- Data constructor argument
  | TySynCtxt Name	-- RHS of a type synonym decl
  | LamPatSigCtxt		-- Type sig in lambda pattern
			-- 	f (x::t) = ...
  | BindPatSigCtxt	-- Type sig in pattern binding pattern
			--	(x::t, y) = e
  | ResSigCtxt		-- Result type sig
			-- 	f x :: t = ....
  | ForSigCtxt Name	-- Foreign import or export signature
  | DefaultDeclCtxt	-- Types in a default declaration
  | InstDeclCtxt        -- An instance declaration
  | SpecInstCtxt	-- SPECIALISE instance pragma
  | ThBrackCtxt		-- Template Haskell type brackets [t| ... |]
  | GenSigCtxt          -- Higher-rank or impredicative situations
                        -- e.g. (f e) where f has a higher-rank type
                        -- We might want to elaborate this
  | GhciCtxt            -- GHCi command :kind <type>

  | ClassSCCtxt Name	-- Superclasses of a class
  | SigmaCtxt		-- Theta part of a normal for-all type
			--	f :: <S> => a -> a
  | DataTyCtxt Name	-- Theta part of a data decl
			--	data <S> => T a = MkT a
\end{code}


-- Notes re TySynCtxt
-- We allow type synonyms that aren't types; e.g.  type List = []
--
-- If the RHS mentions tyvars that aren't in scope, we'll 
-- quantify over them:
--	e.g. 	type T = a->a
-- will become	type T = forall a. a->a
--
-- With gla-exts that's right, but for H98 we should complain. 

---------------------------------
-- Kind variables:
\begin{code}
mkKindName :: Unique -> Name
mkKindName unique = mkSystemName unique kind_var_occ

mkMetaKindVar :: Unique -> IORef MetaDetails -> MetaKindVar
mkMetaKindVar u r
  = mkTcTyVar (mkKindName u)
              tySuperKind  -- not sure this is right,
                            -- do we need kind vars for
                            -- coercions?
              (MetaTv TauTv r)

kind_var_occ :: OccName	-- Just one for all MetaKindVars
			-- They may be jiggled by tidying
kind_var_occ = mkOccName tvName "k"
\end{code}

%************************************************************************
%*									*
		Pretty-printing
%*									*
%************************************************************************

\begin{code}
pprTcTyVarDetails :: TcTyVarDetails -> SDoc
-- For debugging
pprTcTyVarDetails (SkolemTv True)  = ptext (sLit "ssk")
pprTcTyVarDetails (SkolemTv False) = ptext (sLit "sk")
pprTcTyVarDetails (RuntimeUnk {})  = ptext (sLit "rt")
pprTcTyVarDetails (FlatSkol {})    = ptext (sLit "fsk")
pprTcTyVarDetails (MetaTv TauTv _) = ptext (sLit "tau")
pprTcTyVarDetails (MetaTv TcsTv _) = ptext (sLit "tcs")
pprTcTyVarDetails (MetaTv SigTv _) = ptext (sLit "sig")

pprUserTypeCtxt :: UserTypeCtxt -> SDoc
pprUserTypeCtxt (InfSigCtxt n)    = ptext (sLit "the inferred type for") <+> quotes (ppr n)
pprUserTypeCtxt (FunSigCtxt n)    = ptext (sLit "the type signature for") <+> quotes (ppr n)
pprUserTypeCtxt ExprSigCtxt       = ptext (sLit "an expression type signature")
pprUserTypeCtxt (ConArgCtxt c)    = ptext (sLit "the type of the constructor") <+> quotes (ppr c)
pprUserTypeCtxt (TySynCtxt c)     = ptext (sLit "the RHS of the type synonym") <+> quotes (ppr c)
pprUserTypeCtxt ThBrackCtxt       = ptext (sLit "a Template Haskell quotation [t|...|]")
pprUserTypeCtxt LamPatSigCtxt     = ptext (sLit "a pattern type signature")
pprUserTypeCtxt BindPatSigCtxt    = ptext (sLit "a pattern type signature")
pprUserTypeCtxt ResSigCtxt        = ptext (sLit "a result type signature")
pprUserTypeCtxt (ForSigCtxt n)    = ptext (sLit "the foreign declaration for") <+> quotes (ppr n)
pprUserTypeCtxt DefaultDeclCtxt   = ptext (sLit "a type in a `default' declaration")
pprUserTypeCtxt InstDeclCtxt      = ptext (sLit "an instance declaration")
pprUserTypeCtxt SpecInstCtxt      = ptext (sLit "a SPECIALISE instance pragma")
pprUserTypeCtxt GenSigCtxt        = ptext (sLit "a type expected by the context")
pprUserTypeCtxt GhciCtxt          = ptext (sLit "a type in a GHCi command")
pprUserTypeCtxt (ClassSCCtxt c)   = ptext (sLit "the super-classes of class") <+> quotes (ppr c)
pprUserTypeCtxt SigmaCtxt         = ptext (sLit "the context of a polymorphic type")
pprUserTypeCtxt (DataTyCtxt tc)   = ptext (sLit "the context of the data type declaration for") <+> quotes (ppr tc)
\end{code}


%************************************************************************
%*									*
\subsection{TidyType}
%*									*
%************************************************************************

Tidying is here becuase it has a special case for FlatSkol

\begin{code}
-- | This tidies up a type for printing in an error message, or in
-- an interface file.
-- 
-- It doesn't change the uniques at all, just the print names.
tidyTyVarBndr :: TidyEnv -> TyVar -> (TidyEnv, TyVar)
tidyTyVarBndr tidy_env@(occ_env, subst) tyvar
  = case tidyOccName occ_env occ1 of
      (tidy', occ') -> ((tidy', subst'), tyvar')
	where
          subst' = extendVarEnv subst tyvar tyvar'
          tyvar' = setTyVarKind (setTyVarName tyvar name') kind'
          name'  = tidyNameOcc name occ'
          kind'  = tidyKind tidy_env (tyVarKind tyvar)
  where
    name = tyVarName tyvar
    occ  = getOccName name
    -- System Names are for unification variables;
    -- when we tidy them we give them a trailing "0" (or 1 etc)
    -- so that they don't take precedence for the un-modified name
    occ1 | isSystemName name = mkTyVarOcc (occNameString occ ++ "0")
         | otherwise         = occ


---------------
tidyFreeTyVars :: TidyEnv -> TyVarSet -> TidyEnv
-- ^ Add the free 'TyVar's to the env in tidy form,
-- so that we can tidy the type they are free in
tidyFreeTyVars (full_occ_env, var_env) tyvars 
  = fst (tidyOpenTyVars (trimmed_occ_env, var_env) tv_list)

  where
    tv_list = varSetElems tyvars
    
    trimmed_occ_env = foldr mk_occ_env emptyOccEnv tv_list
      -- The idea here is that we restrict the new TidyEnv to the 
      -- _free_ vars of the type, so that we don't gratuitously rename
      -- the _bound_ variables of the type

    mk_occ_env :: TyVar -> TidyOccEnv -> TidyOccEnv
    mk_occ_env tv env 
       = case lookupOccEnv full_occ_env occ of
            Just n  -> extendOccEnv env occ n
            Nothing -> env
       where
         occ = getOccName tv

---------------
tidyOpenTyVars :: TidyEnv -> [TyVar] -> (TidyEnv, [TyVar])
tidyOpenTyVars env tyvars = mapAccumL tidyOpenTyVar env tyvars

---------------
tidyOpenTyVar :: TidyEnv -> TyVar -> (TidyEnv, TyVar)
-- ^ Treat a new 'TyVar' as a binder, and give it a fresh tidy name
-- using the environment if one has not already been allocated. See
-- also 'tidyTyVarBndr'
tidyOpenTyVar env@(_, subst) tyvar
  = case lookupVarEnv subst tyvar of
	Just tyvar' -> (env, tyvar')		-- Already substituted
	Nothing	    -> tidyTyVarBndr env tyvar	-- Treat it as a binder

---------------
tidyTyVarOcc :: TidyEnv -> TyVar -> Type
tidyTyVarOcc env@(_, subst) tv
  = case lookupVarEnv subst tv of
	Nothing  -> expand tv
	Just tv' -> expand tv'
  where
    -- Expand FlatSkols, the skolems introduced by flattening process
    -- We don't want to show them in type error messages
    expand tv | isTcTyVar tv
              , FlatSkol ty <- tcTyVarDetails tv
              = WARN( True, text "I DON'T THINK THIS SHOULD EVER HAPPEN" <+> ppr tv <+> ppr ty )
                tidyType env ty
              | otherwise
              = TyVarTy tv

---------------
tidyTypes :: TidyEnv -> [Type] -> [Type]
tidyTypes env tys = map (tidyType env) tys

---------------
tidyType :: TidyEnv -> Type -> Type
tidyType env (TyVarTy tv)	  = tidyTyVarOcc env tv
tidyType env (TyConApp tycon tys) = let args = tidyTypes env tys
 		                    in args `seqList` TyConApp tycon args
tidyType env (AppTy fun arg)	  = (AppTy $! (tidyType env fun)) $! (tidyType env arg)
tidyType env (FunTy fun arg)	  = (FunTy $! (tidyType env fun)) $! (tidyType env arg)
tidyType env (ForAllTy tv ty)	  = ForAllTy tvp $! (tidyType envp ty)
			          where
			            (envp, tvp) = tidyTyVarBndr env tv

---------------
-- | Grabs the free type variables, tidies them
-- and then uses 'tidyType' to work over the type itself
tidyOpenType :: TidyEnv -> Type -> (TidyEnv, Type)
tidyOpenType env ty
  = (env', tidyType env' ty)
  where
    env' = tidyFreeTyVars env (tyVarsOfType ty)

---------------
tidyOpenTypes :: TidyEnv -> [Type] -> (TidyEnv, [Type])
tidyOpenTypes env tys = mapAccumL tidyOpenType env tys

---------------
-- | Calls 'tidyType' on a top-level type (i.e. with an empty tidying environment)
tidyTopType :: Type -> Type
tidyTopType ty = tidyType emptyTidyEnv ty

---------------
tidyOpenKind :: TidyEnv -> Kind -> (TidyEnv, Kind)
tidyOpenKind = tidyOpenType

tidyKind :: TidyEnv -> Kind -> Kind
tidyKind = tidyType
\end{code}

%************************************************************************
%*									*
                            Tidying coercions
%*									*
%************************************************************************

\begin{code}
tidyCo :: TidyEnv -> Coercion -> Coercion
tidyCo env@(_, subst) co
  = go co
  where
    go (Refl ty)             = Refl (tidyType env ty)
    go (TyConAppCo tc cos)   = let args = map go cos
                               in args `seqList` TyConAppCo tc args
    go (AppCo co1 co2)       = (AppCo $! go co1) $! go co2
    go (ForAllCo tv co)      = ForAllCo tvp $! (tidyCo envp co)
                               where
                                 (envp, tvp) = tidyTyVarBndr env tv
    go (CoVarCo cv)          = case lookupVarEnv subst cv of
                                 Nothing  -> CoVarCo cv
                                 Just cv' -> CoVarCo cv'
    go (AxiomInstCo con cos) = let args = tidyCos env cos
                               in  args `seqList` AxiomInstCo con args
    go (UnsafeCo ty1 ty2)    = (UnsafeCo $! tidyType env ty1) $! tidyType env ty2
    go (SymCo co)            = SymCo $! go co
    go (TransCo co1 co2)     = (TransCo $! go co1) $! go co2
    go (NthCo d co)          = NthCo d $! go co
    go (InstCo co ty)        = (InstCo $! go co) $! tidyType env ty

tidyCos :: TidyEnv -> [Coercion] -> [Coercion]
tidyCos env = map (tidyCo env)
\end{code}

%************************************************************************
%*                  *
    Finding type family instances
%*                  *
%************************************************************************

\begin{code}

-- | Finds type family instances occuring in a type after expanding synonyms.
tcTyFamInsts :: Type -> [(TyCon, [Type])]
tcTyFamInsts ty 
  | Just exp_ty <- tcView ty    = tcTyFamInsts exp_ty
tcTyFamInsts (TyVarTy _)          = []
tcTyFamInsts (TyConApp tc tys) 
  | isSynFamilyTyCon tc           = [(tc, tys)]
  | otherwise                   = concat (map tcTyFamInsts tys)
tcTyFamInsts (FunTy ty1 ty2)      = tcTyFamInsts ty1 ++ tcTyFamInsts ty2
tcTyFamInsts (AppTy ty1 ty2)      = tcTyFamInsts ty1 ++ tcTyFamInsts ty2
tcTyFamInsts (ForAllTy _ ty)      = tcTyFamInsts ty
\end{code}

%************************************************************************
%*                  *
          The "exact" free variables of a type
%*                  *
%************************************************************************

Note [Silly type synonym]
~~~~~~~~~~~~~~~~~~~~~~~~~
Consider
  type T a = Int
What are the free tyvars of (T x)?  Empty, of course!  
Here's the example that Ralf Laemmel showed me:
  foo :: (forall a. C u a -> C u a) -> u
  mappend :: Monoid u => u -> u -> u

  bar :: Monoid u => u
  bar = foo (\t -> t `mappend` t)
We have to generalise at the arg to f, and we don't
want to capture the constraint (Monad (C u a)) because
it appears to mention a.  Pretty silly, but it was useful to him.

exactTyVarsOfType is used by the type checker to figure out exactly
which type variables are mentioned in a type.  It's also used in the
smart-app checking code --- see TcExpr.tcIdApp

On the other hand, consider a *top-level* definition
  f = (\x -> x) :: T a -> T a
If we don't abstract over 'a' it'll get fixed to GHC.Prim.Any, and then
if we have an application like (f "x") we get a confusing error message 
involving Any.  So the conclusion is this: when generalising
  - at top level use tyVarsOfType
  - in nested bindings use exactTyVarsOfType
See Trac #1813 for example.

\begin{code}
exactTyVarsOfType :: Type -> TyVarSet
-- Find the free type variables (of any kind)
-- but *expand* type synonyms.  See Note [Silly type synonym] above.
exactTyVarsOfType ty
  = go ty
  where
    go ty | Just ty' <- tcView ty = go ty'  -- This is the key line
    go (TyVarTy tv)         = unitVarSet tv
    go (TyConApp _ tys)     = exactTyVarsOfTypes tys
    go (FunTy arg res)      = go arg `unionVarSet` go res
    go (AppTy fun arg)      = go fun `unionVarSet` go arg
    go (ForAllTy tyvar ty)  = delVarSet (go ty) tyvar

exactTyVarsOfTypes :: [Type] -> TyVarSet
exactTyVarsOfTypes tys = foldr (unionVarSet . exactTyVarsOfType) emptyVarSet tys
\end{code}

%************************************************************************
%*									*
		Predicates
%*									*
%************************************************************************

\begin{code}
isImmutableTyVar :: TyVar -> Bool

isImmutableTyVar tv
  | isTcTyVar tv = isSkolemTyVar tv
  | otherwise    = True

isTyConableTyVar, isSkolemTyVar, isOverlappableTyVar,
  isMetaTyVar, isAmbiguousTyVar :: TcTyVar -> Bool 

isTyConableTyVar tv	
	-- True of a meta-type variable that can be filled in 
	-- with a type constructor application; in particular,
	-- not a SigTv
  = ASSERT( isTcTyVar tv) 
    case tcTyVarDetails tv of
	MetaTv SigTv _ -> False
	_              -> True
	
isSkolemTyVar tv 
  = ASSERT2( isTcTyVar tv, ppr tv )
    case tcTyVarDetails tv of
        SkolemTv {}   -> True
        FlatSkol {}   -> True
        RuntimeUnk {} -> True
        MetaTv {}     -> False

isOverlappableTyVar tv
  = ASSERT( isTcTyVar tv )
    case tcTyVarDetails tv of
        SkolemTv overlappable -> overlappable
        _                     -> False

isMetaTyVar tv 
  = ASSERT2( isTcTyVar tv, ppr tv )
    case tcTyVarDetails tv of
	MetaTv {} -> True
	_         -> False

-- isAmbiguousTyVar is used only when reporting type errors
-- It picks out variables that are unbound, namely meta
-- type variables and the RuntimUnk variables created by
-- RtClosureInspect.zonkRTTIType.  These are "ambiguous" in
-- the sense that they stand for an as-yet-unknown type
isAmbiguousTyVar tv 
  = ASSERT2( isTcTyVar tv, ppr tv )
    case tcTyVarDetails tv of
	MetaTv {}     -> True
	RuntimeUnk {} -> True
	_             -> False

isMetaTyVarTy :: TcType -> Bool
isMetaTyVarTy (TyVarTy tv) = isMetaTyVar tv
isMetaTyVarTy _            = False

isSigTyVar :: Var -> Bool
isSigTyVar tv 
  = ASSERT( isTcTyVar tv )
    case tcTyVarDetails tv of
	MetaTv SigTv _ -> True
	_              -> False

metaTvRef :: TyVar -> IORef MetaDetails
metaTvRef tv 
  = ASSERT2( isTcTyVar tv, ppr tv )
    case tcTyVarDetails tv of
	MetaTv _ ref -> ref
	_          -> pprPanic "metaTvRef" (ppr tv)

isFlexi, isIndirect :: MetaDetails -> Bool
isFlexi Flexi = True
isFlexi _     = False

isIndirect (Indirect _) = True
isIndirect _            = False

isRuntimeUnkSkol :: TyVar -> Bool
-- Called only in TcErrors; see Note [Runtime skolems] there
isRuntimeUnkSkol x
  | isTcTyVar x, RuntimeUnk <- tcTyVarDetails x = True
  | otherwise                                   = False
\end{code}


%************************************************************************
%*									*
\subsection{Tau, sigma and rho}
%*									*
%************************************************************************

\begin{code}
mkSigmaTy :: [TyVar] -> [PredType] -> Type -> Type
mkSigmaTy tyvars theta tau = mkForAllTys tyvars (mkPhiTy theta tau)

mkPhiTy :: [PredType] -> Type -> Type
mkPhiTy theta ty = foldr mkFunTy ty theta
\end{code}

@isTauTy@ tests for nested for-alls.  It should not be called on a boxy type.

\begin{code}
isTauTy :: Type -> Bool
isTauTy ty | Just ty' <- tcView ty = isTauTy ty'
isTauTy (TyVarTy _)	  = True
isTauTy (TyConApp tc tys) = all isTauTy tys && isTauTyCon tc
isTauTy (AppTy a b)	  = isTauTy a && isTauTy b
isTauTy (FunTy a b)	  = isTauTy a && isTauTy b
isTauTy _    		  = False

isTauTyCon :: TyCon -> Bool
-- Returns False for type synonyms whose expansion is a polytype
isTauTyCon tc 
  | isClosedSynTyCon tc = isTauTy (snd (synTyConDefn tc))
  | otherwise           = True

---------------
getDFunTyKey :: Type -> OccName -- Get some string from a type, to be used to
				-- construct a dictionary function name
getDFunTyKey ty | Just ty' <- tcView ty = getDFunTyKey ty'
getDFunTyKey (TyVarTy tv)    = getOccName tv
getDFunTyKey (TyConApp tc _) = getOccName tc
getDFunTyKey (AppTy fun _)   = getDFunTyKey fun
getDFunTyKey (FunTy _ _)     = getOccName funTyCon
getDFunTyKey (ForAllTy _ t)  = getDFunTyKey t
\end{code}


%************************************************************************
%*									*
\subsection{Expanding and splitting}
%*									*
%************************************************************************

These tcSplit functions are like their non-Tc analogues, but
	*) they do not look through newtypes

However, they are non-monadic and do not follow through mutable type
variables.  It's up to you to make sure this doesn't matter.

\begin{code}
tcSplitForAllTys :: Type -> ([TyVar], Type)
tcSplitForAllTys ty = split ty ty []
   where
     split orig_ty ty tvs | Just ty' <- tcView ty = split orig_ty ty' tvs
     split _ (ForAllTy tv ty) tvs = split ty ty (tv:tvs)
     split orig_ty _          tvs = (reverse tvs, orig_ty)

tcIsForAllTy :: Type -> Bool
tcIsForAllTy ty | Just ty' <- tcView ty = tcIsForAllTy ty'
tcIsForAllTy (ForAllTy {}) = True
tcIsForAllTy _             = False

tcSplitPredFunTy_maybe :: Type -> Maybe (PredType, Type)
-- Split off the first predicate argument from a type
tcSplitPredFunTy_maybe ty 
  | Just ty' <- tcView ty = tcSplitPredFunTy_maybe ty'
tcSplitPredFunTy_maybe (FunTy arg res)
  | isPredTy arg = Just (arg, res)
tcSplitPredFunTy_maybe _
  = Nothing

tcSplitPhiTy :: Type -> (ThetaType, Type)
tcSplitPhiTy ty
  = split ty []
  where
    split ty ts 
      = case tcSplitPredFunTy_maybe ty of
	  Just (pred, ty) -> split ty (pred:ts)
	  Nothing         -> (reverse ts, ty)

tcSplitSigmaTy :: Type -> ([TyVar], ThetaType, Type)
tcSplitSigmaTy ty = case tcSplitForAllTys ty of
			(tvs, rho) -> case tcSplitPhiTy rho of
					(theta, tau) -> (tvs, theta, tau)

-----------------------
tcDeepSplitSigmaTy_maybe
  :: TcSigmaType -> Maybe ([TcType], [TyVar], ThetaType, TcSigmaType)
-- Looks for a *non-trivial* quantified type, under zero or more function arrows
-- By "non-trivial" we mean either tyvars or constraints are non-empty

tcDeepSplitSigmaTy_maybe ty
  | Just (arg_ty, res_ty)           <- tcSplitFunTy_maybe ty
  , Just (arg_tys, tvs, theta, rho) <- tcDeepSplitSigmaTy_maybe res_ty
  = Just (arg_ty:arg_tys, tvs, theta, rho)

  | (tvs, theta, rho) <- tcSplitSigmaTy ty
  , not (null tvs && null theta)
  = Just ([], tvs, theta, rho)

  | otherwise = Nothing

-----------------------
tcTyConAppTyCon :: Type -> TyCon
tcTyConAppTyCon ty = case tcSplitTyConApp_maybe ty of
			Just (tc, _) -> tc
			Nothing	     -> pprPanic "tcTyConAppTyCon" (pprType ty)

tcTyConAppArgs :: Type -> [Type]
tcTyConAppArgs ty = case tcSplitTyConApp_maybe ty of
			Just (_, args) -> args
			Nothing	       -> pprPanic "tcTyConAppArgs" (pprType ty)

tcSplitTyConApp :: Type -> (TyCon, [Type])
tcSplitTyConApp ty = case tcSplitTyConApp_maybe ty of
			Just stuff -> stuff
			Nothing	   -> pprPanic "tcSplitTyConApp" (pprType ty)

tcSplitTyConApp_maybe :: Type -> Maybe (TyCon, [Type])
tcSplitTyConApp_maybe ty | Just ty' <- tcView ty = tcSplitTyConApp_maybe ty'
tcSplitTyConApp_maybe (TyConApp tc tys) = Just (tc, tys)
tcSplitTyConApp_maybe (FunTy arg res)   = Just (funTyCon, [arg,res])
	-- Newtypes are opaque, so they may be split
	-- However, predicates are not treated
	-- as tycon applications by the type checker
tcSplitTyConApp_maybe _                 = Nothing

-----------------------
tcSplitFunTys :: Type -> ([Type], Type)
tcSplitFunTys ty = case tcSplitFunTy_maybe ty of
			Nothing	       -> ([], ty)
			Just (arg,res) -> (arg:args, res')
				       where
					  (args,res') = tcSplitFunTys res

tcSplitFunTy_maybe :: Type -> Maybe (Type, Type)
tcSplitFunTy_maybe ty | Just ty' <- tcView ty           = tcSplitFunTy_maybe ty'
tcSplitFunTy_maybe (FunTy arg res) | not (isPredTy arg) = Just (arg, res)
tcSplitFunTy_maybe _                                    = Nothing
	-- Note the typeKind guard
	-- Consider	(?x::Int) => Bool
	-- We don't want to treat this as a function type!
	-- A concrete example is test tc230:
	--	f :: () -> (?p :: ()) => () -> ()
	--
	--	g = f () ()

tcSplitFunTysN
	:: TcRhoType 
	-> Arity		-- N: Number of desired args
	-> ([TcSigmaType], 	-- Arg types (N or fewer)
	    TcSigmaType)	-- The rest of the type

tcSplitFunTysN ty n_args
  | n_args == 0
  = ([], ty)
  | Just (arg,res) <- tcSplitFunTy_maybe ty
  = case tcSplitFunTysN res (n_args - 1) of
	(args, res) -> (arg:args, res)
  | otherwise
  = ([], ty)

tcSplitFunTy :: Type -> (Type, Type)
tcSplitFunTy  ty = expectJust "tcSplitFunTy" (tcSplitFunTy_maybe ty)

tcFunArgTy :: Type -> Type
tcFunArgTy    ty = fst (tcSplitFunTy ty)

tcFunResultTy :: Type -> Type
tcFunResultTy ty = snd (tcSplitFunTy ty)

-----------------------
tcSplitAppTy_maybe :: Type -> Maybe (Type, Type)
tcSplitAppTy_maybe ty | Just ty' <- tcView ty = tcSplitAppTy_maybe ty'
tcSplitAppTy_maybe ty = repSplitAppTy_maybe ty

tcSplitAppTy :: Type -> (Type, Type)
tcSplitAppTy ty = case tcSplitAppTy_maybe ty of
		    Just stuff -> stuff
		    Nothing    -> pprPanic "tcSplitAppTy" (pprType ty)

tcSplitAppTys :: Type -> (Type, [Type])
tcSplitAppTys ty
  = go ty []
  where
    go ty args = case tcSplitAppTy_maybe ty of
		   Just (ty', arg) -> go ty' (arg:args)
		   Nothing	   -> (ty,args)

-----------------------
tcGetTyVar_maybe :: Type -> Maybe TyVar
tcGetTyVar_maybe ty | Just ty' <- tcView ty = tcGetTyVar_maybe ty'
tcGetTyVar_maybe (TyVarTy tv)   = Just tv
tcGetTyVar_maybe _              = Nothing

tcGetTyVar :: String -> Type -> TyVar
tcGetTyVar msg ty = expectJust msg (tcGetTyVar_maybe ty)

tcIsTyVarTy :: Type -> Bool
tcIsTyVarTy ty = maybeToBool (tcGetTyVar_maybe ty)

-----------------------
tcSplitDFunTy :: Type -> ([TyVar], Int, Class, [Type])
-- Split the type of a dictionary function
-- We don't use tcSplitSigmaTy,  because a DFun may (with NDP)
-- have non-Pred arguments, such as
--     df :: forall m. (forall b. Eq b => Eq (m b)) -> C m
tcSplitDFunTy ty 
  = case tcSplitForAllTys ty   of { (tvs, rho)  ->
    case split_dfun_args 0 rho of { (n_theta, tau) ->
    case tcSplitDFunHead tau   of { (clas, tys) ->
    (tvs, n_theta, clas, tys) }}}
  where
    -- Count the context of the dfun.  This can be a mix of
    -- coercion and class constraints; or (in the general NDP case)
    -- some other function argument
    split_dfun_args n ty | Just ty' <- tcView ty = split_dfun_args n ty'
    split_dfun_args n (FunTy _ ty)     = split_dfun_args (n+1) ty
    split_dfun_args n ty               = (n, ty)

tcSplitDFunHead :: Type -> (Class, [Type])
tcSplitDFunHead = getClassPredTys

tcInstHeadTyNotSynonym :: Type -> Bool
-- Used in Haskell-98 mode, for the argument types of an instance head
-- These must not be type synonyms, but everywhere else type synonyms
-- are transparent, so we need a special function here
tcInstHeadTyNotSynonym ty
  = case ty of
        TyConApp tc _ -> not (isSynTyCon tc)
        _ -> True

tcInstHeadTyAppAllTyVars :: Type -> Bool
-- Used in Haskell-98 mode, for the argument types of an instance head
-- These must be a constructor applied to type variable arguments.
-- But we allow kind instantiations.
tcInstHeadTyAppAllTyVars ty
  | Just ty' <- tcView ty       -- Look through synonyms
  = tcInstHeadTyAppAllTyVars ty'
  | otherwise
  = case ty of
	TyConApp _ tys  -> ok (filter (not . isKind) tys)  -- avoid kinds
	FunTy arg res   -> ok [arg, res]
	_               -> False
  where
	-- Check that all the types are type variables,
	-- and that each is distinct
    ok tys = equalLength tvs tys && hasNoDups tvs
	   where
	     tvs = mapCatMaybes get_tv tys

    get_tv (TyVarTy tv)  = Just tv	-- through synonyms
    get_tv _             = Nothing
\end{code}

\begin{code}
pickyEqType :: TcType -> TcType -> Bool
-- Check when two types _look_ the same, _including_ synonyms.  
-- So (pickyEqType String [Char]) returns False
pickyEqType ty1 ty2
  = go init_env ty1 ty2
  where
    init_env = mkRnEnv2 (mkInScopeSet (tyVarsOfType ty1 `unionVarSet` tyVarsOfType ty2))
    go env (TyVarTy tv1)       (TyVarTy tv2)     = rnOccL env tv1 == rnOccR env tv2
    go env (ForAllTy tv1 t1)   (ForAllTy tv2 t2) = go (rnBndr2 env tv1 tv2) t1 t2
    go env (AppTy s1 t1)       (AppTy s2 t2)     = go env s1 s2 && go env t1 t2
    go env (FunTy s1 t1)       (FunTy s2 t2)     = go env s1 s2 && go env t1 t2
    go env (TyConApp tc1 ts1) (TyConApp tc2 ts2) = (tc1 == tc2) && gos env ts1 ts2
    go _ _ _ = False

    gos _   []       []       = True
    gos env (t1:ts1) (t2:ts2) = go env t1 t2 && gos env ts1 ts2
    gos _ _ _ = False
\end{code}

%************************************************************************
%*									*
\subsection{Predicate types}
%*									*
%************************************************************************

Deconstructors and tests on predicate types

\begin{code}
-- | Like 'classifyPredType' but doesn't look through type synonyms.
-- Used to check that programs only use "simple" contexts without any
-- synonyms in them.
shallowPredTypePredTree :: PredType -> PredTree
shallowPredTypePredTree ev_ty
  | TyConApp tc tys <- ev_ty
  = case () of
      () | Just clas <- tyConClass_maybe tc
         -> ClassPred clas tys
      () | tc `hasKey` eqTyConKey
         , let [_, ty1, ty2] = tys
         -> EqPred ty1 ty2
      () | Just ip <- tyConIP_maybe tc
         , let [ty] = tys
         -> IPPred ip ty
      () | isTupleTyCon tc
         -> TuplePred tys
      _ -> IrredPred ev_ty
  | otherwise
  = IrredPred ev_ty

isTyVarClassPred :: PredType -> Bool
isTyVarClassPred ty = case getClassPredTys_maybe ty of
    Just (_, tys) -> all isTyVarTy tys
    _             -> False

evVarPred_maybe :: EvVar -> Maybe PredType
evVarPred_maybe v = if isPredTy ty then Just ty else Nothing
  where ty = varType v

evVarPred :: EvVar -> PredType
evVarPred var
 | debugIsOn
  = case evVarPred_maybe var of
      Just pred -> pred
      Nothing   -> pprPanic "tcEvVarPred" (ppr var <+> ppr (varType var))
 | otherwise
  = varType var
\end{code}

Superclasses

\begin{code}
mkMinimalBySCs :: [PredType] -> [PredType]
-- Remove predicates that can be deduced from others by superclasses
mkMinimalBySCs ptys = [ ploc |  ploc <- ptys
                             ,  ploc `not_in_preds` rec_scs ]
 where
   rec_scs = concatMap trans_super_classes ptys
   not_in_preds p ps = null (filter (eqPred p) ps)

   trans_super_classes pred   -- Superclasses of pred, excluding pred itself
     = case classifyPredType pred of
         ClassPred cls tys -> transSuperClasses cls tys
         TuplePred ts      -> concatMap trans_super_classes ts
         _                 -> []

transSuperClasses :: Class -> [Type] -> [PredType]
transSuperClasses cls tys    -- Superclasses of (cls tys),
                             -- excluding (cls tys) itself
  = concatMap trans_sc (immSuperClasses cls tys)
  where 
    trans_sc :: PredType -> [PredType]
    -- (trans_sc p) returns (p : p's superclasses)
    trans_sc p = case classifyPredType p of
                   ClassPred cls tys -> p : transSuperClasses cls tys
                   TuplePred ps      -> concatMap trans_sc ps
                   _                 -> [p]

immSuperClasses :: Class -> [Type] -> [PredType]
immSuperClasses cls tys
  = substTheta (zipTopTvSubst tyvars tys) sc_theta
  where 
    (tyvars,sc_theta,_,_) = classBigSig cls
\end{code}


%************************************************************************
%*									*
\subsection{Predicates}
%*									*
%************************************************************************

isSigmaTy returns true of any qualified type.  It doesn't *necessarily* have 
any foralls.  E.g.
	f :: (?x::Int) => Int -> Int

\begin{code}
isSigmaTy :: Type -> Bool
isSigmaTy ty | Just ty' <- tcView ty = isSigmaTy ty'
isSigmaTy (ForAllTy _ _) = True
isSigmaTy (FunTy a _)    = isPredTy a
isSigmaTy _              = False

isOverloadedTy :: Type -> Bool
-- Yes for a type of a function that might require evidence-passing
-- Used only by bindLocalMethods
isOverloadedTy ty | Just ty' <- tcView ty = isOverloadedTy ty'
isOverloadedTy (ForAllTy _ ty) = isOverloadedTy ty
isOverloadedTy (FunTy a _)     = isPredTy a
isOverloadedTy _               = False
\end{code}

\begin{code}
isFloatTy, isDoubleTy, isIntegerTy, isIntTy, isWordTy, isBoolTy,
    isUnitTy, isCharTy :: Type -> Bool
isFloatTy      = is_tc floatTyConKey
isDoubleTy     = is_tc doubleTyConKey
isIntegerTy    = is_tc integerTyConKey
isIntTy        = is_tc intTyConKey
isWordTy       = is_tc wordTyConKey
isBoolTy       = is_tc boolTyConKey
isUnitTy       = is_tc unitTyConKey
isCharTy       = is_tc charTyConKey

isStringTy :: Type -> Bool
isStringTy ty
  = case tcSplitTyConApp_maybe ty of
      Just (tc, [arg_ty]) -> tc == listTyCon && isCharTy arg_ty
      _                   -> False

is_tc :: Unique -> Type -> Bool
-- Newtypes are opaque to this
is_tc uniq ty = case tcSplitTyConApp_maybe ty of
			Just (tc, _) -> uniq == getUnique tc
			Nothing	     -> False
\end{code}

\begin{code}
-- NB: Currently used in places where we have already expanded type synonyms;
--     hence no 'coreView'.  This could, however, be changed without breaking
--     any code.
isSynFamilyTyConApp :: TcTauType -> Bool
isSynFamilyTyConApp (TyConApp tc tys) = isSynFamilyTyCon tc && 
                                      length tys == tyConArity tc 
isSynFamilyTyConApp _other            = False
\end{code}


%************************************************************************
%*									*
\subsection{Misc}
%*									*
%************************************************************************

\begin{code}
deNoteType :: Type -> Type
-- Remove all *outermost* type synonyms and other notes
deNoteType ty | Just ty' <- tcView ty = deNoteType ty'
deNoteType ty = ty

tcTyVarsOfType :: Type -> TcTyVarSet
-- Just the *TcTyVars* free in the type
-- (Types.tyVarsOfTypes finds all free TyVars)
tcTyVarsOfType (TyVarTy tv)	    = if isTcTyVar tv then unitVarSet tv
						      else emptyVarSet
tcTyVarsOfType (TyConApp _ tys)     = tcTyVarsOfTypes tys
tcTyVarsOfType (FunTy arg res)	    = tcTyVarsOfType arg `unionVarSet` tcTyVarsOfType res
tcTyVarsOfType (AppTy fun arg)	    = tcTyVarsOfType fun `unionVarSet` tcTyVarsOfType arg
tcTyVarsOfType (ForAllTy tyvar ty)  = tcTyVarsOfType ty `delVarSet` tyvar
	-- We do sometimes quantify over skolem TcTyVars

tcTyVarsOfTypes :: [Type] -> TyVarSet
tcTyVarsOfTypes tys = foldr (unionVarSet.tcTyVarsOfType) emptyVarSet tys
\end{code}

Find the free tycons and classes of a type.  This is used in the front
end of the compiler.

\begin{code}
orphNamesOfTyCon :: TyCon -> NameSet
orphNamesOfTyCon tycon = unitNameSet (getName tycon) `unionNameSets` case tyConClass_maybe tycon of
    Nothing  -> emptyNameSet
    Just cls -> unitNameSet (getName cls)

orphNamesOfType :: Type -> NameSet
orphNamesOfType ty | Just ty' <- tcView ty = orphNamesOfType ty'
		-- Look through type synonyms (Trac #4912)
orphNamesOfType (TyVarTy _)		   = emptyNameSet
orphNamesOfType (TyConApp tycon tys)       = orphNamesOfTyCon tycon
                                             `unionNameSets` orphNamesOfTypes tys
orphNamesOfType (FunTy arg res)	    = orphNamesOfType arg `unionNameSets` orphNamesOfType res
orphNamesOfType (AppTy fun arg)	    = orphNamesOfType fun `unionNameSets` orphNamesOfType arg
orphNamesOfType (ForAllTy _ ty)	    = orphNamesOfType ty

orphNamesOfTypes :: [Type] -> NameSet
orphNamesOfTypes tys = foldr (unionNameSets . orphNamesOfType) emptyNameSet tys

orphNamesOfDFunHead :: Type -> NameSet
-- Find the free type constructors and classes 
-- of the head of the dfun instance type
-- The 'dfun_head_type' is because of
--	instance Foo a => Baz T where ...
-- The decl is an orphan if Baz and T are both not locally defined,
--	even if Foo *is* locally defined
orphNamesOfDFunHead dfun_ty 
  = case tcSplitSigmaTy dfun_ty of
	(_, _, head_ty) -> orphNamesOfType head_ty
        
orphNamesOfCo :: Coercion -> NameSet
orphNamesOfCo (Refl ty)             = orphNamesOfType ty
orphNamesOfCo (TyConAppCo tc cos)   = unitNameSet (getName tc) `unionNameSets` orphNamesOfCos cos
orphNamesOfCo (AppCo co1 co2)       = orphNamesOfCo co1 `unionNameSets` orphNamesOfCo co2
orphNamesOfCo (ForAllCo _ co)       = orphNamesOfCo co
orphNamesOfCo (CoVarCo _)           = emptyNameSet
orphNamesOfCo (AxiomInstCo con cos) = orphNamesOfCoCon con `unionNameSets` orphNamesOfCos cos
orphNamesOfCo (UnsafeCo ty1 ty2)    = orphNamesOfType ty1 `unionNameSets` orphNamesOfType ty2
orphNamesOfCo (SymCo co)            = orphNamesOfCo co
orphNamesOfCo (TransCo co1 co2)     = orphNamesOfCo co1 `unionNameSets` orphNamesOfCo co2
orphNamesOfCo (NthCo _ co)          = orphNamesOfCo co
orphNamesOfCo (InstCo co ty)        = orphNamesOfCo co `unionNameSets` orphNamesOfType ty

orphNamesOfCos :: [Coercion] -> NameSet
orphNamesOfCos = foldr (unionNameSets . orphNamesOfCo) emptyNameSet

orphNamesOfCoCon :: CoAxiom -> NameSet
orphNamesOfCoCon (CoAxiom { co_ax_lhs = ty1, co_ax_rhs = ty2 })
  = orphNamesOfType ty1 `unionNameSets` orphNamesOfType ty2
\end{code}


%************************************************************************
%*									*
\subsection[TysWiredIn-ext-type]{External types}
%*									*
%************************************************************************

The compiler's foreign function interface supports the passing of a
restricted set of types as arguments and results (the restricting factor
being the )

\begin{code}
tcSplitIOType_maybe :: Type -> Maybe (TyCon, Type)
-- (tcSplitIOType_maybe t) returns Just (IO,t',co)
--              if co : t ~ IO t'
--              returns Nothing otherwise
tcSplitIOType_maybe ty
  = case tcSplitTyConApp_maybe ty of
        Just (io_tycon, [io_res_ty])
         | io_tycon `hasKey` ioTyConKey ->
            Just (io_tycon, io_res_ty)
        _ ->
            Nothing

isFFITy :: Type -> Bool
-- True for any TyCon that can possibly be an arg or result of an FFI call
isFFITy ty = checkRepTyCon legalFFITyCon ty

isFFIArgumentTy :: DynFlags -> Safety -> Type -> Bool
-- Checks for valid argument type for a 'foreign import'
isFFIArgumentTy dflags safety ty 
   = checkRepTyCon (legalOutgoingTyCon dflags safety) ty

isFFIExternalTy :: Type -> Bool
-- Types that are allowed as arguments of a 'foreign export'
isFFIExternalTy ty = checkRepTyCon legalFEArgTyCon ty

isFFIImportResultTy :: DynFlags -> Type -> Bool
isFFIImportResultTy dflags ty 
  = checkRepTyCon (legalFIResultTyCon dflags) ty

isFFIExportResultTy :: Type -> Bool
isFFIExportResultTy ty = checkRepTyCon legalFEResultTyCon ty

isFFIDynArgumentTy :: Type -> Bool
-- The argument type of a foreign import dynamic must be Ptr, FunPtr, Addr,
-- or a newtype of either.
isFFIDynArgumentTy = checkRepTyConKey [ptrTyConKey, funPtrTyConKey]

isFFIDynResultTy :: Type -> Bool
-- The result type of a foreign export dynamic must be Ptr, FunPtr, Addr,
-- or a newtype of either.
isFFIDynResultTy = checkRepTyConKey [ptrTyConKey, funPtrTyConKey]

isFFILabelTy :: Type -> Bool
-- The type of a foreign label must be Ptr, FunPtr, Addr,
-- or a newtype of either.
isFFILabelTy = checkRepTyConKey [ptrTyConKey, funPtrTyConKey]

isFFIPrimArgumentTy :: DynFlags -> Type -> Bool
-- Checks for valid argument type for a 'foreign import prim'
-- Currently they must all be simple unlifted types.
isFFIPrimArgumentTy dflags ty
   = checkRepTyCon (legalFIPrimArgTyCon dflags) ty

isFFIPrimResultTy :: DynFlags -> Type -> Bool
-- Checks for valid result type for a 'foreign import prim'
-- Currently it must be an unlifted type, including unboxed tuples.
isFFIPrimResultTy dflags ty
   = checkRepTyCon (legalFIPrimResultTyCon dflags) ty

isFFIDotnetTy :: DynFlags -> Type -> Bool
isFFIDotnetTy dflags ty
  = checkRepTyCon (\ tc -> (legalFIResultTyCon dflags tc || 
			   isFFIDotnetObjTy ty || isStringTy ty)) ty
	-- NB: isStringTy used to look through newtypes, but
	--     it no longer does so.  May need to adjust isFFIDotNetTy
	--     if we do want to look through newtypes.

isFFIDotnetObjTy :: Type -> Bool
isFFIDotnetObjTy ty
  = checkRepTyCon check_tc t_ty
  where
   (_, t_ty) = tcSplitForAllTys ty
   check_tc tc = getName tc == objectTyConName

isFunPtrTy :: Type -> Bool
isFunPtrTy = checkRepTyConKey [funPtrTyConKey]

-- normaliseFfiType gets run before checkRepTyCon, so we don't
-- need to worry about looking through newtypes or type functions
-- here; that's already been taken care of.
checkRepTyCon :: (TyCon -> Bool) -> Type -> Bool
checkRepTyCon check_tc ty
    | Just (tc, _) <- splitTyConApp_maybe ty
    = check_tc tc
    | otherwise
    = False

checkRepTyConKey :: [Unique] -> Type -> Bool
-- Like checkRepTyCon, but just looks at the TyCon key
checkRepTyConKey keys
  = checkRepTyCon (\tc -> tyConUnique tc `elem` keys)
\end{code}

----------------------------------------------
These chaps do the work; they are not exported
----------------------------------------------

\begin{code}
legalFEArgTyCon :: TyCon -> Bool
legalFEArgTyCon tc
  -- It's illegal to make foreign exports that take unboxed
  -- arguments.  The RTS API currently can't invoke such things.  --SDM 7/2000
  = boxedMarshalableTyCon tc

legalFIResultTyCon :: DynFlags -> TyCon -> Bool
legalFIResultTyCon dflags tc
  | tc == unitTyCon         = True
  | otherwise	            = marshalableTyCon dflags tc

legalFEResultTyCon :: TyCon -> Bool
legalFEResultTyCon tc
  | tc == unitTyCon         = True
  | otherwise               = boxedMarshalableTyCon tc

legalOutgoingTyCon :: DynFlags -> Safety -> TyCon -> Bool
-- Checks validity of types going from Haskell -> external world
legalOutgoingTyCon dflags _ tc
  = marshalableTyCon dflags tc

legalFFITyCon :: TyCon -> Bool
-- True for any TyCon that can possibly be an arg or result of an FFI call
legalFFITyCon tc
  = isUnLiftedTyCon tc || boxedMarshalableTyCon tc || tc == unitTyCon

marshalableTyCon :: DynFlags -> TyCon -> Bool
marshalableTyCon dflags tc
  =  (xopt Opt_UnliftedFFITypes dflags 
      && isUnLiftedTyCon tc
      && not (isUnboxedTupleTyCon tc)
      && case tyConPrimRep tc of	-- Note [Marshalling VoidRep]
	   VoidRep -> False
	   _       -> True)
  || boxedMarshalableTyCon tc

boxedMarshalableTyCon :: TyCon -> Bool
boxedMarshalableTyCon tc
   = getUnique tc `elem` [ intTyConKey, int8TyConKey, int16TyConKey
			 , int32TyConKey, int64TyConKey
			 , wordTyConKey, word8TyConKey, word16TyConKey
			 , word32TyConKey, word64TyConKey
			 , floatTyConKey, doubleTyConKey
			 , ptrTyConKey, funPtrTyConKey
			 , charTyConKey
			 , stablePtrTyConKey
			 , boolTyConKey
			 ]

legalFIPrimArgTyCon :: DynFlags -> TyCon -> Bool
-- Check args of 'foreign import prim', only allow simple unlifted types.
-- Strictly speaking it is unnecessary to ban unboxed tuples here since
-- currently they're of the wrong kind to use in function args anyway.
legalFIPrimArgTyCon dflags tc
  = xopt Opt_UnliftedFFITypes dflags
    && isUnLiftedTyCon tc
    && not (isUnboxedTupleTyCon tc)

legalFIPrimResultTyCon :: DynFlags -> TyCon -> Bool
-- Check result type of 'foreign import prim'. Allow simple unlifted
-- types and also unboxed tuple result types '... -> (# , , #)'
legalFIPrimResultTyCon dflags tc
  = xopt Opt_UnliftedFFITypes dflags
    && isUnLiftedTyCon tc
    && (isUnboxedTupleTyCon tc
        || case tyConPrimRep tc of	-- Note [Marshalling VoidRep]
	   VoidRep -> False
	   _       -> True)
\end{code}

Note [Marshalling VoidRep]
~~~~~~~~~~~~~~~~~~~~~~~~~~
We don't treat State# (whose PrimRep is VoidRep) as marshalable.
In turn that means you can't write
	foreign import foo :: Int -> State# RealWorld

Reason: the back end falls over with panic "primRepHint:VoidRep";
	and there is no compelling reason to permit it
