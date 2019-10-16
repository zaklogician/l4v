(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

theory ArchDetSchedAux_AI
imports "../DetSchedAux_AI"
begin


context Arch begin global_naming ARM

named_theorems DetSchedAux_AI_assms

lemmas arch_machine_ops_valid_sched_pred[wp] =
  arch_machine_ops_last_machine_time[THEN dmo_valid_sched_pred]
  arch_machine_ops_last_machine_time[THEN dmo_valid_sched_pred']

lemma set_pd_valid_sched_pred[wp]:
  "set_pd ptr pd \<lbrace>valid_sched_pred_strong P\<rbrace>"
  apply (wpsimp simp: set_pd_def wp: set_object_wp get_object_wp)
  by (auto simp: obj_at_kh_kheap_simps vs_all_heap_simps split: kernel_object.splits)

lemma set_pt_valid_sched_pred[wp]:
  "set_pt ptr pt \<lbrace>valid_sched_pred_strong P\<rbrace>"
  apply (wpsimp simp: set_pt_def wp: set_object_wp get_object_wp)
  by (auto simp: obj_at_kh_kheap_simps vs_all_heap_simps split: kernel_object.splits)

lemma set_asid_pool_bound_sc_obj_tcb_at[wp]:
  "set_asid_pool ptr pool \<lbrace>valid_sched_pred_strong P\<rbrace>"
  apply (wpsimp simp: set_asid_pool_def wp: set_object_wp get_object_wp)
  by (auto simp: obj_at_kh_kheap_simps vs_all_heap_simps split: kernel_object.splits)

lemma copy_global_mappings_valid_sched_pred[wp]:
  "copy_global_mappings pd \<lbrace>valid_sched_pred_strong P\<rbrace>"
  by (wpsimp simp: copy_global_mappings_def store_pde_def wp: mapM_x_wp_inv)

lemma init_arch_objects_valid_sched_pred[wp, DetSchedAux_AI_assms]:
  "init_arch_objects new_type ptr num_objects obj_sz refs \<lbrace>valid_sched_pred_strong P\<rbrace>"
  by (wpsimp simp: init_arch_objects_def wp: dmo_valid_sched_pred mapM_x_wp_inv)

crunches init_arch_objects
  for exst[wp]: "\<lambda>s. P (exst s)"
  and valid_idle[wp, DetSchedAux_AI_assms]: "\<lambda>s. valid_idle s"
  (wp: crunch_wps)

end

global_interpretation DetSchedAux_AI?: DetSchedAux_AI
  proof goal_cases
    interpret Arch .
    case 1 show ?case by (unfold_locales; (fact DetSchedAux_AI_assms)?)
  qed

context Arch begin global_naming ARM

(* FIXME: move? *)
lemma init_arch_objects_obj_at_impossible:
  "\<forall>ao. \<not> P (ArchObj ao) \<Longrightarrow>
    \<lbrace>\<lambda>s. Q (obj_at P p s)\<rbrace> init_arch_objects a b c d e \<lbrace>\<lambda>rv s. Q (obj_at P p s)\<rbrace>"
  by (auto intro: init_arch_objects_obj_at_non_pd)

lemma perform_asid_control_etcb_at:
  "\<lbrace>etcb_at P t\<rbrace>
   perform_asid_control_invocation aci
   \<lbrace>\<lambda>r s. st_tcb_at (Not \<circ> inactive) t s \<longrightarrow> etcb_at P t s\<rbrace>"
  apply (cases aci, rename_tac frame slot parent base)
  apply (simp add: perform_asid_control_invocation_def, thin_tac _)
  apply (rule hoare_seq_ext[OF _ delete_objects_etcb_at])
  apply (rule hoare_seq_ext[OF _ get_cap_inv])
  apply (rule hoare_seq_ext[OF _ set_cap_valid_sched_pred])
  apply (rule hoare_seq_ext[OF _ retype_region_etcb_at])
  apply (wpsimp wp: hoare_vcg_const_imp_lift hoare_vcg_imp_lift')
  by (clarsimp simp: pred_tcb_at_def obj_at_def)

crunches perform_asid_control_invocation
  for cur_time[wp]: "\<lambda>s. P (cur_time s)"

lemma perform_asid_control_invocation_bound_sc_obj_tcb_at[wp]:
  "\<lbrace>\<lambda>s. bound_sc_obj_tcb_at (P (cur_time s)) t s
        \<and> ex_nonz_cap_to t s
        \<and> invs s
        \<and> ct_active s
        \<and> scheduler_action s = resume_cur_thread
        \<and> valid_aci aci s \<rbrace>
   perform_asid_control_invocation aci
   \<lbrace>\<lambda>rv s. bound_sc_obj_tcb_at (P (cur_time s)) t s\<rbrace>"
  apply (rule hoare_lift_Pf_pre_conj[where f=cur_time, rotated], wpsimp)
  by (rule bound_sc_obj_tcb_at_nonz_cap_lift
      ; wpsimp wp: perform_asid_control_invocation_st_tcb_at
                   perform_asid_control_invocation_sc_at_pred_n)

crunches perform_asid_control_invocation
  for idle_thread[wp]: "\<lambda>s. P (idle_thread s)"
  and valid_blocked[wp]: "valid_blocked"
  (wp: static_imp_wp)

crunches perform_asid_control_invocation
  for rqueues[wp]: "\<lambda>s. P (ready_queues s)"
  and schedact[wp]: "\<lambda>s. P (scheduler_action s)"
  and cur_domain[wp]: "\<lambda>s. P (cur_domain s)"
  and release_queue[wp]: "\<lambda>s. P (release_queue s)"

(* FIXME: move to ArchArch_AI *)
lemma perform_asid_control_invocation_obj_at_live:
  assumes csp: "cspace_agnostic_pred P"
  assumes live: "\<forall>ko. P ko \<longrightarrow> live ko"
  shows
  "\<lbrace>\<lambda>s. N (obj_at P p s)
        \<and> invs s
        \<and> ct_active s
        \<and> valid_aci aci s
        \<and> scheduler_action s = resume_cur_thread\<rbrace>
   perform_asid_control_invocation aci
   \<lbrace>\<lambda>rv s. N (obj_at P p s)\<rbrace>"
  apply (clarsimp simp: perform_asid_control_invocation_def split: asid_control_invocation.splits)
  apply (rename_tac region_ptr target_slot_cnode target_slot_idx untyped_slot_cnode untyped_slot_idx asid)
  apply (rule_tac S="region_ptr && ~~mask page_bits = region_ptr \<and> is_aligned region_ptr page_bits
                     \<and> word_size_bits \<le> page_bits \<and> page_bits \<le> word_bits \<and> page_bits \<le> 32
                     \<and> obj_bits_api (ArchObject ASIDPoolObj) 0 = page_bits" in hoare_gen_asm''
         , fastforce simp: valid_aci_def cte_wp_at_caps_of_state valid_cap_simps
                           cap_aligned_def page_bits_def pageBits_def word_size_bits_def
                           obj_bits_api_def default_arch_object_def
                    dest!: caps_of_state_valid[rotated])
  apply (clarsimp simp: delete_objects_rewrite bind_assoc)
  apply (wpsimp wp: cap_insert_cspace_agnostic_obj_at[OF csp]
                    set_cap.cspace_agnostic_obj_at[OF csp]
                    retype_region_obj_at_live[where sz=page_bits, OF live]
                    max_index_upd_invs_simple set_cap_no_overlap get_cap_wp
                    hoare_vcg_ex_lift
         | strengthen invs_valid_objs invs_psp_aligned)+
  apply (frule detype_invariants
         ; clarsimp simp: valid_aci_def cte_wp_at_caps_of_state page_bits_def
                          intvl_range_conv empty_descendants_range_in descendants_range_def2
                          detype_clear_um_independent range_cover_full
                    cong: conj_cong)
  apply (frule pspace_no_overlap_detype[OF caps_of_state_valid_cap]; clarsimp)
  apply (erule rsubst[of N]; rule iffI; clarsimp simp: obj_at_def)
  apply (drule live[THEN spec, THEN mp])
  apply (frule (2) if_live_then_nonz_cap_invs)
  by (frule (2) descendants_of_empty_untyped_range[where p=p]; simp)

lemma perform_asid_control_invocation_pred_tcb_at_live:
  assumes live: "\<forall>tcb. P (proj (tcb_to_itcb tcb)) \<longrightarrow> live (TCB tcb)"
  shows
  "\<lbrace>\<lambda>s. N (pred_tcb_at proj P p s)
        \<and> invs s
        \<and> ct_active s
        \<and> valid_aci aci s
        \<and> scheduler_action s = resume_cur_thread\<rbrace>
   perform_asid_control_invocation aci
   \<lbrace>\<lambda>rv s. N (pred_tcb_at proj P p s)\<rbrace>"
  unfolding pred_tcb_at_def using live
  by (auto intro!: perform_asid_control_invocation_obj_at_live simp: cspace_agnostic_pred_def tcb_to_itcb_def)

lemma perform_asid_control_invocation_valid_idle:
  "\<lbrace>invs and ct_active
         and valid_aci aci
         and (\<lambda>s. scheduler_action s = resume_cur_thread)\<rbrace>
   perform_asid_control_invocation aci
   \<lbrace>\<lambda>_. valid_idle\<rbrace>"
  by (strengthen invs_valid_idle) wpsimp

crunches perform_asid_control_invocation
  for lmt[wp]: "\<lambda>s. P (last_machine_time_of s)"

lemma perform_asid_control_invocation_valid_sched:
  "\<lbrace>ct_active and (\<lambda>s. scheduler_action s = resume_cur_thread) and invs and valid_aci aci and
    valid_sched and valid_idle\<rbrace>
     perform_asid_control_invocation aci
   \<lbrace>\<lambda>_. valid_sched::det_ext state \<Rightarrow> _\<rbrace>"
  apply (rule hoare_pre)
   apply (rule_tac I="invs and ct_active and
                      (\<lambda>s. scheduler_action s = resume_cur_thread) and valid_aci aci"
          in valid_sched_tcb_state_preservation_gen)
               apply simp
              apply (wpsimp wp: perform_asid_control_invocation_st_tcb_at)
             apply (wpsimp wp: perform_asid_control_invocation_pred_tcb_at_live simp: ipc_queued_thread_state_live)
            apply (wpsimp wp: perform_asid_control_etcb_at)
           apply (wpsimp wp: perform_asid_control_invocation_st_tcb_at)
          apply (wpsimp wp: perform_asid_control_invocation_sc_at_pred_n)
         apply wp
        apply wp
       apply wp
      apply wp
     apply (wpsimp wp: perform_asid_control_invocation_valid_idle)
    apply wp
   apply (rule hoare_lift_Pf[where f=scheduler_action, OF _ perform_asid_control_invocation_schedact])
   apply (rule hoare_lift_Pf[where f=ready_queues, OF _ perform_asid_control_invocation_rqueues])
   apply (rule hoare_lift_Pf[where f=cur_domain, OF _ perform_asid_control_invocation_cur_domain])
   apply (rule perform_asid_control_invocation_release_queue)
  by clarsimp

lemma kernelWCET_us_non_zero:
  "kernelWCET_us \<noteq> 0"
  using kernelWCET_us_pos by fastforce

lemma kernelWCET_ticks_non_zero:
  "kernelWCET_ticks \<noteq> 0"
  using kernelWCET_us_non_zero us_to_ticks_nonzero
  by (fastforce simp: kernelWCET_ticks_def)

crunches retype_region, delete_objects
  for cur_sc[wp]: "\<lambda>(s:: det_ext state). P (cur_sc s)"
  (simp: detype_def)

lemma cur_sc_tcb_only_sym_bound_lift_pre_conj:
  assumes A: "\<And>P. \<lbrace>\<lambda>s. P (cur_thread s)\<rbrace> f \<lbrace>\<lambda>_ s. P (cur_thread s)\<rbrace>"
  assumes B: "\<And>P. \<lbrace>\<lambda>s. P (cur_sc s)\<rbrace> f \<lbrace>\<lambda>_ s. P (cur_sc s)\<rbrace>"
  assumes C: "\<And>P t. \<lbrace>\<lambda>s. \<not> (bound_sc_tcb_at P t s) \<and> R s\<rbrace> f \<lbrace>\<lambda>_ s. \<not> (bound_sc_tcb_at P t s)\<rbrace>"
  shows "\<lbrace>cur_sc_tcb_only_sym_bound and R\<rbrace> f \<lbrace>\<lambda>_. cur_sc_tcb_only_sym_bound\<rbrace>"
  unfolding cur_sc_tcb_only_sym_bound_def
  by (wpsimp wp: hoare_vcg_imp_lift' hoare_vcg_all_lift C hoare_vcg_disj_lift | wps A B)+

lemmas cur_sc_tcb_only_sym_bound_lift = cur_sc_tcb_only_sym_bound_lift_pre_conj[where R=\<top>, simplified]

lemma reset_untyped_cap_cur_sc[wp]:
  "reset_untyped_cap slot \<lbrace>(\<lambda>s. P (cur_sc s)) :: det_ext state \<Rightarrow> _\<rbrace>"
  unfolding reset_untyped_cap_def
  by (wpsimp wp: mapME_x_wp_inv preemption_point_inv get_cap_wp)

lemma delete_objects_not_bound_sc_tcb_at[wp]:
  "delete_objects d f \<lbrace>\<lambda>s. \<not> bound_sc_tcb_at P t s\<rbrace>"
  unfolding delete_objects_def
  by (wpsimp wp: )

lemma reset_untyped_not_bound_sc_tcb_at[wp]:
  "reset_untyped_cap slot \<lbrace>\<lambda>s. \<not> bound_sc_tcb_at P t s\<rbrace>"
  unfolding reset_untyped_cap_def
  by (wpsimp wp: mapME_x_wp_inv preemption_point_inv hoare_drop_imp)

lemma cur_sc_chargeable_invoke_untypedE_R[DetSchedAux_AI_assms]:
  "\<lbrace>cur_sc_tcb_only_sym_bound\<rbrace>
   invoke_untyped i
   -, \<lbrace>\<lambda>rv. cur_sc_tcb_only_sym_bound :: det_ext state \<Rightarrow> _\<rbrace>"
  unfolding invoke_untyped_def
  apply wpsimp
    apply (rule valid_validE_E)
    apply (clarsimp simp: cur_sc_tcb_only_sym_bound_def)
    apply (wpsimp wp: hoare_vcg_all_lift hoare_vcg_imp_lift)
      apply (rule valid_validE, wps)
      apply (wpsimp wp: reset_untyped_cap_bound_sc_tcb_at)
     apply wpsimp
    apply (wpsimp wp: hoare_vcg_all_lift hoare_vcg_imp_lift)
     apply (rule valid_validE, wps)
     apply (wpsimp wp:  reset_untyped_cap_bound_sc_tcb_at)
    apply wpsimp
   apply wpsimp
  apply (clarsimp)
  apply (simp only: cur_sc_tcb_only_sym_bound_def)
  done

end
end
