process_msglm_chunk <- function(file_ix,
                                strip_samples=FALSE, strip_stats=FALSE,
                                postprocess.f = NULL) {
  fit_model.file <- fit_model.files.df[ file_ix, 'filename' ]
  message( 'Loading ', fit_model.file, '...' )
  tmp.env <- new.env(parent = baseenv())
  load(file.path(fit_model_path, fit_model.file ), envir = tmp.env)
  if (!is.null(postprocess.f)) {
    postprocess.f(envir = tmp.env, fit_model.file)
  }
  if (strip_samples || strip_stats) {
    tmp.env$vars_results <- lapply( tmp.env$vars_results, function( var_results ) {
      if (strip_samples) { var_results$samples <- NULL }
      if (strip_stats) { var_results$stats <- NULL }
      return ( var_results )
    } )
  }
  gc()
  res <- mget(ls(envir=tmp.env), envir=tmp.env)
  return ( res )
}

join_report_frames <- function(reports, frame_extractor=function(report) stop('no frame extractor'),
                               global_vars = c('model_dataset', 'version', 'chunk'),
                               prot_info=NULL)
{
  if (is.null(names(reports))) {
    report_names <- seq_along(reports)
  } else {
    report_names <- names(reports)
  }
  joined_res.df <- bind_rows(lapply(report_names, function(report_name) {
    report <- reports[[report_name]]
    frame <- frame_extractor(report)
    if (is.null(frame)) return ( NULL )
    if (nrow(frame) > 0L) {
      frame$report_name <- report_name
    } else {
      frame$report_name <- character()
    }
    for (var in global_vars) {
      frame[[var]] <- report[[var]]
    }
    return ( frame )
  } ) )
  # FIXME other object types?
  if ( !is.null(prot_info) && 'protein_ac_noiso' %in% colnames( joined_res.df ) ) {
    joined_res.df <- dplyr::inner_join( joined_res.df, prot_info[,c('protein_ac_noiso','protein_label','description')] )
  }
  return ( joined_res.df )
}

join_msglm_reports <- function(section, reports, type) {
  message( 'Assembling joint ', type, ' report for ', section, '...' )
  res <- join_report_frames(reports, frame_extractor = function(report) {
    res <- report$vars_results[[section]][[type]]
    # add object id columns
    # FIXME sites support?
    # FIXME model_data$objects support?
    if (!is.null(res) && !('majority_protein_acs' %in% colnames(res))
        && "majority_protein_acs" %in% colnames(report$model_data$protgroups)) {
      res$majority_protein_acs <- rep_len(report$model_data$protgroups$majority_protein_acs[1], nrow(res))
      res$protgroup_id <- rep_len(report$model_data$protgroups$protgroup_id[1], nrow(res))
    }
    if (!is.null(res) && !('pepmod_id' %in% colnames(res))
        && "pepmod_id" %in% colnames(report$model_data$pepmods)) {
      res$pepmod_id <- rep_len(report$model_data$pepmods$pepmod_id[1], nrow(res))
    }
    res
  },
  NULL, global_vars = c())
  return(res)
}