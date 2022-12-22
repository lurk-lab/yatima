import Yatima.Typechecker.Infer
import Yatima.Typechecker.TypecheckM
import Yatima.Converter.Converter
import Yatima.Datatypes.Store

/-!
# Typechecker

This module defines the user-facing functions for the typechecker.
-/

namespace Yatima.Typechecker

open TC

/-- Typechecks all the constants in the `TypecheckEnv.store` -/
def typecheckM : TypecheckM Unit := do
  (← read).store.consts.toList.enum.forM (fun (i, const) => checkConst const i)

/-- Typechecks an array of constants -/
def typecheckConsts (store : Store) : Except String Unit :=
  match TypecheckM.run (.init store) (.init store) typecheckM with
  | .ok u => .ok u
  | .error err => throw $ toString err

/--
Typechecks the contents of an `Ipld.Store`. Such a store can be generated by compiling a Lean file
using the Yatima compiler.
 -/
def typecheck (store : IR.Store) : Except String Unit :=
  match Converter.extractPureStore store with
  | .ok store => typecheckConsts store
  | .error msg => throw msg

end Yatima.Typechecker
