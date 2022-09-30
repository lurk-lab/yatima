import Yatima.Cli.Utils
import Yatima.Typechecker.Typechecker
import Yatima.Transpiler.Transpiler
import Yatima.ForLurkRepo.Eval

open System Yatima.Compiler Yatima.Typechecker in
def typecheckRun (p : Cli.Parsed) : IO UInt32 := do
  let fileName : String := p.positionalArg! "input" |>.as! String
  match ← readStoreFromFile fileName with
  | .error err => IO.eprintln err; return 1
  | .ok store => match typecheck store with
    | .ok _ => IO.println "Typechecking succeeded"; return 0
    | .error msg => IO.eprintln msg; return 1

def typecheckCmd : Cli.Cmd := `[Cli|
  typecheck VIA typecheckRun;
  "Typechecks Yatima IR"

  ARGS:
    input : String; "Input DagCbor binary file"
]
