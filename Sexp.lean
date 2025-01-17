import Lean

inductive Sexp : Type
| atom : String → Sexp
| string : String → Sexp
| integer : Int → Sexp
| double : Float → Sexp
| cons : List Sexp → Sexp
deriving Inhabited

partial def Sexp.toString : Sexp → String
  | .atom s => s
  | .string s => s.quote
  | .integer k => ToString.toString k
  | .double x => ToString.toString x
  | .cons lst => "(" ++ (" ".intercalate $ lst.map toString) ++ ")"

instance: ToString Sexp where
  toString := Sexp.toString

def constr (head : String) (lst : List Sexp) : Sexp :=
  .cons ((.atom (":" ++ head)) :: lst)

class Sexpable (α : Type) : Type where
  toSexp : α → Sexp

def toSexp {α : Type} [s : Sexpable α] (x : α): Sexp := s.toSexp x

instance: Sexpable String where
  toSexp := .string

instance: Sexpable Int where
  toSexp := .integer

instance: Sexpable Nat where
  toSexp := fun n => .integer ↑n

instance: Sexpable UInt64 where
  toSexp := fun k => .integer ↑k.val

instance: Sexpable Float where
  toSexp := .double

def Sexp.fromName (n : Lean.Name) : Sexp :=
  match n with
  | .anonymous => constr "anonymous" []
  | .str mdl nm =>
    constr "name" $ (toSexp mdl.hash) :: (toSexp nm.hash) :: (toAtoms n).reverse
  | .num mdl k =>
    constr "name" $ (toSexp mdl.hash) :: (toSexp k) :: (toAtoms n).reverse
  where
    toAtoms (n : Lean.Name) : List Sexp :=
      match n with
      | .anonymous => [.atom "_"]
      | .str .anonymous s => [.atom s]
      | .str mdl s => .atom s :: toAtoms mdl
      | .num mdl k => .atom s!"num{k}" :: toAtoms mdl

instance: Sexpable Lean.Name where
  toSexp := Sexp.fromName

def Sexp.fromLevel (lvl : Lean.Level) : Sexp := constr "level" [fromLvl lvl]
  where
    fromLvl : Lean.Level → Sexp
    | .zero => constr "lzero" []
    | .succ lvl =>  constr "lsucc" [fromLevel lvl]
    | .max lvl1 lvl2 => constr "max" [fromLevel lvl1, fromLevel lvl2]
    | .imax lvl1 lvl2 => constr "imax" [fromLevel lvl1, fromLevel lvl2]
    | .param nm => toSexp nm
    | .mvar mv => toSexp mv.name

instance: Sexpable Lean.Level where
  toSexp := Sexp.fromLevel

instance: Sexpable Lean.BinderInfo where
  toSexp := fun info =>
    match info with
    | .default => constr "default" []
    | .implicit => constr "implicit" []
    | .strictImplicit => constr "strict-implicit" []
    | .instImplicit => constr "inst-implicit" []

instance: Sexpable Lean.Literal where
  toSexp := fun lit =>
    match lit with
    | .natVal val => constr "literal" [toSexp val]
    | .strVal val => constr "literal" [toSexp val]

def size : Lean.Expr → Nat
  | .bvar _ => 1
  | .fvar _ => 1
  | .mvar _ => 1
  | .sort _ => 1
  | .const _ _ => 1
  | .app e1 e2 => 1 + size e1 + size e2
  | .lam _ binderType body _ => 1 + size binderType + size body
  | .forallE _ binderType body _ => 1 + size binderType + size body
  | .letE _ type value body _ => 1 + size type + size value + size body
  | .lit _ => 1
  | .mdata _ expr => 1 + size expr
  | .proj _ _ struct => 1 + size struct

-- create a count of subexpressions to detect the ones that repeat several times
def collect (seen : Lean.HashMap Lean.Expr Nat) (e : Lean.Expr) : Lean.HashMap Lean.Expr Nat :=
  match seen.find? e with
  | .some k =>
    -- seen before, no need to descend into subexpressions (this avoids exponential blowup)
    seen.insert e (k + 1)
  | .none =>
    match e with
    | .bvar _ => seen
    | .fvar _ => seen
    | .mvar _ => seen
    | .sort _ => seen
    | .const _ _ => seen
    | .lit _ => seen
    | .app e1 e2 => collect (collect seen e1) e2
    | .lam _ binderType body _ => collect (collect (seen.insert e 0) binderType) body
    | .forallE _ binderType body _ => collect (collect (seen.insert e 0) binderType) body
    | .letE _ type value body _ => collect (collect (collect (seen.insert e 0) type) value) body
    | .mdata _ expr => collect (seen.insert e 0) expr
    | .proj _ _ struct => collect (seen.insert e 0) struct

partial def Sexp.fromExpr (e : Lean.Expr) : Sexp :=
  match e with
  | .bvar k => constr "var" [toSexp k]
  | .fvar fv => toSexp fv.name
  | .mvar mvarId => constr "meta" [toSexp mvarId.name]
  | .sort u => constr "sort" [toSexp u]
  | .const declName us => constr "const" $ toSexp declName :: us.map toSexp
  | .app _ _ => constr "apply" $ (getSpine e).reverse.map fromExpr
  | .lam _ binderType body _ => constr "lambda" [fromExpr binderType, fromExpr body]
  | .forallE _ binderType body _ => constr "pi" [fromExpr binderType, fromExpr body]
  | .letE declName type value body _ =>
    constr "let" [toSexp declName, fromExpr type, fromExpr value, fromExpr body]
  | .lit l => toSexp l
  | .mdata _ expr => fromExpr expr
  | .proj typeName idx struct => constr "proj" [toSexp typeName, toSexp idx, fromExpr struct]
  where getSpine (e : Lean.Expr) : List Lean.Expr :=
    match e with
    | .app e1 e2 => e2 :: getSpine e1
    | e => [e]

instance: Sexpable Lean.Expr where
  toSexp := Sexp.fromExpr
  -- toSexp := fun e => constr "size" [toSexp $ size e]

instance: Sexpable Lean.QuotKind where
  toSexp := fun k =>
    match k with
  | .type => constr "type" []
  | .ctor => constr "ctor" []
  | .lift => constr "lift" []
  | .ind  => constr "ind" []

instance: Sexpable Lean.ConstantInfo where
  toSexp := fun info =>
    constr "definition" [toSexp info.name, toSexp info.type, theDef info]
    where theDef : Lean.ConstantInfo → Sexp := fun info =>
      match info with
      | .axiomInfo _ => constr "axiom" []
      | .defnInfo val => constr "function" [toSexp val.value]
      | .thmInfo val => constr "function" [toSexp val.value]
      | .opaqueInfo val => constr "abstract" [toSexp val.value]
      | .quotInfo val => constr "quot-info" [toSexp val.kind, toSexp val.toConstantVal.name]
      | .inductInfo val => constr "data" $ toSexp val.type :: val.ctors.map toSexp
      | .ctorInfo val => constr "constructor" [toSexp val.induct]
      | .recInfo val => constr "recursor" [toSexp val.type]

def Sexp.fromModuleData (nm : Lean.Name) (data : Lean.ModuleData) : Sexp :=
  let lst := data.constants.toList.filter keepEntry
  constr "module" $ constr "module-name" [toSexp nm] :: lst.map toSexp
  where keepEntry (info : Lean.ConstantInfo) : Bool :=
    match info.name with
    | .anonymous => true
    | .str _ _ => ! info.name.isInternal
    | .num _ k => true
