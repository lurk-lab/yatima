import Lurk.DSL
import Yatima.CodeGen.Override

namespace Lurk.Overrides

open Lurk Expr.DSL LDON.DSL DSL
open Yatima.CodeGen

def ByteArrayInductiveData : InductiveData :=
  ⟨``ByteArray, 0, 0, .ofList [(``ByteArray.mk, 0)]⟩

def ByteArrayCore : Override.Decl := ⟨``ByteArray, ⟦
  (lambda (x) ,("ByteArray" 1 0))
⟧⟩

def ByteArray.mk : Override.Decl := ⟨``ByteArray.mk, ⟦
  (lambda (data) data)
⟧⟩

def ByteArrayMkCases (discr : Expr) (alts : Array Override.Alt) : Except String Expr := do
  let #[.alt 0 params k] := alts |
    throw s!"ByteArrayMkCases assumes structures having only one alternative, and never produce `default` match, got\n {alts}"
  let #[data] := params |
    throw s!"`ByteArray.mk` case expects exactly 1 param, got\n {params}"
  let data := data.toString false
  return .let data ⟦(ByteArray.data $discr)⟧ k

/-- We'll keep `ByteArray` isomorphic to `List` for now,
  but of course this is extremely inefficient. -/
protected def ByteArray : Override := Override.ind
  ⟨ByteArrayInductiveData, ByteArrayCore, #[ByteArray.mk], ByteArrayMkCases⟩

def ByteArray.data : Override := Override.decl ⟨``ByteArray.data, ⟦
  (lambda (self) self)
⟧⟩

def ByteArray.mkEmpty : Override := Override.decl ⟨``ByteArray.mkEmpty, ⟦
  (lambda (α c) (List.nil nil))
⟧⟩

def ByteArray.size : Override := Override.decl ⟨``ByteArray.size, ⟦
  (lambda (α a) (List.length α a))
⟧⟩

def ByteArray.get : Override := Override.decl ⟨``ByteArray.get, ⟦
  (lambda (α a i) (getelem! a i))
⟧⟩

def ByteArray.get! : Override := Override.decl ⟨``ByteArray.get!, ⟦
  (lambda (α inst a i) (getelem! a i))
⟧⟩

/-- Warning: this is `O(n)` and extremely inefficient. -/
def ByteArray.push : Override := Override.decl ⟨``ByteArray.push, ⟦
  (lambda (α a v) (push a v))
⟧⟩

def ByteArray.set : Override := Override.decl ⟨``ByteArray.set, ⟦
  (lambda (α a i v) (set a i v))
⟧⟩

def ByteArray.set! : Override := Override.decl ⟨``ByteArray.set!, ⟦
  (lambda (α a i v) (set! a i v))
⟧⟩

def ByteArray.uget : Override := Override.decl ⟨``ByteArray.uget, ⟦
  (lambda (α a i h) (getelem! a i))
⟧⟩

def ByteArray.uset : Override := Override.decl ⟨``ByteArray.uset, ⟦
  (lambda (α a i v h) (set a i v))
⟧⟩

/-- Is this the efficient thing in the world? No. Does it work? Uh probably not.
  But it's good enough for now. -/
def ByteArray.copySlice : Override := Override.decl ⟨``ByteArray.copySlice, ⟦
  (lambda (src srcOff dest destOff len exact)
    (Array.append nil
      (Array.extract nil dest 0 destOff)
      (Array.append nil
        (Array.extract nil src srcOff (+ srcOff len))
        (Array.extract nil dest (+ destOff len) (Array.size dest)))))
⟧⟩

def ByteArray.extract : Override := Override.decl ⟨``ByteArray.extract, ⟦
  (lambda (a b e) (Array.extract nil a b e))
⟧⟩

def ByteArray.append : Override := Override.decl ⟨``ByteArray.append, ⟦
  (lambda (a b) (Array.append nil a b))
⟧⟩

def ByteArray.hash : Override := Override.decl ⟨``ByteArray.hash, ⟦
  (lambda (α a) (commit a))
⟧⟩

def ByteArray.module : List Override := [
  Lurk.Overrides.ByteArray,
  ByteArray.data,
  ByteArray.mkEmpty,
  ByteArray.size,
  ByteArray.get,
  ByteArray.get!,
  ByteArray.push,
  ByteArray.set,
  ByteArray.set!,
  ByteArray.uget,
  ByteArray.copySlice,
  ByteArray.extract,
  ByteArray.append,
  ByteArray.hash
]

end Lurk.Overrides
