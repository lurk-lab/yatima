import Yatima.Typechecker.Value

namespace Yatima.Typechecker

def printUniv (univ : Univ) : String :=
  match univ with
  | .var nam _ => s!"{nam}"
  | .succ a => s!"(succ {printUniv a})"
  | .zero     => s!"0"
  | .imax a b => s!"(imax {printUniv a} {printUniv b})"
  | .max a b => s!"(max {printUniv a} {printUniv b})"

def printExpr (expr : Expr) : String :=
  match expr with
  | .var nam idx => s!"{nam}#{idx}"
  | .sort u => s!"(Sort {printUniv u})"
  | .const nam .. => s!"{nam}"
  | .app fnc arg => s!"({printExpr fnc} {printExpr arg})"
  | .lam nam binfo dom bod =>
    match binfo with
    | .implicit => s!"(λ\{{nam}: {printExpr dom}}. {printExpr bod})"
    | .strictImplicit => s!"(λ⦃{nam}: {printExpr dom}⦄. {printExpr bod})"
    | .instImplicit => s!"(λ[{nam}: {printExpr dom}]. {printExpr bod})"
    | _ => s!"(λ({nam}: {printExpr dom}). {printExpr bod})"
  | .pi nam binfo dom cod =>
    match binfo with
    | .implicit => s!"(\{{nam}: {printExpr dom}} → {printExpr cod})"
    | .strictImplicit => s!"(⦃{nam}: {printExpr dom}⦄ → {printExpr cod})"
    | .instImplicit => s!"([{nam}: {printExpr dom}] → {printExpr cod})"
    | _ => s!"(({nam}: {printExpr dom}) → {printExpr cod})"
  | .letE nam typ val bod => s!"let {nam} : {printExpr typ} := {printExpr val} in {printExpr bod}"
  | .lit (.nat x) => s!"{x}"
  | .lit (.str x) => s!"\"{x}\""
  | .lty .nat => s!"Nat"
  | .lty .str => s!"String"
  | .proj idx val => s!"{printExpr val}.{idx}"

mutual

partial def printVal (val : Value) : String :=
  match val with
  | .sort u => s!"(Sort {printUniv u})"
  | .app neu args => printSpine neu args
  | .lam nam binfo bod env =>
    match binfo with
    | .implicit => s!"(λ\{{nam}}}. {printLamBod bod env})"
    | .strictImplicit => s!"(λ⦃{nam}⦄. {printLamBod bod env})"
    | .instImplicit => s!"(λ[{nam}]. {printLamBod bod env})"
    | _ => s!"(λ({nam}). {printLamBod bod env})"
  | .pi nam binfo dom cod env =>
    let dom := dom.get
    match binfo with
    | .implicit => s!"(\{{nam}: {printVal dom}} → {printLamBod cod env})"
    | .strictImplicit => s!"(⦃{nam}: {printVal dom}⦄ → {printLamBod cod env})"
    | .instImplicit => s!"([{nam}: {printVal dom}] → {printLamBod cod env})"
    | _ => s!"(({nam}: {printVal dom}) → {printLamBod cod env})"
  | .lit (.nat x) => s!"{x}"
  | .lit (.str x) => s!"\"{x}\""
  | .lty .nat => s!"Nat"
  | .lty .str => s!"String"
  | .proj idx neu args => s!"{printSpine neu args}.{idx}"

partial def printLamBod (expr : Expr) (env : Env Value) : String :=
  match expr with
  | .var nam 0 => s!"{nam}#0"
  | .var nam idx =>
    match env.exprs.get? (idx-1) with
   | some val => printVal val.get
   | none => s!"{nam}#{idx}"
  | .sort u => s!"(Sort {printUniv u})"
  | .const nam .. => s!"{nam}"
  | .app fnc arg => s!"({printLamBod fnc env} {printLamBod arg env})"
  | .lam nam binfo dom bod =>
    match binfo with
    | .implicit => s!"(λ\{{nam}: {printLamBod dom env}}. {printLamBod bod env})"
    | .strictImplicit => s!"(λ⦃{nam}: {printLamBod dom env}⦄. {printLamBod bod env})"
    | .instImplicit => s!"(λ[{nam}: {printLamBod dom env}]. {printLamBod bod env})"
    | _ => s!"(λ({nam}: {printLamBod dom env}). {printLamBod bod env})"
  | .pi nam binfo dom cod =>
    match binfo with
    | .implicit => s!"(\{{nam}: {printLamBod dom env}} → {printLamBod cod env})"
    | .strictImplicit => s!"(⦃{nam}: {printLamBod dom env}⦄ → {printLamBod cod env})"
    | .instImplicit => s!"([{nam}: {printLamBod dom env}] → {printLamBod cod env})"
    | _ => s!"(({nam}: {printLamBod dom env}) → {printLamBod cod env})"
  -- | .letE _ nam typ val bod => s!""
  | .letE nam typ val bod => s!"let {nam} : {printLamBod typ env} := {printLamBod val env} in {printLamBod bod env}"
  | .lit (.nat x) => s!"{x}"
  | .lit (.str x) => s!"\"{x}\""
  | .lty .nat => s!"Nat"
  | .lty .str => s!"String"
  | .proj idx val => s!"{printLamBod val env}.{idx}"
  
partial def printSpine (neu : Neutral) (args : Args) : String :=
  match neu with
  | .fvar nam idx .. => List.foldl (fun str arg => s!"({str} {printVal arg.get})") s!"{nam}#{idx}" args
  | .const nam .. => List.foldl (fun str arg => s!"({str} {printVal arg.get})") s!"{nam}" args

end

instance : ToString Expr where toString := printExpr
instance : ToString Univ where toString := printUniv
instance : ToString Value where toString := printVal

end Yatima.Typechecker
