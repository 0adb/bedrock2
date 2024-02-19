Require Import Coq.Strings.String. Local Open Scope string_scope.
Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List. Import ListNotations. Local Open Scope list_scope.
Require Import coqutil.Tactics.fwd coqutil.Tactics.autoforward.
Require coqutil.Datatypes.String.
Require Import coqutil.Map.Interface coqutil.Word.Interface coqutil.Word.Bitwidth.
Require Import bedrock2.Semantics.
Local Open Scope string_scope.

#[local] Instance string_of_nbytes_inj: forall nbytes1 nbytes2,
    autoforward (String.of_nat (nbytes1 * 8) = String.of_nat (nbytes2 * 8))
                (nbytes1 = nbytes2).
Proof.
  intros * H.
  eapply String.of_nat_inj in H.
  eapply PeanoNat.Nat.mul_cancel_r. 2: eassumption.
  discriminate.
Qed.

Class MemoryMappedExtCalls{width: Z}{BW: Bitwidth width}
                          {word: word.word width}{mem: map.map word Byte.byte} := {
  read_step:
    nat -> (* how many bytes to read *)
    trace -> (* trace of events that happened so far *)
    word -> (* address to be read *)
    (word -> mem -> Prop) -> (* postcondition on returned value and memory *)
    Prop;
  write_step:
    nat -> (* how many bytes to write *)
    trace -> (* trace of events that happened so far *)
    word -> (* address to be written *)
    word -> (* value to be written *)
    mem -> (* memory whose ownership is passed to the external world *)
    Prop;
}.

Section WithMem.
  Context {width: Z} {BW: Bitwidth width}
          {word: word.word width} {mem: map.map word Byte.byte}.
  Context {word_ok: word.ok word}.

  Definition ext_spec{mmio_ext_calls: MemoryMappedExtCalls}: ExtSpec :=
    fun (t: trace) (mGive: mem) (action: string) (args: list word)
        (post: mem -> list word -> Prop) =>
      exists n, (n = 1 \/ n = 2 \/ n = 4 \/ (n = 8 /\ width = 64%Z))%nat /\
      ((action = "memory_mapped_extcall_read" ++ String.of_nat (n * 8) /\
        exists addr, args = [addr] /\ mGive = map.empty /\
                     read_step n t addr (fun v mRcv => post mRcv [v])) \/
       (action = "memory_mapped_extcall_write" ++ String.of_nat (n * 8) /\
        exists addr val, args = [addr; val] /\
                         write_step n t addr val mGive /\
                         post map.empty nil)).

  Class MemoryMappedExtCallsOk(ext_calls: MemoryMappedExtCalls): Prop := {
    weaken_read_step: forall t addr n post1 post2,
      read_step n t addr post1 ->
      (forall v mRcv, post1 v mRcv -> post2 v mRcv) ->
      read_step n t addr post2;
    intersect_read_step: forall t addr n post1 post2,
      read_step n t addr post1 ->
      read_step n t addr post2 ->
      read_step n t addr (fun v mRcv => post1 v mRcv /\ post2 v mRcv);
    write_step_unique_mGive: forall m t n mKeep1 mKeep2 mGive1 mGive2 addr val,
      map.split m mKeep1 mGive1 ->
      map.split m mKeep2 mGive2 ->
      write_step n t addr val mGive1 ->
      write_step n t addr val mGive2 ->
      mGive1 = mGive2;
  }.

  Lemma weaken_ext_spec{mmio_ext_calls: MemoryMappedExtCalls}
    {mmio_ext_calls_ok: MemoryMappedExtCallsOk mmio_ext_calls}:
    forall t mGive a args post1 post2,
      (forall mRcv rets, post1 mRcv rets -> post2 mRcv rets) ->
      ext_spec t mGive a args post1 ->
      ext_spec t mGive a args post2.
  Proof.
    unfold ext_spec; intros; fwd; destruct H0p1; fwd; eauto 10 using weaken_read_step.
  Qed.

  Instance ext_spec_ok(mmio_ext_calls: MemoryMappedExtCalls)
    {mmio_ext_calls_ok: MemoryMappedExtCallsOk mmio_ext_calls}: ext_spec.ok ext_spec.
  Proof.
    constructor.
    - (* mGive unique *)
      unfold ext_spec. intros. fwd. destruct H1p1; destruct H2p1; fwd; try congruence.
      inversion H1p1. fwd. eauto using write_step_unique_mGive.
    - (* weaken *)
      unfold Morphisms.Proper, Morphisms.respectful, Morphisms.pointwise_relation,
        Basics.impl. eapply weaken_ext_spec.
    - (* intersect *)
      unfold ext_spec. intros. fwd. destruct Hp1; destruct H0p1; fwd;
        match goal with
        | H: _ ++ _ = _ ++ _ |- _ => inversion H; clear H
        end;
        fwd; eauto 10 using intersect_read_step.
  Qed.

End WithMem.

#[export] Existing Instance ext_spec.
#[export] Existing Instance ext_spec_ok.
