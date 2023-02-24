import TestsUtils.ContAddrAndExtractTests

def initFixturesPath : System.FilePath :=
  "Fixtures" / "Typechecker"

open LSpec in
def main := do
  lspecIO $ ← ensembleTestExtractors'
    [ initFixturesPath / "InfListFalse.lean",
      initFixturesPath / "MetaFalse.lean",
      initFixturesPath / "AxiomFalse.lean",
      initFixturesPath / "SorryFalse.lean" ]
    [extractNonTypecheckingTests]
    []