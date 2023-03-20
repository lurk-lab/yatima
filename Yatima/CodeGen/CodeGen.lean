import Yatima.Datatypes.Lean
import Yatima.Lean.LCNF
import Yatima.CodeGen.CodeGenM
import Yatima.CodeGen.PrettyPrint
import Yatima.CodeGen.Preloads
import Yatima.CodeGen.Overrides.All
import Yatima.CodeGen.Simp
import Yatima.Lean.Utils

namespace Yatima.CodeGen

open Lurk Expr LDON DSL
open Lean.Compiler.LCNF

/--
This is a super dangerous instance, because of how tricky names are;
I'm just gonna turn it on for now, but may cause terrible bugs.
-/
scoped instance (priority := low) : ToExpr Lean.Name where
  toExpr name := .sym name.toString

def preloads : List (Name × Expr) := [
  Lurk.Preloads.reverse_aux,
  Lurk.Preloads.reverse,
  Lurk.Preloads.set,
  Lurk.Preloads.set!,
  Lurk.Preloads.push,
  Lurk.Preloads.append,
  Lurk.Preloads.getelem,
  Lurk.Preloads.getelem!,
  Lurk.Preloads.drop,
  Lurk.Preloads.str_mk,
  Lurk.Preloads.str_data,
  Lurk.Preloads.str_push,
  Lurk.Preloads.str_append,
  Lurk.Preloads.to_bool,
  Lurk.Preloads.lor,
  Lurk.Preloads.land,
  Lurk.Preloads.lnot,
  Lurk.Preloads.lneq,
  Lurk.Preloads.throw
]

def preloadNames : Lean.NameSet :=
  .ofList (preloads.map Prod.fst)

def safeName (name : Name) : CodeGenM Name :=
  -- dbg_trace s!">> safeName {name}"
  let nameStr := name.toString false
  if preloadNames.contains name || nameStr.contains '|' then do
    match (← get).replaced.find? name with
    | some n => return n
    | none   => replace name
  else
    -- dbg_trace s!">> safeName end {name}"
    return name

def mkName (name : Name) : CodeGenM Expr := do
  -- dbg_trace s!">> mkName {name}"
  toExpr <$> safeName name

instance : ToExpr Lean.FVarId where
  toExpr fvarId := toExpr fvarId.name

instance : ToExpr LitValue where toExpr
  | .natVal n => toExpr n
  | .strVal s => toExpr s

def appendBinding (b : Name × Expr) (safe := true) : CodeGenM Unit := do
  -- dbg_trace s!">> appendBinding {b.1}"
  let b := if safe then (← safeName b.1, b.2) else b
  modify fun s => { s with appendedBindings := s.appendedBindings.push b }

def appendInductiveData (data : InductiveData) : CodeGenM Unit := do
  modify fun s => { s with inductives := s.inductives.insert data.name data }

def mkIndLiteral (ind : Lean.InductiveVal) : CodeGenM Expr := do
  -- dbg_trace s!">> mkIndLiteral"
  let (name, params, indices, type) :=
    (ind.name.toString false, ind.numParams, ind.numIndices, ind.type)
  let args ← type.getForallBinderNames.mapM safeName
  let args := args.map (·.toString false)
  if args.isEmpty then
    return ⟦,($name $params $indices)⟧
  else
    return .mkLambda args ⟦,($name $params $indices)⟧

def appendConstructor (ctor : Lean.ConstructorVal) : CodeGenM Unit := do
  -- dbg_trace s!">> appendConstructor"
  let (name, idx, type, ind) := (ctor.name, ctor.cidx, ctor.type, ctor.induct)
  visit ctor.name
  let ctorArgs ← type.getForallBinderNames.mapM safeName
  let ind := ind.toString false
  let ctorData := ⟦(cons $ind (cons $idx $(mkConsListWith $ ctorArgs.map toExpr)))⟧
  let body := if ctorArgs.isEmpty then
    ctorData
  else
    .mkLambda (ctorArgs.map (·.toString false)) ctorData
  appendBinding (name, body)

/-- Amazingly, we don't actually have to codeGen recursors... -/
def appendInductive (ind : Lean.InductiveVal) : CodeGenM Unit := do
  -- dbg_trace s!">> appendInductive"
  let (name, params, indices) := (ind.name, ind.numParams, ind.numIndices)
  visit name
  let ctors : List Lean.ConstructorVal ← ind.ctors.mapM fun ctor => do
    match (← read).env.constants.find? ctor with
    | some (.ctorInfo ctor) => return ctor
    | _ => throw s!"malformed environment, {ctor} is not a constructor or doesn't exist"
  let ctorData := ctors.foldl (init := .empty)
    fun acc ctor => acc.insert ctor.name ctor.cidx
  appendInductiveData ⟨name, params, indices, ctorData⟩
  appendBinding (name, ← mkIndLiteral ind)
  for ctor in ctors do
    appendConstructor ctor

def getInductive (name : Name) : CodeGenM Lean.InductiveVal := do
  match (← read).env.constants.find? name with
  | some (.inductInfo ind) => return ind
  | _ => throw s!"{name} is not an inductive"

def getCtorOrIndInfo? (name : Name) : CodeGenM $ Option (List Name) := do
  match (← read).env.constants.find? name with
  | some (.inductInfo ind) => return some ind.all
  | some (.ctorInfo ctor) =>
    let ind ← getInductive ctor.induct
    return some ind.all
  | _ => return none

def appendCtorOrInd (name : Name) : CodeGenM Bool := do
  match (← read).env.constants.find? name with
  | some (.inductInfo ind) =>
    for ind in ind.all do
      let ind ← getInductive ind
      appendInductive ind
    return true
  | some (.ctorInfo ctor) =>
    let ind ← getInductive ctor.induct
    for ind in ind.all do
      let ind ← getInductive ind
      appendInductive ind
    return true
  | _ => return false

@[inline] def mkFVarId (fvarId : Lean.FVarId) : CodeGenM Expr :=
  -- dbg_trace s!">> mkFVarId"
  mkName fvarId.name

def mkArg : Arg → CodeGenM Expr
  | .erased => return .atom .nil -- toExpr "lcErased"
  | .fvar fvarId => mkFVarId fvarId
    -- hopefully can erase types??
  | .type _ => return .atom .nil -- toExpr "lcErased"

def mkParam : Param → CodeGenM String
  | ⟨fvarId, _, _, _⟩ =>
    -- dbg_trace s!">> mkParam"
    return (← safeName fvarId.name).toString false

def mkParams (params : Array Param) : CodeGenM (Array String) := do
  params.mapM mkParam

def mkCasesCore (indData : InductiveData) (discr : Expr) (alts : Array Override.Alt) :
    Except String Expr := do
  -- dbg_trace s!">> mkCases mkCasesCore: {indData.name}"
  let mut defaultElse : Expr := .atom .nil
  let mut ifThens : Array (Expr × Expr) := #[]
  for alt in alts do match alt with
    | .default k => defaultElse := k
    | .alt cidx params k =>
      if params.isEmpty then
        ifThens := ifThens.push (⟦(= _lurk_idx $cidx)⟧, k)
      else
        let params : List (String × Expr) := params.toList.enum.map fun (i, param) =>
          (param.toString false, ⟦(getelem _lurk_args $i)⟧)
        let case := mkLet params k
        ifThens := ifThens.push (⟦(= _lurk_idx $cidx)⟧, case)
  let cases := mkIfElses ifThens.toList defaultElse
  return ⟦(let ((_lurk_idx (getelem $discr 1))
                (_lurk_args (drop $(2 + indData.params) $discr)))
            $cases)⟧

mutual

  partial def mkLetValue (letv : LetValue) : CodeGenM Expr := do
    -- dbg_trace s!">> mkLetValue"
    match letv with
    | .value lit => return toExpr lit
    | .erased => return .atom .nil -- toExpr "lcErased"
    | .proj typeName idx struct => do
      appendName typeName
      -- TODO FIXME: use `typeName` to get params and add to `idx`
      -- TODO FIXME: support overrides; this is somewhat non-trivial
      let some indData := (← get).inductives.find? typeName |
        throw s!"{typeName} is not an inductive"
      return ⟦(getelem $struct.name $(2 + indData.params + idx))⟧
    | .const declName _ args => do
      -- dbg_trace s!">> mkLetValue go {declName}"
      appendName declName
      if args.isEmpty then
        return toExpr declName
      else
        return mkApp (toExpr declName) $ (← args.mapM mkArg).data
    | .fvar fvarId args =>
      if args.isEmpty then
        mkName fvarId.name
      else
        return mkApp (← mkFVarId fvarId) $ (← args.mapM mkArg).data

  partial def mkLetDecl : LetDecl → CodeGenM (String × Expr)
    | ⟨fvarId, _, _, value⟩ => do
      -- dbg_trace s!">> mkLetDecl"
      let fvarId ← safeName fvarId.name
      let fvarId := fvarId.toString false
      let value ← mkLetValue value
      return (fvarId, value)

  partial def mkFunDecl : FunDecl → CodeGenM (String × Expr)
    | ⟨fvarId, _, params, _, value⟩ => do
      -- dbg_trace s!">> mkFunDecl"
      let fvarId ← safeName fvarId.name
      let fvarId := fvarId.toString false
      let value ← mkCode value
      let ⟨params⟩ ← mkParams params
      return (fvarId, mkLambda params value)

  partial def mkOverrideAlt (indData : InductiveData) :
      Alt → CodeGenM Override.Alt
    | .default k => .default <$> mkCode k
    | .alt ctor params k => do
      -- dbg_trace s!">> mkOverrideAlt"
      let some cidx := indData.ctors.find? ctor |
        throw s!"{ctor} not a valid constructor for {indData.name}"
      let params ← params.mapM fun p => safeName p.fvarId.name
      return .alt cidx params (← mkCode k)

  partial def mkOverrideAlts (indData : InductiveData) (alts : Array Alt) :
      CodeGenM (Array Override.Alt) := do
    alts.mapM $ mkOverrideAlt indData

  partial def mkCases (cases : Cases) : CodeGenM Expr := do
    let ⟨typeName, _, discr, alts⟩ := cases
    appendName typeName
    -- dbg_trace s!">> mkCases typeName: {typeName}"
    let indData := ← match (← get).inductives.find? typeName with
      | some data => return data
      | none => throw s!"{typeName} is not an inductive"
    let discr ← mkFVarId discr
    let alts ← mkOverrideAlts indData alts
    match (← read).overrides.find? typeName with
    | some (.ind ind) => liftExcept <| ind.mkCases discr alts
    | none            => liftExcept <| mkCasesCore indData discr alts
    | some (.decl _)  => throw s!"found a declaration override for {typeName}"

  partial def mkCode : Code → CodeGenM Expr
    | .let decl k => do
      -- dbg_trace s!">> mkCode let"
      let (name, decl) ← mkLetDecl decl
      let k ← mkCode k
      return .let name decl k
    | .fun decl k | .jp decl k => do -- `.fun` and `.jp` are the same case to Lurk
      -- dbg_trace s!">> mkCode fun"
      let (name, decl) ← mkFunDecl decl
      let k ← mkCode k
      return .let name decl k
    | .jmp fvarId args => do
      -- dbg_trace s!">> mkCode jmp"
      let fvarId ← mkFVarId fvarId
      let args ← args.mapM mkArg
      return mkApp fvarId args.data
    | .cases cases =>
      -- dbg_trace s!">> mkCode cases"
      mkCases cases
    | .return fvarId =>
      -- dbg_trace s!">> mkCode return {fvarId.name}"
      mkFVarId fvarId
    | .unreach _ => return .atom .nil -- toExpr "lcUnreachable"

  partial def appendDecl (decl : Decl) : CodeGenM Unit := do
    -- dbg_trace s!">> appendDecl {decl.name}"
    let ⟨name, _, _, params, value, _, _, _⟩ := decl
    visit name
    let ⟨params⟩ := params.map fun p => p.fvarId.name.toString false
    let value : Expr ← mkCode value
    let body := if params.isEmpty then value else mkLambda params value
    appendBinding (name, body)

  partial def appendName (name : Name) : CodeGenM Unit := do
    if ← isVisited name then return
    -- dbg_trace s!">> appendName new name {name}"
    match ← getCtorOrIndInfo? name with
    | some inds =>
      for ind in inds do
        if ← appendOverride ind then continue
        let ind ← getInductive ind
        appendInductive ind
    | none =>
      if ← appendOverride name then return
      appendDecl $ ← getDecl name

  partial def appendOverride (name : Name) : CodeGenM Bool := do
    -- dbg_trace s!">> appendOverride {name}"
    match (← read).overrides.find? name with
    | some (.decl ⟨name, decl⟩) =>
      visit name
      appendPrereqs decl
      appendBinding (name, decl)
      return true
    | some (.ind ⟨indData, ⟨name, decl⟩, ctors, _⟩) =>
      visit name
      appendInductiveData indData
      appendPrereqs decl
      appendBinding (name, decl)
      for ⟨name, ctor⟩ in ctors do
        visit name
        appendPrereqs ctor
        appendBinding (name, ctor)
      return true
    | none => return false
  where
    appendPrereqs (x : Expr) : CodeGenM Unit := do
      -- dbg_trace s!">> appendPrereqs {x.getFreeVars default default |>.toList}"
      (x.getFreeVars).toList.forM fun n => do
        let n := n.toNameSafe
        if !(← isVisited n) then appendName n

end

/-- Main code generation function -/
def codeGenM (decl : Lean.Name) : CodeGenM Unit :=
  let overrides := .ofList $ Lurk.Overrides.All.module.map fun o => (o.name, o)
  withOverrides overrides do
    -- dbg_trace s!">> codeGenM overrides: {(← read).overrides.toList.map Prod.fst}"
    preloads.forM fun (name, preload) => do
      visit name
      appendBinding (name, preload) false
    appendName decl

/--
Constructs a `Expr.letrec` whose body is the call to a `decl` constant in a
context and whose bindings are the constants in the context (including `decl`)
that are needed to define `decl`.
-/
def codeGen (leanEnv : Lean.Environment) (decl : Name) : Except String Expr :=
  match CodeGenM.run ⟨leanEnv.patchUnsafeRec, .empty⟩ default (codeGenM decl) with
  | .error e _ => .error e
  | .ok _ s =>
    let bindings := Expr.mutualize $
      s.appendedBindings.data.map fun (n, x) => (n.toString false, x)
    let expr := mkLetrec bindings (.sym $ decl.toString false)
    return expr.simp.pruneBlocks

end Yatima.CodeGen
