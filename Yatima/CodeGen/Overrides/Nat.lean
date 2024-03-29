import Yatima.CodeGen.Override

namespace Lurk.Overrides

open Lurk Expr.DSL LDON.DSL DSL
open Yatima.CodeGen

def NatInductiveData : InductiveData :=
  ⟨``Nat, 0, 0, .ofList [(``Nat.zero, 0), (``Nat.succ, 1)]⟩

def NatCore : Override.Decl := ⟨``Nat, ⟦
  ,("Nat" 0 0 Fin)
⟧⟩

def Nat.zero : Override.Decl := ⟨``Nat.zero, ⟦
  0
⟧⟩

def Nat.succ : Override.Decl := ⟨``Nat.succ, ⟦
  (lambda (n) (+ n 1))
⟧⟩

def NatMkCases (discr : Expr) (alts : Array Override.Alt) : Except String Expr := do
  let mut defaultElse : Expr := .atom .nil
  let mut ifThens : Array (Expr × Expr) := #[]
  for alt in alts do match alt with
    | .default k => defaultElse := k
    | .alt cidx params k =>
      if cidx == 0 then
        unless params.isEmpty do
          throw s!"`Nat.zero` case expects exactly 0 params, got\n {params}"
        ifThens := ifThens.push (⟦(= $discr 0)⟧, k)
      else if cidx == 1 then
        let #[param] := params |
          throw s!"`Nat.succ` case expects exactly 1 param, got\n {params}"
        let param := param.toString false
        let case := .let param ⟦(- $discr 1)⟧ k
        ifThens := ifThens.push (⟦(lneq $discr 0)⟧, case)
      else
        throw s!"{cidx} is not a valid `Nat` constructor index"
  let cases := Expr.mkIfElses ifThens.toList defaultElse
  return cases

protected def Nat : Override := Override.ind
  ⟨NatInductiveData, NatCore, #[Nat.zero, Nat.succ], NatMkCases⟩

def Nat.add : Override := Override.decl ⟨``Nat.add, ⟦
  (lambda (a b) (+ a b))
⟧⟩

def Nat.sub : Override := Override.decl ⟨``Nat.sub, ⟦
  (lambda (a b)
    (if (< a b)
      0
      (- a b)))
⟧⟩

def Nat.pred : Override := Override.decl ⟨``Nat.pred, ⟦
  (lambda (a)
    (if (= a 0)
      0
      (- a 1)))
⟧⟩

def Nat.mul : Override := Override.decl ⟨``Nat.mul, ⟦
  (lambda (a b) (* a b))
⟧⟩

/-- TODO FIXME: this is a hack for fast division.
  This currently has no support in the evaluator. -/
def Nat.div : Override := Override.decl ⟨``Nat.div, ⟦
  (lambda (a b) (num (/ (u64 a) (u64 b))))
⟧⟩

def Nat.mod : Override := Override.decl ⟨``Nat.mod, ⟦
  (lambda (a b)
    (if (= b 0)
        a
        (if (< a b)
            a
            (- a (* (Nat.div a b) b)))))
⟧⟩

def Nat.decLe : Override := Override.decl ⟨``Nat.decLe, ⟦
  (lambda (a b) (to_bool (<= a b)))
⟧⟩

def Nat.decLt : Override := Override.decl ⟨``Nat.decLt, ⟦
  (lambda (a b) (to_bool (< a b)))
⟧⟩

def Nat.decEq : Override := Override.decl ⟨``Nat.decEq, ⟦
  (lambda (a b) (to_bool (= a b)))
⟧⟩

def Nat.beq : Override := Override.decl ⟨``Nat.beq, ⟦
  (lambda (a b) (to_bool (= a b)))
⟧⟩

-- not strictly needed for now, hopefully `lurk` can implement
-- `land`, `lor`, and `xor` natively
-- enabling this gives about 60% reduction in frame count

-- def Nat.bitwise : Override := Override.decl ⟨``Nat.bitwise, ⟦
--   (lambda (f n m)
--     (if (= n 0)
--         (if (eq (f Bool.false Bool.true) Bool.true) m 0)
--         (if (= m 0)
--             (if (eq (f Bool.true Bool.false) Bool.true) n 0)
--             -- big else block
--             (let ((n' (Nat.div n 2))
--                   (m' (Nat.div m 2))
--                   (b₁ (to_bool (= (Nat.mod n 2) 1)))
--                   (b₂ (to_bool (= (Nat.mod m 2) 1)))
--                   (r (Nat.bitwise f n' m')))
--                 (if (eq (f b₁ b₂) Bool.true)
--                     (+ r (+ r 1))
--                     (+ r r))))))
-- ⟧⟩

def Nat.land : Override := Override.decl ⟨``Nat.land, ⟦
  (Nat.bitwise and)
⟧⟩

def Nat.lor : Override := Override.decl ⟨``Nat.lor, ⟦
  (Nat.bitwise or)
⟧⟩

def Nat.xor : Override := Override.decl ⟨``Nat.xor, ⟦
  (Nat.bitwise bne)
⟧⟩

def Nat.shiftLeft : Override := Override.decl ⟨``Nat.shiftLeft, ⟦
  (lambda (n m)
    (if (= m 0)
        n
        (Nat.shiftLeft (* 2 n) (- m 1))))
⟧⟩

def Nat.shiftRight : Override := Override.decl ⟨``Nat.shiftRight, ⟦
  (lambda (n m)
    (if (= m 0)
        n
        (/ (Nat.shiftRight n (- m 1)) 2)))
⟧⟩

def Nat.module := [
  Lurk.Overrides.Nat,
  Nat.add,
  Nat.sub,
  Nat.pred,
  Nat.mul,
  Nat.div,
  Nat.mod,
  Nat.decLe,
  Nat.decLt,
  Nat.decEq,
  Nat.beq,
  -- Nat.bitwise,
  Nat.land,
  Nat.lor,
  Nat.xor,
  Nat.shiftLeft,
  Nat.shiftRight
]

end Lurk.Overrides
