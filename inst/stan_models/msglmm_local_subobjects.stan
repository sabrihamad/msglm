functions {
    real intensity_log_std(real z, real scaleHi, real scaleLo, real offset, real bend, real smooth) {
        return 0.5*(scaleHi+scaleLo)*(z-bend) + 0.5*(scaleHi-scaleLo)*sqrt((z-bend)*(z-bend)+smooth) + offset;
    }

    // reimplementation of R contr.poly::make.poly()
    matrix contr_poly(int n) {
        vector[n] scores;
        matrix[n, n] x;
        matrix[n, n] r;
        row_vector[n] r_norm;

        for (i in 1:n) scores[i] = i; //*inv(n);
        scores -= mean(scores);

        for (i in 1:n) {
            for (j in 1:n) {
                x[i, j] = scores[i]^(j-1);
            }
        }
        r = qr_Q(x) * diag_matrix(diagonal(qr_R(x)));
        r_norm = sqrt(columns_dot_self(r));
        //print("r_norm=", r_norm);
        for (i in 1:n) {
          if (r_norm[i] == 0.0) {
            r_norm[i] = 1.0;
          }
        }
        r ./= rep_matrix(r_norm, n);
        return block(r, 1, 2, n, n-1);
    }

    // count nonzero elements in effXeff0 matrix
    // (block-diagonal matrix with block generated by contr_poly())
    int effXeff0_Nw(int ngroups, int[] effect2group) {
        int neffs[ngroups];
        int nw;
        for (i in 1:ngroups) neffs[i] = 0;
        for (i in 1:num_elements(effect2group)) neffs[effect2group[i]] += 1;
        nw = 0;
        for (i in 1:ngroups) nw += (neffs[i]-1)*neffs[i];
        return nw;
    }
}

data {
  int<lower=1> Nexperiments;    // number of experiments
  int<lower=1> Nconditions;     // number of experimental conditions
  int<lower=0> Nobjects;        // number of objects (proteins/peptides/sites etc)
  int<lower=0> Nsubobjects;     // number of objects subcomponents (peptides of proteins etc), 0 if not supported
  int<lower=0> Nmsprotocols;    // number of MS protocols used
  int<lower=0> Niactions;       // number of interactions (observed objectXcondition pairs)
  int<lower=1> Nsupactions;     // number of interaction superpositions
  int<lower=0> Nobservations;   // number of observations of interactions (objectXexperiment pairs for all iactions and experiments of its condition)
  int<lower=0> Neffects;        // number of effects (that define conditions)
  int<lower=0> NbatchEffects;   // number of batch effects (that define assay experimental variation, but not biology)
  int<lower=0> NunderdefObjs;   // number of virtual interactions (the ones not detected but required for comparison)
  int<lower=1> Nmix;            // number of interactions mixed in each supaction
  int<lower=1> Nmixtions;       // number of premixed interactions (iaction X mix_coefficient)
  int<lower=1,upper=Nobjects> suo2obj[Nsubobjects];
  int<lower=1,upper=Nobjects> iaction2obj[Niactions];
  int<lower=1,upper=Nobjects> underdef_objs[NunderdefObjs];

  int<lower=1,upper=Niactions> mixt2iact[Nmixtions];
  int<lower=0,upper=Nmix> mixt2mix[Nmixtions];

  vector[Nmix] mix_effect_mean;
  vector<lower=0>[Nmix] mix_effect_tau;
  
  vector[Nexperiments] experiment_shift;

  int<lower=1,upper=Nexperiments> observation2experiment[Nobservations];
  int<lower=1,upper=Nsupactions> observation2supaction[Nobservations];
  int<lower=1,upper=Nmsprotocols> experiment2msproto[Nmsprotocols > 0 ? Nexperiments : 0];

  // map from labelXreplicateXobject to observed/missed data
  int<lower=0> Nquanted;        // total number of quantified subobjectsXexperiments
  int<lower=1,upper=Nobservations>  quant2observation[Nquanted];
  int<lower=1,upper=Nsubobjects> quant2suo[Nsubobjects > 0 ? Nquanted : 0];
  int<lower=0> Nmissed;         // total number of missed subobjectsXexperiments
  int<lower=1,upper=Nobservations> miss2observation[Nmissed];
  int<lower=1,upper=Nsubobjects> miss2suo[Nsubobjects > 0 ? Nmissed : 0];

  int<lower=0> NobjEffects;
  int<lower=1,upper=Neffects> obj_effect2effect[NobjEffects];
  int<lower=0,upper=1> effect_is_positive[Neffects];
  vector[Neffects] effect_mean;

  int<lower=0> NobjBatchEffects;
  int<lower=1,upper=NbatchEffects> obj_batch_effect2batch_effect[NobjBatchEffects];
  int<lower=0,upper=1> batch_effect_is_positive[NbatchEffects];

  // iactXobjeff (interaction X object_effect) sparse matrix
  int<lower=0> iactXobjeff_Nw;
  vector[iactXobjeff_Nw] iactXobjeff_w;
  int<lower=0, upper=iactXobjeff_Nw+1> iactXobjeff_u[Niactions+1];
  int<lower=0, upper=NobjEffects> iactXobjeff_v[iactXobjeff_Nw];

  // supactXmixt in CSR format (all nonzero values are 1)
  int<lower=0> supactXmixt_Nw;
  int<lower=1,upper=supactXmixt_Nw+1> supactXmixt_u[Nsupactions+1];
  int<lower=1,upper=Nmixtions> supactXmixt_v[supactXmixt_Nw];
  vector[supactXmixt_Nw] supactXmixt_w;

  // obsXobj_batcheff (observation X batch_effect) sparse matrix
  int<lower=0> obsXobjbatcheff_Nw;
  vector[obsXobjbatcheff_Nw] obsXobjbatcheff_w;
  int<lower=0, upper=obsXobjbatcheff_Nw+1> obsXobjbatcheff_u[Nobservations + 1];
  int<lower=0, upper=NobjBatchEffects> obsXobjbatcheff_v[obsXobjbatcheff_Nw];

  vector<lower=0>[Nquanted] qData; // quanted data

  // global model constants
  real global_labu_shift;   // shift to be applied to all XXX_labu variables to get the real log intensity
  vector<lower=0>[Neffects] effect_tau;
  real<lower=0> obj_base_repl_shift_tau;
  real<lower=0> obj_effect_repl_shift_tau;
  real<lower=0> obj_batch_effect_tau;
  real<lower=0> obj_base_labu_sigma;
  real<upper=0> underdef_obj_shift;

  // instrument calibrated parameters
  real<lower=0> zDetectionFactor;
  real zDetectionIntercept;
  real<lower=0, upper=1> detectionMax;

  real<lower=0> sigmaScaleHi;
  real<lower=0> sigmaScaleLo;
  real sigmaOffset;
  real sigmaBend;
  real sigmaSmooth;

  real zShift;
  real zScale;
}

transformed data {
  real mzShift; // zShift for the missing observation intensity (zShift shifted by obj_base)
  vector[Nquanted] zScore; // log(qData) transformed in zScore
  vector[Nquanted] qLogStd; // log(sd(qData))-obj_base
  vector<lower=0>[Nquanted] qDataNorm; // qData/sd(qData)

  int<lower=1,upper=Nsupactions> quant2supaction[Nquanted];
  int<lower=1,upper=Nexperiments> quant2experiment[Nquanted];
  int<lower=1,upper=Nmsprotocols*Nsubobjects> quant2msprotoXsuo[((Nmsprotocols > 1) && (Nsubobjects > 0)) ? Nquanted : 0];
  int<lower=1,upper=Nsupactions> miss2supaction[Nmissed];
  int<lower=1,upper=Nexperiments> miss2experiment[Nmissed];
  int<lower=1,upper=Nmsprotocols*Nsubobjects> miss2msprotoXsuo[((Nmsprotocols > 1) && (Nsubobjects > 0)) ? Nmissed : 0];
  int<lower=0,upper=NobjEffects> NobjEffectsPos;
  int<lower=0,upper=NobjEffects> NobjEffectsOther;
  int<lower=1,upper=NobjEffects> obj_effect_reshuffle[NobjEffects];
  vector<lower=0>[NobjEffects] obj_effect_tau;
  vector[NobjEffects] obj_effect_mean;
  vector[NunderdefObjs > 0 ? Nobjects : 0] obj_base_shift;

  int<lower=0,upper=NobjBatchEffects> NobjBatchEffectsPos;
  int<lower=0,upper=NobjBatchEffects> NobjBatchEffectsOther;
  int<lower=1,upper=NobjBatchEffects> obj_batch_effect_reshuffle[NobjBatchEffects];

  vector[iactXobjeff_Nw] iactXobjeff4sigma_w;

  vector[Niactions] iactXobjbase_w;
  int<lower=0> iactXobjbase_u[Niactions + 1];

  vector[Nsupactions] supactXobjbase_w;
  int<lower=0> supactXobjbase_u[Nsupactions + 1];
  int<lower=1,upper=Nobjects> supaction2obj[Nsupactions]; // _v
  int<lower=1,upper=Niactions> supaction2iaction[Nsupactions];

  int<lower=1,upper=Nmix+1> mixt2mix_ext[Nmixtions]; // mixt2mix with all indices shifted by 1

  vector[Nobservations] obsXsupact_w;
  int<lower=0> obsXsupact_u[Nobservations + 1];

  int<lower=0> Nobservations0;  // number of observations degrees of freedom ()

  int<lower=0> obsXobs0_Nw;
  vector[effXeff0_Nw(Nsupactions, observation2supaction)] obsXobs_shift0_w;
  int<lower=1, upper=effXeff0_Nw(Nsupactions, observation2supaction) + 1> obsXobs_shift0_u[Nobservations + 1];
  int<lower=1, upper=Nobservations - Nsupactions> obsXobs_shift0_v[effXeff0_Nw(Nsupactions, observation2supaction)];

  vector[Nsubobjects > 0 ? Nsubobjects - Nobjects : 0] suoXsuo_shift0_w;
  int<lower=0, upper=(Nsubobjects > 0 ? Nsubobjects - Nobjects + 1 : 0)> suoXsuo_shift0_u[Nsubobjects + 1];
  int<lower=0, upper=Nsubobjects - Nobjects> suoXsuo_shift0_v[Nsubobjects - Nobjects];

  if (NunderdefObjs > 0) {
    obj_base_shift = rep_vector(0.0, Nobjects);
    for (i in 1:NunderdefObjs) {
      obj_base_shift[underdef_objs[i]] = underdef_obj_shift;
    }
  }

  // prepare reshuffling of positive/other obj effects
  NobjEffectsPos = sum(effect_is_positive[obj_effect2effect]);
  NobjEffectsOther = NobjEffects - NobjEffectsPos;
  {
    int cur_pos_eff;
    int cur_other_eff;
    cur_pos_eff = 0;
    cur_other_eff = NobjEffectsPos;
    for (i in 1:NobjEffects) {
      if (effect_is_positive[obj_effect2effect[i]]) {
        cur_pos_eff += 1;
        obj_effect_reshuffle[i] = cur_pos_eff;
      } else {
        cur_other_eff += 1;
        obj_effect_reshuffle[i] = cur_other_eff;
      }
    }
  }
  obj_effect_tau = effect_tau[obj_effect2effect];
  obj_effect_mean = effect_mean[obj_effect2effect];

  // prepare reshuffling of positive/other batch effects
  NobjBatchEffectsPos = sum(batch_effect_is_positive[obj_batch_effect2batch_effect]);
  NobjBatchEffectsOther = NobjBatchEffects - NobjBatchEffectsPos;
  {
    int cur_pos_eff;
    int cur_other_eff;
    cur_pos_eff = 0;
    cur_other_eff = NobjBatchEffectsPos;
    for (i in 1:NobjBatchEffects) {
      if (batch_effect_is_positive[obj_batch_effect2batch_effect[i]]) {
        cur_pos_eff += 1;
        obj_batch_effect_reshuffle[i] = cur_pos_eff;
      } else {
        cur_other_eff += 1;
        obj_batch_effect_reshuffle[i] = cur_other_eff;
      }
    }
  }

  // preprocess signals (MS noise)
  {
    vector[Nquanted] qLogData;
    qLogData = log(qData);
    zScore = (qLogData - zShift) * zScale;
    mzShift = zShift - global_labu_shift;

    // process the intensity data to optimize likelihood calculation
    for (i in 1:Nquanted) {
      qLogStd[i] = intensity_log_std(zScore[i], sigmaScaleHi, sigmaScaleLo, sigmaOffset, sigmaBend, sigmaSmooth);
      qDataNorm[i] = exp(qLogData[i] - qLogStd[i]);
      qLogStd[i] -= global_labu_shift; // obs_labu is modeled without obj_base
    }
  }
  quant2experiment = observation2experiment[quant2observation];
  quant2supaction = observation2supaction[quant2observation];
  miss2experiment = observation2experiment[miss2observation];
  miss2supaction = observation2supaction[miss2observation];

  // prepare obsXobs_shift0
  obsXobs0_Nw = effXeff0_Nw(Nsupactions, observation2supaction);
  {
    int supaction2nobs[Nsupactions];

    int supaction2nobs_2ndpass[Nsupactions];
    int supaction2obs_shift0_offset[Nsupactions];

    int obsXobs_shift0_offset;
    int obs_shift0_offset;

    supaction2nobs = rep_array(0, Nsupactions);
    for (i in 1:Nobservations) {
      int sact_ix;
      sact_ix = observation2supaction[i];
      supaction2nobs[sact_ix] += 1;
    }
    //print("supaction2nobs=", supaction2nobs);
    obs_shift0_offset = 0;
    obsXobs_shift0_offset = 0;
    obsXobs_shift0_u[1] = 1;
    supaction2nobs_2ndpass = rep_array(0, Nsupactions);
    supaction2obs_shift0_offset = rep_array(0, Nsupactions);
    for (i in 1:Nobservations) {
        int sact_ix;
        int sact_nobs;
        sact_ix = observation2supaction[i];
        //print("iact_ix[", i, "]=", iact_ix);
        sact_nobs = supaction2nobs[sact_ix];
        if (sact_nobs > 1) {
            // (re)generate contr_poly for interaction FIXME pre-build contr_poly for 2..max_nobs
            matrix[sact_nobs, sact_nobs-1] sact_obsXobs0 = contr_poly(sact_nobs);

            if (supaction2nobs_2ndpass[sact_ix] == 0) {
                // reserve (nobs-1) obs_shift0 variables
                supaction2obs_shift0_offset[sact_ix] = obs_shift0_offset;
                obs_shift0_offset += sact_nobs-1;
                //print("obs_shift0_offset=", obs_shift0_offset);
            }
            supaction2nobs_2ndpass[sact_ix] += 1;
            // add 2npass-th row of iact_obsXobs0 to the obsXobs0
            for (j in 1:cols(sact_obsXobs0)) {
                obsXobs_shift0_v[obsXobs_shift0_offset + j] = supaction2obs_shift0_offset[sact_ix] + j;
                obsXobs_shift0_w[obsXobs_shift0_offset + j] = sact_obsXobs0[supaction2nobs_2ndpass[sact_ix], j];
            }
            obsXobs_shift0_u[i+1] = obsXobs_shift0_u[i] + cols(sact_obsXobs0);
            obsXobs_shift0_offset += cols(sact_obsXobs0);
        }
    }
  }
  Nobservations0 = Nobservations - Nsupactions;
  //print("obsXobs_shift0=", csr_to_dense_matrix(Nobservations, Nobservations0, obsXobs_shift0_w, obsXobs_shift0_v, obsXobs_shift0_u));

  iactXobjeff4sigma_w = square(iactXobjeff_w);
  iactXobjbase_w = rep_vector(1.0, Niactions);
  for (i in 1:(Niactions+1)) iactXobjbase_u[i] = i;

  supactXobjbase_w = rep_vector(1.0, Nsupactions);
  for (i in 1:(Nsupactions+1)) supactXobjbase_u[i] = i;
  // get the first mixtion of supaction from supactXmixt matrix, map it to interaction
  supaction2iaction = mixt2iact[supactXmixt_v[supactXmixt_u[1:Nsupactions]]];
  supaction2obj = iaction2obj[supaction2iaction];

  obsXsupact_w = rep_vector(1.0, Nobservations);
  for (i in 1:(Nobservations+1)) obsXsupact_u[i] = i;

  // prepare supactXmixt matrix
  for (i in 1:Nmixtions) mixt2mix_ext[i] = mixt2mix[i] + 1;

  if (Nsubobjects > 0) {
    # subXsuo_shift0 matrix fixes the shift of the first subobject of each
    # object to 0
    int last_obj_ix;
    suoXsuo_shift0_w = rep_vector(1.0, Nsubobjects - Nobjects);

    for (i in 1:Nsubobjects-Nobjects) suoXsuo_shift0_v[i] = i;

    last_obj_ix = 0;
    for (i in 1:Nsubobjects) {
      suoXsuo_shift0_u[i] = i - last_obj_ix;
      if (last_obj_ix != suo2obj[i]) {
        last_obj_ix = suo2obj[i];
      }
    }
    suoXsuo_shift0_u[Nsubobjects + 1] = Nsubobjects - Nobjects + 1;
    #print("suoXsuo_shift0_u=", suoXsuo_shift0_u);
    #print("suoXsuo_shift0_v=", suoXsuo_shift0_v);
    #print("suoXsuo_shift0=", csr_to_dense_matrix(Nsubobjects, Nsubobjects - Nobjects,
    #      suoXsuo_shift0_w, suoXsuo_shift0_v, suoXsuo_shift0_u));

    if (Nmsprotocols > 1) {
      // all references to the 1st protocol are redirected to index 1 (this shift is always 0)
      for (i in 1:Nquanted) {
        int msproto;
        msproto = experiment2msproto[quant2experiment[i]];
        quant2msprotoXsuo[i] = msproto > 1 ? (msproto-1)*Nsubobjects + quant2suo[i] + 1 : 1;
      }
      for (i in 1:Nmissed) {
        int msproto;
        msproto = experiment2msproto[quant2experiment[i]];
        miss2msprotoXsuo[i] = msproto > 1 ? (msproto-1)*Nsubobjects + miss2suo[i] + 1 : 1;
      }
    }
  }
}

parameters {
  //real obj_base;
  //real<lower=-20, upper=-2> underdef_obj_shift;
  //real<lower=0, upper=5.0> obj_shift_sigma;
  //vector<lower=0>[Nconditions] condition_repl_effect_sigma;

  vector[Nobjects] obj_base_labu0; // baseline object abundance without underdefinedness adjustment
  vector<lower=0.01>[Nobservations0 > 0 ? Nobjects : 0] obj_base_repl_shift_sigma;

  real<lower=0.0> suo_shift_sigma;
  vector[Nsubobjects > 0 ? Nsubobjects-Nobjects : 0] suo_shift0_unscaled; // subobject shift within object
  real<lower=0.0> suo_msproto_shift_sigma;
  vector[Nsubobjects > 0 && Nmsprotocols > 1 ? Nsubobjects * (Nmsprotocols-1) : 0] suo_msproto_shift_unscaled;

  //real<lower=0.0> obj_effect_tau;
  vector<lower=0.0>[NobjEffects] obj_effect_lambda_t;
  vector<lower=0.0>[NobjEffects] obj_effect_lambda_a;
  vector<lower=0.0>[NobjEffectsPos] obj_effect_unscaled_pos;
  vector[NobjEffectsOther] obj_effect_unscaled_other;

  //real<lower=0> obj_repl_effect_sigma;
  //vector<lower=0>[Nobjects*Nexperiments] repl_shift_lambda;
  vector<lower=0.01>[Nobservations0 > 0 ? NobjEffects : 0] obj_effect_repl_shift_sigma;
  vector[Nobservations0] obs_shift0;

  //real<lower=0> obj_batch_effect_sigma;
  vector<lower=0>[NobjBatchEffects] obj_batch_effect_lambda_t;
  vector<lower=0>[NobjBatchEffects] obj_batch_effect_lambda_a;
  vector<lower=0.0>[NobjBatchEffectsPos] obj_batch_effect_unscaled_pos;
  vector[NobjBatchEffectsOther] obj_batch_effect_unscaled_other;

  vector<lower=0.0>[Nmix] obj_mix_effect_lambda_t;
  vector<lower=0.0>[Nmix] obj_mix_effect_lambda_a;
  vector[Nmix] obj_mix_effect_unscaled;
}

transformed parameters {
  vector[Nobjects] obj_base_labu;
  vector[NobjEffects] obj_effect;
  vector<lower=0>[NobjEffects] obj_effect_sigma;
  vector[NobjBatchEffects] obj_batch_effect;

  vector<lower=0>[Nmix] obj_mix_effect_sigma;
  vector[Nmix] obj_mix_effect;

  vector[Niactions] iaction_labu;
  vector[Nsupactions] supaction_labu;
  vector[Nobservations0 > 0 ? Nsupactions : 0] supact_repl_shift_sigma;

  vector[Nobservations0 > 0 ? Niactions : 0] iact_repl_shift_sigma;
  vector[Nobservations] obs_labu; // supaction_labu + objXexp_repl_shift * obj_repl_shift_sigma
  vector[Nobservations0 > 0 ? Nobservations : 0] obs_repl_shift; // replicate shifts for all potential observations (including missing)
  vector[NobjBatchEffects > 0 ? Nobservations : 0] obs_batch_shift;

  vector[Nsubobjects] suo_shift_unscaled; // subcomponent shift within object

  if (NunderdefObjs > 0) {
    // correct baseline abundances of underdefined objects
    obj_base_labu = obj_base_labu0 + obj_base_shift;
  } else {
    obj_base_labu = obj_base_labu0;
  }

  // calculate obj_mix_effects
  obj_mix_effect_sigma = obj_mix_effect_lambda_a .* inv_sqrt(obj_mix_effect_lambda_t) .* mix_effect_tau;
  obj_mix_effect = mix_effect_mean + obj_mix_effect_unscaled .* obj_mix_effect_sigma;

  // calculate object effects lambdas and scale effects
  obj_effect_sigma = obj_effect_lambda_a .* inv_sqrt(obj_effect_lambda_t) .* obj_effect_tau;
  obj_effect = obj_effect_mean + append_row(obj_effect_unscaled_pos, obj_effect_unscaled_other)[obj_effect_reshuffle] .* obj_effect_sigma;

  // calculate iaction_labu and supaction_labu
  {
    vector[Niactions] preiaction_labu;
    vector[Nmixtions] mixtion_abu;
    vector[Nsupactions] supaction_abu;
    //vector[Nsupactions] supaction_abu_trunc;

    // multiply effects by iactXobjeff, hold off adding obj_base_labu to avoid overflows with exp()
    preiaction_labu = csr_matrix_times_vector(Niactions, NobjEffects, iactXobjeff_w, iactXobjeff_v, iactXobjeff_u, obj_effect);
    //print("preiaction_labu=", preiaction_labu);
    // distribute iaction_labu components to mixtures and convert to exponent
    mixtion_abu = exp(preiaction_labu[mixt2iact] + append_row(1.0, obj_mix_effect)[mixt2mix_ext]);
    //print("mixtion_abu=", mixtion_abu);
    // do mixing
    supaction_abu = csr_matrix_times_vector(Nsupactions, Nmixtions, supactXmixt_w, supactXmixt_v, supactXmixt_u, mixtion_abu);
    //print("supaction_abu=", supaction_abu);
    //for (i in 1:Nsupactions) {
    //  supaction_abu_trunc[i] = fmax(supaction_abu[i], 1E-5);
    //}
    //print("supaction_abu_trunc=", supaction_abu_trunc);
    // convert to log back and add obj_base_labu shifts
    supaction_labu = log(supaction_abu) +
          csr_matrix_times_vector(Nsupactions, Nobjects, supactXobjbase_w, supaction2obj,
                                  supactXobjbase_u, obj_base_labu);
    // add obj_base_labu shifts to iaction_labu
    iaction_labu = csr_matrix_times_vector(Niactions, Nobjects, iactXobjbase_w, iaction2obj,
                                           iactXobjbase_u, obj_base_labu) +
                   preiaction_labu;
  }

  // calculate obs_shift and obs_labu
  obs_labu = csr_matrix_times_vector(Nobservations, Nsupactions, obsXsupact_w, observation2supaction, obsXsupact_u, supaction_labu);
  if (Nobservations0 > 0) {
    // FIXME: non-linear transform of obj_effect_repl_shift_sigma, Jacobian is not zero
    iact_repl_shift_sigma = sqrt(csr_matrix_times_vector(Niactions, NobjEffects, iactXobjeff4sigma_w,
                                                         iactXobjeff_v, iactXobjeff_u,
                                                         square(obj_effect_repl_shift_sigma)) +
                                 csr_matrix_times_vector(Niactions, Nobjects, iactXobjbase_w,
                                                         iaction2obj, iactXobjbase_u,
                                                         square(obj_base_repl_shift_sigma)));
    // HACK: just use the first mixtion to get the supaction -> iaction correspondence
    supact_repl_shift_sigma = iact_repl_shift_sigma[supaction2iaction];
    obs_repl_shift = csr_matrix_times_vector(Nobservations, Nobservations0,
                                             obsXobs_shift0_w, obsXobs_shift0_v,
                                             obsXobs_shift0_u, obs_shift0);
    obs_labu += obs_repl_shift;
  }
  // calculate objXexp_batch_shift (doesn't make sense to add to obs_labu)
  if (NbatchEffects > 0) {
    vector[NobjBatchEffects] obj_batch_effect_sigma;

    obj_batch_effect_sigma = obj_batch_effect_lambda_a .* inv_sqrt(obj_batch_effect_lambda_t) * obj_batch_effect_tau;
    obj_batch_effect = append_row(obj_batch_effect_unscaled_pos, obj_batch_effect_unscaled_other)[obj_batch_effect_reshuffle] .* obj_batch_effect_sigma;
    obs_batch_shift = csr_matrix_times_vector(Nobservations, NobjBatchEffects,
                                              obsXobjbatcheff_w, obsXobjbatcheff_v,
                                              obsXobjbatcheff_u, obj_batch_effect);
  }
  // calculate suo_labu_shift
  if (Nsubobjects > 1) {
    suo_shift_unscaled = csr_matrix_times_vector(Nsubobjects, Nsubobjects - Nobjects,
                                                 suoXsuo_shift0_w, suoXsuo_shift0_v,
                                                 suoXsuo_shift0_u, suo_shift0_unscaled);
  } else if (Nsubobjects == 1) {
    suo_shift_unscaled = rep_vector(0.0, Nsubobjects);
  }
}

model {
    // abundance distribution
    //obj_base ~ normal(zShift, 1.0);
    //obj_shift_sigma ~ inv_gamma(2.0, 0.33/zScale); // mode is 1/zScale
    obj_base_labu0 ~ normal(0, obj_base_labu_sigma);
    // treatment effect parameters, horseshoe prior
    //obj_effect_tau ~ student_t(2, 0.0, 1.0);
    //obj_effect_lambda ~ student_t(2, 0.0, obj_effect_tau);
    obj_effect_lambda_t ~ chi_square(2.0);
    obj_effect_lambda_a ~ normal(0.0, 1.0); // 1.0 = 2/2
    obj_effect_unscaled_pos ~ normal(0.0, 1.0);
    obj_effect_unscaled_other ~ normal(0.0, 1.0);
    // batch effect parameters, cauchy prior on sigma
    //condition_repl_effect_sigma ~ inv_gamma(1.5, 1.0);

    obj_mix_effect_lambda_t ~ chi_square(2.0);
    obj_mix_effect_lambda_a ~ normal(0.0, 1.0); // 1.0 = 2/2
    obj_mix_effect_unscaled ~ normal(0.0, 1.0);

    //underdef_obj_shift ~ normal(0.0, 10.0);

    //repl_shift_lambda ~ student_t(2, 0.0, repl_shift_tau);
    //obj_repl_effect ~ normal(0.0, obj_repl_effect_lambda);
    if (Nobservations0 > 0) {
      vector[Nobservations] obs_repl_shift_sigma;
      obj_base_repl_shift_sigma ~ student_t(4, 0.0, obj_base_repl_shift_tau);
      obj_effect_repl_shift_sigma ~ student_t(4, 0.0, obj_effect_repl_shift_tau);
      obs_repl_shift_sigma = csr_matrix_times_vector(Nobservations, Nsupactions,
              obsXsupact_w, observation2supaction, obsXsupact_u, supact_repl_shift_sigma);
      //print("iact_repl_shift_sigma=", iact_repl_shift_sigma);
      //print("obsXiact=", csr_to_dense_matrix(Nobservations, Niactions,
      //          obsXiact_w, observation2iaction, obsXiact_u));
      obs_repl_shift ~ normal(0.0, obs_repl_shift_sigma);
    }
    //to_vector(repl_shift) ~ normal(0.0, repl_shift_lambda);

    //obj_batch_effect_lambda ~ student_t(2, 0.0, obj_batch_effect_tau);
    if (NbatchEffects > 0) {
      obj_batch_effect_lambda_t ~ chi_square(3.0);
      obj_batch_effect_lambda_a ~ normal(0.0, 1.0);
      //obj_batch_effect ~ normal(0.0, obj_batch_effect_lambda);
      obj_batch_effect_unscaled_pos ~ normal(0.0, 1.0);
      obj_batch_effect_unscaled_other ~ normal(0.0, 1.0);
    }
    if (Nsubobjects > 0) {
      suo_shift_sigma ~ inv_gamma(1.0, 1.0);
      suo_shift_unscaled ~ normal(0.0, 1.0);
      suo_msproto_shift_sigma ~ inv_gamma(2.0, 1.0); // if Nmsprotocols==1, fake something far from 0 and +Inf
      if (Nmsprotocols > 1) {
        to_vector(suo_msproto_shift_unscaled) ~ normal(0.0, 1.0);
      }
    }

    // calculate the likelihood
    {
        vector[Nquanted] q_labu;
        vector[Nmissed] m_labu;

        q_labu = obs_labu[quant2observation] + experiment_shift[quant2experiment];
        m_labu = obs_labu[miss2observation] + experiment_shift[miss2experiment];
        //qLogAbu = iaction_shift[quant2iaction] + experiment_shift[quant2experiment];
        //mLogAbu = iaction_shift[miss2iaction] + experiment_shift[miss2experiment];
        if (Nsubobjects > 0) {
            // adjust by subcomponent shift
            vector[Nsubobjects] suo_shift;
            suo_shift = suo_shift_unscaled * suo_shift_sigma;
            q_labu += suo_shift[quant2suo];
            m_labu += suo_shift[miss2suo];

            if (Nmsprotocols > 1) {
                vector[(Nmsprotocols-1)*Nsubobjects+1] suo_msproto_shift;
                suo_msproto_shift[1] = 0.0; // the 1st protocol has no shift (taken care by suo_shift)
                suo_msproto_shift[2:((Nmsprotocols-1)*Nsubobjects+1)] = suo_msproto_shift_unscaled * suo_msproto_shift_sigma;

                q_labu += suo_msproto_shift[quant2msprotoXsuo];
                m_labu += suo_msproto_shift[miss2msprotoXsuo];
            }
        }
        if (NbatchEffects > 0) {
          q_labu += obs_batch_shift[quant2observation];
          m_labu += obs_batch_shift[miss2observation];
        }

        // model quantitations and missing data
        qDataNorm ~ double_exponential(exp(q_labu - qLogStd), 1);
        1 ~ bernoulli_logit(q_labu * (zScale * zDetectionFactor) + (-mzShift * zScale * zDetectionFactor + zDetectionIntercept));
        0 ~ bernoulli_logit(m_labu * (zScale * zDetectionFactor) + (-mzShift * zScale * zDetectionFactor + zDetectionIntercept));
    }
}

generated quantities {
    vector[Nobjects] obj_base_labu_replCI;
    vector[NobjEffects] obj_effect_replCI;
    vector[Niactions] iaction_labu_replCI;
    vector[Nsubobjects] suo_llh;

    for (i in 1:Nobjects) {
        obj_base_labu_replCI[i] = normal_rng(obj_base_labu[i], obj_base_repl_shift_sigma[i]);
    }
    for (i in 1:NobjEffects) {
        obj_effect_replCI[i] = normal_rng(obj_effect[i], obj_effect_repl_shift_sigma[i]);
    }
    iaction_labu_replCI = csr_matrix_times_vector(Niactions, Nobjects, iactXobjbase_w, iaction2obj, iactXobjbase_u, obj_base_labu_replCI) +
                          csr_matrix_times_vector(Niactions, NobjEffects, iactXobjeff_w, iactXobjeff_v, iactXobjeff_u, obj_effect_replCI);
    // per-subobject loglikelihood (the code copied from "model" section)
    if (Nsubobjects > 0) {
        vector[Nquanted] q_labu;
        vector[Nmissed] m_labu;
        vector[Nsubobjects] suo_shift;

        suo_shift = suo_shift_unscaled * suo_shift_sigma;
        // prepare predicted abundances
        q_labu = obs_labu[quant2observation] + experiment_shift[quant2experiment] + suo_shift[quant2suo];
        m_labu = obs_labu[miss2observation] + experiment_shift[miss2experiment] + suo_shift[miss2suo];

        if (Nmsprotocols > 1) {
            vector[(Nmsprotocols-1)*Nsubobjects+1] suo_msproto_shift;
            suo_msproto_shift[1] = 0.0; // the 1st protocol has no shift (taken care by suo_shift)
            suo_msproto_shift[2:((Nmsprotocols-1)*Nsubobjects+1)] = suo_msproto_shift_unscaled * suo_msproto_shift_sigma;

            q_labu += suo_msproto_shift[quant2msprotoXsuo];
            m_labu += suo_msproto_shift[miss2msprotoXsuo];
        }
        if (NbatchEffects > 0) {
          q_labu = q_labu + obs_batch_shift[quant2observation];
          m_labu = m_labu + obs_batch_shift[miss2observation];
        }

        // calculate log-likelihood per subobject
        suo_llh = rep_vector(0.0, Nsubobjects);
        for (i in 1:Nquanted) {
          suo_llh[quant2suo[i]] += double_exponential_lpdf(qDataNorm[i] | exp(q_labu[i] - qLogStd[i]), 1) +
              bernoulli_logit_lpmf(1 | q_labu[i] * (zScale * zDetectionFactor) + (-mzShift * zScale * zDetectionFactor + zDetectionIntercept));
        }
        for (i in 1:Nmissed) {
          suo_llh[miss2suo[i]] += bernoulli_logit_lpmf(0 | m_labu[i] * (zScale * zDetectionFactor) + (-mzShift * zScale * zDetectionFactor + zDetectionIntercept));
        }
    }
}
