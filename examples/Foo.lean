inductive BLA
  | nil
  | bla : BLA → BLA → BLA

inductive BLAH | blah : BLA → BLAH

mutual
inductive BLE | bli : BLI → BLE
inductive BLI | ble : BLE → BLI
inductive BLO | blea : BLE → BLA → BLO
end

inductive BLEH
  | bleh : BLE → BLEH
  | bloh : BLO → BLEH

mutual
  inductive Tree (A : Type) where
    | branch : (a : A) → (trees : TreeList A) → Tree A

  inductive TreeList (A : Type) where
    | nil : TreeList A
    | cons : (t : Tree A) → (ts : TreeList A) → TreeList A
end

inductive Treew (A : Type) where
  | branch : (a : A) → (trees : List (Treew A)) → Treew A

mutual
  inductive Treeq (A : Type) where
    | branch : TreeListq A → (a : A) → (trees : List (Treeq A)) → Treeq A

  inductive TreeListq (A : Type) where
    | nil : TreeListq A
    | cons : (t : Treeq A) → (ts : TreeListq A) → TreeListq A
end

-- mutual
--   unsafe def A : Nat → Nat
--   | 0 => 0
--   | n + 1 => B n + E n + C n + 1

--   unsafe def C : Nat → Nat
--   | 0 => 0
--   | n + 1 => B n + F n + A n + 1

--   unsafe def B : Nat → Nat
--   | 0 => 0
--   | n + 1 => C n + 2

--   unsafe def E : Nat → Nat 
--   | 0 => 0 
--   | n + 1 => B n + A n + F n + 1

--   unsafe def F : Nat → Nat 
--   | 0 => 0 
--   | n + 1 => B n + C n + E n + 1

--   unsafe def G : Nat → Nat 
--   | 0 => 0
--   | n + 1 => B n + F n + H n + 2

--   unsafe def H : Nat → Nat 
--   | 0 => 0
--   | n + 1 => B n + E n + G n + 2
-- end
