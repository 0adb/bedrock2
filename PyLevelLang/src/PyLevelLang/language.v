Require Import String.
Require Import ZArith.
Require Import List.
Require Import coqutil.Map.Interface coqutil.Map.Properties.
Require Import coqutil.Datatypes.Result.
Import ResultMonadNotations.

Inductive type : Type :=
  | TInt
  | TBool
  | TString
  | TPair (t1 t2 : type)
  | TList (t : type)
  | TEmpty. (* "Empty" type: its only value should be the empty tuple () *)

Scheme Equality for type. (* creates type_beq and type_eq_dec *)

Declare Scope pylevel_scope. Local Open Scope pylevel_scope.
Notation "t1 =? t2" := (type_beq t1 t2) (at level 70) : pylevel_scope.

(* Construct a "record" type using a list of types *)
Fixpoint TRecord (l : list type) : type :=
  match l with
  (* This creates the issue of having the empty type as the last element *)
  | nil => TEmpty
  | t :: ts => TPair t (TRecord ts)
  end.

(* "Pre-expression": untyped expressions from surface-level parsing. *)
Inductive pexpr : Type :=
  | PEVar (x : string)
  | PELoc (l : string)
  | PEInt (n : Z)
  | PEBool (b : bool)
  | PEString (s : string)
  | PEPair (p1 p2 : pexpr)
  | PEFst (p: pexpr)
  | PESnd (p: pexpr)
  | PENil (t : type)
  | PECons (p1 p2 : pexpr)
  | PERange (lo hi : pexpr)
  | PEFlatmap (p1 : pexpr) (x : string) (p2 : pexpr)
  | PEIf (p1 p2 p3 : pexpr)
  | PELet (x : string) (p1 p2 : pexpr).

(* Typed expressions. Most of the type checking is enforced in the GADT itself
   via Coq's type system, but some of it needs to be done in the [elaborate]
   function below *)
Inductive expr : type -> Type :=
  | EVar (t : type) (x : string) : expr t
  | ELoc (t : type) (l : string) : expr t
  | EInt (n : Z) : expr TInt
  (* TODO: ultimately use a more efficient implementation than Z for arbitrarily
     large integers; this can probably be taken care of by compiling to
     Bedrock *)
  | EBool (b : bool) : expr TBool
  | EString (s : string) : expr TString
  | EPair (t1 t2 : type) (e1 : expr t1) (e2 : expr t2) : expr (TPair t1 t2)
  | EFst (t1 t2 : type) (e : expr (TPair t1 t2)) : expr t1
  | ESnd (t1 t2 : type) (e : expr (TPair t1 t2)) : expr t2
  | ENil (t : type) : expr (TList t)
  | ECons (t : type) (e1 : expr t) (e2 : expr (TList t)) : expr (TList t)
  | ERange (lo hi : expr TInt) : expr (TList TInt)
  | ELet (t1 t2 : type) (x : string) (e1 : expr t1) (e2 : expr t2) : expr t2
  | EIf (t : type) (e1 : expr TBool) (e2 e3 : expr t) : expr t
  | EFlatmap (t : type) (e1 : expr (TList t)) (x : string) (e2 : expr (TList t))
      : expr (TList t).

Inductive command : Type :=
  | CSkip
  | CSeq (c1 c2 : command)
  | CLet (t: type) (x : string) (e : expr t) (c : command)
  | CLetMut (t : type) (l : string) (e : expr t) (c : command)
  | CIf (e : expr TBool) (c1 c2 : command)
  | CForeach (t: type) (x : string) (e : expr (TList t)) (c : command).


(* A few helper functions *)
(* Takes an integer n and a natural number c' and returns a 
   list of TInt expressions corresponding to [n, n + c) *)
Fixpoint EIntRange (s : Z)  (c: nat) : list (expr TInt) :=
  match c with
  | 0 => nil
  | S c' => EInt s :: EIntRange (s + 1) c'
  end.

Fixpoint interp_type (t: type) :=
  match t with
  | TInt => Z
  | TBool => bool
  | TString => string
  | TPair t1 t2 => prod (interp_type t1) (interp_type t2)
  | TList u => list (interp_type u)
  | TEmpty => unit
  end.

(* Casts one type to another, provided that they are equal
   https://stackoverflow.com/a/52518299 *)
Definition cast {T : Type} {T1 T2 : T} (H : T1 = T2) (f: T -> Type) (x : f T1) : f T2 :=
  eq_rect T1 (fun T3 : T => f T3) x T2 H.

Section WithMap.
  (* abstract all functions in this section over the implementation of the map,
     and over its spec (map.ok) *)
  Context {locals: map.map string {t & interp_type t}} {locals_ok: map.ok locals}.
  (* Type checks a [pexpr] and possibly emits a typed expression
     Checks scoping and field names/indices (for records) *)
  (* TODO: take context into account for variables, locations, and flatmap and
     let expressions *)   
  Fixpoint elaborate (p : pexpr) : result {t & expr t}.
  Proof. 
    refine (
    match p with
    | PEVar x => _
    | PELoc l => _
    | PEInt n =>
        Success (existT _ _ (EInt n))
    | PEBool b =>
        Success (existT _ _ (EBool b))
    | PEString s =>
        Success (existT _ _ (EString s))
    | PEPair p1 p2 =>
        '(existT _ t1 e1) <- elaborate p1 ;;
        '(existT _ t2 e2) <- elaborate p2 ;;
        Success (existT _ _ (EPair t1 t2 e1 e2))
    | PEFst p' =>
        '(existT _ t' e') <- elaborate p' ;;
        (match t' as t'' return t' = t'' -> _ with
         | TPair t1 t2 =>
             fun H => Success (existT _ _ (EFst _ _ (cast H _ e')))
         | _ => fun _ => error:("PEFst applied to non-pair")
         end) (eq_refl _)
    | PESnd p' =>
        '(existT _ t' e') <- elaborate p' ;;
        (match t' as t'' return t' = t'' -> _ with
         | TPair t1 t2 =>
             fun H => Success (existT _ _ (ESnd _ _ (cast H _ e')))
         | _ => fun _ => error:("PESnd applied to non-pair")
         end) (eq_refl _)
    | PENil t =>
        Success (existT _ _ (ENil t))
    | PECons p1 p2 =>
        '(existT _ t1 e1) <- elaborate p1 ;;
        '(existT _ t2 e2) <- elaborate p2 ;;
        match t2 with
        | TList _ =>
            match type_eq_dec t2 (TList t1) with
            | left H =>
                Success (existT _ _ (ECons t1 e1 (cast H _ e2)))
            | _ => error:("PECons with mismatched types")
            end
        | _ => error:("PECons with non-list")
        end
    | PERange lo hi =>
        '(existT _ t_lo e_lo) <- elaborate lo ;;
        '(existT _ t_hi e_hi) <- elaborate hi ;;
        match type_eq_dec t_lo TInt, type_eq_dec t_hi TInt with
        | left Hlo, left Hhi =>
            Success (existT _ _ (ERange (cast Hlo _ e_lo) (cast Hhi _ e_hi)))
        | _, _ => error:("PERange with non-integer(s)")
        end
    | PEFlatmap p1 x p2 => _
    | PEIf p1 p2 p3 => _
    | PELet x p1 p2 => _
    end).

    - admit.
    - admit.
    - admit.
    - admit.
    - admit.
  Admitted.
End WithMap.
