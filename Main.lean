import Lean
import Yatima.Compiler.FromLean

def List.pop : (l : List α) → l ≠ [] → α × List α
  | a :: as, _ => (a, as)

open Yatima.Compiler in
def main (args : List String) : IO UInt32 := do
  if h : args ≠ [] then
    let (cmd, args) := args.pop h
    match cmd with
    | "build" =>
      if h : args ≠ [] then
        let (fileName, args) := args.pop h
        let input ← IO.FS.readFile ⟨fileName⟩
        Lean.initSearchPath $ ← Lean.findSysroot
        let (env, ok) ← Lean.Elab.runFrontend input .empty fileName default
        if ok then
          let (env₀, _) ← Lean.Elab.runFrontend default .empty default default
          let delta : Lean.ConstMap := env.constants.fold
            (init := Lean.SMap.empty) fun acc n c =>
              if env₀.contains n then acc else acc.insert n c
          match extractEnv delta env.constants
            (args.contains "-pl") (args.contains "-py") with
          | .ok env =>
            -- todo: compile to .ya
            return 0
          | .error e =>
            IO.eprintln e
            return 1
        else
          IO.eprintln s!"Lean frontend failed on file {fileName}"
          return 1
      else
        -- todo: print help
        return 0
    | _ =>
      -- todo: print help
      return 0
  else
    -- todo: print help
    return 0
