/-
Copyright (c) 2021 Shing Tak Lam. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Shing Tak Lam, Daniel Selsam, Mario Carneiro, Yatima Inc
-/
import Lean.Elab.Command

open Lean Meta Elab Command

namespace Lean

namespace Environment

structure FindOptions where
  stage1       : Bool := true
  checkPrivate : Bool := false

def findCore (env : Environment) (ϕ : ConstantInfo → Bool) (opts : FindOptions := {}) :
  Array ConstantInfo :=
  let matches_ := if !opts.stage1 then #[] else
    env.constants.map₁.fold (init := #[]) check
  env.constants.map₂.foldl (init := matches_) check
where
  check matches_ name cinfo :=
    if opts.checkPrivate || !isPrivateName name then
      if ϕ cinfo then matches_.push cinfo else matches_
    else matches_

end Environment

namespace Meta

def find (msg : String)
  (ϕ : ConstantInfo → Bool) (opts : Environment.FindOptions := {}) : TermElabM String := do
  let cinfos := (← getEnv).findCore ϕ opts
  let cinfos := cinfos.qsort fun p q => p.name.lt q.name
  let mut msg := msg
  for cinfo in cinfos do
    msg := msg ++ s!"{cinfo.name} : {← Meta.ppExpr cinfo.type}\n"
  pure msg

end Meta

namespace Elab.Command

syntax (name := printPrefix) "#printprefix " ident : command

/--
The command `#print prefix foo` will print all definitions that start with
the namespace `foo`.
-/
@[command_elab printPrefix] def elabPrintPrefix : CommandElab
| `(#printprefix%$tk $name:ident) => do
  let nameId := name.getId
  liftTermElabM do
    let mut msg ← find "" fun cinfo => nameId.isPrefixOf cinfo.name
    if msg.isEmpty then
      if let [name] ← resolveGlobalConst name then
        msg ← find msg fun cinfo => name.isPrefixOf cinfo.name
    if !msg.isEmpty then
      logInfoAt tk msg
| _ => throwUnsupportedSyntax

end Elab.Command
end Lean
