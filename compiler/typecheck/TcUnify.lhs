%
% (c) The University of Glasgow 2006
% (c) The GRASP/AQUA Project, Glasgow University, 1992-1998
%

Type subsumption and unification

\begin{code}
{-# OPTIONS -fno-warn-tabs #-}
-- The above warning supression flag is a temporary kludge.
-- While working on this module you are encouraged to remove it and
-- detab the module (please do the detabbing in a separate patch). See
--     http://hackage.haskell.org/trac/ghc/wiki/Commentary/CodingStyle#TabsvsSpaces
-- for details

module TcUnify (
  -- Full-blown subsumption
  tcWrapResult, tcSubType, tcGen, 
  checkConstraints, newImplication, sigCtxt,

  -- Various unifications
  unifyType, unifyTypeList, unifyTheta, unifyKind, unifyKindEq,

  --------------------------------
  -- Holes
  tcInfer,
  matchExpectedListTy,
  matchExpectedPArrTy,
  matchExpectedTyConApp,
  matchExpectedAppTy, 
  matchExpectedFunTys,
  matchExpectedFunKind,
  wrapFunResCoercion,
  wrapEqCtxt,

  --------------------------------
  -- Errors
  mkKindErrorCtxt

  ) where

#include "HsVersions.h"

import HsSyn
import TypeRep
import TcErrors	( unifyCtxt )
import TcMType
import TcIface
import TcRnMonad
import TcType
import Type
import TcEvidence
import Name ( isSystemName )
import Inst
import Kind
import TyCon
import TysWiredIn
import Var
import VarSet
import VarEnv
import ErrUtils
import DynFlags
import BasicTypes
import Maybes ( allMaybes )
import Util
import Outputable
import FastString

import Control.Monad
\end{code}


%************************************************************************
%*                                                                      *
             matchExpected functions
%*                                                                      *
%************************************************************************

Note [Herald for matchExpectedFunTys]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
The 'herald' always looks like:
   "The equation(s) for 'f' have"
   "The abstraction (\x.e) takes"
   "The section (+ x) expects"
   "The function 'f' is applied to"

This is used to construct a message of form

   The abstraction `\Just 1 -> ...' takes two arguments
   but its type `Maybe a -> a' has only one

   The equation(s) for `f' have two arguments
   but its type `Maybe a -> a' has only one

   The section `(f 3)' requires 'f' to take two arguments
   but its type `Int -> Int' has only one

   The function 'f' is applied to two arguments
   but its type `Int -> Int' has only one

Note [matchExpectedFunTys]
~~~~~~~~~~~~~~~~~~~~~~~~~~
matchExpectedFunTys checks that an (Expected rho) has the form
of an n-ary function.  It passes the decomposed type to the
thing_inside, and returns a wrapper to coerce between the two types

It's used wherever a language construct must have a functional type,
namely:
	A lambda expression
	A function definition
     An operator section

This is not (currently) where deep skolemisation occurs;
matchExpectedFunTys does not skolmise nested foralls in the 
expected type, becuase it expects that to have been done already


\begin{code}
matchExpectedFunTys :: SDoc 	-- See Note [Herald for matchExpectedFunTys]
            	    -> Arity
            	    -> TcRhoType 
                    -> TcM (TcCoercion, [TcSigmaType], TcRhoType)

-- If    matchExpectFunTys n ty = (co, [t1,..,tn], ty_r)
-- then  co : ty ~ (t1 -> ... -> tn -> ty_r)
--
-- Does not allocate unnecessary meta variables: if the input already is 
-- a function, we just take it apart.  Not only is this efficient, 
-- it's important for higher rank: the argument might be of form
--		(forall a. ty) -> other
-- If allocated (fresh-meta-var1 -> fresh-meta-var2) and unified, we'd
-- hide the forall inside a meta-variable

matchExpectedFunTys herald arity orig_ty 
  = go arity orig_ty
  where
    -- If     go n ty = (co, [t1,..,tn], ty_r)
    -- then   co : ty ~ t1 -> .. -> tn -> ty_r

    go n_req ty
      | n_req == 0 = return (mkTcReflCo ty, [], ty)

    go n_req ty
      | Just ty' <- tcView ty = go n_req ty'

    go n_req (FunTy arg_ty res_ty)
      | not (isPredTy arg_ty)
      = do { (co, tys, ty_r) <- go (n_req-1) res_ty
           ; return (mkTcFunCo (mkTcReflCo arg_ty) co, arg_ty:tys, ty_r) }

    go n_req ty@(TyVarTy tv)
      | ASSERT( isTcTyVar tv) isMetaTyVar tv
      = do { cts <- readMetaTyVar tv
	   ; case cts of
	       Indirect ty' -> go n_req ty'
	       Flexi        -> defer n_req ty }

       -- In all other cases we bale out into ordinary unification
    go n_req ty = defer n_req ty

    ------------
    defer n_req fun_ty 
      = addErrCtxtM mk_ctxt $
        do { arg_tys <- newFlexiTyVarTys n_req argTypeKind
           ; res_ty  <- newFlexiTyVarTy openTypeKind
           ; co   <- unifyType fun_ty (mkFunTys arg_tys res_ty)
           ; return (co, arg_tys, res_ty) }

    ------------
    mk_ctxt :: TidyEnv -> TcM (TidyEnv, MsgDoc)
    mk_ctxt env = do { orig_ty1 <- zonkTcType orig_ty
                     ; let (env', orig_ty2) = tidyOpenType env orig_ty1
                           (args, _) = tcSplitFunTys orig_ty2
                           n_actual = length args
                     ; return (env', mk_msg orig_ty2 n_actual) }

    mk_msg ty n_args
      = herald <+> speakNOf arity (ptext (sLit "argument")) <> comma $$ 
	sep [ptext (sLit "but its type") <+> quotes (pprType ty), 
	     if n_args == 0 then ptext (sLit "has none") 
	     else ptext (sLit "has only") <+> speakN n_args]
\end{code}


\begin{code}
----------------------
matchExpectedListTy :: TcRhoType -> TcM (TcCoercion, TcRhoType)
-- Special case for lists
matchExpectedListTy exp_ty
 = do { (co, [elt_ty]) <- matchExpectedTyConApp listTyCon exp_ty
      ; return (co, elt_ty) }

----------------------
matchExpectedPArrTy :: TcRhoType -> TcM (TcCoercion, TcRhoType)
-- Special case for parrs
matchExpectedPArrTy exp_ty
  = do { (co, [elt_ty]) <- matchExpectedTyConApp parrTyCon exp_ty
       ; return (co, elt_ty) }

----------------------
matchExpectedTyConApp :: TyCon                -- T :: forall kv1 ... kvm. k1 -> ... -> kn -> *
                      -> TcRhoType 	      -- orig_ty
                      -> TcM (TcCoercion,      -- T k1 k2 k3 a b c ~ orig_ty
                              [TcSigmaType])  -- Element types, k1 k2 k3 a b c
                              
-- It's used for wired-in tycons, so we call checkWiredInTyCon
-- Precondition: never called with FunTyCon
-- Precondition: input type :: *

matchExpectedTyConApp tc orig_ty
  = do  { checkWiredInTyCon tc
        ; go (tyConArity tc) orig_ty [] }
  where
    go :: Int -> TcRhoType -> [TcSigmaType] -> TcM (TcCoercion, [TcSigmaType])
    -- If     go n ty tys = (co, [t1..tn] ++ tys)
    -- then   co : T t1..tn ~ ty

    go n_req ty tys
      | Just ty' <- tcView ty = go n_req ty' tys

    go n_req ty@(TyVarTy tv) tys
      | ASSERT( isTcTyVar tv) isMetaTyVar tv
      = do { cts <- readMetaTyVar tv
           ; case cts of
               Indirect ty -> go n_req ty tys
               Flexi       -> defer n_req ty tys }

    go n_req ty@(TyConApp tycon args) tys
      | tc == tycon
      = ASSERT( n_req == length args)   -- ty::*
        return (mkTcReflCo ty, args ++ tys)

    go n_req (AppTy fun arg) tys
      | n_req > 0
      = do { (co, args) <- go (n_req - 1) fun (arg : tys) 
           ; return (mkTcAppCo co (mkTcReflCo arg), args) }

    go n_req ty tys = defer n_req ty tys

    ----------
    defer n_req ty tys
      = do { kappa_tys <- mapM (const newMetaKindVar) kvs
           ; let arg_kinds' = map (substKiWith kvs kappa_tys) arg_kinds
           ; tau_tys <- mapM newFlexiTyVarTy arg_kinds'
           ; co <- unifyType (mkTyConApp tc (kappa_tys ++ tau_tys)) ty
           ; return (co, kappa_tys ++ tau_tys ++ tys) }
      where
        (kvs, body) = splitForAllTys (tyConKind tc)
        (arg_kinds, _) = splitKindFunTysN (n_req - length kvs) body

----------------------
matchExpectedAppTy :: TcRhoType                         -- orig_ty
                   -> TcM (TcCoercion,                   -- m a ~ orig_ty
                           (TcSigmaType, TcSigmaType))  -- Returns m, a
-- If the incoming type is a mutable type variable of kind k, then
-- matchExpectedAppTy returns a new type variable (m: * -> k); note the *.

matchExpectedAppTy orig_ty
  = go orig_ty
  where
    go ty
      | Just ty' <- tcView ty = go ty'

      | Just (fun_ty, arg_ty) <- tcSplitAppTy_maybe ty
      = return (mkTcReflCo orig_ty, (fun_ty, arg_ty))

    go (TyVarTy tv)
      | ASSERT( isTcTyVar tv) isMetaTyVar tv
      = do { cts <- readMetaTyVar tv
           ; case cts of
               Indirect ty -> go ty
               Flexi       -> defer }

    go _ = defer

    -- Defer splitting by generating an equality constraint
    defer = do { ty1 <- newFlexiTyVarTy kind1
               ; ty2 <- newFlexiTyVarTy kind2
               ; co <- unifyType (mkAppTy ty1 ty2) orig_ty
               ; return (co, (ty1, ty2)) }

    orig_kind = typeKind orig_ty
    kind1 = mkArrowKind liftedTypeKind (defaultKind orig_kind)
    kind2 = liftedTypeKind    -- m :: * -> k
                              -- arg type :: *
        -- The defaultKind is a bit smelly.  If you remove it,
        -- try compiling        f x = do { x }
        -- and you'll get a kind mis-match.  It smells, but
        -- not enough to lose sleep over.
\end{code}


%************************************************************************
%*                                                                      *
                Subsumption checking
%*                                                                      *
%************************************************************************

All the tcSub calls have the form
                tcSub actual_ty expected_ty
which checks
                actual_ty <= expected_ty

That is, that a value of type actual_ty is acceptable in
a place expecting a value of type expected_ty.

It returns a coercion function
        co_fn :: actual_ty ~ expected_ty
which takes an HsExpr of type actual_ty into one of type
expected_ty.

\begin{code}
tcSubType :: CtOrigin -> UserTypeCtxt -> TcSigmaType -> TcSigmaType -> TcM HsWrapper
-- Check that ty_actual is more polymorphic than ty_expected
-- Both arguments might be polytypes, so we must instantiate and skolemise
-- Returns a wrapper of shape   ty_actual ~ ty_expected
tcSubType origin ctxt ty_actual ty_expected
  | isSigmaTy ty_actual
  = do { (sk_wrap, inst_wrap) 
            <- tcGen ctxt ty_expected $ \ _ sk_rho -> do
            { (in_wrap, in_rho) <- deeplyInstantiate origin ty_actual
            ; cow <- unifyType in_rho sk_rho
            ; return (coToHsWrapper cow <.> in_wrap) }
       ; return (sk_wrap <.> inst_wrap) }

  | otherwise	-- Urgh!  It seems deeply weird to have equality
    		-- when actual is not a polytype, and it makes a big 
		-- difference e.g. tcfail104
  = do { cow <- unifyType ty_actual ty_expected
       ; return (coToHsWrapper cow) }
  
tcInfer :: (TcType -> TcM a) -> TcM (a, TcType)
tcInfer tc_infer = do { ty  <- newFlexiTyVarTy openTypeKind
                      ; res <- tc_infer ty
		      ; return (res, ty) }

-----------------
tcWrapResult :: HsExpr TcId -> TcRhoType -> TcRhoType -> TcM (HsExpr TcId)
tcWrapResult expr actual_ty res_ty
  = do { cow <- unifyType actual_ty res_ty
       	        -- Both types are deeply skolemised
       ; return (mkHsWrapCo cow expr) }

-----------------------------------
wrapFunResCoercion
        :: [TcType]     -- Type of args
        -> HsWrapper    -- HsExpr a -> HsExpr b
        -> TcM HsWrapper        -- HsExpr (arg_tys -> a) -> HsExpr (arg_tys -> b)
wrapFunResCoercion arg_tys co_fn_res
  | isIdHsWrapper co_fn_res
  = return idHsWrapper
  | null arg_tys
  = return co_fn_res
  | otherwise
  = do  { arg_ids <- newSysLocalIds (fsLit "sub") arg_tys
        ; return (mkWpLams arg_ids <.> co_fn_res <.> mkWpEvVarApps arg_ids) }
\end{code}



%************************************************************************
%*                                                                      *
\subsection{Generalisation}
%*                                                                      *
%************************************************************************

\begin{code}
tcGen :: UserTypeCtxt -> TcType
      -> ([TcTyVar] -> TcRhoType -> TcM result)
      -> TcM (HsWrapper, result)
        -- The expression has type: spec_ty -> expected_ty

tcGen ctxt expected_ty thing_inside
   -- We expect expected_ty to be a forall-type
   -- If not, the call is a no-op
  = do  { traceTc "tcGen" empty
        ; (wrap, tvs', given, rho') <- deeplySkolemise expected_ty

        ; when debugIsOn $
              traceTc "tcGen" $ vcat [
                           text "expected_ty" <+> ppr expected_ty,
                           text "inst ty" <+> ppr tvs' <+> ppr rho' ]

	-- Generally we must check that the "forall_tvs" havn't been constrained
        -- The interesting bit here is that we must include the free variables
        -- of the expected_ty.  Here's an example:
        --       runST (newVar True)
        -- Here, if we don't make a check, we'll get a type (ST s (MutVar s Bool))
        -- for (newVar True), with s fresh.  Then we unify with the runST's arg type
        -- forall s'. ST s' a. That unifies s' with s, and a with MutVar s Bool.
        -- So now s' isn't unconstrained because it's linked to a.
        -- 
	-- However [Oct 10] now that the untouchables are a range of 
        -- TcTyVars, all this is handled automatically with no need for
	-- extra faffing around

        -- Use the *instantiated* type in the SkolemInfo
        -- so that the names of displayed type variables line up
        ; let skol_info = SigSkol ctxt (mkPiTypes given rho')

        ; (ev_binds, result) <- checkConstraints skol_info tvs' given $
                                thing_inside tvs' rho'

        ; return (wrap <.> mkWpLet ev_binds, result) }
	  -- The ev_binds returned by checkConstraints is very
	  -- often empty, in which case mkWpLet is a no-op

checkConstraints :: SkolemInfo
		 -> [TcTyVar]		-- Skolems
		 -> [EvVar]             -- Given
		 -> TcM result
		 -> TcM (TcEvBinds, result)

checkConstraints skol_info skol_tvs given thing_inside
  | null skol_tvs && null given
  = do { res <- thing_inside; return (emptyTcEvBinds, res) }
      -- Just for efficiency.  We check every function argument with
      -- tcPolyExpr, which uses tcGen and hence checkConstraints.

  | otherwise
  = newImplication skol_info skol_tvs given thing_inside

newImplication :: SkolemInfo -> [TcTyVar]
	       -> [EvVar] -> TcM result
               -> TcM (TcEvBinds, result)
newImplication skol_info skol_tvs given thing_inside
  = ASSERT2( all isTcTyVar skol_tvs, ppr skol_tvs )
    ASSERT2( all isSkolemTyVar skol_tvs, ppr skol_tvs )
    do { ((result, untch), wanted) <- captureConstraints  $ 
                                      captureUntouchables $
                                      thing_inside

       ; if isEmptyWC wanted && not (hasEqualities given)
       	    -- Optimisation : if there are no wanteds, and the givens
       	    -- are sufficiently simple, don't generate an implication
       	    -- at all.  Reason for the hasEqualities test:
	    -- we don't want to lose the "inaccessible alternative"
	    -- error check
         then 
            return (emptyTcEvBinds, result)
         else do
       { ev_binds_var <- newTcEvBinds
       ; lcl_env <- getLclTypeEnv
       ; loc <- getCtLoc skol_info
       ; emitImplication $ Implic { ic_untch = untch
             		     	  , ic_env = lcl_env
             		     	  , ic_skols = skol_tvs
                             	  , ic_given = given
                                  , ic_wanted = wanted
                                  , ic_insol  = insolubleWC wanted
                                  , ic_binds = ev_binds_var
             		     	  , ic_loc = loc }

       ; return (TcEvBinds ev_binds_var, result) } }
\end{code}

%************************************************************************
%*                                                                      *
                Boxy unification
%*                                                                      *
%************************************************************************

The exported functions are all defined as versions of some
non-exported generic functions.

\begin{code}
unifyType :: TcTauType -> TcTauType -> TcM TcCoercion
-- Actual and expected types
-- Returns a coercion : ty1 ~ ty2
unifyType ty1 ty2 = uType [] ty1 ty2

---------------
unifyPred :: PredType -> PredType -> TcM TcCoercion
-- Actual and expected types
unifyPred = unifyType

---------------
unifyTheta :: TcThetaType -> TcThetaType -> TcM [TcCoercion]
-- Actual and expected types
unifyTheta theta1 theta2
  = do  { checkTc (equalLength theta1 theta2)
                  (vcat [ptext (sLit "Contexts differ in length"),
                         nest 2 $ parens $ ptext (sLit "Use -XRelaxedPolyRec to allow this")])
        ; zipWithM unifyPred theta1 theta2 }
\end{code}

@unifyTypeList@ takes a single list of @TauType@s and unifies them
all together.  It is used, for example, when typechecking explicit
lists, when all the elts should be of the same type.

\begin{code}
unifyTypeList :: [TcTauType] -> TcM ()
unifyTypeList []                 = return ()
unifyTypeList [_]                = return ()
unifyTypeList (ty1:tys@(ty2:_)) = do { _ <- unifyType ty1 ty2
                                     ; unifyTypeList tys }
\end{code}

%************************************************************************
%*                                                                      *
                 uType and friends									
%*                                                                      *
%************************************************************************

uType is the heart of the unifier.  Each arg occurs twice, because
we want to report errors in terms of synomyms if possible.  The first of
the pair is used in error messages only; it is always the same as the
second, except that if the first is a synonym then the second may be a
de-synonym'd version.  This way we get better error messages.

\begin{code}
data SwapFlag 
  = NotSwapped	-- Args are: actual,   expected
  | IsSwapped   -- Args are: expected, actual

instance Outputable SwapFlag where
  ppr IsSwapped  = ptext (sLit "Is-swapped")
  ppr NotSwapped = ptext (sLit "Not-swapped")

unSwap :: SwapFlag -> (a->a->b) -> a -> a -> b
unSwap NotSwapped f a b = f a b
unSwap IsSwapped  f a b = f b a

------------
uType, uType_np, uType_defer
  :: [EqOrigin]
  -> TcType    -- ty1 is the *actual* type
  -> TcType    -- ty2 is the *expected* type
  -> TcM TcCoercion

--------------
-- It is always safe to defer unification to the main constraint solver
-- See Note [Deferred unification]
uType_defer items ty1 ty2
  = ASSERT( not (null items) )
    do { eqv <- newEq ty1 ty2
       ; loc <- getCtLoc (TypeEqOrigin (last items))
       ; emitFlat (mkNonCanonical eqv (Wanted loc))

       -- Error trace only
       -- NB. do *not* call mkErrInfo unless tracing is on, because
       -- it is hugely expensive (#5631)
       ; ifDOptM Opt_D_dump_tc_trace $ do
            { ctxt <- getErrCtxt
            ; doc <- mkErrInfo emptyTidyEnv ctxt
            ; traceTc "utype_defer" (vcat [ppr eqv, ppr ty1,
                                           ppr ty2, ppr items, doc])
            }
       ; return (mkTcCoVarCo eqv) }

--------------
-- Push a new item on the origin stack (the most common case)
uType origin ty1 ty2  -- Push a new item on the origin stack
  = uType_np (pushOrigin ty1 ty2 origin) ty1 ty2

--------------
-- unify_np (short for "no push" on the origin stack) does the work
uType_np origin orig_ty1 orig_ty2
  = do { traceTc "u_tys " $ vcat 
              [ sep [ ppr orig_ty1, text "~", ppr orig_ty2]
              , ppr origin]
       ; co <- go orig_ty1 orig_ty2
       ; if isTcReflCo co
            then traceTc "u_tys yields no coercion" empty
            else traceTc "u_tys yields coercion:" (ppr co)
       ; return co }
  where
    go :: TcType -> TcType -> TcM TcCoercion
	-- The arguments to 'go' are always semantically identical 
	-- to orig_ty{1,2} except for looking through type synonyms

        -- Variables; go for uVar
	-- Note that we pass in *original* (before synonym expansion), 
        -- so that type variables tend to get filled in with 
        -- the most informative version of the type
    go (TyVarTy tv1) ty2 
      = do { lookup_res <- lookupTcTyVar tv1
           ; case lookup_res of
               Filled ty1   -> go ty1 ty2
               Unfilled ds1 -> uUnfilledVar origin NotSwapped tv1 ds1 ty2 }
    go ty1 (TyVarTy tv2) 
      = do { lookup_res <- lookupTcTyVar tv2
           ; case lookup_res of
               Filled ty2   -> go ty1 ty2
               Unfilled ds2 -> uUnfilledVar origin IsSwapped tv2 ds2 ty1 }

        -- See Note [Expanding synonyms during unification]
	--
	-- Also NB that we recurse to 'go' so that we don't push a
	-- new item on the origin stack. As a result if we have
	--   type Foo = Int
	-- and we try to unify  Foo ~ Bool
	-- we'll end up saying "can't match Foo with Bool"
	-- rather than "can't match "Int with Bool".  See Trac #4535.
    go ty1 ty2
      | Just ty1' <- tcView ty1 = go ty1' ty2
      | Just ty2' <- tcView ty2 = go ty1  ty2'
      	     
        -- Functions (or predicate functions) just check the two parts
    go (FunTy fun1 arg1) (FunTy fun2 arg2)
      = do { co_l <- uType origin fun1 fun2
           ; co_r <- uType origin arg1 arg2
           ; return $ mkTcFunCo co_l co_r }

        -- Always defer if a type synonym family (type function)
      	-- is involved.  (Data families behave rigidly.)
    go ty1@(TyConApp tc1 _) ty2
      | isSynFamilyTyCon tc1 = uType_defer origin ty1 ty2   
    go ty1 ty2@(TyConApp tc2 _)
      | isSynFamilyTyCon tc2 = uType_defer origin ty1 ty2   

    go (TyConApp tc1 tys1) (TyConApp tc2 tys2)
      -- See Note [Mismatched type lists and application decomposition]
      | tc1 == tc2, length tys1 == length tys2
      = do { cos <- zipWithM (uType origin) tys1 tys2
           ; return $ mkTcTyConAppCo tc1 cos }
     
	-- See Note [Care with type applications]
        -- Do not decompose FunTy against App; 
        -- it's often a type error, so leave it for the constraint solver
    go (AppTy s1 t1) (AppTy s2 t2)
      = go_app s1 t1 s2 t2

    go (AppTy s1 t1) (TyConApp tc2 ts2)
      | Just (ts2', t2') <- snocView ts2
      = ASSERT( isDecomposableTyCon tc2 ) 
        go_app s1 t1 (TyConApp tc2 ts2') t2'

    go (TyConApp tc1 ts1) (AppTy s2 t2) 
      | Just (ts1', t1') <- snocView ts1
      = ASSERT( isDecomposableTyCon tc1 ) 
        go_app (TyConApp tc1 ts1') t1' s2 t2 

    go ty1 ty2
      | tcIsForAllTy ty1 || tcIsForAllTy ty2 
      = unifySigmaTy origin ty1 ty2

        -- Anything else fails
    go ty1 ty2 = uType_defer origin ty1 ty2 -- failWithMisMatch origin

    ------------------
    go_app s1 t1 s2 t2
      = do { co_s <- uType_np origin s1 s2  -- See Note [Unifying AppTy]
           ; co_t <- uType origin t1 t2        
           ; return $ mkTcAppCo co_s co_t }

unifySigmaTy :: [EqOrigin] -> TcType -> TcType -> TcM TcCoercion
unifySigmaTy origin ty1 ty2
  = do { let (tvs1, body1) = tcSplitForAllTys ty1
             (tvs2, body2) = tcSplitForAllTys ty2

       ; defer_or_continue (not (equalLength tvs1 tvs2)) $ do {
         skol_tvs <- tcInstSkolTyVars tvs1
                  -- Get location from monad, not from tvs1
       ; let tys      = mkTyVarTys skol_tvs
             in_scope = mkInScopeSet (mkVarSet skol_tvs)
             phi1     = Type.substTy (mkTvSubst in_scope (zipTyEnv tvs1 tys)) body1
             phi2     = Type.substTy (mkTvSubst in_scope (zipTyEnv tvs2 tys)) body2
	     skol_info = UnifyForAllSkol skol_tvs phi1

       ; (ev_binds, co) <- checkConstraints skol_info skol_tvs [] $
                           uType origin phi1 phi2

       ; return (foldr mkTcForAllCo (TcLetCo ev_binds co) skol_tvs) } }
  where
    defer_or_continue True  _ = uType_defer origin ty1 ty2
    defer_or_continue False m = m
\end{code}

Note [Care with type applications]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Note: type applications need a bit of care!
They can match FunTy and TyConApp, so use splitAppTy_maybe
NB: we've already dealt with type variables and Notes,
so if one type is an App the other one jolly well better be too

Note [Unifying AppTy]
~~~~~~~~~~~~~~~~~~~~~
Consider unifying  (m Int) ~ (IO Int) where m is a unification variable 
that is now bound to (say) (Bool ->).  Then we want to report 
     "Can't unify (Bool -> Int) with (IO Int)
and not 
     "Can't unify ((->) Bool) with IO"
That is why we use the "_np" variant of uType, which does not alter the error
message.

Note [Mismatched type lists and application decomposition]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
When we find two TyConApps, you might think that the argument lists 
are guaranteed equal length.  But they aren't. Consider matching
	w (T x) ~ Foo (T x y)
We do match (w ~ Foo) first, but in some circumstances we simply create
a deferred constraint; and then go ahead and match (T x ~ T x y).
This came up in Trac #3950.

So either 
   (a) either we must check for identical argument kinds 
       when decomposing applications,
  
   (b) or we must be prepared for ill-kinded unification sub-problems

Currently we adopt (b) since it seems more robust -- no need to maintain
a global invariant.

Note [Expanding synonyms during unification]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
We expand synonyms during unification, but:
 * We expand *after* the variable case so that we tend to unify
   variables with un-expanded type synonym. This just makes it
   more likely that the inferred types will mention type synonyms
   understandable to the user

 * We expand *before* the TyConApp case.  For example, if we have
      type Phantom a = Int
   and are unifying
      Phantom Int ~ Phantom Char
   it is *wrong* to unify Int and Char.

Note [Deferred Unification]
~~~~~~~~~~~~~~~~~~~~~~~~~~~
We may encounter a unification ty1 ~ ty2 that cannot be performed syntactically,
and yet its consistency is undetermined. Previously, there was no way to still
make it consistent. So a mismatch error was issued.

Now these unfications are deferred until constraint simplification, where type
family instances and given equations may (or may not) establish the consistency.
Deferred unifications are of the form
                F ... ~ ...
or              x ~ ...
where F is a type function and x is a type variable.
E.g.
        id :: x ~ y => x -> y
        id e = e

involves the unfication x = y. It is deferred until we bring into account the
context x ~ y to establish that it holds.

If available, we defer original types (rather than those where closed type
synonyms have already been expanded via tcCoreView).  This is, as usual, to
improve error messages.


%************************************************************************
%*                                                                      *
                 uVar and friends
%*                                                                      *
%************************************************************************

@uVar@ is called when at least one of the types being unified is a
variable.  It does {\em not} assume that the variable is a fixed point
of the substitution; rather, notice that @uVar@ (defined below) nips
back into @uTys@ if it turns out that the variable is already bound.

\begin{code}
uUnfilledVar :: [EqOrigin]
             -> SwapFlag
             -> TcTyVar -> TcTyVarDetails       -- Tyvar 1
             -> TcTauType  			-- Type 2
             -> TcM TcCoercion
-- "Unfilled" means that the variable is definitely not a filled-in meta tyvar
--            It might be a skolem, or untouchable, or meta

uUnfilledVar origin swapped tv1 details1 (TyVarTy tv2)
  | tv1 == tv2  -- Same type variable => no-op
  = return (mkTcReflCo (mkTyVarTy tv1))

  | otherwise  -- Distinct type variables
  = do  { lookup2 <- lookupTcTyVar tv2
        ; case lookup2 of
            Filled ty2'       -> uUnfilledVar origin swapped tv1 details1 ty2' 
            Unfilled details2 -> uUnfilledVars origin swapped tv1 details1 tv2 details2
        }

uUnfilledVar origin swapped tv1 details1 non_var_ty2  -- ty2 is not a type variable
  = case details1 of
      MetaTv TauTv ref1 
        -> do { mb_ty2' <- checkTauTvUpdate tv1 non_var_ty2
              ; case mb_ty2' of
                  Nothing   -> do { traceTc "Occ/kind defer" (ppr tv1); defer }
                  Just ty2' -> updateMeta tv1 ref1 ty2'
              }

      _other -> do { traceTc "Skolem defer" (ppr tv1); defer }	-- Skolems of all sorts
  where
    defer | Just ty2' <- tcView non_var_ty2	-- Note [Avoid deferring]
    	    	         	   		-- non_var_ty2 isn't expanded yet
          = uUnfilledVar origin swapped tv1 details1 ty2'
          | otherwise
          = unSwap swapped (uType_defer origin) (mkTyVarTy tv1) non_var_ty2
          -- Occurs check or an untouchable: just defer
	  -- NB: occurs check isn't necessarily fatal: 
	  --     eg tv1 occured in type family parameter

----------------
uUnfilledVars :: [EqOrigin]
              -> SwapFlag
              -> TcTyVar -> TcTyVarDetails      -- Tyvar 1
              -> TcTyVar -> TcTyVarDetails      -- Tyvar 2
              -> TcM TcCoercion
-- Invarant: The type variables are distinct,
--           Neither is filled in yet

uUnfilledVars origin swapped tv1 details1 tv2 details2
  = do { traceTc "uUnfilledVars" (    text "trying to unify" <+> ppr k1
                                  <+> text "with"            <+> ppr k2)
       ; let ctxt = mkKindErrorCtxt ty1 ty2 k1 k2
       ; sub_kind <- addErrCtxtM ctxt $ unifyKind k1 k2

       ; case (sub_kind, details1, details2) of
           -- k1 < k2, so update tv2
           (LT, _, MetaTv _ ref2) -> updateMeta tv2 ref2 ty1

           -- k2 < k1, so update tv1
           (GT, MetaTv _ ref1, _) -> updateMeta tv1 ref1 ty2

	   -- k1 = k2, so we are free to update either way
           (EQ, MetaTv i1 ref1, MetaTv i2 ref2)
                | nicer_to_update_tv1 i1 i2 -> updateMeta tv1 ref1 ty2
                | otherwise                 -> updateMeta tv2 ref2 ty1
           (EQ, MetaTv _ ref1, _) -> updateMeta tv1 ref1 ty2
           (EQ, _, MetaTv _ ref2) -> updateMeta tv2 ref2 ty1

	   -- Can't do it in-place, so defer
	   -- This happens for skolems of all sorts
           (_, _, _) -> unSwap swapped (uType_defer origin) ty1 ty2 } 
  where
    k1       = tyVarKind tv1
    k2       = tyVarKind tv2
    ty1      = mkTyVarTy tv1
    ty2      = mkTyVarTy tv2

    nicer_to_update_tv1 _     SigTv = True
    nicer_to_update_tv1 SigTv _     = False
    nicer_to_update_tv1 _         _ = isSystemName (Var.varName tv1)
        -- Try not to update SigTvs; and try to update sys-y type
        -- variables in preference to ones gotten (say) by
        -- instantiating a polymorphic function with a user-written
        -- type sig

----------------
checkTauTvUpdate :: TcTyVar -> TcType -> TcM (Maybe TcType)
--    (checkTauTvUpdate tv ty)
-- We are about to update the TauTv tv with ty.
-- Check (a) that tv doesn't occur in ty (occurs check)
--       (b) that kind(ty) is a sub-kind of kind(tv)
--       (c) that ty does not contain any type families, see Note [Type family sharing]
-- 
-- We have two possible outcomes:
-- (1) Return the type to update the type variable with, 
--        [we know the update is ok]
-- (2) Return Nothing,
--        [the update might be dodgy]
--
-- Note that "Nothing" does not mean "definite error".  For example
--   type family F a
--   type instance F Int = Int
-- consider
--   a ~ F a
-- This is perfectly reasonable, if we later get a ~ Int.  For now, though,
-- we return Nothing, leaving it to the later constraint simplifier to
-- sort matters out.

checkTauTvUpdate tv ty
  = do { ty' <- zonkTcType ty
       ; let k2 = typeKind ty'
       ; k1 <- zonkTcKind (tyVarKind tv)
       ; let ctxt = mkKindErrorCtxt (mkTyVarTy tv) ty' k1 k2
       ; sub_k <- addErrCtxtM ctxt $
                  unifyKind (tyVarKind tv) (typeKind ty')

       ; case sub_k of
           LT -> return Nothing
           _  -> return (ok ty') }
  where 
    ok :: TcType -> Maybe TcType 
    -- Checks that tv does not occur in the arg type
    -- expanding type synonyms where necessary to make this so
    -- eg type Phantom a = Bool
    --     ok (tv -> Int)         = Nothing
    --     ok (x -> Int)          = Just (x -> Int)
    --     ok (Phantom tv -> Int) = Just (Bool -> Int)
    ok (TyVarTy tv') | not (tv == tv') = Just (TyVarTy tv') 
    ok this_ty@(TyConApp tc tys) 
      | not (isSynFamilyTyCon tc), Just tys' <- allMaybes (map ok tys) 
      = Just (TyConApp tc tys') 
      | isSynTyCon tc, Just ty_expanded <- tcView this_ty
      = ok ty_expanded -- See Note [Type synonyms and the occur check] 
    ok (FunTy arg res) | Just arg' <- ok arg, Just res' <- ok res
                       = Just (FunTy arg' res') 
    ok (AppTy fun arg) | Just fun' <- ok fun, Just arg' <- ok arg 
                       = Just (AppTy fun' arg') 
    ok (ForAllTy tv1 ty1) | Just ty1' <- ok ty1 = Just (ForAllTy tv1 ty1') 
    -- Fall-through 
    ok _ty = Nothing 
\end{code}

Note [Avoid deferring]
~~~~~~~~~~~~~~~~~~~~~~
We try to avoid creating deferred constraints only for efficiency.
Example (Trac #4917)
       a ~ Const a b
where type Const a b = a.  We can solve this immediately, even when
'a' is a skolem, just by expanding the synonym.

Note [Type synonyms and the occur check]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Generally speaking we try to update a variable with type synonyms not
expanded, which improves later error messages, unless looking
inside a type synonym may help resolve a spurious occurs check
error. Consider:
          type A a = ()

          f :: (A a -> a -> ()) -> ()
          f = \ _ -> ()

          x :: ()
          x = f (\ x p -> p x)

We will eventually get a constraint of the form t ~ A t. The ok function above will 
properly expand the type (A t) to just (), which is ok to be unified with t. If we had
unified with the original type A t, we would lead the type checker into an infinite loop. 

Hence, if the occurs check fails for a type synonym application, then (and *only* then), 
the ok function expands the synonym to detect opportunities for occurs check success using
the underlying definition of the type synonym. 

The same applies later on in the constraint interaction code; see TcInteract, 
function @occ_check_ok@. 


Note [Type family sharing]
~~~~~~~~~~~~~~ 
We must avoid eagerly unifying type variables to types that contain function symbols, 
because this may lead to loss of sharing, and in turn, in very poor performance of the
constraint simplifier. Assume that we have a wanted constraint: 
{ 
  m1 ~ [F m2], 
  m2 ~ [F m3], 
  m3 ~ [F m4], 
  D m1, 
  D m2, 
  D m3 
} 
where D is some type class. If we eagerly unify m1 := [F m2], m2 := [F m3], m3 := [F m2], 
then, after zonking, our constraint simplifier will be faced with the following wanted 
constraint: 
{ 
  D [F [F [F m4]]], 
  D [F [F m4]], 
  D [F m4] 
} 
which has to be flattened by the constraint solver. However, because the sharing is lost, 
an polynomially larger number of flatten skolems will be created and the constraint sets 
we are working with will be polynomially larger. 

Instead, if we defer the unifications m1 := [F m2], etc. we will only be generating three 
flatten skolems, which is the maximum possible sharing arising from the original constraint. 

\begin{code}
data LookupTyVarResult	-- The result of a lookupTcTyVar call
  = Unfilled TcTyVarDetails	-- SkolemTv or virgin MetaTv
  | Filled   TcType

lookupTcTyVar :: TcTyVar -> TcM LookupTyVarResult
lookupTcTyVar tyvar 
  | MetaTv _ ref <- details
  = do { meta_details <- readMutVar ref
       ; case meta_details of
           Indirect ty -> return (Filled ty)
           Flexi -> do { is_untch <- isUntouchable tyvar
                       ; let    -- Note [Unifying untouchables]
                             ret_details | is_untch  = vanillaSkolemTv
                                         | otherwise = details
       	               ; return (Unfilled ret_details) } }
  | otherwise
  = return (Unfilled details)
  where
    details = ASSERT2( isTcTyVar tyvar, ppr tyvar )
              tcTyVarDetails tyvar

updateMeta :: TcTyVar -> TcRef MetaDetails -> TcType -> TcM TcCoercion
updateMeta tv1 ref1 ty2
  = do { writeMetaTyVarRef tv1 ref1 ty2
       ; return (mkTcReflCo ty2) }
\end{code}

Note [Unifying untouchables]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~
We treat an untouchable type variable as if it was a skolem.  That
ensures it won't unify with anything.  It's a slight had, because
we return a made-up TcTyVarDetails, but I think it works smoothly.


%************************************************************************
%*                                                                      *
        Errors and contexts
%*                                                                      *
%************************************************************************

\begin{code}
pushOrigin :: TcType -> TcType -> [EqOrigin] -> [EqOrigin]
pushOrigin ty_act ty_exp origin
  = UnifyOrigin { uo_actual = ty_act, uo_expected = ty_exp } : origin

---------------
wrapEqCtxt :: [EqOrigin] -> TcM a -> TcM a
-- Build a suitable error context from the origin and do the thing inside
-- The "couldn't match" error comes from the innermost item on the stack,
-- and, if there is more than one item, the "Expected/inferred" part
-- comes from the outermost item
wrapEqCtxt []    thing_inside = thing_inside
wrapEqCtxt items thing_inside = addErrCtxtM (unifyCtxt (last items)) thing_inside
\end{code}


-----------------------------------------
	UNUSED FOR NOW
-----------------------------------------

----------------
----------------
-- If an error happens we try to figure out whether the function
-- function has been given too many or too few arguments, and say so.
addSubCtxt :: InstOrigin -> TcType -> TcType -> TcM a -> TcM a
addSubCtxt orig actual_res_ty expected_res_ty thing_inside
  = addErrCtxtM mk_err thing_inside
  where
    mk_err tidy_env
      = do { exp_ty' <- zonkTcType expected_res_ty
           ; act_ty' <- zonkTcType actual_res_ty
           ; let (env1, exp_ty'') = tidyOpenType tidy_env exp_ty'
                 (env2, act_ty'') = tidyOpenType env1     act_ty'
                 (exp_args, _)    = tcSplitFunTys exp_ty''
                 (act_args, _)    = tcSplitFunTys act_ty''

                 len_act_args     = length act_args
                 len_exp_args     = length exp_args

                 message = case orig of
                             OccurrenceOf fun
                                  | len_exp_args < len_act_args -> wrongArgsCtxt "too few"  fun
                                  | len_exp_args > len_act_args -> wrongArgsCtxt "too many" fun
                             _ -> mkExpectedActualMsg act_ty'' exp_ty''
           ; return (env2, message) }


%************************************************************************
%*                                                                      *
                Kind unification
%*                                                                      *
%************************************************************************

Unifying kinds is much, much simpler than unifying types.

One small wrinkle is that as far as the user is concerned, types of kind
Constraint should only be allowed to occur where we expect *exactly* that kind.
We SHOULD NOT allow a type of kind fact to appear in a position expecting
one of argTypeKind or openTypeKind.

The situation is different in the core of the compiler, where we are perfectly
happy to have types of kind Constraint on either end of an arrow.

\begin{code}
matchExpectedFunKind :: TcKind -> TcM (Maybe (TcKind, TcKind))
-- Like unifyFunTy, but does not fail; instead just returns Nothing

matchExpectedFunKind (TyVarTy kvar) = do
    maybe_kind <- readMetaTyVar kvar
    case maybe_kind of
      Indirect fun_kind -> matchExpectedFunKind fun_kind
      Flexi ->
          do { arg_kind <- newMetaKindVar
             ; res_kind <- newMetaKindVar
             ; writeMetaTyVar kvar (mkArrowKind arg_kind res_kind)
             ; return (Just (arg_kind,res_kind)) }

matchExpectedFunKind (FunTy arg_kind res_kind) = return (Just (arg_kind,res_kind))
matchExpectedFunKind _                         = return Nothing

-----------------  
unifyKind :: TcKind           -- k1 (actual)
          -> TcKind           -- k2 (expected)
          -> TcM Ordering     -- Returns the relation between the kinds
                              -- LT <=> k1 is a sub-kind of k2

unifyKind (TyVarTy kv1) k2 = uKVar False kv1 k2
unifyKind k1 (TyVarTy kv2) = uKVar True  kv2 k1

unifyKind k1 k2       -- See Note [Expanding synonyms during unification]
  | Just k1' <- tcView k1 = unifyKind k1' k2
  | Just k2' <- tcView k2 = unifyKind k1  k2'

unifyKind k1@(TyConApp kc1 []) k2@(TyConApp kc2 [])
  | kc1 == kc2               = return EQ
  | kc1 `tcIsSubKindCon` kc2 = return LT
  | kc2 `tcIsSubKindCon` kc1 = return GT
  | otherwise                = unifyKindMisMatch k1 k2

unifyKind k1 k2 = do { unifyKindEq k1 k2; return EQ }
  -- In all other cases, let unifyKindEq do the work

uKVar :: Bool -> MetaKindVar -> TcKind -> TcM Ordering
uKVar isFlipped kv1 k2
  | isMetaTyVar kv1
  = do  { mb_k1 <- readMetaTyVar kv1
        ; case mb_k1 of
            Flexi -> uUnboundKVar kv1 k2 >> return EQ
            Indirect k1 -> unifyKind k1 k2 }
  | TyVarTy kv2 <- k2, isMetaTyVar kv2
  = uKVar (not isFlipped) kv2 (TyVarTy kv1)
  | TyVarTy kv2 <- k2, kv1 == kv2 = return EQ
  | otherwise = if isFlipped 
                then unifyKindMisMatch k2 (TyVarTy kv1)
                else unifyKindMisMatch (TyVarTy kv1) k2

---------------------------
unifyKindEq :: TcKind -> TcKind -> TcM ()
unifyKindEq (TyVarTy kv1) k2 = uKVarEq False kv1 k2
unifyKindEq k1 (TyVarTy kv2) = uKVarEq True  kv2 k1

unifyKindEq (FunTy a1 r1) (FunTy a2 r2)
  = do { unifyKindEq a1 a2; unifyKindEq r1 r2 }
  
unifyKindEq (TyConApp kc1 k1s) (TyConApp kc2 k2s)
  | kc1 == kc2
  = ASSERT (length k1s == length k2s)
       -- Should succeed since the kind constructors are the same, 
       -- and the kinds are sort-checked, thus fully applied
    zipWithM_ unifyKindEq k1s k2s

unifyKindEq k1 k2 = unifyKindMisMatch k1 k2

----------------
-- For better error messages, we record whether we've flipped the kinds
-- during the process.
uKVarEq :: Bool -> MetaKindVar -> TcKind -> TcM ()
uKVarEq isFlipped kv1 k2
  | isMetaTyVar kv1
  = do  { mb_k1 <- readMetaTyVar kv1
        ; case mb_k1 of
            Flexi -> uUnboundKVar kv1 k2
            Indirect k1 -> unifyKindEq k1 k2 }
  | TyVarTy kv2 <- k2, isMetaTyVar kv2
  = uKVarEq (not isFlipped) kv2 (TyVarTy kv1)
  | TyVarTy kv2 <- k2, kv1 == kv2 = return ()
  | otherwise = if isFlipped 
                then unifyKindMisMatch k2 (TyVarTy kv1)
                else unifyKindMisMatch (TyVarTy kv1) k2

----------------
uUnboundKVar :: MetaKindVar -> TcKind -> TcM ()
uUnboundKVar kv1 k2@(TyVarTy kv2)
  | kv1 == kv2 = return ()
  | isMetaTyVar kv2   -- Distinct kind variables
  = do  { mb_k2 <- readMetaTyVar kv2
        ; case mb_k2 of
            Indirect k2 -> uUnboundKVar kv1 k2
            Flexi -> writeMetaTyVar kv1 k2 }
  | otherwise = writeMetaTyVar kv1 k2

uUnboundKVar kv1 non_var_k2
  = do  { k2' <- zonkTcKind non_var_k2
        ; kindOccurCheck kv1 k2'
        ; let k2'' = kindSimpleKind k2'
                -- MetaKindVars must be bound only to simple kinds
        ; writeMetaTyVar kv1 k2'' }

----------------
kindOccurCheck :: TyVar -> Type -> TcM ()
kindOccurCheck kv1 k2   -- k2 is zonked
  = if elemVarSet kv1 (tyVarsOfType k2)
    then failWithTc (kindOccurCheckErr kv1 k2)
    else return ()

kindSimpleKind :: Kind -> SimpleKind
-- (kindSimpleKind k) returns a simple kind k' such that k' <= k
kindSimpleKind k
  | isOpenTypeKind k = liftedTypeKind
  | isArgTypeKind  k = liftedTypeKind
  | otherwise        = k

mkKindErrorCtxt :: Type -> Type -> Kind -> Kind -> TidyEnv -> TcM (TidyEnv, SDoc)
mkKindErrorCtxt ty1 ty2 k1 k2 env0
  = let (env1, ty1') = tidyOpenType env0 ty1
        (env2, ty2') = tidyOpenType env1 ty2
        (env3, k1' ) = tidyOpenKind env2 k1
        (env4, k2' ) = tidyOpenKind env3 k2
    in do ty1 <- zonkTcType ty1'
          ty2 <- zonkTcType ty2'
          k1  <- zonkTcKind k1'
          k2  <- zonkTcKind k2'
          return (env4, 
                  vcat [ ptext (sLit "Kind incompatibility when matching types:")
                       , nest 2 (vcat [ ppr ty1 <+> dcolon <+> ppr k1
                                      , ppr ty2 <+> dcolon <+> ppr k2 ]) ])

unifyKindMisMatch :: TcKind -> TcKind -> TcM a
unifyKindMisMatch ki1 ki2 = do
    ki1' <- zonkTcKind ki1
    ki2' <- zonkTcKind ki2
    let msg = hang (ptext (sLit "Couldn't match kind"))
              2 (sep [quotes (ppr ki1'),
                      ptext (sLit "against"),
                      quotes (ppr ki2')])
    failWithTc msg

----------------
kindOccurCheckErr :: Var -> Type -> SDoc
kindOccurCheckErr tyvar ty
  = hang (ptext (sLit "Occurs check: cannot construct the infinite kind:"))
       2 (sep [ppr tyvar, char '=', ppr ty])
\end{code}

%************************************************************************
%*                                                                      *
\subsection{Checking signature type variables}
%*                                                                      *
%************************************************************************

@checkSigTyVars@ checks that a set of universally quantified type varaibles
are not mentioned in the environment.  In particular:

        (a) Not mentioned in the type of a variable in the envt
                eg the signature for f in this:

                        g x = ... where
                                        f :: a->[a]
                                        f y = [x,y]

                Here, f is forced to be monorphic by the free occurence of x.

        (d) Not (unified with another type variable that is) in scope.
                eg f x :: (r->r) = (\y->y) :: forall a. a->r
            when checking the expression type signature, we find that
            even though there is nothing in scope whose type mentions r,
            nevertheless the type signature for the expression isn't right.

            Another example is in a class or instance declaration:
                class C a where
                   op :: forall b. a -> b
                   op x = x
            Here, b gets unified with a

Before doing this, the substitution is applied to the signature type variable.

-- \begin{code}
checkSigTyVars :: [TcTyVar] -> TcM ()
checkSigTyVars sig_tvs = check_sig_tyvars emptyVarSet sig_tvs

checkSigTyVarsWrt :: TcTyVarSet -> [TcTyVar] -> TcM ()
-- The extra_tvs can include boxy type variables;
--      e.g. TcMatches.tcCheckExistentialPat
checkSigTyVarsWrt extra_tvs sig_tvs
  = do  { extra_tvs' <- zonkTcTyVarsAndFV extra_tvs
        ; check_sig_tyvars extra_tvs' sig_tvs }

check_sig_tyvars
        :: TcTyVarSet   -- Global type variables. The universally quantified
                        --      tyvars should not mention any of these
                        --      Guaranteed already zonked.
        -> [TcTyVar]    -- Universally-quantified type variables in the signature
                        --      Guaranteed to be skolems
        -> TcM ()
check_sig_tyvars _ []
  = return ()
check_sig_tyvars extra_tvs sig_tvs
  = ASSERT( all isTcTyVar sig_tvs && all isSkolemTyVar sig_tvs )
    do  { gbl_tvs <- tcGetGlobalTyVars
        ; traceTc "check_sig_tyvars" $ vcat 
               [ text "sig_tys" <+> ppr sig_tvs
               , text "gbl_tvs" <+> ppr gbl_tvs
               , text "extra_tvs" <+> ppr extra_tvs]

        ; let env_tvs = gbl_tvs `unionVarSet` extra_tvs
        ; when (any (`elemVarSet` env_tvs) sig_tvs)
               (bleatEscapedTvs env_tvs sig_tvs sig_tvs)
        }

bleatEscapedTvs :: TcTyVarSet   -- The global tvs
                -> [TcTyVar]    -- The possibly-escaping type variables
                -> [TcTyVar]    -- The zonked versions thereof
                -> TcM ()
-- Complain about escaping type variables
-- We pass a list of type variables, at least one of which
-- escapes.  The first list contains the original signature type variable,
-- while the second  contains the type variable it is unified to (usually itself)
bleatEscapedTvs globals sig_tvs zonked_tvs
  = do  { env0 <- tcInitTidyEnv
        ; let (env1, tidy_tvs)        = tidyOpenTyVars env0 sig_tvs
              (env2, tidy_zonked_tvs) = tidyOpenTyVars env1 zonked_tvs

        ; (env3, msgs) <- foldlM check (env2, []) (tidy_tvs `zip` tidy_zonked_tvs)
        ; failWithTcM (env3, main_msg $$ nest 2 (vcat msgs)) }
  where
    main_msg = ptext (sLit "Inferred type is less polymorphic than expected")

    check (tidy_env, msgs) (sig_tv, zonked_tv)
      | not (zonked_tv `elemVarSet` globals) = return (tidy_env, msgs)
      | otherwise
      = do { lcl_env <- getLclTypeEnv
           ; (tidy_env1, globs) <- findGlobals (unitVarSet zonked_tv) lcl_env tidy_env
           ; return (tidy_env1, escape_msg sig_tv zonked_tv globs : msgs) }

-----------------------
escape_msg :: Var -> Var -> [SDoc] -> SDoc
escape_msg sig_tv zonked_tv globs
  | notNull globs
  = vcat [sep [msg, ptext (sLit "is mentioned in the environment:")],
          nest 2 (vcat globs)]
  | otherwise
  = msg <+> ptext (sLit "escapes")
        -- Sigh.  It's really hard to give a good error message
        -- all the time.   One bad case is an existential pattern match.
        -- We rely on the "When..." context to help.
  where
    msg = ptext (sLit "Quantified type variable") <+> quotes (ppr sig_tv) <+> is_bound_to
    is_bound_to
        | sig_tv == zonked_tv = empty
        | otherwise = ptext (sLit "is unified with") <+> quotes (ppr zonked_tv) <+> ptext (sLit "which")
-- \end{code}

These two context are used with checkSigTyVars

\begin{code}
sigCtxt :: Id -> [TcTyVar] -> TcThetaType -> TcTauType
        -> TidyEnv -> TcM (TidyEnv, MsgDoc)
sigCtxt id sig_tvs sig_theta sig_tau tidy_env = do
    actual_tau <- zonkTcType sig_tau
    let
        (env1, tidy_sig_tvs)    = tidyOpenTyVars tidy_env sig_tvs
        (env2, tidy_sig_rho)    = tidyOpenType env1 (mkPhiTy sig_theta sig_tau)
        (env3, tidy_actual_tau) = tidyOpenType env2 actual_tau
        sub_msg = vcat [ptext (sLit "Signature type:    ") <+> pprType (mkForAllTys tidy_sig_tvs tidy_sig_rho),
                        ptext (sLit "Type to generalise:") <+> pprType tidy_actual_tau
                   ]
        msg = vcat [ptext (sLit "When trying to generalise the type inferred for") <+> quotes (ppr id),
                    nest 2 sub_msg]

    return (env3, msg)
\end{code}
