import Yatima.Typechecker.Equal

/-!
# Yatima typechecker: Infer

## Basic Structure

This is the third of the three main files that constitute the Yatima typechecker: `Eval`, `Equal`,
and `Infer`.

TODO: Add a high level overview of Infer in the context of Eval-Equal-Infer.

## Infer

In this module the two major functions `check` and `infer` are defined.
* `check` : Checks that a Yatima expression has a prescribed type.
* `infer` : Determines the type of a given Yatima expression.
-/

namespace Yatima.Typechecker

open TC

/-- Checks if a type is an unit inductive -/
def isUnit : Value → TypecheckM Bool
  | .app (.const name i _) _ => do
    match ← derefConst name i with
    | .inductive induct => pure induct.unit
    | _ => pure false
  | _ => pure false

def isStruct : Value → TypecheckM (Option (ConstIdx × Constructor × List Univ × List SusValue))
  | .app (.const name k univs) params => do
    match ← derefConst name k with
    | .inductive ind => do
      match ind.struct with
        | some ctor =>
          -- Sanity check
          if ind.params != params.length then throw .impossible else
          pure (k, ctor, univs, params)
        | none => pure none
    | _ => pure none
  | _ => pure none

/--
  Gives the correct type information for a lambda based on the information of the body.
  No lambdas can be a proposition, a struct or be elements of the unit type.
-/
def lamInfo (bodInfo : TypeInfo) : TypeInfo :=
  { proof? := bodInfo.proof?
  , unit? := false
  , prop? := false
  , struct? := none }

/--
  Gives the correct type information for a term based on its type.
-/
def infoFromType (typ : SusValue) : TypecheckM TypeInfo := do
  let struct? := (← isStruct typ.get).map (fun (k, _, _, _) => k)
  let proof? := typ.info.prop?
  let unit? ← isUnit typ.get
  let prop? := match typ.get with
    | .sort lvl => lvl.isZero
    | _ => false
  pure { proof?, unit?, prop?, struct? }

-- `Sort u` is not an element of `Prop` (i.e. `Sort 0`), unit-like types, structures or propositions
def sortInfo : TypeInfo :=
  { prop? := false, unit? := false, proof? := false, struct? := none }

-- Type info of `Nat` and `String`
def primTypeInfo : TypeInfo :=
  { prop? := false, unit? := false, proof? := false, struct? := none }

mutual
  /--
  Checks if `term : Expr` has type `type : SusValue`. Returns the expression with flags updated
  -/
  partial def check (term : Expr) (type : SusValue) : TypecheckM Expr := do
    match term with
    | .lam _ lamName bind lamDom bod =>
      let (lamDom, _) ← isSort lamDom
      match type.get with
      | .pi _ _ dom img env =>
        let lvl := (← read).lvl
        if !(dom.info == lamDom.info) || !(← equal dom.info lvl (← eval lamDom) dom.get) then
          throw $ .custom "Lambda annotation does not match with its type"
        let var := mkSusVar (← infoFromType dom) lamName lvl
        let env := env.extendWith var 
        let img := suspend img { ← read with env } (← get)
        let bod ← withExtendedCtx var dom $ check bod img
        pure $ .lam (lamInfo bod.info) lamName bind lamDom bod
      | val => throw $ .notPi (toString val)
    | .letE _ name expType exp bod =>
      let (expType, _) ← isSort expType
      let expTypeVal := suspend expType (← read) (← get)
      let exp ← check exp expTypeVal
      let expVal := suspend exp (← read) (← get)
      let bod ← withExtendedCtx expVal expTypeVal $ check bod type
      pure $ .letE bod.info name expType exp bod
    | .app _ (.lam _ lamName bind lamDom bod) arg =>
      let (lamDom, _) ← isSort lamDom
      let lamDomVal := suspend lamDom (← read) (← get)
      let arg ← check arg lamDomVal
      let argVal := suspend arg (← read) (← get)
      let bod ← withExtendedCtx argVal lamDomVal $ check bod type
      pure $ .app bod.info (.lam (lamInfo bod.info) lamName bind lamDom bod) arg
    | _ =>
      let (term, inferType) ← infer term
      if !(inferType.info == type.info) || !(← equal inferType.info (← read).lvl type.get inferType.get) then
        throw $ .valueMismatch (toString type.get) (toString inferType.get)
      else
        pure term

  /-- Infers the type of `term : Expr`. Returns the expression with flags updated along with the inferred type  -/
  partial def infer (term : Expr) : TypecheckM (Expr × SusValue) := do
    match term with
    | .var _ name idx =>
      let types := (← read).types
      let some type := types.get? idx | throw $ .outOfEnvironmentRange name idx types.length
      let term := .var (← infoFromType type) name idx
      pure (term, type)
    | .sort _ lvl =>
      let univs := (← read).env.univs
      let typ := .mk sortInfo ⟨ fun _ => .sort $ .instBulkReduce univs lvl.succ ⟩
      return (term, typ)
    | .app _ (.lam _ lamName bind lamDom bod) arg =>
      let (lamDom, _) ← isSort lamDom
      let lamDomVal := suspend lamDom (← read) (← get)
      let arg ← check arg lamDomVal
      let argVal := suspend arg (← read) (← get)
      let (bod, type) ← withExtendedCtx argVal lamDomVal $ infer bod
      pure (.app bod.info (.lam (lamInfo bod.info) lamName bind lamDom bod) arg, type)
    | .app _ fnc arg =>
      let (fnc, fncType) ← infer fnc
      match fncType.get with
      | .pi _ _ dom img env =>
        let arg ← check arg dom
        let typ := suspend img { ← read with env := env.extendWith $ suspend arg (← read) (← get)} (← get)
        let term := .app (← infoFromType typ) fnc arg
        pure (term, typ)
      | val => throw $ .notPi (toString val)
    -- Should we add inference of lambda terms? Perhaps not on this checker,
    -- but on another that is capable of general unification, since this checker
    -- is supposed to be used on fully annotated terms.
    | .lam .. => throw .cannotInferLam
    | .pi _ name bind dom img =>
      let (dom, domLvl) ← isSort dom
      let ctx ← read
      let domVal := suspend dom ctx (← get)
      withExtendedCtx (mkSusVar (← infoFromType domVal) name ctx.lvl) domVal $ do
        let (img, imgLvl) ← isSort img
        let typ := .mk sortInfo ⟨ fun _ => .sort $ .reduceIMax domLvl imgLvl ⟩
        let term := .pi (← infoFromType typ) name bind dom img
        return (term, typ)
    | .letE _ name expType exp bod =>
      let (expType, _) ← isSort expType
      let expTypeVal := suspend expType (← read) (← get)
      let exp ← check exp expTypeVal
      let expVal := suspend exp (← read) (← get)
      let (bod, typ) ← withExtendedCtx expVal expTypeVal $ infer bod
      let term := .letE bod.info name expType exp bod
      return (term, typ)
    | .lit _ (.natVal _) =>
      let typ := .mk primTypeInfo (mkConst `Nat (← natIndex) [])
      pure $ (term, typ)
    | .lit _ (.strVal _) =>
      let typ := .mk primTypeInfo (mkConst `String (← stringIndex) [])
      pure $ (term, typ)
    | .const _ name k constUnivs =>
      let univs := (← read).env.univs
      let const ← derefConst name k
      checkConst const k
      let env := ⟨[], constUnivs.map (Univ.instBulkReduce univs)⟩
      let typ := suspend const.type { ← read with env := env } (← get)
      pure (.const (← infoFromType typ) name k constUnivs, typ)
    | .proj _ idx expr =>
      let (expr, exprType) ← infer expr
      let some (_, ctor, univs, params) ← isStruct exprType.get
        | throw $ .typNotStructure (toString exprType.get)
      -- annotate constructor type
      let (ctorType, _) ← infer ctor.type
      let mut ctorType ← applyType (← withEnv ⟨[], univs⟩ $ eval ctorType) params.reverse
      for i in [:idx] do
        match ctorType with
        | .pi _ _ _ img piEnv =>
          -- Note: This expression that is generated on the fly is immediately transformed into a value,
          -- which discards the hash, so the value of the hash does not matter here
          let proj := suspend (Expr.proj default i expr) (← read) (← get)
          ctorType ← withNewExtendedEnv piEnv proj $ eval img
        | _ => pure ()
      match ctorType with
      | .pi _ _ dom _ _  =>
        if exprType.info.prop? && !(dom.info.prop?) then 
          throw $ .projEscapesProp (toString term)
        else
          let term := .proj (← infoFromType dom) idx expr
          pure (term, dom)
      | _ => throw .impossible

  /--
  Checks if `expr : Expr` is `Sort lvl` for some level `lvl`, and throws `TypecheckerError.notTyp`
  if it is not.
  -/
  partial def isSort (expr : Expr) : TypecheckM (Expr × Univ) := do
    let (expr, typ) ← infer expr
    match typ.get with
    | .sort u => pure (expr, u)
    | val => throw $ .notTyp (toString val)

  /-- Typechecks a `Yatima.Const`. The `TypecheckM Unit` computation finishes if the check finishes,
  otherwise a `TypecheckError` is thrown in some other function in the typechecker stack.

  Note that inductives, constructors, and recursors are constructed to typecheck, so this function
  only has to check the other `Const` constructors.
  -/
  partial def checkConst (c : Const) (idx : Nat) : TypecheckM Unit := do
    match (← get).tcConsts.get? idx with
    | .some .none =>
      let univs := c.levels.foldr
        (fun name cont i => Univ.var name i :: (cont (i + 1)))
        (fun _ => []) 0
      withEnv ⟨ [], univs ⟩ $ do
        match c with
        | .theorem    struct
        | .opaque     struct
        | .definition struct => do
          let (type, _) ← isSort struct.type
          let typeSus := suspend type (← read) (← get)
          let value ← check struct.value typeSus

          -- update the typechecked consts with the annotated values/types
          let tcConsts := (← get).tcConsts
          if h : idx < tcConsts.size then
            let newConst ← match c with
            | .theorem    struct => pure $ Const.theorem {struct with value := value, type := type}
            | .opaque     struct => pure $ .opaque {struct with value := value, type := type}
            | .definition struct => pure $ .definition {struct with value := value, type := type}
            | _ => throw .impossible
            modify fun stt => {stt with tcConsts := tcConsts.set ⟨idx, h⟩ $ .some newConst}
          else
            throw $ .impossible
        -- TODO: check that inductives, constructors and recursors are well-formed
        -- TODO: check that quotient is well-formed. I guess it is possible to do this
        -- while converting from Ipld by checking the cids of the quotient constants
        -- with precomputed ones
        | .axiom       struct
        | .inductive   struct
        | .constructor struct
        | .extRecursor struct
        | .intRecursor struct
        | .quotient    struct =>
          let (type, _)  ← isSort struct.type

          -- update the typechecked consts with the annotated values/types
          let tcConsts := (← get).tcConsts
          if h : idx < tcConsts.size then
            let newConst ← match c with 
            | .axiom       struct => pure $ Const.axiom {struct with type := type}
            | .inductive   struct => pure $ Const.inductive {struct with type := type}
            | .constructor struct => pure $ Const.constructor {struct with type := type}
            | .extRecursor struct => pure $ Const.extRecursor {struct with type := type}
            | .intRecursor struct => pure $ Const.intRecursor {struct with type := type}
            | .quotient    struct => pure $ Const.quotient {struct with type := type}
            | _ => throw $ .impossible
            modify fun stt => {stt with tcConsts := tcConsts.set ⟨idx, h⟩ $ .some newConst}
          else
            throw $ .impossible
    | .none =>
      throw .impossible
    | _ => pure ()
end

end Yatima.Typechecker
