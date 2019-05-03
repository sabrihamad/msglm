#' @useDynLib msglm
#' @importFrom dplyr %>% tibble as_tibble mutate mutate_at select select_at
#' @importForm dplyr summarise summarise_at rename rename_at arrange arrange_at group_by group_by_at
#' @importFrom dplyr row_number coalesce case_when if_else n n_distinct one_of cume_dist
#' @importFrom stringr str_count str_detect str_subset str_match str_replace str_remove str_split_fixed
NULL

.onLoad <- function(lib, pkg)
{
}

.onAttach <- function(lib, pkg)
{
    #packageStartupMessage("Linked to JAGS ",
    #                      .Call("get_version", PACKAGE="rjags"))
}


.onUnload <- function(libpath)
{
    #library.dynam.unload("rjags", libpath)
}