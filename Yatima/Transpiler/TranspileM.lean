import Yatima.Transpiler.TranspileError

namespace Yatima.Transpiler

open Yatima.Compiler

structure TranspileEnv where 
  state : CompileState
  builtins : List (Name × Lurk.Expr)

structure TranspileState where
  appendedBindings  : Array (Name × Lurk.Expr)
  /-- Contains constants that have already been processed -/
  visited : Lean.NameSet
  ngen : Lean.NameGenerator
  replaced : Lean.NameMap Name
  deriving Inhabited

abbrev TranspileM := ReaderT TranspileEnv $
  ExceptT TranspileError $ StateT TranspileState Id

instance : Lean.MonadNameGenerator TranspileM where
  getNGen := return (← get).ngen
  setNGen ngen := modify fun s => { s with ngen := ngen }

/-- Set `name` as a visited node -/
def visit (name : Name) : TranspileM Unit := do
  -- dbg_trace s!">> visit {name}"
  modify fun s => { s with visited := s.visited.insert name }

/-- Create a fresh variable `_x_n` to replace `name` and update `replaced` -/
def replaceFreshId (name : Name) : TranspileM Name := do
  let _x ← Lean.mkFreshId
  -- dbg_trace s!">> mk fresh name {_x}"
  set $ { (← get) with replaced := (← get).replaced.insert name _x}
  return _x

def appendBinding (b : Name × Lurk.Expr) (vst := true) : TranspileM Unit := do
  let s ← get
  set $ { s with appendedBindings := s.appendedBindings.push b }
  if vst then visit b.1

def TranspileM.run (env : TranspileEnv) (ste : TranspileState)
    (m : TranspileM α) : Except String TranspileState := do
  match StateT.run (ReaderT.run m env) ste with
  | (.ok _, ste)  => .ok ste
  | (.error e, _) => .error (toString e)

end Yatima.Transpiler
