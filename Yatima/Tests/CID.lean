import LSpec
import Yatima.Compiler.Frontend
import Yatima.Const

open Std (RBMap)

namespace Yatima.Tests

/-- 
Runs a `LSpec` test and pretty prints the results.
-/
def my_lspec (t : LSpec) : Except String String := do
  let (success?, msg) := LSpec.runAndCompile t
  if success?
    then .ok msg
    else throw msg

open Yatima in
def cid_test (fileName : String) (groups : List (List Lean.Name)) : IO UInt32 := do
  let mut groupIdxs : RBMap Lean.Name Nat compare := RBMap.empty
  for (i, ds) in groups.enum do
    for d in ds do
      groupIdxs := groupIdxs.insert d i

  let names := groups.foldl (fun acc a => acc ++ a) []

  match ← Compiler.runFrontend  fileName false default with
    | .error err => IO.eprintln err; return 1
    | .ok env => 
      let mut namesToCids : RBMap Lean.Name ConstAnonCid compare := RBMap.empty
      for (constCid, const) in env.store.const_cache do
         namesToCids := namesToCids.insert const.name constCid.anon

      let mut errList : List String := []

      -- TODO eliminate n(n+1)/2 duplicate comparisons
      for a in names do
        for b in names do
          if a.toString < b.toString then 
            let aIdx ← match groupIdxs.find? a with
              | some idx => pure idx
              | none => unreachable!
            let aCid ← match namesToCids.find? a with
              | some cid => pure cid
              | none => unreachable!

            let bIdx ← match groupIdxs.find? b with
              | some idx => pure idx
              | none => unreachable!
            let bCid ← match namesToCids.find? b with
              | some cid => pure cid
              | none => unreachable!

            if aIdx = bIdx then
              match my_lspec $ test s!"anon CID equality {a} and {b} of equivalent anon data" (aCid == bCid) with
              | .ok msg => IO.println msg
              | .error msg =>
                IO.eprintln msg
                errList := msg :: errList
            else
              match my_lspec $ test s!"anon CID inequality {a} and {b} of inequivalent anon data" (aCid != bCid) with
              | .ok msg => IO.println msg
              | .error msg =>
                IO.eprintln msg
                errList := msg :: errList

      if errList.isEmpty then
        return 0
      else
        IO.eprintln $ "\n".intercalate errList.reverse 
        return 1

def CID : IO UInt32 :=
  cid_test "Fixtures/MutDefBlock.lean" [[`A, `C, `E, `F], [`B], [`G, `H]]
