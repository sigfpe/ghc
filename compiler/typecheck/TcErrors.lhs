\begin{code}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS -fno-warn-tabs #-}
-- The above warning supression flag is a temporary kludge.
-- While working on this module you are encouraged to remove it and
-- detab the module (please do the detabbing in a separate patch). See
--     http://hackage.haskell.org/trac/ghc/wiki/Commentary/CodingStyle#TabsvsSpaces
-- for details

module TcErrors( 
       reportUnsolved, ErrEnv,
       warnDefaulting,
       unifyCtxt,
       misMatchMsg,

       flattenForAllErrorTcS,
       solverDepthErrorTcS
  ) where

#include "HsVersions.h"

import TcRnMonad
import TcMType
import TcType
import TypeRep
import Type
import Kind ( isKind )
import Unify            ( tcMatchTys )
import Inst
import InstEnv
import TyCon
import TcEvidence
import Name
import NameEnv
import Id               ( idType )
import Var
import VarSet
import VarEnv
import Bag
import Maybes
import ErrUtils         ( ErrMsg, makeIntoWarning, pprLocErrMsg )
import Util
import FastString
import Outputable
import DynFlags
import Data.List        ( partition, mapAccumL )
import Data.Either      ( partitionEithers )
-- import Control.Monad    ( when )
\end{code}

%************************************************************************
%*									*
\section{Errors and contexts}
%*									*
%************************************************************************

ToDo: for these error messages, should we note the location as coming
from the insts, or just whatever seems to be around in the monad just
now?

\begin{code}
-- We keep an environment mapping coercion ids to the error messages they
-- trigger; this is handy for -fwarn--type-errors
type ErrEnv = VarEnv [ErrMsg]

reportUnsolved :: Bool -> WantedConstraints -> TcM (Bag EvBind)
reportUnsolved runtimeCoercionErrors wanted
  | isEmptyWC wanted
  = return emptyBag
  | otherwise
  = do {   -- Zonk to un-flatten any flatten-skols
         wanted  <- zonkWC wanted

       ; env0 <- tcInitTidyEnv
       ; defer <- if runtimeCoercionErrors 
                  then do { ev <- newTcEvBinds
                          ; return (Just ev) }
                  else return Nothing

       ; errs_so_far <- ifErrsM (return True) (return False)
       ; let tidy_env = tidyFreeTyVars env0 free_tvs
             free_tvs = tyVarsOfWC wanted
             err_ctxt = CEC { cec_encl  = []
                            , cec_insol = errs_so_far
                            , cec_extra = empty
                            , cec_tidy  = tidy_env
                            , cec_defer = defer }

       ; traceTc "reportUnsolved" (ppr free_tvs $$ ppr wanted)

       ; reportWanteds err_ctxt wanted

       ; case defer of
           Nothing -> return emptyBag
           Just ev -> getTcEvBinds ev }

--------------------------------------------
--      Internal functions
--------------------------------------------

data ReportErrCtxt 
    = CEC { cec_encl :: [Implication]  -- Enclosing implications
                	       	       --   (innermost first)
                                       -- ic_skols and givens are tidied, rest are not
          , cec_tidy  :: TidyEnv
          , cec_extra :: SDoc       -- Add this to each error message
          , cec_insol :: Bool       -- True <=> do not report errors involving 
                                    --          ambiguous errors
          , cec_defer :: Maybe EvBindsVar 
                         -- Nothinng <=> errors are, well, errors
                         -- Just ev  <=> make errors into warnings, and emit evidence
                         --              bindings into 'ev' for unsolved constraints
      }

reportImplic :: ReportErrCtxt -> Implication -> TcM ()
reportImplic ctxt implic@(Implic { ic_skols = tvs, ic_given = given
                                 , ic_wanted = wanted, ic_binds = evb
                                 , ic_insol = insoluble, ic_loc = loc })
  | BracketSkol <- ctLocOrigin loc
  , not insoluble -- For Template Haskell brackets report only
  = return ()     -- definite errors. The whole thing will be re-checked
                  -- later when we plug it in, and meanwhile there may
                  -- certainly be un-satisfied constraints

  | otherwise
  = reportWanteds ctxt' wanted
  where
    (env1, tvs') = mapAccumL tidyTyVarBndr (cec_tidy ctxt) tvs
    implic' = implic { ic_skols = tvs'
                     , ic_given = map (tidyEvVar env1) given
                     , ic_loc   = tidyGivenLoc env1 loc }
    ctxt' = ctxt { cec_tidy  = env1
                 , cec_encl  = implic' : cec_encl ctxt
                 , cec_defer = case cec_defer ctxt of
                                 Nothing -> Nothing
                                 Just {} -> Just evb }

reportWanteds :: ReportErrCtxt -> WantedConstraints -> TcM ()
reportWanteds ctxt (WC { wc_flat = flats, wc_insol = insols, wc_impl = implics })
  = reportTidyWanteds ctxt tidy_insols tidy_flats implics
  where
    env = cec_tidy ctxt
    tidy_insols = mapBag (tidyCt env) insols
    tidy_flats  = mapBag (tidyCt env) flats

reportTidyWanteds :: ReportErrCtxt -> Bag Ct -> Bag Ct -> Bag Implication -> TcM ()
reportTidyWanteds ctxt insols flats implics
  | Just ev_binds_var <- cec_defer ctxt
  = do { -- Defer errors to runtime
         -- See Note [Deferring coercion errors to runtime] in TcSimplify
         mapBagM_ (deferToRuntime ev_binds_var ctxt mkFlatErr) 
                  (flats `unionBags` insols)
       ; mapBagM_ (reportImplic ctxt) implics }

  | otherwise
  = do { reportInsolsAndFlats ctxt insols flats
       ; mapBagM_ (reportImplic ctxt) implics }
             

deferToRuntime :: EvBindsVar -> ReportErrCtxt -> (ReportErrCtxt -> Ct -> TcM ErrMsg) 
               -> Ct -> TcM ()
deferToRuntime ev_binds_var ctxt mk_err_msg ct 
  | Wanted loc <- cc_flavor ct
  = do { err <- setCtLoc loc $
                mk_err_msg ctxt ct
       ; let ev_id   = cc_id ct
             err_msg = pprLocErrMsg err
             err_fs  = mkFastString $ showSDoc $ 
                       err_msg $$ text "(deferred type error)"

         -- Create the binding
       ; addTcEvBind ev_binds_var ev_id (EvDelayedError (idType ev_id) err_fs)

         -- And emit a warning
       ; reportWarning (makeIntoWarning err) }

  | otherwise   -- Do not set any evidence for Given/Derived
  = return ()   

reportInsolsAndFlats :: ReportErrCtxt -> Cts -> Cts -> TcM ()
reportInsolsAndFlats ctxt insols flats
  = tryReporters 
      [ -- First deal with things that are utterly wrong
        -- Like Int ~ Bool (incl nullary TyCons)
        -- or  Int ~ t a   (AppTy on one side)
        ("Utterly wrong",  utterly_wrong,   groupErrs (mkEqErr ctxt))

        -- Report equalities of form (a~ty).  They are usually
        -- skolem-equalities, and they cause confusing knock-on 
        -- effects in other errors; see test T4093b.
      , ("Skolem equalities",    skolem_eq,       mkReporter (mkEqErr1 ctxt))

      , ("Unambiguous",          unambiguous,     reportFlatErrs ctxt) ]
      (reportAmbigErrs ctxt)
      (bagToList (insols `unionBags` flats))
  where
    utterly_wrong, skolem_eq, unambiguous :: Ct -> PredTree -> Bool

    utterly_wrong _ (EqPred ty1 ty2) = isRigid ty1 && isRigid ty2 
    utterly_wrong _ _ = False

    skolem_eq _ (EqPred ty1 ty2) = isRigidOrSkol ty1 && isRigidOrSkol ty2 
    skolem_eq _ _ = False

    unambiguous ct pred 
      | not (any isAmbiguousTyVar (varSetElems (tyVarsOfCt ct)))
      = True
      | otherwise 
      = case pred of
          EqPred ty1 ty2 -> isNothing (isTyFun_maybe ty1) && isNothing (isTyFun_maybe ty2)
          _              -> False

---------------
isRigid, isRigidOrSkol :: Type -> Bool
isRigid ty 
  | Just (tc,_) <- tcSplitTyConApp_maybe ty = isDecomposableTyCon tc
  | Just {} <- tcSplitAppTy_maybe ty        = True
  | isForAllTy ty                           = True
  | otherwise                               = False

isRigidOrSkol ty 
  | Just tv <- getTyVar_maybe ty = isSkolemTyVar tv
  | otherwise                    = isRigid ty

isTyFun_maybe :: Type -> Maybe TyCon
isTyFun_maybe ty = case tcSplitTyConApp_maybe ty of
                      Just (tc,_) | isSynFamilyTyCon tc -> Just tc
                      _ -> Nothing

-----------------
type Reporter = [Ct] -> TcM ()

mkReporter :: (Ct -> TcM ErrMsg) -> [Ct] -> TcM ()
-- Reports errors one at a time
mkReporter mk_err = mapM_ (\ct -> do { err <- setCtFlavorLoc (cc_flavor ct) $
                                              mk_err ct; 
                                     ; reportError err })

tryReporters :: [(String, Ct -> PredTree -> Bool, Reporter)] -> Reporter -> Reporter
tryReporters reporters deflt cts
  = do { traceTc "tryReporters {" (ppr cts) 
       ; go reporters cts
       ; traceTc "tryReporters }" empty }
  where
    go [] cts = deflt cts 
    go ((str, pred, reporter) : rs) cts
      | null yeses  = traceTc "tryReporters: no" (text str) >> 
                      go rs cts
      | otherwise   = traceTc "tryReporters: yes" (text str <+> ppr yeses) >> 
                      reporter yeses
      where
       yeses = filter keep_me cts
       keep_me ct = pred ct (classifyPredType (ctPred ct))

-----------------
mkFlatErr :: ReportErrCtxt -> Ct -> TcM ErrMsg
-- Context is already set
mkFlatErr ctxt ct   -- The constraint is always wanted
  = case classifyPredType (ctPred ct) of
      ClassPred {}  -> mkDictErr  ctxt [ct]
      IPPred {}     -> mkIPErr    ctxt [ct]
      IrredPred {}  -> mkIrredErr ctxt [ct]
      EqPred {}     -> mkEqErr1 ctxt ct
      TuplePred {}  -> panic "mkFlat"
      
reportAmbigErrs :: ReportErrCtxt -> Reporter
reportAmbigErrs ctxt cts
  | cec_insol ctxt = return ()
  | otherwise      = reportFlatErrs ctxt cts
          -- Only report ambiguity if no other errors (at all) happened
          -- See Note [Avoiding spurious errors] in TcSimplify

reportFlatErrs :: ReportErrCtxt -> Reporter
-- Called once for non-ambigs, once for ambigs
-- Report equality errors, and others only if we've done all 
-- the equalities.  The equality errors are more basic, and
-- can lead to knock on type-class errors
reportFlatErrs ctxt cts
  = tryReporters
      [ ("Equalities", is_equality, groupErrs (mkEqErr ctxt)) ]
      (\cts -> do { let (dicts, ips, irreds) = go cts [] [] []
                  ; groupErrs (mkIPErr    ctxt) ips   
                  ; groupErrs (mkIrredErr ctxt) irreds
                  ; groupErrs (mkDictErr  ctxt) dicts })
      cts
  where
    is_equality _ (EqPred {}) = True
    is_equality _ _           = False

    go [] dicts ips irreds
      = (dicts, ips, irreds)
    go (ct:cts) dicts ips irreds
      = case classifyPredType (ctPred ct) of
          ClassPred {}  -> go cts (ct:dicts) ips irreds
          IPPred {}     -> go cts dicts (ct:ips) irreds
          IrredPred {}  -> go cts dicts ips (ct:irreds)
          _             -> panic "mkFlat"
    -- TuplePreds should have been expanded away by the constraint
    -- simplifier, so they shouldn't show up at this point
    -- And EqPreds are dealt with by the is_equality test


--------------------------------------------
--      Support code 
--------------------------------------------

groupErrs :: ([Ct] -> TcM ErrMsg)  -- Deal with one group
	  -> [Ct]	           -- Unsolved wanteds
          -> TcM ()
-- Group together insts from same location
-- We want to report them together in error messages

groupErrs _ [] 
  = return ()
groupErrs mk_err (ct1 : rest)
  = do  { err <- setCtFlavorLoc flavor $ mk_err cts
        ; reportError err
        ; groupErrs mk_err others }
  where
   flavor            = cc_flavor ct1
   cts               = ct1 : friends
   (friends, others) = partition is_friend rest
   is_friend friend  = cc_flavor friend `same_group` flavor

   same_group :: CtFlavor -> CtFlavor -> Bool
   same_group (Given l1 _) (Given l2 _) = same_loc l1 l2
   same_group (Derived l1) (Derived l2) = same_loc l1 l2
   same_group (Wanted l1)  (Wanted l2)  = same_loc l1 l2
   same_group _ _ = False

   same_loc :: CtLoc o -> CtLoc o -> Bool
   same_loc (CtLoc _ s1 _) (CtLoc _ s2 _) = s1==s2

-- Add the "arising from..." part to a message about bunch of dicts
addArising :: CtOrigin -> SDoc -> SDoc
addArising orig msg = msg $$ nest 2 (pprArising orig)

pprWithArising :: [Ct] -> (WantedLoc, SDoc)
-- Print something like
--    (Eq a) arising from a use of x at y
--    (Show a) arising from a use of p at q
-- Also return a location for the error message
-- Works for Wanted/Derived only
pprWithArising [] 
  = panic "pprWithArising"
pprWithArising (ct:cts)
  | null cts
  = (loc, hang (pprEvVarTheta [cc_id ct]) 
             2 (pprArising (ctLocOrigin (ctWantedLoc ct))))
  | otherwise
  = (loc, vcat (map ppr_one (ct:cts)))
  where
    loc = ctWantedLoc ct
    ppr_one ct = hang (parens (pprType (ctPred ct))) 
                    2 (pprArisingAt (ctWantedLoc ct))

mkErrorReport :: ReportErrCtxt -> SDoc -> TcM ErrMsg
mkErrorReport ctxt msg = mkErrTcM (cec_tidy ctxt, msg $$ cec_extra ctxt)

type UserGiven = ([EvVar], GivenLoc)

getUserGivens :: ReportErrCtxt -> [UserGiven]
-- One item for each enclosing implication
getUserGivens (CEC {cec_encl = ctxt})
  = reverse $
    [ (givens, loc) | Implic {ic_given = givens, ic_loc = loc} <- ctxt
                    , not (null givens) ]
\end{code}

%************************************************************************
%*                  *
                Irreducible predicate errors
%*                  *
%************************************************************************

\begin{code}
mkIrredErr :: ReportErrCtxt -> [Ct] -> TcM ErrMsg
mkIrredErr ctxt cts 
  = mkErrorReport ctxt msg
  where
    (ct1:_) = cts
    orig    = ctLocOrigin (ctWantedLoc ct1)
    givens  = getUserGivens ctxt
    msg = couldNotDeduce givens (map ctPred cts, orig)
\end{code}


%************************************************************************
%*									*
                Implicit parameter errors
%*									*
%************************************************************************

\begin{code}
mkIPErr :: ReportErrCtxt -> [Ct] -> TcM ErrMsg
mkIPErr ctxt cts
  = do { (ctxt', _, ambig_err) <- mkAmbigMsg ctxt cts
       ; mkErrorReport ctxt' (msg $$ ambig_err) }
  where
    (ct1:_) = cts
    orig    = ctLocOrigin (ctWantedLoc ct1)
    preds   = map ctPred cts
    givens  = getUserGivens ctxt
    msg | null givens
        = addArising orig $
          sep [ ptext (sLit "Unbound implicit parameter") <> plural cts
              , nest 2 (pprTheta preds) ] 
        | otherwise
        = couldNotDeduce givens (preds, orig)
\end{code}


%************************************************************************
%*									*
                Equality errors
%*									*
%************************************************************************

\begin{code}
mkEqErr :: ReportErrCtxt -> [Ct] -> TcM ErrMsg
-- Don't have multiple equality errors from the same location
-- E.g.   (Int,Bool) ~ (Bool,Int)   one error will do!
mkEqErr ctxt (ct:_) = mkEqErr1 ctxt ct
mkEqErr _ [] = panic "mkEqErr"

mkEqErr1 :: ReportErrCtxt -> Ct -> TcM ErrMsg
-- Wanted constraints only!
mkEqErr1 ctxt ct
  = case cc_flavor ct of
       Given gl gk -> mkEqErr_help ctxt2 ct False ty1 ty2
              where
                 ctxt2 = ctxt { cec_extra = cec_extra ctxt $$ 
                                inaccessible_msg gl gk }  
    
       flav -> do { let orig = ctLocOrigin (getWantedLoc flav)
                  ; (ctxt1, orig') <- zonkTidyOrigin ctxt orig
                  ; mk_err ctxt1 orig' }
  where
     -- If a GivenSolved then we should not report inaccessible code
    inaccessible_msg loc GivenOrig = hang (ptext (sLit "Inaccessible code in"))
                                        2 (ppr (ctLocOrigin loc))
    inaccessible_msg _ _ = empty

    (ty1, ty2) = getEqPredTys (evVarPred (cc_id ct))

       -- If the types in the error message are the same as the types
       -- we are unifying, don't add the extra expected/actual message
    mk_err ctxt1 (TypeEqOrigin (UnifyOrigin { uo_actual = act, uo_expected = exp })) 
      | act `pickyEqType` ty1
      , exp `pickyEqType` ty2 = mkEqErr_help ctxt1 ct True  ty2 ty1
      | exp `pickyEqType` ty1
      , act `pickyEqType` ty2 = mkEqErr_help ctxt1 ct True  ty1 ty2
      | otherwise             = mkEqErr_help ctxt2 ct False ty1 ty2
      where
        ctxt2 = ctxt1 { cec_extra = msg $$ cec_extra ctxt1 }
        msg   = mkExpectedActualMsg exp act
    mk_err ctxt1 _ = mkEqErr_help ctxt1 ct False ty1 ty2

mkEqErr_help :: ReportErrCtxt
             -> Ct
             -> Bool     -- True  <=> Types are correct way round;
                         --           report "expected ty1, actual ty2"
                         -- False <=> Just report a mismatch without orientation
                         --           The ReportErrCtxt has expected/actual 
             -> TcType -> TcType -> TcM ErrMsg
mkEqErr_help ctxt ct oriented ty1 ty2
  | Just tv1 <- tcGetTyVar_maybe ty1 = mkTyVarEqErr ctxt ct oriented tv1 ty2
  | Just tv2 <- tcGetTyVar_maybe ty2 = mkTyVarEqErr ctxt ct oriented tv2 ty1
  | otherwise   -- Neither side is a type variable
  = do { ctxt' <- mkEqInfoMsg ctxt ct ty1 ty2
       ; mkErrorReport ctxt' (misMatchOrCND ctxt' ct oriented ty1 ty2) }

mkTyVarEqErr :: ReportErrCtxt -> Ct -> Bool -> TcTyVar -> TcType -> TcM ErrMsg
-- tv1 and ty2 are already tidied
mkTyVarEqErr ctxt ct oriented tv1 ty2
  |  isSkolemTyVar tv1 	  -- ty2 won't be a meta-tyvar, or else the thing would
     		   	  -- be oriented the other way round; see TcCanonical.reOrient
  || isSigTyVar tv1 && not (isTyVarTy ty2)
  = mkErrorReport (addExtraTyVarInfo ctxt ty1 ty2)
                  (misMatchOrCND ctxt ct oriented ty1 ty2)

  -- So tv is a meta tyvar, and presumably it is
  -- an *untouchable* meta tyvar, else it'd have been unified
  | not (k2 `isSubKind` k1)   	 -- Kind error
  = mkErrorReport ctxt $ (kindErrorMsg (mkTyVarTy tv1) ty2)

  -- Occurs check
  | tv1 `elemVarSet` tyVarsOfType ty2
  = let occCheckMsg = hang (text "Occurs check: cannot construct the infinite type:") 2
                           (sep [ppr ty1, char '=', ppr ty2])
    in mkErrorReport ctxt occCheckMsg

  -- Check for skolem escape
  | (implic:_) <- cec_encl ctxt   -- Get the innermost context
  , let esc_skols = filter (`elemVarSet` (tyVarsOfType ty2)) (ic_skols implic)
        implic_loc = ic_loc implic
  , not (null esc_skols)
  = setCtLoc implic_loc $	-- Override the error message location from the
    	     			-- place the equality arose to the implication site
    do { (ctxt', env_sigs) <- findGlobals ctxt (unitVarSet tv1)
       ; let msg = misMatchMsg oriented ty1 ty2
             esc_doc = sep [ ptext (sLit "because type variable") <> plural esc_skols
                             <+> pprQuotedList esc_skols
                           , ptext (sLit "would escape") <+>
                             if isSingleton esc_skols then ptext (sLit "its scope")
                                                      else ptext (sLit "their scope") ]
             extra1 = vcat [ nest 2 $ esc_doc
                           , sep [ (if isSingleton esc_skols 
                                    then ptext (sLit "This (rigid, skolem) type variable is")
                                    else ptext (sLit "These (rigid, skolem) type variables are"))
                                   <+> ptext (sLit "bound by")
                                 , nest 2 $ ppr (ctLocOrigin implic_loc) ] ]
       ; mkErrorReport ctxt' (msg $$ extra1 $$ mkEnvSigMsg (ppr tv1) env_sigs) }

  -- Nastiest case: attempt to unify an untouchable variable
  | (implic:_) <- cec_encl ctxt   -- Get the innermost context
  , let implic_loc = ic_loc implic
        given      = ic_given implic
  = setCtLoc (ic_loc implic) $
    do { let msg = misMatchMsg oriented ty1 ty2
             extra = quotes (ppr tv1)
                 <+> sep [ ptext (sLit "is untouchable")
                         , ptext (sLit "inside the constraints") <+> pprEvVarTheta given
                         , ptext (sLit "bound at") <+> ppr (ctLocOrigin implic_loc)]
       ; mkErrorReport (addExtraTyVarInfo ctxt ty1 ty2) (msg $$ nest 2 extra) }

  | otherwise
  = pprTrace "mkTyVarEqErr" (ppr tv1 $$ ppr ty2 $$ ppr (cec_encl ctxt)) $
    panic "mkTyVarEqErr"
    	-- I don't think this should happen, and if it does I want to know
	-- Trac #5130 happened because an actual type error was not
	-- reported at all!  So not reporting is pretty dangerous.
	-- 
	-- OLD, OUT OF DATE COMMENT
        -- This can happen, by a recursive decomposition of frozen
        -- occurs check constraints
        -- Example: alpha ~ T Int alpha has frozen.
        --          Then alpha gets unified to T beta gamma
        -- So now we have  T beta gamma ~ T Int (T beta gamma)
        -- Decompose to (beta ~ Int, gamma ~ T beta gamma)
        -- The (gamma ~ T beta gamma) is the occurs check, but
        -- the (beta ~ Int) isn't an error at all.  So return ()
  where         
    k1 	= tyVarKind tv1
    k2 	= typeKind ty2
    ty1 = mkTyVarTy tv1

mkEqInfoMsg :: ReportErrCtxt -> Ct -> TcType -> TcType -> TcM ReportErrCtxt
-- Report (a) ambiguity if either side is a type function application
--            e.g. F a0 ~ Int    
--        (b) warning about injectivity if both sides are the same
--            type function application   F a ~ F b
--            See Note [Non-injective type functions]
mkEqInfoMsg ctxt ct ty1 ty2
  = do { (ctxt', _, ambig_msg) <- if isJust mb_fun1 || isJust mb_fun2
                                  then mkAmbigMsg ctxt [ct]
                                  else return (ctxt, False, empty)
       ; return (ctxt' { cec_extra = tyfun_msg $$ ambig_msg $$ cec_extra ctxt' }) }
  where
    mb_fun1 = isTyFun_maybe ty1
    mb_fun2 = isTyFun_maybe ty2
    tyfun_msg | Just tc1 <- mb_fun1
              , Just tc2 <- mb_fun2
              , tc1 == tc2 
              = ptext (sLit "NB:") <+> quotes (ppr tc1) 
                <+> ptext (sLit "is a type function, and may not be injective")
              | otherwise = empty

misMatchOrCND :: ReportErrCtxt -> Ct -> Bool -> TcType -> TcType -> SDoc
-- If oriented then ty1 is expected, ty2 is actual
misMatchOrCND ctxt ct oriented ty1 ty2
  | null givens || 
    (isRigid ty1 && isRigid ty2) || 
    isGivenOrSolved (cc_flavor ct)
       -- If the equality is unconditionally insoluble
       -- or there is no context, don't report the context
  = misMatchMsg oriented ty1 ty2
  | otherwise      
  = couldNotDeduce givens ([mkEqPred (ty1, ty2)], orig)
  where
    givens = getUserGivens ctxt
    orig   = TypeEqOrigin (UnifyOrigin ty1 ty2)

couldNotDeduce :: [UserGiven] -> (ThetaType, CtOrigin) -> SDoc
couldNotDeduce givens (wanteds, orig)
  = vcat [ hang (ptext (sLit "Could not deduce") <+> pprTheta wanteds)
              2 (pprArising orig)
         , vcat (pp_givens givens)]

pp_givens :: [([EvVar], GivenLoc)] -> [SDoc]
pp_givens givens 
   = case givens of
         []     -> []
         (g:gs) ->      ppr_given (ptext (sLit "from the context")) g
                 : map (ppr_given (ptext (sLit "or from"))) gs
    where ppr_given herald (gs,loc)
           = hang (herald <+> pprEvVarTheta gs)
                2 (sep [ ptext (sLit "bound by") <+> ppr (ctLocOrigin loc)
                       , ptext (sLit "at") <+> ppr (ctLocSpan loc)])

addExtraTyVarInfo :: ReportErrCtxt -> TcType -> TcType -> ReportErrCtxt
-- Add on extra info about the types themselves
-- NB: The types themselves are already tidied
addExtraTyVarInfo ctxt ty1 ty2
  = ctxt { cec_extra = nest 2 (extra1 $$ extra2) $$ cec_extra ctxt }
  where
    extra1 = tyVarExtraInfoMsg (cec_encl ctxt) ty1
    extra2 = tyVarExtraInfoMsg (cec_encl ctxt) ty2

tyVarExtraInfoMsg :: [Implication] -> Type -> SDoc
-- Shows a bit of extra info about skolem constants
tyVarExtraInfoMsg implics ty
  | Just tv <- tcGetTyVar_maybe ty
  , isTcTyVar tv, isSkolemTyVar tv
  , let pp_tv = quotes (ppr tv)
 = case tcTyVarDetails tv of
    SkolemTv {}   -> pp_tv <+> ppr_skol (getSkolemInfo implics tv) (getSrcLoc tv)
    FlatSkol {}   -> pp_tv <+> ptext (sLit "is a flattening type variable")
    RuntimeUnk {} -> pp_tv <+> ptext (sLit "is an interactive-debugger skolem")
    MetaTv {}     -> empty

 | otherwise             -- Normal case
 = empty

 where
   ppr_skol UnkSkol _   = ptext (sLit "is an unknown type variable")  -- Unhelpful
   ppr_skol info    loc = sep [ptext (sLit "is a rigid type variable bound by"),
                               sep [ppr info, ptext (sLit "at") <+> ppr loc]]
 
kindErrorMsg :: TcType -> TcType -> SDoc   -- Types are already tidy
kindErrorMsg ty1 ty2
  = vcat [ ptext (sLit "Kind incompatibility when matching types:")
         , nest 2 (vcat [ ppr ty1 <+> dcolon <+> ppr k1
                        , ppr ty2 <+> dcolon <+> ppr k2 ]) ]
  where
    k1 = typeKind ty1
    k2 = typeKind ty2

--------------------
unifyCtxt :: EqOrigin -> TidyEnv -> TcM (TidyEnv, SDoc)
unifyCtxt (UnifyOrigin { uo_actual = act_ty, uo_expected = exp_ty }) tidy_env
  = do  { (env1, act_ty') <- zonkTidyTcType tidy_env act_ty
        ; (env2, exp_ty') <- zonkTidyTcType env1 exp_ty
        ; return (env2, mkExpectedActualMsg exp_ty' act_ty') }

misMatchMsg :: Bool -> TcType -> TcType -> SDoc	   -- Types are already tidy
-- If oriented then ty1 is expected, ty2 is actual
misMatchMsg oriented ty1 ty2 
  | oriented
  = sep [ ptext (sLit "Couldn't match expected") <+> what <+> quotes (ppr ty1)
        , nest 12 $   ptext (sLit "with actual") <+> what <+> quotes (ppr ty2) ]
  | otherwise
  = sep [ ptext (sLit "Couldn't match") <+> what <+> quotes (ppr ty1)
        , nest 14 $ ptext (sLit "with") <+> quotes (ppr ty2) ]
  where 
    what | isKind ty1 = ptext (sLit "kind")
         | otherwise  = ptext (sLit "type")

mkExpectedActualMsg :: Type -> Type -> SDoc
mkExpectedActualMsg exp_ty act_ty
  = vcat [ text "Expected type" <> colon <+> ppr exp_ty
         , text "  Actual type" <> colon <+> ppr act_ty ]
\end{code}

Note [Non-injective type functions]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
It's very confusing to get a message like
     Couldn't match expected type `Depend s'
            against inferred type `Depend s1'
so mkTyFunInfoMsg adds:
       NB: `Depend' is type function, and hence may not be injective

Warn of loopy local equalities that were dropped.


%************************************************************************
%*									*
                 Type-class errors
%*									*
%************************************************************************

\begin{code}
mkDictErr :: ReportErrCtxt -> [Ct] -> TcM ErrMsg
mkDictErr ctxt cts 
  = do { inst_envs <- tcGetInstEnvs
       ; stuff <- mapM (mkOverlap ctxt inst_envs orig) cts
       ; let (non_overlaps, overlap_errs) = partitionEithers stuff
       ; if null non_overlaps
         then mkErrorReport ctxt (vcat overlap_errs)
         else do
       { (ctxt', is_ambig, ambig_msg) <- mkAmbigMsg ctxt cts
       ; mkErrorReport ctxt' 
            (vcat [ mkNoInstErr givens non_overlaps orig
                  , ambig_msg
                  , mk_no_inst_fixes is_ambig non_overlaps]) } }
  where
    (ct1:_) = cts
    orig    = ctLocOrigin (ctWantedLoc ct1)

    givens = getUserGivens ctxt

    mk_no_inst_fixes is_ambig cts 
      | null givens = show_fixes (fixes2 ++ fixes3)
      | otherwise   = show_fixes (fixes1 ++ fixes2 ++ fixes3) 
      where
        min_wanteds = map ctPred cts
        instance_dicts = filterOut isTyVarClassPred min_wanteds
		-- Insts for which it is worth suggesting an adding an 
		-- instance declaration.  Exclude tyvar dicts.

        fixes2 = case instance_dicts of
                   []  -> []
                   [_] -> [sep [ptext (sLit "add an instance declaration for"),
                                pprTheta instance_dicts]]
                   _   -> [sep [ptext (sLit "add instance declarations for"),
                                pprTheta instance_dicts]]
        fixes3 = case orig of
                   DerivOrigin -> [drv_fix]
                   _           -> []

        drv_fix = vcat [ptext (sLit "use a standalone 'deriving instance' declaration,"),
                        nest 2 $ ptext (sLit "so you can specify the instance context yourself")]

        fixes1 | not is_ambig
               , (orig:origs) <- mapCatMaybes get_good_orig (cec_encl ctxt)
               = [sep [ ptext (sLit "add") <+> pprTheta min_wanteds
                        <+> ptext (sLit "to the context of")
	              , nest 2 $ ppr_skol orig $$ 
                                 vcat [ ptext (sLit "or") <+> ppr_skol orig 
                                      | orig <- origs ]
                 ]    ]
               | otherwise = []

        ppr_skol (PatSkol dc _) = ptext (sLit "the data constructor") <+> quotes (ppr dc)
        ppr_skol skol_info      = ppr skol_info

	-- Do not suggest adding constraints to an *inferred* type signature!
        get_good_orig ic = case ctLocOrigin (ic_loc ic) of 
                             SigSkol (InfSigCtxt {}) _ -> Nothing
                             origin                    -> Just origin


    show_fixes :: [SDoc] -> SDoc
    show_fixes []     = empty
    show_fixes (f:fs) = sep [ ptext (sLit "Possible fix:")
   	                   , nest 2 (vcat (f : map (ptext (sLit "or") <+>) fs))]

mkNoInstErr :: [UserGiven] -> [Ct] -> CtOrigin -> SDoc
mkNoInstErr givens cts orig
  | null givens     -- Top level
  = addArising orig $
    ptext (sLit "No instance") <> plural cts
    <+> ptext (sLit "for") <+> pprTheta theta

  | otherwise
  = couldNotDeduce givens (theta, orig)
  where
   theta = map ctPred cts

mkOverlap :: ReportErrCtxt -> (InstEnv,InstEnv) -> CtOrigin
          -> Ct -> TcM (Either Ct SDoc)
-- Report an overlap error if this class constraint results
-- from an overlap (returning Left clas), otherwise return (Right pred)
mkOverlap ctxt inst_envs orig ct
  = do { tys_flat <- mapM quickFlattenTy tys
           -- Note [Flattening in error message generation]

       ; case lookupInstEnv inst_envs clas tys_flat of
                ([], _, _) -> return (Left ct)    -- No match
                res        -> return (Right (mk_overlap_msg res)) }
  where
    (clas, tys) = getClassPredTys (ctPred ct)

    -- Normal overlap error
    mk_overlap_msg (matches, unifiers, False)
      = ASSERT( not (null matches) )
        vcat [	addArising orig (ptext (sLit "Overlapping instances for") 
				<+> pprType (mkClassPred clas tys))
    	     ,	sep [ptext (sLit "Matching instances") <> colon,
    		     nest 2 (vcat [pprInstances ispecs, pprInstances unifiers])]

             ,  if not (null matching_givens) then 
                  sep [ptext (sLit "Matching givens (or their superclasses)") <> colon
                      , nest 2 (vcat matching_givens)]
                else empty

             ,  if null matching_givens && isSingleton matches && null unifiers then
                -- Intuitively, some given matched the wanted in their
                -- flattened or rewritten (from given equalities) form
                -- but the matcher can't figure that out because the
                -- constraints are non-flat and non-rewritten so we
                -- simply report back the whole given
                -- context. Accelerate Smart.hs showed this problem.
                  sep [ ptext (sLit "There exists a (perhaps superclass) match") <> colon
                      , nest 2 (vcat (pp_givens givens))]
                else empty 

	     ,	if not (isSingleton matches)
    		then 	-- Two or more matches
		     empty
    		else 	-- One match
		parens (vcat [ptext (sLit "The choice depends on the instantiation of") <+>
	    		         quotes (pprWithCommas ppr (varSetElems (tyVarsOfTypes tys))),
			      if null (matching_givens) then
                                   vcat [ ptext (sLit "To pick the first instance above, use -XIncoherentInstances"),
			                  ptext (sLit "when compiling the other instance declarations")]
                              else empty])]
        where
            ispecs = [ispec | (ispec, _) <- matches]

            givens = getUserGivens ctxt
            matching_givens = mapCatMaybes matchable givens

            matchable (evvars,gloc) 
              = case ev_vars_matching of
                     [] -> Nothing
                     _  -> Just $ hang (pprTheta ev_vars_matching)
                                    2 (sep [ ptext (sLit "bound by") <+> ppr (ctLocOrigin gloc)
                                           , ptext (sLit "at") <+> ppr (ctLocSpan gloc)])
                where ev_vars_matching = filter ev_var_matches (map evVarPred evvars)
                      ev_var_matches ty = case getClassPredTys_maybe ty of
                         Just (clas', tys')
                           | clas' == clas
                           , Just _ <- tcMatchTys (tyVarsOfTypes tys) tys tys'
                           -> True 
                           | otherwise
                           -> any ev_var_matches (immSuperClasses clas' tys')
                         Nothing -> False

    -- Overlap error because of Safe Haskell (first match should be the most
    -- specific match)
    mk_overlap_msg (matches, _unifiers, True)
      = ASSERT( length matches > 1 )
        vcat [ addArising orig (ptext (sLit "Unsafe overlapping instances for") 
                        <+> pprType (mkClassPred clas tys))
             , sep [ptext (sLit "The matching instance is") <> colon,
                    nest 2 (pprInstance $ head ispecs)]
             , vcat [ ptext $ sLit "It is compiled in a Safe module and as such can only"
                    , ptext $ sLit "overlap instances from the same module, however it"
                    , ptext $ sLit "overlaps the following instances from different modules:"
                    , nest 2 (vcat [pprInstances $ tail ispecs])
                    ]
             ]
        where
            ispecs = [ispec | (ispec, _) <- matches]

----------------------
quickFlattenTy :: TcType -> TcM TcType
-- See Note [Flattening in error message generation]
quickFlattenTy ty | Just ty' <- tcView ty = quickFlattenTy ty'
quickFlattenTy ty@(TyVarTy {})  = return ty
quickFlattenTy ty@(ForAllTy {}) = return ty     -- See
  -- Don't flatten because of the danger or removing a bound variable
quickFlattenTy (AppTy ty1 ty2) = do { fy1 <- quickFlattenTy ty1
                                    ; fy2 <- quickFlattenTy ty2
                                    ; return (AppTy fy1 fy2) }
quickFlattenTy (FunTy ty1 ty2) = do { fy1 <- quickFlattenTy ty1
                                    ; fy2 <- quickFlattenTy ty2
                                    ; return (FunTy fy1 fy2) }
quickFlattenTy (TyConApp tc tys)
    | not (isSynFamilyTyCon tc)
    = do { fys <- mapM quickFlattenTy tys 
         ; return (TyConApp tc fys) }
    | otherwise
    = do { let (funtys,resttys) = splitAt (tyConArity tc) tys
                -- Ignore the arguments of the type family funtys
         ; v <- newMetaTyVar TauTv (typeKind (TyConApp tc funtys))
         ; flat_resttys <- mapM quickFlattenTy resttys
         ; return (foldl AppTy (mkTyVarTy v) flat_resttys) }
\end{code}

Note [Flattening in error message generation]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Consider (C (Maybe (F x))), where F is a type function, and we have
instances
                C (Maybe Int) and C (Maybe a)
Since (F x) might turn into Int, this is an overlap situation, and
indeed (because of flattening) the main solver will have refrained
from solving.  But by the time we get to error message generation, we've
un-flattened the constraint.  So we must *re*-flatten it before looking
up in the instance environment, lest we only report one matching
instance when in fact there are two.

Re-flattening is pretty easy, because we don't need to keep track of
evidence.  We don't re-use the code in TcCanonical because that's in
the TcS monad, and we are in TcM here.

Note [Quick-flatten polytypes]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
If we see C (Ix a => blah) or C (forall a. blah) we simply refrain from
flattening any further.  After all, there can be no instance declarations
that match such things.  And flattening under a for-all is problematic
anyway; consider C (forall a. F a)

\begin{code}
mkAmbigMsg :: ReportErrCtxt -> [Ct] 
           -> TcM (ReportErrCtxt, Bool, SDoc)
mkAmbigMsg ctxt cts
  | isEmptyVarSet ambig_tv_set
  = return (ctxt, False, empty)
  | otherwise
  = do { dflags <- getDOpts
       ; (ctxt', gbl_docs) <- findGlobals ctxt ambig_tv_set
       ; return (ctxt', True, mk_msg dflags gbl_docs) }
  where
    ambig_tv_set = foldr (unionVarSet . filterVarSet isAmbiguousTyVar . tyVarsOfCt) 
                         emptyVarSet cts
    ambig_tvs = varSetElems ambig_tv_set
    
    is_or_are | isSingleton ambig_tvs = text "is"
              | otherwise             = text "are"
                 
    mk_msg dflags docs 
      | any isRuntimeUnkSkol ambig_tvs  -- See Note [Runtime skolems]
      =  vcat [ ptext (sLit "Cannot resolve unknown runtime type") <> plural ambig_tvs
                   <+> pprQuotedList ambig_tvs
              , ptext (sLit "Use :print or :force to determine these types")]
      | otherwise
      = vcat [ text "The type variable" <> plural ambig_tvs
	          <+> pprQuotedList ambig_tvs
                  <+> is_or_are <+> text "ambiguous"
             , mk_extra_msg dflags docs ]
  
    mk_extra_msg dflags docs
      | null docs
      = ptext (sLit "Possible fix: add a type signature that fixes these type variable(s)")
			-- This happens in things like
			--	f x = show (read "foo")
			-- where monomorphism doesn't play any role
      | otherwise 
      = vcat [ ptext (sLit "Possible cause: the monomorphism restriction applied to the following:")
	     , nest 2 (vcat docs)
             , ptext (sLit "Probable fix:") <+> vcat
     	          [ ptext (sLit "give these definition(s) an explicit type signature")
     	          , if xopt Opt_MonomorphismRestriction dflags
                    then ptext (sLit "or use -XNoMonomorphismRestriction")
                    else empty ]    -- Only suggest adding "-XNoMonomorphismRestriction"
     			            -- if it is not already set!
             ]

getSkolemInfo :: [Implication] -> TcTyVar -> SkolemInfo
-- Get the skolem info for a type variable 
-- from the implication constraint that binds it
getSkolemInfo [] tv
  = WARN( True, ptext (sLit "No skolem info:") <+> ppr tv )
    UnkSkol
getSkolemInfo (implic:implics) tv
  | tv `elem` ic_skols implic = ctLocOrigin (ic_loc implic)
  | otherwise                 = getSkolemInfo implics tv

-----------------------
-- findGlobals looks at the value environment and finds values whose
-- types mention any of the offending type variables.  It has to be
-- careful to zonk the Id's type first, so it has to be in the monad.
-- We must be careful to pass it a zonked type variable, too.

mkEnvSigMsg :: SDoc -> [SDoc] -> SDoc
mkEnvSigMsg what env_sigs
 | null env_sigs = empty
 | otherwise = vcat [ ptext (sLit "The following variables have types that mention") <+> what
                    , nest 2 (vcat env_sigs) ]

findGlobals :: ReportErrCtxt
            -> TcTyVarSet
            -> TcM (ReportErrCtxt, [SDoc])

findGlobals ctxt tvs 
  = do { lcl_ty_env <- case cec_encl ctxt of 
                        []    -> getLclTypeEnv
                        (i:_) -> return (ic_env i)
       ; go (cec_tidy ctxt) [] (nameEnvElts lcl_ty_env) }
  where
    go tidy_env acc [] = return (ctxt { cec_tidy = tidy_env }, acc)
    go tidy_env acc (thing : things)
       = do { (tidy_env1, maybe_doc) <- find_thing tidy_env ignore_it thing
	    ; case maybe_doc of
	        Just d  -> go tidy_env1 (d:acc) things
	        Nothing -> go tidy_env1 acc     things }

    ignore_it ty = tvs `disjointVarSet` tyVarsOfType ty

-----------------------
find_thing :: TidyEnv -> (TcType -> Bool)
           -> TcTyThing -> TcM (TidyEnv, Maybe SDoc)
find_thing tidy_env ignore_it (ATcId { tct_id = id })
  = do { (tidy_env', tidy_ty) <- zonkTidyTcType tidy_env (idType id)
       ; if ignore_it tidy_ty then
	   return (tidy_env, Nothing)
         else do 
       { let msg = sep [ ppr id <+> dcolon <+> ppr tidy_ty
		       , nest 2 (parens (ptext (sLit "bound at") <+>
			 	   ppr (getSrcLoc id)))]
       ; return (tidy_env', Just msg) } }

find_thing tidy_env ignore_it (ATyVar tv ty)
  = do { (tidy_env1, tidy_ty) <- zonkTidyTcType tidy_env ty
       ; if ignore_it tidy_ty then
	    return (tidy_env, Nothing)
         else do
       { let -- The name tv is scoped, so we don't need to tidy it
            msg = sep [ ptext (sLit "Scoped type variable") <+> quotes (ppr tv) <+> eq_stuff
                      , nest 2 bound_at]

            eq_stuff | Just tv' <- tcGetTyVar_maybe tidy_ty
		     , getOccName tv == getOccName tv' = empty
		     | otherwise = equals <+> ppr tidy_ty
		-- It's ok to use Type.getTyVar_maybe because ty is zonked by now
	    bound_at = parens $ ptext (sLit "bound at:") <+> ppr (getSrcLoc tv)
 
       ; return (tidy_env1, Just msg) } }

find_thing _ _ thing = pprPanic "find_thing" (ppr thing)

warnDefaulting :: [Ct] -> Type -> TcM ()
warnDefaulting wanteds default_ty
  = do { warn_default <- woptM Opt_WarnTypeDefaults
       ; env0 <- tcInitTidyEnv
       ; let wanted_bag = listToBag wanteds
             tidy_env = tidyFreeTyVars env0 $
                        tyVarsOfCts wanted_bag
             tidy_wanteds = mapBag (tidyCt tidy_env) wanted_bag
             (loc, ppr_wanteds) = pprWithArising (bagToList tidy_wanteds)
             warn_msg  = hang (ptext (sLit "Defaulting the following constraint(s) to type")
                                <+> quotes (ppr default_ty))
                            2 ppr_wanteds
       ; setCtLoc loc $ warnTc warn_default warn_msg }
\end{code}

Note [Runtime skolems]
~~~~~~~~~~~~~~~~~~~~~~
We want to give a reasonably helpful error message for ambiguity
arising from *runtime* skolems in the debugger.  These
are created by in RtClosureInspect.zonkRTTIType.  

%************************************************************************
%*									*
                 Error from the canonicaliser
	 These ones are called *during* constraint simplification
%*									*
%************************************************************************

\begin{code}
solverDepthErrorTcS :: Int -> [Ct] -> TcM a
solverDepthErrorTcS depth stack
  | null stack	    -- Shouldn't happen unless you say -fcontext-stack=0
  = failWith msg
  | otherwise
  = setCtFlavorLoc (cc_flavor top_item) $
    do { ev_vars <- mapM (zonkEvVar . cc_id) stack
       ; env0 <- tcInitTidyEnv
       ; let tidy_env = tidyFreeTyVars env0 (tyVarsOfEvVars ev_vars)
             tidy_ev_vars = map (tidyEvVar tidy_env) ev_vars
       ; failWithTcM (tidy_env, hang msg 2 (pprEvVars tidy_ev_vars)) }
  where
    top_item = head stack
    msg = vcat [ ptext (sLit "Context reduction stack overflow; size =") <+> int depth
               , ptext (sLit "Use -fcontext-stack=N to increase stack size to N") ]

flattenForAllErrorTcS :: CtFlavor -> TcType -> TcM a
flattenForAllErrorTcS fl ty
  = setCtFlavorLoc fl $ 
    do { env0 <- tcInitTidyEnv
       ; let (env1, ty') = tidyOpenType env0 ty 
             msg = sep [ ptext (sLit "Cannot deal with a type function under a forall type:")
                       , ppr ty' ]
       ; failWithTcM (env1, msg) }
\end{code}

%************************************************************************
%*									*
                 Setting the context
%*									*
%************************************************************************

\begin{code}
setCtFlavorLoc :: CtFlavor -> TcM a -> TcM a
setCtFlavorLoc (Wanted  loc)   thing = setCtLoc loc thing
setCtFlavorLoc (Derived loc)   thing = setCtLoc loc thing
setCtFlavorLoc (Given loc _gk) thing = setCtLoc loc thing
\end{code}

%************************************************************************
%*									*
                 Tidying
%*									*
%************************************************************************

\begin{code}
zonkTidyTcType :: TidyEnv -> TcType -> TcM (TidyEnv, TcType)
zonkTidyTcType env ty = do { ty' <- zonkTcType ty
                           ; return (tidyOpenType env ty') }

zonkTidyOrigin :: ReportErrCtxt -> CtOrigin -> TcM (ReportErrCtxt, CtOrigin)
zonkTidyOrigin ctxt (TypeEqOrigin (UnifyOrigin { uo_actual = act, uo_expected = exp }))
  = do { (env1,  act') <- zonkTidyTcType (cec_tidy ctxt) act
       ; (env2, exp') <- zonkTidyTcType env1            exp
       ; return ( ctxt { cec_tidy = env2 }
                , TypeEqOrigin (UnifyOrigin { uo_actual = act', uo_expected = exp' })) }
zonkTidyOrigin ctxt orig = return (ctxt, orig)
\end{code}
