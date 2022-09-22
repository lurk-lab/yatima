import Lean

namespace Lean

def compareNames : Name → Name → Ordering
  | .anonymous, .anonymous => .eq
  | .num namₗ nₗ, .num namᵣ nᵣ =>
    if nₗ < nᵣ then .lt
    else
      if nₗ > nᵣ then .gt
      else compareNames namₗ namᵣ
  | .str namₗ sₗ, .str namᵣ sᵣ =>
    if sₗ < sᵣ then .lt
    else
      if sₗ > sᵣ then .gt
      else compareNames namₗ namᵣ
  | .anonymous, .num .. => .lt
  | .anonymous, .str .. => .lt
  | .num .., .str .. => .lt
  | .num .., .anonymous => .gt
  | .str .., .anonymous => .gt
  | .str .., .num .. => .gt

instance : Ord Name where
  compare := compareNames

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

section OpenReferences

open Std (RBTree)

def getOpenReferencesInExpr (map : ConstMap) (mem : RBTree Name compare) :
    Expr → RBTree Name compare
  | .app e₁ e₂ .. =>
    (getOpenReferencesInExpr map mem e₁).union (getOpenReferencesInExpr map mem e₂)
  | .lam _ e₁ e₂ .. =>
    (getOpenReferencesInExpr map mem e₁).union (getOpenReferencesInExpr map mem e₂)
  | .forallE _ e₁ e₂ .. =>
    (getOpenReferencesInExpr map mem e₁).union (getOpenReferencesInExpr map mem e₂)
  | .letE _ e₁ e₂ e₃ .. =>
    (getOpenReferencesInExpr map mem e₁).union $ (getOpenReferencesInExpr map mem e₂).union
      (getOpenReferencesInExpr map mem e₃)
  | .mdata _ e ..  => getOpenReferencesInExpr map mem e
  | .proj n _ e .. =>
    getOpenReferencesInExpr map (if map.contains n then mem else mem.insert n) e
  | .const n .. => if map.contains n then mem else mem.insert n
  | _ => mem

def getOpenReferencesInConst (map : Lean.ConstMap) : Lean.ConstantInfo → RBTree Name compare
  | .axiomInfo struct => getOpenReferencesInExpr map .empty struct.type
  | .thmInfo struct =>
      getOpenReferencesInExpr
        map (getOpenReferencesInExpr map .empty struct.type) struct.value
  | .opaqueInfo struct =>
      getOpenReferencesInExpr
        map (getOpenReferencesInExpr map .empty struct.type) struct.value
  | .defnInfo struct =>
      getOpenReferencesInExpr
        map (getOpenReferencesInExpr map .empty struct.type) struct.value
  | .ctorInfo struct => getOpenReferencesInExpr map .empty struct.type
  | .inductInfo struct => getOpenReferencesInExpr map .empty struct.type
  | .recInfo struct =>
    struct.rules.foldl
      (init := getOpenReferencesInExpr map .empty struct.type)
      fun acc r => getOpenReferencesInExpr map acc r.rhs
  | .quotInfo struct => getOpenReferencesInExpr map .empty struct.type

def hasOpenReferenceInExpr (openReferences : RBTree Name compare) : Lean.Expr → Bool
  | .app e₁ e₂ .. =>
    hasOpenReferenceInExpr openReferences e₁
      || hasOpenReferenceInExpr openReferences e₂
  | .lam _ e₁ e₂ .. =>
    hasOpenReferenceInExpr openReferences e₁
      || hasOpenReferenceInExpr openReferences e₂
  | .forallE _ e₁ e₂ .. =>
    hasOpenReferenceInExpr openReferences e₁
      || hasOpenReferenceInExpr openReferences e₂
  | .letE _ e₁ e₂ e₃ .. =>
    hasOpenReferenceInExpr openReferences e₁
      || hasOpenReferenceInExpr openReferences e₂
      || hasOpenReferenceInExpr openReferences e₃
  | .mdata _ e ..  => hasOpenReferenceInExpr openReferences e
  | .proj n _ e .. =>
    openReferences.contains n
      || hasOpenReferenceInExpr openReferences e
  | .const n .. => openReferences.contains n
  | _ => false

def hasOpenReferenceInConst (openReferences : RBTree Name compare) :
    Lean.ConstantInfo → Bool
  | .axiomInfo struct => hasOpenReferenceInExpr openReferences struct.type
  | .thmInfo struct =>
    hasOpenReferenceInExpr openReferences struct.type
      || hasOpenReferenceInExpr openReferences struct.value
  | .opaqueInfo struct =>
    hasOpenReferenceInExpr openReferences struct.type
      || hasOpenReferenceInExpr openReferences struct.value
  | .defnInfo struct =>
    hasOpenReferenceInExpr openReferences struct.type
      || hasOpenReferenceInExpr openReferences struct.value
  | .ctorInfo struct => hasOpenReferenceInExpr openReferences struct.type
  | .inductInfo struct => hasOpenReferenceInExpr openReferences struct.type
  | .recInfo struct =>
    struct.rules.foldl
      (init := hasOpenReferenceInExpr openReferences struct.type)
      fun acc r => acc || hasOpenReferenceInExpr openReferences r.rhs
  | .quotInfo struct => hasOpenReferenceInExpr openReferences struct.type

def filterConstants (cs : ConstMap) : ConstMap :=
  let openReferences : RBTree Name compare := cs.fold (init := .empty)
    fun acc _ c => acc.union (getOpenReferencesInConst cs c)
  Lean.List.toSMap $ cs.toList.filter fun (n, c) =>
    (!openReferences.contains n) && (!hasOpenReferenceInConst openReferences c)

end OpenReferences

instance : BEq ReducibilityHints where beq
  | .opaque,    .opaque    => true
  | .abbrev,    .abbrev    => true
  | .regular l, .regular r => l == r
  | _,          _          => false

instance : BEq QuotKind where beq
  | .type, .type => true
  | .ctor, .ctor => true
  | .lift, .lift => true
  | .ind,  .ind  => true
  | _,     _     => false

instance : BEq RecursorRule where beq
  | ⟨cₗ, nₗ, rₗ⟩, ⟨cᵣ, nᵣ, rᵣ⟩ => cₗ == cᵣ && nₗ == nᵣ && rₗ == rᵣ

instance : BEq ConstantInfo where
  beq (l r : ConstantInfo) : Bool :=
  l.name == r.name && l.levelParams == r.levelParams && l.type == r.type
    && match l, r with
  | .axiomInfo  l, .axiomInfo  r => l.isUnsafe == r.isUnsafe
  | .thmInfo    l, .thmInfo    r => l.value == r.value
  | .opaqueInfo l, .opaqueInfo r =>
    l.isUnsafe == r.isUnsafe && l.value == r.value
  | .defnInfo   l, .defnInfo   r =>
    l.value == r.value && l.safety == r.safety && l.hints == r.hints
  | .ctorInfo   l, .ctorInfo   r =>
    l.induct == r.induct && l.cidx == r.cidx && l.numParams == r.numParams
      && l.numFields == r.numFields && l.isUnsafe == r.isUnsafe
  | .inductInfo l, .inductInfo r =>
    l.numParams == r.numParams && l.numIndices == r.numIndices && l.all == r.all
      && l.ctors == r.ctors && l.isRec == r.isRec && l.isUnsafe == r.isUnsafe
      && l.isReflexive == r.isReflexive && l.isNested == r.isNested
  | .recInfo    l, .recInfo    r =>
    l.all == r.all && l.numParams == r.numParams && l.numIndices == r.numIndices
      && l.numMotives == r.numMotives && l.numMinors == r.numMinors
      && l.rules == r.rules && l.k == r.k && l.isUnsafe == r.isUnsafe
  | .quotInfo   l, .quotInfo   r => l.kind == r.kind
  | _, _ => false

open Elab in
def runFrontend (input : String) (fileName : String := default) :
    IO $ Option String × Environment := do
  let inputCtx := Parser.mkInputContext input fileName
  let (header, parserState, messages) ← Parser.parseHeader inputCtx
  let (env, messages) ← processHeader header default messages inputCtx 0
  let env := env.setMainModule default
  let commandState := Command.mkState env messages default

  let s ← IO.processCommands inputCtx parserState commandState
  let msgs := s.commandState.messages
  let errMsg := if msgs.hasErrors
    then some $ "\n\n".intercalate $
      (← msgs.toList.mapM (·.toString)).map String.trim
    else none
  return (errMsg, s.commandState.env)
end Lean

instance : HMul Ordering Ordering Ordering where
  hMul
  | .gt, _ => .gt
  | .lt, _ => .lt
  | .eq, x => x

instance [Ord α] : Ord $ Option α where
  compare x y := match x, y with
  | some x, some y => compare x y
  | some _, none => .gt
  | none, some _ => .lt
  | none, none => .eq

instance [Ord α] [Ord β] : Ord $ α × β where
  compare x y := compare x.1 y.1 * compare x.2 y.2

def concatOrds : List Ordering → Ordering :=
  List.foldl (fun x y => x * y) .eq

namespace Std

namespace PersistentHashMap

def filter {_ : BEq α} {_ : Hashable α} 
    (map : PersistentHashMap α β) (p : α → β → Bool) : PersistentHashMap α β :=
  map.foldl (init := .empty) fun acc x y => 
    match p x y with 
      | true => acc.insert x y 
      | false => acc

end PersistentHashMap
end Std

section 
variable {α : Type u} {β : Type v} {σ : Type u} {_ : BEq α} {_ : Hashable α} 
variable {m : Type u → Type w} [Monad m]

def Std.HashMap.mapM (hmap : Std.HashMap α β) (f : β → m σ) : m (Std.HashMap α σ) := do 
  let l := hmap.toList
  dbg_trace s!"AFTER toList"
  let thing ← l.mapM fun (a, b) => do 
    dbg_trace s!"HI?"
    let out ← f b
    dbg_trace s!"AFTER out"
    return (a, out) 
  dbg_trace s!"AFTER thing"
  return Std.HashMap.ofList thing 

def Std.HashMap.map (hmap : Std.HashMap α β) (f : β → σ) : Std.HashMap α σ := 
  Std.HashMap.ofList $ hmap.toList.map fun (a, b) => (a, f b)  

def Std.HashMap.filter (hmap : Std.HashMap α β) (p : α → β → Bool) : Std.HashMap α β :=
  Std.HashMap.ofList $ hmap.toList.filter fun (a, b) => p a b

def Lean.SMap.mapM (smap : Lean.SMap α β) (f : β → m σ) : m (Lean.SMap α σ) := do 
  let m₁ ← smap.map₁.mapM f
  let m₂ ← smap.map₂.mapM f
  return ⟨smap.stage₁, m₁, m₂⟩

def Lean.SMap.map (smap : Lean.SMap α β) (f : β → σ) : Lean.SMap α σ :=
  let m₁ := smap.map₁.map f
  let m₂ := smap.map₂.map f
  ⟨smap.stage₁, m₁, m₂⟩

def Lean.SMap.filter (smap : Lean.SMap α β) (f : α → β → Bool) : Lean.SMap α β :=
  ⟨smap.stage₁, smap.map₁.filter f, smap.map₂.filter f⟩

end 

open Lean in 
def patchUnsafeRec (cs : ConstMap) : ConstMap := 
  let unsafes : Std.HashSet Name := 
    cs.fold (init := .empty) fun acc n _ => match n with 
    | .str n "_unsafe_rec" => acc.insert n 
    | _ => acc
  cs.map fun c => match c with 
    | .opaqueInfo o => 
      if unsafes.contains o.name then 
        .opaqueInfo ⟨
            o.toConstantVal, mkConst (o.name ++ `_unsafe_rec), 
            o.isUnsafe, o.levelParams
          ⟩
      else 
        .opaqueInfo o
    | c => c