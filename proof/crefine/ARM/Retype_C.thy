(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

theory Retype_C
imports
  Detype_C
  CSpace_All
  StoreWord_C
begin

declare word_neq_0_conv [simp del]

instance cte_C :: array_outer_max_size
  by intro_classes simp

context begin interpretation Arch . (*FIXME: arch_split*)

lemma map_option_byte_to_word_heap:
  assumes disj: "\<And>(off :: 10 word) x. x<4 \<Longrightarrow> p + ucast off * 4 + x \<notin> S "
  shows "byte_to_word_heap (\<lambda>x. if x \<in> S then 0 else mem x) p
        = byte_to_word_heap mem p"
  by (clarsimp simp: option_map_def  byte_to_word_heap_def[abs_def]
                     Let_def disj disj[where x = 0,simplified]
              split: option.splits)

text {* Generalise the different kinds of retypes to allow more general proofs
about what they might change. *}
definition
  ptr_retyps_gen :: "nat \<Rightarrow> ('a :: c_type) ptr \<Rightarrow> bool \<Rightarrow> heap_typ_desc \<Rightarrow> heap_typ_desc"
where
  "ptr_retyps_gen n p mk_array
    = (if mk_array then ptr_arr_retyps n p else ptr_retyps n p)"

end

context kernel_m
begin

(* Ensure that the given region of memory does not contain any typed memory. *)
definition
  region_is_typeless :: "word32 \<Rightarrow> nat \<Rightarrow> ('a globals_scheme, 'b) StateSpace.state_scheme \<Rightarrow> bool"
where
  "region_is_typeless ptr sz s \<equiv>
      \<forall>z\<in>{ptr ..+ sz}. snd (snd (t_hrs_' (globals s)) z) = Map.empty"

lemma c_guard_word8:
  "c_guard (p :: word8 ptr) = (ptr_val p \<noteq> 0)"
  unfolding c_guard_def ptr_aligned_def c_null_guard_def
  apply simp
  apply (rule iffI)
   apply (drule intvlD)
   apply clarsimp
  apply simp
  apply (rule intvl_self)
  apply simp
  done

lemma
  "(x \<in> {x ..+ n}) = (n \<noteq> 0)"
  apply (rule iffI)
   apply (drule intvlD)
   apply clarsimp
  apply (rule intvl_self)
  apply simp
  done

lemma heap_update_list_append3:
    "\<lbrakk> s' = s + of_nat (length xs) \<rbrakk> \<Longrightarrow> heap_update_list s (xs @ ys) H = heap_update_list s' ys (heap_update_list s xs H)"
  apply simp
  apply (subst heap_update_list_append [symmetric])
  apply clarsimp
  done

lemma ptr_aligned_word32:
  "\<lbrakk> is_aligned p 2  \<rbrakk> \<Longrightarrow> ptr_aligned ((Ptr p) :: word32 ptr)"
  apply (clarsimp simp: is_aligned_def ptr_aligned_def)
  done

lemma c_guard_word32:
  "\<lbrakk> is_aligned (ptr_val p) 2; p \<noteq> NULL  \<rbrakk> \<Longrightarrow> c_guard (p :: (word32 ptr))"
  apply (clarsimp simp: c_guard_def)
  apply (rule conjI)
   apply (case_tac p, clarsimp simp: ptr_aligned_word32)
  apply (case_tac p, simp add: c_null_guard_def)
  apply (subst intvl_aligned_bottom_eq [where n=2 and bits=2], auto simp: word_bits_def)
  done

lemma is_aligned_and_not_zero: "\<lbrakk> is_aligned n k; n \<noteq> 0 \<rbrakk> \<Longrightarrow> 2^k \<le> n"
  apply (metis aligned_small_is_0 word_not_le)
  done

lemma replicate_append_list [rule_format]:
  "\<forall>n. set L \<subseteq> {0::word8} \<longrightarrow> (replicate n 0 @ L = replicate (n + length L) 0)"
  apply (rule rev_induct)
   apply clarsimp
  apply (rule allI)
  apply (erule_tac x="n+1" in allE)
  apply clarsimp
  apply (subst append_assoc[symmetric])
  apply clarsimp
  apply (subgoal_tac "\<And>n. (replicate n 0 @ [0]) = (0 # replicate n (0 :: word8))")
   apply clarsimp
  apply (induct_tac na)
   apply clarsimp
  apply clarsimp
  done

lemma heap_update_list_replicate:
  "\<lbrakk> set L = {0}; n' = n + length L \<rbrakk> \<Longrightarrow>  heap_update_list s ((replicate n 0) @ L) H = heap_update_list s (replicate n' 0) H"
  apply (subst replicate_append_list)
   apply clarsimp
  apply clarsimp
  done

lemma heap_update_word32_is_heap_update_list:
  "heap_update p (x :: word32) = heap_update_list (ptr_val p) (to_bytes x a)"
  apply (rule ext)+
  apply (clarsimp simp: heap_update_def)
  apply (clarsimp simp: to_bytes_def typ_info_word)
  done

lemma to_bytes_word32_0:
  "to_bytes (0 :: word32) xs = [0, 0, 0, 0 :: word8]"
  apply (simp add: to_bytes_def typ_info_word word_rsplit_same word_rsplit_0)
  done

lemma globals_list_distinct_subset:
  "\<lbrakk> globals_list_distinct D symtab xs; D' \<subseteq> D \<rbrakk>
    \<Longrightarrow> globals_list_distinct D' symtab xs"
  by (simp add: globals_list_distinct_def disjoint_subset)

lemma memzero_spec:
  "\<forall>s. \<Gamma> \<turnstile> \<lbrace>s. ptr_val \<acute>s \<noteq> 0 \<and> ptr_val \<acute>s \<le> ptr_val \<acute>s + (\<acute>n - 1)
         \<and> (is_aligned (ptr_val \<acute>s) 2) \<and> (is_aligned (\<acute>n) 2)
         \<and> {ptr_val \<acute>s ..+ unat \<acute>n} \<times> {SIndexVal, SIndexTyp 0} \<subseteq> dom_s (hrs_htd \<acute>t_hrs)
         \<and> gs_get_assn cap_get_capSizeBits_'proc \<acute>ghost'state \<in> insert 0 {\<acute>n ..}\<rbrace>
    Call memzero_'proc {t.
     t_hrs_' (globals t) = hrs_mem_update (heap_update_list (ptr_val (s_' s))
                                            (replicate (unat (n_' s)) (ucast (0)))) (t_hrs_' (globals s))}"
  apply (hoare_rule HoarePartial.ProcNoRec1)
  apply (clarsimp simp: whileAnno_def)
  apply (rule_tac I1="{t. (ptr_val (s_' s) \<le> ptr_val (s_' s) + ((n_' s) - 1) \<and> ptr_val (s_' s) \<noteq> 0) \<and>
                             ptr_val (s_' s) + (n_' s - n_' t) = ptr_val (p___ptr_to_unsigned_char_' t) \<and>
                             n_' t \<le> n_' s \<and>
                             (is_aligned (n_' t) 2) \<and>
                             (is_aligned (n_' s) 2) \<and>
                             (is_aligned (ptr_val (s_' t)) 2) \<and>
                             (is_aligned (ptr_val (s_' s)) 2) \<and>
                             (is_aligned (ptr_val (p___ptr_to_unsigned_char_' t)) 2) \<and>
                             {ptr_val (p___ptr_to_unsigned_char_' t) ..+ unat (n_' t)} \<times> {SIndexVal, SIndexTyp 0}
                                 \<subseteq> dom_s (hrs_htd (t_hrs_' (globals t))) \<and>
                             globals t = (globals s)\<lparr> t_hrs_' :=
                             hrs_mem_update (heap_update_list (ptr_val (s_' s))
                                               (replicate (unat (n_' s - n_' t)) 0))
                                                      (t_hrs_' (globals s))\<rparr> }"
            and V1=undefined in subst [OF whileAnno_def])
  apply vcg
    apply (clarsimp simp add: hrs_mem_update_def)

   apply clarsimp
   apply (case_tac s, case_tac p___ptr_to_unsigned_char)

   apply (subgoal_tac "4 \<le> unat na")
    apply (intro conjI)
           apply (simp add: ptr_safe_def s_footprint_def s_footprint_untyped_def
                            typ_uinfo_t_def typ_info_word)
           apply (erule order_trans[rotated])
            apply (auto intro!: intvlI)[1]
          apply (subst c_guard_word32, simp_all)[1]
          apply (clarsimp simp: field_simps)
          apply (metis le_minus' minus_one_helper5 olen_add_eqv diff_self word_le_0_iff word_le_less_eq)
         apply (clarsimp simp: field_simps)
        apply (frule is_aligned_and_not_zero)
         apply clarsimp
        apply (rule word_le_imp_diff_le, auto)[1]
       apply clarsimp
       apply (rule aligned_sub_aligned [where n=2], simp_all add: is_aligned_def word_bits_def)[1]
      apply clarsimp
      apply (rule is_aligned_add, simp_all add: is_aligned_def word_bits_def)[1]
     apply (erule order_trans[rotated])
     apply (clarsimp simp: subset_iff)
     apply (erule subsetD[OF intvl_sub_offset, rotated])
     apply (simp add: unat_sub word_le_nat_alt)
    apply (clarsimp simp: word_bits_def hrs_mem_update_def)
    apply (subst heap_update_word32_is_heap_update_list [where a="[]"])
    apply (subst heap_update_list_append3[symmetric])
     apply clarsimp
    apply (subst to_bytes_word32_0)
    apply (rule heap_update_list_replicate)
     apply clarsimp
    apply (rule_tac s="unat ((n - na) + 4)" in trans)
     apply (simp add: field_simps)
    apply (subst Word.unat_plus_simple[THEN iffD1])
     apply (rule is_aligned_no_overflow''[where n=2, simplified])
      apply (erule(1) aligned_sub_aligned, simp)
     apply (clarsimp simp: field_simps)
     apply (frule_tac x=n in is_aligned_no_overflow'', simp)
     apply simp
    apply simp
   apply (rule dvd_imp_le)
    apply (simp add: is_aligned_def)
   apply (simp add: unat_eq_0[symmetric])
  apply clarsimp
  done

lemma is_aligned_and_2_to_k:
  assumes  mask_2_k: "(n && 2 ^ k - 1) = 0"
  shows "is_aligned (n :: word32) k"
proof (subst is_aligned_mask)
  have "mask k = (2 :: word32) ^ k - 1"
   by (clarsimp simp: mask_def)
  thus "n && mask k = 0" using mask_2_k
   by simp
qed

(* This is currently unused, but hard to prove.
   it might be worth fixing if it breaks, but ask around first. *)
lemma memset_spec:
  "\<forall>s. \<Gamma> \<turnstile> \<lbrace>s. ptr_val \<acute>s \<noteq> 0 \<and> ptr_val \<acute>s \<le> ptr_val \<acute>s + (\<acute>n - 1)
         \<and> {ptr_val \<acute>s ..+ unat \<acute>n} \<times> {SIndexVal, SIndexTyp 0} \<subseteq> dom_s (hrs_htd \<acute>t_hrs)
         \<and> gs_get_assn cap_get_capSizeBits_'proc \<acute>ghost'state \<in> insert 0 {\<acute>n ..}\<rbrace>
    Call memset_'proc
   {t. t_hrs_' (globals t) = hrs_mem_update (heap_update_list (ptr_val (s_' s))
                                            (replicate (unat (n_' s)) (ucast (c_' s)))) (t_hrs_' (globals s))}"
  apply (hoare_rule HoarePartial.ProcNoRec1)
  apply (clarsimp simp: whileAnno_def)
  apply (rule_tac I1="{t. (ptr_val (s_' s) \<le> ptr_val (s_' s) + ((n_' s) - 1) \<and> ptr_val (s_' s) \<noteq> 0) \<and>
                             c_' t = c_' s \<and>
                             ptr_val (s_' s) + (n_' s - n_' t) = ptr_val (p___ptr_to_unsigned_char_' t) \<and>
                             n_' t \<le> n_' s \<and>
                             {ptr_val (p___ptr_to_unsigned_char_' t) ..+ unat (n_' t)} \<times> {SIndexVal, SIndexTyp 0}
                                \<subseteq> dom_s (hrs_htd (t_hrs_' (globals t))) \<and>
                             globals t = (globals s)\<lparr> t_hrs_' :=
                             hrs_mem_update (heap_update_list (ptr_val (s_' s))
                                               (replicate (unat (n_' s - n_' t)) (ucast (c_' t))))
                                                      (t_hrs_' (globals s))\<rparr>}"
            and V1=undefined in subst [OF whileAnno_def])
  apply vcg
    apply (clarsimp simp add: hrs_mem_update_def split: if_split_asm)
    apply (subst (asm) word_mod_2p_is_mask [where n=2, simplified], simp)
    apply (subst (asm) word_mod_2p_is_mask [where n=2, simplified], simp)
    apply (rule conjI)
     apply (rule is_aligned_and_2_to_k, clarsimp simp: mask_def)
    apply (rule is_aligned_and_2_to_k, clarsimp simp: mask_def)
   apply clarsimp
   apply (intro conjI)
        apply (simp add: ptr_safe_def s_footprint_def s_footprint_untyped_def
                         typ_uinfo_t_def typ_info_word)
        apply (erule order_trans[rotated])
        apply (auto simp: intvl_self unat_gt_0 intro!: intvlI)[1]
       apply (simp add: c_guard_word8)
       apply (erule subst)
       apply (subst lt1_neq0 [symmetric])
       apply (rule order_trans)
        apply (subst lt1_neq0, assumption)
       apply (erule word_random)
       apply (rule word_le_minus_mono_right)
         apply (simp add: lt1_neq0)
        apply assumption
       apply (erule order_trans [rotated])
       apply (simp add: lt1_neq0)
      apply (case_tac p___ptr_to_unsigned_char, simp add: CTypesDefs.ptr_add_def unat_minus_one field_simps)
     apply (metis word_must_wrap word_not_simps(1) linear)
    apply (erule order_trans[rotated])
    apply (clarsimp simp: ptr_val_case split: ptr.splits)
    apply (erule subsetD[OF intvl_sub_offset, rotated])
    apply (simp add: unat_sub word_le_nat_alt word_less_nat_alt)
   apply (clarsimp simp: ptr_val_case unat_minus_one hrs_mem_update_def split: ptr.splits)
   apply (subgoal_tac "unat (n - (na - 1)) = Suc (unat (n - na))")
    apply (erule ssubst, subst replicate_Suc_append)
    apply (subst heap_update_list_append)
    apply (simp add: heap_update_word8)
   apply (subst unatSuc [symmetric])
    apply (subst add.commute)
    apply (metis word_neq_0_conv word_sub_plus_one_nonzero)
   apply (simp add: field_simps)
  apply (clarsimp)
  apply (metis diff_0_right word_gt_0)
  done

declare snd_get[simp]

declare snd_gets[simp]

lemma snd_when_aligneError[simp]:
  shows "(snd ((when P (alignError sz)) s)) = P"
  by (simp add: when_def alignError_def fail_def split: if_split)

lemma lift_t_retyp_heap_same:
  fixes p :: "'a :: mem_type ptr"
  assumes gp: "g p"
  shows "lift_t g (hp, ptr_retyp p td) p = Some (from_bytes (heap_list hp (size_of TYPE('a)) (ptr_val p)))"
  apply (simp add: lift_t_def lift_typ_heap_if s_valid_def hrs_htd_def)
  apply (subst ptr_retyp_h_t_valid)
   apply (rule gp)
  apply simp
  apply (subst heap_list_s_heap_list_dom)
  apply (clarsimp simp: s_footprint_intvl)
  apply simp
  done

(* FIXME: Move to LemmaBucket_C. Stopped by: simp rules. *)
lemma lift_t_retyp_heap_same_rep0:
  fixes p :: "'a :: mem_type ptr"
  assumes gp: "g p"
  shows "lift_t g (heap_update_list (ptr_val p) (replicate (size_of TYPE('a)) 0) hp, ptr_retyp p td) p =
  Some (from_bytes (replicate (size_of TYPE('a)) 0))"
  apply (subst lift_t_retyp_heap_same)
   apply (rule gp)
  apply (subst heap_list_update [where v = "replicate (size_of TYPE('a)) 0", simplified])
  apply (rule order_less_imp_le)
  apply simp
  apply simp
  done

(* FIXME: Move to LemmaBucket_C. Stopped by: simp rules. *)
lemma lift_t_retyp_heap_other2:
  fixes p :: "'a :: mem_type ptr" and p' :: "'b :: mem_type ptr"
  assumes orth: "{ptr_val p..+size_of TYPE('a)} \<inter> {ptr_val p'..+size_of TYPE('b)} = {}"
  shows "lift_t g (hp, ptr_retyp p td) p' = lift_t g (hp, td) p'"
  apply (simp add: lift_t_def lift_typ_heap_if s_valid_def hrs_htd_def ptr_retyp_disjoint_iff [OF orth])
  apply (cases "td, g \<Turnstile>\<^sub>t p'")
   apply simp
   apply (simp add: h_t_valid_taut heap_list_s_heap_list heap_list_update_disjoint_same
     ptr_retyp_disjoint_iff orth)
  apply (simp add: h_t_valid_taut heap_list_s_heap_list heap_list_update_disjoint_same
    ptr_retyp_disjoint_iff orth)
  done

lemma h_t_valid_not_empty:
  fixes p :: "'a :: c_type ptr"
  shows "\<lbrakk> d,g \<Turnstile>\<^sub>t p; x \<in> {ptr_val p..+size_of TYPE('a)} \<rbrakk> \<Longrightarrow> snd (d x) \<noteq> Map.empty"
  apply (drule intvlD)
  apply (clarsimp simp: h_t_valid_def size_of_def)
  apply (drule valid_footprintD)
   apply simp
  apply clarsimp
  done

lemma ptr_retyps_out:
  fixes p :: "'a :: mem_type ptr"
  shows "x \<notin> {ptr_val p..+n * size_of TYPE('a)} \<Longrightarrow> ptr_retyps n p td x = td x"
proof (induct n arbitrary: p)
  case 0 thus ?case by simp
next
  case (Suc m)

  have ih: "ptr_retyps m (CTypesDefs.ptr_add p 1) td x = td x"
  proof (rule Suc.hyps)
    from Suc.prems show "x \<notin> {ptr_val (CTypesDefs.ptr_add p 1)..+m * size_of TYPE('a)}"
      apply (rule contrapos_nn)
      apply (erule subsetD [rotated])
      apply (simp add: CTypesDefs.ptr_add_def)
      apply (rule intvl_sub_offset)
      apply (simp add: unat_of_nat)
      done
  qed

  from Suc.prems have "x \<notin> {ptr_val p..+size_of TYPE('a)}"
    apply (rule contrapos_nn)
    apply (erule subsetD [rotated])
    apply (rule intvl_start_le)
    apply simp
    done

  thus ?case
    by (simp add: ptr_retyp_d ih)
qed

lemma image_add_intvl:
  "((+) x) ` {p ..+ n} = {p + x ..+ n}"
  by (auto simp add: intvl_def)

lemma intvl_sum:
  "{p..+ i + j}
    = {p ..+ i} \<union> {(p :: ('a :: len) word) + of_nat i ..+ j}"
  apply (simp add: intvl_def, safe)
    apply clarsimp
    apply (case_tac "k < i")
     apply auto[1]
    apply (drule_tac x="k - i" in spec)
    apply simp
   apply fastforce
  apply (rule_tac x="k + i" in exI)
  apply simp
  done

lemma intvl_Suc_right:
  "{p ..+ Suc n} = {p} \<union> {(p :: ('a :: len) word) + 1 ..+ n}"
  apply (simp add: intvl_sum[where p=p and i=1 and j=n, simplified])
  apply (auto dest: intvl_Suc simp: intvl_self)
  done

lemma htd_update_list_same2:
  "x \<notin> {p ..+ length xs} \<Longrightarrow>
    htd_update_list p xs htd x = htd x"
  by (induct xs arbitrary: p htd, simp_all add: intvl_Suc_right)

lemma ptr_retyps_gen_out:
  fixes p :: "'a :: mem_type ptr"
  shows "x \<notin> {ptr_val p..+n * size_of TYPE('a)} \<Longrightarrow> ptr_retyps_gen n p arr td x = td x"
  apply (simp add: ptr_retyps_gen_def ptr_retyps_out split: if_split)
  apply (clarsimp simp: ptr_arr_retyps_def htd_update_list_same2)
  done

lemma h_t_valid_intvl_htd_contains_uinfo_t:
  "h_t_valid d g (p :: ('a :: c_type) ptr) \<Longrightarrow> x \<in> {ptr_val p ..+ size_of TYPE('a)} \<Longrightarrow>
    (\<exists>n. snd (d x) n \<noteq> None \<and> fst (the (snd (d x) n)) = typ_uinfo_t TYPE ('a))"
  apply (clarsimp simp: h_t_valid_def valid_footprint_def Let_def intvl_def size_of_def)
  apply (drule spec, drule(1) mp)
  apply (cut_tac m=k in typ_slice_t_self[where td="typ_uinfo_t TYPE ('a)"])
  apply (clarsimp simp: in_set_conv_nth)
  apply (drule_tac x=i in map_leD)
   apply simp
  apply fastforce
  done

lemma list_map_override_comono:
  "list_map xs  \<subseteq>\<^sub>m m ++ list_map ys
    \<Longrightarrow> xs \<le> ys \<or> ys \<le> xs"
  apply (simp add: map_le_def list_map_eq map_add_def)
  apply (cases "length xs \<le> length ys")
   apply (simp add: prefix_eq_nth)
  apply (simp split: if_split_asm add: prefix_eq_nth)
  done

lemma list_map_plus_le_not_tag_disj:
  "list_map (typ_slice_t td y) \<subseteq>\<^sub>m m ++ list_map (typ_slice_t td' y')
    \<Longrightarrow> \<not> td \<bottom>\<^sub>t td'"
  apply (drule list_map_override_comono)
  apply (auto dest: typ_slice_sub)
  done

lemma htd_update_list_not_tag_disj:
  "list_map (typ_slice_t td y)
        \<subseteq>\<^sub>m snd (htd_update_list p xs htd x)
    \<Longrightarrow> x \<in> {p ..+ length xs}
    \<Longrightarrow> y < size_td td
    \<Longrightarrow> length xs < addr_card
    \<Longrightarrow> set xs \<subseteq> list_map ` typ_slice_t td' ` {..< size_td td'}
    \<Longrightarrow> \<not> td \<bottom>\<^sub>t td'"
  apply (induct xs arbitrary: p htd)
   apply simp
  apply (clarsimp simp: intvl_Suc_right)
  apply (erule disjE)
   apply clarsimp
   apply (subst(asm) htd_update_list_same2,
     rule intvl_Suc_nmem'[where n="Suc m" for m, simplified])
    apply (simp add: addr_card_def card_word)
   apply (simp add: list_map_plus_le_not_tag_disj)
  apply blast
  done

(* Sigh *)
lemma td_set_offset_ind:
  "\<forall>j. td_set t (Suc j) = (apsnd Suc :: ('a typ_desc \<times> nat) \<Rightarrow> _) ` td_set t j"
  "\<forall>j. td_set_struct ts (Suc j) = (apsnd Suc :: ('a typ_desc \<times> nat) \<Rightarrow> _) ` td_set_struct ts j"
  "\<forall>j. td_set_list xs (Suc j) = (apsnd Suc :: ('a typ_desc \<times> nat) \<Rightarrow> _) ` td_set_list xs j"
  "\<forall>j. td_set_pair x (Suc j) = (apsnd Suc :: ('a typ_desc \<times> nat) \<Rightarrow> _) ` td_set_pair x j"
  apply (induct t and ts and xs and x)
  apply (simp_all add: image_Un)
  done

lemma td_set_offset:
  "(td, i) \<in> td_set td' j \<Longrightarrow> (td, i - j) \<in> td_set td' 0"
  by (induct j arbitrary: i, auto simp: td_set_offset_ind)

lemma typ_le_uinfo_array_tag_n_m:
  "0 < n \<Longrightarrow> td \<le> uinfo_array_tag_n_m TYPE('a :: c_type) n m
    = (td \<le> typ_uinfo_t TYPE('a) \<or> td = uinfo_array_tag_n_m TYPE('a) n m)"
proof -
  have ind: "\<And>xs cs. \<forall>n'. td_set_list (map (\<lambda>i. DTPair (typ_uinfo_t TYPE('a)) (cs i)) xs) n'
    \<subseteq> (fst ` (\<Union>i. td_set (typ_uinfo_t TYPE('a)) i)) \<times> UNIV"
    apply (induct_tac xs)
     apply clarsimp
    apply clarsimp
    apply (fastforce intro: image_eqI[rotated])
    done
  assume "0 < n"
  thus ?thesis
    apply (simp add: uinfo_array_tag_n_m_def typ_tag_le_def upt_conv_Cons)
    apply (auto dest!: ind[rule_format, THEN subsetD], (blast dest: td_set_offset)+)
    done
qed

lemma h_t_array_valid_retyp:
  "0 < n \<Longrightarrow> n * size_of TYPE('a) < addr_card
    \<Longrightarrow> h_t_array_valid (ptr_arr_retyps n p htd) (p :: ('a :: wf_type) ptr) n"
  apply (clarsimp simp: ptr_arr_retyps_def h_t_array_valid_def
                        valid_footprint_def)
  apply (simp add: htd_update_list_index intvlI mult.commute)
  apply (simp add: addr_card_wb unat_of_nat32)
  done

lemma typ_slice_list_array:
  "x < size_td td * n
    \<Longrightarrow> typ_slice_list (map (\<lambda>i. DTPair td (nm i)) [0..<n]) x
        = typ_slice_t td (x mod size_td td)"
proof (induct n arbitrary: x nm)
  case 0 thus ?case by simp
next
  case (Suc n)
  from Suc.prems show ?case
    apply (simp add: upt_conv_Cons map_Suc_upt[symmetric]
                del: upt.simps)
    apply (split if_split, intro conjI impI)
     apply auto[1]
    apply (simp add: o_def)
    apply (subst Suc.hyps)
     apply arith
    apply (metis mod_geq)
    done
qed

lemma h_t_array_valid_field:
  "h_t_array_valid htd (p :: ('a :: wf_type) ptr) n
    \<Longrightarrow> k < n
    \<Longrightarrow> gd (p +\<^sub>p int k)
    \<Longrightarrow> h_t_valid htd gd (p +\<^sub>p int k)"
  apply (clarsimp simp: h_t_array_valid_def h_t_valid_def valid_footprint_def
                        size_of_def[symmetric, where t="TYPE('a)"])
  apply (drule_tac x="k * size_of TYPE('a) + y" in spec)
  apply (drule mp)
   apply (frule_tac k="size_of TYPE('a)" in mult_le_mono1[where j=n, OF Suc_leI])
   apply (simp add: mult.commute)
  apply (clarsimp simp: ptr_add_def add.assoc)
  apply (erule map_le_trans[rotated])
  apply (clarsimp simp: uinfo_array_tag_n_m_def)
  apply (subst typ_slice_list_array)
   apply (frule_tac k="size_of TYPE('a)" in mult_le_mono1[where j=n, OF Suc_leI])
   apply (simp add: mult.commute size_of_def)
  apply (simp add: size_of_def list_map_mono)
  done

lemma h_t_valid_ptr_retyps_gen:
  assumes sz: "nptrs * size_of TYPE('a :: mem_type) < addr_card"
    and gd: "gd p'"
  shows
  "(p' \<in> ((+\<^sub>p) (Ptr p :: 'a ptr) \<circ> int) ` {k. k < nptrs})
    \<Longrightarrow> h_t_valid (ptr_retyps_gen nptrs (Ptr p :: 'a ptr) arr htd) gd p'"
  using gd sz
  apply (cases arr, simp_all add: ptr_retyps_gen_def)
   apply (cases "nptrs = 0")
    apply simp
   apply (cut_tac h_t_array_valid_retyp[where p="Ptr p" and htd=htd, OF _ sz], simp_all)
   apply clarsimp
   apply (drule_tac k=x in h_t_array_valid_field, simp_all)
  apply (induct nptrs arbitrary: p htd)
   apply simp
  apply clarsimp
  apply (case_tac x, simp_all add: ptr_retyp_h_t_valid)
  apply (rule ptr_retyp_disjoint)
   apply (elim meta_allE, erule meta_mp, rule image_eqI[rotated], simp)
   apply (simp add: field_simps)
  apply simp
  apply (cut_tac p=p and z="size_of TYPE('a)"
    and k="Suc nat * size_of TYPE('a)" in init_intvl_disj)
   apply (erule order_le_less_trans[rotated])
   apply (simp del: mult_Suc)
  apply (simp add: field_simps Int_ac)
  apply (erule disjoint_subset[rotated] disjoint_subset2[rotated])
  apply (rule intvl_start_le, simp)
  done

lemma ptr_retyps_gen_not_tag_disj:
  "x \<in> {p ..+ n * size_of TYPE('a :: mem_type)}
    \<Longrightarrow> list_map (typ_slice_t td y)
        \<subseteq>\<^sub>m snd (ptr_retyps_gen n (Ptr p :: 'a ptr) arr htd x)
    \<Longrightarrow> y < size_td td
    \<Longrightarrow> n * size_of TYPE('a) < addr_card
    \<Longrightarrow> 0 < n
    \<Longrightarrow> \<not> td \<bottom>\<^sub>t typ_uinfo_t TYPE('a)"
  apply (simp add: ptr_retyps_gen_def ptr_arr_retyps_def
            split: if_split_asm)
   apply (drule_tac td'="uinfo_array_tag_n_m TYPE('a) n n"
     in htd_update_list_not_tag_disj, simp+)
    apply (clarsimp simp: mult.commute)
   apply (clarsimp simp: tag_disj_def)
   apply (erule disjE)
    apply (metis order_refl typ_le_uinfo_array_tag_n_m)
   apply (erule notE, erule order_trans[rotated])
   apply (simp add: typ_le_uinfo_array_tag_n_m)
  apply clarsimp
  apply (induct n arbitrary: p htd, simp_all)
  apply (case_tac "x \<in> {p ..+ size_of TYPE('a)}")
   apply (simp add: intvl_sum ptr_retyp_def)
   apply (drule_tac td'="typ_uinfo_t TYPE('a)"
     in htd_update_list_not_tag_disj, simp+)
    apply (clarsimp simp add: typ_slices_def size_of_def)
   apply simp
  apply (simp add: intvl_sum)
  apply (case_tac "n = 0")
   apply simp
  apply (simp add: ptr_retyps_out[where n=1, simplified])
  apply blast
  done

lemma ptr_retyps_gen_valid_footprint:
  assumes cleared: "region_is_bytes' p (n * size_of TYPE('a)) htd"
    and distinct: "td \<bottom>\<^sub>t typ_uinfo_t TYPE('a)"
    and not_byte: "td \<noteq> typ_uinfo_t TYPE(word8)"
    and sz: "n * size_of TYPE('a) < addr_card"
  shows
  "valid_footprint (ptr_retyps_gen n (Ptr p :: 'a :: mem_type ptr) arr htd) p' td
    = (valid_footprint htd p' td)"
  apply (cases "n = 0")
   apply (simp add: ptr_retyps_gen_def ptr_arr_retyps_def split: if_split)
  apply (simp add: valid_footprint_def Let_def)
  apply (intro conj_cong refl, rule all_cong)
  apply (case_tac "p' + of_nat y \<in> {p ..+ n * size_of TYPE('a)}")
   apply (simp_all add: ptr_retyps_gen_out)
  apply (rule iffI; clarsimp)
   apply (frule(1) ptr_retyps_gen_not_tag_disj, (simp add: sz)+)
   apply (simp add: distinct)
  apply (cut_tac m=y in typ_slice_t_self[where td=td])
  apply (clarsimp simp: in_set_conv_nth)
  apply (drule_tac x=i in map_leD)
   apply simp
  apply (simp add: cleared[unfolded region_is_bytes'_def] not_byte)
  done

(* FIXME: Move to LemmaBucket_C. Stopped by: simp rules. *)
(* This is currently unused, but might be useful.
   it might be worth fixing if it breaks, but ask around first. *)
lemma dom_lift_t_heap_update:
  "dom (lift_t g (hrs_mem_update v hp)) = dom (lift_t g hp)"
  by (clarsimp simp add: lift_t_def lift_typ_heap_if s_valid_def hrs_htd_def hrs_mem_update_def split_def dom_def
    intro!: Collect_cong split: if_split)

lemma h_t_valid_ptr_retyps_gen_same:
  assumes guard: "\<forall>n' < nptrs. gd (CTypesDefs.ptr_add (Ptr p :: 'a ptr) (of_nat n'))"
  assumes cleared: "region_is_bytes' p (nptrs * size_of TYPE('a :: mem_type)) htd"
  and not_byte: "typ_uinfo_t TYPE('a) \<noteq> typ_uinfo_t TYPE(word8)"
  assumes sz: "nptrs * size_of TYPE('a) < addr_card"
  shows
  "h_t_valid (ptr_retyps_gen nptrs (Ptr p :: 'a ptr) arr htd) gd p'
    = ((p' \<in> ((+\<^sub>p) (Ptr p :: 'a ptr) \<circ> int) ` {k. k < nptrs}) \<or> h_t_valid htd gd p')"
  (is "h_t_valid ?htd' gd p' = (p' \<in> ?S \<or> h_t_valid htd gd p')")
proof (cases "{ptr_val p' ..+ size_of TYPE('a)} \<inter> {p ..+ nptrs * size_of TYPE('a)} = {}")
  case True

  from True have notin:
    "p' \<notin> ?S"
    apply clarsimp
    apply (drule_tac x="p + of_nat (x * size_of TYPE('a))" in eqset_imp_iff)
    apply (simp only: Int_iff empty_iff simp_thms)
    apply (subst(asm) intvlI, simp)
    apply (simp add: intvl_self)
    done

  from True have same: "\<forall>y < size_of TYPE('a). ?htd' (ptr_val p' + of_nat y)
        = htd (ptr_val p' + of_nat y)"
    apply clarsimp
    apply (rule ptr_retyps_gen_out)
    apply simp
    apply (blast intro: intvlI)
    done

  show ?thesis
    by (clarsimp simp: h_t_valid_def valid_footprint_def Let_def
                       notin same size_of_def[symmetric, where t="TYPE('a)"])
next
  case False

  from False have nvalid: "\<not> h_t_valid htd gd p'"
    apply (clarsimp simp: h_t_valid_def valid_footprint_def set_eq_iff
                          Let_def size_of_def[symmetric, where t="TYPE('a)"]
                          intvl_def[where x="(ptr_val p', a)" for a])
    apply (drule cleared[unfolded region_is_bytes'_def, THEN bspec])
    apply (drule spec, drule(1) mp, clarsimp)
    apply (cut_tac m=k in typ_slice_t_self[where td="typ_uinfo_t TYPE ('a)"])
    apply (clarsimp simp: in_set_conv_nth)
    apply (drule_tac x=i in map_leD, simp_all)
    apply (simp add: not_byte)
    done

  have mod_split: "\<And>k. k < nptrs * size_of TYPE('a)
    \<Longrightarrow> \<exists>quot rem. k = quot * size_of TYPE('a) + rem \<and> rem < size_of TYPE('a) \<and> quot < nptrs"
    apply (intro exI conjI, rule div_mult_mod_eq[symmetric])
     apply simp
    apply (simp add: Word_Miscellaneous.td_gal_lt)
    done

  have gd: "\<And>p'. p' \<in> ?S \<Longrightarrow> gd p'"
    using guard by auto

  note htv = h_t_valid_ptr_retyps_gen[where gd=gd, OF sz gd]

  show ?thesis using False
    apply (simp add: nvalid)
    apply (rule iffI, simp_all add: htv)
    apply (clarsimp simp: set_eq_iff intvl_def[where x="(p, a)" for a])
    apply (drule mod_split, clarsimp)
    apply (frule_tac htv[OF imageI, simplified])
     apply fastforce
    apply (rule ccontr)
    apply (drule(1) h_t_valid_neq_disjoint)
      apply simp
     apply (clarsimp simp: field_of_t_refl)
    apply (simp add: set_eq_iff)
    apply (drule spec, drule(1) mp)
    apply (subst(asm) add.assoc[symmetric], subst(asm) intvlI, assumption)
    apply simp
    done
qed

lemma clift_ptr_retyps_gen_memset_same:
  assumes guard: "\<forall>n' < n. c_guard (CTypesDefs.ptr_add (Ptr p :: 'a :: mem_type ptr) (of_nat n'))"
  assumes cleared: "region_is_bytes' p (n * size_of TYPE('a :: mem_type)) (hrs_htd hrs)"
    and not_byte: "typ_uinfo_t TYPE('a :: mem_type) \<noteq> typ_uinfo_t TYPE(word8)"
  and nb: "nb = n * size_of TYPE ('a)"
  and sz: "n * size_of TYPE('a) < 2 ^ word_bits"
  shows "(clift (hrs_htd_update (ptr_retyps_gen n (Ptr p :: 'a :: mem_type ptr) arr)
              (hrs_mem_update (heap_update_list p (replicate nb 0))
               hrs)) :: 'a :: mem_type typ_heap)
         = (\<lambda>y. if y \<in> (CTypesDefs.ptr_add (Ptr p :: 'a :: mem_type ptr) o of_nat) ` {k. k < n}
                then Some (from_bytes (replicate (size_of TYPE('a  :: mem_type)) 0)) else clift hrs y)"
  using sz
  apply (simp add: nb liftt_if[folded hrs_mem_def hrs_htd_def]
                   hrs_htd_update hrs_mem_update
                   h_t_valid_ptr_retyps_gen_same[OF guard cleared not_byte]
                   addr_card_wb)
  apply (rule ext, rename_tac p')
  apply (case_tac "p' \<in> ((+\<^sub>p) (Ptr p) \<circ> int) ` {k. k < n}")
   apply (clarsimp simp: h_val_def)
   apply (simp only: Word.Abs_fnat_hom_mult hrs_mem_update)
   apply (frule_tac k="size_of TYPE('a)" in mult_le_mono1[where j=n, OF Suc_leI])
   apply (subst heap_list_update_list)
    apply (simp add: addr_card_def card_word word_bits_def)
   apply simp
  apply (clarsimp split: if_split)
  apply (simp add: h_val_def)
  apply (subst heap_list_update_disjoint_same, simp_all)
  apply (simp add: region_is_bytes_disjoint[OF cleared not_byte])
  done

lemma clift_ptr_retyps_gen_prev_memset_same:
  assumes guard: "\<forall>n' < n. c_guard (CTypesDefs.ptr_add (Ptr p :: 'a :: mem_type ptr) (of_nat n'))"
  assumes cleared: "region_is_bytes' p (n * size_of TYPE('a :: mem_type)) (hrs_htd hrs)"
    and not_byte: "typ_uinfo_t TYPE('a :: mem_type) \<noteq> typ_uinfo_t TYPE(word8)"
  and nb: "nb = n * size_of TYPE ('a)"
  and sz: "n * size_of TYPE('a) < 2 ^ word_bits"
  and rep0:  "heap_list (hrs_mem hrs) nb p = replicate nb 0"
  shows "(clift (hrs_htd_update (ptr_retyps_gen n (Ptr p :: 'a :: mem_type ptr) arr) hrs) :: 'a :: mem_type typ_heap)
         = (\<lambda>y. if y \<in> (CTypesDefs.ptr_add (Ptr p :: 'a :: mem_type ptr) o of_nat) ` {k. k < n}
                then Some (from_bytes (replicate (size_of TYPE('a  :: mem_type)) 0)) else clift hrs y)"
  using rep0
  apply (subst clift_ptr_retyps_gen_memset_same[symmetric, OF guard cleared not_byte nb sz])
  apply (rule arg_cong[where f=clift])
  apply (rule_tac f="hrs_htd_update f" for f in arg_cong)
  apply (cases hrs, simp add: hrs_mem_update_def)
  apply (simp add: heap_update_list_id hrs_mem_def)
  done

lemma clift_ptr_retyps_gen_other:
  assumes cleared: "region_is_bytes' (ptr_val p) (nptrs * size_of TYPE('a :: mem_type)) (hrs_htd hrs)"
  and sz: "nptrs * size_of TYPE('a) < 2 ^ word_bits"
  and other: "typ_uinfo_t TYPE('b)  \<bottom>\<^sub>t typ_uinfo_t TYPE('a)"
  and not_byte: "typ_uinfo_t TYPE('b :: mem_type) \<noteq> typ_uinfo_t TYPE(word8)"
  shows "(clift (hrs_htd_update (ptr_retyps_gen nptrs (p :: 'a ptr) arr) hrs) :: 'b :: mem_type typ_heap)
         = clift hrs"
  using sz cleared
  apply (cases p)
  apply (simp add: liftt_if[folded hrs_mem_def hrs_htd_def]
                   h_t_valid_def hrs_htd_update
                   ptr_retyps_gen_valid_footprint[simplified addr_card_wb, OF _ other not_byte sz])
  done

lemma clift_heap_list_update_no_heap_other:
  assumes cleared: "region_is_bytes' p (length xs) (hrs_htd hrs)"
  and not_byte: "typ_uinfo_t TYPE('a :: c_type) \<noteq> typ_uinfo_t TYPE(word8)"
  shows "clift (hrs_mem_update (heap_update_list p xs) hrs) = (clift hrs :: 'a typ_heap)"
  apply (clarsimp simp: liftt_if[folded hrs_mem_def hrs_htd_def] hrs_mem_update
                        fun_eq_iff h_val_def split: if_split)
  apply (subst heap_list_update_disjoint_same, simp_all)
  apply (clarsimp simp: set_eq_iff h_t_valid_def valid_footprint_def Let_def
                 dest!: intvlD[where n="size_of TYPE('a)"])
  apply (drule_tac x="of_nat k" in spec, clarsimp simp: size_of_def)
  apply (cut_tac m=k in typ_slice_t_self[where td="typ_uinfo_t TYPE('a)"])
  apply (clarsimp simp: in_set_conv_nth)
  apply (drule_tac x=i in map_leD, simp)
  apply (simp add: cleared[unfolded region_is_bytes'_def] not_byte size_of_def)
  done

lemma add_is_injective_ring:
  "inj ((+) (x :: 'a :: ring))"
  by (rule inj_onI, clarsimp)

lemma ptr_retyp_to_array:
  "ptr_retyps_gen 1 (p :: (('a :: wf_type)['b :: finite]) ptr) False
    = ptr_retyps_gen CARD('b) (ptr_coerce p :: 'a ptr) True"
  by (intro ext, simp add: ptr_retyps_gen_def ptr_arr_retyps_to_retyp)

lemma projectKO_opt_retyp_other:
  assumes cover: "range_cover ptr sz (objBitsKO ko) n"
  assumes pal: "pspace_aligned' \<sigma>"
  assumes pno: "pspace_no_overlap' ptr sz \<sigma>"
  and  ko_def: "ko \<equiv> x"
  and  pko: "\<forall>v. (projectKO_opt x :: ('a :: pre_storable) option) \<noteq> Some v"
  shows "projectKO_opt \<circ>\<^sub>m
    (\<lambda>x. if x \<in> set (new_cap_addrs n ptr ko) then Some ko else ksPSpace \<sigma> x)
  = (projectKO_opt \<circ>\<^sub>m (ksPSpace \<sigma>) :: word32 \<Rightarrow> ('a :: pre_storable) option)" (is "?LHS = ?RHS")
proof (rule ext)
  fix x
  show "?LHS x = ?RHS x"
  proof (cases "x \<in> set (new_cap_addrs n ptr ko)")
    case False
      thus ?thesis by (simp add: map_comp_def)
  next
    case True
      hence "ksPSpace \<sigma> x = None"
        apply -
        apply (cut_tac no_overlap_new_cap_addrs_disjoint [OF cover pal pno])
          apply (rule ccontr)
          apply (clarsimp,drule domI[where a = x])
          apply blast
        done
      thus ?thesis using True pko ko_def by simp
  qed
qed

lemma pspace_aligned_to_C:
  fixes v :: "'a :: pre_storable"
  assumes pal: "pspace_aligned' s"
  and    cmap: "cmap_relation (projectKO_opt \<circ>\<^sub>m (ksPSpace s) :: word32 \<rightharpoonup> 'a)
                              (cslift x :: 'b :: mem_type typ_heap) Ptr rel"
  and     pko: "projectKO_opt ko = Some v"
  and   pkorl: "\<And>ko' (v' :: 'a).  projectKO_opt ko' = Some v' \<Longrightarrow> objBitsKO ko = objBitsKO ko'"
  shows  "\<forall>x\<in>dom (cslift x :: 'b :: mem_type typ_heap). is_aligned (ptr_val x) (objBitsKO ko)"
  (is "\<forall>x\<in>dom ?CS. is_aligned (ptr_val x) (objBitsKO ko)")
proof
  fix z
  assume "z \<in> dom ?CS"
  hence "z \<in> Ptr ` dom (projectKO_opt \<circ>\<^sub>m (ksPSpace s) :: word32 \<rightharpoonup> 'a)" using cmap
    by (simp add: cmap_relation_def)
  hence pvz: "ptr_val z \<in> dom (projectKO_opt \<circ>\<^sub>m (ksPSpace s) :: word32 \<rightharpoonup> 'a)"
    by clarsimp
  then obtain v' :: 'a where "projectKO_opt (the (ksPSpace s (ptr_val z))) = Some v'"
    and pvz: "ptr_val z \<in> dom (ksPSpace s)"
    apply -
    apply (frule map_comp_subset_domD)
    apply (clarsimp simp: dom_def)
    done

  thus "is_aligned (ptr_val z) (objBitsKO ko)" using pal
    unfolding pspace_aligned'_def
    apply -
    apply (drule (1) bspec)
    apply (simp add: pkorl)
    done
qed

lemma ptr_add_to_new_cap_addrs:
  assumes size_of_m: "size_of TYPE('a :: mem_type) = 2 ^ objBitsKO ko"
  shows "(CTypesDefs.ptr_add (Ptr ptr :: 'a :: mem_type ptr) \<circ> of_nat) ` {k. k < n}
   = Ptr ` set (new_cap_addrs n ptr ko)"
  unfolding new_cap_addrs_def
  apply (simp add: comp_def image_image shiftl_t2n size_of_m field_simps)
  apply (clarsimp simp: atLeastLessThan_def lessThan_def)
  done

lemma cmap_relation_retype:
  assumes cm: "cmap_relation mp mp' Ptr rel"
  and   rel: "rel (makeObject :: 'a :: pspace_storable) ko'"
  shows "cmap_relation
        (\<lambda>x. if x \<in> addrs then Some (makeObject :: 'a :: pspace_storable) else mp x)
        (\<lambda>y. if y \<in> Ptr ` addrs then Some ko' else mp' y)
        Ptr rel"
  using cm rel
  apply -
  apply (rule cmap_relationI)
   apply (simp add: dom_if cmap_relation_def image_Un)
  apply (case_tac "x \<in> addrs")
   apply simp
  apply simp
  apply (subst (asm) if_not_P)
   apply clarsimp
  apply (erule (2) cmap_relation_relI)
  done

lemma update_ti_t_word32_0s:
  "update_ti_t (typ_info_t TYPE(word32)) [0,0,0,0] X = 0"
  "word_rcat [0, 0, 0, (0 :: word8)] = (0 :: word32)"
  by (simp_all add: typ_info_word word_rcat_def bin_rcat_def)

lemma is_aligned_ptr_aligned:
  fixes p :: "'a :: c_type ptr"
  assumes al: "is_aligned (ptr_val p) n"
  and  alignof: "align_of TYPE('a) = 2 ^ n"
  shows "ptr_aligned p"
  using al unfolding is_aligned_def ptr_aligned_def
  by (simp add: alignof)

lemma is_aligned_c_guard:
  "is_aligned (ptr_val p) n
    \<Longrightarrow> ptr_val p \<noteq> 0
    \<Longrightarrow> align_of TYPE('a) = 2 ^ m
    \<Longrightarrow> size_of TYPE('a) \<le> 2 ^ n
    \<Longrightarrow> m \<le> n
    \<Longrightarrow> c_guard (p :: ('a :: c_type) ptr)"
  apply (clarsimp simp: c_guard_def c_null_guard_def)
  apply (rule conjI)
   apply (rule is_aligned_ptr_aligned, erule(1) is_aligned_weaken, simp)
  apply (erule is_aligned_get_word_bits, simp_all)
  apply (rule intvl_nowrap[where x=0, simplified], simp)
  apply (erule is_aligned_no_wrap_le, simp+)
  done

lemma retype_guard_helper:
  assumes cover: "range_cover p sz (objBitsKO ko) n"
  and ptr0: "p \<noteq> 0"
  and szo: "size_of TYPE('a :: c_type) = 2 ^ objBitsKO ko"
  and lt2: "m \<le> objBitsKO ko"
  and ala: "align_of TYPE('a :: c_type) = 2 ^ m"
  shows "\<forall>b < n. c_guard (CTypesDefs.ptr_add (Ptr p :: 'a ptr) (of_nat b))"
proof (rule allI, rule impI)
  fix b :: nat
  assume nv: "b < n"
  let ?p = "(Ptr p :: 'a ptr)"

  have "of_nat b * of_nat (size_of TYPE('a)) = (of_nat (b * 2 ^ objBitsKO ko) :: word32)"
    by (simp add: szo)

  also have "\<dots> < (2 :: word32) ^ sz" using nv cover
    apply simp
    apply (rule word_less_power_trans_ofnat)
      apply (erule less_le_trans)
      apply (erule range_cover.range_cover_n_le(2))
    apply (erule range_cover.sz)+
    done

  finally have ofn: "of_nat b * of_nat (size_of TYPE('a)) < (2 :: word32) ^ sz" .

  have le: "p \<le> p + of_nat b * 2 ^ objBitsKO ko"
    using ofn szo nv
    apply -
    apply (cases b,clarsimp+)
    apply (cut_tac n = nat in range_cover_ptr_le)
     apply (rule range_cover_le[OF cover])
      apply simp
     apply (simp add:ptr0)
    apply (simp add:shiftl_t2n field_simps)
    done

  show "c_guard (CTypesDefs.ptr_add ?p (of_nat b))"
    apply (rule is_aligned_c_guard[OF _ _ ala _ lt2])
      apply (simp add: szo)
      apply (rule is_aligned_add)
       apply (rule range_cover.aligned, rule cover)
      apply (rule is_aligned_mult_triv2)
     apply (simp add: szo neq_0_no_wrap[OF le ptr0])
    apply (simp add: szo)
    done
qed

(* When we are retyping, CTEs in the system do not change,
 * unless we happen to be retyping into a CNode or a TCB,
 * in which case new CTEs only pop up in the new object. *)
lemma retype_ctes_helper:
  assumes pal: "pspace_aligned' s"
  and    pdst: "pspace_distinct' s"
  and     pno: "pspace_no_overlap' ptr sz s"
  and      al: "is_aligned ptr (objBitsKO ko)"
  and      sz: "objBitsKO ko \<le> sz"
  and     szb: "sz < word_bits"
  and     mko: "makeObjectKO dev tp = Some ko"
  and      rc: "range_cover ptr sz (objBitsKO ko) n"
  shows  "map_to_ctes (\<lambda>xa. if xa \<in> set (new_cap_addrs n ptr ko) then Some ko else ksPSpace s xa) =
   (\<lambda>x. if tp = Inr (APIObjectType ArchTypes_H.apiobject_type.CapTableObject) \<and> x \<in> set (new_cap_addrs n ptr ko) \<or>
           tp = Inr (APIObjectType ArchTypes_H.apiobject_type.TCBObject) \<and>
           x && ~~ mask tcbBlockSizeBits \<in> set (new_cap_addrs n ptr ko) \<and> x && mask tcbBlockSizeBits \<in> dom tcb_cte_cases
        then Some (CTE capability.NullCap nullMDBNode) else ctes_of s x)"
  using mko pal pdst
proof (rule ctes_of_retype)
  show "pspace_aligned' (s\<lparr>ksPSpace := \<lambda>xa. if xa \<in> set (new_cap_addrs n ptr ko) then Some ko else ksPSpace s xa\<rparr>)"
    using pal pdst pno szb al sz rc
    apply -
    apply (rule retype_aligned_distinct'', simp_all)
    done

  show "pspace_distinct' (s\<lparr>ksPSpace := \<lambda>xa. if xa \<in> set (new_cap_addrs n ptr ko) then Some ko else ksPSpace s xa\<rparr>)"
    using pal pdst pno szb al sz rc
    apply -
    apply (rule retype_aligned_distinct'', simp_all)
    done

  show "\<forall>x\<in>set (new_cap_addrs n ptr ko). is_aligned x (objBitsKO ko)"
    using al szb
    apply -
    apply (rule new_cap_addrs_aligned, simp_all)
    done

  show "\<forall>x\<in>set (new_cap_addrs n ptr ko). ksPSpace s x = None"
    using al szb pno pal rc sz
    apply -
    apply (drule(1) pspace_no_overlap_disjoint')
    apply (frule new_cap_addrs_subset)
    apply (clarsimp simp: Word_Lib.ptr_add_def field_simps)
    apply fastforce
    done
qed

lemma ptr_retyps_htd_safe:
  "\<lbrakk> htd_safe D htd;
    {ptr_val ptr ..+ n * size_of TYPE('a :: mem_type)}
        \<subseteq> D \<rbrakk>
   \<Longrightarrow> htd_safe D (ptr_retyps_gen n (ptr :: 'a ptr) arr htd)"
  apply (clarsimp simp: htd_safe_def)
  apply (case_tac "a \<in> {ptr_val ptr..+n * size_of TYPE('a)}")
   apply blast
  apply (case_tac "(a, b) \<in> dom_s htd")
   apply blast
  apply (clarsimp simp: dom_s_def ptr_retyps_gen_out)
  done

lemma ptr_retyps_htd_safe_neg:
  "\<lbrakk> htd_safe (- D) htd;
    {ptr_val ptr ..+ n * size_of TYPE('a :: mem_type)}
        \<inter> D = {} \<rbrakk>
   \<Longrightarrow> htd_safe (- D) (ptr_retyps_gen n (ptr :: 'a ptr) arr htd)"
  using ptr_retyps_htd_safe by blast

lemma region_is_bytes_subset:
  "region_is_bytes' ptr sz htd
    \<Longrightarrow> {ptr' ..+ sz'} \<subseteq> {ptr ..+ sz}
    \<Longrightarrow> region_is_bytes' ptr' sz' htd"
  by (auto simp: region_is_bytes'_def)

lemma (in range_cover) strong_times_32:
  "len_of TYPE('a) = len_of TYPE(32) \<Longrightarrow> n * 2 ^ sbit < 2 ^ word_bits"
  apply (simp add: nat_mult_power_less_eq)
  apply (rule order_less_le_trans, rule string)
  apply (simp add: word_bits_def)
  done

(* Helper for use in the many proofs below. *)
lemma cslift_ptr_retyp_other_inst:
  assumes   bytes: "region_is_bytes' p (n * (2 ^ bits)) (hrs_htd hp)"
  and       cover: "range_cover p sz bits n"
  and          sz: "region_sz = n * size_of TYPE('a :: mem_type)"
  and         sz2: "size_of TYPE('a :: mem_type) = 2 ^ bits"
  and       tdisj: "typ_uinfo_t TYPE('b) \<bottom>\<^sub>t typ_uinfo_t TYPE('a)"
  and    not_byte: "typ_uinfo_t TYPE('b :: mem_type) \<noteq> typ_uinfo_t TYPE(word8)"
  shows "(clift (hrs_htd_update (ptr_retyps_gen n (Ptr p :: 'a :: mem_type ptr) arr)
               hp) :: 'b :: mem_type typ_heap)
         = clift hp"
  using bytes
  apply (subst clift_ptr_retyps_gen_other[OF _ _ tdisj not_byte], simp_all)
   apply (simp add: sz2)
  apply (simp add: sz2 range_cover.strong_times_32[OF cover])
  done

(* Helper for use in the many proofs below. *)
lemma cslift_ptr_retyp_memset_other_inst:
  assumes   bytes: "region_is_bytes p (n * (2 ^ bits)) x"
  and       cover: "range_cover p sz bits n"
  and          sz: "region_sz = n * size_of TYPE('a :: mem_type)"
  and         sz2: "size_of TYPE('a :: mem_type) = 2 ^ bits"
  and       tdisj: "typ_uinfo_t TYPE('b) \<bottom>\<^sub>t typ_uinfo_t TYPE('a)"
  and    not_byte: "typ_uinfo_t TYPE('b :: mem_type) \<noteq> typ_uinfo_t TYPE(word8)"
  shows "(clift (hrs_htd_update (ptr_retyps_gen n (Ptr p :: 'a :: mem_type ptr) arr)
              (hrs_mem_update (heap_update_list p (replicate (region_sz) 0))
               (t_hrs_' (globals x)))) :: 'b :: mem_type typ_heap)
         = cslift x"
  using bytes
  apply (subst cslift_ptr_retyp_other_inst[OF _ cover sz sz2 tdisj not_byte])
   apply simp
  apply (rule clift_heap_list_update_no_heap_other[OF _ not_byte])
  apply (simp add: hrs_htd_def sz sz2)
  done

lemma ptr_retyps_one:
  "ptr_retyps (Suc 0) = ptr_retyp"
  apply (rule ext)+
  apply simp
  done

lemma in_set_list_map:
  "x \<in> set xs \<Longrightarrow> \<exists>n. [n \<mapsto> x] \<subseteq>\<^sub>m list_map xs"
  apply (clarsimp simp: in_set_conv_nth)
  apply (rule_tac x=i in exI)
  apply (simp add: map_le_def)
  done

lemma h_t_valid_eq_array_valid:
  "h_t_valid htd gd (p :: (('a :: wf_type)['b :: finite]) ptr)
    = (gd p \<and> h_t_array_valid htd (ptr_coerce p :: 'a ptr) CARD('b))"
  by (auto simp: h_t_array_valid_def h_t_valid_def
                 typ_uinfo_array_tag_n_m_eq)

lemma h_t_array_valid_ptr_retyps_gen:
  assumes sz2: "size_of TYPE('a :: mem_type) = sz"
  assumes bytes: "region_is_bytes' (ptr_val p) (n * sz) htd"
  shows "h_t_array_valid htd p' n'
    \<Longrightarrow> h_t_array_valid (ptr_retyps_gen n (p :: 'a :: mem_type ptr) arr htd) p' n'"
  apply (clarsimp simp: h_t_array_valid_def valid_footprint_def)
  apply (drule spec, drule(1) mp, clarsimp)
  apply (case_tac "ptr_val p' + of_nat y \<in> {ptr_val p ..+ n * size_of TYPE('a)}")
   apply (cut_tac s="uinfo_array_tag_n_m TYPE('b) n' n'" and n=y in ladder_set_self)
   apply (clarsimp dest!: in_set_list_map)
   apply (drule(1) map_le_trans)
   apply (simp add: map_le_def)
   apply (subst(asm) bytes[unfolded region_is_bytes'_def, rule_format, symmetric])
     apply (simp add: sz2)
    apply (simp add: uinfo_array_tag_n_m_def typ_uinfo_t_def typ_info_word)
   apply simp
  apply (simp add: ptr_retyps_gen_out)
  done

lemma cvariable_array_ptr_retyps:
  assumes sz2: "size_of TYPE('a :: mem_type) = sz"
  assumes bytes: "region_is_bytes' (ptr_val p) (n * sz) htd"
  shows "cvariable_array_map_relation m ns ptrfun htd
    \<Longrightarrow> cvariable_array_map_relation m ns (ptrfun :: _ \<Rightarrow> ('b :: mem_type) ptr)
            (ptr_retyps_gen n (p :: 'a :: mem_type ptr) arr htd)"
  by (clarsimp simp: cvariable_array_map_relation_def
                     h_t_array_valid_ptr_retyps_gen[OF sz2 bytes])

lemma cvariable_array_ptr_upd:
  assumes at: "h_t_array_valid htd (ptrfun x) (ns y)"
  shows "cvariable_array_map_relation m ns ptrfun htd
    \<Longrightarrow> cvariable_array_map_relation (m(x \<mapsto> y))
        ns (ptrfun :: _ \<Rightarrow> ('b :: mem_type) ptr) htd"
  by (clarsimp simp: cvariable_array_map_relation_def at
              split: if_split)

lemma clift_eq_h_t_valid_eq:
  "clift hp = (clift hp' :: ('a :: c_type) ptr \<Rightarrow> _)
    \<Longrightarrow> (h_t_valid (hrs_htd hp) c_guard :: 'a ptr \<Rightarrow> _)
        = h_t_valid (hrs_htd hp') c_guard"
  by (rule ext, simp add: h_t_valid_clift_Some_iff)

lemma region_actually_is_bytes_retyp_disjoint:
  "{ptr ..+ sz} \<inter> {ptr_val (p :: 'a ptr)..+n * size_of TYPE('a :: mem_type)} = {}
    \<Longrightarrow> region_actually_is_bytes' ptr sz htd
    \<Longrightarrow> region_actually_is_bytes' ptr sz (ptr_retyps_gen n p arr htd)"
  apply (clarsimp simp: region_actually_is_bytes'_def del: impI)
  apply (subst ptr_retyps_gen_out)
   apply blast
  apply simp
  done

lemma intvl_plus_unat_eq:
  "p \<le> p + x - 1 \<Longrightarrow> x \<noteq> 0
    \<Longrightarrow> {p ..+ unat x} = {p .. p + x - 1}"
  apply (subst upto_intvl_eq', simp_all add: unat_eq_0 field_simps)
  apply (rule order_less_imp_le, simp)
  done

lemma zero_ranges_ptr_retyps:
  "zero_ranges_are_zero (gsUntypedZeroRanges s) hrs
    \<Longrightarrow> caps_overlap_reserved' {ptr_val (p :: 'a ptr) ..+ n * size_of TYPE ('a :: mem_type)} s
    \<Longrightarrow> untyped_ranges_zero' s
    \<Longrightarrow> valid_objs' s
    \<Longrightarrow> zero_ranges_are_zero (gsUntypedZeroRanges s)
       (hrs_htd_update (ptr_retyps_gen n p arr) hrs)"
  apply (clarsimp simp: zero_ranges_are_zero_def untyped_ranges_zero_inv_def
                        hrs_htd_update)
  apply (drule(1) bspec, clarsimp)
  apply (rule region_actually_is_bytes_retyp_disjoint, simp_all)
  apply (clarsimp simp: map_comp_Some_iff cteCaps_of_def
                 elim!: ranE)
  apply (frule(1) ctes_of_valid')
  apply (simp add: caps_overlap_reserved'_def,
      drule bspec, erule ranI)
  apply (frule(1) untypedZeroRange_to_usableCapRange)
  apply (clarsimp simp: isCap_simps untypedZeroRange_def
                        getFreeRef_def max_free_index_def
                 split: if_split_asm)
  apply (erule disjoint_subset[rotated])
  apply (subst intvl_plus_unat_eq)
    apply clarsimp
   apply clarsimp
   apply (clarsimp simp: word_unat.Rep_inject[symmetric]
                         valid_cap_simps' capAligned_def
                         unat_of_nat
               simp del: word_unat.Rep_inject)
  apply clarsimp
  done

abbreviation
  "ret_zero ptr sz
    \<equiv> valid_objs' and untyped_ranges_zero' and caps_overlap_reserved' {ptr ..+ sz}"

lemma createObjects_ccorres_ep:
  defines "ko \<equiv> (KOEndpoint (makeObject :: endpoint))"
  shows "\<forall>\<sigma> x. (\<sigma>, x) \<in> rf_sr
  \<and> ptr \<noteq> 0
  \<and> pspace_aligned' \<sigma> \<and> pspace_distinct' \<sigma>
  \<and> pspace_no_overlap' ptr sz \<sigma>
  \<and> ret_zero ptr (n * (2 ^ objBitsKO ko)) \<sigma>
  \<and> region_is_zero_bytes ptr (n * (2 ^ objBitsKO ko)) x
  \<and> range_cover ptr sz (objBitsKO ko) n
  \<and> {ptr ..+ n * (2 ^ objBitsKO ko)} \<inter> kernel_data_refs = {}
  \<longrightarrow>
  (\<sigma>\<lparr>ksPSpace := foldr (\<lambda>addr. data_map_insert addr ko) (new_cap_addrs n ptr ko) (ksPSpace \<sigma>)\<rparr>,
   x\<lparr>globals := globals x
                 \<lparr>t_hrs_' := hrs_htd_update (ptr_retyps_gen n (Ptr ptr :: endpoint_C ptr) False)
                   (t_hrs_' (globals x))\<rparr>\<rparr>) \<in> rf_sr"
  (is "\<forall>\<sigma> x. ?P \<sigma> x \<longrightarrow>
    (\<sigma>\<lparr>ksPSpace := ?ks \<sigma>\<rparr>, x\<lparr>globals := globals x\<lparr>t_hrs_' := ?ks' x\<rparr>\<rparr>) \<in> rf_sr")
proof (intro impI allI)
  fix \<sigma> x
  let ?thesis = "(\<sigma>\<lparr>ksPSpace := ?ks \<sigma>\<rparr>, x\<lparr>globals := globals x\<lparr>t_hrs_' := ?ks' x\<rparr>\<rparr>) \<in> rf_sr"
  let ?ks = "?ks \<sigma>"
  let ?ks' = "?ks' x"
  let ?ptr = "Ptr ptr :: endpoint_C ptr"

  assume "?P \<sigma> x"
  hence rf: "(\<sigma>, x) \<in> rf_sr"
    and cover: "range_cover ptr sz (objBitsKO ko) n"
    and al: "is_aligned ptr (objBitsKO ko)" and ptr0: "ptr \<noteq> 0"
    and sz: "objBitsKO ko \<le> sz"
    and szb: "sz < word_bits"
    and pal: "pspace_aligned' \<sigma>" and pdst: "pspace_distinct' \<sigma>"
    and pno: "pspace_no_overlap' ptr sz \<sigma>"
    and rzo: "ret_zero ptr (n * (2 ^ objBitsKO ko)) \<sigma>"
    and empty: "region_is_bytes ptr (n * (2 ^ objBitsKO ko)) x"
    and zero: "heap_list_is_zero (hrs_mem (t_hrs_' (globals x))) ptr (n * (2 ^ objBitsKO ko))"
    and rc: "range_cover ptr sz (objBitsKO ko) n"
    and kdr: "{ptr..+n * (2 ^ objBitsKO ko)} \<inter> kernel_data_refs = {}"
    by (clarsimp simp:range_cover_def[where 'a=32, folded word_bits_def])+

  (* obj specific *)
  have mko: "\<And>dev. makeObjectKO dev (Inr (APIObjectType ArchTypes_H.apiobject_type.EndpointObject)) = Some ko"
    by (simp add: ko_def makeObjectKO_def)

  have relrl:
    "cendpoint_relation (cslift x) makeObject (from_bytes (replicate (size_of TYPE(endpoint_C)) 0))"
    unfolding cendpoint_relation_def
    apply (simp add: Let_def makeObject_endpoint size_of_def endpoint_lift_def)
    apply (simp add: from_bytes_def)
    apply (simp add: typ_info_simps endpoint_C_tag_def endpoint_lift_def
      size_td_lt_final_pad size_td_lt_ti_typ_pad_combine Let_def size_of_def)
    apply (simp add: final_pad_def Let_def size_td_lt_ti_typ_pad_combine Let_def
      size_of_def padup_def align_td_array' size_td_array update_ti_adjust_ti
      ti_typ_pad_combine_def Let_def ti_typ_combine_def empty_typ_info_def)
    apply (simp add: typ_info_array array_tag_def eval_nat_numeral)
    apply (simp add: array_tag_n_eq)
    apply (simp add: final_pad_def Let_def size_td_lt_ti_typ_pad_combine
      size_of_def padup_def align_td_array' size_td_array update_ti_adjust_ti
      ti_typ_pad_combine_def ti_typ_combine_def empty_typ_info_def)
    apply (simp add: EPState_Idle_def update_ti_t_word32_0s)
    done

  (* /obj specific *)

  (* s/obj/obj'/ *)
  have szo: "size_of TYPE(endpoint_C) = 2 ^ objBitsKO ko"
    by (simp add: size_of_def objBits_simps' ko_def)
  have szo': "n * (2 ^ objBitsKO ko) = n * size_of TYPE(endpoint_C)"
    by (metis szo)

  note rl' = cslift_ptr_retyp_other_inst[OF empty cover[simplified] szo' szo]

  note rl = projectKO_opt_retyp_other [OF rc pal pno ko_def]
  note cterl = retype_ctes_helper [OF pal pdst pno al sz szb mko rc, simplified]
  note ht_rl = clift_eq_h_t_valid_eq[OF rl', OF tag_disj_via_td_name, simplified]

 have guard:
    "\<forall>b < n. c_guard (CTypesDefs.ptr_add ?ptr (of_nat b))"
    apply (rule retype_guard_helper [where m = 2, OF cover ptr0 szo])
    apply (simp add: ko_def objBits_simps')
    apply (simp add: align_of_def)
    done

  from rf have "cpspace_relation (ksPSpace \<sigma>) (underlying_memory (ksMachineState \<sigma>)) (t_hrs_' (globals x))"
    unfolding rf_sr_def cstate_relation_def by (simp add: Let_def)
  hence "cpspace_relation ?ks  (underlying_memory (ksMachineState \<sigma>)) ?ks'"
    unfolding cpspace_relation_def
    apply -
    apply (clarsimp simp: rl' cterl tag_disj_via_td_name foldr_upd_app_if [folded data_map_insert_def]
      heap_to_user_data_def cte_C_size heap_to_device_data_def)
    apply (subst clift_ptr_retyps_gen_prev_memset_same[OF guard _ _ szo' _ zero],
      simp_all only: szo empty, simp_all)
     apply (rule range_cover.strong_times_32[OF cover refl])
    apply (simp add: ptr_add_to_new_cap_addrs [OF szo] ht_rl)
    apply (simp add: rl projectKO_opt_retyp_same projectKOs)
    apply (simp add: ko_def projectKO_opt_retyp_same projectKOs cong: if_cong)
    apply (erule cmap_relation_retype)
    apply (rule relrl[simplified szo ko_def])
    done

  thus ?thesis using rf empty kdr rzo
  apply (simp add: rf_sr_def cstate_relation_def Let_def rl'
                   tag_disj_via_td_name)
  apply (simp add: carch_state_relation_def cmachine_state_relation_def)
  apply (simp add: rl' cterl tag_disj_via_td_name h_t_valid_clift_Some_iff)
  apply (clarsimp simp: hrs_htd_update ptr_retyps_htd_safe_neg szo
                        kernel_data_refs_domain_eq_rotate
                        ht_rl foldr_upd_app_if [folded data_map_insert_def]
                        rl projectKOs cvariable_array_ptr_retyps[OF szo]
                        zero_ranges_ptr_retyps
              simp del: endpoint_C_size)
  done
qed

lemma createObjects_ccorres_ntfn:
  defines "ko \<equiv> (KONotification (makeObject :: Structures_H.notification))"
  shows "\<forall>\<sigma> x. (\<sigma>, x) \<in> rf_sr \<and> ptr \<noteq> 0
  \<and> pspace_aligned' \<sigma> \<and> pspace_distinct' \<sigma>
  \<and> pspace_no_overlap' ptr sz \<sigma>
  \<and> ret_zero ptr (n * (2 ^ objBitsKO ko)) \<sigma>
  \<and> region_is_zero_bytes ptr (n * 2 ^ objBitsKO ko) x
  \<and> range_cover ptr sz (objBitsKO ko) n
  \<and> {ptr ..+ n * (2 ^ objBitsKO ko)} \<inter> kernel_data_refs = {}
  \<longrightarrow>
  (\<sigma>\<lparr>ksPSpace := foldr (\<lambda>addr. data_map_insert addr ko) (new_cap_addrs n ptr ko) (ksPSpace \<sigma>)\<rparr>,
   x\<lparr>globals := globals x
                 \<lparr>t_hrs_' := hrs_htd_update (ptr_retyps_gen n (Ptr ptr :: notification_C ptr) False)
                      (t_hrs_' (globals x))\<rparr>\<rparr>) \<in> rf_sr"
  (is "\<forall>\<sigma> x. ?P \<sigma> x \<longrightarrow>
    (\<sigma>\<lparr>ksPSpace := ?ks \<sigma>\<rparr>, x\<lparr>globals := globals x\<lparr>t_hrs_' := ?ks' x\<rparr>\<rparr>) \<in> rf_sr")

proof (intro impI allI)
  fix \<sigma> x
  let ?thesis = "(\<sigma>\<lparr>ksPSpace := ?ks \<sigma>\<rparr>, x\<lparr>globals := globals x\<lparr>t_hrs_' := ?ks' x\<rparr>\<rparr>) \<in> rf_sr"
  let ?ks = "?ks \<sigma>"
  let ?ks' = "?ks' x"
  let ?ptr = "Ptr ptr :: notification_C ptr"

  assume "?P \<sigma> x"
  hence rf: "(\<sigma>, x) \<in> rf_sr"
    and cover: "range_cover ptr sz (objBitsKO ko) n"
    and al: "is_aligned ptr (objBitsKO ko)" and ptr0: "ptr \<noteq> 0"
    and sz: "objBitsKO ko \<le> sz"
    and szb: "sz < word_bits"
    and pal: "pspace_aligned' \<sigma>" and pdst: "pspace_distinct' \<sigma>"
    and pno: "pspace_no_overlap' ptr sz \<sigma>"
    and rzo: "ret_zero ptr (n * (2 ^ objBitsKO ko)) \<sigma>"
    and empty: "region_is_bytes ptr (n * (2 ^ objBitsKO ko)) x"
    and zero: "heap_list_is_zero (hrs_mem (t_hrs_' (globals x))) ptr (n * (2 ^ objBitsKO ko))"
    and rc: "range_cover ptr sz (objBitsKO ko) n"
    and kdr: "{ptr..+n * 2 ^ objBitsKO ko} \<inter> kernel_data_refs = {}"
    by (clarsimp simp:range_cover_def[where 'a=32, folded word_bits_def])+

  (* obj specific *)
  have mko: "\<And> dev. makeObjectKO dev (Inr (APIObjectType ArchTypes_H.apiobject_type.NotificationObject)) = Some ko" by (simp add: ko_def makeObjectKO_def)

  have relrl:
    "cnotification_relation (cslift x) makeObject (from_bytes (replicate (size_of TYPE(notification_C)) 0))"
    unfolding cnotification_relation_def
    apply (simp add: Let_def makeObject_notification size_of_def notification_lift_def)
    apply (simp add: from_bytes_def)
    apply (simp add: typ_info_simps notification_C_tag_def notification_lift_def
      size_td_lt_final_pad size_td_lt_ti_typ_pad_combine Let_def size_of_def)
    apply (simp add: final_pad_def Let_def size_td_lt_ti_typ_pad_combine Let_def
      size_of_def padup_def align_td_array' size_td_array update_ti_adjust_ti
      ti_typ_pad_combine_def Let_def ti_typ_combine_def empty_typ_info_def)
    apply (simp add: typ_info_array array_tag_def eval_nat_numeral)
    apply (simp add: array_tag_n.simps)
    apply (simp add: final_pad_def Let_def size_td_lt_ti_typ_pad_combine Let_def
      size_of_def padup_def align_td_array' size_td_array update_ti_adjust_ti
      ti_typ_pad_combine_def Let_def ti_typ_combine_def empty_typ_info_def)
    apply (simp add: update_ti_t_word32_0s NtfnState_Idle_def option_to_ctcb_ptr_def)
    done

  (* /obj specific *)

  (* s/obj/obj'/ *)
  have szo: "size_of TYPE(notification_C) = 2 ^ objBitsKO ko"
    by (simp add: size_of_def objBits_simps' ko_def)
  have szo': "n * (2 ^ objBitsKO ko) = n * size_of TYPE(notification_C)" using sz
    apply (subst szo)
    apply (simp add: power_add [symmetric])
    done

  note rl' = cslift_ptr_retyp_other_inst[OF empty cover[simplified] szo' szo]

  (* rest is generic *)
  note rl = projectKO_opt_retyp_other [OF rc pal pno ko_def]
  note cterl = retype_ctes_helper [OF pal pdst pno al sz szb mko rc, simplified]
  note ht_rl = clift_eq_h_t_valid_eq[OF rl', OF tag_disj_via_td_name, simplified]

  have guard:
    "\<forall>b<n. c_guard (CTypesDefs.ptr_add ?ptr (of_nat b))"
    apply (rule retype_guard_helper[where m=2, OF cover ptr0 szo])
    apply (simp add: ko_def objBits_simps' align_of_def)+
    done

  from rf have "cpspace_relation (ksPSpace \<sigma>) (underlying_memory (ksMachineState \<sigma>)) (t_hrs_' (globals x))"
    unfolding rf_sr_def cstate_relation_def by (simp add: Let_def)
  hence "cpspace_relation ?ks  (underlying_memory (ksMachineState \<sigma>)) ?ks'"
    unfolding cpspace_relation_def
    apply -
    apply (clarsimp simp: rl' cterl tag_disj_via_td_name foldr_upd_app_if [folded data_map_insert_def]
      heap_to_user_data_def cte_C_size)
    apply (subst clift_ptr_retyps_gen_prev_memset_same[OF guard _ _ szo' _ zero],
      simp_all only: szo empty, simp_all)
     apply (rule range_cover.strong_times_32[OF cover refl])
    apply (simp add: ptr_add_to_new_cap_addrs [OF szo] ht_rl)
    apply (simp add: rl projectKO_opt_retyp_same projectKOs)
    apply (simp add: ko_def projectKO_opt_retyp_same projectKOs cong: if_cong)
    apply (erule cmap_relation_retype)
    apply (rule relrl[simplified szo ko_def])
    done

  thus ?thesis using rf empty kdr rzo
    apply (simp add: rf_sr_def cstate_relation_def Let_def rl' tag_disj_via_td_name)
    apply (simp add: carch_state_relation_def cmachine_state_relation_def)
    apply (simp add: rl' cterl tag_disj_via_td_name h_t_valid_clift_Some_iff )
    apply (clarsimp simp: hrs_htd_update ptr_retyps_htd_safe_neg szo
                          kernel_data_refs_domain_eq_rotate
                          ht_rl foldr_upd_app_if [folded data_map_insert_def]
                          rl projectKOs cvariable_array_ptr_retyps[OF szo]
                          zero_ranges_ptr_retyps
                simp del: notification_C_size)
    done
qed


lemma ccte_relation_makeObject:
  notes option.case_cong_weak [cong]
  shows "ccte_relation makeObject (from_bytes (replicate (size_of TYPE(cte_C)) 0))"
  apply (simp add: Let_def makeObject_cte size_of_def ccte_relation_def map_option_Some_eq2)
  apply (simp add: from_bytes_def)
  apply (simp add: typ_info_simps cte_C_tag_def  cte_lift_def
    size_td_lt_final_pad size_td_lt_ti_typ_pad_combine Let_def size_of_def)
  apply (simp add: final_pad_def Let_def size_td_lt_ti_typ_pad_combine
    size_of_def padup_def align_td_array' size_td_array update_ti_adjust_ti
    ti_typ_pad_combine_def ti_typ_combine_def empty_typ_info_def align_of_def
    typ_info_simps cap_C_tag_def mdb_node_C_tag_def split: option.splits)
  apply (simp add: typ_info_array array_tag_def eval_nat_numeral array_tag_n.simps)
  apply (simp add: final_pad_def Let_def size_td_lt_ti_typ_pad_combine
    size_of_def padup_def align_td_array' size_td_array update_ti_adjust_ti
    ti_typ_pad_combine_def ti_typ_combine_def empty_typ_info_def update_ti_t_word32_0s)
  apply (simp add: cap_lift_def Let_def cap_get_tag_def cap_tag_defs cte_to_H_def cap_to_H_def mdb_node_to_H_def
    mdb_node_lift_def nullMDBNode_def c_valid_cte_def)
  done

lemma ccte_relation_nullCap:
  notes option.case_cong_weak [cong]
  shows "ccte_relation (CTE NullCap (MDB 0 0 False False)) (from_bytes (replicate (size_of TYPE(cte_C)) 0))"
  apply (simp add: Let_def makeObject_cte size_of_def ccte_relation_def map_option_Some_eq2)
  apply (simp add: from_bytes_def)
  apply (simp add: typ_info_simps cte_C_tag_def  cte_lift_def
    size_td_lt_final_pad size_td_lt_ti_typ_pad_combine Let_def size_of_def)
  apply (simp add: final_pad_def Let_def size_td_lt_ti_typ_pad_combine
    size_of_def padup_def align_td_array' size_td_array update_ti_adjust_ti
    ti_typ_pad_combine_def ti_typ_combine_def empty_typ_info_def align_of_def
    typ_info_simps cap_C_tag_def mdb_node_C_tag_def split: option.splits)
  apply (simp add: typ_info_array array_tag_def eval_nat_numeral array_tag_n.simps)
  apply (simp add: final_pad_def Let_def size_td_lt_ti_typ_pad_combine
    size_of_def padup_def align_td_array' size_td_array update_ti_adjust_ti
    ti_typ_pad_combine_def ti_typ_combine_def empty_typ_info_def update_ti_t_word32_0s)
  apply (simp add: cap_lift_def Let_def cap_get_tag_def cap_tag_defs cte_to_H_def cap_to_H_def mdb_node_to_H_def
    mdb_node_lift_def nullMDBNode_def c_valid_cte_def)
  done

lemma createObjects_ccorres_cte:
  defines "ko \<equiv> (KOCTE (makeObject :: cte))"
  shows "\<forall>\<sigma> x. (\<sigma>, x) \<in> rf_sr  \<and> ptr \<noteq> 0
  \<and> pspace_aligned' \<sigma> \<and> pspace_distinct' \<sigma>
  \<and> pspace_no_overlap' ptr sz \<sigma>
  \<and> ret_zero ptr (n * 2 ^ objBitsKO ko) \<sigma>
  \<and> region_is_zero_bytes ptr (n * 2 ^ objBitsKO ko) x
  \<and> range_cover ptr sz (objBitsKO ko) n
  \<and> {ptr ..+ n * (2 ^ objBitsKO ko)} \<inter> kernel_data_refs = {}
   \<longrightarrow>
  (\<sigma>\<lparr>ksPSpace := foldr (\<lambda>addr. data_map_insert addr ko) (new_cap_addrs n ptr ko) (ksPSpace \<sigma>)\<rparr>,
   x\<lparr>globals := globals x
                 \<lparr>t_hrs_' := hrs_htd_update (ptr_retyps_gen n (Ptr ptr :: cte_C ptr) True)
                       (t_hrs_' (globals x))\<rparr>\<rparr>) \<in> rf_sr"
  (is "\<forall>\<sigma> x. ?P \<sigma> x \<longrightarrow>
    (\<sigma>\<lparr>ksPSpace := ?ks \<sigma>\<rparr>, x\<lparr>globals := globals x\<lparr>t_hrs_' := ?ks' x\<rparr>\<rparr>) \<in> rf_sr")
proof (intro impI allI)
  fix \<sigma> x
  let ?thesis = "(\<sigma>\<lparr>ksPSpace := ?ks \<sigma>\<rparr>, x\<lparr>globals := globals x\<lparr>t_hrs_' := ?ks' x\<rparr>\<rparr>) \<in> rf_sr"
  let ?ks = "?ks \<sigma>"
  let ?ks' = "?ks' x"
  let ?ptr = "Ptr ptr :: cte_C ptr"

  assume "?P \<sigma> x"
  hence rf: "(\<sigma>, x) \<in> rf_sr"
    and cover: "range_cover ptr sz (objBitsKO ko) n"
    and al: "is_aligned ptr (objBitsKO ko)" and ptr0: "ptr \<noteq> 0"
    and sz: "objBitsKO ko \<le> sz"
    and szb: "sz < word_bits"
    and pal: "pspace_aligned' \<sigma>" and pdst: "pspace_distinct' \<sigma>"
    and pno: "pspace_no_overlap' ptr sz \<sigma>"
    and rzo: "ret_zero ptr (n * 2 ^ objBitsKO ko) \<sigma>"
    and empty: "region_is_bytes ptr (n * (2 ^ objBitsKO ko)) x"
    and zero: "heap_list_is_zero (hrs_mem (t_hrs_' (globals x))) ptr (n * (2 ^ objBitsKO ko))"
    and rc: "range_cover ptr sz (objBitsKO ko) n"
    and kdr: "{ptr..+n * 2 ^ objBitsKO ko} \<inter> kernel_data_refs = {}"
    by (clarsimp simp:range_cover_def[where 'a=32, folded word_bits_def])+

  (* obj specific *)
  have mko: "\<And>dev. makeObjectKO dev (Inr (APIObjectType  ArchTypes_H.apiobject_type.CapTableObject)) = Some ko"
    by (simp add: ko_def makeObjectKO_def)

  note relrl = ccte_relation_makeObject

  (* /obj specific *)

  (* s/obj/obj'/ *)
  have szo: "size_of TYPE(cte_C) = 2 ^ objBitsKO ko"
    by (simp add: size_of_def objBits_simps' ko_def)
  have szo': "n * 2 ^ objBitsKO ko = n * size_of TYPE(cte_C)" using sz
    apply (subst szo)
    apply (simp add: power_add [symmetric])
    done

  note rl' = cslift_ptr_retyp_other_inst[OF empty cover szo' szo]

  (* rest is generic *)
  note rl = projectKO_opt_retyp_other [OF rc pal pno ko_def]
  note cterl = retype_ctes_helper [OF pal pdst pno al sz szb mko rc, simplified]
  note ht_rl = clift_eq_h_t_valid_eq[OF rl', OF tag_disj_via_td_name, simplified]

  have guard:
    "\<forall>b< n. c_guard (CTypesDefs.ptr_add ?ptr (of_nat b))"
    apply (rule retype_guard_helper[where m=2, OF cover ptr0 szo])
    apply (simp add: ko_def objBits_simps' align_of_def)+
    done

  note irq = h_t_valid_eq_array_valid[where 'a=cte_C]
    h_t_array_valid_ptr_retyps_gen[where p="Ptr ptr", simplified, OF szo empty]

  with rf have irq: "h_t_valid (hrs_htd ?ks') c_guard intStateIRQNode_array_Ptr"
    apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def)
    apply (simp add: hrs_htd_update h_t_valid_eq_array_valid)
    apply (simp add: h_t_array_valid_ptr_retyps_gen[OF szo] empty)
    done

  note if_cong[cong] (* needed by some of the [simplified]'s below. *)
  from rf have "cpspace_relation (ksPSpace \<sigma>) (underlying_memory (ksMachineState \<sigma>)) (t_hrs_' (globals x))"
    unfolding rf_sr_def cstate_relation_def by (simp add: Let_def)
  hence "cpspace_relation ?ks (underlying_memory (ksMachineState \<sigma>)) ?ks'"
    unfolding cpspace_relation_def
    apply -
    apply (clarsimp simp: rl' cterl tag_disj_via_td_name foldr_upd_app_if [folded data_map_insert_def])
    apply (subst clift_ptr_retyps_gen_prev_memset_same[OF guard _ _ szo' _ zero],
      simp_all only: szo empty, simp_all)
     apply (rule range_cover.strong_times_32[OF cover refl])
    apply (simp add: ptr_add_to_new_cap_addrs [OF szo] ht_rl)
    apply (simp add: rl projectKO_opt_retyp_same projectKOs)
    apply (simp add: ko_def projectKO_opt_retyp_same projectKOs cong: if_cong)
    apply (subst makeObject_cte[symmetric])
    apply (erule cmap_relation_retype)
    apply (rule relrl[simplified szo ko_def])
    done

  thus ?thesis using rf empty kdr irq rzo
    apply (simp add: rf_sr_def cstate_relation_def Let_def rl' tag_disj_via_td_name)
    apply (simp add: carch_state_relation_def cmachine_state_relation_def)
    apply (simp add: rl' cterl tag_disj_via_td_name h_t_valid_clift_Some_iff)
    apply (clarsimp simp: hrs_htd_update ptr_retyps_htd_safe_neg szo
                          kernel_data_refs_domain_eq_rotate
                          rl foldr_upd_app_if [folded data_map_insert_def] projectKOs
                          zero_ranges_ptr_retyps
                          ht_rl cvariable_array_ptr_retyps[OF szo])
    done
qed

lemma h_t_valid_ptr_retyps_gen_disjoint:
  "\<lbrakk> d \<Turnstile>\<^sub>t p; {ptr_val p..+ size_of TYPE('b)} \<inter> {ptr_val ptr..+n * size_of TYPE('a)} = {} \<rbrakk> \<Longrightarrow>
  ptr_retyps_gen n (ptr::'a::mem_type ptr) arr d \<Turnstile>\<^sub>t (p::'b::mem_type ptr)"
  apply (clarsimp simp: h_t_valid_def valid_footprint_def Let_def)
  apply (drule spec, drule (1) mp)
  apply (subgoal_tac "ptr_val p + of_nat y \<notin> {ptr_val ptr..+n * size_of TYPE('a)}")
   apply (simp add: ptr_retyps_gen_out)
  apply clarsimp
  apply (drule intvlD)
  apply (clarsimp simp: disjoint_iff_not_equal )
  apply (drule_tac x = "ptr_val p + of_nat y" in bspec)
   apply (rule intvlI)
   apply (simp add: size_of_def)
  apply (drule_tac x = "ptr_val ptr + of_nat k" in bspec)
   apply (erule intvlI)
  apply simp
  done

lemma range_cover_intvl:
assumes cover: "range_cover (ptr :: 'a :: len word) sz us n"
assumes not0 : "n \<noteq> 0"
shows "{ptr..+n * 2 ^ us} = {ptr..ptr + (of_nat n * 2 ^ us - 1)}"
  proof
    have not0' : "(0 :: 'a word) < of_nat n * (2 :: 'a word) ^ us"
      using range_cover_not_zero_shift[OF _ cover,where gbits = "us"]
     apply (simp add:not0 shiftl_t2n field_simps)
     apply unat_arith
     done

    show "{ptr..+n * 2 ^ us} \<subseteq> {ptr..ptr + (of_nat n* 2 ^ us - 1)}"
     using not0 not0'
     apply (clarsimp simp:intvl_def)
     apply (intro conjI)
      apply (rule word_plus_mono_right2[rotated,where b = "of_nat n * 2^us - 1"])
       apply (subst le_m1_iff_lt[THEN iffD1])
        apply (simp add:not0')
       apply (rule word_of_nat_less)
       apply (clarsimp simp: range_cover.unat_of_nat_shift[OF cover] field_simps)
      apply (clarsimp simp: field_simps)
      apply (erule range_cover_bound[OF cover])
     apply (rule word_plus_mono_right)
      apply (subst le_m1_iff_lt[THEN iffD1])
       apply (simp add:not0')
      apply (rule word_of_nat_less)
      apply (clarsimp simp: range_cover.unat_of_nat_shift[OF cover] field_simps)
     apply (clarsimp simp: field_simps)
      apply (erule range_cover_bound[OF cover])
     done
   show "{ptr..ptr + (of_nat n * 2 ^ us - 1)} \<subseteq> {ptr..+n * 2 ^ us}"
     using not0 not0'
     apply (clarsimp simp:intvl_def)
     apply (rule_tac x = "unat (x - ptr)" in exI)
      apply simp
      apply (simp add:field_simps)
      apply (rule unat_less_helper)
      apply (subst le_m1_iff_lt[THEN iffD1,symmetric])
      apply (simp add:field_simps not0 range_cover_not_zero_shift[unfolded shiftl_t2n,OF _ _ le_refl])
     apply (rule word_diff_ls')
      apply (simp add:field_simps)
     apply simp
    done
  qed

lemma cmap_relation_array_add_array[OF refl]:
  "ptrf = Ptr \<Longrightarrow> carray_map_relation n ahp chp ptrf
    \<Longrightarrow> is_aligned p n
    \<Longrightarrow> ahp' = (\<lambda>x. if x \<in> set (new_cap_addrs sz p ko) then Some v else ahp x)
    \<Longrightarrow> (\<forall>x. chp x \<longrightarrow> is_aligned (ptr_val x) n \<Longrightarrow> \<forall>y. chp' y = (y = ptrf p | chp y))
    \<Longrightarrow> sz = 2 ^ (n - objBits v)
    \<Longrightarrow> objBitsKO ko = objBitsKO (injectKOS v)
    \<Longrightarrow> objBits v \<le> n \<Longrightarrow> n < word_bits
    \<Longrightarrow> carray_map_relation n ahp' chp' ptrf"
  apply (clarsimp simp: carray_map_relation_def objBits_koTypeOf
                        objBitsT_koTypeOf[symmetric]
                        koTypeOf_injectKO
              simp del: objBitsT_koTypeOf)
  apply (drule meta_mp)
   apply auto[1]
  apply (case_tac "pa = p"; clarsimp)
   apply (subst if_P; simp add: new_cap_addrs_def)
   apply (rule_tac x="unat ((p' && mask n) >> objBitsKO ko)" in image_eqI)
    apply (simp add: shiftr_shiftl1 is_aligned_andI1 add.commute
                     word_plus_and_or_coroll2)
   apply (simp, rule unat_less_helper, simp, rule shiftr_less_t2n)
   apply (simp add: and_mask_less_size word_size word_bits_def)
  apply (case_tac "chp (ptrf pa)", simp_all)
   apply (drule spec, drule(1) iffD2)
   apply (auto split: if_split)[1]
  apply (drule_tac x=pa in spec, clarsimp)
  apply (drule_tac x=p' in spec, clarsimp split: if_split_asm)
  apply (clarsimp simp: new_cap_addrs_def)
  apply (subst(asm) is_aligned_add_helper, simp_all)
  apply (rule shiftl_less_t2n, rule word_of_nat_less, simp_all add: word_bits_def)
  done

lemma createObjects_ccorres_pte:
  defines "ko \<equiv> (KOArch (KOPTE (makeObject :: pte)))"
  shows "\<forall>\<sigma> x. (\<sigma>, x) \<in> rf_sr \<and> ptr \<noteq> 0
  \<and> pspace_aligned' \<sigma> \<and> pspace_distinct' \<sigma>
  \<and> pspace_no_overlap' ptr sz \<sigma>
  \<and> ret_zero ptr (2 ^ ptBits) \<sigma>
  \<and> region_is_zero_bytes ptr (2 ^ ptBits) x
  \<and> range_cover ptr sz ptBits 1
  \<and> valid_global_refs' s
  \<and> kernel_data_refs \<inter> {ptr..+ 2 ^ ptBits} = {} \<longrightarrow>
  (\<sigma>\<lparr>ksPSpace := foldr (\<lambda>addr. data_map_insert addr ko) (new_cap_addrs 256 ptr ko) (ksPSpace \<sigma>)\<rparr>,
   x\<lparr>globals := globals x
                 \<lparr>t_hrs_' := hrs_htd_update (ptr_retyps_gen 1 (pt_Ptr ptr) False)
                       (t_hrs_' (globals x))\<rparr>\<rparr>) \<in> rf_sr"
  (is "\<forall>\<sigma> x. ?P \<sigma> x \<longrightarrow>
    (\<sigma>\<lparr>ksPSpace := ?ks \<sigma>\<rparr>, x\<lparr>globals := globals x\<lparr>t_hrs_' := ?ks' x\<rparr>\<rparr>) \<in> rf_sr")
proof (intro impI allI)
  fix \<sigma> x
  let ?thesis = "(\<sigma>\<lparr>ksPSpace := ?ks \<sigma>\<rparr>, x\<lparr>globals := globals x\<lparr>t_hrs_' := ?ks' x\<rparr>\<rparr>) \<in> rf_sr"
  let ?ks = "?ks \<sigma>"
  let ?ks' = "?ks' x"
  let ?ptr = "Ptr ptr :: (pte_C[256]) ptr"
  assume "?P \<sigma> x"
  hence rf: "(\<sigma>, x) \<in> rf_sr"
    and cover: "range_cover ptr sz ptBits 1"
    and al: "is_aligned ptr ptBits"
    and ptr0: "ptr \<noteq> 0"
    and sz: "ptBits \<le> sz"
    and szb: "sz < word_bits"
    and pal: "pspace_aligned' \<sigma>"
    and pdst: "pspace_distinct' \<sigma>"
    and pno: "pspace_no_overlap' ptr sz \<sigma>"
    and rzo: "ret_zero ptr (2 ^ ptBits) \<sigma>"
    and empty: "region_is_bytes ptr (2 ^ ptBits) x"
    and zero: "heap_list_is_zero (hrs_mem (t_hrs_' (globals x))) ptr (2 ^ ptBits)"
    and kernel_data_refs_disj : "kernel_data_refs \<inter> {ptr..+ 2 ^ ptBits} = {}"
    by (clarsimp simp:range_cover_def[where 'a=32, folded word_bits_def])+

    note blah[simp del] =  atLeastAtMost_iff atLeastatMost_subset_iff atLeastLessThan_iff
          Int_atLeastAtMost atLeastatMost_empty_iff split_paired_Ex

  (* obj specific *)
  have mko: "\<And>dev. makeObjectKO dev (Inr ARM_H.PageTableObject) = Some ko" by (simp add: ko_def makeObjectKO_def)

  have relrl:
    "cpte_relation makeObject (from_bytes (replicate (size_of TYPE(pte_C)) 0))"
    unfolding cpte_relation_def
    apply (simp add: Let_def makeObject_pte size_of_def pte_lift_def)
    apply (simp add: from_bytes_def)
    apply (simp add: typ_info_simps pte_C_tag_def pte_lift_def pte_get_tag_def
      size_td_lt_final_pad size_td_lt_ti_typ_pad_combine Let_def size_of_def)
    apply (simp add: final_pad_def Let_def size_td_lt_ti_typ_pad_combine Let_def
      size_of_def padup_def align_td_array' size_td_array update_ti_adjust_ti
      ti_typ_pad_combine_def Let_def ti_typ_combine_def empty_typ_info_def)
    apply (simp add: typ_info_array array_tag_def eval_nat_numeral)
    apply (simp add: array_tag_n.simps)
    apply (simp add: final_pad_def Let_def size_td_lt_ti_typ_pad_combine Let_def
      size_of_def padup_def align_td_array' size_td_array update_ti_adjust_ti
      ti_typ_pad_combine_def Let_def ti_typ_combine_def empty_typ_info_def)
    apply (simp add: update_ti_t_word32_0s pte_tag_defs)
    done

  (* /obj specific *)

  (* s/obj/obj'/ *)
  have szo: "size_of TYPE(pte_C[256]) = 2 ^ ptBits"
    by (simp add: size_of_def size_td_array ptBits_def pageBits_def pteBits_def)
  have szo2: "256 * size_of TYPE(pte_C) = 2 ^ ptBits"
    by (simp add: szo[symmetric])
  have szo': "size_of TYPE(pte_C) = 2 ^ objBitsKO ko"
    by (simp add: objBits_simps ko_def archObjSize_def ptBits_def pageBits_def pteBits_def)

  note rl' = cslift_ptr_retyp_other_inst[where n=1,
    simplified, OF empty cover[simplified] szo[symmetric] szo]

  have sz_weaken: "objBitsKO ko \<le> ptBits"
    by (simp add: objBits_simps ko_def archObjSize_def ptBits_def pageBits_def)
  have cover': "range_cover ptr sz (objBitsKO ko) 256"
    apply (rule range_cover_rel[OF cover sz_weaken])
    apply (simp add: ptBits_def objBits_simps ko_def archObjSize_def pageBits_def)
    done
  from sz sz_weaken have sz': "objBitsKO ko \<le> sz" by simp
  note al' = is_aligned_weaken[OF al sz_weaken]

  have koT: "koTypeOf ko = ArchT PTET"
    by (simp add: ko_def)

  (* rest used to be generic, but PT arrays are complicating everything *)

  note rl = projectKO_opt_retyp_other [OF cover' pal pno ko_def]
  note cterl = retype_ctes_helper [OF pal pdst pno al' sz' szb mko cover']

  have guard: "c_guard ?ptr"
    apply (rule is_aligned_c_guard[where n=ptBits and m=2])
        apply (simp_all add: al ptr0 align_of_def align_td_array)
     apply (simp_all add: ptBits_def pageBits_def pteBits_def)
    done

  have guard': "\<forall>n < 256. c_guard (pte_Ptr ptr +\<^sub>p int n)"
    apply (rule retype_guard_helper [OF cover' ptr0 szo', where m=2])
     apply (simp_all add: objBits_simps ko_def archObjSize_def align_of_def pteBits_def)
    done

  note ptr_retyps.simps[simp del]

  from rf have pterl: "cmap_relation (map_to_ptes (ksPSpace \<sigma>)) (cslift x) Ptr cpte_relation"
    unfolding rf_sr_def cstate_relation_def by (simp add: Let_def cpspace_relation_def)

  note ht_rl = clift_eq_h_t_valid_eq[OF rl', OF tag_disj_via_td_name, simplified]

  have pte_arr: "cpspace_pte_array_relation (ksPSpace \<sigma>) (t_hrs_' (globals x))
    \<Longrightarrow> cpspace_pte_array_relation ?ks ?ks'"
   apply (erule cmap_relation_array_add_array[OF _ al])
        apply (simp add: foldr_upd_app_if[folded data_map_insert_def])
        apply (rule projectKO_opt_retyp_same, simp add: ko_def projectKOs)
       apply (simp add: h_t_valid_clift_Some_iff dom_def split: if_split)
       apply (subst clift_ptr_retyps_gen_prev_memset_same[where n=1, simplified, OF guard],
         simp_all only: szo refl empty, simp_all add: zero)[1]
        apply (simp add: ptBits_def pageBits_def word_bits_def pteBits_def)
       apply (auto split: if_split)[1]
      apply (simp_all add: objBits_simps archObjSize_def ptBits_def
                           pageBits_def ko_def word_bits_def pteBits_def)
   done

  from rf have "cpspace_relation (ksPSpace \<sigma>) (underlying_memory (ksMachineState \<sigma>)) (t_hrs_' (globals x))"
    unfolding rf_sr_def cstate_relation_def by (simp add: Let_def)
  hence "cpspace_relation ?ks (underlying_memory (ksMachineState \<sigma>))  ?ks'"
    unfolding cpspace_relation_def
  using pte_arr
  apply (clarsimp simp: rl' cterl cte_C_size tag_disj_via_td_name
                        foldr_upd_app_if [folded data_map_insert_def])
  apply (simp add: ht_rl)
  apply (simp add: ptr_retyp_to_array[simplified])
  apply (subst clift_ptr_retyps_gen_prev_memset_same[OF guard'], simp_all only: szo2 empty)
     apply simp
    apply (simp(no_asm) add: ptBits_def pageBits_def word_bits_def pteBits_def)
   apply (simp add: zero)
  apply (simp add: rl projectKOs del: pte_C_size)
  apply (simp add: rl projectKO_opt_retyp_same ko_def projectKOs Let_def
                   ptr_add_to_new_cap_addrs [OF szo']
              cong: if_cong del: pte_C_size)
  apply (erule cmap_relation_retype)
  apply (insert relrl, auto)
  done

  moreover
  from rf szb al
  have "ptr_span (pd_Ptr (symbol_table ''armKSGlobalPD'')) \<inter> {ptr ..+ 2 ^ ptBits} = {}"
    apply (clarsimp simp: valid_global_refs'_def  Let_def
                          valid_refs'_def ran_def rf_sr_def cstate_relation_def)
    apply (erule disjoint_subset)
    apply (simp add:kernel_data_refs_disj)
    done

  ultimately
  show ?thesis using rf empty kernel_data_refs_disj rzo
    apply (simp add: rf_sr_def cstate_relation_def Let_def rl' tag_disj_via_td_name)
    apply (simp add: carch_state_relation_def cmachine_state_relation_def)
    apply (clarsimp simp add: rl' cterl tag_disj_via_td_name
      hrs_htd_update ht_rl foldr_upd_app_if [folded data_map_insert_def] rl projectKOs
      cvariable_array_ptr_retyps[OF szo]
      zero_ranges_ptr_retyps[where p="pt_Ptr ptr", simplified szo])
    apply (subst h_t_valid_ptr_retyps_gen_disjoint, assumption)
     apply (simp add:szo cte_C_size cte_level_bits_def)
     apply (erule disjoint_subset)
     apply (simp add: ptBits_def pageBits_def pteBits_def del: replicate_numeral)
    apply (subst h_t_valid_ptr_retyps_gen_disjoint, assumption)
     apply (simp add:szo cte_C_size cte_level_bits_def)
     apply (erule disjoint_subset)
     apply (simp add: ptBits_def pageBits_def pteBits_def del: replicate_numeral)
    by (simp add:szo ptr_retyps_htd_safe_neg hrs_htd_def
      kernel_data_refs_domain_eq_rotate ptBits_def pageBits_def
      pteBits_def
      Int_ac del: replicate_numeral)
qed

lemma createObjects_ccorres_pde:
  defines "ko \<equiv> (KOArch (KOPDE (makeObject :: pde)))"
  shows "\<forall>\<sigma> x. (\<sigma>, x) \<in> rf_sr \<and> ptr \<noteq> 0
  \<and> pspace_aligned' \<sigma> \<and> pspace_distinct' \<sigma>
  \<and> pspace_no_overlap' ptr sz \<sigma>
  \<and> ret_zero ptr (2 ^ pdBits) \<sigma>
  \<and> region_is_zero_bytes ptr (2 ^ pdBits) x
  \<and> range_cover ptr sz pdBits 1
  \<and> valid_global_refs' s
  \<and> kernel_data_refs \<inter> {ptr..+ 2 ^ pdBits} = {} \<longrightarrow>
  (\<sigma>\<lparr>ksPSpace := foldr (\<lambda>addr. data_map_insert addr ko) (new_cap_addrs 4096 ptr ko) (ksPSpace \<sigma>)\<rparr>,
   x\<lparr>globals := globals x
                 \<lparr>t_hrs_' := hrs_htd_update (ptr_retyps_gen 1 (Ptr ptr :: (pde_C[4096]) ptr) False)
                       (t_hrs_' (globals x))\<rparr>\<rparr>) \<in> rf_sr"
  (is "\<forall>\<sigma> x. ?P \<sigma> x \<longrightarrow>
    (\<sigma>\<lparr>ksPSpace := ?ks \<sigma>\<rparr>, x\<lparr>globals := globals x\<lparr>t_hrs_' := ?ks' x\<rparr>\<rparr>) \<in> rf_sr")
proof (intro impI allI)
  fix \<sigma> x
  let ?thesis = "(\<sigma>\<lparr>ksPSpace := ?ks \<sigma>\<rparr>, x\<lparr>globals := globals x\<lparr>t_hrs_' := ?ks' x\<rparr>\<rparr>) \<in> rf_sr"
  let ?ks = "?ks \<sigma>"
  let ?ks' = "?ks' x"
  let ?ptr = "Ptr ptr :: (pde_C[4096]) ptr"

  assume "?P \<sigma> x"
  hence rf: "(\<sigma>, x) \<in> rf_sr" and al: "is_aligned ptr pdBits" and ptr0: "ptr \<noteq> 0"
    and cover: "range_cover ptr sz pdBits 1"
    and sz: "pdBits \<le> sz"
    and szb: "sz < word_bits"
    and pal: "pspace_aligned' \<sigma>" and pdst: "pspace_distinct' \<sigma>"
    and pno: "pspace_no_overlap' ptr sz \<sigma>"
    and rzo: "ret_zero ptr (2 ^ pdBits) \<sigma>"
    and empty: "region_is_bytes ptr (2 ^ pdBits) x"
    and zero: "heap_list_is_zero (hrs_mem (t_hrs_' (globals x))) ptr (2 ^ pdBits)"
    and kernel_data_refs_disj : "kernel_data_refs \<inter> {ptr..+ 2 ^ pdBits} = {}"
    by (clarsimp simp:range_cover_def[where 'a=32, folded word_bits_def])+

  (* obj specific *)
  have mko: "\<And>dev. makeObjectKO dev (Inr ARM_H.PageDirectoryObject) = Some ko"
    by (simp add: ko_def makeObjectKO_def)

  note blah[simp del] =  atLeastAtMost_iff atLeastatMost_subset_iff atLeastLessThan_iff
          Int_atLeastAtMost atLeastatMost_empty_iff split_paired_Ex

  have relrl':
    "from_bytes (replicate (size_of TYPE(pde_C)) 0)
          = pde_C.words_C_update (\<lambda>_. Arrays.update (pde_C.words_C undefined) 0 0) undefined"
    apply (simp add: from_bytes_def)
    apply (simp add: typ_info_simps pde_C_tag_def pde_lift_def pde_get_tag_def
      size_td_lt_final_pad size_td_lt_ti_typ_pad_combine Let_def size_of_def)
    apply (simp add: final_pad_def Let_def size_td_lt_ti_typ_pad_combine Let_def
      size_of_def padup_def align_td_array' size_td_array update_ti_adjust_ti
      ti_typ_pad_combine_def Let_def ti_typ_combine_def empty_typ_info_def)
    apply (simp add: typ_info_array array_tag_def eval_nat_numeral)
    apply (simp add: array_tag_n.simps)
    apply (simp add: final_pad_def Let_def size_td_lt_ti_typ_pad_combine Let_def
      size_of_def padup_def align_td_array' size_td_array update_ti_adjust_ti
      ti_typ_pad_combine_def Let_def ti_typ_combine_def empty_typ_info_def)
    apply (simp add: update_ti_t_word32_0s pde_tag_defs)
    done

  have relrl:
    "cpde_relation makeObject (from_bytes (replicate (size_of TYPE(pde_C)) 0))"
    unfolding cpde_relation_def
    apply (simp only: relrl')
    apply (simp add: Let_def makeObject_pde pde_lift_def)
    apply (simp add: pde_lift_def pde_get_tag_def pde_pde_invalid_def)
    done

  have stored_asid: "pde_stored_asid (from_bytes (replicate (size_of TYPE(pde_C)) 0))
                            = None"
    apply (simp only: relrl')
    apply (simp add: pde_stored_asid_def pde_lift_def pde_pde_invalid_lift_def Let_def
                     pde_get_tag_def pde_pde_invalid_def)
    done

  (* /obj specific *)

  (* s/obj/obj'/ *)
  have szo: "size_of TYPE(pde_C[4096]) = 2 ^ pdBits"
    by (simp add: size_of_def size_td_array pdBits_def pageBits_def pdeBits_def)
  have szo2: "4096 * size_of TYPE(pde_C) = 2 ^ pdBits"
    by (simp add: szo[symmetric])
  have szo': "size_of TYPE(pde_C) = 2 ^ objBitsKO ko"
    by (simp add: objBits_simps ko_def archObjSize_def pdBits_def pageBits_def pdeBits_def)

  note rl' = cslift_ptr_retyp_other_inst[where n=1,
    simplified, OF empty cover[simplified] szo[symmetric] szo]

  have sz_weaken: "objBitsKO ko \<le> pdBits"
    by (simp add: objBits_simps ko_def archObjSize_def pdBits_def pageBits_def)
  have cover': "range_cover ptr sz (objBitsKO ko) 4096"
    apply (rule range_cover_rel[OF cover sz_weaken])
    apply (simp add: pdBits_def objBits_simps ko_def archObjSize_def pageBits_def)
    done
  from sz sz_weaken have sz': "objBitsKO ko \<le> sz" by simp
  note al' = is_aligned_weaken[OF al sz_weaken]

  have koT: "koTypeOf ko = ArchT PDET"
    by (simp add: ko_def)

  (* rest used to be generic, but PD arrays are complicating everything *)

  note rl = projectKO_opt_retyp_other [OF cover' pal pno ko_def]
  note cterl = retype_ctes_helper [OF pal pdst pno al' sz' szb mko cover']

  have guard: "c_guard ?ptr"
    apply (rule is_aligned_c_guard[where n=pdBits and m=2])
        apply (simp_all add: al ptr0 align_of_def align_td_array)
     apply (simp_all add: pdBits_def pageBits_def pdeBits_def)
    done

  have guard': "\<forall>n < 4096. c_guard (pde_Ptr ptr +\<^sub>p int n)"
    apply (rule retype_guard_helper [OF cover' ptr0 szo', where m=2])
     apply (simp_all add: objBits_simps ko_def archObjSize_def align_of_def pdeBits_def)
    done

  note rl' = cslift_ptr_retyp_other_inst[OF _ cover refl szo,
    simplified szo, simplified, OF empty]

  from rf have pderl: "cmap_relation (map_to_pdes (ksPSpace \<sigma>)) (cslift x) Ptr cpde_relation"
    unfolding rf_sr_def cstate_relation_def by (simp add: Let_def cpspace_relation_def)

  note ht_rl = clift_eq_h_t_valid_eq[OF rl', OF tag_disj_via_td_name, simplified]

  have pde_arr: "cpspace_pde_array_relation (ksPSpace \<sigma>) (t_hrs_' (globals x))
    \<Longrightarrow> cpspace_pde_array_relation ?ks ?ks'"
   apply (erule cmap_relation_array_add_array[OF _ al])
        apply (simp add: foldr_upd_app_if[folded data_map_insert_def])
        apply (rule projectKO_opt_retyp_same, simp add: ko_def projectKOs)
       apply (simp add: h_t_valid_clift_Some_iff dom_def split: if_split)
       apply (subst clift_ptr_retyps_gen_prev_memset_same[where n=1, simplified, OF guard],
         simp_all only: szo empty, simp_all add: zero)[1]
        apply (simp add: pdBits_def pageBits_def word_bits_def pdeBits_def)
       apply (auto split: if_split)[1]
      apply (simp_all add: objBits_simps archObjSize_def pdBits_def
                           pageBits_def ko_def word_bits_def pdeBits_def)
   done

  from rf have cpsp: "cpspace_relation (ksPSpace \<sigma>) (underlying_memory (ksMachineState \<sigma>)) (t_hrs_' (globals x))"
    unfolding rf_sr_def cstate_relation_def by (simp add: Let_def)
  hence "cpspace_relation ?ks (underlying_memory (ksMachineState \<sigma>))  ?ks'"
    unfolding cpspace_relation_def
  using pde_arr
  apply (clarsimp simp: rl' cterl cte_C_size tag_disj_via_td_name
                        foldr_upd_app_if [folded data_map_insert_def])
  apply (simp add: ht_rl)
  apply (simp add: ptr_retyp_to_array[simplified])
  apply (subst clift_ptr_retyps_gen_prev_memset_same[OF guard'], simp_all only: szo2 empty)
     apply simp
    apply (simp(no_asm) add: pdBits_def pageBits_def word_bits_def pdeBits_def)
   apply (simp add: zero)
  apply (simp add: rl projectKOs)
  apply (simp add: rl projectKO_opt_retyp_same ko_def projectKOs Let_def
                   ptr_add_to_new_cap_addrs [OF szo']
              cong: if_cong)
  apply (erule cmap_relation_retype)
  apply (insert relrl, auto)
  done

  moreover
  from rf szb al
  have "ptr_span (pd_Ptr (symbol_table ''armKSGlobalPD'')) \<inter> {ptr ..+ 2 ^ pdBits} = {}"
    apply (clarsimp simp: valid_global_refs'_def  Let_def
                          valid_refs'_def ran_def rf_sr_def cstate_relation_def)
    apply (erule disjoint_subset)
    apply (simp add:kernel_data_refs_disj)
    done

  moreover from rf have stored_asids: "(pde_stored_asid \<circ>\<^sub>m clift ?ks')
                         = (pde_stored_asid \<circ>\<^sub>m cslift x)"
    unfolding rf_sr_def
    using cpsp empty
    apply (clarsimp simp: rl' cterl cte_C_size tag_disj_via_td_name foldr_upd_app_if [folded data_map_insert_def])
    apply (simp add: ptr_retyp_to_array[simplified])
    apply (subst clift_ptr_retyps_gen_prev_memset_same[OF guard'], simp_all only: szo2 empty)
       apply simp
      apply (simp add: pdBits_def word_bits_def pageBits_def pdeBits_def)
     apply (simp add: zero)
    apply (rule ext)
    apply (simp add: map_comp_def stored_asid[simplified] split: option.split if_split)
    apply (simp only: o_def CTypesDefs.ptr_add_def' Abs_fnat_hom_mult)
    apply (clarsimp simp only:)
    apply (drule h_t_valid_intvl_htd_contains_uinfo_t [OF h_t_valid_clift])
     apply (rule intvl_self, simp)
    apply clarsimp
    apply (subst (asm) empty[unfolded region_is_bytes'_def])
      apply (simp add: objBits_simps archObjSize_def ko_def pdBits_def pageBits_def
                       offs_in_intvl_iff unat_word_ariths unat_of_nat pdeBits_def)
     apply clarsimp
    apply clarsimp
    done

  ultimately
  show ?thesis using rf empty kernel_data_refs_disj rzo
    apply (simp add: rf_sr_def cstate_relation_def Let_def rl'  tag_disj_via_td_name)
    apply (simp add: carch_state_relation_def cmachine_state_relation_def)
    apply (clarsimp simp add: rl' cte_C_size cterl tag_disj_via_td_name
                              hrs_htd_update ht_rl foldr_upd_app_if [folded data_map_insert_def]
                              projectKOs rl cvariable_array_ptr_retyps[OF szo]
                              zero_ranges_ptr_retyps[where p="pd_Ptr ptr", simplified szo])
    apply (subst h_t_valid_ptr_retyps_gen_disjoint)
      apply assumption
     apply (simp add:szo cte_C_size cte_level_bits_def)
     apply (erule disjoint_subset)
     apply (simp add: ko_def projectKOs objBits_simps archObjSize_def
                      pdeBits_def
                      pdBits_def pageBits_def del: replicate_numeral)
    apply (subst h_t_valid_ptr_retyps_gen_disjoint)
      apply assumption
     apply (simp add:szo cte_C_size cte_level_bits_def)
     apply (erule disjoint_subset)
     apply (simp add: ko_def projectKOs objBits_simps archObjSize_def
                      pdeBits_def
                      pdBits_def pageBits_def del: replicate_numeral)
    apply (simp add:szo ptr_retyps_htd_safe_neg hrs_htd_def
      kernel_data_refs_domain_eq_rotate pdeBits_def
      ko_def projectKOs objBits_simps archObjSize_def Int_ac
      pdBits_def pageBits_def
      del: replicate_numeral)
    done
qed

definition
  object_type_from_H :: "object_type \<Rightarrow> word32"
  where
  "object_type_from_H tp \<equiv> case tp of
                              APIObjectType x \<Rightarrow>
                                     (case x of ArchTypes_H.apiobject_type.Untyped \<Rightarrow> scast seL4_UntypedObject
                                              | ArchTypes_H.apiobject_type.TCBObject \<Rightarrow> scast seL4_TCBObject
                                              | ArchTypes_H.apiobject_type.EndpointObject \<Rightarrow> scast seL4_EndpointObject
                                              | ArchTypes_H.apiobject_type.NotificationObject \<Rightarrow> scast seL4_NotificationObject
                                              | ArchTypes_H.apiobject_type.CapTableObject \<Rightarrow> scast seL4_CapTableObject)
                            | ARM_H.SmallPageObject \<Rightarrow> scast seL4_ARM_SmallPageObject
                            | ARM_H.LargePageObject \<Rightarrow> scast seL4_ARM_LargePageObject
                            | ARM_H.SectionObject \<Rightarrow> scast seL4_ARM_SectionObject
                            | ARM_H.SuperSectionObject \<Rightarrow> scast seL4_ARM_SuperSectionObject
                            | ARM_H.PageTableObject \<Rightarrow> scast seL4_ARM_PageTableObject
                            | ARM_H.PageDirectoryObject \<Rightarrow> scast seL4_ARM_PageDirectoryObject"

lemmas nAPIObjects_def = seL4_NonArchObjectTypeCount_def

definition
  object_type_to_H :: "word32 \<Rightarrow> object_type"
  where
  "object_type_to_H x \<equiv>
     (if (x = scast seL4_UntypedObject) then APIObjectType ArchTypes_H.apiobject_type.Untyped else (
      if (x = scast seL4_TCBObject) then APIObjectType ArchTypes_H.apiobject_type.TCBObject else (
       if (x = scast seL4_EndpointObject) then APIObjectType ArchTypes_H.apiobject_type.EndpointObject else (
        if (x = scast seL4_NotificationObject) then APIObjectType ArchTypes_H.apiobject_type.NotificationObject else (
         if (x = scast seL4_CapTableObject) then APIObjectType ArchTypes_H.apiobject_type.CapTableObject else (
          if (x = scast seL4_ARM_SmallPageObject) then ARM_H.SmallPageObject else (
           if (x = scast seL4_ARM_LargePageObject) then ARM_H.LargePageObject else (
            if (x = scast seL4_ARM_SectionObject) then ARM_H.SectionObject else (
             if (x = scast seL4_ARM_SuperSectionObject) then ARM_H.SuperSectionObject else (
              if (x = scast seL4_ARM_PageTableObject) then ARM_H.PageTableObject else (
               if (x = scast seL4_ARM_PageDirectoryObject) then ARM_H.PageDirectoryObject else
                undefined)))))))))))"

lemmas Kernel_C_defs =
  seL4_UntypedObject_def
  seL4_TCBObject_def
  seL4_EndpointObject_def
  seL4_NotificationObject_def
  seL4_CapTableObject_def
  seL4_ARM_SmallPageObject_def
  seL4_ARM_LargePageObject_def
  seL4_ARM_SectionObject_def
  seL4_ARM_SuperSectionObject_def
  seL4_ARM_PageTableObject_def
  seL4_ARM_PageDirectoryObject_def
  Kernel_C.asidLowBits_def
  Kernel_C.asidHighBits_def

abbreviation(input)
  "Basic_htd_update f ==
     (Basic (globals_update (t_hrs_'_update (hrs_htd_update f))))"

lemma object_type_to_from_H [simp]: "object_type_to_H (object_type_from_H x) = x"
  apply (clarsimp simp: object_type_from_H_def object_type_to_H_def Kernel_C_defs)
  by (clarsimp split: object_type.splits apiobject_type.splits simp: Kernel_C_defs)

declare ptr_retyps_one[simp]

(* FIXME: move *)
lemma ccorres_return_C_Seq:
  "ccorres_underlying sr \<Gamma> r rvxf arrel xf P P' hs X (return_C xfu v) \<Longrightarrow>
      ccorres_underlying sr \<Gamma> r rvxf arrel xf P P' hs X (return_C xfu v ;; Z)"
  apply (clarsimp simp: return_C_def)
  apply (erule ccorres_semantic_equiv0[rotated])
  apply (rule semantic_equivI)
  apply (clarsimp simp: exec_assoc[symmetric])
  apply (rule exec_Seq_cong, simp)
  apply (clarsimp simp: exec_assoc[symmetric])
  apply (rule exec_Seq_cong, simp)
  apply (rule iffI)
   apply (auto elim!:exec_Normal_elim_cases intro: exec.Throw exec.Seq)[1]
  apply (auto elim!:exec_Normal_elim_cases intro: exec.Throw)
 done

lemma mdb_node_get_mdbNext_heap_ccorres:
  "ccorres (=) ret__unsigned_' \<top> UNIV hs
  (liftM (mdbNext \<circ> cteMDBNode) (getCTE parent))
  (\<acute>ret__unsigned :== CALL mdb_node_get_mdbNext(h_val
                           (hrs_mem \<acute>t_hrs)
                           (Ptr &((Ptr parent :: cte_C ptr) \<rightarrow>[''cteMDBNode_C'']))))"
  apply (simp add: ccorres_liftM_simp)
  apply (rule ccorres_add_return2)
  apply (rule ccorres_guard_imp2)
  apply (rule ccorres_getCTE)
   apply (rule_tac  P = "\<lambda>s. ctes_of s parent = Some x" in ccorres_from_vcg [where P' = UNIV])
   apply (rule allI, rule conseqPre)
    apply vcg
   apply (clarsimp simp: return_def)
   apply (drule cmap_relation_cte)
   apply (erule (1) cmap_relationE1)
   apply (simp add: typ_heap_simps)
   apply (drule ccte_relation_cmdbnode_relation)
   apply (erule mdbNext_CL_mdb_node_lift_eq_mdbNext [symmetric])
   apply simp
   done

lemma getCTE_pre_cte_at:
  "\<lbrace>\<lambda>s. \<not> cte_at' p s \<rbrace> getCTE p \<lbrace> \<lambda>_ _. False \<rbrace>"
  apply (wp getCTE_wp)
  apply clarsimp
  done

lemmas ccorres_guard_from_wp_liftM = ccorres_guard_from_wp [OF liftM_pre iffD2 [OF empty_fail_liftM]]
lemmas ccorres_guard_from_wp_bind_liftM = ccorres_guard_from_wp_bind [OF liftM_pre iffD2 [OF empty_fail_liftM]]

lemmas ccorres_liftM_getCTE_cte_at = ccorres_guard_from_wp_liftM [OF getCTE_pre_cte_at empty_fail_getCTE]
  ccorres_guard_from_wp_bind_liftM [OF getCTE_pre_cte_at empty_fail_getCTE]

lemma insertNewCap_ccorres_helper:
  notes option.case_cong_weak [cong]
  shows "ccap_relation cap rv'b
       \<Longrightarrow> ccorres dc xfdc (cte_at' slot and K (is_aligned next 3 \<and> is_aligned parent 3))
           UNIV hs (setCTE slot (CTE cap (MDB next parent True True)))
           (Basic (\<lambda>s. globals_update (t_hrs_'_update (hrs_mem_update (heap_update
                                    (Ptr &(Ptr slot :: cte_C ptr\<rightarrow>[''cap_C'']) :: cap_C ptr) rv'b))) s);;
            \<acute>ret__struct_mdb_node_C :== CALL mdb_node_new(ptr_val (Ptr next),scast true,scast true,ptr_val (Ptr parent));;
            Guard C_Guard \<lbrace>hrs_htd \<acute>t_hrs \<Turnstile>\<^sub>t (Ptr slot :: cte_C ptr)\<rbrace>
             (Basic (\<lambda>s. globals_update (t_hrs_'_update (hrs_mem_update (heap_update
                                                                  (Ptr &(Ptr slot :: cte_C ptr\<rightarrow>[''cteMDBNode_C'']) :: mdb_node_C ptr)
                                                                  (ret__struct_mdb_node_C_' s)))) s)))"
  apply simp
  apply (rule ccorres_from_vcg)
  apply (rule allI, rule conseqPre)
   apply vcg
  apply (clarsimp simp: Collect_const_mem cte_wp_at_ctes_of)
  apply (frule (1) rf_sr_ctes_of_clift)
  apply (clarsimp simp: typ_heap_simps)
  apply (rule fst_setCTE [OF ctes_of_cte_at], assumption)
   apply (erule bexI [rotated])
   apply (clarsimp simp: cte_wp_at_ctes_of)
   apply (clarsimp simp add: rf_sr_def cstate_relation_def typ_heap_simps
     Let_def cpspace_relation_def)
   apply (rule conjI)
    apply (erule (2) cmap_relation_updI)
    apply (simp add: ccap_relation_def ccte_relation_def cte_lift_def)
    subgoal by (simp add: cte_to_H_def map_option_Some_eq2 mdb_node_to_H_def to_bool_mask_to_bool_bf is_aligned_neg_mask
      c_valid_cte_def true_def
      split: option.splits)
   subgoal by simp
   apply (erule_tac t = s' in ssubst)
   apply simp
   apply (rule conjI)
    apply (erule (1) setCTE_tcb_case)
   by (simp add: carch_state_relation_def cmachine_state_relation_def
                    typ_heap_simps
                    cvariable_array_map_const_add_map_option[where f="tcb_no_ctes_proj"])

definition
   byte_regions_unmodified :: "heap_raw_state \<Rightarrow> heap_raw_state \<Rightarrow> bool"
where
  "byte_regions_unmodified hrs hrs' \<equiv> \<forall>x. (\<forall>n td b. snd (hrs_htd hrs x) n = Some (td, b)
        \<longrightarrow> td = typ_uinfo_t TYPE (word8))
    \<longrightarrow> snd (hrs_htd hrs x) 0 \<noteq> None
    \<longrightarrow> hrs_mem hrs' x = hrs_mem hrs x"

abbreviation
  byte_regions_unmodified' :: "globals myvars \<Rightarrow> globals myvars \<Rightarrow> bool"
where
  "byte_regions_unmodified' s t \<equiv> byte_regions_unmodified (t_hrs_' (globals s))
    (t_hrs_' (globals t))"

lemma byte_regions_unmodified_refl[iff]:
  "byte_regions_unmodified hrs hrs"
  by (simp add: byte_regions_unmodified_def)

lemma byte_regions_unmodified_trans:
  "byte_regions_unmodified hrs hrs'
    \<Longrightarrow> byte_regions_unmodified hrs' hrs''
    \<Longrightarrow> hrs_htd hrs' = hrs_htd hrs
    \<Longrightarrow> byte_regions_unmodified hrs hrs''"
  by (simp add: byte_regions_unmodified_def)

lemma byte_regions_unmodified_hrs_mem_update1:
  "byte_regions_unmodified hrs hrs'
    \<Longrightarrow> hrs_htd hrs \<Turnstile>\<^sub>t (p :: ('a :: wf_type) ptr)
    \<Longrightarrow> hrs_htd hrs' = hrs_htd hrs
    \<Longrightarrow> typ_uinfo_t TYPE ('a) \<noteq> typ_uinfo_t TYPE (word8)
    \<Longrightarrow> byte_regions_unmodified hrs
      (hrs_mem_update (heap_update p v) hrs')"
  apply (erule byte_regions_unmodified_trans, simp_all)
  apply (clarsimp simp: byte_regions_unmodified_def hrs_mem_update
                        heap_update_def h_t_valid_def
                        valid_footprint_def Let_def)
  apply (rule heap_update_nmem_same)
  apply (clarsimp simp: size_of_def intvl_def)
  apply (drule spec, drule(1) mp, clarsimp)
  apply (cut_tac s="(typ_uinfo_t TYPE('a))" and n=k in ladder_set_self)
  apply (clarsimp dest!: in_set_list_map)
  apply (drule(1) map_le_trans)
  apply (simp add: map_le_def)
  apply metis
  done

lemma byte_regions_unmodified_hrs_mem_update2:
  "byte_regions_unmodified hrs hrs'
    \<Longrightarrow> hrs_htd hrs \<Turnstile>\<^sub>t (p :: ('a :: wf_type) ptr)
    \<Longrightarrow> typ_uinfo_t TYPE ('a) \<noteq> typ_uinfo_t TYPE (word8)
    \<Longrightarrow> byte_regions_unmodified (hrs_mem_update (heap_update p v) hrs) hrs'"
  apply (erule byte_regions_unmodified_trans[rotated], simp_all)
  apply (clarsimp simp: byte_regions_unmodified_def hrs_mem_update
                        heap_update_def h_t_valid_def
                        valid_footprint_def Let_def)
  apply (rule sym, rule heap_update_nmem_same)
  apply (clarsimp simp: size_of_def intvl_def)
  apply (drule spec, drule(1) mp, clarsimp)
  apply (cut_tac s="(typ_uinfo_t TYPE('a))" and n=k in ladder_set_self)
  apply (clarsimp dest!: in_set_list_map)
  apply (drule(1) map_le_trans)
  apply (simp add: map_le_def)
  apply metis
  done

lemmas byte_regions_unmodified_hrs_mem_update
  = byte_regions_unmodified_hrs_mem_update1
    byte_regions_unmodified_hrs_mem_update2

lemma byte_regions_unmodified_hrs_htd_update[iff]:
  "byte_regions_unmodified
      (hrs_htd_update h hrs) hrs"
  by (clarsimp simp: byte_regions_unmodified_def)

lemma byte_regions_unmodified_flip:
  "byte_regions_unmodified (hrs_htd_update (\<lambda>_. hrs_htd hrs) hrs') hrs
    \<Longrightarrow> byte_regions_unmodified hrs hrs'"
  by (simp add: byte_regions_unmodified_def hrs_htd_update)

lemma mdb_node_ptr_set_mdbPrev_preserves_bytes:
  "\<forall>s. \<Gamma>\<turnstile>\<^bsub>/UNIV\<^esub> {s} Call mdb_node_ptr_set_mdbPrev_'proc
      {t. hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))
         \<and> byte_regions_unmodified' s t}"
  apply (hoare_rule HoarePartial.ProcNoRec1)
  apply (rule allI, rule conseqPre, vcg)
  apply (clarsimp simp: )
  apply (intro byte_regions_unmodified_hrs_mem_update byte_regions_unmodified_refl,
    simp_all add: typ_heap_simps)
  done

lemma mdb_node_ptr_set_mdbNext_preserves_bytes:
  "\<forall>s. \<Gamma>\<turnstile>\<^bsub>/UNIV\<^esub> {s} Call mdb_node_ptr_set_mdbNext_'proc
      {t. hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))
         \<and> byte_regions_unmodified' s t}"
  apply (hoare_rule HoarePartial.ProcNoRec1)
  apply (rule allI, rule conseqPre, vcg)
  apply (clarsimp simp: )
  apply (intro byte_regions_unmodified_hrs_mem_update byte_regions_unmodified_refl,
    simp_all add: typ_heap_simps)
  done

lemma updateNewFreeIndex_noop_ccorres:
  "ccorres dc xfdc (valid_objs' and cte_wp_at' (\<lambda>cte. cteCap cte = cap) slot)
      {s. (case untypedZeroRange cap of None \<Rightarrow> True
          | Some (a, b) \<Rightarrow> region_actually_is_zero_bytes a (unat ((b + 1) - a)) s)} hs
      (updateNewFreeIndex slot) Skip"
  (is "ccorres _ _ ?P ?P' hs _ _")
  apply (simp add: updateNewFreeIndex_def getSlotCap_def)
  apply (rule ccorres_guard_imp)
    apply (rule ccorres_pre_getCTE[where P="\<lambda>rv. cte_wp_at' ((=) rv) slot and ?P"
        and P'="K ?P'"])
    apply (case_tac "cteCap cte", simp_all add: ccorres_guard_imp[OF ccorres_return_Skip])[1]
    defer
    apply (clarsimp simp: cte_wp_at_ctes_of)
   apply simp
  apply (simp add: updateTrackedFreeIndex_def getSlotCap_def)
  apply (rule ccorres_guard_imp)
    apply (rule_tac P="\<lambda>rv. cte_wp_at' ((=) rv) slot and K (rv = cte) and ?P"
        in ccorres_pre_getCTE[where P'="K ?P'"])
    defer
    apply (clarsimp simp: cte_wp_at_ctes_of)
   apply simp
  apply (rule ccorres_from_vcg)
  apply (rule allI, rule conseqPre, vcg)
  apply (clarsimp simp: bind_def simpler_modify_def)
  apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def)
  apply (clarsimp simp: zero_ranges_are_zero_def
                        cte_wp_at_ctes_of
                 split: option.split)
  done

lemma byte_regions_unmodified_region_is_bytes:
  "byte_regions_unmodified hrs hrs'
    \<Longrightarrow> region_actually_is_bytes' y n (hrs_htd hrs)
    \<Longrightarrow> x \<in> {y ..+ n}
    \<Longrightarrow> hrs_mem hrs' x = hrs_mem hrs x"
  apply (clarsimp simp: byte_regions_unmodified_def imp_conjL[symmetric])
  apply (drule spec, erule mp)
  apply (clarsimp simp: region_actually_is_bytes'_def)
  apply (drule(1) bspec, simp split: if_split_asm)
  done

lemma insertNewCap_ccorres1:
  "ccorres dc xfdc (pspace_aligned' and valid_mdb' and valid_objs' and valid_cap' cap)
     ({s. (case untypedZeroRange cap of None \<Rightarrow> True
          | Some (a, b) \<Rightarrow> region_actually_is_zero_bytes a (unat ((b + 1) - a)) s)}
       \<inter> {s. ccap_relation cap (cap_' s)} \<inter> {s. parent_' s = Ptr parent}
       \<inter> {s. slot_' s = Ptr slot}) []
     (insertNewCap parent slot cap)
     (Call insertNewCap_'proc)"
  apply (cinit (no_ignore_call) lift: cap_' parent_' slot_')
  apply (rule ccorres_liftM_getCTE_cte_at)
   apply (rule ccorres_move_c_guard_cte)
   apply (simp only: )
   apply (rule ccorres_split_nothrow [OF mdb_node_get_mdbNext_heap_ccorres])
      apply ceqv
     apply (erule_tac s = "next" in subst)
     apply csymbr
     apply (ctac (c_lines 3) pre: ccorres_pre_getCTE ccorres_assert add: insertNewCap_ccorres_helper)
       apply (simp only: Ptr_not_null_pointer_not_zero)
       apply (ctac add: updateMDB_set_mdbPrev)
         apply (rule ccorres_seq_skip'[THEN iffD1])
         apply ctac
           apply (rule updateNewFreeIndex_noop_ccorres[where cap=cap])
          apply (wp updateMDB_weak_cte_wp_at)
         apply simp
         apply (vcg exspec=mdb_node_ptr_set_mdbNext_preserves_bytes)
        apply (wp updateMDB_weak_cte_wp_at)
       apply clarsimp
       apply (vcg exspec=mdb_node_ptr_set_mdbPrev_preserves_bytes)
      apply (wp setCTE_weak_cte_wp_at)
     apply (clarsimp simp: hrs_mem_update Collect_const_mem
                 simp del: imp_disjL)
     apply vcg
    apply simp
    apply (wp getCTE_wp')
   apply (clarsimp simp: hrs_mem_update)
   apply vcg
  apply (rule conjI)
   apply (clarsimp simp: cte_wp_at_ctes_of is_aligned_3_next)
  apply (clarsimp split: option.split)
  apply (intro allI conjI impI; simp; clarsimp simp: region_actually_is_bytes)
   apply (erule trans[OF heap_list_h_eq2, rotated])
   apply (rule byte_regions_unmodified_region_is_bytes)
      apply (erule byte_regions_unmodified_trans[rotated]
         | simp
         | rule byte_regions_unmodified_hrs_mem_update
         | simp add: typ_heap_simps')+
  apply (erule trans[OF heap_list_h_eq2, rotated])
  apply (rule byte_regions_unmodified_region_is_bytes)
     apply (erule byte_regions_unmodified_trans[rotated]
        | simp
        | rule byte_regions_unmodified_hrs_mem_update
        | simp add: typ_heap_simps')+
  done

end

locale insertNewCap_i_locale = kernel
begin

lemma mdb_node_get_mdbNext_spec:
  "\<forall>s. \<Gamma> \<turnstile>\<^bsub>/UNIV\<^esub> {s} Call mdb_node_get_mdbNext_'proc {t. i_' t = i_' s}"
  apply (rule allI)
  apply (hoare_rule HoarePartial.ProcNoRec1)
  apply vcg
  apply simp
  done

lemma mdb_node_new_spec:
  "\<forall>s. \<Gamma> \<turnstile>\<^bsub>/UNIV\<^esub> {s} Call mdb_node_new_'proc {t. i_' t = i_' s}"
  apply (rule allI)
  apply (hoare_rule HoarePartial.ProcNoRec1)
  apply vcg
  apply simp
  done

lemma mdb_node_ptr_set_mdbPrev_spec:
  "\<forall>s. \<Gamma> \<turnstile>\<^bsub>/UNIV\<^esub> {s} Call mdb_node_ptr_set_mdbPrev_'proc {t. i_' t = i_' s}"
  apply (rule allI)
  apply (hoare_rule HoarePartial.ProcNoRec1)
  apply vcg
  apply simp
  done

lemma mdb_node_ptr_set_mdbNext_spec:
  "\<forall>s. \<Gamma> \<turnstile>\<^bsub>/UNIV\<^esub> {s} Call mdb_node_ptr_set_mdbNext_'proc {t. i_' t = i_' s}"
  apply (rule allI)
  apply (hoare_rule HoarePartial.ProcNoRec1)
  apply vcg
  apply simp
  done

lemma insertNewCap_spec:
  "\<forall>s. \<Gamma> \<turnstile>\<^bsub>/UNIV\<^esub> {s} Call insertNewCap_'proc {t. i_' t = i_' s}"
  apply vcg
  apply clarsimp
  done
end

context kernel_m
begin

lemma ccorres_fail:
  "ccorres r xf \<top> UNIV hs fail c"
  apply (rule ccorresI')
  apply (simp add: fail_def)
  done

lemma object_type_from_H_toAPIType_simps:
  "(object_type_from_H tp = scast seL4_UntypedObject) = (toAPIType tp = Some ArchTypes_H.apiobject_type.Untyped)"
  "(object_type_from_H tp = scast seL4_TCBObject) = (toAPIType tp = Some ArchTypes_H.apiobject_type.TCBObject)"
  "(object_type_from_H tp = scast seL4_EndpointObject) = (toAPIType tp = Some ArchTypes_H.apiobject_type.EndpointObject)"
  "(object_type_from_H tp = scast seL4_NotificationObject) = (toAPIType tp = Some ArchTypes_H.apiobject_type.NotificationObject)"
  "(object_type_from_H tp = scast seL4_CapTableObject) = (toAPIType tp = Some ArchTypes_H.apiobject_type.CapTableObject)"
  "(object_type_from_H tp = scast seL4_ARM_SmallPageObject) = (tp = ARM_H.SmallPageObject)"
  "(object_type_from_H tp = scast seL4_ARM_LargePageObject) = (tp = ARM_H.LargePageObject)"
  "(object_type_from_H tp = scast seL4_ARM_SectionObject) = (tp = ARM_H.SectionObject)"
  "(object_type_from_H tp = scast seL4_ARM_SuperSectionObject) = (tp = ARM_H.SuperSectionObject)"
  "(object_type_from_H tp = scast seL4_ARM_PageTableObject) = (tp = ARM_H.PageTableObject)"
  "(object_type_from_H tp = scast seL4_ARM_PageDirectoryObject) = (tp = ARM_H.PageDirectoryObject)"
  by (auto simp: toAPIType_def
                 object_type_from_H_def "StrictC'_object_defs" api_object_defs
          split: object_type.splits ArchTypes_H.apiobject_type.splits)

declare Collect_const_mem [simp]

(* Levity: added (20090419 09:44:40) *)
declare shiftl_mask_is_0 [simp]

lemma heap_update_field':
  "\<lbrakk>field_ti TYPE('a :: packed_type) f = Some t; c_guard p;
  export_uinfo t = export_uinfo (typ_info_t TYPE('b :: packed_type))\<rbrakk>
  \<Longrightarrow> heap_update (Ptr &(p\<rightarrow>f) :: 'b ptr) v hp =
  heap_update p (update_ti_t t (to_bytes_p v) (h_val hp p)) hp"
  apply (erule field_ti_field_lookupE)
  apply (subst packed_heap_super_field_update [unfolded typ_uinfo_t_def])
     apply assumption+
  apply (drule export_size_of [simplified typ_uinfo_t_def])
  apply (simp add: update_ti_t_def)
  done

lemma option_noneI: "\<lbrakk> \<And>x. a = Some x \<Longrightarrow> False \<rbrakk> \<Longrightarrow> a = None"
  apply (case_tac a)
   apply clarsimp
  apply atomize
  apply clarsimp
  done

lemma projectKO_opt_retyp_other':
  assumes pko: "\<forall>v. (projectKO_opt ko :: 'a :: pre_storable option) \<noteq> Some v"
  and pno: "pspace_no_overlap' ptr (objBitsKO ko) (\<sigma> :: kernel_state)"
  and pal: "pspace_aligned' (\<sigma> :: kernel_state)"
  and al: "is_aligned ptr (objBitsKO ko)"
  shows "projectKO_opt \<circ>\<^sub>m ((ksPSpace \<sigma>)(ptr \<mapsto> ko))
  = (projectKO_opt \<circ>\<^sub>m (ksPSpace \<sigma>) :: word32 \<Rightarrow> 'a :: pre_storable option)" (is "?LHS = ?RHS")
proof (rule ext)
  fix x
  show "?LHS x = ?RHS x"
  proof (cases "x = ptr")
    case True
    hence "x \<in> {ptr..(ptr && ~~ mask (objBitsKO ko)) + 2 ^ objBitsKO ko - 1}"
      apply (rule ssubst)
      apply (insert al)
      apply (clarsimp simp: is_aligned_def)
      done
    hence "ksPSpace \<sigma> x = None" using pno
      apply -
      apply (rule option_noneI)
      apply (frule pspace_no_overlap_disjoint'[rotated])
       apply (rule pal)
      apply (drule domI[where a = x])
      apply blast
      done
    thus ?thesis using True pko by simp
  next
    case False
    thus ?thesis by (simp add: map_comp_def)
  qed
qed

lemma dom_tcb_cte_cases_iff:
  "(x \<in> dom tcb_cte_cases) = (\<exists>y < 5. unat x = y * 16)"
  unfolding tcb_cte_cases_def
  by (auto simp: unat_arith_simps)

lemma cmap_relation_retype2:
  assumes cm: "cmap_relation mp mp' Ptr rel"
  and   rel: "rel (mobj :: 'a :: pre_storable) ko'"
  shows "cmap_relation
        (\<lambda>x. if x \<in> ptr_val ` addrs then Some (mobj :: 'a :: pre_storable) else mp x)
        (\<lambda>y. if y \<in> addrs then Some ko' else mp' y)
        Ptr rel"
  using cm rel
  apply -
  apply (rule cmap_relationI)
   apply (simp add: dom_if cmap_relation_def image_Un)
  apply (case_tac "x \<in> addrs")
   apply (simp add: image_image)
  apply (simp add: image_image)
  apply (clarsimp split: if_split_asm)
   apply (erule contrapos_np)
   apply (erule image_eqI [rotated])
   apply simp
  apply (erule (2) cmap_relation_relI)
  done

lemma update_ti_t_ptr_0s:
  "update_ti_t (typ_info_t TYPE('a :: c_type ptr)) [0,0,0,0] X = NULL"
  apply (simp add: typ_info_ptr word_rcat_def bin_rcat_def)
  done

lemma size_td_map_list:
  "size_td_list (map (\<lambda>n. DTPair
                                 (adjust_ti (typ_info_t TYPE('a :: c_type))
                                   (\<lambda>x. index x n)
                                   (\<lambda>x f. Arrays.update f n x))
                                 (replicate n CHR ''1''))
                        [0..<n]) = (size_td (typ_info_t TYPE('a :: c_type)) * n)"
  apply (induct n)
   apply simp
  apply simp
  done

lemma update_ti_t_array_tag_n_rep:
  fixes x :: "'a :: c_type ['b :: finite]"
  shows "\<lbrakk> bs = replicate (n * size_td (typ_info_t TYPE('a))) v; n \<le> card (UNIV  :: 'b set) \<rbrakk> \<Longrightarrow>
  update_ti_t (array_tag_n n) bs x =
  foldr (\<lambda>n arr. Arrays.update arr n
        (update_ti_t (typ_info_t TYPE('a)) (replicate (size_td (typ_info_t TYPE('a))) v) (index arr n)))
        [0..<n] x"
  apply (induct n arbitrary: bs x)
   apply (simp add: array_tag_n_eq)
  apply (simp add: array_tag_n_eq size_td_map_list iffD2 [OF linorder_min_same1] field_simps
    cong: if_cong )
  apply (simp add: update_ti_adjust_ti)
  done

lemma update_ti_t_array_rep:
  "bs = replicate ((card (UNIV :: 'b :: finite set)) * size_td (typ_info_t TYPE('a))) v \<Longrightarrow>
  update_ti_t (typ_info_t TYPE('a :: c_type['b :: finite])) bs x =
  foldr (\<lambda>n arr. Arrays.update arr n
        (update_ti_t (typ_info_t TYPE('a)) (replicate (size_td (typ_info_t TYPE('a))) v) (index arr n)))
        [0..<(card (UNIV :: 'b :: finite set))] x"
  unfolding typ_info_array array_tag_def
  apply (rule update_ti_t_array_tag_n_rep)
    apply simp
   apply simp
   done

lemma update_ti_t_array_rep_word0:
  "bs = replicate ((card (UNIV :: 'b :: finite set)) * 4) 0 \<Longrightarrow>
  update_ti_t (typ_info_t TYPE(word32['b :: finite])) bs x =
  foldr (\<lambda>n arr. Arrays.update arr n 0)
        [0..<(card (UNIV :: 'b :: finite set))] x"
  apply (subst update_ti_t_array_rep)
   apply simp
  apply (simp add: update_ti_t_word32_0s)
  done

lemma tcb_queue_update_other:
  "\<lbrakk> ctcb_ptr_to_tcb_ptr p \<notin> set tcbs \<rbrakk> \<Longrightarrow>
  tcb_queue_relation next prev (mp(p \<mapsto> v)) tcbs qe qh =
  tcb_queue_relation next prev mp tcbs qe qh"
  apply (induct tcbs arbitrary: qh qe)
   apply simp
  apply (rename_tac a tcbs qh qe)
  apply simp
  apply (subgoal_tac "p \<noteq> tcb_ptr_to_ctcb_ptr a")
   apply (simp cong: conj_cong)
  apply clarsimp
  done

lemma tcb_queue_update_other':
  "\<lbrakk> ctcb_ptr_to_tcb_ptr p \<notin> set tcbs \<rbrakk> \<Longrightarrow>
  tcb_queue_relation' next prev (mp(p \<mapsto> v)) tcbs qe qh =
  tcb_queue_relation' next prev mp tcbs qe qh"
  unfolding tcb_queue_relation'_def
  by (simp add: tcb_queue_update_other)

lemma map_to_ko_atI2:
  "\<lbrakk>(projectKO_opt \<circ>\<^sub>m (ksPSpace s)) x = Some v; pspace_aligned' s; pspace_distinct' s\<rbrakk> \<Longrightarrow> ko_at' v x s"
  apply (clarsimp simp: map_comp_Some_iff)
  apply (erule (2) aligned_distinct_obj_atI')
  apply (simp add: project_inject)
  done

lemma c_guard_tcb:
  assumes al: "is_aligned (ctcb_ptr_to_tcb_ptr p) tcbBlockSizeBits"
  and   ptr0: "ctcb_ptr_to_tcb_ptr p \<noteq> 0"
  shows "c_guard p"
  unfolding c_guard_def
proof (rule conjI)
  show "ptr_aligned p" using al
    apply -
    apply (rule is_aligned_ptr_aligned [where n = word_size_bits])
     apply (rule is_aligned_weaken)
      apply (erule ctcb_ptr_to_tcb_ptr_aligned)
     by (auto simp: align_of_def word_size_bits_def ctcb_size_bits_def)

  show "c_null_guard p" using ptr0 al
    unfolding c_null_guard_def
    apply -
    apply (rule intvl_nowrap [where x = 0, simplified])
     apply (clarsimp simp: ctcb_ptr_to_tcb_ptr_def ctcb_offset_defs is_aligned_def objBits_defs)
    apply (drule ctcb_ptr_to_tcb_ptr_aligned)
    apply (erule is_aligned_no_wrap_le)
     by (auto simp add: word_bits_conv ctcb_size_bits_def)
qed


lemma tcb_ptr_orth_cte_ptrs':
  "ptr_span (tcb_Ptr (regionBase + 0x100)) \<inter> ptr_span (Ptr regionBase :: (cte_C[5]) ptr) = {}"
  apply (rule disjointI)
  apply (clarsimp simp: ctcb_ptr_to_tcb_ptr_def size_td_array
                        intvl_def field_simps size_of_def ctcb_offset_def)
  apply (simp add: unat_arith_simps unat_of_nat)
  done

lemmas ptr_retyp_htd_safe_neg
    = ptr_retyps_htd_safe_neg[where n="Suc 0" and arr=False,
    unfolded ptr_retyps_gen_def, simplified]

lemma cnc_tcb_helper:
  fixes p :: "tcb_C ptr"
  defines "kotcb \<equiv> (KOTCB (makeObject :: tcb))"
  assumes rfsr: "(\<sigma>\<lparr>ksPSpace := ks\<rparr>, x) \<in> rf_sr"
  and      al: "is_aligned (ctcb_ptr_to_tcb_ptr p) (objBitsKO kotcb)"
  and ptr0: "ctcb_ptr_to_tcb_ptr p \<noteq> 0"
  and ptrlb: "2^ctcb_size_bits \<le> ptr_val p"
  and vq:  "valid_queues \<sigma>"
  and pal: "pspace_aligned' (\<sigma>\<lparr>ksPSpace := ks\<rparr>)"
  and pno: "pspace_no_overlap' (ctcb_ptr_to_tcb_ptr p) (objBitsKO kotcb) (\<sigma>\<lparr>ksPSpace := ks\<rparr>)"
  and pds: "pspace_distinct' (\<sigma>\<lparr>ksPSpace := ks\<rparr>)"
  and symref: "sym_refs (state_refs_of' (\<sigma>\<lparr>ksPSpace := ks\<rparr>))"
  and kssub: "dom (ksPSpace \<sigma>) \<subseteq> dom ks"
  and rzo: "ret_zero (ctcb_ptr_to_tcb_ptr p) (2 ^ objBitsKO kotcb) \<sigma>"
  and empty: "region_is_bytes (ctcb_ptr_to_tcb_ptr p) (2 ^ tcbBlockSizeBits) x"
  and rep0:  "heap_list (fst (t_hrs_' (globals x))) (2 ^ tcbBlockSizeBits) (ctcb_ptr_to_tcb_ptr p) = replicate (2 ^ tcbBlockSizeBits) 0"
  and kdr: "{ctcb_ptr_to_tcb_ptr p..+2 ^ tcbBlockSizeBits} \<inter> kernel_data_refs = {}"
  shows "(\<sigma>\<lparr>ksPSpace := ks(ctcb_ptr_to_tcb_ptr p \<mapsto> kotcb)\<rparr>,
     globals_update
      (t_hrs_'_update
        (\<lambda>a. hrs_mem_update (heap_update (Ptr &(p\<rightarrow>[''tcbTimeSlice_C'']) :: machine_word ptr) (5 :: machine_word))
              (hrs_mem_update
                (heap_update ((Ptr &((Ptr &((Ptr &(p\<rightarrow>[''tcbArch_C'']) :: arch_tcb_C ptr)\<rightarrow>[''tcbContext_C''])
                     :: user_context_C ptr)\<rightarrow>[''registers_C''])) :: (word32[20]) ptr)
                  (Arrays.update (h_val (hrs_mem a) ((Ptr &((Ptr &((Ptr &(p\<rightarrow>[''tcbArch_C'']) :: arch_tcb_C ptr)\<rightarrow>[''tcbContext_C''])
                       :: user_context_C ptr)\<rightarrow>[''registers_C''])) :: (word32[20]) ptr)) (unat Kernel_C.CPSR) (0x150 :: word32)))
                   (hrs_htd_update (\<lambda>xa. ptr_retyps_gen 1 (Ptr (ctcb_ptr_to_tcb_ptr p) :: (cte_C[5]) ptr) False
                       (ptr_retyps_gen 1 p False xa)) a)))) x)
             \<in> rf_sr"
  (is "(\<sigma>\<lparr>ksPSpace := ?ks\<rparr>, globals_update ?gs' x) \<in> rf_sr")

proof -
  define ko where "ko \<equiv> (KOCTE (makeObject :: cte))"
  let ?ptr = "cte_Ptr (ctcb_ptr_to_tcb_ptr p)"
  let ?arr_ptr = "Ptr (ctcb_ptr_to_tcb_ptr p) :: (cte_C[5]) ptr"
  let ?sp = "\<sigma>\<lparr>ksPSpace := ks\<rparr>"
  let ?s = "\<sigma>\<lparr>ksPSpace := ?ks\<rparr>"
  let ?gs = "?gs' (globals x)"
  let ?hp = "(fst (t_hrs_' ?gs), (ptr_retyps_gen 1 p False (snd (t_hrs_' (globals x)))))"

  note tcb_C_size[simp del]

  from al have cover: "range_cover (ctcb_ptr_to_tcb_ptr p) (objBitsKO kotcb)
        (objBitsKO kotcb) (Suc 0)"
    by (rule range_cover_full, simp_all add: al)

  have "\<forall>n<2 ^ (objBitsKO kotcb - objBitsKO ko). c_guard (CTypesDefs.ptr_add ?ptr (of_nat n))"
    apply (rule retype_guard_helper [where m = 2])
        apply (rule range_cover_rel[OF cover, rotated])
         apply simp
        apply (simp add: ko_def objBits_simps' kotcb_def)
       apply (rule ptr0)
      apply (simp add: ko_def objBits_simps' size_of_def)
     apply (simp add: ko_def objBits_simps')
    apply (simp add: ko_def objBits_simps align_of_def)
    done
  hence guard: "\<forall>n<5. c_guard (CTypesDefs.ptr_add ?ptr (of_nat n))"
    by (simp add: ko_def kotcb_def objBits_simps' align_of_def)

  have arr_guard: "c_guard ?arr_ptr"
    apply (rule is_aligned_c_guard[where m=2], simp, rule al)
       apply (simp add: ptr0)
      apply (simp add: align_of_def align_td_array)
     apply (simp add: cte_C_size objBits_simps' kotcb_def)
    apply (simp add: kotcb_def objBits_simps')
    done

  have heap_update_to_hrs_mem_update:
    "\<And>p x hp ht. (heap_update p x hp, ht) = hrs_mem_update (heap_update p x) (hp, ht)"
    by (simp add: hrs_mem_update_def split_def)

  have empty_smaller:
    "region_is_bytes (ptr_val p) (size_of TYPE(tcb_C)) x"
    "region_is_bytes' (ctcb_ptr_to_tcb_ptr p) (5 * size_of TYPE(cte_C))
        (ptr_retyps_gen 1 p False (hrs_htd (t_hrs_' (globals x))))"
     using al region_is_bytes_subset[OF empty] tcb_ptr_to_ctcb_ptr_in_range'
     apply (simp add: objBits_simps kotcb_def)
    apply (clarsimp simp: region_is_bytes'_def)
    apply (subst(asm) ptr_retyps_gen_out)
     apply (clarsimp simp: ctcb_ptr_to_tcb_ptr_def ctcb_offset_defs intvl_def)
     apply (simp add: unat_arith_simps unat_of_nat cte_C_size tcb_C_size
               split: if_split_asm)
    apply (subst(asm) empty[unfolded region_is_bytes'_def], simp_all)
    apply (erule subsetD[rotated], rule intvl_start_le)
    apply (simp add: cte_C_size objBits_defs)
    done

  note htd[simp] = hrs_htd_update_htd_update[unfolded o_def,
        where d="ptr_retyps_gen n p a" and d'="ptr_retyps_gen n' p' a'"
        for n p a n' p' a', symmetric]

  have cgp: "c_guard p" using al
    apply -
    apply (rule c_guard_tcb [OF _ ptr0])
    apply (simp add: kotcb_def objBits_simps)
    done

  have "ptr_val p = ctcb_ptr_to_tcb_ptr p + ctcb_offset"
    by (simp add: ctcb_ptr_to_tcb_ptr_def)

  have cl_cte: "(cslift (x\<lparr>globals := ?gs\<rparr>) :: cte_C typ_heap) =
    (\<lambda>y. if y \<in> (CTypesDefs.ptr_add (cte_Ptr (ctcb_ptr_to_tcb_ptr p)) \<circ>
                 of_nat) `
                {k. k < 5}
         then Some (from_bytes (replicate (size_of TYPE(cte_C)) 0)) else cslift x y)"
    using cgp
    apply (simp add: ptr_retyp_to_array[simplified] hrs_comm[symmetric])
    apply (subst clift_ptr_retyps_gen_prev_memset_same[OF guard],
           simp_all add: hrs_htd_update empty_smaller[simplified])
      apply (simp add: cte_C_size word_bits_def)
     apply (simp add: hrs_mem_update typ_heap_simps
                      packed_heap_update_collapse)
     apply (simp add: heap_update_def)
     apply (subst heap_list_update_disjoint_same)
      apply (clarsimp simp: ctcb_ptr_to_tcb_ptr_def ctcb_offset_defs intvl_def
                            set_eq_iff)
      apply (simp add: unat_arith_simps unat_of_nat cte_C_size tcb_C_size)
     apply (subst take_heap_list_le[symmetric])
      prefer 2
      apply (simp add: hrs_mem_def, subst rep0)
      apply (simp only: take_replicate, simp add: cte_C_size objBits_defs)
     apply (simp add: cte_C_size objBits_defs)
    apply (simp add: fun_eq_iff
              split: if_split)
    apply (simp add: hrs_comm packed_heap_update_collapse
                     typ_heap_simps)
    apply (subst clift_heap_update_same_td_name, simp_all,
      simp add: hrs_htd_update ptr_retyps_gen_def ptr_retyp_h_t_valid)+
    apply (subst clift_ptr_retyps_gen_other,
      simp_all add: empty_smaller tag_disj_via_td_name)
    apply (simp add: tcb_C_size word_bits_def)
    done

  have tcb0: "heap_list (fst (t_hrs_' (globals x))) (size_of TYPE(tcb_C)) (ptr_val p) = replicate (size_of TYPE(tcb_C)) 0"
  proof -
    have "heap_list (fst (t_hrs_' (globals x))) (size_of TYPE(tcb_C)) (ptr_val p)
      = take (size_of TYPE(tcb_C))
             (drop (unat (ptr_val p - ctcb_ptr_to_tcb_ptr p))
                   (heap_list (fst (t_hrs_' (globals x))) (2 ^ tcbBlockSizeBits) (ctcb_ptr_to_tcb_ptr p)))"
      by (simp add: drop_heap_list_le take_heap_list_le size_of_def ctcb_ptr_to_tcb_ptr_def
                    ctcb_offset_defs objBits_defs)
    also have "\<dots> = replicate (size_of TYPE(tcb_C)) 0"
      apply (subst rep0)
      apply (simp only: take_replicate drop_replicate)
      apply (rule arg_cong [where f = "\<lambda>x. replicate x 0"])
      apply (clarsimp simp: ctcb_ptr_to_tcb_ptr_def ctcb_offset_defs size_of_def objBits_defs)
      done
    finally show "heap_list (fst (t_hrs_' (globals x))) (size_of TYPE(tcb_C)) (ptr_val p) = replicate (size_of TYPE(tcb_C)) 0" .
  qed

  let ?new_tcb =  "(from_bytes (replicate (size_of TYPE(tcb_C)) 0)
                  \<lparr>tcbArch_C := tcbArch_C (from_bytes (replicate (size_of TYPE(tcb_C)) 0))
                    \<lparr>tcbContext_C := tcbContext_C (tcbArch_C (from_bytes (replicate (size_of TYPE(tcb_C)) 0)))
                     \<lparr>registers_C :=
                        Arrays.update (registers_C (tcbContext_C (tcbArch_C (from_bytes (replicate (size_of TYPE(tcb_C)) 0))))) (unat Kernel_C.CPSR)
                         0x150\<rparr>\<rparr>, tcbTimeSlice_C := 5\<rparr>)"

  have "ptr_retyp p (snd (t_hrs_' (globals x))) \<Turnstile>\<^sub>t p" using cgp
    by (rule ptr_retyp_h_t_valid)
  hence "clift (hrs_mem (t_hrs_' (globals x)), ptr_retyp p (snd (t_hrs_' (globals x)))) p
    = Some (from_bytes (replicate (size_of TYPE(tcb_C)) 0))"
    by (simp add: lift_t_if h_val_def tcb0 hrs_mem_def)
  hence cl_tcb: "(cslift (x\<lparr>globals := ?gs\<rparr>) :: tcb_C typ_heap) = (cslift x)(p \<mapsto> ?new_tcb)"
    using cgp
    apply (clarsimp simp add: typ_heap_simps
                              hrs_mem_update packed_heap_update_collapse_hrs)
    apply (simp add: hrs_comm[symmetric])
    apply (subst clift_ptr_retyps_gen_other, simp_all add: hrs_htd_update
      empty_smaller[simplified] tag_disj_via_td_name)
     apply (simp add: cte_C_size word_bits_def)
    apply (simp add: hrs_comm typ_heap_simps ptr_retyps_gen_def
                     hrs_htd_update ptr_retyp_h_t_valid
                     h_val_heap_update)
    apply (simp add: h_val_field_from_bytes)
    apply (simp add: h_val_def tcb0[folded hrs_mem_def])
    apply (rule ext, rename_tac p')
    apply (case_tac "p' = p", simp_all)
    apply (cut_tac clift_ptr_retyps_gen_prev_memset_same[where n=1 and arr=False, simplified,
      OF _ empty_smaller(1) _ refl], simp_all add: tcb0[folded hrs_mem_def])
     apply (simp add: ptr_retyps_gen_def)
    apply (simp add: tcb_C_size word_bits_def)
    done

  have cl_rest:
    "\<lbrakk>typ_uinfo_t TYPE(tcb_C) \<bottom>\<^sub>t typ_uinfo_t TYPE('a :: mem_type);
      typ_uinfo_t TYPE(cte_C[5]) \<bottom>\<^sub>t typ_uinfo_t TYPE('a :: mem_type);
      typ_uinfo_t TYPE('a) \<noteq> typ_uinfo_t TYPE(word8) \<rbrakk> \<Longrightarrow>
    cslift (x\<lparr>globals := ?gs\<rparr>) = (cslift x :: 'a :: mem_type typ_heap)"
    using cgp
    apply (clarsimp simp: hrs_comm[symmetric])
    apply (subst clift_ptr_retyps_gen_other,
      simp_all add: hrs_htd_update empty_smaller[simplified],
      simp_all add: cte_C_size tcb_C_size word_bits_def)
    apply (simp add: hrs_comm ptr_retyps_gen_def)
    apply (simp add: clift_heap_update_same hrs_htd_update ptr_retyp_h_t_valid typ_heap_simps)
    apply (rule trans[OF _ clift_ptr_retyps_gen_other[where nptrs=1 and arr=False,
        simplified, OF empty_smaller(1)]], simp_all)
     apply (simp add: ptr_retyps_gen_def)
    apply (simp add: tcb_C_size word_bits_def)
    done

  have rl:
    "(\<forall>v :: 'a :: pre_storable. projectKO_opt kotcb \<noteq> Some v) \<Longrightarrow>
    (projectKO_opt \<circ>\<^sub>m (ks(ctcb_ptr_to_tcb_ptr p \<mapsto> KOTCB makeObject)) :: word32 \<Rightarrow> 'a option)
    = projectKO_opt \<circ>\<^sub>m ks" using pno al
    apply -
    apply (drule(2) projectKO_opt_retyp_other'[OF _ _ pal])
    apply (simp add: kotcb_def)
    done

  have rl_tcb: "(projectKO_opt \<circ>\<^sub>m (ks(ctcb_ptr_to_tcb_ptr p \<mapsto> KOTCB makeObject)) :: word32 \<Rightarrow> tcb option)
    = (projectKO_opt \<circ>\<^sub>m ks)(ctcb_ptr_to_tcb_ptr p \<mapsto> makeObject)"
    apply (rule ext)
    apply (clarsimp simp: projectKOs map_comp_def split: if_split)
    done

  have mko: "\<And>dev. makeObjectKO dev (Inr (APIObjectType ArchTypes_H.apiobject_type.TCBObject)) = Some kotcb"
    by (simp add: makeObjectKO_def kotcb_def)
  note hacky_cte = retype_ctes_helper [where sz = "objBitsKO kotcb" and ko = kotcb and ptr = "ctcb_ptr_to_tcb_ptr p",
    OF pal pds pno al _ _ mko, simplified new_cap_addrs_def, simplified]

  \<comment> \<open>Ugh\<close>
  moreover have
    "\<And>y. y \<in> ptr_val ` (CTypesDefs.ptr_add (cte_Ptr (ctcb_ptr_to_tcb_ptr p)) \<circ> of_nat) ` {k. k < 5}
      = (y && ~~ mask tcbBlockSizeBits = ctcb_ptr_to_tcb_ptr p \<and> y && mask tcbBlockSizeBits \<in> dom tcb_cte_cases)"
    (is "\<And>y. ?LHS y = ?RHS y")
  proof -
    fix y

    have al_rl: "\<And>k. k < 5 \<Longrightarrow>
      ctcb_ptr_to_tcb_ptr p + of_nat k * of_nat (size_of TYPE(cte_C)) && mask tcbBlockSizeBits = of_nat k * of_nat (size_of TYPE(cte_C))
      \<and> ctcb_ptr_to_tcb_ptr p + of_nat k * of_nat (size_of TYPE(cte_C)) && ~~ mask tcbBlockSizeBits = ctcb_ptr_to_tcb_ptr p" using al
      apply -
      apply (rule is_aligned_add_helper)
      apply (simp add: objBits_simps kotcb_def)
       apply (subst Abs_fnat_hom_mult)
       apply (subst word_less_nat_alt)
       apply (subst unat_of_nat32)
       apply (simp add: size_of_def word_bits_conv objBits_defs)+
      done

    have al_rl2: "\<And>k. k < 5 \<Longrightarrow> unat (of_nat k * of_nat (size_of TYPE(cte_C)) :: word32) = k * 2^cteSizeBits"
       apply (subst Abs_fnat_hom_mult)
       apply (subst unat_of_nat32)
       apply (simp add: size_of_def word_bits_conv objBits_defs)+
       done

    show "?LHS y = ?RHS y" using al
      apply (simp add: image_image kotcb_def objBits_simps)
      apply rule
       apply (clarsimp simp: dom_tcb_cte_cases_iff al_rl al_rl2)
       apply (simp add: objBits_defs)
      apply (clarsimp simp: dom_tcb_cte_cases_iff al_rl al_rl2)
      apply (rule_tac x = ya in image_eqI)
       apply (rule mask_eqI [where n = tcbBlockSizeBits])
        apply (subst unat_arith_simps(3))
      apply (simp add: al_rl al_rl2, simp add: objBits_defs)+
      done
  qed

  ultimately have rl_cte: "(map_to_ctes (ks(ctcb_ptr_to_tcb_ptr p \<mapsto> KOTCB makeObject)) :: word32 \<Rightarrow> cte option)
    = (\<lambda>x. if x \<in> ptr_val ` (CTypesDefs.ptr_add (cte_Ptr (ctcb_ptr_to_tcb_ptr p)) \<circ> of_nat) ` {k. k < 5}
         then Some (CTE NullCap nullMDBNode)
         else map_to_ctes ks x)"
    apply simp
    apply (drule_tac x = "Suc 0" in meta_spec)
    apply clarsimp
    apply (erule impE[OF impI])
     apply (rule range_cover_full[OF al])
     apply (simp add: objBits_simps' word_bits_conv pageBits_def archObjSize_def pdeBits_def pteBits_def
       split:kernel_object.splits arch_kernel_object.splits)
    apply (simp add: fun_upd_def kotcb_def cong: if_cong)
    done

  let ?tcb = "undefined
    \<lparr>tcbArch_C := tcbArch_C undefined
     \<lparr>tcbContext_C := tcbContext_C (tcbArch_C undefined)
       \<lparr>registers_C :=
          foldr (\<lambda>n arr. Arrays.update arr n 0) [0..<20]
           (registers_C (tcbContext_C (tcbArch_C undefined)))\<rparr>\<rparr>,
       tcbState_C :=
         thread_state_C.words_C_update
          (\<lambda>_. foldr (\<lambda>n arr. Arrays.update arr n 0) [0..<3]
                (thread_state_C.words_C (tcbState_C undefined)))
          (tcbState_C undefined),
       tcbFault_C :=
         seL4_Fault_C.words_C_update
          (\<lambda>_. foldr (\<lambda>n arr. Arrays.update arr n 0) [0..<2]
                (seL4_Fault_C.words_C (tcbFault_C undefined)))
          (tcbFault_C undefined),
       tcbLookupFailure_C :=
         lookup_fault_C.words_C_update
          (\<lambda>_. foldr (\<lambda>n arr. Arrays.update arr n 0) [0..<2]
                (lookup_fault_C.words_C (tcbLookupFailure_C undefined)))
          (tcbLookupFailure_C undefined),
       tcbPriority_C := 0, tcbMCP_C := 0, tcbDomain_C := 0, tcbTimeSlice_C := 0,
       tcbFaultHandler_C := 0, tcbIPCBuffer_C := 0,
       tcbSchedNext_C := tcb_Ptr 0, tcbSchedPrev_C := tcb_Ptr 0,
       tcbEPNext_C := tcb_Ptr 0, tcbEPPrev_C := tcb_Ptr 0,
       tcbBoundNotification_C := ntfn_Ptr 0\<rparr>"
  have fbtcb: "from_bytes (replicate (size_of TYPE(tcb_C)) 0) = ?tcb"
    apply (simp add: from_bytes_def)
    apply (simp add: typ_info_simps tcb_C_tag_def)
    apply (simp add: ti_typ_pad_combine_empty_ti ti_typ_pad_combine_td align_of_def padup_def
      final_pad_def size_td_lt_ti_typ_pad_combine Let_def size_of_def)(* takes ages *)
    apply (simp add: update_ti_adjust_ti update_ti_t_word32_0s
      typ_info_simps
      user_context_C_tag_def thread_state_C_tag_def seL4_Fault_C_tag_def
      lookup_fault_C_tag_def update_ti_t_ptr_0s arch_tcb_C_tag_def
      ti_typ_pad_combine_empty_ti ti_typ_pad_combine_td
      align_of_def padup_def
      final_pad_def size_td_lt_ti_typ_pad_combine Let_def size_of_def
      align_td_array' size_td_array)
    apply (simp add: update_ti_t_array_rep_word0)
    done

  have tcb_rel:
    "ctcb_relation makeObject ?new_tcb"
    unfolding ctcb_relation_def makeObject_tcb
    apply (simp add: fbtcb minBound_word)
    apply (intro conjI)
    apply (simp add: cthread_state_relation_def thread_state_lift_def
      eval_nat_numeral ThreadState_Inactive_def)
    apply (simp add: ccontext_relation_def carch_tcb_relation_def)
    apply rule
    apply (case_tac r, simp_all add: "StrictC'_register_defs" eval_nat_numeral atcbContext_def newArchTCB_def newContext_def initContext_def)[1] \<comment> \<open>takes ages\<close>
    apply (simp add: thread_state_lift_def eval_nat_numeral atcbContextGet_def)+
    apply (simp add: timeSlice_def)
    apply (simp add: cfault_rel_def seL4_Fault_lift_def seL4_Fault_get_tag_def Let_def
      lookup_fault_lift_def lookup_fault_get_tag_def lookup_fault_invalid_root_def
      eval_nat_numeral seL4_Fault_NullFault_def option_to_ptr_def option_to_0_def
      split: if_split)+
    done

  have pks: "ks (ctcb_ptr_to_tcb_ptr p) = None"
    by (rule pspace_no_overlap_base' [OF pal pno al, simplified])

  have ep1 [simplified]: "\<And>p' list. map_to_eps (ksPSpace ?sp) p' = Some (Structures_H.endpoint.RecvEP list)
       \<Longrightarrow> ctcb_ptr_to_tcb_ptr p \<notin> set list"
    using symref pks pal pds
    apply -
    apply (frule map_to_ko_atI2)
      apply simp
     apply simp
    apply (drule (1) sym_refs_ko_atD')
    apply clarsimp
    apply (drule (1) bspec)
    apply (simp add: ko_wp_at'_def)
    done

  have ep2 [simplified]: "\<And>p' list. map_to_eps (ksPSpace ?sp) p' = Some (Structures_H.endpoint.SendEP list)
       \<Longrightarrow> ctcb_ptr_to_tcb_ptr p \<notin> set list"
    using symref pks pal pds
    apply -
    apply (frule map_to_ko_atI2)
      apply simp
     apply simp
    apply (drule (1) sym_refs_ko_atD')
    apply clarsimp
    apply (drule (1) bspec)
    apply (simp add: ko_wp_at'_def)
    done

  have ep3 [simplified]: "\<And>p' list boundTCB. map_to_ntfns (ksPSpace ?sp) p' = Some (Structures_H.notification.NTFN (Structures_H.ntfn.WaitingNtfn list) boundTCB)
       \<Longrightarrow> ctcb_ptr_to_tcb_ptr p \<notin> set list"
    using symref pks pal pds
    apply -
    apply (frule map_to_ko_atI2)
      apply simp
     apply simp
    apply (drule (1) sym_refs_ko_atD')
    apply clarsimp
    apply (drule_tac x="(ctcb_ptr_to_tcb_ptr p, NTFNSignal)" in bspec, simp)
    apply (simp add: ko_wp_at'_def)
    done

  have pks': "ksPSpace \<sigma> (ctcb_ptr_to_tcb_ptr p) = None" using pks kssub
    apply -
    apply (erule contrapos_pp)
    apply (fastforce simp: dom_def)
    done

  hence kstcb: "\<And>qdom prio. ctcb_ptr_to_tcb_ptr p \<notin> set (ksReadyQueues \<sigma> (qdom, prio))" using vq
    apply (clarsimp simp add: valid_queues_def valid_queues_no_bitmap_def)
    apply (drule_tac x = qdom in spec)
    apply (drule_tac x = prio in spec)
    apply clarsimp
    apply (drule (1) bspec)
    apply (simp add: obj_at'_def)
    done

  have ball_subsetE:
    "\<And>P S R. \<lbrakk> \<forall>x \<in> S. P x; R \<subseteq> S \<rbrakk> \<Longrightarrow> \<forall>x \<in> R. P x"
    by blast

  have htd_safe:
    "htd_safe (- kernel_data_refs) (hrs_htd (t_hrs_' (globals x)))
        \<Longrightarrow> htd_safe (- kernel_data_refs) (hrs_htd (t_hrs_' ?gs))"
    using kdr
    apply (simp add: hrs_htd_update)
    apply (intro ptr_retyp_htd_safe_neg ptr_retyps_htd_safe_neg, simp_all)
     apply (erule disjoint_subset[rotated])
     apply (simp add: ctcb_ptr_to_tcb_ptr_def size_of_def)
     apply (rule intvl_sub_offset[where k="ptr_val p - ctcb_offset" and x="ctcb_offset", simplified])
     apply (simp add: ctcb_offset_defs objBits_defs)
    apply (erule disjoint_subset[rotated])
    apply (rule intvl_start_le)
    apply (simp add: size_of_def objBits_defs)
    done

  have zro:
    "zero_ranges_are_zero (gsUntypedZeroRanges \<sigma>) (t_hrs_' (globals x))"
    using rfsr
    by (clarsimp simp: rf_sr_def cstate_relation_def Let_def)

  have h_t_valid_p:
    "h_t_valid (hrs_htd (t_hrs_' ?gs)) c_guard p"
    using fun_cong[OF cl_tcb, where x=p]
    by (clarsimp dest!: h_t_valid_clift)

  have zro':
    "zero_ranges_are_zero (gsUntypedZeroRanges \<sigma>) (t_hrs_' ?gs)"
    using zro h_t_valid_p rzo al
    apply clarsimp
    apply (simp add: hrs_htd_update typ_heap_simps')
    apply (intro zero_ranges_ptr_retyps, simp_all)
     apply (erule caps_overlap_reserved'_subseteq)
     apply (rule order_trans, rule tcb_ptr_to_ctcb_ptr_in_range')
      apply (simp add: objBits_simps kotcb_def)
     apply (simp add: objBits_simps kotcb_def)
    apply (erule caps_overlap_reserved'_subseteq)
    apply (rule intvl_start_le)
    apply (simp add: cte_C_size kotcb_def objBits_simps')
    done

  note ht_rest = clift_eq_h_t_valid_eq[OF cl_rest, simplified]

  note irq = h_t_valid_eq_array_valid[where p=intStateIRQNode_array_Ptr]
    h_t_array_valid_ptr_retyps_gen[where n=1, simplified, OF refl empty_smaller(1)]
    h_t_array_valid_ptr_retyps_gen[where p="Ptr x" for x, simplified, OF refl empty_smaller(2)]

  from rfsr have "cpspace_relation ks (underlying_memory (ksMachineState \<sigma>)) (t_hrs_' (globals x))"
    unfolding rf_sr_def cstate_relation_def by (simp add: Let_def)
  hence "cpspace_relation ?ks (underlying_memory (ksMachineState \<sigma>))  (t_hrs_' ?gs)"
    unfolding cpspace_relation_def
    apply -
    apply (simp add: cl_cte [simplified] cl_tcb [simplified] cl_rest [simplified] tag_disj_via_td_name
                     ht_rest)
    apply (simp add: rl kotcb_def projectKOs rl_tcb rl_cte)
    apply (elim conjE)
    apply (intro conjI)
     \<comment> \<open>cte\<close>
     apply (erule cmap_relation_retype2)
     apply (simp add:ccte_relation_nullCap nullMDBNode_def nullPointer_def)
    \<comment> \<open>tcb\<close>
     apply (erule cmap_relation_updI2 [where dest = "ctcb_ptr_to_tcb_ptr p" and f = "tcb_ptr_to_ctcb_ptr", simplified])
     apply (rule map_comp_simps)
     apply (rule pks)
     apply (rule tcb_rel)
    \<comment> \<open>ep\<close>
     apply (erule iffD2 [OF cmap_relation_cong, OF refl refl, rotated -1])
     apply (simp add: cendpoint_relation_def Let_def)
     apply (subst endpoint.case_cong)
       apply (rule refl)
      apply (simp add: tcb_queue_update_other' ep1)
     apply (simp add: tcb_queue_update_other' del: tcb_queue_relation'_empty)
    apply (simp add: tcb_queue_update_other' ep2)
   apply clarsimp
  \<comment> \<open>ntfn\<close>
   apply (erule iffD2 [OF cmap_relation_cong, OF refl refl, rotated -1])
   apply (simp add: cnotification_relation_def Let_def)
     apply (subst ntfn.case_cong)
      apply (rule refl)
     apply (simp add: tcb_queue_update_other' del: tcb_queue_relation'_empty)
    apply (simp add: tcb_queue_update_other' del: tcb_queue_relation'_empty)
   apply (case_tac a, simp add: tcb_queue_update_other' ep3)
  apply (clarsimp simp: typ_heap_simps)
  done

  moreover have "cte_array_relation \<sigma> ?gs
    \<and> tcb_cte_array_relation ?s ?gs"
    using rfsr
    apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def
                          hrs_htd_update map_comp_update
                          kotcb_def projectKO_opt_tcb)
    apply (intro cvariable_array_ptr_upd conjI
                 cvariable_array_ptr_retyps[OF refl, where n=1, simplified],
           simp_all add: empty_smaller[simplified])
    apply (simp add: ptr_retyps_gen_def)
    apply (rule ptr_retyp_h_t_valid[where g=c_guard, OF arr_guard,
        THEN h_t_array_valid, simplified])
    done

  ultimately show ?thesis
    using rfsr zro'
    apply (simp add: rf_sr_def cstate_relation_def Let_def h_t_valid_clift_Some_iff
      tag_disj_via_td_name carch_state_relation_def cmachine_state_relation_def irq)
    apply (simp add: cl_cte [simplified] cl_tcb [simplified] cl_rest [simplified] tag_disj_via_td_name)
    apply (clarsimp simp add: cready_queues_relation_def Let_def
                              htd_safe[simplified] kernel_data_refs_domain_eq_rotate)
    apply (simp add: kstcb tcb_queue_update_other' hrs_htd_update
                     ptr_retyp_to_array[simplified] irq[simplified])
    done
qed

lemma ps_clear_subset:
  assumes pd: "ps_clear x (objBitsKO ko) (s' \<lparr>ksPSpace := (\<lambda>x. if x \<in> as then Some (f x) else ksPSpace s' x) \<rparr>)"
  and    sub: "as' \<subseteq> as"
  and     al: "is_aligned x (objBitsKO ko)"
  shows  "ps_clear x (objBitsKO ko) (s' \<lparr>ksPSpace := (\<lambda>x. if x \<in> as' then Some (f x) else ksPSpace s' x) \<rparr>)"
  using al pd sub
  apply -
  apply (simp add: ps_clear_def3 [OF al objBitsKO_gt_0] dom_if_Some)
  apply (erule disjoint_subset2 [rotated])
  apply fastforce
  done

lemma cslift_bytes_mem_update:
  fixes x :: cstate and sz and ptr
  defines "x' \<equiv> x\<lparr>globals := globals x
                       \<lparr>t_hrs_' := hrs_mem_update (heap_update_list ptr (replicate sz 0)) (t_hrs_' (globals x))\<rparr>\<rparr>"
  assumes bytes: "region_is_bytes ptr sz x"
  assumes not_byte: "typ_uinfo_t TYPE ('a) \<noteq> typ_uinfo_t TYPE (word8)"
  shows "(cslift x' :: ('a :: mem_type) ptr \<Rightarrow> _)
     = clift (fst (t_hrs_' (globals x)), snd (t_hrs_' (globals x)))"
  using bytes
  apply (unfold region_is_bytes'_def)
  apply (rule ext)
  apply (simp only: lift_t_if hrs_mem_update_def split_def x'_def)
  apply (simp add: lift_t_if hrs_mem_update_def split_def)
  apply (clarsimp simp: h_val_def split: if_split)
  apply (subst heap_list_update_disjoint_same)
   apply simp
   apply (rule disjointI)
   apply clarsimp
   apply (drule (1) bspec)
   apply (frule (1) h_t_valid_intvl_htd_contains_uinfo_t)
   apply (clarsimp simp: hrs_htd_def not_byte)
  apply simp
  done

lemma heap_list_eq_replicate_eq_eq:
  "(heap_list hp n ptr = replicate n v)
    = (\<forall>p \<in> {ptr ..+ n}. hp p = v)"
  by (induct n arbitrary: ptr, simp_all add: intvl_Suc_right)

lemma heap_update_list_replicate_eq:
  "(heap_update_list x (replicate n v) hp y)
    = (if y \<in> {x ..+ n} then v else hp y)"
  apply (induct n arbitrary: x hp, simp_all add: intvl_Suc_right)
  apply (simp split: if_split)
  done

lemma zero_ranges_are_zero_update_zero[simp]:
  "zero_ranges_are_zero rs hrs
    \<Longrightarrow> zero_ranges_are_zero rs (hrs_mem_update (heap_update_list ptr (replicate n 0)) hrs)"
  apply (clarsimp simp: zero_ranges_are_zero_def hrs_mem_update)
  apply (drule(1) bspec)
  apply (clarsimp simp: heap_list_eq_replicate_eq_eq heap_update_list_replicate_eq)
  done

lemma rf_sr_rep0:
  assumes sr: "(\<sigma>, x) \<in> rf_sr"
  assumes empty: "region_is_bytes ptr sz x"
  shows "(\<sigma>, globals_update (t_hrs_'_update (hrs_mem_update (heap_update_list ptr (replicate sz 0)))) x) \<in> rf_sr"
  using sr
  by (clarsimp simp add: rf_sr_def cstate_relation_def Let_def cpspace_relation_def
        carch_state_relation_def cmachine_state_relation_def
        cslift_bytes_mem_update[OF empty, simplified] cte_C_size)

lemma mapM_x_storeWord:
  assumes al: "is_aligned ptr 2"
  shows "mapM_x (\<lambda>x. storeWord (ptr + of_nat x * 4) 0) [0..<n]
  = modify (underlying_memory_update (\<lambda>m x. if x \<in> {ptr..+ n * 4} then 0 else m x))"
proof (induct n)
  case 0
  thus ?case
    apply (rule ext)
    apply (simp add: mapM_x_mapM mapM_def sequence_def
      modify_def get_def put_def bind_def return_def)
    done
next
  case (Suc n')

  have funs_eq:
    "\<And>m x. (if x \<in> {ptr..+4 + n' * 4} then 0 else (m x :: word8)) =
           ((\<lambda>xa. if xa \<in> {ptr..+n' * 4} then 0 else m xa)
           (ptr + of_nat n' * 4 := word_rsplit (0 :: word32) ! 3,
            ptr + of_nat n' * 4 + 1 := word_rsplit (0 :: word32) ! 2,
            ptr + of_nat n' * 4 + 2 := word_rsplit (0 :: word32) ! Suc 0,
            ptr + of_nat n' * 4 + 3 := word_rsplit (0 :: word32) ! 0)) x"
  proof -
    fix m x

    have xin': "\<And>x. (x < 4 + n' * 4) = (x < n' * 4 \<or> x = n' * 4
                     \<or> x = (n' * 4) + 1 \<or> x = (n' * 4) + 2 \<or> x = (n' * 4) + 3)"
      by (safe, simp_all)

    have xin: "x \<in> {ptr..+4 + n' * 4} = (x \<in> {ptr..+n' * 4} \<or> x = ptr + of_nat n' * 4 \<or>
      x = ptr + of_nat n' * 4 + 1 \<or> x = ptr + of_nat n' * 4 + 2 \<or> x = ptr + of_nat n' * 4 + 3)"
      by (simp add: intvl_def xin' conj_disj_distribL
                    ex_disj_distrib field_simps)

    show "?thesis m x"
      apply (simp add: xin word_rsplit_0 cong: if_cong)
      apply (simp split: if_split)
      done
  qed

  from al have "is_aligned (ptr + of_nat n' * 4) 2"
    apply (rule aligned_add_aligned)
    apply (rule is_aligned_mult_triv2 [where n = 2, simplified])
    apply (simp add: word_bits_conv)+
    done

  thus ?case
    apply (simp add: mapM_x_append bind_assoc Suc.hyps mapM_x_singleton)
    apply (simp add: storeWord_def assert_def is_aligned_mask modify_modify comp_def)
    apply (simp only: funs_eq)
    done
qed

lemma mapM_x_storeWord_step:
  assumes al: "is_aligned ptr sz"
  and    sz2: "2 \<le> sz"
  and     sz: "sz < word_bits"
  shows "mapM_x (\<lambda>p. storeWord p 0) [ptr , ptr + 4 .e. ptr + 2 ^ sz - 1] =
  modify (underlying_memory_update (\<lambda>m x. if x \<in> {ptr..+2 ^ (sz - 2) * 4} then 0 else m x))"
  using al sz
  apply (simp only: upto_enum_step_def field_simps cong: if_cong)
  apply (subst if_not_P)
   apply (subst not_less)
   apply (erule is_aligned_no_overflow)
   apply (simp add: mapM_x_map comp_def upto_enum_word del: upt.simps)
   apply (subst div_power_helper_32 [OF sz2, simplified])
    apply assumption
   apply (simp add: word_bits_def unat_minus_one del: upt.simps)
   apply (subst mapM_x_storeWord)
   apply (erule is_aligned_weaken [OF _ sz2])
   apply (simp add: field_simps)
   done

lemma range_cover_bound_weak:
  "\<lbrakk>n \<noteq> 0;range_cover ptr sz us n\<rbrakk> \<Longrightarrow>
  ptr + (of_nat n * 2 ^ us - 1) \<le> (ptr && ~~ mask sz) + 2 ^ sz - 1"
 apply (frule range_cover_cell_subset[where x = "of_nat (n - 1)"])
  apply (simp add:range_cover_not_zero)
 apply (frule range_cover_subset_not_empty[rotated,where x = "of_nat (n - 1)"])
  apply (simp add:range_cover_not_zero)
 apply (clarsimp simp: field_simps)
 done

lemma pspace_no_overlap_underlying_zero:
  "pspace_no_overlap' ptr sz \<sigma>
    \<Longrightarrow> valid_machine_state' \<sigma>
    \<Longrightarrow> x \<in> {ptr .. (ptr && ~~ mask sz) + 2 ^ sz - 1}
    \<Longrightarrow> underlying_memory (ksMachineState \<sigma>) x = 0"
  using mask_in_range[where ptr'=x and bits=pageBits and ptr="x && ~~ mask pageBits"]
  apply (clarsimp simp: valid_machine_state'_def)
  apply (drule_tac x=x in spec, clarsimp simp: pointerInUserData_def)
  apply (clarsimp simp: typ_at'_def ko_wp_at'_def koTypeOf_eq_UserDataT)
  apply (case_tac "pointerInDeviceData x \<sigma>")
   apply (clarsimp simp: pointerInDeviceData_def
                         ko_wp_at'_def obj_at'_def projectKOs
                  dest!: device_data_at_ko)
   apply (drule(1) pspace_no_overlapD')
   apply (drule_tac x=x in eqset_imp_iff)
   apply (simp add: objBits_simps)
  apply clarsimp
  apply (drule(1) pspace_no_overlapD')
  apply (drule_tac x=x in eqset_imp_iff, simp)
  apply (simp add: objBits_simps)
  done

lemma range_cover_nca_neg: "\<And>x p (off :: 10 word).
  \<lbrakk>(x::word32) < 4; {p..+2 ^pageBits } \<inter> {ptr..ptr + (of_nat n * 2 ^ (gbits + pageBits) - 1)} = {};
    range_cover ptr sz (gbits + pageBits) n\<rbrakk>
  \<Longrightarrow> p + ucast off * 4 + x \<notin> {ptr..+n * 2 ^ (gbits + pageBits)}"
  apply (case_tac "n = 0")
   apply simp
  apply (subst range_cover_intvl,simp)
   apply simp
  apply (subgoal_tac "p + ucast off * 4 + x \<in>  {p..+2 ^ pageBits}")
   apply blast
  apply (clarsimp simp: intvl_def)
  apply (rule_tac x = "unat off * 4 + unat x" in exI)
  apply (simp add: ucast_nat_def)
  apply (rule nat_add_offset_less [where n = 2, simplified])
    apply (simp add: word_less_nat_alt)
   apply (rule unat_lt2p)
  apply (simp add: pageBits_def objBits_simps)
  done

lemma heap_to_device_data_disj_mdf:
  assumes rc: "range_cover ptr sz (gbits + pageBits) n"
  and ko_at: "ksPSpace \<sigma> a = Some obj"
  and obj_size: "objBitsKO obj = pageBits"
  and pal: "pspace_aligned' \<sigma>" and pdst: "pspace_distinct' \<sigma>"
  and pno: "pspace_no_overlap' ptr sz \<sigma>"
  and sz: "gbits + pageBits \<le> sz"
  and szb: "sz < word_bits"
  shows "(heap_to_device_data (ksPSpace \<sigma>)
          (\<lambda>x. if x \<in> {ptr..+n * 2 ^ (gbits + pageBits)} then 0 else underlying_memory (ksMachineState \<sigma>) x) a)
          = (heap_to_device_data (ksPSpace \<sigma>) (underlying_memory (ksMachineState \<sigma>)) a)"
  proof -
  from sz have "2 \<le> sz" by (simp add: objBits_simps pageBits_def)

  hence sz2: "2 ^ (sz - 2) * 4 = (2 :: nat) ^ sz"
    apply (subgoal_tac "(4 :: nat) = 2 ^ 2")
    apply (erule ssubst)
    apply (subst power_add [symmetric])
    apply (rule arg_cong [where f = "\<lambda>n. 2 ^ n"])
    apply simp
    apply simp
    done
  have p2dist: "n * (2::nat) ^ (gbits + pageBits) = n * 2 ^ gbits * 2 ^ pageBits" (is "?lhs = ?rhs")
    by (simp add: monoid_mult_class.power_add)
  show ?thesis
    apply (simp add: heap_to_device_data_def)
    apply (case_tac "n = 0")
     apply simp
    apply (subst map_option_byte_to_word_heap)
     apply (erule range_cover_nca_neg[OF _ _ rc])
     using range_cover_intvl[OF rc]
     apply (clarsimp simp add: heap_to_user_data_def Let_def
       byte_to_word_heap_def[abs_def] map_comp_Some_iff projectKOs)
     apply (cut_tac pspace_no_overlapD' [OF ko_at pno])
     apply (subst (asm) upto_intvl_eq [symmetric])
      apply (rule pspace_alignedD' [OF ko_at pal])
     apply (simp add: obj_size p2dist)
     apply (drule_tac B' = "{ptr..ptr + (of_nat n * 2 ^ (gbits + pageBits) - 1)}" in disjoint_subset2[rotated])
      apply (clarsimp simp: p2dist )
      apply (rule range_cover_bound_weak)
       apply simp
      apply (rule rc)
     apply simp
    apply simp
   done
qed

lemma pageBitsForSize_mess_multi:
  "4 * (2::nat) ^ (pageBitsForSize sz - 2) = 2^(pageBitsForSize sz)"
  apply (subgoal_tac "(4 :: nat) = 2 ^ 2")
  apply (erule ssubst)
  apply (subst power_add [symmetric])
  apply (rule arg_cong [where f = "\<lambda>n. 2 ^ n"])
  apply (case_tac sz,simp+)
  done

lemma createObjects_ccorres_user_data:
  defines "ko \<equiv> KOUserData"
  shows "\<forall>\<sigma> x. (\<sigma>, x) \<in> rf_sr \<and> range_cover ptr sz (gbits + pageBits) n
  \<and> ptr \<noteq> 0
  \<and> pspace_aligned' \<sigma> \<and> pspace_distinct' \<sigma>
  \<and> valid_machine_state' \<sigma>
  \<and> ret_zero ptr (n * 2 ^ (gbits + pageBits)) \<sigma>
  \<and> pspace_no_overlap' ptr sz \<sigma>
  \<and> region_is_zero_bytes ptr (n * 2 ^ (gbits + pageBits)) x
  \<and> {ptr ..+ n * (2 ^ (gbits + pageBits))} \<inter> kernel_data_refs = {}
  \<longrightarrow>
  (\<sigma>\<lparr>ksPSpace :=
               foldr (\<lambda>addr. data_map_insert addr KOUserData)
                  (new_cap_addrs (n * 2^gbits) ptr KOUserData) (ksPSpace \<sigma>)\<rparr>,
           x\<lparr>globals := globals x\<lparr>t_hrs_' :=
                      hrs_htd_update
                       (ptr_retyps_gen (n * 2 ^ gbits) (Ptr ptr :: user_data_C ptr) arr)
                       ((t_hrs_' (globals x)))\<rparr> \<rparr>) \<in> rf_sr"
  (is "\<forall>\<sigma> x. ?P \<sigma> x \<longrightarrow>
    (\<sigma>\<lparr>ksPSpace := ?ks \<sigma>\<rparr>, x\<lparr>globals := globals x\<lparr>t_hrs_' := ?ks' x\<rparr>\<rparr>) \<in> rf_sr")
proof (intro impI allI)
  fix \<sigma> x
  let ?thesis = "(\<sigma>\<lparr>ksPSpace := ?ks \<sigma>\<rparr>, x\<lparr>globals := globals x\<lparr>t_hrs_' := ?ks' x\<rparr>\<rparr>) \<in> rf_sr"
  let ?ks = "?ks \<sigma>"
  let ?ks' = "?ks' x"
  let ?ptr = "Ptr ptr :: user_data_C ptr"

  note Kernel_C.user_data_C_size [simp del]

  assume "?P \<sigma> x"
  hence rf: "(\<sigma>, x) \<in> rf_sr" and al: "is_aligned ptr (gbits + pageBits)"
    and ptr0: "ptr \<noteq> 0"
    and sz: "gbits + pageBits \<le> sz"
    and szb: "sz < word_bits"
    and pal: "pspace_aligned' \<sigma>" and pdst: "pspace_distinct' \<sigma>"
    and pno: "pspace_no_overlap' ptr sz \<sigma>"
    and vms: "valid_machine_state' \<sigma>"
    and rzo: "ret_zero ptr (n * 2 ^ (gbits + pageBits)) \<sigma>"
    and empty: "region_is_bytes ptr (n * 2 ^ (gbits + pageBits)) x"
    and zero: "heap_list_is_zero (hrs_mem (t_hrs_' (globals x))) ptr (n * 2 ^ (gbits + pageBits))"
    and rc: "range_cover ptr sz (gbits + pageBits) n"
    and rc': "range_cover ptr sz (objBitsKO ko) (n * 2^ gbits)"
    and kdr: "{ptr..+n * 2 ^ (gbits + pageBits)} \<inter> kernel_data_refs = {}"
    by (auto simp: range_cover.aligned objBits_simps  ko_def
                   range_cover_rel[where sbit' = pageBits]
                   range_cover.sz[where 'a=32, folded word_bits_def])

  hence al': "is_aligned ptr (objBitsKO ko)"
    by (clarsimp dest!: is_aligned_weaken range_cover.aligned)

  (* This is a hack *)
  have mko: "\<And>dev. makeObjectKO False (Inr object_type.SmallPageObject) = Some ko"
    by (simp add: makeObjectKO_def ko_def)

  from sz have "2 \<le> sz" by (simp add: objBits_simps pageBits_def ko_def)

  hence sz2: "2 ^ (sz - 2) * 4 = (2 :: nat) ^ sz"
    apply (subgoal_tac "(4 :: nat) = 2 ^ 2")
    apply (erule ssubst)
    apply (subst power_add [symmetric])
    apply (rule arg_cong [where f = "\<lambda>n. 2 ^ n"])
    apply simp
    apply simp
    done

  define big_0s where "big_0s \<equiv> (replicate (2^pageBits) 0) :: word8 list"

  have "length big_0s = 4096" unfolding big_0s_def
    by simp (simp add: pageBits_def)

  hence i1: "\<And>off :: 10 word. index (user_data_C.words_C (from_bytes big_0s)) (unat off) = 0"
    apply (simp add: from_bytes_def)
    apply (simp add: typ_info_simps user_data_C_tag_def)
    apply (simp add: ti_typ_pad_combine_empty_ti ti_typ_pad_combine_td align_of_def padup_def
      final_pad_def size_td_lt_ti_typ_pad_combine Let_def align_td_array' size_td_array size_of_def
      cong: if_cong)
    apply (simp add: update_ti_adjust_ti update_ti_t_word32_0s
      typ_info_simps update_ti_t_ptr_0s
      ti_typ_pad_combine_empty_ti ti_typ_pad_combine_td
      align_of_def padup_def
      final_pad_def size_td_lt_ti_typ_pad_combine Let_def
      align_td_array' size_td_array cong: if_cong)
    apply (subst update_ti_t_array_rep_word0)
     apply (unfold big_0s_def)[1]
     apply (rule arg_cong [where f = "\<lambda>x. replicate x 0"])
     apply (simp (no_asm) add: size_of_def pageBits_def)
    apply (subst index_foldr_update)
      apply (rule order_less_le_trans [OF unat_lt2p])
      apply simp
     apply simp
    apply simp
    done

  have p2dist: "n * (2::nat) ^ (gbits + pageBits) = n * 2 ^ gbits * 2 ^ pageBits" (is "?lhs = ?rhs")
    by (simp add:monoid_mult_class.power_add)

  have nca: "\<And>x p (off :: 10 word). \<lbrakk> p \<in> set (new_cap_addrs (n*2^gbits) ptr KOUserData); x < 4 \<rbrakk>
    \<Longrightarrow> p + ucast off * 4 + x \<in> {ptr..+ n * 2 ^ (gbits + pageBits) }"
    using sz
    apply (clarsimp simp: new_cap_addrs_def objBits_simps shiftl_t2n intvl_def)
    apply (rule_tac x = "2 ^ pageBits * pa + unat off * 4 + unat x" in exI)
    apply (simp add: ucast_nat_def power_add)
    apply (subst mult.commute, subst add.assoc)
    apply (rule_tac y = "(pa + 1) * 2 ^ pageBits " in less_le_trans)
     apply (simp add:word_less_nat_alt)
    apply (rule_tac y="unat off * 4 + 4" in less_le_trans)
      apply simp
     apply (simp add:pageBits_def)
     apply (cut_tac x = off in unat_lt2p)
     apply simp
    apply (subst mult.assoc[symmetric])
    apply (rule mult_right_mono)
     apply simp+
    done

  have nca_neg: "\<And>x p (off :: 10 word).
    \<lbrakk>x < 4; {p..+2 ^ objBitsKO KOUserData } \<inter> {ptr..ptr + (of_nat n * 2 ^ (gbits + pageBits) - 1)} = {}\<rbrakk>
     \<Longrightarrow> p + ucast off * 4 + x \<notin> {ptr..+n * 2 ^ (gbits + pageBits)}"
    apply (case_tac "n = 0")
     apply simp
    apply (subst range_cover_intvl[OF rc])
     apply simp
    apply (subgoal_tac " p + ucast off * 4 + x \<in>  {p..+2 ^ objBitsKO KOUserData}")
     apply blast
    apply (clarsimp simp:intvl_def)
    apply (rule_tac x = "unat off * 4 + unat x" in exI)
    apply (simp add: ucast_nat_def)
    apply (rule nat_add_offset_less [where n = 2, simplified])
      apply (simp add: word_less_nat_alt)
     apply (rule unat_lt2p)
    apply (simp add: pageBits_def objBits_simps)
    done

  have zero_app: "\<And>x. x \<in> {ptr..+ n * 2 ^ (gbits + pageBits) }
    \<Longrightarrow> underlying_memory (ksMachineState \<sigma>) x = 0"
    apply (cases "n = 0")
     apply simp
    apply (rule pspace_no_overlap_underlying_zero[OF pno vms])
    apply (erule subsetD[rotated])
    apply (cases "n = 0")
     apply simp
    apply (subst range_cover_intvl[OF rc], simp)
    apply (rule order_trans[rotated], erule range_cover_subset'[OF rc])
    apply (simp add: field_simps)
    done

  have cud: "\<And>p. p \<in> set (new_cap_addrs (n * 2^ gbits) ptr KOUserData) \<Longrightarrow>
              cuser_user_data_relation
                (byte_to_word_heap
                  (underlying_memory (ksMachineState \<sigma>)) p)
                (from_bytes big_0s)"
    unfolding cuser_user_data_relation_def
    apply -
    apply (rule allI)
    apply (subst i1)
    apply (simp add: byte_to_word_heap_def Let_def
                     zero_app nca nca [where x3 = 0, simplified])
    apply (simp add: word_rcat_bl)
    done

  note blah[simp del] =  atLeastAtMost_iff atLeastatMost_subset_iff atLeastLessThan_iff
      Int_atLeastAtMost atLeastatMost_empty_iff split_paired_Ex

  have cud2: "\<And>xa v y.
              \<lbrakk> heap_to_user_data
                     (\<lambda>x. if x \<in> set (new_cap_addrs (n*2^gbits) ptr KOUserData)
                           then Some KOUserData else ksPSpace \<sigma> x)
                     (underlying_memory (ksMachineState \<sigma>)) xa =
              Some v; xa \<notin> set (new_cap_addrs (n*2^gbits) ptr KOUserData);
              heap_to_user_data (ksPSpace \<sigma>) (underlying_memory (ksMachineState \<sigma>)) xa = Some y \<rbrakk> \<Longrightarrow> y = v"
    using range_cover_intvl[OF rc]
    by (clarsimp simp add: heap_to_user_data_def Let_def sz2
      byte_to_word_heap_def[abs_def] map_comp_Some_iff projectKOs)

  have relrl: "cmap_relation (heap_to_user_data (ksPSpace \<sigma>) (underlying_memory (ksMachineState \<sigma>)))
                             (cslift x) Ptr cuser_user_data_relation
    \<Longrightarrow> cmap_relation
        (heap_to_user_data
          (\<lambda>x. if x \<in> set (new_cap_addrs (n * 2 ^ gbits) ptr KOUserData)
               then Some KOUserData else ksPSpace \<sigma> x)
          (underlying_memory (ksMachineState \<sigma>)))
        (\<lambda>y. if y \<in> Ptr ` set (new_cap_addrs (n*2^gbits) ptr KOUserData)
             then Some
                   (from_bytes (replicate (2 ^ pageBits) 0))
             else cslift x y)
        Ptr cuser_user_data_relation"
    apply (rule cmap_relationI)
    apply (clarsimp simp: dom_heap_to_user_data cmap_relation_def dom_if image_Un
      projectKO_opt_retyp_same projectKOs)
    apply (case_tac "xa \<in> set (new_cap_addrs (n*2^gbits) ptr KOUserData)")
    apply (clarsimp simp: heap_to_user_data_def sz2)
    apply (erule cud [unfolded big_0s_def])
    apply (subgoal_tac "(Ptr xa :: user_data_C ptr) \<notin> Ptr ` set (new_cap_addrs (n*2^gbits) ptr KOUserData)")
    apply simp
    apply (erule (1) cmap_relationE2)
    apply (drule (1) cud2)
    apply simp
   apply simp
   apply clarsimp
   done

  (* /obj specific *)

  (* s/obj/obj'/ *)

  have szo: "size_of TYPE(user_data_C) = 2 ^ objBitsKO ko" by (simp add: size_of_def objBits_simps archObjSize_def ko_def pageBits_def)
  have szo': "n * 2 ^ (gbits + pageBits) = n * 2 ^ gbits * size_of TYPE(user_data_C)" using sz
    apply (subst szo)
    apply (clarsimp simp: power_add[symmetric] objBits_simps ko_def)
    done

  have rb': "region_is_bytes ptr (n * 2 ^ gbits * 2 ^ objBitsKO ko) x"
    using empty
    by (simp add: mult.commute mult.left_commute power_add objBits_simps ko_def)

  note rl' = cslift_ptr_retyp_other_inst[OF rb' rc' szo' szo, simplified]

  (* rest is generic *)

  note rl = projectKO_opt_retyp_other [OF rc' pal pno,unfolded ko_def]
  note cterl = retype_ctes_helper[OF pal pdst pno al' range_cover.sz(2)[OF rc'] range_cover.sz(1)[OF rc', folded word_bits_def] mko rc']
  note ht_rl = clift_eq_h_t_valid_eq[OF rl', OF tag_disj_via_td_name, simplified]

  have guard:
    "\<forall>t<n * 2 ^ gbits. c_guard (CTypesDefs.ptr_add ?ptr (of_nat t))"
    apply (rule retype_guard_helper[OF rc' ptr0 szo,where m = 2])
    apply (clarsimp simp:align_of_def objBits_simps ko_def pageBits_def)+
    done

  from rf have "cpspace_relation (ksPSpace \<sigma>) (underlying_memory (ksMachineState \<sigma>)) (t_hrs_' (globals x))"
    unfolding rf_sr_def cstate_relation_def by (simp add: Let_def)

  hence "cpspace_relation ?ks (underlying_memory (ksMachineState \<sigma>)) ?ks'"
    unfolding cpspace_relation_def
    using empty rc' szo
    apply -
    apply (clarsimp simp: rl' tag_disj_via_td_name cte_C_size ht_rl
                          foldr_upd_app_if [folded data_map_insert_def])
    apply (simp add: rl ko_def projectKOs p2dist
                     cterl[unfolded ko_def])
    apply (subst clift_ptr_retyps_gen_prev_memset_same[OF guard])
         apply (simp add: pageBits_def objBits_simps)
        apply simp
       apply (simp add: pageBits_def objBits_simps)
      apply (cut_tac range_cover.strong_times_32[OF rc], simp_all)[1]
      apply (simp add: p2dist objBits_simps)
     apply (cut_tac zero)
     apply (simp add: pageBits_def power_add field_simps)
    apply (simp add: objBits_simps ptr_add_to_new_cap_addrs[OF szo] ko_def
               cong: if_cong)
    apply (simp add: p2dist[symmetric])
    apply (erule relrl[simplified])
    done

  thus  ?thesis using rf empty kdr rzo
    apply (simp add: rf_sr_def cstate_relation_def Let_def rl' tag_disj_via_td_name )
    apply (simp add: carch_state_relation_def cmachine_state_relation_def)
    apply (simp add: tag_disj_via_td_name rl' tcb_C_size h_t_valid_clift_Some_iff)
    apply (clarsimp simp: hrs_htd_update szo'[symmetric])
    apply (simp add:szo hrs_htd_def p2dist objBits_simps ko_def ptr_retyps_htd_safe_neg
                    kernel_data_refs_domain_eq_rotate
                    rl foldr_upd_app_if [folded data_map_insert_def]
                    projectKOs cvariable_array_ptr_retyps
                    zero_ranges_ptr_retyps)
    done
qed

lemma valid_pde_mappings_ko_atD':
  "\<lbrakk> ko_at' ko p s; valid_pde_mappings' s \<rbrakk>
       \<Longrightarrow> ko_at' ko p s \<and> valid_pde_mapping' (p && mask pdBits) ko"
  by (simp add: valid_pde_mappings'_def)

lemmas clift_array_assertionE
    = clift_array_assertion_imp[where p="Ptr q" and p'="Ptr q" for q,
        OF _ refl _ exI[where x=0], simplified]

lemma copyGlobalMappings_ccorres:
  "ccorres dc xfdc
     (valid_pde_mappings' and (\<lambda>s. page_directory_at' (armKSGlobalPD (ksArchState s)) s)
        and page_directory_at' pd and (\<lambda>_. is_aligned pd pdBits))
     (UNIV \<inter> {s. newPD_' s = Ptr pd}) []
    (copyGlobalMappings pd) (Call copyGlobalMappings_'proc)"
  apply (rule ccorres_gen_asm)
  apply (cinit lift: newPD_' simp: ARMSectionBits_def pdeBits_def)
   apply (rule ccorres_h_t_valid_armKSGlobalPD)
   apply csymbr
   apply (simp add: kernelBase_def ARM.kernelBase_def objBits_simps archObjSize_def
                    whileAnno_def word_sle_def word_sless_def
                    Collect_True              del: Collect_const)
   apply (rule ccorres_pre_gets_armKSGlobalPD_ksArchState)
   apply csymbr
   apply (rule ccorres_rel_imp)
    apply (rule_tac F="\<lambda>_ s. rv = armKSGlobalPD (ksArchState s)
                                \<and> is_aligned rv pdBits \<and> valid_pde_mappings' s
                                \<and> page_directory_at' pd s
                                \<and> page_directory_at' (armKSGlobalPD (ksArchState s)) s"
              and i="0xE00"
               in ccorres_mapM_x_while')
        apply (clarsimp simp del: Collect_const)
        apply (rule ccorres_guard_imp2)
         apply (rule ccorres_pre_getObject_pde)
         apply (simp add: storePDE_def del: Collect_const)
         apply (rule_tac P="\<lambda>s. ko_at' rva (armKSGlobalPD (ksArchState s)
                                              + ((0xE00 + of_nat n) << 2)) s
                                    \<and> page_directory_at' pd s \<and> valid_pde_mappings' s
                                    \<and> page_directory_at' (armKSGlobalPD (ksArchState s)) s"
                    and P'="{s. i_' s = of_nat (3584 + n)
                                    \<and> is_aligned (symbol_table ''armKSGlobalPD'') pdBits}"
                    in setObject_ccorres_helper)
           apply (rule conseqPre, vcg)
           apply (clarsimp simp: shiftl_t2n field_simps upto_enum_word
                                 rf_sr_armKSGlobalPD
                       simp del: upt.simps)
           apply (frule_tac pd=pd in page_directory_at_rf_sr, simp)
           apply (frule_tac pd="symbol_table a" for a in page_directory_at_rf_sr, simp)
           apply (rule cmap_relationE1[OF rf_sr_cpde_relation],
                  assumption, erule_tac ko=ko' in ko_at_projectKO_opt)
           apply (rule cmap_relationE1[OF rf_sr_cpde_relation],
                  assumption, erule_tac ko=rva in ko_at_projectKO_opt)
           apply (clarsimp simp: typ_heap_simps')
           apply (drule(1) page_directory_at_rf_sr)+
           apply clarsimp
           apply (subst array_ptr_valid_array_assertionI[where p="Ptr pd" and q="Ptr pd"],
             erule h_t_valid_clift; simp)
            apply (simp add: unat_def[symmetric] unat_word_ariths unat_of_nat pdBits_def pageBits_def pdeBits_def)
           apply (subst array_ptr_valid_array_assertionI[where q="Ptr (symbol_table x)" for x],
             erule h_t_valid_clift; simp)
            apply (simp add: unat_def[symmetric] unat_word_ariths unat_of_nat pdBits_def pageBits_def pdeBits_def)
           apply (clarsimp simp: rf_sr_def cstate_relation_def
                                 Let_def typ_heap_simps update_pde_map_tos)
           apply (rule conjI)
            apply clarsimp
            apply (rule conjI)
             apply (rule disjCI2, erule clift_array_assertionE, simp+)
             apply (simp only: unat_arith_simps unat_of_nat,
               simp add: pdBits_def pageBits_def pdeBits_def)
            apply (rule conjI)
             apply (rule disjCI2, erule clift_array_assertionE, simp+)
             apply (simp only: unat_arith_simps unat_of_nat,
               simp add: pdBits_def pageBits_def pdeBits_def)
            apply (rule conjI)
             apply (clarsimp simp: cpspace_relation_def
                                   typ_heap_simps
                                   update_pde_map_tos
                                   update_pde_map_to_pdes
                                   carray_map_relation_upd_triv)
             apply (erule(2) cmap_relation_updI)
              subgoal by simp
             subgoal by simp
            apply (clarsimp simp: carch_state_relation_def
                                  cmachine_state_relation_def
                                  typ_heap_simps map_comp_eq
                                  pd_pointer_to_asid_slot_def
                          intro!: ext split: if_split)
            apply (simp add: field_simps)
            apply (drule arg_cong[where f="\<lambda>x. x && mask pdBits"],
                   simp add: mask_add_aligned)
            apply (simp add: iffD2[OF mask_eq_iff_w2p] word_size pdBits_def pageBits_def pdeBits_def)
            apply (subst(asm) iffD2[OF mask_eq_iff_w2p])
              subgoal by (simp add: word_size)
             apply (simp only: word_shift_by_2)
             apply (rule shiftl_less_t2n)
              apply (rule of_nat_power)
               subgoal by simp
              subgoal by simp
             subgoal by simp
            apply (simp add: word_shift_by_2)
            apply (drule arg_cong[where f="\<lambda>x. x >> 2"], subst(asm) shiftl_shiftr_id)
              subgoal by (simp add: word_bits_def)
             apply (rule of_nat_power)
              subgoal by (simp add: word_bits_def)
             subgoal by (simp add: word_bits_def)
            apply simp
           apply clarsimp
           apply (drule(1) valid_pde_mappings_ko_atD')+
           apply (clarsimp simp: mask_add_aligned valid_pde_mapping'_def field_simps)
           apply (subst(asm) field_simps, simp add: mask_add_aligned)
           apply (simp add: mask_def pdBits_def pageBits_def pdeBits_def
                            valid_pde_mapping_offset'_def pd_asid_slot_def)
           apply (simp add: obj_at'_def projectKOs fun_upd_idem)
          apply simp
         apply (simp add: objBits_simps archObjSize_def pdeBits_def)
        apply (clarsimp simp: upto_enum_word rf_sr_armKSGlobalPD
                    simp del: upt.simps)
       apply (simp add: pdBits_def pageBits_def pdeBits_def)
      apply (rule allI, rule conseqPre, vcg)
      apply clarsimp
     apply (rule hoare_pre)
      apply (wp getObject_valid_pde_mapping' | simp
        | wps storePDE_arch')+
     apply (clarsimp simp: mask_add_aligned)
    apply (simp add: pdBits_def pageBits_def word_bits_def pdeBits_def)
   apply simp
  apply (clarsimp simp: word_sle_def page_directory_at'_def)
  done

(* If we only change local variables on the C side, nothing need be done on the abstract side.

   This is currently unused, but might be useful.
   it might be worth fixing if it breaks, but ask around first. *)
lemma ccorres_only_change_locals:
  "\<lbrakk> \<And>s. \<Gamma> \<turnstile> {s} C {t. globals s = globals t} \<rbrakk> \<Longrightarrow> ccorresG rf_sr \<Gamma> dc xfdc \<top> UNIV hs (return x) C"
  apply (rule ccorres_from_vcg)
  apply (clarsimp simp: return_def)
  apply (clarsimp simp: rf_sr_def)
  apply (rule hoare_complete)
  apply (clarsimp simp: HoarePartialDef.valid_def)
  apply (erule_tac x=x in meta_allE)
  apply (drule hoare_sound)
  apply (clarsimp simp: cvalid_def HoarePartialDef.valid_def)
  apply auto
  done

lemma getObjectSize_max_size:
  "\<lbrakk> newType =  APIObjectType apiobject_type.Untyped \<longrightarrow> x < 32;
         newType =  APIObjectType apiobject_type.CapTableObject \<longrightarrow> x < 28 \<rbrakk> \<Longrightarrow> getObjectSize newType x < word_bits"
  apply (clarsimp simp only: getObjectSize_def apiGetObjectSize_def word_bits_def
                  split: ARM_H.object_type.splits apiobject_type.splits)
  apply (clarsimp simp: tcbBlockSizeBits_def epSizeBits_def ntfnSizeBits_def cteSizeBits_def
                        pdBits_def pageBits_def ptBits_def pteBits_def pdeBits_def)
  done

(*
 * Assuming "placeNewObject" doesn't fail, it is equivalent
 * to placing a number of objects into the PSpace.
 *)
lemma placeNewObject_eq:
  notes option.case_cong_weak [cong]
  shows
  "\<lbrakk> groupSizeBits < word_bits; is_aligned ptr (groupSizeBits + objBitsKO (injectKOS object));
    no_fail ((=) s) (placeNewObject ptr object groupSizeBits) \<rbrakk> \<Longrightarrow>
  ((), (s\<lparr>ksPSpace := foldr (\<lambda>addr. data_map_insert addr (injectKOS object)) (new_cap_addrs (2 ^ groupSizeBits) ptr (injectKOS object)) (ksPSpace s)\<rparr>))
                \<in> fst (placeNewObject ptr object groupSizeBits s)"
  apply (clarsimp simp: placeNewObject_def placeNewObject'_def)
  apply (clarsimp simp: split_def field_simps split del: if_split)
  apply (clarsimp simp: no_fail_def)
  apply (subst lookupAround2_pspace_no)
   apply assumption
  apply (subst (asm) lookupAround2_pspace_no)
   apply assumption
  apply (clarsimp simp add: in_monad' split_def bind_assoc field_simps
    snd_bind ball_to_all unless_def  split: option.splits if_split_asm)
  apply (clarsimp simp: data_map_insert_def new_cap_addrs_def)
  apply (subst upto_enum_red2)
   apply (fold word_bits_def, assumption)
  apply (clarsimp simp: field_simps shiftl_t2n power_add mult.commute mult.left_commute
           cong: foldr_cong map_cong)
  done

lemma rf_sr_htd_safe:
  "(s, s') \<in> rf_sr \<Longrightarrow> htd_safe domain (hrs_htd (t_hrs_' (globals s')))"
  by (simp add: rf_sr_def cstate_relation_def Let_def)

lemma region_actually_is_bytes_dom_s:
  "region_actually_is_bytes' ptr len htd
    \<Longrightarrow> S \<subseteq> {ptr ..+ len}
    \<Longrightarrow> S \<times> {SIndexVal, SIndexTyp 0} \<subseteq> dom_s htd"
  apply (clarsimp simp: region_actually_is_bytes'_def dom_s_def)
  apply fastforce
  done

lemma typ_region_bytes_actually_is_bytes:
  "htd = typ_region_bytes ptr bits htd'
    \<Longrightarrow> region_actually_is_bytes' ptr (2 ^ bits) htd"
  by (clarsimp simp: region_actually_is_bytes'_def typ_region_bytes_def)

(* FIXME: need a way to avoid overruling the parser on this, it's ugly *)
lemma memzero_modifies:
  "\<forall>\<sigma>. \<Gamma>\<turnstile>\<^bsub>/UNIV\<^esub> {\<sigma>} Call memzero_'proc {t. t may_only_modify_globals \<sigma> in [t_hrs]}"
  apply (rule allI, rule conseqPre)
  apply (hoare_rule HoarePartial.ProcNoRec1)
   apply (tactic {* HoarePackage.vcg_tac "_modifies" "false" [] @{context} 1 *})
  apply (clarsimp simp: mex_def meq_def simp del: split_paired_Ex)
  apply (intro exI globals.equality, simp_all)
  done

lemma ghost_assertion_size_logic_no_unat:
  "sz \<le> gsMaxObjectSize s
    \<Longrightarrow> (s, \<sigma>) \<in> rf_sr
    \<Longrightarrow> gs_get_assn cap_get_capSizeBits_'proc (ghost'state_' (globals \<sigma>)) = 0 \<or>
            of_nat sz \<le> gs_get_assn cap_get_capSizeBits_'proc (ghost'state_' (globals \<sigma>))"
  apply (rule ghost_assertion_size_logic'[rotated])
   apply (simp add: rf_sr_def)
  apply (simp add: unat_of_nat)
  done

lemma ccorres_placeNewObject_endpoint:
  "ko = (makeObject :: endpoint)
   \<Longrightarrow> ccorresG rf_sr \<Gamma> dc xfdc
   (pspace_aligned' and pspace_distinct'
      and pspace_no_overlap' regionBase (objBits ko)
      and ret_zero regionBase (2 ^ objBits ko)
      and (\<lambda>s. 2 ^ (objBits ko) \<le> gsMaxObjectSize s)
      and K (regionBase \<noteq> 0 \<and> range_cover regionBase (objBits ko) (objBits ko) 1
      \<and> {regionBase..+ 2 ^ (objBits ko)} \<inter> kernel_data_refs = {}))
   ({s. region_actually_is_zero_bytes regionBase (2 ^ objBits ko) s})
    hs
    (placeNewObject regionBase ko 0)
    (global_htd_update (\<lambda>_. (ptr_retyp (ep_Ptr regionBase))))"
  apply (rule ccorres_from_vcg_nofail)
  apply clarsimp
  apply (rule conseqPre)
  apply vcg
  apply (clarsimp simp: rf_sr_htd_safe)
  apply (intro conjI allI impI)
   apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def
                         kernel_data_refs_domain_eq_rotate
                         objBits_simps'
                  elim!: ptr_retyp_htd_safe_neg)
  apply (rule bexI [OF _ placeNewObject_eq])
     apply (clarsimp simp: split_def)
     apply (clarsimp simp: new_cap_addrs_def)
     apply (cut_tac createObjects_ccorres_ep [where ptr=regionBase and n="1" and sz="objBitsKO (KOEndpoint makeObject)"])
     apply (erule_tac x=\<sigma> in allE, erule_tac x=x in allE)
     apply (clarsimp elim!:is_aligned_weaken simp: objBitsKO_def word_bits_def)+
     apply (clarsimp simp: split_def Let_def
         Fun.comp_def rf_sr_def new_cap_addrs_def
         region_actually_is_bytes ptr_retyps_gen_def
         objBits_simps
         elim!: rsubst[where P="cstate_relation s'" for s'])
    apply (clarsimp simp: word_bits_conv)
   apply (clarsimp simp: range_cover.aligned objBits_simps)
  apply (clarsimp simp: no_fail_def)
  done

lemma ccorres_placeNewObject_notification:
  "ccorresG rf_sr \<Gamma> dc xfdc
   (pspace_aligned' and pspace_distinct' and pspace_no_overlap' regionBase 4
      and (\<lambda>s. 2^ntfnSizeBits \<le> gsMaxObjectSize s)
      and ret_zero regionBase (2^ntfnSizeBits)
      and K (regionBase \<noteq> 0
      \<and> {regionBase..+2^ntfnSizeBits} \<inter> kernel_data_refs = {}
      \<and> range_cover regionBase ntfnSizeBits ntfnSizeBits 1))
   ({s. region_actually_is_zero_bytes regionBase (2^ntfnSizeBits) s})
    hs
    (placeNewObject regionBase (makeObject :: Structures_H.notification) 0)
    (global_htd_update (\<lambda>_. (ptr_retyp (ntfn_Ptr regionBase))))"
  apply (rule ccorres_from_vcg_nofail)
  apply clarsimp
  apply (rule conseqPre)
  apply vcg
  apply (clarsimp simp: rf_sr_htd_safe)
  apply (intro conjI allI impI)
   apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def
                         kernel_data_refs_domain_eq_rotate objBits_defs
                  elim!: ptr_retyp_htd_safe_neg)
  apply (rule bexI [OF _ placeNewObject_eq])
     apply (clarsimp simp: split_def new_cap_addrs_def)
     apply (cut_tac createObjects_ccorres_ntfn [where ptr=regionBase and n="1" and sz="objBitsKO (KONotification makeObject)"])
     apply (erule_tac x=\<sigma> in allE, erule_tac x=x in allE)
     apply (clarsimp elim!: is_aligned_weaken simp: objBitsKO_def word_bits_def)+
     apply (clarsimp simp: split_def objBitsKO_def Let_def
                           Fun.comp_def rf_sr_def new_cap_addrs_def)
     apply (clarsimp simp: cstate_relation_def carch_state_relation_def split_def
                           Let_def cmachine_state_relation_def cpspace_relation_def
                           region_actually_is_bytes ptr_retyps_gen_def objBits_defs)
    apply (clarsimp simp: word_bits_conv)
   apply (clarsimp simp: objBits_simps range_cover.aligned)
  apply (clarsimp simp: no_fail_def)
  done

lemma htd_update_list_dom_better [rule_format]:
  "(\<forall>p d. dom_s (htd_update_list p xs d) =
          (dom_s d) \<union> dom_tll p xs)"
apply(induct_tac xs)
 apply simp
apply clarsimp
apply(auto split: if_split_asm)
 apply(erule notE)
 apply(clarsimp simp: dom_s_def)
apply(case_tac y)
 apply clarsimp+
apply(clarsimp simp: dom_s_def)
done

lemma ptr_array_retyps_htd_safe_neg:
  "\<lbrakk> htd_safe (- D) htd;
    {ptr_val ptr ..+ n * size_of TYPE('a :: mem_type)}
        \<inter> D = {} \<rbrakk>
   \<Longrightarrow> htd_safe (- D) (ptr_arr_retyps n (ptr :: 'a ptr) htd)"
  apply (simp add: htd_safe_def ptr_arr_retyps_def htd_update_list_dom_better)
  apply (auto simp: dom_tll_def intvl_def)
  done

lemma ccorres_placeNewObject_captable:
  "ccorresG rf_sr \<Gamma> dc xfdc
   (pspace_aligned' and pspace_distinct' and pspace_no_overlap' regionBase (unat userSize + cteSizeBits)
      and (\<lambda>s. 2 ^ (unat userSize + cteSizeBits) \<le> gsMaxObjectSize s)
      and ret_zero regionBase (2 ^ (unat userSize + cteSizeBits))
      and K (regionBase \<noteq> 0 \<and> range_cover regionBase (unat userSize + cteSizeBits) (unat userSize + cteSizeBits) 1
      \<and> ({regionBase..+2 ^ (unat userSize + cteSizeBits)} \<inter> kernel_data_refs = {})))
    ({s. region_actually_is_zero_bytes regionBase (2 ^ (unat userSize + cteSizeBits)) s})
    hs
    (placeNewObject regionBase (makeObject :: cte) (unat (userSize::word32)))
    (global_htd_update (\<lambda>_. (ptr_arr_retyps (2 ^ (unat userSize)) (cte_Ptr regionBase))))"
  apply (rule ccorres_from_vcg_nofail)
  apply clarsimp
  apply (rule conseqPre)
  apply vcg
  apply (clarsimp simp: rf_sr_htd_safe)
  apply (intro conjI allI impI)
   apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def
                         kernel_data_refs_domain_eq_rotate
                  elim!: ptr_array_retyps_htd_safe_neg)
   apply (simp add: size_of_def power_add objBits_defs)
  apply (frule range_cover_rel[where sbit' = cteSizeBits])
    apply simp
   apply simp
  apply (frule range_cover.unat_of_nat_shift[where gbits = cteSizeBits, OF _ le_refl le_refl])
  apply (subgoal_tac "region_is_bytes regionBase (2 ^ (unat userSize + cteSizeBits)) x")
   apply (rule bexI [OF _ placeNewObject_eq])
      apply (clarsimp simp: split_def new_cap_addrs_def)
      apply (cut_tac createObjects_ccorres_cte
                       [where ptr=regionBase and n="2 ^ unat userSize"
                          and sz="unat userSize + objBitsKO (KOCTE makeObject)"])
      apply (erule_tac x=\<sigma> in allE, erule_tac x=x in allE)
      apply (clarsimp elim!:is_aligned_weaken simp: objBitsKO_def word_bits_def)+
      apply (clarsimp simp: split_def objBitsKO_def
                            Fun.comp_def rf_sr_def Let_def
                            new_cap_addrs_def field_simps power_add ptr_retyps_gen_def
                   elim!: rsubst[where P="cstate_relation s'" for s'])
     apply (clarsimp simp: word_bits_conv range_cover_def)
    apply (clarsimp simp: objBitsKO_def range_cover.aligned)
   apply (clarsimp simp: no_fail_def)
  apply (simp add: region_actually_is_bytes)
 done

lemma rf_sr_domain_eq:
  "(\<sigma>, s) \<in> rf_sr \<Longrightarrow> htd_safe domain = htd_safe (- kernel_data_refs)"
  by (simp add: rf_sr_def cstate_relation_def Let_def
                kernel_data_refs_domain_eq_rotate)

declare replicate_numeral [simp del]

lemma ccorres_placeNewObject_tcb:
  "ccorresG rf_sr \<Gamma> dc xfdc
   (pspace_aligned' and pspace_distinct' and pspace_no_overlap' regionBase tcbBlockSizeBits
      and valid_queues and (\<lambda>s. sym_refs (state_refs_of' s))
      and (\<lambda>s. 2 ^ tcbBlockSizeBits \<le> gsMaxObjectSize s)
      and ret_zero regionBase (2 ^ tcbBlockSizeBits)
      and K (regionBase \<noteq> 0 \<and> range_cover regionBase tcbBlockSizeBits tcbBlockSizeBits 1
      \<and>  {regionBase..+2^tcbBlockSizeBits} \<inter> kernel_data_refs = {}))
   ({s. region_actually_is_zero_bytes regionBase (2^tcbBlockSizeBits) s})
    hs
   (placeNewObject regionBase (makeObject :: tcb) 0)
   (\<acute>tcb :== tcb_Ptr (regionBase + 0x100);;
        (global_htd_update (\<lambda>s. ptr_retyp (Ptr (ptr_val (tcb_' s) - ctcb_offset) :: (cte_C[5]) ptr)
            \<circ> ptr_retyp (tcb_' s)));;
        (Guard C_Guard \<lbrace>hrs_htd \<acute>t_hrs \<Turnstile>\<^sub>t \<acute>tcb\<rbrace>
           (call (\<lambda>s. s\<lparr>context_' := Ptr &((Ptr &(tcb_' s\<rightarrow>[''tcbArch_C'']) :: arch_tcb_C ptr)\<rightarrow>[''tcbContext_C''])\<rparr>) Arch_initContext_'proc (\<lambda>s t. s\<lparr>globals := globals t\<rparr>) (\<lambda>s' s''. Basic (\<lambda>s. s))));;
        (Guard C_Guard \<lbrace>hrs_htd \<acute>t_hrs \<Turnstile>\<^sub>t \<acute>tcb\<rbrace>
           (Basic (\<lambda>s. globals_update (t_hrs_'_update (hrs_mem_update (heap_update (Ptr &((tcb_' s)\<rightarrow>[''tcbTimeSlice_C''])) (5::word32)))) s))))"
  apply -
  apply (rule ccorres_from_vcg_nofail)
  apply clarsimp
  apply (rule conseqPre)
   apply vcg
  apply (clarsimp simp: rf_sr_htd_safe ctcb_offset_defs)
  apply (subgoal_tac "c_guard (tcb_Ptr (regionBase + 0x100))")
   apply (subgoal_tac "hrs_htd (hrs_htd_update (ptr_retyp (Ptr regionBase :: (cte_C[5]) ptr)
                                 \<circ> ptr_retyp (tcb_Ptr (regionBase + 0x100)))
                  (t_hrs_' (globals x))) \<Turnstile>\<^sub>t tcb_Ptr (regionBase + 0x100)")
    prefer 2
    apply (clarsimp simp: hrs_htd_update)
    apply (rule h_t_valid_ptr_retyps_gen_disjoint[where n=1 and arr=False,
                unfolded ptr_retyps_gen_def, simplified])
     apply (rule ptr_retyp_h_t_valid)
     apply simp
    apply (rule tcb_ptr_orth_cte_ptrs')
   apply (intro conjI allI impI)
         apply (simp only: rf_sr_domain_eq)
         apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def
                               kernel_data_refs_domain_eq_rotate)
         apply (intro ptr_retyps_htd_safe_neg ptr_retyp_htd_safe_neg, simp_all add: size_of_def)[1]
          apply (erule disjoint_subset[rotated])
          apply (rule intvl_sub_offset, simp add: objBits_defs)
         apply (erule disjoint_subset[rotated],
                simp add: intvl_start_le size_td_array cte_C_size objBits_defs)
        apply (clarsimp simp: hrs_htd_update)
       apply (clarsimp simp: CPSR_def word_sle_def)+
     apply (clarsimp simp: hrs_htd_update)
     apply (rule h_t_valid_field[rotated], simp+)+
    apply (clarsimp simp: hrs_htd_update)
   apply (clarsimp simp: hrs_htd_update)
   apply (rule bexI [OF _ placeNewObject_eq])
      apply (clarsimp simp: split_def new_cap_addrs_def)
      apply (cut_tac \<sigma>=\<sigma> and x=x
                   and ks="ksPSpace \<sigma>" and p="tcb_Ptr (regionBase + 0x100)" in cnc_tcb_helper)
                    apply clarsimp
                   apply (clarsimp simp: ctcb_ptr_to_tcb_ptr_def ctcb_offset_defs
                                         objBitsKO_def range_cover.aligned)
                  apply (clarsimp simp: ctcb_ptr_to_tcb_ptr_def ctcb_offset_defs objBitsKO_def)
                 apply (simp add:olen_add_eqv[symmetric] ctcb_size_bits_def)
                 apply (erule is_aligned_no_wrap'[OF range_cover.aligned])
                 apply (simp add: objBits_defs)
                apply simp
               apply clarsimp
              apply (clarsimp simp: ctcb_ptr_to_tcb_ptr_def ctcb_offset_defs objBitsKO_def)
             apply (clarsimp)
            apply simp
           apply clarsimp
          apply (clarsimp simp: objBits_simps ctcb_ptr_to_tcb_ptr_def ctcb_offset_defs)
         apply (frule region_actually_is_bytes)
         apply (clarsimp simp: region_is_bytes'_def ctcb_ptr_to_tcb_ptr_def ctcb_offset_defs split_def
                               hrs_mem_update_def hrs_htd_def)
        apply (clarsimp simp: ctcb_ptr_to_tcb_ptr_def ctcb_offset_defs hrs_mem_update_def split_def)
        apply (simp add: hrs_mem_def)
       apply (simp add: ctcb_ptr_to_tcb_ptr_def ctcb_offset_defs)
      apply (clarsimp simp: ctcb_ptr_to_tcb_ptr_def ctcb_offset_defs hrs_mem_update_def split_def)
      apply (clarsimp simp: rf_sr_def ptr_retyps_gen_def cong: Kernel_C.globals.unfold_congs
                            StateSpace.state.unfold_congs kernel_state.unfold_congs)
     apply (clarsimp simp: word_bits_def)
    apply (clarsimp simp: objBitsKO_def range_cover.aligned)
   apply (clarsimp simp: no_fail_def)
  apply (rule c_guard_tcb)
   apply (clarsimp simp: ctcb_ptr_to_tcb_ptr_def ctcb_offset_defs range_cover.aligned)
  apply (clarsimp simp: ctcb_ptr_to_tcb_ptr_def ctcb_offset_defs)
  done

lemma placeNewObject_pte:
  "ccorresG rf_sr \<Gamma> dc xfdc
   ( valid_global_refs' and pspace_aligned' and pspace_distinct' and pspace_no_overlap' regionBase 10
      and (\<lambda>s. 2 ^ 10 \<le> gsMaxObjectSize s)
      and ret_zero regionBase (2 ^ 10)
      and K (regionBase \<noteq> 0 \<and> range_cover regionBase 10 10 1
      \<and> ({regionBase..+2 ^ 10} \<inter> kernel_data_refs = {})
      ))
    ({s. region_actually_is_zero_bytes regionBase (2 ^ 10) s})
    hs
    (placeNewObject regionBase (makeObject :: pte) 8)
    (global_htd_update (\<lambda>_. (ptr_retyp (Ptr regionBase :: (pte_C[256]) ptr))))"
  apply (rule ccorres_from_vcg_nofail)
  apply clarsimp
  apply (rule conseqPre)
  apply vcg
  apply (clarsimp simp: rf_sr_htd_safe)
  apply (intro conjI allI impI)
   apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def
                         kernel_data_refs_domain_eq_rotate
                  elim!: ptr_retyp_htd_safe_neg)
  apply (frule range_cover_rel[where sbit' = 2])
    apply simp+
  apply (frule range_cover.unat_of_nat_shift[where gbits = 2 ])
   apply simp+
   apply (rule le_refl)
  apply (subgoal_tac "region_is_bytes regionBase 1024 x")
   apply (rule bexI [OF _ placeNewObject_eq])
      apply (clarsimp simp: split_def new_cap_addrs_def)
      apply (cut_tac s=\<sigma> in createObjects_ccorres_pte [where ptr=regionBase and sz=10])
      apply (erule_tac x=\<sigma> in allE, erule_tac x=x in allE)
      apply (clarsimp elim!:is_aligned_weaken simp: objBitsKO_def word_bits_def)+
      apply (clarsimp simp: split_def objBitsKO_def archObjSize_def
          Fun.comp_def rf_sr_def split_def Let_def ptr_retyps_gen_def
          new_cap_addrs_def field_simps power_add
          cong: globals.unfold_congs)
      apply (simp add:Int_ac ptBits_def pageBits_def pteBits_def)
     apply (clarsimp simp: word_bits_conv range_cover_def archObjSize_def word_bits_def)
    apply (clarsimp simp: objBitsKO_def range_cover.aligned archObjSize_def pteBits_def)
   apply (clarsimp simp: no_fail_def)
  apply (simp add: region_actually_is_bytes)
 done


lemma placeNewObject_pde:
  "ccorresG rf_sr \<Gamma> dc xfdc
   (valid_global_refs' and pspace_aligned' and pspace_distinct' and pspace_no_overlap' regionBase 14
      and (\<lambda>s. 2 ^ 14 \<le> gsMaxObjectSize s)
      and ret_zero regionBase (2 ^ 14)
      and K (regionBase \<noteq> 0 \<and> range_cover regionBase 14 14 1
      \<and> ({regionBase..+2 ^ 14}
          \<inter> kernel_data_refs = {})
      ))
    ({s. region_actually_is_zero_bytes regionBase (2 ^ 14) s})
    hs
    (placeNewObject regionBase (makeObject :: pde) 12)
    (global_htd_update (\<lambda>_. (ptr_retyp (pd_Ptr regionBase))))"
  apply (rule ccorres_from_vcg_nofail)
  apply clarsimp
  apply (rule conseqPre)
  apply vcg
  apply (clarsimp simp: rf_sr_htd_safe)
  apply (intro conjI allI impI)
   apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def
                         kernel_data_refs_domain_eq_rotate
                  elim!: ptr_retyp_htd_safe_neg)
  apply (frule range_cover_rel[where sbit' = 2])
    apply simp+
  apply (frule range_cover.unat_of_nat_shift[where gbits = 2 ])
   apply simp+
   apply (rule le_refl)
  apply (subgoal_tac "region_is_bytes regionBase 16384 x")
   apply (rule bexI [OF _ placeNewObject_eq])
      apply (clarsimp simp: split_def new_cap_addrs_def)
      apply (cut_tac s=\<sigma> in createObjects_ccorres_pde [where ptr=regionBase and sz=14])
      apply (erule_tac x=\<sigma> in allE, erule_tac x=x in allE)
      apply (clarsimp elim!:is_aligned_weaken simp: objBitsKO_def word_bits_def)+
      apply (clarsimp simp: split_def objBitsKO_def archObjSize_def
          Fun.comp_def rf_sr_def Let_def ptr_retyps_gen_def
          new_cap_addrs_def field_simps power_add
          cong: globals.unfold_congs)
      apply (simp add:Int_ac pdBits_def pageBits_def pdeBits_def)
     apply (clarsimp simp: word_bits_conv range_cover_def archObjSize_def)
    apply (clarsimp simp: objBitsKO_def range_cover.aligned archObjSize_def pdeBits_def)
   apply (clarsimp simp: no_fail_def)
  apply (simp add: region_actually_is_bytes)
 done

end

context begin interpretation Arch . (*FIXME: arch_split*)
end

lemma dom_disj_union:
  "dom (\<lambda>x. if P x \<or> Q x then Some (G x) else None) = dom (\<lambda>x. if P x then Some (G x) else None)
  \<union> dom (\<lambda>x. if Q x then Some (G x) else None)"
  by (auto split:if_splits)
context kernel_m begin

lemma createObjects_ccorres_user_data_device:
  defines "ko \<equiv> KOUserDataDevice"
  shows "\<forall>\<sigma> x. (\<sigma>, x) \<in> rf_sr \<and> range_cover ptr sz (gbits + pageBits) n
  \<and> ptr \<noteq> 0
  \<and> pspace_aligned' \<sigma> \<and> pspace_distinct' \<sigma>
  \<and> pspace_no_overlap' ptr sz \<sigma>
  \<and> ret_zero ptr (n * 2 ^ (gbits + pageBits)) \<sigma>
  \<and> region_is_bytes ptr (n * 2 ^ (gbits + pageBits)) x
  \<and> {ptr ..+ n * (2 ^ (gbits + pageBits))} \<inter> kernel_data_refs = {}
  \<longrightarrow>
  (\<sigma>\<lparr>ksPSpace :=
               foldr (\<lambda>addr. data_map_insert addr KOUserDataDevice) (new_cap_addrs (n * 2^gbits) ptr KOUserDataDevice) (ksPSpace \<sigma>)\<rparr>,
           x\<lparr>globals := globals x\<lparr>t_hrs_' :=
                      hrs_htd_update
                       (ptr_retyps_gen (n * 2 ^ gbits) (Ptr ptr :: user_data_device_C ptr) arr)
                       (t_hrs_' (globals x))\<rparr> \<rparr>) \<in> rf_sr"
  (is "\<forall>\<sigma> x. ?P \<sigma> x \<longrightarrow>
    (\<sigma>\<lparr>ksPSpace := ?ks \<sigma>\<rparr>, x\<lparr>globals := globals x\<lparr>t_hrs_' := ?ks' x\<rparr>\<rparr>) \<in> rf_sr")
proof (intro impI allI)
  fix \<sigma> x
  let ?thesis = "(\<sigma>\<lparr>ksPSpace := ?ks \<sigma>\<rparr>, x\<lparr>globals := globals x\<lparr>t_hrs_' := ?ks' x\<rparr>\<rparr>) \<in> rf_sr"
  let ?ks = "?ks \<sigma>"
  let ?ks' = "?ks' x"
  let ?ptr = "Ptr ptr :: user_data_device_C ptr"

  note Kernel_C.user_data_C_size [simp del]

  assume "?P \<sigma> x"
  hence rf: "(\<sigma>, x) \<in> rf_sr" and al: "is_aligned ptr (gbits + pageBits)"
    and ptr0: "ptr \<noteq> 0"
    and sz: "gbits + pageBits \<le> sz"
    and szb: "sz < word_bits"
    and pal: "pspace_aligned' \<sigma>" and pdst: "pspace_distinct' \<sigma>"
    and pno: "pspace_no_overlap' ptr sz \<sigma>"
    and rzo: "ret_zero ptr (n * 2 ^ (gbits + pageBits)) \<sigma>"
    and empty: "region_is_bytes ptr (n * 2 ^ (gbits + pageBits)) x"
    and rc: "range_cover ptr sz (gbits + pageBits) n"
    and rc': "range_cover ptr sz (objBitsKO ko) (n * 2^ gbits)"
    and kdr: "{ptr..+n * 2 ^ (gbits + pageBits)} \<inter> kernel_data_refs = {}"
    by (auto simp: range_cover.aligned objBits_simps  ko_def
                   range_cover_rel[where sbit' = pageBits]
                   range_cover.sz[where 'a=32, folded word_bits_def])


  hence al': "is_aligned ptr (objBitsKO ko)"
    by (clarsimp dest!:is_aligned_weaken range_cover.aligned)

  note range_cover.no_overflow_n[OF rc']
  hence sz_word_bits:
    "n * 2 ^ gbits * size_of TYPE(user_data_device_C)  < 2 ^ word_bits"
      by (simp add:word_bits_def objBits_simps ko_def pageBits_def)

  (* This is a hack *)
  have mko: "\<And>dev. makeObjectKO True (Inr object_type.SmallPageObject) = Some ko"
    by (simp add: makeObjectKO_def ko_def)

  from sz have "2 \<le> sz" by (simp add: objBits_simps pageBits_def ko_def)

  hence sz2: "2 ^ (sz - 2) * 4 = (2 :: nat) ^ sz"
    apply (subgoal_tac "(4 :: nat) = 2 ^ 2")
    apply (erule ssubst)
    apply (subst power_add [symmetric])
    apply (rule arg_cong [where f = "\<lambda>n. 2 ^ n"])
    apply simp
    apply simp
    done

  have p2dist: "n * (2::nat) ^ (gbits + pageBits) = n * 2 ^ gbits * 2 ^ pageBits" (is "?lhs = ?rhs")
    by (simp add:monoid_mult_class.power_add)

  note blah[simp del] =  atLeastAtMost_iff atLeastatMost_subset_iff atLeastLessThan_iff
      Int_atLeastAtMost atLeastatMost_empty_iff split_paired_Ex

  (* /obj specific *)

  (* s/obj/obj'/ *)

  have szo: "size_of TYPE(user_data_device_C) = 2 ^ objBitsKO ko"
    by (simp add: size_of_def objBits_simps archObjSize_def ko_def pageBits_def)
  have szo': "n * 2 ^ (gbits + pageBits) = n * 2 ^ gbits * size_of TYPE(user_data_device_C)" using sz
    apply (subst szo)
    apply (clarsimp simp: power_add[symmetric] objBits_simps ko_def)
    done

  have rb': "region_is_bytes ptr (n * 2 ^ gbits * 2 ^ objBitsKO ko) x"
    using empty
    by (simp add: mult.commute mult.left_commute power_add objBits_simps ko_def)

  from rb' have rbu: "region_is_bytes ptr (n * 2 ^ gbits * size_of TYPE(user_data_device_C)) x"
    by (simp add:szo[symmetric])

  note rl' = clift_ptr_retyps_gen_other[where p = "Ptr ptr",simplified, OF rbu  sz_word_bits]

  (* rest is generic *)

  note rl = projectKO_opt_retyp_other [OF rc' pal pno,unfolded ko_def]
  note cterl = retype_ctes_helper[OF pal pdst pno al' range_cover.sz(2)[OF rc'] range_cover.sz(1)[OF rc', folded word_bits_def] mko rc']
  note ht_rl = clift_eq_h_t_valid_eq[OF rl', OF tag_disj_via_td_name, simplified]

  have guard:
    "\<forall>t<n * 2 ^ gbits. c_guard (CTypesDefs.ptr_add ?ptr (of_nat t))"
    apply (rule retype_guard_helper[OF rc' ptr0 szo,where m = 2])
    apply (clarsimp simp: align_of_def objBits_simps ko_def pageBits_def)+
    done

  have cud2: "\<And>xa v y.
              \<lbrakk> heap_to_device_data
                     (\<lambda>x. if x \<in> set (new_cap_addrs (n*2^gbits) ptr KOUserDataDevice)
                           then Some KOUserData else ksPSpace \<sigma> x)
                     (underlying_memory (ksMachineState \<sigma>)) xa =
              Some v; xa \<notin> set (new_cap_addrs (n*2^gbits) ptr KOUserDataDevice);
              heap_to_device_data (ksPSpace \<sigma>) (underlying_memory (ksMachineState \<sigma>)) xa = Some y \<rbrakk> \<Longrightarrow> y = v"
    using range_cover_intvl[OF rc]
    by (clarsimp simp add: heap_to_device_data_def Let_def sz2
      byte_to_word_heap_def[abs_def] map_comp_Some_iff projectKOs)

  note ptr_retyps_valid = h_t_valid_ptr_retyps_gen_same[OF guard rbu,unfolded addr_card_wb,OF _ sz_word_bits,simplified]

  from rf have "cpspace_relation (ksPSpace \<sigma>) (underlying_memory (ksMachineState \<sigma>)) (t_hrs_' (globals x))"
    unfolding rf_sr_def cstate_relation_def by (simp add: Let_def)

  hence "cpspace_relation ?ks (underlying_memory (ksMachineState \<sigma>)) ?ks'"
    unfolding cpspace_relation_def
    using empty rc' szo
    apply -
    apply (clarsimp simp: rl' tag_disj_via_td_name cte_C_size ht_rl
                          clift_ptr_retyps_gen_other
                          foldr_upd_app_if [folded data_map_insert_def])
    apply (simp add: rl ko_def projectKOs p2dist
                     cterl[unfolded ko_def])
    apply (rule cmap_relationI)
     apply (clarsimp simp: dom_heap_to_device_data cmap_relation_def dom_if image_Un
                           projectKO_opt_retyp_same projectKOs liftt_if[folded hrs_mem_def hrs_htd_def]
                           hrs_htd_update hrs_mem_update ptr_retyps_valid dom_disj_union ptr_add_to_new_cap_addrs)
    apply (simp add: heap_to_device_data_def cuser_user_data_device_relation_def)
    done (* dont need to track all the device memory *)

  thus  ?thesis using rf empty kdr rzo
    apply (simp add: rf_sr_def cstate_relation_def Let_def rl' tag_disj_via_td_name )
    apply (simp add: carch_state_relation_def cmachine_state_relation_def)
    apply (simp add: tag_disj_via_td_name rl' tcb_C_size h_t_valid_clift_Some_iff)
    apply (clarsimp simp: hrs_htd_update szo'[symmetric] cvariable_array_ptr_retyps[OF szo] rb')
    apply (subst zero_ranges_ptr_retyps, simp_all only: szo'[symmetric] power_add,
      simp)
    apply (simp add:szo  p2dist objBits_simps ko_def ptr_retyps_htd_safe_neg
                    kernel_data_refs_domain_eq_rotate
                    rl foldr_upd_app_if [folded data_map_insert_def]
                    projectKOs cvariable_array_ptr_retyps)
    apply (subst cvariable_array_ptr_retyps[OF szo])
    apply (simp add: rb'  ptr_retyps_htd_safe_neg)+
    apply (erule ptr_retyps_htd_safe_neg)
    apply (simp add:pageBits_def field_simps)
    done
qed

lemma placeNewObject_user_data:
  "ccorresG rf_sr \<Gamma> dc xfdc
  (pspace_aligned' and pspace_distinct' and pspace_no_overlap' regionBase (pageBits+us)
  and valid_queues and valid_machine_state'
  and ret_zero regionBase (2 ^ (pageBits+us))
  and (\<lambda>s. sym_refs (state_refs_of' s))
  and (\<lambda>s. 2^(pageBits +  us) \<le> gsMaxObjectSize s)
  and K (regionBase \<noteq> 0 \<and> range_cover regionBase (pageBits + us) (pageBits+us) (Suc 0)
  \<and> us < word_bits
  \<and>  {regionBase..+2^(pageBits +  us)} \<inter> kernel_data_refs = {}))
  ({s. region_actually_is_zero_bytes regionBase (2^(pageBits+us)) s})
  hs
  (placeNewObject regionBase UserData us)
  (global_htd_update (\<lambda>s. (ptr_retyps (2^us) (Ptr regionBase :: user_data_C ptr))))"
  apply (rule ccorres_from_vcg_nofail)
  apply (clarsimp simp:)
  apply (rule conseqPre)
  apply vcg
  apply (clarsimp simp: rf_sr_htd_safe)
  apply (intro conjI allI impI)
   apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def
                         kernel_data_refs_domain_eq_rotate
                  elim!: ptr_retyps_htd_safe_neg[where arr=False,
                        unfolded ptr_retyps_gen_def, simplified])
   apply (simp add: size_of_def pageBits_def power_add mult.commute mult.left_commute)
  apply (frule range_cover.unat_of_nat_shift[where gbits = "pageBits + us"])
    apply simp
   apply (clarsimp simp:size_of_def power_add pageBits_def
     rf_sr_def cstate_relation_def Let_def field_simps)
   apply blast
  apply (frule range_cover.aligned)
  apply (rule bexI [OF _ placeNewObject_eq], simp_all)
    apply (cut_tac ptr=regionBase and sz="pageBits + us" and gbits=us and arr=False
                in createObjects_ccorres_user_data[rule_format])
     apply (rule conjI, assumption, clarsimp)
     apply (fastforce simp: pageBits_def field_simps region_actually_is_bytes)
    apply (clarsimp elim!: rsubst[where P="\<lambda>x. (\<sigma>, x) \<in> rf_sr" for \<sigma>]
                     simp: field_simps objBitsKO_def ptr_retyps_gen_def)
   apply (simp add: objBitsKO_def field_simps)
  apply (rule no_fail_pre, rule no_fail_placeNewObject)
  apply (clarsimp simp: objBitsKO_def)
  done


definition
  createObject_hs_preconds :: "word32 \<Rightarrow> ArchTypes_H.object_type \<Rightarrow> nat \<Rightarrow> bool \<Rightarrow> kernel_state \<Rightarrow> bool"
where
  "createObject_hs_preconds regionBase newType userSize d \<equiv>
     (invs' and pspace_no_overlap' regionBase (getObjectSize newType userSize)
           and caps_overlap_reserved' {regionBase ..+ 2 ^ (getObjectSize newType userSize)}
           and (\<lambda>s. 2 ^ (getObjectSize newType userSize) \<le> gsMaxObjectSize s)
           and K(regionBase \<noteq> 0
                   \<and> ({regionBase..+2 ^ (getObjectSize newType userSize)} \<inter> kernel_data_refs = {})
                   \<and> range_cover regionBase (getObjectSize newType userSize) (getObjectSize newType userSize) (Suc 0)
                   \<and> (newType = APIObjectType apiobject_type.Untyped \<longrightarrow> userSize \<le> maxUntypedSizeBits)
                   \<and> (newType = APIObjectType apiobject_type.CapTableObject \<longrightarrow> userSize < 28)
                   \<and> (newType = APIObjectType apiobject_type.Untyped \<longrightarrow> minUntypedSizeBits \<le> userSize)
                   \<and> (newType = APIObjectType apiobject_type.CapTableObject \<longrightarrow> 0 < userSize)
                   \<and> (d \<longrightarrow> newType = APIObjectType apiobject_type.Untyped \<or> isFrameType newType)
           ))"

abbreviation
  "region_actually_is_dev_bytes ptr len devMem s
    \<equiv> region_actually_is_bytes ptr len s
        \<and> (\<not> devMem \<longrightarrow> heap_list_is_zero (hrs_mem (t_hrs_' (globals s))) ptr len)"

(* these preconds actually used throughout the proof *)
abbreviation(input)
  createObject_c_preconds1 :: "word32 \<Rightarrow> ArchTypes_H.object_type \<Rightarrow> nat \<Rightarrow> bool \<Rightarrow> (globals myvars) set"
where
  "createObject_c_preconds1 regionBase newType userSize deviceMemory \<equiv>
    {s. region_actually_is_dev_bytes regionBase (2 ^ getObjectSize newType userSize) deviceMemory s}"

(* these preconds used at start of proof *)
definition
  createObject_c_preconds :: "word32 \<Rightarrow> ArchTypes_H.object_type \<Rightarrow> nat \<Rightarrow> bool \<Rightarrow> (globals myvars) set"
where
  "createObject_c_preconds regionBase newType userSize deviceMemory \<equiv>
  (createObject_c_preconds1 regionBase newType userSize deviceMemory
           \<inter> {s. object_type_from_H newType = t_' s}
           \<inter> {s. Ptr regionBase = regionBase_' s}
           \<inter> {s. unat (scast (userSize_' s) :: word32) = userSize}
           \<inter> {s. to_bool (deviceMemory_' s) = deviceMemory}
     )"

lemma ccorres_apiType_split:
  "\<lbrakk> apiType = apiobject_type.Untyped \<Longrightarrow> ccorres rr xf P1 P1' hs X Y;
     apiType = apiobject_type.TCBObject \<Longrightarrow> ccorres rr xf P2 P2' hs X Y;
     apiType = apiobject_type.EndpointObject \<Longrightarrow> ccorres rr xf P3 P3' hs X Y;
     apiType = apiobject_type.NotificationObject \<Longrightarrow> ccorres rr xf P4 P4' hs X Y;
     apiType = apiobject_type.CapTableObject \<Longrightarrow> ccorres rr xf P5 P5' hs X Y
   \<rbrakk> \<Longrightarrow> ccorres rr xf
         ((\<lambda>s. apiType = apiobject_type.Untyped \<longrightarrow> P1 s)
         and (\<lambda>s. apiType = apiobject_type.TCBObject \<longrightarrow> P2 s)
         and (\<lambda>s. apiType = apiobject_type.EndpointObject \<longrightarrow> P3 s)
         and (\<lambda>s. apiType = apiobject_type.NotificationObject \<longrightarrow> P4 s)
         and (\<lambda>s. apiType = apiobject_type.CapTableObject \<longrightarrow> P5 s))
         ({s. apiType = apiobject_type.Untyped \<longrightarrow> s \<in> P1'}
         \<inter> {s. apiType = apiobject_type.TCBObject \<longrightarrow> s \<in> P2'}
         \<inter> {s. apiType = apiobject_type.EndpointObject \<longrightarrow> s \<in> P3'}
         \<inter> {s. apiType = apiobject_type.NotificationObject \<longrightarrow> s \<in> P4'}
         \<inter> {s. apiType = apiobject_type.CapTableObject \<longrightarrow> s \<in> P5'})
         hs X Y"
  apply (case_tac apiType, simp_all)
  done

(* FIXME: with the current state of affairs, we could simplify gs_new_frames *)
lemma gsUserPages_update_ccorres:
  "ccorresG rf_sr G dc xf (\<lambda>_. sz = pageBitsForSize pgsz) UNIV hs
     (modify (gsUserPages_update (\<lambda>m a. if a = ptr then Some pgsz else m a)))
     (Basic (globals_update (ghost'state_'_update
                  (gs_new_frames pgsz ptr sz))))"
  apply (rule ccorres_from_vcg)
  apply vcg_step
  apply (clarsimp simp: split_def simpler_modify_def gs_new_frames_def)
  apply (case_tac "ghost'state_' (globals x)")
  apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def fun_upd_def
                        carch_state_relation_def cmachine_state_relation_def
                        ghost_size_rel_def ghost_assertion_data_get_def
                  cong: if_cong)
  done

lemma placeNewObject_user_data_device:
  "ccorresG rf_sr \<Gamma> dc xfdc
  (pspace_aligned' and pspace_distinct'
    and ret_zero regionBase (2 ^ (pageBits + us))
    and pspace_no_overlap' regionBase (pageBits+us) and valid_queues
    and (\<lambda>s. sym_refs (state_refs_of' s))
    and (\<lambda>s. 2^(pageBits +  us) \<le> gsMaxObjectSize s)
    and K (regionBase \<noteq> 0 \<and> range_cover regionBase (pageBits + us) (pageBits+us) (Suc 0)
    \<and>  {regionBase..+2^(pageBits +  us)} \<inter> kernel_data_refs = {}))
  ({s. region_actually_is_bytes regionBase (2^(pageBits+us)) s})
  hs
  (placeNewObject regionBase UserDataDevice us )
  (global_htd_update (\<lambda>s. (ptr_retyps (2^us) (Ptr regionBase :: user_data_device_C ptr))))"
  apply (rule ccorres_from_vcg_nofail)
  apply (clarsimp simp:)
  apply (rule conseqPre)
  apply vcg
  apply (clarsimp simp: rf_sr_htd_safe)
  apply (intro conjI allI impI)
   apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def
                         kernel_data_refs_domain_eq_rotate
                  elim!: ptr_retyps_htd_safe_neg[where arr=False,
                        unfolded ptr_retyps_gen_def, simplified])
   apply (simp add: size_of_def pageBits_def power_add mult.commute mult.left_commute)
  apply (frule range_cover.unat_of_nat_shift[where gbits = "pageBits + us"])
    apply simp
   apply (clarsimp simp:size_of_def power_add pageBits_def
     rf_sr_def cstate_relation_def Let_def field_simps)
   apply blast
  apply (frule range_cover.aligned)
  apply (frule range_cover.sz(1), fold word_bits_def)
  apply (rule bexI [OF _ placeNewObject_eq], simp_all)
    apply (cut_tac ptr=regionBase and sz="pageBits + us" and gbits=us and arr=False
                in createObjects_ccorres_user_data_device[rule_format])
     apply (rule conjI, assumption, clarsimp)
     apply (fastforce simp: pageBits_def field_simps region_actually_is_bytes)
    apply (clarsimp elim!: rsubst[where P="\<lambda>x. (\<sigma>, x) \<in> rf_sr" for \<sigma>]
                     simp: field_simps objBitsKO_def ptr_retyps_gen_def)
   apply (simp add: objBitsKO_def field_simps)
  apply (rule no_fail_pre, rule no_fail_placeNewObject)
  apply (clarsimp simp: objBitsKO_def)
  done

lemma createObjects'_page_directory_at_global:
  "\<lbrace> \<lambda>s. n \<noteq> 0 \<and> range_cover ptr sz (objBitsKO val + gbits) n
      \<and> pspace_aligned' s \<and> pspace_distinct' s \<and> pspace_no_overlap' ptr sz s
      \<and> page_directory_at' (armKSGlobalPD (ksArchState s)) s \<rbrace>
    createObjects' ptr n val gbits
  \<lbrace> \<lambda>rv s. page_directory_at' (armKSGlobalPD (ksArchState s)) s \<rbrace>"
  apply (simp add: page_directory_at'_def)
  apply (rule hoare_pre, wp hoare_vcg_all_lift hoare_vcg_const_imp_lift)
   apply (wps createObjects'_ksArch)
   apply (wp createObjects'_typ_at[where sz=sz])
  apply simp
  done

lemma gsUserPages_update:
    "\<And>f. (\<lambda>s. s\<lparr>gsUserPages := f(gsUserPages s)\<rparr>) = gsUserPages_update f"
    by (rule ext) simp

lemma modify_gsUserPages_update:
  "modify (\<lambda>s. s\<lparr>gsUserPages := f(gsUserPages s)\<rparr>) = modify (gsUserPages_update f)"
  by (simp only: gsUserPages_update)

method arch_create_data_obj_corres_helper =
  (match conclusion in "ccorres ?rel ?var ?P ?P' ?hs
            (ARM_H.createObject object_type.SmallPageObject ?regionBase sz ?deviceMemory)
            (Call Arch_createObject_'proc)
             " for sz \<Rightarrow> \<open>(simp add: toAPIType_def ARM_H.createObject_def
                placeNewDataObject_def bind_assoc
               ARMLargePageBits_def),subst gsUserPages_update,((rule ccorres_gen_asm)+) \<close>)

lemma placeNewDataObject_ccorres:
  "ccorresG rf_sr \<Gamma> dc xfdc
  (createObject_hs_preconds regionBase newType us devMem
      and K (APIType_capBits newType us = pageBits + us))
  ({s. region_actually_is_bytes regionBase (2 ^ (pageBits + us)) s
      \<and> (\<not> devMem \<longrightarrow> heap_list_is_zero (hrs_mem (t_hrs_' (globals s))) regionBase
          (2 ^ (pageBits + us)))})
  hs
  (placeNewDataObject regionBase us devMem)
  (Cond {s. devMem}
    (global_htd_update (\<lambda>s. (ptr_retyps (2^us) (Ptr regionBase :: user_data_device_C ptr))))
    (global_htd_update (\<lambda>s. (ptr_retyps (2^us) (Ptr regionBase :: user_data_C ptr))))
  )"
  apply (cases devMem)
   apply (simp add: placeNewDataObject_def ccorres_cond_univ_iff)
   apply (rule ccorres_guard_imp, rule placeNewObject_user_data_device, simp_all)
   apply (clarsimp simp: createObject_hs_preconds_def invs'_def
                         valid_state'_def valid_pspace'_def)
  apply (simp add: placeNewDataObject_def ccorres_cond_empty_iff)
  apply (rule ccorres_guard_imp, rule placeNewObject_user_data, simp_all)
  apply (clarsimp simp: createObject_hs_preconds_def invs'_def
                        valid_state'_def valid_pspace'_def)
  apply (frule range_cover.sz(1), simp add: word_bits_def)
  done

lemma cond_second_eq_seq_ccorres:
  "ccorres_underlying sr Gamm r xf arrel axf G G' hs m
        (Cond P (a ;; c) (b ;; c) ;; d)
    = ccorres_underlying sr Gamm r xf arrel axf G G' hs m
        (Cond P a b ;; c ;; d)"
  apply (rule ccorres_semantic_equiv)
  apply (rule semantic_equivI)
  apply (auto elim!: exec_Normal_elim_cases intro: exec.Seq exec.CondTrue exec.CondFalse)
  done

lemma Arch_createObject_ccorres:
  assumes t: "toAPIType newType = None"
  shows "ccorres (\<lambda>a b. ccap_relation (ArchObjectCap a) b) ret__struct_cap_C_'
     (createObject_hs_preconds regionBase newType userSize deviceMemory)
     (createObject_c_preconds regionBase newType userSize deviceMemory)
     []
     (Arch.createObject newType regionBase userSize deviceMemory)
     (Call Arch_createObject_'proc)"
proof -
  note if_cong[cong]

  show ?thesis
    apply (clarsimp simp: createObject_c_preconds_def
                          createObject_hs_preconds_def)
    apply (rule ccorres_gen_asm)
    apply clarsimp
    apply (frule range_cover.aligned)
    apply (cut_tac t)
    apply (case_tac newType,
           simp_all add: toAPIType_def
               bind_assoc
               ARMLargePageBits_def)

         apply (cinit' lift: t_' regionBase_' userSize_' deviceMemory_')
          apply (simp add: object_type_from_H_def Kernel_C_defs)
          apply (simp add: ccorres_cond_univ_iff ccorres_cond_empty_iff
                      ARMLargePageBits_def ARMSmallPageBits_def
                      ARMSectionBits_def ARMSuperSectionBits_def asidInvalid_def
                      sle_positive APIType_capBits_def shiftL_nat objBits_simps
                      ptBits_def archObjSize_def pageBits_def word_sle_def word_sless_def
                      fold_eq_0_to_bool)
          apply (ccorres_remove_UNIV_guard)
          apply (clarsimp simp: hrs_htd_update ptBits_def objBits_simps archObjSize_def
            ARM_H.createObject_def pageBits_def
            cond_second_eq_seq_ccorres modify_gsUserPages_update
            intro!: ccorres_rhs_assoc)
          apply ((rule ccorres_return_C | simp | wp | vcg
            | (rule match_ccorres, ctac add:
                    placeNewDataObject_ccorres[where us=0 and newType=newType, simplified]
                    gsUserPages_update_ccorres[folded modify_gsUserPages_update])
            | (rule match_ccorres, csymbr))+)[1]
         apply (intro conjI)
          apply (clarsimp simp: createObject_hs_preconds_def
                                APIType_capBits_def pageBits_def)
         apply (clarsimp simp: pageBits_def ccap_relation_def APIType_capBits_def
                    framesize_to_H_def cap_to_H_simps cap_small_frame_cap_lift
                    vmrights_to_H_def mask_def vm_rights_defs)

        \<comment> \<open>Page objects: could possibly fix the duplication here\<close>
        apply (cinit' lift: t_' regionBase_' userSize_' deviceMemory_')
         apply (simp add: object_type_from_H_def Kernel_C_defs)
         apply (simp add: ccorres_cond_univ_iff ccorres_cond_empty_iff
                     ARMLargePageBits_def ARMSmallPageBits_def
                     ARMSectionBits_def ARMSuperSectionBits_def asidInvalid_def
                     sle_positive APIType_capBits_def shiftL_nat objBits_simps
                     ptBits_def archObjSize_def pageBits_def word_sle_def word_sless_def
                     fold_eq_0_to_bool)
         apply (ccorres_remove_UNIV_guard)
         apply (clarsimp simp: hrs_htd_update ptBits_def objBits_simps archObjSize_def
           ARM_H.createObject_def pageBits_def
           cond_second_eq_seq_ccorres modify_gsUserPages_update
           intro!: ccorres_rhs_assoc)
         apply ((rule ccorres_return_C | simp | wp | vcg
           | (rule match_ccorres, ctac add:
                   placeNewDataObject_ccorres[where us=4 and newType=newType, simplified]
                   gsUserPages_update_ccorres[folded modify_gsUserPages_update])
           | (rule match_ccorres, csymbr))+)[1]
        apply (intro conjI)
         apply (clarsimp simp: createObject_hs_preconds_def
                               APIType_capBits_def pageBits_def)
        apply (clarsimp simp: pageBits_def ccap_relation_def APIType_capBits_def
                   framesize_to_H_def cap_to_H_simps cap_frame_cap_lift
                   vmrights_to_H_def mask_def vm_rights_defs vm_page_size_defs
                   cl_valid_cap_def c_valid_cap_def
                   is_aligned_neg_mask_eq_concrete[THEN sym])

       apply (cinit' lift: t_' regionBase_' userSize_' deviceMemory_')
        apply (simp add: object_type_from_H_def Kernel_C_defs)
        apply (simp add: ccorres_cond_univ_iff ccorres_cond_empty_iff
                    ARMLargePageBits_def ARMSmallPageBits_def
                    ARMSectionBits_def ARMSuperSectionBits_def asidInvalid_def
                    sle_positive APIType_capBits_def shiftL_nat objBits_simps
                    ptBits_def archObjSize_def pageBits_def word_sle_def word_sless_def
                    fold_eq_0_to_bool)
        apply (ccorres_remove_UNIV_guard)
        apply (clarsimp simp: hrs_htd_update ptBits_def objBits_simps archObjSize_def
          ARM_H.createObject_def pageBits_def
          cond_second_eq_seq_ccorres modify_gsUserPages_update
          intro!: ccorres_rhs_assoc)
        apply ((rule ccorres_return_C | simp | wp | vcg
          | (rule match_ccorres, ctac add:
                  placeNewDataObject_ccorres[where us=8 and newType=newType, simplified]
                  gsUserPages_update_ccorres[folded modify_gsUserPages_update])
          | (rule match_ccorres, csymbr))+)[1]
       apply (intro conjI)
        apply (clarsimp simp: createObject_hs_preconds_def
                              APIType_capBits_def pageBits_def)
       apply (clarsimp simp: pageBits_def ccap_relation_def APIType_capBits_def
                  framesize_to_H_def cap_to_H_simps cap_frame_cap_lift
                  vmrights_to_H_def mask_def vm_rights_defs vm_page_size_defs
                  cl_valid_cap_def c_valid_cap_def
                  is_aligned_neg_mask_eq_concrete[THEN sym])

      apply (cinit' lift: t_' regionBase_' userSize_' deviceMemory_')
       apply (simp add: object_type_from_H_def Kernel_C_defs)
       apply (simp add: ccorres_cond_univ_iff ccorres_cond_empty_iff
                   ARMLargePageBits_def ARMSmallPageBits_def
                   ARMSectionBits_def ARMSuperSectionBits_def asidInvalid_def
                   sle_positive APIType_capBits_def shiftL_nat objBits_simps
                   ptBits_def archObjSize_def pageBits_def word_sle_def word_sless_def
                   fold_eq_0_to_bool)
       apply (ccorres_remove_UNIV_guard)
       apply (clarsimp simp: hrs_htd_update ptBits_def objBits_simps archObjSize_def
         ARM_H.createObject_def pageBits_def
         cond_second_eq_seq_ccorres modify_gsUserPages_update
         intro!: ccorres_rhs_assoc)
       apply ((rule ccorres_return_C | simp | wp | vcg
         | (rule match_ccorres, ctac add:
                 placeNewDataObject_ccorres[where us=12 and newType=newType, simplified]
                 gsUserPages_update_ccorres[folded modify_gsUserPages_update])
         | (rule match_ccorres, csymbr))+)[1]
      apply (intro conjI)
       apply (clarsimp simp: createObject_hs_preconds_def
                             APIType_capBits_def pageBits_def)
      apply (clarsimp simp: pageBits_def ccap_relation_def APIType_capBits_def
                 framesize_to_H_def cap_to_H_simps cap_frame_cap_lift
                 vmrights_to_H_def mask_def vm_rights_defs vm_page_size_defs
                 cl_valid_cap_def c_valid_cap_def
                 is_aligned_neg_mask_eq_concrete[THEN sym])

     \<comment> \<open>PageTableObject\<close>
     apply (cinit' lift: t_' regionBase_' userSize_' deviceMemory_')
      apply (simp add: object_type_from_H_def Kernel_C_defs)
      apply (simp add: ccorres_cond_univ_iff ccorres_cond_empty_iff
                  ARMLargePageBits_def ARMSmallPageBits_def
                  ARMSectionBits_def ARMSuperSectionBits_def asidInvalid_def
                  sle_positive APIType_capBits_def shiftL_nat objBits_simps
                  ptBits_def archObjSize_def pageBits_def word_sle_def word_sless_def)
      apply (ccorres_remove_UNIV_guard)
      apply (rule ccorres_rhs_assoc)+
      apply (clarsimp simp: hrs_htd_update ptBits_def objBits_simps archObjSize_def
        ARM_H.createObject_def pageBits_def)
      apply (ctac pre only: add: placeNewObject_pte[simplified])
        apply csymbr
        apply (rule ccorres_return_C)
          apply simp
         apply simp
        apply simp
       apply wp
      apply vcg
     apply clarify
     apply (intro conjI)
      apply (clarsimp simp: invs_pspace_aligned' invs_pspace_distinct' invs_valid_global'
                            APIType_capBits_def invs_queues invs_valid_objs'
                            invs_urz)
     apply clarsimp
     apply (clarsimp simp: pageBits_def ccap_relation_def APIType_capBits_def
                framesize_to_H_def cap_to_H_simps cap_page_table_cap_lift
                is_aligned_neg_mask_eq vmrights_to_H_def
                Kernel_C.VMReadWrite_def Kernel_C.VMNoAccess_def
                Kernel_C.VMKernelOnly_def Kernel_C.VMReadOnly_def)
     apply (simp add: to_bool_def false_def isFrameType_def)

    \<comment> \<open>PageDirectoryObject\<close>
    apply (cinit' lift: t_' regionBase_' userSize_' deviceMemory_')
     apply (simp add: object_type_from_H_def Kernel_C_defs)
     apply (simp add: ccorres_cond_univ_iff ccorres_cond_empty_iff
                asidInvalid_def sle_positive APIType_capBits_def shiftL_nat
                objBits_simps archObjSize_def
                ptBits_def pageBits_def pdBits_def word_sle_def word_sless_def)
     apply (ccorres_remove_UNIV_guard)
     apply (rule ccorres_rhs_assoc)+
     apply (clarsimp simp: hrs_htd_update ptBits_def objBits_simps archObjSize_def
        ARM_H.createObject_def pageBits_def pdBits_def)
     apply (ctac pre only: add: placeNewObject_pde[simplified])
       apply (ctac add: copyGlobalMappings_ccorres)
         apply csymbr
         apply (ctac add: cleanCacheRange_PoU_ccorres)
           apply csymbr
           apply (rule ccorres_return_C)
             apply simp
            apply simp
           apply simp
          apply wp
         apply (clarsimp simp: false_def)
         apply vcg
        apply wp
       apply (clarsimp simp: pageBits_def ccap_relation_def APIType_capBits_def
                  framesize_to_H_def cap_to_H_simps cap_page_directory_cap_lift
                  is_aligned_neg_mask_eq vmrights_to_H_def
                  Kernel_C.VMReadWrite_def Kernel_C.VMNoAccess_def
                  Kernel_C.VMKernelOnly_def Kernel_C.VMReadOnly_def)
       apply (vcg exspec=copyGlobalMappings_modifies)
      apply (clarsimp simp:placeNewObject_def2)
      apply (wp createObjects'_pde_mappings' createObjects'_page_directory_at_global[where sz=pdBits]
                createObjects'_page_directory_at'[where n=0, simplified])
     apply clarsimp
     apply vcg
    apply (clarsimp simp: invs_pspace_aligned' invs_pspace_distinct'
               archObjSize_def invs_valid_global' makeObject_pde pdBits_def
               pageBits_def range_cover.aligned projectKOs APIType_capBits_def
               object_type_from_H_def objBits_simps pdeBits_def
               invs_valid_objs' isFrameType_def)
    apply (frule invs_arch_state')
    apply (frule range_cover.aligned)
    apply (frule is_aligned_addrFromPPtr_n, simp)
    apply (intro conjI, simp_all)
         apply fastforce
        apply fastforce
       apply (clarsimp simp: pageBits_def pdeBits_def
                             valid_arch_state'_def page_directory_at'_def pdBits_def)
      apply (clarsimp simp: is_aligned_no_overflow'[where n=14, simplified] pdeBits_def
                            field_simps is_aligned_mask[symmetric] mask_AND_less_0)+
    done
qed

(* FIXME: with the current state of affairs, we could simplify gs_new_cnodes *)
lemma gsCNodes_update_ccorres:
  "ccorresG rf_sr G dc xf (\<lambda>_. bits = sz + 4)
        \<lbrace> h_t_array_valid (hrs_htd \<acute>t_hrs) (cte_Ptr ptr) (2 ^ sz) \<rbrace> hs
     (modify (gsCNodes_update (\<lambda>m a. if a = ptr then Some sz else m a)))
     (Basic (globals_update (ghost'state_'_update
                  (gs_new_cnodes sz ptr bits))))"
  apply (rule ccorres_from_vcg)
  apply vcg_step
  apply (clarsimp simp: split_def simpler_modify_def gs_new_cnodes_def)
  apply (case_tac "ghost'state_' (globals x)")
  apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def fun_upd_def
                        carch_state_relation_def cmachine_state_relation_def
                        ghost_size_rel_def ghost_assertion_data_get_def
                 cong: if_cong)
  apply (rule cvariable_array_ptr_upd[unfolded fun_upd_def], simp_all)
  done

(* FIXME: move *)
lemma map_to_tcbs_upd:
  "map_to_tcbs (ksPSpace s(t \<mapsto> KOTCB tcb')) = map_to_tcbs (ksPSpace s)(t \<mapsto> tcb')"
  apply (rule ext)
  apply (clarsimp simp: map_comp_def projectKOs split: option.splits if_splits)
  done

(* FIXME: move *)
lemma cmap_relation_updI:
  "\<lbrakk>cmap_relation am cm f rel; am dest = Some ov; rel nv nv'; inj f\<rbrakk> \<Longrightarrow> cmap_relation (am(dest \<mapsto> nv)) (cm(f dest \<mapsto> nv')) f rel"
  apply (clarsimp simp: cmap_relation_def)
  apply (rule conjI)
   apply (drule_tac t="dom cm" in sym)
   apply fastforce
  apply clarsimp
  apply (case_tac "x = dest")
   apply simp
  apply clarsimp
  apply (subgoal_tac "f x \<noteq> f dest")
   apply simp
   apply force
  apply clarsimp
  apply (drule (1) injD)
  apply simp
  done

lemma cep_relations_drop_fun_upd:
  "\<lbrakk> f x = Some v; tcbEPNext_C v' = tcbEPNext_C v; tcbEPPrev_C v' = tcbEPPrev_C v \<rbrakk>
      \<Longrightarrow> cendpoint_relation (f (x \<mapsto> v')) = cendpoint_relation f"
  "\<lbrakk> f x = Some v; tcbEPNext_C v' = tcbEPNext_C v; tcbEPPrev_C v' = tcbEPPrev_C v \<rbrakk>
      \<Longrightarrow> cnotification_relation (f (x \<mapsto> v')) = cnotification_relation f"
  by (intro ext cendpoint_relation_upd_tcb_no_queues[where thread=x]
                cnotification_relation_upd_tcb_no_queues[where thread=x]
          | simp split: if_split)+

lemma threadSet_domain_ccorres [corres]:
  "ccorres dc xfdc (tcb_at' thread) {s. thread' s = tcb_ptr_to_ctcb_ptr thread \<and> d' s = ucast d} hs
           (threadSet (tcbDomain_update (\<lambda>_. d)) thread)
           (Basic (\<lambda>s. globals_update (t_hrs_'_update (hrs_mem_update (heap_update (Ptr &(thread' s\<rightarrow>[''tcbDomain_C''])::word32 ptr) (d' s)))) s))"
  apply (rule ccorres_guard_imp2)
   apply (rule threadSet_ccorres_lemma4 [where P=\<top> and P'=\<top>])
    apply vcg
   prefer 2
   apply (rule conjI, simp)
   apply assumption
  apply clarsimp
  apply (clarsimp simp: rf_sr_def cstate_relation_def Let_def)
  apply (clarsimp simp: cmachine_state_relation_def carch_state_relation_def cpspace_relation_def)
  apply (clarsimp simp: update_tcb_map_tos typ_heap_simps')
  apply (simp add: map_to_ctes_upd_tcb_no_ctes map_to_tcbs_upd tcb_cte_cases_def)
  apply (simp add: cep_relations_drop_fun_upd
                   cvariable_relation_upd_const ko_at_projectKO_opt)
  apply (rule conjI)
   defer
   apply (erule cready_queues_relation_not_queue_ptrs)
    apply (rule ext, simp split: if_split)
   apply (rule ext, simp split: if_split)
  apply (drule ko_at_projectKO_opt)
  apply (erule (2) cmap_relation_upd_relI)
    subgoal by (simp add: ctcb_relation_def)
   apply assumption
  by simp

lemma createObject_ccorres:
  notes APITypecapBits_simps[simp] =
          APIType_capBits_def[split_simps
          object_type.split apiobject_type.split]
  shows
    "ccorres ccap_relation ret__struct_cap_C_'
     (createObject_hs_preconds regionBase newType userSize isdev)
     (createObject_c_preconds regionBase newType userSize isdev)
     []
     (createObject newType regionBase userSize isdev)
     (Call createObject_'proc)"
proof -
  note if_cong[cong]

  have gsCNodes_update:
    "\<And>f. (\<lambda>ks. ks \<lparr>gsCNodes := f (gsCNodes ks)\<rparr>) = gsCNodes_update f"
    by (rule ext) simp

  show ?thesis
  apply (clarsimp simp: createObject_c_preconds_def
                        createObject_hs_preconds_def)
  apply (rule ccorres_gen_asm_state)
  apply (cinit lift: t_' regionBase_' userSize_' deviceMemory_')
   apply (rule ccorres_cond_seq)
   (* Architecture specific objects. *)
   apply (rule_tac
           Q="createObject_hs_preconds regionBase newType userSize isdev" and
           S="createObject_c_preconds1 regionBase newType userSize isdev" and
           R="createObject_hs_preconds regionBase newType userSize isdev" and
           T="createObject_c_preconds1 regionBase newType userSize isdev"
           in ccorres_Cond_rhs)
    apply (subgoal_tac "toAPIType newType = None")
     apply clarsimp
     apply (rule ccorres_rhs_assoc)+
     apply (rule ccorres_guard_imp)
       apply (ctac (no_vcg) add: Arch_createObject_ccorres)
        apply (rule ccorres_return_C_Seq)
        apply (rule ccorres_return_C)
          apply clarsimp
         apply clarsimp
        apply clarsimp
       apply wp[1]
      apply clarsimp
     apply (clarsimp simp: createObject_c_preconds_def
                           region_actually_is_bytes
                           region_actually_is_bytes_def)
    apply (clarsimp simp: object_type_from_H_def
                          Kernel_C_defs toAPIType_def
                          nAPIObjects_def word_sle_def createObject_c_preconds_def
                          word_le_nat_alt
                   split: apiobject_type.splits object_type.splits)
   apply (subgoal_tac "\<exists>apiType. newType = APIObjectType apiType")
    apply clarsimp
    apply (rule ccorres_guard_imp)
      apply (rule_tac apiType=apiType in ccorres_apiType_split)

          (* Untyped *)
          apply (clarsimp simp: Kernel_C_defs object_type_from_H_def
                                toAPIType_def nAPIObjects_def word_sle_def
                        intro!: Corres_UL_C.ccorres_cond_empty
                                Corres_UL_C.ccorres_cond_univ ccorres_rhs_assoc)
          apply (rule_tac
             A ="createObject_hs_preconds regionBase
                   (APIObjectType apiobject_type.Untyped)
                    (unat (userSizea :: word32)) isdev" and
             A'=UNIV in
             ccorres_guard_imp)
            apply (rule ccorres_symb_exec_r)
              apply (rule ccorres_return_C, simp, simp, simp)
             apply vcg
            apply (rule conseqPre, vcg, clarsimp)
           apply simp
          apply (clarsimp simp: ccap_relation_def cap_to_H_def
                                getObjectSize_def apiGetObjectSize_def
                                cap_untyped_cap_lift to_bool_eq_0 true_def
                                aligned_add_aligned
                         split: option.splits)
          apply (subst is_aligned_neg_mask_eq [OF is_aligned_weaken])
            apply (erule range_cover.aligned)
           apply (clarsimp simp:APIType_capBits_def untypedBits_defs)
          apply (clarsimp simp: cap_untyped_cap_lift_def)
          apply (subst word_le_mask_eq, clarsimp simp: mask_def, unat_arith,
                 auto simp: to_bool_eq_0 word_bits_conv untypedBits_defs split:if_splits)[1]

         (* TCB *)
         apply (clarsimp simp: Kernel_C_defs object_type_from_H_def
                               toAPIType_def nAPIObjects_def word_sle_def
                       intro!: Corres_UL_C.ccorres_cond_empty
                               Corres_UL_C.ccorres_cond_univ ccorres_rhs_assoc)
         apply (rule_tac
           A ="createObject_hs_preconds regionBase
                 (APIObjectType apiobject_type.TCBObject) (unat userSizea) isdev" and
           A'="createObject_c_preconds1 regionBase
                 (APIObjectType apiobject_type.TCBObject) (unat userSizea) isdev" in
            ccorres_guard_imp2)
          apply (rule ccorres_symb_exec_r)
            apply (ccorres_remove_UNIV_guard)
            apply (simp add: hrs_htd_update)
            apply (ctac (c_lines 4) add: ccorres_placeNewObject_tcb[simplified])
              apply simp
              apply (rule ccorres_pre_curDomain)
              apply ctac
                apply (rule ccorres_symb_exec_r)
                  apply (rule ccorres_return_C, simp, simp, simp)
                 apply vcg
                apply (rule conseqPre, vcg, clarsimp)
               apply wp
              apply vcg
             apply (simp add: obj_at'_real_def)
             apply (wp placeNewObject_ko_wp_at')
            apply vcg
           apply (clarsimp simp: dc_def)
           apply vcg
          apply (clarsimp simp: CPSR_def)
          apply (rule conseqPre, vcg, clarsimp)
         apply (clarsimp simp: createObject_hs_preconds_def
                               createObject_c_preconds_def)
         apply (frule invs_pspace_aligned')
         apply (frule invs_pspace_distinct')
         apply (frule invs_queues)
         apply (frule invs_sym')
         apply (simp add: getObjectSize_def objBits_simps' word_bits_conv apiGetObjectSize_def
                          new_cap_addrs_def projectKO_opt_tcb)
         apply (clarsimp simp: range_cover.aligned
                               region_actually_is_bytes_def APIType_capBits_def)
         apply (frule(1) ghost_assertion_size_logic_no_unat)
         apply (clarsimp simp: ccap_relation_def cap_to_H_def getObjectSize_def
                               apiGetObjectSize_def cap_thread_cap_lift to_bool_def true_def
                               aligned_add_aligned
                        split: option.splits)
         apply (clarsimp simp: ctcb_ptr_to_tcb_ptr_def ctcb_offset_defs
                               tcb_ptr_to_ctcb_ptr_def
                               invs_valid_objs' invs_urz isFrameType_def)
         apply (subst is_aligned_neg_mask_weaken)
           apply (rule is_aligned_add[where n=ctcb_size_bits, unfolded ctcb_size_bits_def])
             apply (clarsimp elim!: is_aligned_weaken
                             dest!: range_cover.aligned)
            apply (clarsimp simp: is_aligned_def)
           apply (clarsimp simp: word_bits_def)
          apply simp
         apply clarsimp

        (* Endpoint *)
        apply (clarsimp simp: Kernel_C_defs object_type_from_H_def
                              toAPIType_def nAPIObjects_def word_sle_def
                      intro!: ccorres_cond_empty ccorres_cond_univ
                              ccorres_rhs_assoc)
        apply (rule_tac
           A ="createObject_hs_preconds regionBase
                 (APIObjectType apiobject_type.EndpointObject)
                 (unat (userSizea :: machine_word)) isdev" and
           A'="createObject_c_preconds1 regionBase
                 (APIObjectType apiobject_type.EndpointObject)
                 (unat userSizea) isdev" in
           ccorres_guard_imp2)
         apply (ccorres_remove_UNIV_guard)
         apply (simp add: hrs_htd_update)
         apply (ctac (no_vcg) pre only: add: ccorres_placeNewObject_endpoint)
           apply (rule ccorres_symb_exec_r)
             apply (rule ccorres_return_C, simp, simp, simp)
            apply vcg
           apply (rule conseqPre, vcg, clarsimp)
          apply wp
         apply (clarsimp simp: ccap_relation_def cap_to_H_def getObjectSize_def
                               objBits_simps apiGetObjectSize_def epSizeBits_def
                               cap_endpoint_cap_lift to_bool_def true_def
                        split: option.splits
                        dest!: range_cover.aligned)
        apply (clarsimp simp: createObject_hs_preconds_def isFrameType_def)
        apply (frule invs_pspace_aligned')
        apply (frule invs_pspace_distinct')
        apply (frule invs_queues)
        apply (frule invs_sym')
        apply (auto simp: getObjectSize_def objBits_simps
                          apiGetObjectSize_def
                          epSizeBits_def word_bits_conv
                   elim!: is_aligned_no_wrap')[1]

       (* Notification *)
       apply (clarsimp simp: createObject_c_preconds_def)
       apply (clarsimp simp: getObjectSize_def objBits_simps apiGetObjectSize_def
                             epSizeBits_def word_bits_conv word_sle_def word_sless_def)
       apply (clarsimp simp: Kernel_C_defs object_type_from_H_def
                             toAPIType_def nAPIObjects_def word_sle_def
                     intro!: ccorres_cond_empty ccorres_cond_univ
                             ccorres_rhs_assoc)
       apply (rule_tac
         A ="createObject_hs_preconds regionBase
               (APIObjectType apiobject_type.NotificationObject)
               (unat (userSizea :: word32)) isdev" and
         A'="createObject_c_preconds1 regionBase
               (APIObjectType apiobject_type.NotificationObject)
               (unat userSizea) isdev" in
         ccorres_guard_imp2)
        apply (ccorres_remove_UNIV_guard)
        apply (simp add: hrs_htd_update)
        apply (ctac (no_vcg) pre only: add: ccorres_placeNewObject_notification)
          apply (rule ccorres_symb_exec_r)
            apply (rule ccorres_return_C, simp, simp, simp)
           apply vcg
          apply (rule conseqPre, vcg, clarsimp)
         apply wp
        apply (clarsimp simp: ccap_relation_def cap_to_H_def getObjectSize_def
                              apiGetObjectSize_def ntfnSizeBits_def objBits_simps
                              cap_notification_cap_lift to_bool_def true_def
                       dest!: range_cover.aligned
                       split: option.splits)
       apply (clarsimp simp: createObject_hs_preconds_def isFrameType_def)
       apply (frule invs_pspace_aligned')
       apply (frule invs_pspace_distinct')
       apply (frule invs_queues)
       apply (frule invs_sym')
       apply (auto simp: getObjectSize_def objBits_simps apiGetObjectSize_def
                         ntfnSizeBits_def word_bits_conv
                  elim!: is_aligned_no_wrap')[1]

      (* CapTable *)
      apply (clarsimp simp: createObject_c_preconds_def)
      apply (clarsimp simp: getObjectSize_def objBits_simps apiGetObjectSize_def
                            ntfnSizeBits_def word_bits_conv)
      apply (clarsimp simp: Kernel_C_defs object_type_from_H_def toAPIType_def nAPIObjects_def
                            word_sle_def word_sless_def zero_le_sint_32
                    intro!: ccorres_cond_empty ccorres_cond_univ ccorres_rhs_assoc
                            ccorres_move_c_guards ccorres_Guard_Seq)
      apply (rule_tac
         A ="createObject_hs_preconds regionBase
               (APIObjectType apiobject_type.CapTableObject)
               (unat (userSizea :: word32)) isdev" and
         A'="createObject_c_preconds1 regionBase
               (APIObjectType apiobject_type.CapTableObject)
               (unat userSizea) isdev" in
         ccorres_guard_imp2)
       apply (simp add:field_simps hrs_htd_update)
       apply (ccorres_remove_UNIV_guard)
       apply (ctac pre only: add: ccorres_placeNewObject_captable)
         apply (subst gsCNodes_update)
         apply (ctac add: gsCNodes_update_ccorres)
           apply (rule ccorres_symb_exec_r)
             apply (rule ccorres_return_C, simp, simp, simp)
            apply vcg
           apply (rule conseqPre, vcg, clarsimp)
          apply (rule hoare_triv[of \<top>], simp add:hoare_TrueI)
         apply vcg
        apply wp
       apply vcg
      apply (rule conjI)
       apply (clarsimp simp: createObject_hs_preconds_def isFrameType_def)
       apply (frule invs_pspace_aligned')
       apply (frule invs_pspace_distinct')
       apply (frule invs_queues)
       apply (frule invs_sym')
       apply (frule(1) ghost_assertion_size_logic_no_unat)
       apply (clarsimp simp: getObjectSize_def objBits_simps apiGetObjectSize_def
                             cteSizeBits_def word_bits_conv add.commute createObject_c_preconds_def
                             region_actually_is_bytes_def invs_valid_objs' invs_urz
                      elim!: is_aligned_no_wrap'
                       dest: word_of_nat_le)[1]
      apply (clarsimp simp: createObject_hs_preconds_def hrs_htd_update isFrameType_def)
      apply (frule range_cover.strong_times_32[folded addr_card_wb], simp+)
      apply (subst h_t_array_valid_retyp, simp+)
       apply (simp add: power_add cte_C_size objBits_defs)
      apply (frule range_cover.aligned)
      apply (clarsimp simp: ccap_relation_def cap_to_H_def
                            cap_cnode_cap_lift to_bool_def true_def
                            getObjectSize_def
                            apiGetObjectSize_def cteSizeBits_def
                            objBits_simps field_simps is_aligned_power2
                            addr_card_wb is_aligned_weaken[where y=word_size_bits]
                            is_aligned_neg_mask
                     split: option.splits)
      apply (subst word_le_mask_eq[symmetric, THEN eqTrueI])
        apply (clarsimp simp: mask_def)
        apply unat_arith
       apply (clarsimp simp: word_bits_conv)
      apply simp
     apply unat_arith
     apply auto[1]
    apply (clarsimp simp: createObject_c_preconds_def)
    apply (intro impI conjI, simp_all)[1]
   apply (clarsimp simp: nAPIObjects_def object_type_from_H_def Kernel_C_defs
                  split: object_type.splits)
  apply (clarsimp simp: createObject_c_preconds_def
                        createObject_hs_preconds_def)
  done
qed

lemma ccorres_guard_impR:
  "\<lbrakk>ccorres_underlying sr \<Gamma> r xf arrel axf W Q' hs f g; (\<And>s s'. \<lbrakk>(s, s') \<in> sr; s' \<in> A'\<rbrakk> \<Longrightarrow> s' \<in> Q')\<rbrakk>
  \<Longrightarrow> ccorres_underlying sr \<Gamma> r xf arrel axf W A' hs f g"
  by (rule ccorres_guard_imp2,simp+)

lemma tcb_range_subseteq:
  "is_aligned x (objBitsKO (KOTCB ko))
   \<Longrightarrow> {ptr_val (tcb_ptr_to_ctcb_ptr x)..+size_of TYPE(tcb_C)} \<subseteq> {x..x + 2 ^ objBitsKO (KOTCB ko) - 1}"
  apply (simp add: tcb_ptr_to_ctcb_ptr_def)
  apply (rule subset_trans)
   apply (rule intvl_sub_offset[where z = "2^objBitsKO (KOTCB ko)"])
   apply (simp add: ctcb_offset_defs size_of_def objBits_simps')
  apply (subst intvl_range_conv)
    apply simp
   apply (simp add: objBits_simps' word_bits_conv)
  apply simp
  done

lemma pspace_no_overlap_induce_tcb:
  "\<lbrakk>cpspace_relation (ksPSpace (s::kernel_state))
      (underlying_memory (ksMachineState s)) hp;
    pspace_aligned' s; clift hp xa = Some (v::tcb_C);
    is_aligned ptr bits; bits < word_bits;
    pspace_no_overlap' ptr bits s\<rbrakk>
   \<Longrightarrow> {ptr_val xa..+size_of TYPE(tcb_C)} \<inter> {ptr..+2 ^ bits} = {}"
  apply (clarsimp simp:cpspace_relation_def)
  apply (clarsimp simp:cmap_relation_def)
  apply (subgoal_tac "xa\<in>tcb_ptr_to_ctcb_ptr ` dom (map_to_tcbs (ksPSpace s))")
    prefer 2
    apply (simp add:domI)
  apply (thin_tac "S = dom K" for S K)+
  apply (thin_tac "\<forall>x\<in> S. K x" for S K)+
  apply (clarsimp simp: image_def projectKO_opt_tcb map_comp_def
                 split: option.splits kernel_object.split_asm)
  apply (frule(1) pspace_no_overlapD')
  apply (rule disjoint_subset[OF tcb_range_subseteq[simplified]])
   apply (erule(1) pspace_alignedD')
  apply (subst intvl_range_conv)
   apply (simp add: word_bits_def)+
  done

lemma pspace_no_overlap_induce_endpoint:
  "\<lbrakk>cpspace_relation (ksPSpace (s::kernel_state))
      (underlying_memory (ksMachineState s)) hp;
    pspace_aligned' s; clift hp xa = Some (v::endpoint_C);
    is_aligned ptr bits; bits < word_bits;
    pspace_no_overlap' ptr bits s\<rbrakk>
   \<Longrightarrow> {ptr_val xa..+size_of TYPE(endpoint_C)} \<inter> {ptr..+2 ^ bits} = {}"
  apply (clarsimp simp: cpspace_relation_def)
  apply (clarsimp simp: cmap_relation_def)
  apply (subgoal_tac "xa\<in>ep_Ptr ` dom (map_to_eps (ksPSpace s))")
   prefer 2
   subgoal by (simp add: domI)
  apply (thin_tac "S = dom K" for S K)+
  apply (thin_tac "\<forall>x\<in> S. K x" for S K)+
  apply (clarsimp simp: image_def projectKO_opt_ep map_comp_def
                 split: option.splits kernel_object.split_asm)
  apply (frule(1) pspace_no_overlapD')
  apply (subst intvl_range_conv)
    apply simp
   apply (simp add: word_bits_def)
  apply (simp add: size_of_def)
  apply (subst intvl_range_conv[where bits = epSizeBits, simplified epSizeBits_def, simplified])
    apply (drule(1) pspace_alignedD')
    apply (simp add: objBits_simps' archObjSize_def
              split: arch_kernel_object.split_asm)
   apply (simp add: word_bits_conv)
  apply (simp add: objBits_simps' archObjSize_def
            split: arch_kernel_object.split_asm)
  done

lemma pspace_no_overlap_induce_notification:
  "\<lbrakk>cpspace_relation (ksPSpace (s::kernel_state))
      (underlying_memory (ksMachineState s)) hp;
    pspace_aligned' s; clift hp xa = Some (v::notification_C);
    is_aligned ptr bits; bits < word_bits;
    pspace_no_overlap' ptr bits s\<rbrakk>
   \<Longrightarrow> {ptr_val xa..+size_of TYPE(notification_C)} \<inter> {ptr..+2 ^ bits} = {}"
  apply (clarsimp simp: cpspace_relation_def)
  apply (clarsimp simp: cmap_relation_def size_of_def)
  apply (subgoal_tac "xa\<in>ntfn_Ptr ` dom (map_to_ntfns (ksPSpace s))")
   prefer 2
   apply (simp add: domI)
  apply (thin_tac "S = dom K" for S K)+
  apply (thin_tac "\<forall>x\<in> S. K x" for S K)+
  apply (clarsimp simp: image_def projectKO_opt_ntfn map_comp_def
                 split: option.splits kernel_object.split_asm)
  apply (frule(1) pspace_no_overlapD')
  apply (subst intvl_range_conv)
    apply simp
   apply (simp add: word_bits_def)
  apply (subst intvl_range_conv[where bits = ntfnSizeBits, simplified ntfnSizeBits_def, simplified])
    apply (drule(1) pspace_alignedD')
    apply (simp add: objBits_simps' archObjSize_def
              split: arch_kernel_object.split_asm)
   apply (simp add: word_bits_conv)
  apply (simp add: objBits_simps' archObjSize_def
            split: arch_kernel_object.split_asm)
  done

lemma ctes_of_ko_at_strong:
  "\<lbrakk>ctes_of s p = Some a; is_aligned p cteSizeBits\<rbrakk> \<Longrightarrow>
  (\<exists>ptr ko. (ksPSpace s ptr = Some ko \<and> {p ..+ 2^cteSizeBits} \<subseteq> obj_range' ptr ko))"
  apply (clarsimp simp: map_to_ctes_def Let_def split: if_split_asm)
   apply (intro exI conjI, assumption)
   apply (simp add: obj_range'_def objBits_simps is_aligned_no_wrap' field_simps)
   apply (subst intvl_range_conv[where bits=cteSizeBits])
      apply simp
     apply (simp add: word_bits_def objBits_defs)
    apply (simp add: field_simps)
  apply (intro exI conjI, assumption)
  apply (clarsimp simp: objBits_simps obj_range'_def word_and_le2)
  apply (cut_tac intvl_range_conv[where bits=cteSizeBits and ptr=p, simplified])
    defer
    apply simp
   apply (simp add: word_bits_conv objBits_defs)
  apply (intro conjI)
   apply (rule order_trans[OF word_and_le2])
   apply clarsimp
  apply clarsimp
  apply (thin_tac "P \<or> Q" for P Q)
  apply (erule order_trans)
  apply (subst word_plus_and_or_coroll2[where x=p and w="mask tcbBlockSizeBits",symmetric])
  apply (clarsimp simp: tcb_cte_cases_def field_simps split: if_split_asm;
         simp only: p_assoc_help;
         rule word_plus_mono_right[OF _ is_aligned_no_wrap', OF _ Aligned.is_aligned_neg_mask[OF le_refl]];
         simp add: objBits_defs)
  done

lemma pspace_no_overlap_induce_cte:
  "\<lbrakk>cpspace_relation (ksPSpace (s::kernel_state))
      (underlying_memory (ksMachineState s)) hp;
    pspace_aligned' s; clift hp xa = Some (v::cte_C);
    is_aligned ptr bits; bits < word_bits;
    pspace_no_overlap' ptr bits s\<rbrakk>
   \<Longrightarrow> {ptr_val xa..+size_of TYPE(cte_C)} \<inter> {ptr..+2 ^ bits} = {}"
  apply (clarsimp simp: cpspace_relation_def)
  apply (clarsimp simp: cmap_relation_def size_of_def)
  apply (subgoal_tac "xa\<in>cte_Ptr ` dom (ctes_of s)")
   prefer 2
   apply (simp add:domI)
  apply (thin_tac "S = dom K" for S K)+
  apply (thin_tac "\<forall>x\<in> S. K x" for S K)+
  apply (clarsimp simp: image_def projectKO_opt_cte map_comp_def
                 split: option.splits kernel_object.split_asm)
  apply (frule ctes_of_is_aligned)
  apply (simp add: objBits_simps)
  apply (drule ctes_of_ko_at_strong)
   apply simp
  apply (clarsimp simp: objBits_defs)
  apply (erule disjoint_subset)
  apply (frule(1) pspace_no_overlapD')
  apply (subst intvl_range_conv)
    apply simp
   apply (simp add: word_bits_def)
  apply (simp add: obj_range'_def)
  done

lemma pspace_no_overlap_induce_asidpool:
  "\<lbrakk>cpspace_relation (ksPSpace (s::kernel_state)) (underlying_memory (ksMachineState s)) hp;
    pspace_aligned' s; clift hp xa = Some (v::asid_pool_C);
    is_aligned ptr bits; bits < word_bits;
    pspace_no_overlap' ptr bits s\<rbrakk>
     \<Longrightarrow> {ptr_val xa..+size_of TYPE(asid_pool_C)} \<inter> {ptr..+2 ^ bits} = {}"
  apply (clarsimp simp:cpspace_relation_def)
  apply (clarsimp simp:cmap_relation_def size_of_def)
  apply (subgoal_tac "xa\<in>ap_Ptr ` dom (map_to_asidpools (ksPSpace s))")
    prefer 2
    apply (simp add:domI)
  apply (thin_tac "S = dom K" for S K)+
  apply (thin_tac "\<forall>x\<in> S. K x" for S K)+
  apply (clarsimp simp:image_def projectKO_opt_asidpool
    map_comp_def split:option.splits kernel_object.split_asm)
  apply (frule(1) pspace_no_overlapD')
   apply (subst intvl_range_conv)
     apply simp
    apply (simp add: word_bits_def)
   apply (subst intvl_range_conv[where bits = 12,simplified])
    apply (drule(1) pspace_alignedD')
    apply (simp add: objBits_simps archObjSize_def pageBits_def split:arch_kernel_object.split_asm)
    apply (clarsimp elim!:is_aligned_weaken)
  apply (simp only: is_aligned_neg_mask_eq)
  apply (erule disjoint_subset[rotated])
  apply (clarsimp simp: field_simps)
  apply (simp add: p_assoc_help)
   apply (rule word_plus_mono_right)
   apply (clarsimp simp:objBits_simps archObjSize_def pageBits_def split:arch_kernel_object.split_asm)+
  done

lemma pspace_no_overlap_induce_user_data:
  "\<lbrakk>cpspace_relation (ksPSpace (s::kernel_state)) (underlying_memory (ksMachineState s)) hp;
    pspace_aligned' s; clift hp xa = Some (v::user_data_C);
    is_aligned ptr bits; bits < word_bits;
    pspace_no_overlap' ptr bits s\<rbrakk>
     \<Longrightarrow> {ptr_val xa..+size_of TYPE(user_data_C)} \<inter> {ptr..+2 ^ bits} = {}"
  apply (clarsimp simp:cpspace_relation_def)
  apply (clarsimp simp:cmap_relation_def size_of_def)
  apply (subgoal_tac "xa\<in>Ptr ` dom (heap_to_user_data (ksPSpace s) (underlying_memory (ksMachineState s)))")
    prefer 2
    apply (simp add:domI)
  apply (thin_tac "S = dom K" for S K)+
  apply (thin_tac "\<forall>x\<in> S. K x" for S K)+
  apply (clarsimp simp: image_def heap_to_user_data_def projectKO_opt_user_data map_comp_def
                 split: option.splits kernel_object.splits)
  apply (frule(1) pspace_no_overlapD')
  apply (clarsimp simp: word_bits_def)
   apply (subst intvl_range_conv[where bits = 12,simplified])
    apply (drule(1) pspace_alignedD')
    apply (simp add:objBits_simps archObjSize_def pageBits_def split:arch_kernel_object.split_asm)
    apply (clarsimp elim!:is_aligned_weaken)
  apply (subst intvl_range_conv, simp, simp)
  apply (clarsimp simp: field_simps)
  apply (simp add: p_assoc_help)
  apply (clarsimp simp: objBits_simps archObjSize_def pageBits_def split:arch_kernel_object.split_asm)+
  done

lemma pspace_no_overlap_induce_device_data:
  "\<lbrakk>cpspace_relation (ksPSpace (s::kernel_state)) (underlying_memory (ksMachineState s)) hp;
    pspace_aligned' s; clift hp xa = Some (v::user_data_device_C);
    is_aligned ptr bits; bits < word_bits;
    pspace_no_overlap' ptr bits s\<rbrakk>
     \<Longrightarrow> {ptr_val xa..+size_of TYPE(user_data_C)} \<inter> {ptr..+2 ^ bits} = {}"
  apply (clarsimp simp: cpspace_relation_def)
  apply (clarsimp simp: cmap_relation_def size_of_def)
  apply (subgoal_tac "xa\<in>Ptr ` dom (heap_to_device_data (ksPSpace s) (underlying_memory (ksMachineState s)))")
    prefer 2
    apply (simp add: domI)
  apply (thin_tac "S = dom K" for S K)+
  apply (thin_tac "\<forall>x\<in> S. K x" for S K)+
  apply (clarsimp simp: image_def heap_to_device_data_def projectKO_opt_user_data_device map_comp_def
                 split: option.splits kernel_object.splits)
  apply (frule(1) pspace_no_overlapD')
  apply (clarsimp simp: word_bits_def)
   apply (subst intvl_range_conv[where bits = 12,simplified])
    apply (drule(1) pspace_alignedD')
    apply (simp add: objBits_simps archObjSize_def pageBits_def split: arch_kernel_object.split_asm)
    apply (clarsimp elim!: is_aligned_weaken)
  apply (subst intvl_range_conv, simp, simp)
  apply (clarsimp simp: field_simps)
  apply (simp add: p_assoc_help)
  apply (clarsimp simp: objBits_simps archObjSize_def pageBits_def split:arch_kernel_object.split_asm)+
  done

lemma typ_region_bytes_dom:
 "typ_uinfo_t TYPE('b) \<noteq> typ_uinfo_t TYPE (word8)
    \<Longrightarrow> dom (clift (hrs_htd_update (typ_region_bytes ptr bits) hp) :: 'b :: mem_type typ_heap)
  \<subseteq>  dom ((clift hp) :: 'b :: mem_type typ_heap)"
  apply (clarsimp simp: liftt_if split: if_splits)
  apply (case_tac "{ptr_val x ..+ size_of TYPE('b)} \<inter> {ptr ..+ 2 ^ bits} = {}")
   apply (clarsimp simp: h_t_valid_def valid_footprint_def Let_def
                         hrs_htd_update_def split_def typ_region_bytes_def)
   apply (drule spec, drule(1) mp)
   apply (simp add: size_of_def split: if_split_asm)
   apply (drule subsetD[OF equalityD1], rule IntI, erule intvlI, simp)
   apply simp
  apply (clarsimp simp: set_eq_iff)
  apply (drule(1) h_t_valid_intvl_htd_contains_uinfo_t)
  apply (clarsimp simp: hrs_htd_update_def typ_region_bytes_def split_def
                 split: if_split_asm)
  done

lemma lift_t_typ_region_bytes_none:
  "\<lbrakk> \<And>x (v :: 'a). lift_t g hp x = Some v
    \<Longrightarrow> {ptr_val x ..+ size_of TYPE('a)} \<inter> {ptr ..+ 2 ^ bits} = {};
     typ_uinfo_t TYPE('a) \<noteq> typ_uinfo_t TYPE(8 word) \<rbrakk> \<Longrightarrow>
  lift_t g (hrs_htd_update (typ_region_bytes ptr bits) hp)
    = (lift_t g hp :: (('a :: mem_type) ptr) \<Rightarrow> _)"
  apply atomize
  apply (subst lift_t_typ_region_bytes, simp_all)
   apply (clarsimp simp: liftt_if hrs_htd_def split: if_splits)
  apply (rule ext, simp add: restrict_map_def)
  apply (rule ccontr, clarsimp split: if_splits)
  apply (clarsimp simp: liftt_if hrs_htd_def split: if_splits)
  apply (clarsimp simp: set_eq_iff intvl_self)
  done

lemma typ_bytes_cpspace_relation_clift_userdata:
assumes "cpspace_relation (ksPSpace s) (underlying_memory (ksMachineState (s::kernel_state))) hp"
  and "is_aligned ptr bits" "bits < word_bits"
  and "pspace_aligned' s"
  and "pspace_no_overlap' ptr bits s"
shows "clift (hrs_htd_update (typ_region_bytes ptr bits) hp) = ((clift hp) :: (user_data_C ptr \<rightharpoonup> user_data_C))"
  (is "?lhs = ?rhs")
  using assms
  apply -
  apply (rule lift_t_typ_region_bytes_none, simp_all)
  apply (rule pspace_no_overlap_induce_user_data[simplified], auto)
  done


lemma typ_bytes_cpspace_relation_clift_devicedata:
assumes "cpspace_relation (ksPSpace s) (underlying_memory (ksMachineState (s::kernel_state))) hp"
  and "is_aligned ptr bits" "bits < word_bits"
  and "pspace_aligned' s"
  and "pspace_no_overlap' ptr bits s"
 shows "clift (hrs_htd_update (typ_region_bytes ptr bits) hp) = ((clift hp) :: (user_data_device_C ptr \<rightharpoonup> user_data_device_C))"
  (is "?lhs = ?rhs")
  using assms
  apply -
  apply (rule lift_t_typ_region_bytes_none, simp_all)
  apply (rule pspace_no_overlap_induce_device_data[simplified], auto)
  done


lemma pspace_no_overlap_induce_pte:
  "\<lbrakk>cpspace_relation (ksPSpace (s::kernel_state)) (underlying_memory (ksMachineState s)) hp;
    pspace_aligned' s; clift hp xa = Some (v::pte_C);
    is_aligned ptr bits; bits < word_bits;
    pspace_no_overlap' ptr bits s\<rbrakk>
     \<Longrightarrow> {ptr_val xa..+size_of TYPE(pte_C)} \<inter> {ptr..+2 ^ bits} = {}"
  apply (clarsimp simp:cpspace_relation_def)
  apply (clarsimp simp:cmap_relation_def)
  apply (subgoal_tac "xa\<in>pte_Ptr ` dom (map_to_ptes (ksPSpace s))")
    prefer 2
    apply (simp add:domI)
  apply (thin_tac "S = dom K" for S K)+
  apply (thin_tac "\<forall>x\<in> S. K x" for S K)+
  apply (clarsimp simp: image_def projectKO_opt_pte map_comp_def
                 split: option.splits kernel_object.split_asm)
  apply (frule(1) pspace_no_overlapD')
   apply (subst intvl_range_conv)
     apply simp
    apply (simp add: word_bits_def)
   apply (subst intvl_range_conv[where bits = 2,simplified])
    apply (drule(1) pspace_alignedD')
    apply (simp add: objBits_simps archObjSize_def pteBits_def
                split:arch_kernel_object.split_asm)
   apply (simp add: word_bits_conv)
  apply (simp add: objBits_simps archObjSize_def  pteBits_def
              split:arch_kernel_object.split_asm)
  done

lemma pspace_no_overlap_induce_pde:
  "\<lbrakk>cpspace_relation (ksPSpace (s::kernel_state)) (underlying_memory (ksMachineState s)) hp;
    pspace_aligned' s; clift hp xa = Some (v::pde_C);
    is_aligned ptr bits; bits < word_bits;
    pspace_no_overlap' ptr bits s\<rbrakk>
     \<Longrightarrow> {ptr_val xa..+size_of TYPE(pde_C)} \<inter> {ptr..+2 ^ bits} = {}"
  apply (clarsimp simp:cpspace_relation_def)
  apply (clarsimp simp:cmap_relation_def)
  apply (subgoal_tac "xa\<in>pde_Ptr ` dom (map_to_pdes (ksPSpace s))")
    prefer 2
    subgoal by (simp add:domI)
  apply (thin_tac "S = dom K" for S K)+
  apply (thin_tac "\<forall>x\<in> S. K x" for S K)+
  apply (clarsimp simp:image_def projectKO_opt_pde
    map_comp_def split:option.splits kernel_object.split_asm)
  apply (frule(1) pspace_no_overlapD')
   apply (subst intvl_range_conv)
     apply simp
    apply (simp add: word_bits_def)
   apply (subst intvl_range_conv[where bits = 2,simplified])
    apply (drule(1) pspace_alignedD')
    apply (simp add: objBits_simps archObjSize_def pdeBits_def
                split:arch_kernel_object.split_asm)
   apply (simp add:word_bits_conv)
  by (simp add: objBits_simps archObjSize_def pdeBits_def
           split:arch_kernel_object.split_asm)


lemma typ_bytes_cpspace_relation_clift_tcb:
assumes "cpspace_relation (ksPSpace s) (underlying_memory (ksMachineState (s::kernel_state))) hp"
  and "is_aligned ptr bits" "bits < word_bits"
  and "pspace_aligned' s"
  and "pspace_no_overlap' ptr bits s"
 shows "clift (hrs_htd_update (typ_region_bytes ptr bits) hp) = ((clift hp) :: (tcb_C ptr \<rightharpoonup> tcb_C))"
  (is "?lhs = ?rhs")
  using assms
  apply -
  apply (rule lift_t_typ_region_bytes_none, simp_all)
  apply (erule(5) pspace_no_overlap_induce_tcb[simplified])
  done

lemma typ_bytes_cpspace_relation_clift_pde:
assumes "cpspace_relation (ksPSpace s) (underlying_memory (ksMachineState (s::kernel_state))) hp"
  and "is_aligned ptr bits" "bits < word_bits"
  and "pspace_aligned' s"
  and "pspace_no_overlap' ptr bits s"
 shows "clift (hrs_htd_update (typ_region_bytes ptr bits) hp) = ((clift hp) :: (pde_C ptr \<rightharpoonup> pde_C))"
  (is "?lhs = ?rhs")
  using assms
  apply -
  apply (rule lift_t_typ_region_bytes_none, simp_all)
  apply (erule(5) pspace_no_overlap_induce_pde[unfolded size_of_def,simplified])
  done

lemma typ_bytes_cpspace_relation_clift_pte:
assumes "cpspace_relation (ksPSpace s) (underlying_memory (ksMachineState (s::kernel_state))) hp"
  and "is_aligned ptr bits" "bits < word_bits"
  and "pspace_aligned' s"
  and "pspace_no_overlap' ptr bits s"
 shows "clift (hrs_htd_update (typ_region_bytes ptr bits) hp) = ((clift hp) :: (pte_C ptr \<rightharpoonup> pte_C))"
  (is "?lhs = ?rhs")
  using assms
  apply -
  apply (rule lift_t_typ_region_bytes_none, simp_all)
  apply (erule(5) pspace_no_overlap_induce_pte[unfolded size_of_def,simplified])
  done

lemma typ_bytes_cpspace_relation_clift_endpoint:
assumes "cpspace_relation (ksPSpace s) (underlying_memory (ksMachineState (s::kernel_state))) hp"
  and "is_aligned ptr bits" "bits < word_bits"
  and "pspace_aligned' s"
  and "pspace_no_overlap' ptr bits s"
 shows "clift (hrs_htd_update (typ_region_bytes ptr bits) hp) = ((clift hp) :: (endpoint_C ptr \<rightharpoonup> endpoint_C))"
  (is "?lhs = ?rhs")
  using assms
  apply -
  apply (rule lift_t_typ_region_bytes_none, simp_all)
  apply (erule(5) pspace_no_overlap_induce_endpoint[simplified])
  done

lemma typ_bytes_cpspace_relation_clift_notification:
assumes "cpspace_relation (ksPSpace s) (underlying_memory (ksMachineState (s::kernel_state))) hp"
  and "is_aligned ptr bits" "bits < word_bits"
  and "pspace_aligned' s"
  and "pspace_no_overlap' ptr bits s"
 shows "clift (hrs_htd_update (typ_region_bytes ptr bits) hp) = ((clift hp) :: (notification_C ptr \<rightharpoonup> notification_C))"
  (is "?lhs = ?rhs")
  using assms
  apply -
  apply (rule lift_t_typ_region_bytes_none, simp_all)
  apply (erule(5) pspace_no_overlap_induce_notification[simplified])
  done

lemma typ_bytes_cpspace_relation_clift_asid_pool:
assumes "cpspace_relation (ksPSpace s) (underlying_memory (ksMachineState (s::kernel_state))) hp"
  and "is_aligned ptr bits" "bits < word_bits"
  and "pspace_aligned' s"
  and "pspace_no_overlap' ptr bits s"
 shows "clift (hrs_htd_update (typ_region_bytes ptr bits) hp) = ((clift hp) :: (asid_pool_C ptr \<rightharpoonup> asid_pool_C))"
  (is "?lhs = ?rhs")
  using assms
  apply -
  apply (rule lift_t_typ_region_bytes_none, simp_all)
  apply (erule(5) pspace_no_overlap_induce_asidpool[simplified])
  done

lemma typ_bytes_cpspace_relation_clift_cte:
assumes "cpspace_relation (ksPSpace s) (underlying_memory (ksMachineState (s::kernel_state))) hp"
  and "is_aligned ptr bits" "bits < word_bits"
  and "pspace_aligned' s"
  and "pspace_no_overlap' ptr bits s"
 shows "clift (hrs_htd_update (typ_region_bytes ptr bits) hp) = ((clift hp) :: (cte_C ptr \<rightharpoonup> cte_C))"
  (is "?lhs = ?rhs")
  using assms
  apply -
  apply (rule lift_t_typ_region_bytes_none)
   apply (erule(5) pspace_no_overlap_induce_cte)
  apply (simp add: cte_C_size)
  done

lemma typ_bytes_cpspace_relation_clift_gptr:
assumes "cpspace_relation (ksPSpace s) (underlying_memory (ksMachineState (s::kernel_state))) hp"
  and "is_aligned ptr bits" "bits < word_bits"
  and "pspace_aligned' s"
  and "kernel_data_refs \<inter> {ptr ..+ 2^bits} = {}"
  and "ptr_span (ptr' :: 'a ptr) \<subseteq> kernel_data_refs"
  and "typ_uinfo_t TYPE('a :: mem_type) \<noteq> typ_uinfo_t TYPE(8 word)"
 shows "clift (hrs_htd_update (typ_region_bytes ptr bits) hp)
    ptr'
  = (clift hp) ptr'"
  (is "?lhs = ?rhs ptr'")
  using assms
  apply -
   apply (case_tac "ptr' \<notin> dom ?rhs")
   apply (frule contra_subsetD[OF typ_region_bytes_dom[where ptr = ptr and bits = bits], rotated])
    apply simp
   apply fastforce
  apply (clarsimp simp: liftt_if hrs_htd_update_def split_def split: if_splits)
  apply (simp add: h_t_valid_typ_region_bytes)
  apply blast
  done

lemma cmap_array_typ_region_bytes_triv[OF refl]:
  "ptrf = (Ptr :: _ \<Rightarrow> 'b ptr)
    \<Longrightarrow> carray_map_relation bits' (map_comp f (ksPSpace s)) (h_t_valid htd c_guard) ptrf
    \<Longrightarrow> is_aligned ptr bits
    \<Longrightarrow> pspace_no_overlap' ptr bits s
    \<Longrightarrow> pspace_aligned' s
    \<Longrightarrow> typ_uinfo_t TYPE('b :: c_type) \<noteq> typ_uinfo_t TYPE(8 word)
    \<Longrightarrow> size_of TYPE('b) = 2 ^ bits'
    \<Longrightarrow> objBitsT (koType TYPE('a :: pspace_storable)) \<le> bits
    \<Longrightarrow> objBitsT (koType TYPE('a :: pspace_storable)) \<le> bits'
    \<Longrightarrow> bits' < word_bits
    \<Longrightarrow> carray_map_relation bits' (map_comp (f :: _ \<Rightarrow> 'a option) (ksPSpace s))
        (h_t_valid (typ_region_bytes ptr bits htd) c_guard) ptrf"
  apply (frule(7) cmap_array_typ_region_bytes[where ptrf=ptrf])
  apply (subst(asm) restrict_map_subdom, simp_all)
  apply (drule(1) pspace_no_overlap_disjoint')
  apply (simp add: upto_intvl_eq)
  apply (rule order_trans[OF map_comp_subset_dom])
  apply auto
  done

lemma h_t_array_first_element_at:
  "h_t_array_valid htd p n
    \<Longrightarrow> 0 < n
    \<Longrightarrow> gd p
    \<Longrightarrow> h_t_valid htd gd (p :: ('a :: wf_type) ptr)"
  apply (clarsimp simp: h_t_array_valid_def h_t_valid_def valid_footprint_def
                        Let_def CTypes.sz_nzero[unfolded size_of_def])
  apply(drule_tac x="y" in spec, erule impE)
   apply (erule order_less_le_trans, simp add: size_of_def)
  apply (clarsimp simp: uinfo_array_tag_n_m_def upt_conv_Cons)
  apply (erule map_le_trans[rotated])
  apply (simp add: list_map_mono split: if_split)
  done

end

definition
  "cnodes_retype_have_size R bits cns
    = (\<forall>ptr' sz'. cns ptr' = Some sz'
        \<longrightarrow> is_aligned ptr' (cte_level_bits + sz')
            \<and> ({ptr' ..+ 2 ^ (cte_level_bits + sz')} \<inter> R = {}
                \<or> cte_level_bits + sz' = bits))"

lemma cnodes_retype_have_size_mono:
  "cnodes_retype_have_size T bits cns \<and> S \<subseteq> T
    \<longrightarrow> cnodes_retype_have_size S bits cns"
  by (auto simp add: cnodes_retype_have_size_def)

context kernel_m begin

lemma gsCNodes_typ_region_bytes:
  "cvariable_array_map_relation (gsCNodes \<sigma>) ((^) 2) cte_Ptr (hrs_htd hrs)
    \<Longrightarrow> cnodes_retype_have_size {ptr..+2 ^ bits} bits (gsCNodes \<sigma>)
    \<Longrightarrow> 0 \<notin> {ptr..+2 ^ bits} \<Longrightarrow> is_aligned ptr bits
    \<Longrightarrow> clift (hrs_htd_update (typ_region_bytes ptr bits) hrs)
        = (clift hrs :: cte_C ptr \<Rightarrow> _)
    \<Longrightarrow> cvariable_array_map_relation (gsCNodes \<sigma>) ((^) 2) cte_Ptr
        (typ_region_bytes ptr bits (hrs_htd hrs))"
  apply (clarsimp simp: cvariable_array_map_relation_def
                        h_t_array_valid_def)
  apply (elim allE, drule(1) mp)
  apply (subst valid_footprint_typ_region_bytes)
   apply (simp add: uinfo_array_tag_n_m_def typ_uinfo_t_def typ_info_word)
  apply (clarsimp simp: cnodes_retype_have_size_def field_simps)
  apply (elim allE, drule(1) mp)
  apply (subgoal_tac "size_of TYPE(cte_C) * 2 ^ v = 2 ^ (cte_level_bits + v)")
  prefer 2
   apply (simp add: cte_C_size cte_level_bits_def power_add)
  apply (clarsimp simp add: upto_intvl_eq[symmetric] field_simps)
  apply (case_tac "p \<in> {ptr ..+ 2 ^ bits}")
   apply (drule h_t_array_first_element_at[where p="Ptr p" and gd=c_guard for p,
       unfolded h_t_array_valid_def, simplified])
     apply simp
    apply (rule is_aligned_c_guard[where m=2], simp+)
       apply clarsimp
      apply (simp add: align_of_def)
     apply (simp add: size_of_def cte_level_bits_def power_add)
    apply (simp add: cte_level_bits_def)
   apply (drule_tac x="cte_Ptr p" in fun_cong)
   apply (simp add: liftt_if[folded hrs_htd_def] hrs_htd_update
                    h_t_valid_def valid_footprint_typ_region_bytes
             split: if_split_asm)
   apply (subgoal_tac "p \<in> {p ..+ size_of TYPE(cte_C)}")
    apply (simp add: cte_C_size)
    apply blast
   apply (simp add: intvl_self)
  apply (simp only: upto_intvl_eq mask_in_range[symmetric])
  apply (rule aligned_ranges_subset_or_disjoint_coroll, simp_all)
  done

lemma tcb_ctes_typ_region_bytes:
  "cvariable_array_map_relation (map_to_tcbs (ksPSpace \<sigma>))
      (\<lambda>x. 5) cte_Ptr (hrs_htd hrs)
    \<Longrightarrow> pspace_no_overlap' ptr bits \<sigma>
    \<Longrightarrow> pspace_aligned' \<sigma>
    \<Longrightarrow> is_aligned ptr bits
    \<Longrightarrow> cpspace_tcb_relation (ksPSpace \<sigma>) hrs
    \<Longrightarrow> cvariable_array_map_relation (map_to_tcbs (ksPSpace \<sigma>)) (\<lambda>x. 5)
        cte_Ptr (typ_region_bytes ptr bits (hrs_htd hrs))"
  apply (clarsimp simp: cvariable_array_map_relation_def
                        h_t_array_valid_def)
  apply (drule spec, drule mp, erule exI)
  apply (subst valid_footprint_typ_region_bytes)
   apply (simp add: uinfo_array_tag_n_m_def typ_uinfo_t_def typ_info_word)
  apply (clarsimp simp only: map_comp_Some_iff projectKOs
                             pspace_no_overlap'_def is_aligned_neg_mask_eq
                             field_simps upto_intvl_eq[symmetric])
  apply (elim allE, drule(1) mp)
  apply simp
  apply (drule(1) pspace_alignedD')
  apply (erule disjoint_subset[rotated])
  apply (simp add: upto_intvl_eq[symmetric])
  apply (rule intvl_start_le)
  apply (simp add: objBits_simps' cte_C_size)
  done

lemma ccorres_typ_region_bytes_dummy:
  "ccorresG rf_sr
     AnyGamma dc xfdc
     (invs' and ct_active' and sch_act_simple and
      pspace_no_overlap' ptr bits and
      (cnodes_retype_have_size S bits o gsCNodes)
      and K (bits < word_bits \<and> is_aligned ptr bits \<and> 2 \<le> bits
         \<and> 0 \<notin> {ptr..+2 ^ bits}
         \<and> {ptr ..+ 2 ^ bits} \<subseteq> S
         \<and> kernel_data_refs \<inter> {ptr..+2 ^ bits} = {}))
     UNIV hs
     (return ())
     (global_htd_update (\<lambda>_. (typ_region_bytes ptr bits)))"
  apply (rule ccorres_from_vcg)
  apply (clarsimp simp: return_def)
  apply (simp add: rf_sr_def)
  apply vcg
  apply (clarsimp simp: cstate_relation_def Let_def)
  apply (frule typ_bytes_cpspace_relation_clift_tcb)
      apply (simp add: invs_pspace_aligned')+
  apply (frule typ_bytes_cpspace_relation_clift_pte)
      apply (simp add: invs_pspace_aligned')+
  apply (frule typ_bytes_cpspace_relation_clift_pde)
      apply (simp add: invs_pspace_aligned')+
  apply (frule typ_bytes_cpspace_relation_clift_endpoint)
      apply (simp add: invs_pspace_aligned')+
  apply (frule typ_bytes_cpspace_relation_clift_notification)
      apply (simp add: invs_pspace_aligned')+
  apply (frule typ_bytes_cpspace_relation_clift_asid_pool)
      apply (simp add: invs_pspace_aligned')+
  apply (frule typ_bytes_cpspace_relation_clift_cte)
      apply (simp add: invs_pspace_aligned')+
  apply (frule typ_bytes_cpspace_relation_clift_userdata)
      apply (simp add: invs_pspace_aligned')+
  apply (frule typ_bytes_cpspace_relation_clift_devicedata)
      apply (simp add: invs_pspace_aligned')+
  apply (frule typ_bytes_cpspace_relation_clift_gptr[where ptr'="armKSGlobalPD_Ptr"])
        apply (simp add: invs_pspace_aligned')+
  apply (frule typ_bytes_cpspace_relation_clift_gptr[where ptr'="intStateIRQNode_array_Ptr"])
        apply (simp add: invs_pspace_aligned')+
  apply (simp add: carch_state_relation_def cmachine_state_relation_def)
  apply (simp add: cpspace_relation_def htd_safe_typ_region_bytes)
  apply (simp add: h_t_valid_clift_Some_iff)
  apply (simp add: hrs_htd_update gsCNodes_typ_region_bytes
                   cnodes_retype_have_size_mono[where T=S]
                   tcb_ctes_typ_region_bytes[OF _ _ invs_pspace_aligned'])
  apply (simp add: cmap_array_typ_region_bytes_triv
               invs_pspace_aligned' pdBits_def pageBits_def ptBits_def
               objBitsT_simps word_bits_def pteBits_def pdeBits_def
               zero_ranges_are_zero_typ_region_bytes)
  apply (rule htd_safe_typ_region_bytes, simp)
  apply blast
  done

lemma insertNewCap_sch_act_simple[wp]:
 "\<lbrace>sch_act_simple\<rbrace>insertNewCap a b c\<lbrace>\<lambda>_. sch_act_simple\<rbrace>"
  by (simp add:sch_act_simple_def,wp)

lemma updateMDB_ctes_of_cap:
  "\<lbrace>\<lambda>s. (\<forall>x\<in>ran(ctes_of s). P (cteCap x)) \<and> no_0 (ctes_of s)\<rbrace>
    updateMDB srcSlot t
  \<lbrace>\<lambda>r s. \<forall>x\<in>ran (ctes_of s). P (cteCap x)\<rbrace>"
  apply (rule hoare_pre)
  apply wp
  apply (clarsimp)
  apply (erule ranE)
  apply (clarsimp simp:modify_map_def split:if_splits)
   apply (drule_tac x = z in bspec)
    apply fastforce
   apply simp
  apply (drule_tac x = x in bspec)
   apply fastforce
  apply simp
  done

lemma insertNewCap_caps_no_overlap'':
notes blah[simp del] =  atLeastAtMost_iff atLeastatMost_subset_iff atLeastLessThan_iff
      Int_atLeastAtMost atLeastatMost_empty_iff split_paired_Ex
shows "\<lbrace>cte_wp_at' (\<lambda>_. True) cptr and valid_pspace'
        and caps_no_overlap'' ptr us
        and K  (cptr \<noteq> (0::word32)) and K (untypedRange x \<inter> {ptr..(ptr && ~~ mask us) + 2 ^ us - 1} = {})\<rbrace>
 insertNewCap srcSlot cptr x
          \<lbrace>\<lambda>rv s. caps_no_overlap'' ptr us s\<rbrace>"
  apply (clarsimp simp:insertNewCap_def caps_no_overlap''_def)
  apply (rule hoare_pre)
   apply (wp getCTE_wp updateMDB_ctes_of_cap)
  apply (clarsimp simp:cte_wp_at_ctes_of valid_pspace'_def
    valid_mdb'_def valid_mdb_ctes_def no_0_def split:if_splits)
  apply (erule ranE)
  apply (clarsimp split:if_splits)
  apply (frule_tac c=  "(cteCap xa)" and q = xb in caps_no_overlapD''[rotated])
   apply (clarsimp simp:cte_wp_at_ctes_of)
  apply clarsimp
  apply blast
  done

lemma insertNewCap_caps_overlap_reserved':
notes blah[simp del] =  atLeastAtMost_iff atLeastatMost_subset_iff atLeastLessThan_iff
      Int_atLeastAtMost atLeastatMost_empty_iff split_paired_Ex
shows "\<lbrace>cte_wp_at' (\<lambda>_. True) cptr and valid_pspace' and caps_overlap_reserved' S
        and valid_cap' x and K  (cptr \<noteq> (0::word32)) and K (untypedRange x \<inter> S = {})\<rbrace>
       insertNewCap srcSlot cptr x
       \<lbrace>\<lambda>rv s. caps_overlap_reserved' S s\<rbrace>"
   apply (clarsimp simp:insertNewCap_def caps_overlap_reserved'_def)
   apply (rule hoare_pre)
   apply (wp getCTE_wp updateMDB_ctes_of_cap)
   apply (clarsimp simp:cte_wp_at_ctes_of valid_pspace'_def
    valid_mdb'_def valid_mdb_ctes_def no_0_def split:if_splits)
   apply (erule ranE)
   apply (clarsimp split:if_splits)
   apply (drule usableRange_subseteq[rotated])
     apply (simp add:valid_cap'_def)
    apply blast
   apply (drule_tac p = xaa in caps_overlap_reserved'_D)
     apply simp
    apply simp
   apply blast
  done

lemma insertNewCap_pspace_no_overlap':
notes blah[simp del] =  atLeastAtMost_iff atLeastatMost_subset_iff atLeastLessThan_iff
      Int_atLeastAtMost atLeastatMost_empty_iff split_paired_Ex
shows "\<lbrace>pspace_no_overlap' ptr sz and pspace_aligned'
  and pspace_distinct' and cte_wp_at' (\<lambda>_. True) cptr\<rbrace>
  insertNewCap srcSlot cptr x
  \<lbrace>\<lambda>rv s. pspace_no_overlap' ptr sz s\<rbrace>"
   apply (clarsimp simp:insertNewCap_def)
   apply (rule hoare_pre)
   apply (wp updateMDB_pspace_no_overlap'
     setCTE_pspace_no_overlap' getCTE_wp)
   apply (clarsimp simp:cte_wp_at_ctes_of)
   done

lemma insertNewCap_cte_at:
  "\<lbrace>cte_at' p\<rbrace> insertNewCap srcSlot q cap
   \<lbrace>\<lambda>rv. cte_at' p\<rbrace>"
  apply (clarsimp simp:insertNewCap_def)
  apply (wp getCTE_wp)
  apply (clarsimp simp:cte_wp_at_ctes_of)
  done

lemma createObject_invs':
  "\<lbrace>\<lambda>s. invs' s \<and> ct_active' s \<and> pspace_no_overlap' ptr (APIType_capBits ty us) s
          \<and> caps_no_overlap'' ptr (APIType_capBits ty us) s \<and> ptr \<noteq> 0 \<and>
          caps_overlap_reserved' {ptr..ptr + 2 ^ APIType_capBits ty us - 1} s \<and>
          (ty = APIObjectType apiobject_type.CapTableObject \<longrightarrow> 0 < us) \<and>
          is_aligned ptr (APIType_capBits ty us) \<and> APIType_capBits ty us < word_bits \<and>
          {ptr..ptr + 2 ^ APIType_capBits ty us - 1} \<inter> kernel_data_refs = {} \<and>
          0 < gsMaxObjectSize s
    \<rbrace> createObject ty ptr us dev\<lbrace>\<lambda>r s. invs' s \<rbrace>"
  apply (simp add:createObject_def3)
  apply (rule hoare_pre)
  apply (wp createNewCaps_invs'[where sz = "APIType_capBits ty us"])
  apply (clarsimp simp:range_cover_full)
  done

lemma createObject_sch_act_simple[wp]:
  "\<lbrace>\<lambda>s. sch_act_simple s
    \<rbrace>createObject ty ptr us dev\<lbrace>\<lambda>r s. sch_act_simple s \<rbrace>"
 apply (simp add:sch_act_simple_def)
 apply wp
 done

lemma createObject_ct_active'[wp]:
  "\<lbrace>\<lambda>s. ct_active' s \<and> pspace_aligned' s \<and> pspace_distinct' s
     \<and>  pspace_no_overlap' ptr (APIType_capBits ty us) s
     \<and>  is_aligned ptr (APIType_capBits ty us) \<and> APIType_capBits ty us < word_bits
    \<rbrace>createObject ty ptr us dev\<lbrace>\<lambda>r s. ct_active' s \<rbrace>"
 apply (simp add:ct_in_state'_def createObject_def3)
 apply (rule hoare_pre)
 apply wp
 apply wps
 apply (wp createNewCaps_pred_tcb_at')
 apply (intro conjI)
 apply (auto simp:range_cover_full)
 done

lemma createObject_notZombie[wp]:
  "\<lbrace>\<top>\<rbrace>createObject ty ptr us dev \<lbrace>\<lambda>r s. \<not> isZombie r\<rbrace>"
  apply (rule hoare_pre)
  apply (simp add:createObject_def)
   apply wpc
    apply (wp| clarsimp simp add:isCap_simps)+
   apply wpc
    apply (wp| clarsimp simp add:isCap_simps)+
  done

lemma createObject_valid_cap':
  "\<lbrace>\<lambda>s. pspace_no_overlap' ptr (APIType_capBits ty us) s \<and>
         valid_pspace' s \<and>
         is_aligned ptr (APIType_capBits ty us) \<and>
          APIType_capBits ty us < word_bits \<and>
         (ty = APIObjectType apiobject_type.CapTableObject \<longrightarrow> 0 < us) \<and>
         (ty = APIObjectType apiobject_type.Untyped \<longrightarrow> minUntypedSizeBits \<le> us \<and> us \<le> maxUntypedSizeBits) \<and> ptr \<noteq> 0\<rbrace>
    createObject ty ptr us dev \<lbrace>\<lambda>r s. s \<turnstile>' r\<rbrace>"
  apply (simp add:createObject_def3)
  apply (rule hoare_pre)
  apply wp
   apply (rule_tac Q = "\<lambda>r s. r \<noteq> [] \<and> Q r s" for Q in hoare_strengthen_post)
   apply (rule hoare_vcg_conj_lift)
     apply (rule hoare_strengthen_post[OF createNewCaps_ret_len])
      apply clarsimp
     apply (rule hoare_strengthen_post[OF createNewCaps_valid_cap'[where sz = "APIType_capBits ty us"]])
    apply assumption
   apply clarsimp
  apply (clarsimp simp add:word_bits_conv range_cover_full)
  done

lemma createObject_untypedRange:
  assumes split:
    "\<lbrace>P\<rbrace> createObject ty ptr us dev
     \<lbrace>\<lambda>m s. (toAPIType ty = Some apiobject_type.Untyped \<longrightarrow>
                            Q {ptr..ptr + 2 ^ us - 1} s) \<and>
            (toAPIType ty \<noteq> Some apiobject_type.Untyped \<longrightarrow> Q {} s)\<rbrace>"
  shows "\<lbrace>P\<rbrace> createObject ty ptr us dev\<lbrace>\<lambda>m s. Q (untypedRange m) s\<rbrace>"
  including no_pre
  using split
  apply (simp add: createObject_def)
  apply (case_tac "toAPIType ty")
   apply (simp add: split | wp)+
   apply (simp add: valid_def return_def bind_def split_def)
  apply (case_tac a, simp_all)
      apply (simp add: valid_def return_def simpler_gets_def simpler_modify_def
                       bind_def split_def curDomain_def)+
  done

lemma createObject_capRange:
shows "\<lbrace>P\<rbrace>createObject ty ptr us dev \<lbrace>\<lambda>m s. capRange m = {ptr.. ptr + 2 ^ (APIType_capBits ty us) - 1}\<rbrace>"
  apply (simp add:createObject_def)
  apply (case_tac "ty")
    apply (simp_all add:toAPIType_def ARM_H.toAPIType_def)
        apply (rule hoare_pre)
         apply wpc
             apply wp
        apply (simp add:split untypedRange.simps objBits_simps capRange_def APIType_capBits_def | wp)+
       apply (simp add:ARM_H.createObject_def capRange_def APIType_capBits_def
         acapClass.simps | wp)+
  done

lemma createObject_capRange_helper:
assumes static: "\<lbrace>P\<rbrace>createObject ty ptr us dev \<lbrace>\<lambda>m s. Q {ptr.. ptr + 2 ^ (APIType_capBits ty us) - 1} s\<rbrace>"
shows "\<lbrace>P\<rbrace>createObject ty ptr us dev \<lbrace>\<lambda>m s. Q (capRange m) s\<rbrace>"
  apply (rule hoare_pre)
   apply (rule hoare_strengthen_post[OF hoare_vcg_conj_lift])
     apply (rule static)
    apply (rule createObject_capRange)
   apply simp
  apply simp
  done

lemma createObject_caps_overlap_reserved':
  "\<lbrace>\<lambda>s. caps_overlap_reserved' S s \<and>
         pspace_aligned' s \<and>
         pspace_distinct' s \<and> pspace_no_overlap' ptr (APIType_capBits ty us) s \<and>
         is_aligned ptr (APIType_capBits ty us) \<and> APIType_capBits ty us < word_bits
    \<rbrace>createObject ty ptr us dev \<lbrace>\<lambda>rv. caps_overlap_reserved' S\<rbrace>"
  apply (simp add:createObject_def3)
  apply (wp createNewCaps_caps_overlap_reserved'[where sz = "APIType_capBits ty us"])
  apply (clarsimp simp:range_cover_full)
  done

lemma createObject_caps_overlap_reserved_ret':
  "\<lbrace>\<lambda>s.  caps_overlap_reserved' {ptr..ptr + 2 ^ APIType_capBits ty us - 1} s \<and>
         pspace_aligned' s \<and>
         pspace_distinct' s \<and> pspace_no_overlap' ptr (APIType_capBits ty us) s \<and>
         is_aligned ptr (APIType_capBits ty us) \<and> APIType_capBits ty us < word_bits
    \<rbrace>createObject ty ptr us dev \<lbrace>\<lambda>rv. caps_overlap_reserved' (untypedRange rv)\<rbrace>"
  apply (simp add:createObject_def3)
  apply (rule hoare_pre)
  apply wp
   apply (rule_tac Q = "\<lambda>r s. r \<noteq> [] \<and> Q r s" for Q in hoare_strengthen_post)
   apply (rule hoare_vcg_conj_lift)
     apply (rule hoare_strengthen_post[OF createNewCaps_ret_len])
      apply clarsimp
     apply (rule hoare_strengthen_post[OF createNewCaps_caps_overlap_reserved_ret'[where sz = "APIType_capBits ty us"]])
    apply assumption
   apply (case_tac r,simp)
   apply clarsimp
   apply (erule caps_overlap_reserved'_subseteq)
   apply (rule untypedRange_in_capRange)
  apply (clarsimp simp add:word_bits_conv range_cover_full)
  done

lemma createObject_descendants_range':
  "\<lbrace>\<lambda>s.  descendants_range_in' {ptr..ptr + 2 ^ APIType_capBits ty us - 1} q (ctes_of s) \<and>
         pspace_aligned' s \<and>
         pspace_distinct' s \<and> pspace_no_overlap' ptr (APIType_capBits ty us) s \<and>
         is_aligned ptr (APIType_capBits ty us) \<and> APIType_capBits ty us < word_bits
    \<rbrace>createObject ty ptr us dev \<lbrace>\<lambda>rv s. descendants_range' rv q (ctes_of s)\<rbrace>"
  apply (simp add:createObject_def3)
  apply (rule hoare_pre)
  apply wp
   apply (rule_tac Q = "\<lambda>r s. r \<noteq> [] \<and> Q r s" for Q in hoare_strengthen_post)
   apply (rule hoare_vcg_conj_lift)
     apply (rule hoare_strengthen_post[OF createNewCaps_ret_len])
      apply clarsimp
     apply (rule hoare_strengthen_post[OF createNewCaps_descendants_range_ret'[where sz = "APIType_capBits ty us"]])
    apply assumption
   apply fastforce
  apply (clarsimp simp add:word_bits_conv range_cover_full)
  done

lemma createObject_descendants_range_in':
  "\<lbrace>\<lambda>s.  descendants_range_in' S q (ctes_of s) \<and>
         pspace_aligned' s \<and>
         pspace_distinct' s \<and> pspace_no_overlap' ptr (APIType_capBits ty us) s \<and>
         is_aligned ptr (APIType_capBits ty us) \<and> APIType_capBits ty us < word_bits
    \<rbrace>createObject ty ptr us dev \<lbrace>\<lambda>rv s. descendants_range_in' S q (ctes_of s)\<rbrace>"
  apply (simp add:createObject_def3 descendants_range_in'_def2)
  apply (wp createNewCaps_null_filter')
  apply clarsimp
  apply (intro conjI)
   apply simp
  apply (simp add:range_cover_full)
  done

lemma createObject_idlethread_range:
  "\<lbrace>\<lambda>s. is_aligned ptr (APIType_capBits ty us) \<and> APIType_capBits ty us < word_bits
        \<and> ksIdleThread s \<notin> {ptr..ptr + 2 ^ (APIType_capBits ty us) - 1}\<rbrace>
   createObject ty ptr us dev \<lbrace>\<lambda>cap s. ksIdleThread s \<notin> capRange cap\<rbrace>"
  apply (simp add:createObject_def3)
  apply (rule hoare_pre)
  apply wp
   apply (rule_tac Q = "\<lambda>r s. r \<noteq> [] \<and> Q r s" for Q in hoare_strengthen_post)
   apply (rule hoare_vcg_conj_lift)
     apply (rule hoare_strengthen_post[OF createNewCaps_ret_len])
      apply clarsimp
     apply (rule hoare_strengthen_post[OF createNewCaps_idlethread_ranges[where sz = "APIType_capBits ty us"]])
    apply assumption
   apply clarsimp
  apply (clarsimp simp:word_bits_conv range_cover_full)
  done

lemma createObject_IRQHandler:
  "\<lbrace>\<top>\<rbrace> createObject ty ptr us dev
    \<lbrace>\<lambda>rv s. rv = IRQHandlerCap x \<longrightarrow> P rv s x\<rbrace>"
  apply (simp add:createObject_def3)
  apply (rule hoare_pre)
  apply wp
   apply (rule_tac Q = "\<lambda>r s. r \<noteq> [] \<and> Q r s" for Q in hoare_strengthen_post)
   apply (rule hoare_vcg_conj_lift)
     apply (rule hoare_strengthen_post[OF createNewCaps_ret_len])
      apply clarsimp
     apply (rule hoare_strengthen_post[OF createNewCaps_IRQHandler[where irq = x and P = "\<lambda>_ _. False"]])
    apply assumption
   apply (case_tac r,clarsimp+)
  apply (clarsimp simp:word_bits_conv)
  done

lemma createObject_capClass[wp]:
  "\<lbrace> \<lambda>s. is_aligned ptr (APIType_capBits ty us) \<and> APIType_capBits ty us < word_bits
   \<rbrace> createObject ty ptr us dev
   \<lbrace>\<lambda>rv s. capClass rv = PhysicalClass\<rbrace>"
  apply (simp add:createObject_def3)
  apply (rule hoare_pre)
  apply wp
   apply (rule_tac Q = "\<lambda>r s. r \<noteq> [] \<and> Q r s" for Q in hoare_strengthen_post)
   apply (rule hoare_vcg_conj_lift)
     apply (rule hoare_strengthen_post[OF createNewCaps_ret_len])
      apply clarsimp
     apply (rule hoare_strengthen_post[OF createNewCaps_range_helper])
    apply assumption
   apply (case_tac r,clarsimp+)
  apply (clarsimp simp:word_bits_conv )
  apply (rule range_cover_full)
   apply (simp add:word_bits_conv)+
  done

lemma createObject_child:
  "\<lbrace>\<lambda>s.
     is_aligned ptr (APIType_capBits ty us) \<and> APIType_capBits ty us < word_bits \<and>
     {ptr .. ptr + (2^APIType_capBits ty us) - 1} \<subseteq> (untypedRange cap) \<and> isUntypedCap cap
   \<rbrace> createObject ty ptr us dev
   \<lbrace>\<lambda>rv s. sameRegionAs cap rv\<rbrace>"
  apply (rule hoare_assume_pre)
  apply (simp add:createObject_def3)
  apply wp
  apply (rule hoare_chain [OF createNewCaps_range_helper[where sz = "APIType_capBits ty us"]])
   apply (fastforce simp:range_cover_full)
  apply clarsimp
  apply (drule_tac x = ptr in spec)
   apply (case_tac "(capfn ptr)")
   apply (simp_all add:capUntypedPtr_def sameRegionAs_def Let_def isCap_simps)+
    apply clarsimp+
    apply (rename_tac arch_capability d v0 v1 f)
    apply (case_tac arch_capability)
     apply (simp add:ARM_H.capUntypedSize_def)+
     apply (simp add: is_aligned_no_wrap' field_simps ptBits_def pteBits_def)
    apply (simp add:ARM_H.capUntypedSize_def)+
    apply (simp add: is_aligned_no_wrap' field_simps pdBits_def pdeBits_def)
  apply clarsimp+
  done

lemma createObject_parent_helper:
  "\<lbrace>\<lambda>s. cte_wp_at' (\<lambda>cte. isUntypedCap (cteCap cte)
         \<and> {ptr .. ptr + (2^APIType_capBits ty us) - 1} \<subseteq> untypedRange (cteCap cte)) p s \<and>
         pspace_aligned' s \<and>
         pspace_distinct' s \<and>
         pspace_no_overlap' ptr (APIType_capBits ty us) s \<and>
         is_aligned ptr (APIType_capBits ty us) \<and> APIType_capBits ty us < word_bits \<and>
         (ty = APIObjectType apiobject_type.CapTableObject \<longrightarrow> 0 < us)
    \<rbrace>
    createObject ty ptr us dev
    \<lbrace>\<lambda>rv. cte_wp_at' (\<lambda>cte. isUntypedCap (cteCap cte) \<and> (sameRegionAs (cteCap cte) rv)) p\<rbrace>"
  apply (rule hoare_post_imp [where Q="\<lambda>rv s. \<exists>cte. cte_wp_at' ((=) cte) p s
                                           \<and> isUntypedCap (cteCap cte) \<and>
                                sameRegionAs (cteCap cte) rv"])
  apply (clarsimp simp:cte_wp_at_ctes_of)
  apply (wp hoare_vcg_ex_lift)
   apply (rule hoare_vcg_conj_lift)
   apply (simp add:createObject_def3)
    apply (wp createNewCaps_cte_wp_at')
   apply (wp createObject_child)
  apply (clarsimp simp:cte_wp_at_ctes_of)
  apply (intro conjI)
   apply (erule range_cover_full)
    apply simp
  apply simp
  done

lemma insertNewCap_untypedRange:
  "\<lbrace>\<lambda>s. cte_wp_at' (\<lambda>cte. isUntypedCap (cteCap cte) \<and> P untypedRange (cteCap cte)) srcSlot s\<rbrace>
    insertNewCap srcSlot destSlot x
   \<lbrace>\<lambda>rv s. cte_wp_at' (\<lambda>cte. isUntypedCap (cteCap cte) \<and> P untypedRange (cteCap cte)) srcSlot s\<rbrace>"
  apply (simp add:insertNewCap_def)
  apply (wp updateMDB_weak_cte_wp_at setCTE_cte_wp_at_other getCTE_wp)
  apply (clarsimp simp:cte_wp_at_ctes_of)
  done

lemma createObject_caps_no_overlap'':
  " \<lbrace>\<lambda>s. caps_no_overlap'' (ptr + (1 + of_nat n << APIType_capBits newType userSize))
                     sz s \<and>
     pspace_aligned' s \<and> pspace_distinct' s \<and>
     pspace_no_overlap' (ptr + (of_nat n << APIType_capBits newType userSize)) (APIType_capBits newType userSize) s
     \<and> is_aligned ptr (APIType_capBits newType userSize)
     \<and> APIType_capBits newType userSize < word_bits\<rbrace>
   createObject newType (ptr + (of_nat n << APIType_capBits newType userSize)) userSize dev
   \<lbrace>\<lambda>rv s. caps_no_overlap'' (ptr + (1 + of_nat n << APIType_capBits newType userSize))
                     sz s \<rbrace>"
  apply (clarsimp simp:createObject_def3 caps_no_overlap''_def2)
  apply (wp createNewCaps_null_filter')
  apply clarsimp
  apply (intro conjI)
   apply simp
  apply (rule range_cover_full)
   apply (erule aligned_add_aligned)
     apply (rule is_aligned_shiftl_self)
    apply simp
   apply simp
  done

lemma createObject_ex_cte_cap_wp_to:
  "\<lbrace>\<lambda>s. ex_cte_cap_wp_to' P p s \<and> is_aligned ptr (APIType_capBits ty us) \<and> pspace_aligned' s
    \<and> pspace_distinct' s \<and> (APIType_capBits ty us) < word_bits  \<and> pspace_no_overlap' ptr (APIType_capBits ty us) s \<rbrace>
    createObject ty ptr us dev
   \<lbrace>\<lambda>rv s. ex_cte_cap_wp_to' P p s \<rbrace>"
  apply (clarsimp simp:ex_cte_cap_wp_to'_def createObject_def3)
  apply (rule hoare_pre)
   apply (wp hoare_vcg_ex_lift)
   apply wps
   apply (wp createNewCaps_cte_wp_at')
  apply clarsimp
  apply (intro exI conjI)
      apply assumption
     apply (rule range_cover_full)
    apply (clarsimp simp:cte_wp_at_ctes_of)
   apply simp
  apply simp
  done

lemma range_cover_one:
  "\<lbrakk>is_aligned (ptr :: 'a :: len word) us; us\<le> sz;sz < len_of TYPE('a)\<rbrakk>
  \<Longrightarrow> range_cover ptr sz us (Suc 0)"
  apply (clarsimp simp:range_cover_def)
  apply (rule Suc_leI)
  apply (rule unat_less_power)
   apply simp
  apply (rule shiftr_less_t2n)
   apply simp
  apply (rule le_less_trans[OF word_and_le1])
  apply (simp add:mask_def)
  done

lemma createObject_no_inter:
notes blah[simp del] =  atLeastAtMost_iff atLeastatMost_subset_iff atLeastLessThan_iff
      Int_atLeastAtMost atLeastatMost_empty_iff split_paired_Ex
shows
  "\<lbrace>\<lambda>s. range_cover ptr sz (APIType_capBits newType userSize) (n + 2) \<and> ptr \<noteq> 0\<rbrace>
  createObject newType (ptr + (of_nat n << APIType_capBits newType userSize)) userSize dev
  \<lbrace>\<lambda>rv s. untypedRange rv \<inter>
  {ptr + (1 + of_nat n << APIType_capBits newType userSize) ..
   ptrend } =
  {}\<rbrace>"
  apply (rule createObject_untypedRange)
  apply (clarsimp | wp)+
  apply (clarsimp simp: blah toAPIType_def APIType_capBits_def
    ARM_H.toAPIType_def split: object_type.splits)
  apply (clarsimp simp:shiftl_t2n field_simps)
  apply (drule word_eq_zeroI)
  apply (drule(1) range_cover_no_0[where p = "Suc n"])
   apply simp
  apply (simp add:field_simps)
  done

lemma range_cover_bound'':
  "\<lbrakk>range_cover ptr sz us n; x < of_nat n\<rbrakk>
  \<Longrightarrow> ptr + x * 2 ^ us + 2 ^ us - 1 \<le> (ptr && ~~ mask sz) + 2 ^ sz - 1"
  apply (frule range_cover_cell_subset)
   apply assumption
  apply (drule(1) range_cover_subset_not_empty)
   apply (clarsimp simp: field_simps)
  done

lemma caps_no_overlap''_le:
  "\<lbrakk>caps_no_overlap'' ptr sz s;us \<le> sz;sz < word_bits\<rbrakk>
    \<Longrightarrow> caps_no_overlap'' ptr us s"
  apply (clarsimp simp:caps_no_overlap''_def)
  apply (drule(1) bspec)
  apply (subgoal_tac  "{ptr..(ptr && ~~ mask us) + 2 ^ us - 1}
                      \<subseteq>  {ptr..(ptr && ~~ mask sz) + 2 ^ sz - 1}")
   apply (erule impE)
    apply (rule ccontr)
    apply clarify
    apply (drule(1) disjoint_subset2[rotated -1])
    apply simp
   apply (erule subsetD)+
   apply simp
  apply clarsimp
  apply (frule neg_mask_diff_bound[where ptr = ptr])
  apply (simp add:p_assoc_help)
   apply (rule word_plus_mcs[where x = "2 ^ us - 1 + (ptr && ~~ mask sz)"])
    apply (simp add:field_simps)
   apply (simp add:field_simps)
   apply (simp add:p_assoc_help)
   apply (rule word_plus_mono_right)
   apply (simp add: word_bits_def)
   apply (erule two_power_increasing)
   apply simp
  apply (rule is_aligned_no_overflow')
   apply (simp add:is_aligned_neg_mask)
  done

lemma caps_no_overlap''_le2:
  "\<lbrakk>caps_no_overlap'' ptr sz s;ptr \<le> ptr'; ptr' && ~~ mask sz = ptr && ~~ mask sz\<rbrakk>
    \<Longrightarrow> caps_no_overlap'' ptr' sz s"
  apply (clarsimp simp:caps_no_overlap''_def)
  apply (drule(1) bspec)
  apply (subgoal_tac  "{ptr'..(ptr' && ~~ mask sz) + 2 ^ sz - 1}
                      \<subseteq>  {ptr..(ptr && ~~ mask sz) + 2 ^ sz - 1}")
   apply (erule impE)
    apply (rule ccontr)
    apply clarify
    apply (drule(1) disjoint_subset2[rotated -1])
    apply simp
   apply (erule subsetD)+
   apply simp
  apply clarsimp
  done

lemma range_cover_head_mask:
  "\<lbrakk>range_cover (ptr :: word32) sz us (Suc n); ptr \<noteq> 0\<rbrakk>
  \<Longrightarrow> ptr + (of_nat n << us) && ~~ mask sz = ptr && ~~ mask sz"
  apply (case_tac n)
   apply clarsimp
  apply (clarsimp simp:range_cover_tail_mask)
  done

lemma pspace_no_overlap'_strg:
  "pspace_no_overlap' ptr sz s \<and> sz' \<le> sz \<and> sz < word_bits \<longrightarrow> pspace_no_overlap' ptr sz' s"
  apply clarsimp
  apply (erule(2) pspace_no_overlap'_le)
  done

lemma cte_wp_at_no_0:
  "\<lbrakk>invs' s; cte_wp_at' (\<lambda>_. True) ptr s\<rbrakk> \<Longrightarrow> ptr \<noteq> 0"
  by (clarsimp dest!:invs_mdb' simp:valid_mdb'_def valid_mdb_ctes_def no_0_def cte_wp_at_ctes_of)

lemma insertNewCap_descendants_range_in':
  "\<lbrace>\<lambda>s. valid_pspace' s \<and> descendants_range_in' S p (ctes_of s)
    \<and> capRange x \<inter> S = {}
    \<and> cte_wp_at' (\<lambda>cte. isUntypedCap (cteCap cte) \<and> sameRegionAs (cteCap cte) x) p s
    \<and> cte_wp_at' (\<lambda>cte. cteCap cte = capability.NullCap) dslot s
    \<and> descendants_range' x p (ctes_of s) \<and> capClass x = PhysicalClass
   \<rbrace> insertNewCap p dslot x
    \<lbrace>\<lambda>rv s. descendants_range_in' S p (ctes_of s)\<rbrace>"
  apply (clarsimp simp:insertNewCap_def descendants_range_in'_def)
  apply (wp getCTE_wp)
  apply (clarsimp simp:cte_wp_at_ctes_of)
  apply (intro conjI allI)
   apply (clarsimp simp:valid_pspace'_def valid_mdb'_def
     valid_mdb_ctes_def no_0_def split:if_splits)
  apply (clarsimp simp: descendants_of'_mdbPrev split:if_splits)
  apply (cut_tac p = p and m = "ctes_of s" and parent = p and s = s
        and parent_cap = "cteCap cte" and parent_node = "cteMDBNode cte"
        and site = dslot and site_cap = capability.NullCap and site_node = "cteMDBNode ctea"
        and c' = x
    in mdb_insert_again_child.descendants)
   apply (case_tac cte ,case_tac ctea)
   apply (rule mdb_insert_again_child.intro[OF mdb_insert_again.intro])
      apply (simp add:mdb_ptr_def vmdb_def valid_pspace'_def valid_mdb'_def
            mdb_ptr_axioms_def mdb_insert_again_axioms_def )+
    apply (intro conjI allI impI)
      apply clarsimp
      apply (erule(1) ctes_of_valid_cap')
     apply (clarsimp simp:valid_mdb_ctes_def)
    apply clarsimp
   apply (rule mdb_insert_again_child_axioms.intro)
   apply (clarsimp simp: nullPointer_def)+
   apply (clarsimp simp:isMDBParentOf_def valid_pspace'_def
      valid_mdb'_def valid_mdb_ctes_def)
   apply (frule(2) ut_revocableD'[rotated 1])
   apply (clarsimp simp:isCap_simps)
  apply (clarsimp cong: if_cong)
  done

lemma insertNewCap_cte_wp_at_other:
  "\<lbrace>cte_wp_at' (\<lambda>cte. P (cteCap cte)) p and K (slot \<noteq> p)\<rbrace> insertNewCap srcSlot slot x
            \<lbrace>\<lambda>rv. cte_wp_at' (\<lambda>cte. P (cteCap cte)) p \<rbrace>"
  apply (clarsimp simp:insertNewCap_def)
  apply (wp updateMDB_weak_cte_wp_at setCTE_cte_wp_at_other getCTE_wp)
  apply (clarsimp simp:cte_wp_at_ctes_of)
  done

lemma range_cover_bound3:
  "\<lbrakk>range_cover ptr sz us n; x < of_nat n\<rbrakk>
  \<Longrightarrow> ptr + x * 2 ^ us + 2 ^ us - 1 \<le> ptr + (of_nat n) * 2 ^ us - 1"
  apply (frule range_cover_subset[where p = "unat x"])
    apply (simp add:unat_less_helper)
   apply (rule ccontr,simp)
  apply (drule(1) range_cover_subset_not_empty)
   apply (clarsimp simp: field_simps)
  done

lemma range_cover_gsMaxObjectSize:
  "cte_wp_at' (\<lambda>cte. cteCap cte = UntypedCap dev (ptr &&~~ mask sz) sz idx) srcSlot s
    \<Longrightarrow> range_cover ptr sz (APIType_capBits newType userSize) (length destSlots)
    \<Longrightarrow> valid_global_refs' s
    \<Longrightarrow> unat num = length destSlots
    \<Longrightarrow> unat (num << (APIType_capBits newType userSize) :: word32) \<le> gsMaxObjectSize s
        \<and> 2 ^ APIType_capBits newType userSize \<le> gsMaxObjectSize s"
  apply (clarsimp simp: cte_wp_at_ctes_of)
  apply (drule (1) valid_global_refsD_with_objSize)
  apply clarsimp
  apply (rule conjI)
   apply (frule range_cover.range_cover_compare_bound)
   apply (drule range_cover.unat_of_nat_n_shift, rule order_refl)
   apply (drule_tac s="unat num" in sym)
   apply simp
  apply (clarsimp simp: range_cover_def)
  apply (erule order_trans[rotated])
  apply simp
  done

lemma APIType_capBits_min:
  "(tp = APIObjectType apiobject_type.Untyped \<longrightarrow> minUntypedSizeBits \<le> userSize)
    \<Longrightarrow> 4 \<le> APIType_capBits tp userSize"
  by (simp add: APIType_capBits_def objBits_simps' untypedBits_defs
         split: object_type.split ArchTypes_H.apiobject_type.split)

end

context begin interpretation Arch . (*FIXME: arch_split*)

crunch gsCNodes[wp]: insertNewCap, Arch_createNewCaps, threadSet,
        "Arch.createObject" "\<lambda>s. P (gsCNodes s)"
  (wp: crunch_wps setObject_ksPSpace_only
     simp: unless_def updateObject_default_def crunch_simps
   ignore: getObject setObject)

lemma createNewCaps_1_gsCNodes_p:
  "\<lbrace>\<lambda>s. P (gsCNodes s p) \<and> p \<noteq> ptr\<rbrace> createNewCaps newType ptr 1 n dev\<lbrace>\<lambda>rv s. P (gsCNodes s p)\<rbrace>"
  apply (simp add: createNewCaps_def)
  apply (rule hoare_pre)
   apply (wp mapM_x_wp' | wpc | simp add: createObjects_def)+
  done

lemma createObject_gsCNodes_p:
  "\<lbrace>\<lambda>s. P (gsCNodes s p) \<and> p \<noteq> ptr\<rbrace> createObject t ptr sz dev\<lbrace>\<lambda>rv s. P (gsCNodes s p)\<rbrace>"
  apply (simp add: createObject_def)
  apply (rule hoare_pre)
   apply (wp mapM_x_wp' | wpc | simp add: createObjects_def)+
  done

lemma createObject_cnodes_have_size:
  "\<lbrace>\<lambda>s. is_aligned ptr (APIType_capBits newType userSize)
      \<and> cnodes_retype_have_size R (APIType_capBits newType userSize) (gsCNodes s)\<rbrace>
    createObject newType ptr userSize dev
  \<lbrace>\<lambda>rv s. cnodes_retype_have_size R (APIType_capBits newType userSize) (gsCNodes s)\<rbrace>"
  apply (simp add: createObject_def)
  apply (rule hoare_pre)
   apply (wp mapM_x_wp' | wpc | simp add: createObjects_def)+
  apply (cases newType, simp_all add: ARM_H.toAPIType_def)
  apply (clarsimp simp: APIType_capBits_def objBits_simps'
                              cnodes_retype_have_size_def cte_level_bits_def
                       split: if_split_asm)
  done

lemma range_cover_not_in_neqD:
  "\<lbrakk> x \<notin> {ptr..ptr + (of_nat n << APIType_capBits newType userSize) - 1};
    range_cover ptr sz (APIType_capBits newType userSize) n; n' < n \<rbrakk>
  \<Longrightarrow> x \<noteq> ptr + (of_nat n' << APIType_capBits newType userSize)"
  apply (clarsimp simp only: shiftl_t2n mult.commute)
  apply (erule notE, rule subsetD, erule_tac p=n' in range_cover_subset)
    apply simp+
  apply (rule is_aligned_no_overflow)
  apply (rule aligned_add_aligned)
    apply (erule range_cover.aligned)
   apply (simp add: is_aligned_mult_triv2)
  apply simp
  done

crunch gsMaxObjectSize[wp]: createObject "\<lambda>s. P (gsMaxObjectSize s)"
  (simp: crunch_simps unless_def wp: crunch_wps)

end

context kernel_m begin

lemma insertNewCap_preserves_bytes:
  "\<forall>s. \<Gamma>\<turnstile>\<^bsub>/UNIV\<^esub> {s} Call insertNewCap_'proc
      {t. hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))
         \<and> byte_regions_unmodified' s t}"
  apply (hoare_rule HoarePartial.ProcNoRec1)
  apply (rule allI, rule conseqPre, vcg exspec=mdb_node_ptr_set_mdbPrev_preserves_bytes
    exspec=mdb_node_ptr_set_mdbNext_preserves_bytes
    exspec=mdb_node_get_mdbNext_modifies exspec=mdb_node_new_modifies)
  apply (safe intro!: byte_regions_unmodified_hrs_mem_update
    elim!: byte_regions_unmodified_trans byte_regions_unmodified_trans[rotated],
    simp_all add: h_t_valid_field)
  done

lemma byte_regions_unmodified_flip_eq:
  "byte_regions_unmodified hrs' hrs
    \<Longrightarrow> hrs_htd hrs' = hrs_htd hrs
    \<Longrightarrow> byte_regions_unmodified hrs hrs'"
  by (simp add: byte_regions_unmodified_def)

lemma insertNewCap_preserves_bytes_flip:
  "\<forall>s. \<Gamma>\<turnstile>\<^bsub>/UNIV\<^esub> {s} Call insertNewCap_'proc
      {t. hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))
         \<and> byte_regions_unmodified' t s}"
  by (rule allI, rule conseqPost,
    rule insertNewCap_preserves_bytes[rule_format],
    auto elim: byte_regions_unmodified_flip_eq)

lemma copyGlobalMappings_preserves_bytes:
  "\<forall>s. \<Gamma>\<turnstile>\<^bsub>/UNIV\<^esub> {s} Call copyGlobalMappings_'proc
      {t. hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))
         \<and> byte_regions_unmodified' s t}"
  apply (hoare_rule HoarePartial.ProcNoRec1)
  apply (clarsimp simp only: whileAnno_def)
  apply (subst whileAnno_def[symmetric, where V=undefined
       and I="{t. hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))
         \<and> byte_regions_unmodified' s t}" for s])
  apply (rule conseqPre, vcg)
  apply (safe intro!: byte_regions_unmodified_hrs_mem_update
    elim!: byte_regions_unmodified_trans byte_regions_unmodified_trans[rotated],
    (simp_all add: h_t_valid_field)+)
  done

lemma cleanByVA_PoU_preserves_bytes:
  "\<forall>s. \<Gamma>\<turnstile>\<^bsub>/UNIV\<^esub> {s} Call cleanByVA_PoU_'proc
      {t. hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))
         \<and> byte_regions_unmodified' s t}"
  apply (rule allI, rule conseqPost,
    rule cleanByVA_PoU_preserves_kernel_bytes[rule_format])
   apply simp_all
  apply (clarsimp simp: byte_regions_unmodified_def)
  done

lemma cleanCacheRange_PoU_preserves_bytes:
  "\<forall>s. \<Gamma>\<turnstile>\<^bsub>/UNIV\<^esub> {s} Call cleanCacheRange_PoU_'proc
      {t. hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))
         \<and> byte_regions_unmodified' s t}"
  apply (hoare_rule HoarePartial.ProcNoRec1)
  apply (clarsimp simp only: whileAnno_def)
  apply (subst whileAnno_def[symmetric, where V=undefined
       and I="{t. hrs_htd (t_hrs_' (globals t)) = hrs_htd (t_hrs_' (globals s))
         \<and> byte_regions_unmodified' s t}" for s])
  apply (rule conseqPre, vcg exspec=cleanByVA_PoU_preserves_bytes)
  apply (safe intro!: byte_regions_unmodified_hrs_mem_update
    elim!: byte_regions_unmodified_trans byte_regions_unmodified_trans[rotated],
    (simp_all add: h_t_valid_field)+)
  done

lemma hrs_htd_update_canon:
  "hrs_htd_update (\<lambda>_. f (hrs_htd hrs)) hrs = hrs_htd_update f hrs"
  by (cases hrs, simp add: hrs_htd_update_def hrs_htd_def)

lemma Arch_createObject_preserves_bytes:
  "\<forall>s. \<Gamma>\<turnstile>\<^bsub>/UNIV\<^esub> {s} Call Arch_createObject_'proc
      {t. \<forall>nt. t_' s = object_type_from_H nt
         \<longrightarrow> (\<forall>x \<in> - {ptr_val (regionBase_' s) ..+ 2 ^ getObjectSize nt (unat (userSize_' s))}.
             hrs_htd (t_hrs_' (globals t)) x = hrs_htd (t_hrs_' (globals s)) x)
         \<and> byte_regions_unmodified' t s}"
  apply (hoare_rule HoarePartial.ProcNoRec1)
  apply clarsimp
  apply (rule conseqPre, vcg exspec=cap_small_frame_cap_new_modifies
    exspec=cap_frame_cap_new_modifies
    exspec=cap_page_table_cap_new_modifies
    exspec=copyGlobalMappings_preserves_bytes
    exspec=addrFromPPtr_modifies
    exspec=cleanCacheRange_PoU_preserves_bytes
    exspec=cap_page_directory_cap_new_modifies)
  apply (safe intro!: byte_regions_unmodified_hrs_mem_update,
    (simp_all add: h_t_valid_field hrs_htd_update)+)
  apply (safe intro!: ptr_retyp_d ptr_retyps_out)
  apply (simp_all add: object_type_from_H_def Kernel_C_defs APIType_capBits_def
    split: object_type.split_asm ArchTypes_H.apiobject_type.split_asm)
   apply (rule byte_regions_unmodified_flip, simp)
  apply (rule byte_regions_unmodified_trans[rotated],
    assumption, simp_all add: hrs_htd_update_canon hrs_htd_update)
  done

lemma ptr_arr_retyps_eq_outside_dom:
  "x \<notin> {ptr_val (p :: 'a ptr) ..+ n * size_of TYPE ('a :: wf_type)}
    \<Longrightarrow> ptr_arr_retyps n p htd x = htd x"
  by (simp add: ptr_arr_retyps_def htd_update_list_same2)

lemma createObject_preserves_bytes:
  "\<forall>s. \<Gamma>\<turnstile>\<^bsub>/UNIV\<^esub> {s} Call createObject_'proc
      {t. \<forall>nt. t_' s = object_type_from_H nt
         \<longrightarrow> (\<forall>x \<in> - {ptr_val (regionBase_' s) ..+ 2 ^ getObjectSize nt (unat (userSize_' s))}.
             hrs_htd (t_hrs_' (globals t)) x = hrs_htd (t_hrs_' (globals s)) x)
         \<and> byte_regions_unmodified' t s}"
  apply (hoare_rule HoarePartial.ProcNoRec1)
  apply clarsimp
  apply (rule conseqPre, vcg exspec=Arch_createObject_preserves_bytes
    exspec=cap_thread_cap_new_modifies
    exspec=cap_endpoint_cap_new_modifies
    exspec=cap_notification_cap_new_modifies
    exspec=cap_cnode_cap_new_modifies
    exspec=cap_untyped_cap_new_modifies)
  apply (safe intro!: byte_regions_unmodified_hrs_mem_update,
    (simp_all add: h_t_valid_field hrs_htd_update)+)
  apply (safe intro!: ptr_retyp_d ptr_retyps_out trans[OF ptr_retyp_d ptr_retyp_d]
                      ptr_arr_retyps_eq_outside_dom)
  apply (simp_all add: object_type_from_H_def Kernel_C_defs APIType_capBits_def
                       objBits_simps' cte_C_size power_add ctcb_offset_defs
    split: object_type.split_asm ArchTypes_H.apiobject_type.split_asm)
   apply (erule notE, erule subsetD[rotated],
     rule intvl_start_le intvl_sub_offset, simp)+
  done

lemma offset_intvl_first_chunk_subsets:
  "range_cover (p :: addr) sz bits n
    \<Longrightarrow> i < of_nat n
    \<Longrightarrow> {p + (i << bits) ..+ 2 ^ bits} \<subseteq> {p + (i << bits) ..+ (n - unat i) * 2 ^ bits}
        \<and> {p + ((i + 1) << bits) ..+ (n - unat (i + 1)) * 2 ^ bits}
            \<le> {p + (i << bits) ..+ (n - unat i) * 2 ^ bits}
        \<and> {p + (i << bits) ..+ 2 ^ bits}
            \<inter> {p + ((i + 1) << bits) ..+ (n - unat (i + 1)) * 2 ^ bits}
            = {}"
  apply (strengthen intvl_start_le)
  apply (strengthen order_trans[OF _
      intvl_sub_offset[where x="2 ^ bits" and y="(n - unat (i + 1)) * 2 ^ bits"]])
  apply (frule range_cover_sz')
  apply (cut_tac n=i in unatSuc)
   apply unat_arith
  apply (simp add: word_shiftl_add_distrib field_simps TWO)
  apply (simp add: mult_Suc[symmetric] del: mult_Suc)
  apply (frule unat_less_helper)
  apply (cut_tac p="p + (i << bits)" and k="2 ^ bits"
    and z="(n - unat (i + 1)) * 2 ^ bits" in init_intvl_disj)
   apply (simp add: field_simps)
   apply (drule range_cover.strong_times_32, simp)
   apply (simp add: addr_card_def word_bits_def card_word)
   apply (erule order_le_less_trans[rotated])
   apply (simp add: mult_Suc[symmetric] del: mult_Suc)
  apply (simp add: Int_commute field_simps)
  apply unat_arith
  done

lemma offset_intvl_first_chunk_subsets_unat:
  "range_cover (p :: addr) sz bits n
    \<Longrightarrow> unat n' = n
    \<Longrightarrow> i < of_nat n
    \<Longrightarrow> {p + (i << bits) ..+ 2 ^ bits} \<subseteq> {p + (i << bits) ..+ unat (n' - i) * 2 ^ bits}
        \<and> {p + ((i + 1) << bits) ..+ unat (n' - (i + 1)) * 2 ^ bits}
            \<le> {p + (i << bits) ..+ unat (n' - i) * 2 ^ bits}
        \<and> {p + (i << bits) ..+ 2 ^ bits}
            \<inter> {p + ((i + 1) << bits) ..+ unat (n' - (i + 1)) * 2 ^ bits}
            = {}"
  apply (subgoal_tac "unat (n' - (i + 1)) = unat n' - unat (i + 1)
        \<and> unat (n' - i) = unat n' - unat i")
   apply (frule(1) offset_intvl_first_chunk_subsets)
   apply simp
  apply (intro conjI unat_sub)
   apply (rule minus_one_helper2, simp)
   apply (simp add: word_less_nat_alt unat_of_nat)
  apply (simp add: word_le_nat_alt word_less_nat_alt unat_of_nat)
  done

lemma retype_offs_region_actually_is_zero_bytes:
  "\<lbrakk> ctes_of s p = Some cte; (s, s') \<in> rf_sr; untyped_ranges_zero' s;
      cteCap cte = UntypedCap False (ptr &&~~ mask sz) sz idx;
      idx \<le> unat (ptr && mask sz);
      range_cover ptr sz (getObjectSize newType userSize) num_ret \<rbrakk>
    \<Longrightarrow> region_actually_is_zero_bytes ptr
            (num_ret * 2 ^ APIType_capBits newType userSize) s'"
  using word_unat_mask_lt[where w=ptr and m=sz]
  apply -
  apply (frule range_cover.sz(1))
  apply (drule(2) ctes_of_untyped_zero_rf_sr)
   apply (simp add: untypedZeroRange_def max_free_index_def word_size)
  apply clarify
  apply (strengthen heap_list_is_zero_mono2[mk_strg I E]
      region_actually_is_bytes_subset[mk_strg I E])
  apply (simp add: getFreeRef_def word_size)
  apply (rule intvl_both_le)
   apply (rule order_trans, rule word_plus_mono_right, erule word_of_nat_le)
    apply (simp add: word_plus_and_or_coroll2 add.commute word_and_le2)
   apply (simp add: word_plus_and_or_coroll2 add.commute)
  apply (subst unat_plus_simple[THEN iffD1], rule is_aligned_no_wrap',
    rule is_aligned_neg_mask2)
   apply (rule word_of_nat_less, simp)
  apply (simp add: unat_of_nat_eq[OF order_less_trans, OF _ power_strict_increasing[where n=sz]]
    unat_sub[OF word_of_nat_le])
  apply (subst word_plus_and_or_coroll2[where x=ptr and w="mask sz", symmetric])
  apply (subst unat_plus_simple[THEN iffD1],
    simp add: word_plus_and_or_coroll2 add.commute word_and_le2)
  apply simp
  apply (rule order_trans[rotated], erule range_cover.range_cover_compare_bound)
  apply simp
  done

lemma createNewCaps_valid_cap_hd:
    "\<lbrace>\<lambda>s. pspace_no_overlap' ptr sz s \<and>
        valid_pspace' s \<and> n \<noteq> 0 \<and>
        range_cover ptr sz (APIType_capBits ty us) n \<and>
        (ty = APIObjectType ArchTypes_H.CapTableObject \<longrightarrow> 0 < us) \<and>
        (ty = APIObjectType ArchTypes_H.apiobject_type.Untyped \<longrightarrow> minUntypedSizeBits \<le> us \<and> us \<le> maxUntypedSizeBits) \<and>
       ptr \<noteq> 0 \<rbrace>
    createNewCaps ty ptr n us dev
  \<lbrace>\<lambda>r s. s \<turnstile>' hd r\<rbrace>"
  apply (cases "n = 0")
   apply simp
  apply (rule hoare_chain)
    apply (rule hoare_vcg_conj_lift)
     apply (rule createNewCaps_ret_len)
    apply (rule createNewCaps_valid_cap'[where sz=sz])
   apply (clarsimp simp: range_cover_n_wb)
  apply simp
  done

lemma insertNewCap_ccorres:
  "ccorres dc xfdc (pspace_aligned' and valid_mdb' and cte_wp_at' (\<lambda>_. True) slot
          and valid_objs' and valid_cap' cap)
     ({s. cap_get_tag (cap_' s) = scast cap_untyped_cap
         \<longrightarrow> (case untypedZeroRange (cap_to_H (the (cap_lift (cap_' s)))) of None \<Rightarrow> True
          | Some (a, b) \<Rightarrow> region_actually_is_zero_bytes a (unat ((b + 1) - a)) s)}
       \<inter> {s. ccap_relation cap (cap_' s)} \<inter> {s. parent_' s = Ptr parent}
       \<inter> {s. slot_' s = Ptr slot}) []
     (insertNewCap parent slot cap)
     (Call insertNewCap_'proc)"
  (is "ccorres _ _ ?P ?P' _ _ _")
  apply (rule ccorres_guard_imp2, rule insertNewCap_ccorres1)
  apply (clarsimp simp: cap_get_tag_isCap)
  apply (clarsimp simp: ccap_relation_def map_option_Some_eq2)
  apply (simp add: untypedZeroRange_def Let_def)
  done

lemma createObject_untyped_region_is_zero_bytes:
  "\<forall>\<sigma>. \<Gamma>\<turnstile>\<^bsub>/UNIV\<^esub> {s. let tp = (object_type_to_H (t_' s));
          sz = APIType_capBits tp (unat (userSize_' s))
      in (\<not> to_bool (deviceMemory_' s)
              \<longrightarrow> region_actually_is_zero_bytes (ptr_val (regionBase_' s)) (2 ^ sz) s)
          \<and> is_aligned (ptr_val (regionBase_' s)) sz
          \<and> sz < 32 \<and> (tp = APIObjectType ArchTypes_H.apiobject_type.Untyped \<longrightarrow> sz \<ge> minUntypedSizeBits)}
      Call createObject_'proc
   {t. cap_get_tag (ret__struct_cap_C_' t) = scast cap_untyped_cap
         \<longrightarrow> (case untypedZeroRange (cap_to_H (the (cap_lift (ret__struct_cap_C_' t)))) of None \<Rightarrow> True
          | Some (a, b) \<Rightarrow> region_actually_is_zero_bytes a (unat ((b + 1) - a)) t)}"
  apply (rule allI, rule conseqPre, vcg exspec=copyGlobalMappings_modifies
      exspec=Arch_initContext_modifies
      exspec=cleanCacheRange_PoU_modifies)
  apply (clarsimp simp: cap_tag_defs)
  apply (simp add: cap_lift_untyped_cap cap_tag_defs cap_to_H_simps
                   cap_untyped_cap_lift_def object_type_from_H_def)
  apply (simp add: untypedZeroRange_def split: if_split)
  apply (clarsimp simp: getFreeRef_def Let_def object_type_to_H_def untypedBits_defs)
  apply (simp add:  APIType_capBits_def
                   less_mask_eq word_less_nat_alt)
  done

lemma createNewObjects_ccorres:
notes blah[simp del] =  atLeastAtMost_iff atLeastatMost_subset_iff atLeastLessThan_iff
      Int_atLeastAtMost atLeastatMost_empty_iff split_paired_Ex
and   hoare_TrueI[simp add]
defines "unat_eq a b \<equiv> unat a = b"
shows  "ccorres dc xfdc
     (invs' and sch_act_simple and ct_active'
                  and (cte_wp_at' (\<lambda>cte. cteCap cte = UntypedCap isdev (ptr &&~~ mask sz) sz idx ) srcSlot)
                  and (\<lambda>s. \<forall>slot\<in>set destSlots. cte_wp_at' (\<lambda>c. cteCap c = NullCap) slot s)
                  and (\<lambda>s. \<forall>slot\<in>set destSlots. ex_cte_cap_wp_to' (\<lambda>_. True) slot s)
                  and (\<lambda>s. \<exists>n. gsCNodes s cnodeptr = Some n \<and> unat start + length destSlots \<le> 2 ^ n)
                  and (pspace_no_overlap' ptr sz)
                  and caps_no_overlap'' ptr sz
                  and caps_overlap_reserved' {ptr .. ptr + of_nat (length destSlots) * 2^ (getObjectSize newType userSize) - 1}
                  and (\<lambda>s. descendants_range_in' {ptr..(ptr && ~~ mask sz) + 2 ^ sz - 1} srcSlot (ctes_of s))
                  and cnodes_retype_have_size {ptr .. ptr + of_nat (length destSlots) * 2^ (getObjectSize newType userSize) - 1}
                      (APIType_capBits newType userSize) o gsCNodes
                  and (K (srcSlot \<notin> set destSlots
                    \<and> destSlots \<noteq> []
                    \<and> range_cover ptr sz (getObjectSize newType userSize) (length destSlots )
                    \<and> ptr \<noteq> 0
                    \<and> {ptr .. ptr + of_nat (length destSlots) * 2^ (getObjectSize newType userSize) - 1}
                      \<inter> kernel_data_refs = {}
                    \<and> cnodeptr \<notin> {ptr .. ptr + (of_nat (length destSlots)<< APIType_capBits newType userSize) - 1}
                    \<and> 0 \<notin> {ptr..(ptr && ~~ mask sz) + 2 ^ sz - 1}
                    \<and> is_aligned ptr 4
                    \<and> (newType = APIObjectType apiobject_type.Untyped \<longrightarrow> userSize \<le> maxUntypedSizeBits)
                    \<and> (newType = APIObjectType apiobject_type.CapTableObject \<longrightarrow> userSize < 28)
                    \<and> (newType = APIObjectType apiobject_type.Untyped \<longrightarrow> minUntypedSizeBits \<le> userSize)
                    \<and> (newType = APIObjectType apiobject_type.CapTableObject \<longrightarrow> 0 < userSize)
                    \<and> (isdev \<longrightarrow> newType = APIObjectType ArchTypes_H.apiobject_type.Untyped \<or>
                                           isFrameType newType)
                    \<and> (unat num = length destSlots)
                    )))
    ({s. (\<not> isdev \<longrightarrow> region_actually_is_zero_bytes ptr
            (length destSlots * 2 ^ APIType_capBits newType userSize) s)}
           \<inter> {s. t_' s = object_type_from_H newType}
           \<inter> {s. parent_' s = cte_Ptr srcSlot}
           \<inter> {s. slots_' s = slot_range_C (cte_Ptr cnodeptr) start num
                     \<and> unat num \<noteq> 0
                     \<and> (\<forall>n. n < length destSlots \<longrightarrow> destSlots ! n = cnodeptr + ((start + of_nat n) * 0x10))
                     }
           \<inter> {s. regionBase_' s = Ptr ptr }
           \<inter> {s. unat_eq (userSize_' s) userSize}
           \<inter> {s. to_bool (deviceMemory_' s) = isdev}
     ) []
     (createNewObjects newType srcSlot destSlots ptr userSize isdev)
     (Call createNewObjects_'proc)"
  apply (rule ccorres_gen_asm_state)
  apply clarsimp
  apply (subgoal_tac "unat (of_nat (getObjectSize newType userSize)) = getObjectSize newType userSize")
   prefer 2
   apply (subst unat_of_nat32)
    apply (rule less_le_trans [OF getObjectSize_max_size], auto simp: word_bits_def untypedBits_defs)[1]
   apply simp
  apply (cinit lift: t_' parent_' slots_' regionBase_' userSize_' deviceMemory_')
   apply (rule ccorres_rhs_assoc2)+
   apply (rule ccorres_rhs_assoc)
   apply (rule_tac Q' = "Q'
     \<inter> {s. objectSize_' s = of_nat (APIType_capBits newType userSize)}
     \<inter> {s. nextFreeArea_' s = Ptr ptr } "
     and R="(\<lambda>s. unat (num << (APIType_capBits newType userSize) :: word32)
        \<le> gsMaxObjectSize s) and R''"
     for Q' R'' in ccorres_symb_exec_r)
     apply (rule ccorres_guard_imp[where A="X and Q"
         and A'=Q' and Q=Q and Q'=Q' for X Q Q', rotated]
         (* this moves the gsMaxObjectSize bit into the ccorres_symb_exec_r
            vcg proof *))
       apply clarsimp
      apply clarsimp
     apply (cinitlift objectSize_' nextFreeArea_')
     apply simp
     apply (clarsimp simp: whileAnno_def)
     apply (rule ccorres_rel_imp)
      apply (rule_tac Q="{s. \<not> isdev \<longrightarrow> region_actually_is_zero_bytes
            (ptr + (i_' s << APIType_capBits newType userSize))
            (unat (num - i_' s) * 2 ^ APIType_capBits newType userSize) s}"
            in ccorres_zipWithM_x_while_genQ[where j=1, OF _ _ _ _ _ i_xf_for_sequence, simplified])
          apply clarsimp
          apply (subst upt_enum_offset_trivial)
            apply (rule minus_one_helper)
             apply (rule word_of_nat_le)
             apply (drule range_cover.range_cover_n_less)
             apply (simp add:word_bits_def minus_one_norm)
            apply (erule range_cover_not_zero[rotated],simp)
           apply simp
          apply (rule ccorres_guard_impR)
           apply (rule_tac xf'=i_' in ccorres_abstract, ceqv)
           apply (rule_tac P="rv' = of_nat n" in ccorres_gen_asm2, simp)
           apply (rule ccorres_rhs_assoc)+
           apply (rule ccorres_add_return)
           apply (simp only: dc_def[symmetric] hrs_htd_update)
           apply ((rule ccorres_Guard_Seq[where S=UNIV])+)?
           apply (rule ccorres_split_nothrow,
                rule_tac S="{ptr .. ptr + of_nat (length destSlots) * 2^ (getObjectSize newType userSize) - 1}"
                  in ccorres_typ_region_bytes_dummy, ceqv)
             apply (rule ccorres_Guard_Seq)+
             apply (ctac add:createObject_ccorres)
               apply (rule ccorres_move_array_assertion_cnode_ctes
                           ccorres_move_c_guard_cte)+
               apply (rule ccorres_add_return2)
               apply (ctac (no_vcg) add: insertNewCap_ccorres)
                apply (rule ccorres_move_array_assertion_cnode_ctes
                            ccorres_return_Skip')+
               apply wp
              apply (clarsimp simp:createObject_def3 conj_ac)
              apply (wp createNewCaps_valid_pspace_extras[where sz = sz]
                createNewCaps_cte_wp_at[where sz = sz]
                createNewCaps_valid_cap_hd[where sz = sz])
                apply (rule range_cover_one)
                  apply (rule aligned_add_aligned[OF is_aligned_shiftl_self])
                   apply (simp add:range_cover.aligned)
                  apply (simp add:range_cover_def)
                 apply (simp add:range_cover_def)
                apply (simp add:range_cover_def)
               apply (simp add:range_cover.sz)
              apply (wp createNewCaps_1_gsCNodes_p[simplified]
                        createNewCaps_cte_wp_at'[where sz=sz])[1]
             apply clarsimp
             apply (vcg exspec=createObject_untyped_region_is_zero_bytes)
            apply (simp add:size_of_def)
            apply (rule_tac P = "\<lambda>s. cte_wp_at' (\<lambda>cte. isUntypedCap (cteCap cte) \<and>
              {ptr .. ptr + (of_nat (length destSlots)<< APIType_capBits newType userSize) - 1} \<subseteq> untypedRange (cteCap cte)) srcSlot s
              \<and> pspace_no_overlap'  ((of_nat n << APIType_capBits newType userSize) + ptr) sz s
              \<and> caps_no_overlap'' ((of_nat n << APIType_capBits newType userSize) + ptr) sz s
              \<and> caps_overlap_reserved'  {(of_nat n << APIType_capBits newType userSize) +
                 ptr.. ptr + of_nat (length destSlots) * 2^ (getObjectSize newType userSize) - 1 } s
              \<and> kernel_data_refs \<inter> {ptr .. ptr + (of_nat (length destSlots) << APIType_capBits newType userSize) - 1} = {}
              \<and> (\<forall>n < length destSlots. cte_at' (cnodeptr + (start * 0x10 + of_nat n * 0x10)) s
                    \<and> ex_cte_cap_wp_to' (\<lambda>_. True) (cnodeptr + (start * 0x10 + of_nat n * 0x10)) s)
              \<and> invs' s
              \<and> 2 ^ APIType_capBits newType userSize \<le> gsMaxObjectSize s
              \<and> (\<exists>cn. gsCNodes s cnodeptr = Some cn \<and> unat start + length destSlots \<le> 2 ^ cn)
              \<and> cnodeptr \<notin> {ptr .. ptr + (of_nat (length destSlots)<< APIType_capBits newType userSize) - 1}
              \<and> (\<forall>k < length destSlots - n.
                 cte_wp_at' (\<lambda>c. cteCap c = NullCap)
                 (cnodeptr + (of_nat k * 0x10 + start * 0x10 + of_nat n * 0x10)) s)
              \<and> descendants_range_in' {(of_nat n << APIType_capBits newType userSize) +
                 ptr.. (ptr && ~~ mask sz) + 2 ^ sz  - 1} srcSlot (ctes_of s)"
              in hoare_pre(1))
             apply wp
            apply (clarsimp simp:createObject_hs_preconds_def field_simps conj_comms
                   invs_valid_pspace' invs_pspace_distinct' invs_pspace_aligned'
                   invs_ksCurDomain_maxDomain')
            apply (subst intvl_range_conv)
              apply (rule aligned_add_aligned[OF range_cover.aligned],assumption)
               subgoal by (simp add:is_aligned_shiftl_self)
              apply (fold_subgoals (prefix))[2]
              subgoal premises prems using prems
                        by (simp_all add:range_cover_sz'[where 'a=32, folded word_bits_def]
                                   word_bits_def range_cover_def)+
            apply (simp add: range_cover_not_in_neqD)
            apply (intro conjI)
                  apply (drule_tac p = n in range_cover_no_0)
                    apply (simp add:shiftl_t2n field_simps)+
                 apply (cut_tac x=num in unat_lt2p, simp)
                 apply (simp add: unat_arith_simps unat_of_nat, simp split: if_split)
                 apply (intro impI, erule order_trans[rotated], simp)
                apply (erule pspace_no_overlap'_le)
                 apply (fold_subgoals (prefix))[2]
                 subgoal premises prems using prems
                           by (simp add:range_cover.sz[where 'a=32, folded word_bits_def])+
               apply (rule range_cover_one)
                 apply (rule aligned_add_aligned[OF range_cover.aligned],assumption)
                  apply (simp add:is_aligned_shiftl_self)
                 apply (fold_subgoals (prefix))[2]
                 subgoal premises prems using prems
                           by (simp add: range_cover_sz'[where 'a=32, folded word_bits_def]
                                         range_cover.sz[where 'a=32, folded word_bits_def])+
               apply (simp add:  word_bits_def range_cover_def)
              apply (rule range_cover_full)
               apply (rule aligned_add_aligned[OF range_cover.aligned],assumption)
                apply (simp add:is_aligned_shiftl_self)
               apply (fold_subgoals (prefix))[2]
               subgoal premises prems using prems
                         by (simp add: range_cover_sz'[where 'a=32, folded word_bits_def]
                                       range_cover.sz[where 'a=32, folded word_bits_def])+
              apply (erule caps_overlap_reserved'_subseteq)
              apply (frule_tac x = "of_nat n" in range_cover_bound3)
               apply (rule word_of_nat_less)
               apply (simp add:range_cover.unat_of_nat_n)
              apply (clarsimp simp:field_simps shiftl_t2n blah)
             apply (erule disjoint_subset[rotated])
             apply (rule_tac p1 = n in subset_trans[OF _ range_cover_subset])
                apply (simp add: upto_intvl_eq is_aligned_add range_cover.aligned is_aligned_shiftl)
                apply (simp add:field_simps shiftl_t2n)
               apply simp+
            apply (erule caps_overlap_reserved'_subseteq)
            apply (frule_tac x = "of_nat n" in range_cover_bound3)
             apply (rule word_of_nat_less)
             apply (simp add:range_cover.unat_of_nat_n)
            apply (clarsimp simp: field_simps shiftl_t2n blah)
           apply (clarsimp simp:createObject_c_preconds_def field_simps)
           apply vcg
          apply (clarsimp simp: cte_C_size conj_comms untypedBits_defs)
          apply (simp cong: conj_cong)
          apply (intro conjI impI)
              apply (simp add: unat_eq_def)
             apply (drule range_cover_sz')
             apply (simp add: unat_eq_def word_less_nat_alt)
            apply (simp add: hrs_htd_update typ_region_bytes_actually_is_bytes)
           apply clarsimp
           apply (erule heap_list_is_zero_mono)
           apply (subgoal_tac "unat (num - of_nat n) \<noteq> 0")
            apply simp
           apply (simp only: unat_eq_0, clarsimp simp: unat_of_nat)
          apply (frule range_cover_sz')
          apply (clarsimp simp: Let_def hrs_htd_update
                                APIType_capBits_def[where ty="APIObjectType ArchTypes_H.apiobject_type.Untyped"])
          apply (subst is_aligned_add, erule range_cover.aligned)
           apply (simp add: is_aligned_shiftl)+
         apply (subst range_cover.unat_of_nat_n)
          apply (erule range_cover_le)
          subgoal by simp
         subgoal by (simp add:word_unat.Rep_inverse')
        apply clarsimp
        apply (rule conseqPre, vcg exspec=insertNewCap_preserves_bytes_flip
            exspec=createObject_preserves_bytes)
        apply (clarsimp simp del: imp_disjL)
        apply (frule(1) offset_intvl_first_chunk_subsets_unat,
          erule order_less_le_trans)
         apply (drule range_cover.weak)
         apply (simp add: word_le_nat_alt unat_of_nat)

        apply (drule spec, drule mp, rule refl[where t="object_type_from_H newType"])
        apply clarsimp
        apply (rule context_conjI)
         apply (simp add: hrs_htd_update)
         apply (simp add: region_actually_is_bytes'_def, rule ballI)
         apply (drule bspec, erule(1) subsetD)
         apply (drule(1) orthD2)
         apply (simp add: Ball_def unat_eq_def typ_bytes_region_out)
        apply (erule trans[OF heap_list_h_eq2 heap_list_is_zero_mono2, rotated])
         apply (simp add: word_shiftl_add_distrib field_simps)
        apply (rule sym, rule byte_regions_unmodified_region_is_bytes)
          apply (erule byte_regions_unmodified_trans, simp_all)[1]
          apply (simp add: byte_regions_unmodified_def)
         apply simp
        apply assumption

       apply (clarsimp simp:conj_comms field_simps
                       createObject_hs_preconds_def range_cover_sz')
       apply (subgoal_tac "is_aligned (ptr + (1 + of_nat n << APIType_capBits newType userSize))
         (APIType_capBits newType userSize)")
        prefer 2
        apply (rule aligned_add_aligned[OF range_cover.aligned],assumption)
         apply (rule is_aligned_shiftl_self)
        apply (simp)
       apply (simp add: range_cover_one[OF _  range_cover.sz(2) range_cover.sz(1)])
       including no_pre
       apply (wp insertNewCap_invs' insertNewCap_valid_pspace' insertNewCap_caps_overlap_reserved'
                 insertNewCap_pspace_no_overlap' insertNewCap_caps_no_overlap'' insertNewCap_descendants_range_in'
                 insertNewCap_untypedRange hoare_vcg_all_lift insertNewCap_cte_at static_imp_wp)
         apply (wp insertNewCap_cte_wp_at_other)
        apply (wp hoare_vcg_all_lift static_imp_wp insertNewCap_cte_at)
       apply (clarsimp simp:conj_comms |
         strengthen invs_valid_pspace' invs_pspace_aligned'
         invs_pspace_distinct')+
       apply (frule range_cover.range_cover_n_less)
       apply (subst upt_enum_offset_trivial)
         apply (rule minus_one_helper[OF word_of_nat_le])
          apply (fold_subgoals (prefix))[3]
          subgoal premises prems using prems
                    by (simp add:word_bits_conv minus_one_norm range_cover_not_zero[rotated])+
       apply (simp add: intvl_range_conv aligned_add_aligned[OF range_cover.aligned]
              is_aligned_shiftl_self range_cover_sz')
       apply (subst intvl_range_conv)
         apply (erule aligned_add_aligned[OF range_cover.aligned])
          apply (rule is_aligned_shiftl_self, rule le_refl)
        apply (erule range_cover_sz')
       apply (subst intvl_range_conv)
         apply (erule aligned_add_aligned[OF range_cover.aligned])
          apply (rule is_aligned_shiftl_self, rule le_refl)
        apply (erule range_cover_sz')
       apply (rule hoare_pre)
        apply (strengthen pspace_no_overlap'_strg[where sz = sz])
        apply (clarsimp simp:range_cover.sz conj_comms)
        apply (wp createObject_invs'
                  createObject_caps_overlap_reserved_ret' createObject_valid_cap'
                  createObject_descendants_range' createObject_idlethread_range
                  hoare_vcg_all_lift createObject_IRQHandler createObject_parent_helper
                  createObject_caps_overlap_reserved' createObject_caps_no_overlap''
                  createObject_pspace_no_overlap' createObject_cte_wp_at'
                  createObject_ex_cte_cap_wp_to createObject_descendants_range_in'
                  createObject_caps_overlap_reserved'
                  hoare_vcg_prop createObject_gsCNodes_p createObject_cnodes_have_size)
        apply (rule hoare_vcg_conj_lift[OF createObject_capRange_helper])
         apply (wp createObject_cte_wp_at' createObject_ex_cte_cap_wp_to
                   createObject_no_inter[where sz = sz] hoare_vcg_all_lift static_imp_wp)+
       apply (clarsimp simp:invs_pspace_aligned' invs_pspace_distinct' invs_valid_pspace'
         field_simps range_cover.sz conj_comms range_cover.aligned range_cover_sz'
         is_aligned_shiftl_self aligned_add_aligned[OF range_cover.aligned])
       apply (drule_tac x = n and  P = "\<lambda>x. x< length destSlots \<longrightarrow> Q x" for Q in spec)+
       apply clarsimp
       apply (simp add: range_cover_not_in_neqD)
       apply (intro conjI)
                          subgoal by (simp add: word_bits_def range_cover_def)
                         subgoal by (clarsimp simp: cte_wp_at_ctes_of invs'_def valid_state'_def
                                               valid_global_refs'_def cte_at_valid_cap_sizes_0)
                        apply (erule range_cover_le,simp)
                       apply (drule_tac p = "n" in range_cover_no_0)
                         apply (simp add:field_simps shiftl_t2n)+
                      apply (erule caps_no_overlap''_le)
                       apply (simp add:range_cover.sz[where 'a=32, folded word_bits_def])+
                     apply (erule caps_no_overlap''_le2)
                      apply (erule range_cover_compare_offset,simp+)
                     apply (simp add:range_cover_tail_mask[OF range_cover_le] range_cover_head_mask[OF range_cover_le])
                    apply (rule contra_subsetD)
                     apply (rule order_trans[rotated], erule range_cover_cell_subset,
                       erule of_nat_mono_maybe[rotated], simp)
                     apply (simp add: upto_intvl_eq shiftl_t2n mult.commute
                                      aligned_add_aligned[OF range_cover.aligned is_aligned_mult_triv2])
                    subgoal by simp
                   apply (simp add:cte_wp_at_no_0)
                  apply (rule disjoint_subset2[where B="{ptr .. foo}" for foo, rotated], simp add: Int_commute)
                  apply (rule order_trans[rotated], erule_tac p="Suc n" in range_cover_subset, simp+)
                  subgoal by (simp add: upto_intvl_eq shiftl_t2n mult.commute
                                   aligned_add_aligned[OF range_cover.aligned is_aligned_mult_triv2])
                 apply (drule_tac x = 0 in spec)
                 subgoal by simp
                apply (erule caps_overlap_reserved'_subseteq)
                subgoal by (clarsimp simp:range_cover_compare_offset blah)
               apply (erule descendants_range_in_subseteq')
               subgoal by (clarsimp simp:range_cover_compare_offset blah)
              apply (erule caps_overlap_reserved'_subseteq)
              apply (clarsimp simp:range_cover_compare_offset blah)
              apply (frule_tac x = "of_nat n" in range_cover_bound3)
               subgoal by (simp add:word_of_nat_less range_cover.unat_of_nat_n blah)
              subgoal by (simp add:field_simps shiftl_t2n blah)
             apply (simp add:shiftl_t2n field_simps)
             apply (rule contra_subsetD)
              apply (rule_tac x1 = 0 in subset_trans[OF _ range_cover_cell_subset,rotated ])
                apply (erule_tac p = n in range_cover_offset[rotated])
                subgoal by simp
               apply simp
               apply (rule less_diff_gt0)
               subgoal by (simp add:word_of_nat_less range_cover.unat_of_nat_n blah)
              apply (clarsimp simp: field_simps)
               apply (clarsimp simp: valid_idle'_def pred_tcb_at'_def
               dest!:invs_valid_idle' elim!: obj_atE')
             apply (drule(1) pspace_no_overlapD')
             apply (erule_tac x = "ksIdleThread s" in in_empty_interE[rotated])
              prefer 2
              apply (simp add:Int_ac)
             subgoal by (clarsimp simp: blah)
            subgoal by blast
           apply (erule descendants_range_in_subseteq')
           apply (clarsimp simp: blah)
           apply (rule order_trans[rotated], erule_tac x="of_nat n" in range_cover_bound'')
            subgoal by (simp add: word_less_nat_alt unat_of_nat)
           subgoal by (simp add: shiftl_t2n field_simps)
          apply (rule order_trans[rotated],
            erule_tac p="Suc n" in range_cover_subset, simp_all)[1]
          subgoal by (simp add: upto_intvl_eq shiftl_t2n mult.commute
                   aligned_add_aligned[OF range_cover.aligned is_aligned_mult_triv2])
         apply (erule cte_wp_at_weakenE')
         apply (clarsimp simp:shiftl_t2n field_simps)
         apply (erule subsetD)
         apply (erule subsetD[rotated])
         apply (rule_tac p1 = n in subset_trans[OF _ range_cover_subset])
            prefer 2
            apply (simp add:field_simps )
           apply (fold_subgoals (prefix))[2]
           subgoal premises prems using prems by (simp add:field_simps )+
        apply (clarsimp simp: word_shiftl_add_distrib)
        apply (clarsimp simp:blah field_simps shiftl_t2n)
        apply (drule word_eq_zeroI)
        apply (drule_tac p = "Suc n" in range_cover_no_0)
          apply (simp add:field_simps)+
       apply clarsimp
       apply (rule conjI)
        apply (drule_tac n = "x+1" and gbits = 4 in range_cover_not_zero_shift[OF _ range_cover_le,rotated])
           apply simp
          subgoal by (case_tac newType; simp add: objBits_simps' untypedBits_defs
                       APIType_capBits_def range_cover_def split:apiobject_type.splits)
         subgoal by simp
        subgoal by (simp add:word_of_nat_plus word_shiftl_add_distrib field_simps shiftl_t2n)
       apply (drule_tac x = "Suc x" in spec)
       subgoal by (clarsimp simp: field_simps)
      apply clarsimp
      apply (subst range_cover.unat_of_nat_n)
       apply (erule range_cover_le)
       apply simp
      apply (simp add:word_unat.Rep_inverse')
      subgoal by (clarsimp simp:range_cover.range_cover_n_less[where 'a=32, simplified])
     subgoal by clarsimp
    apply vcg
   apply (rule conseqPre, vcg, clarsimp)
   apply (frule(1) ghost_assertion_size_logic)
   apply (drule range_cover_sz')
   subgoal by (intro conjI impI; simp add: o_def word_of_nat_less)
  apply (rule conjI)
   apply (frule range_cover.aligned)
   apply (frule range_cover_full[OF range_cover.aligned])
    apply (simp add:range_cover_def word_bits_def)
   apply (clarsimp simp: invs_valid_pspace' conj_comms intvl_range_conv
        createObject_hs_preconds_def range_cover.aligned range_cover_full)
   apply (frule(1) range_cover_gsMaxObjectSize, fastforce, assumption)
   apply (simp add: intvl_range_conv[OF range_cover.aligned range_cover_sz']
                    order_trans[OF _ APIType_capBits_min])
   apply (intro conjI)
           subgoal by (simp add: word_bits_def range_cover_def)
          apply (clarsimp simp:rf_sr_def cstate_relation_def Let_def)
          apply (erule pspace_no_overlap'_le)
           apply (fold_subgoals (prefix))[2]
           subgoal premises prems using prems
                     by (simp add:range_cover.sz[where 'a=32, simplified] word_bits_def)+
         apply (erule contra_subsetD[rotated])
         subgoal by (rule order_trans[rotated], rule range_cover_subset'[where n=1],
           erule range_cover_le, simp_all, (clarsimp simp: neq_Nil_conv)+)
        apply (rule disjoint_subset2[rotated])
         apply (simp add:Int_ac)
        apply (erule range_cover_subset[where p = 0,simplified])
         subgoal by simp
        subgoal by simp
       subgoal by (simp add: Int_commute shiftl_t2n mult.commute)
      apply (erule cte_wp_at_weakenE')
      apply (clarsimp simp:blah word_and_le2 shiftl_t2n field_simps)
      apply (frule range_cover_bound''[where x = "of_nat (length destSlots) - 1"])
       subgoal by (simp add: range_cover_not_zero[rotated])
      subgoal by (simp add:field_simps)
     subgoal by (erule range_cover_subset[where p=0, simplified]; simp)
    apply clarsimp
    apply (drule_tac x = k in spec)
    apply simp
    apply (drule(1) bspec[OF _ nth_mem])+
    subgoal by (clarsimp simp: field_simps)
   apply clarsimp
   apply (drule(1) bspec[OF _ nth_mem])+
   subgoal by (clarsimp simp:cte_wp_at_ctes_of)
  apply clarsimp
  apply (frule range_cover_sz')
  apply (frule(1) range_cover_gsMaxObjectSize, fastforce, assumption)
  apply (clarsimp simp: cte_wp_at_ctes_of)
  apply (drule(1) ghost_assertion_size_logic)+
  apply (simp add: o_def)
  apply (case_tac newType,simp_all add:object_type_from_H_def Kernel_C_defs
             nAPIObjects_def APIType_capBits_def o_def split:apiobject_type.splits)[1]
          subgoal by (simp add:unat_eq_def word_unat.Rep_inverse' word_less_nat_alt)
         subgoal by (clarsimp simp: objBits_simps', unat_arith)
        apply (fold_subgoals (prefix))[3]
        subgoal premises prems using prems
                  by (clarsimp simp: objBits_simps' unat_eq_def word_unat.Rep_inverse'
                                     word_less_nat_alt)+

     by (clarsimp simp: ARMSmallPageBits_def ARMLargePageBits_def
                        ARMSectionBits_def ARMSuperSectionBits_def)+

end

end
