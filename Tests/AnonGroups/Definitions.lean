import TestsUtils.ContAddrAndExtractTests

def wellFoundedExtractor := extractAnonGroupsTests [
  [`WellFounded.A, `WellFounded.A'],
  [`WellFounded.B, `WellFounded.B'],
  [`WellFounded.C, `WellFounded.C'],
  [`WellFounded.E, `WellFounded.E'],
  [`WellFounded.F, `WellFounded.F'],
  [`WellFounded.G, `WellFounded.G'],
  [`WellFounded.H, `WellFounded.H'],
  [`WellFounded.I, `WellFounded.I']]

def partialExtractor := extractAnonGroupsTests [
  [`Partial.A, `Partial.C, `Partial.E, `Partial.F,
   `Partial.B, `Partial.G, `Partial.H], [`Partial.I]]

open LSpec in
def main := do
  lspecIO $ ← ensembleTestExtractors
    ("Fixtures" / "AnonGroups" / "Definitions.lean")
    [ wellFoundedExtractor, partialExtractor/-, extractTypecheckingTests-/]
    []
