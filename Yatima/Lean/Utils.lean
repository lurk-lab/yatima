import Lean
import Std.Data.RBMap
import YatimaStdLib.Lean
import Yatima.Datatypes.Lean

namespace Lean

section

variable [BEq α] [Hashable α] [Monad m]

def HashMap.map (hmap : Lean.HashMap α β) (f : β → σ) : Lean.HashMap α σ :=
  hmap.fold (init := default) fun acc a b => acc.insert a (f b)

def SMap.map (smap : Lean.SMap α β) (f : β → σ) : Lean.SMap α σ :=
  let m₁ := smap.map₁.map f
  let m₂ := smap.map₂.map f
  ⟨smap.stage₁, m₁, m₂⟩

end

def ConstantInfo.formatAll (c : ConstantInfo) : String :=
  match c.all with
  | [ ]
  | [_] => ""
  | all => " " ++ all.toString

def ConstantInfo.ctorName : ConstantInfo → String
  | axiomInfo  _ => "axiom"
  | defnInfo   _ => "definition"
  | thmInfo    _ => "theorem"
  | opaqueInfo _ => "opaque"
  | quotInfo   _ => "quotient"
  | inductInfo _ => "inductive"
  | ctorInfo   _ => "constructor"
  | recInfo    _ => "recursor"

def ConstMap.childrenOfWith (map : ConstMap) (name : Name)
    (p : ConstantInfo → Bool) : List ConstantInfo :=
  map.fold (init := []) fun acc n c => match n with
  | .str n ..
  | .num n .. => if n == name && p c then c :: acc else acc
  | _ => acc

def ConstMap.patchUnsafeRec (cs : ConstMap) : ConstMap :=
  let unsafes : Std.RBSet Name compare := cs.fold (init := .empty)
    fun acc n _ => match n with
      | .str n "_unsafe_rec" => acc.insert n
      | _ => acc
  cs.map fun c => match c with
    | .opaqueInfo o =>
      if unsafes.contains o.name then
        .opaqueInfo ⟨
          o.toConstantVal, mkConst (o.name ++ `_unsafe_rec),
          o.isUnsafe, o.levelParams ⟩
      else .opaqueInfo o
    | _ => c

def Environment.patchUnsafeRec (env : Environment) : Environment :=
  { env with constants := env.constants.patchUnsafeRec }

def PersistentHashMap.filter [BEq α] [Hashable α]
    (map : PersistentHashMap α β) (p : α → β → Bool) : PersistentHashMap α β :=
  map.foldl (init := .empty) fun acc x y =>
    match p x y with
    | true => acc.insert x y
    | false => acc

def Environment.getConstsAndDelta (env : Environment) : ConstMap × List ConstantInfo :=
  let constants := env.constants
  let delta := constants.map₂.filter fun n _ => !n.isInternal
  (constants, delta.toList.map (·.2))

/--
Sets the directories where `olean` files can be found.

This function must be called before `runFrontend` if the file to be compiled has
imports (the automatic imports from `Init` also count).
-/
def setLibsPaths : IO Unit := do
  let out ← IO.Process.output {
    cmd := "lake"
    args := #["print-paths"]
  }
  let split := out.stdout.splitOn "\"oleanPath\":[" |>.getD 1 ""
  let split := split.splitOn "],\"loadDynlibPaths\":[" |>.getD 0 ""
  let paths := split.replace "\"" "" |>.splitOn ","|>.map System.FilePath.mk
  Lean.initSearchPath (← Lean.findSysroot) paths

def runCmd (cmd : String) (args : Array String) : IO $ Except String String := do
  let out ← IO.Process.output { cmd := cmd, args := args }
  return if out.exitCode != 0 then .error out.stderr
    else .ok out.stdout

def checkToolchain : IO Unit := do
  match ← runCmd "lake" #["--version"] with
  | .error e => throw $ IO.userError e
  | .ok out =>
    let version := out.splitOn "(Lean version " |>.get! 1
    let version := version.splitOn ")" |>.head!
    let expectedVersion := Lean.versionString
    if version != expectedVersion then
      IO.println s!"Warning: expected toolchain '{expectedVersion}' but got '{version}'"

open Elab in
open System (FilePath) in
def runFrontend (input : String) (filePath : FilePath) : IO Environment := do
  checkToolchain
  let inputCtx := Parser.mkInputContext input filePath.toString
  let (header, parserState, messages) ← Parser.parseHeader inputCtx
  let (env, messages) ← processHeader header default messages inputCtx 0
  let env := env.setMainModule default
  let commandState := Command.mkState env messages default
  let s ← IO.processCommands inputCtx parserState commandState
  let msgs := s.commandState.messages
  if msgs.hasErrors then
    throw $ IO.userError $ "\n\n".intercalate $
      (← msgs.toList.mapM (·.toString)).map String.trim
  else return s.commandState.env

end Lean
