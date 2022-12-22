import Lean.CoreM
import Lean.Compiler.LCNF
import Yatima.Transpiler.Override

namespace Yatima.Transpiler

open Lurk.Backend

open Lean.Compiler.LCNF Lean.Core

structure TranspileEnv where
  env : Lean.Environment
  overrides : Lean.NameMap Override

structure TranspileState where
  appendedBindings : Array (Lean.Name × Expr)
  /-- Contains the names of constants that have already been processed -/
  visited  : Lean.NameSet
  inductives : Lean.NameMap InductiveData
  ngen     : Lean.NameGenerator
  replaced : Lean.NameMap Lean.Name
  deriving Inhabited

abbrev TranspileM := ReaderT TranspileEnv $ EStateM String TranspileState

instance : Lean.MonadNameGenerator TranspileM where
  getNGen := return (← get).ngen
  setNGen ngen := modify fun s => { s with ngen := ngen }

/-- Create a fresh variable to replace `name` and update `replaced` -/
def replace (name : Lean.Name) : TranspileM Lean.Name := do
  let mut name' ← Lean.mkFreshId
  let env ← read
  while env.env.contains name' || env.overrides.contains name' do
    -- making sure we don't hit an existing name
    name' ← Lean.mkFreshId
  modifyGet fun stt => (name', { stt with
    replaced := stt.replaced.insert name name' })

/-- Set `name` as a visited node -/
def visit (name : Lean.Name) : TranspileM Unit :=
  dbg_trace s!">> visit {name}"
  modify fun s => { s with visited := s.visited.insert name }

@[inline] def isVisited (n : Lean.Name) : TranspileM Bool :=
  return (← get).visited.contains n

def getDecl (declName : Lean.Name) : TranspileM Decl := do
  if let some decl := getDeclCore? (← read).env monoExt declName then
    return decl
  else if let some decl := getDeclCore? (← read).env baseExt declName then
    return decl
  else
    throw s!"environment does not contain {declName}"

def withOverrides (overrides : Lean.NameMap Override) : TranspileM α → TranspileM α :=
  withReader fun env => { env with overrides := overrides }

def TranspileM.run (env : TranspileEnv) (s : TranspileState) (m : TranspileM α) :
    EStateM.Result String TranspileState α :=
  m env |>.run s

end Yatima.Transpiler
