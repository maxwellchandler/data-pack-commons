#' @export
#' @title StackPrefixedCols(data, prefixes)
#' 
#' @description Takes columns from data with specified prefixes and stacks them based on the unprefixed
#' portion of the name. Columns not containing one of the prefixes are excluded in returned data. 
#' @param data dataframe - contains data to stack 
#' @param prefixes string vector - list of prefixes to include in column selection and stacking
#' @return  tibble with superset of columns without prefixes in column names
#'
StackPrefixedCols <- function(data, prefixes){
  assertthat::assert_that(length(prefixes) > 0, is.data.frame(data))
  SelectAndStripPrefix <- function(prefix, df) {
    dplyr::select(df, dplyr::starts_with(prefix, ignore.case = FALSE)) %>% 
      dplyr::rename_all(.funs = stringr::str_remove, pattern = prefix)
  }
  
  purrr::map(prefixes, SelectAndStripPrefix, data) %>% dplyr::bind_rows()
}

#' @export
#' @title FormatForApi_Dimensions(data, type_col, dim_id_col, item_id_col)
#' 
#' @description Uses specified columns in a data from to produce APIrequest 
#' formated dimensions e.g. &dimension=dim-id:dim-item;dim-item
#' Only includes unique dimension, dim-id, dim-item tupples 
#' @param data dataframe - containing parameters to incorporate into api call  
#' @param type_col string - name of column in data that specifies "dimension"
#' or "filter"
#' @param dim_id_col string - name of column in data that specifies 
#' dimension ids - including dx, ou, etc.
#' @param item_id_col string - name of column in data that specifies 
#' dimension item ids
#' @return  string ready for api call such as
#' "dimension=dim-id:dim-item;dim-item&filter=dim-id:dim-item;dim-item"
#' Note there is no leading "&" in string
#' @examples
#' df = tibble::tribble(~type, ~dim_id, ~item_id, ~other_col,
#' "dimension",    "LFsZ8v5v7rq", "CW81uF03hvV", 
#' "Implementing Partner: AIDSRelief Consortium",
#' "dimension",    "LFsZ8v5v7rq", "C6nZpLKjEJr", 
#' "Implementing Partner: African Medical and Research Foundation",
#' "filter", "dx", "BOSZApCrBni", "ART enrollment stage 1",
#' "filter", "dx", "dGdeotKpRed", "ART enrollment stage 2",
#' "dimension", "ou", "O6uvpzGd5pu", "Bo",
#' "filter", "pe", "THIS_FINANCIAL_YEAR","")
#' FormatForApi_Dimensions(df, "type", "dim_id", "item_id")
#'
FormatForApi_Dimensions <- function(data, type_col, dim_id_col, item_id_col){
  assertthat::assert_that(assertthat::has_name(data, type_col),
                          assertthat::has_name(data, dim_id_col),
                          assertthat::has_name(data, item_id_col))
  data %>% dplyr::mutate(type = data[[type_col]],
                         dim_id = data[[dim_id_col]],
                         item_id = data[[item_id_col]])  %>%
    dplyr::select(type, dim_id, item_id) %>% unique() %>% 
    dplyr::group_by_at(c("type", "dim_id"))  %>%  
    dplyr::summarise(items = paste0(item_id, collapse = ";")) %>% 
     dplyr::ungroup() %>% 
     dplyr::transmute(component = glue::glue("{type}={dim_id}:{items}")) %>% 
     .[[1]] %>% 
     paste0(collapse="&")
}

#' @export
#' @title RenameDimensionColumns(data, type)
#' 
#' @description Renames the original column names of datapackcommons::dim_items_sets, 
#' by prepending the string in the type parameter
#' @param data the unique dim_cop_type that is passed in the MapDimToOptions method
#' @param type It will pre-pend the string in type to the columns names
#' @return  The dataframe with renamed column names for dimensions
#'
RenameDimensionColumns <- function(data, type){
  data %>% dplyr::rename(!!paste0(type,"_dim_uid") := dim_uid,
                         !!paste0(type,"_dim_name") := dim_name,
                         !!paste0(type,"_dim_cop_type") := dim_cop_type,
                         !!paste0(type,"_dim_item_name") := dim_item_name,
                         !!paste0(type,"_option_name") := option_name,
                         !!paste0(type,"_option_uid") := option_uid,
                         !!paste0(type,"_sort_order") := sort_order,
                         !!paste0(type,"_weight") := weight,
                         !!paste0(type,"_model_sets") := model_sets) %>% return()
}

#' @export
#' @title MapDimToOptions(data, items_to_options, allocate)
#' 
#' @description A function that maps dimensions from a dataframe to the options sets
#' @param data dataframe - dimension name and dimension UID, along with the quantity
#' @param items_to_options dimension item sets dataframe filtered by one of the model sets
#' @param allocate If allocate is set to "distriute", mutates a column in the returned df with the weight being multiplied to the value
#' @return If there are no options provided, returns the analytics output, else if there are no dim_uid in the options list, joins the data using crossing or left join,
#' else if the allocation is set to "distriute", then renames them adds a value column and finally performs the renaming of the dimension columns.
#'
MapDimToOptions <- function(data, items_to_options, allocate){
  
  if(NROW(items_to_options) == 0){
    return(data)
  }
  
  dimension_uid <- unique(items_to_options$dim_uid)
  cop_category <- unique(items_to_options$dim_cop_type)
  assertthat::assert_that(NROW(dimension_uid) == 1, NROW(cop_category) == 1)
  
  if(is.na(dimension_uid)){
    # We are in a scenario of distributing to category options in the absence of a source dimension
    # so we need cartesian product of data with item_to_dim entries
    joined_data <- tidyr::crossing(data, 
                                   dplyr::select(items_to_options, -dim_item_uid))
  } else {
    dim_name <-  items_to_options[[1,"dim_name"]]
    joined_data <- data %>%
      dplyr::left_join(items_to_options, by = stats::setNames("dim_item_uid", dim_name))
  }
  
  if(allocate == "distribute"){
    joined_data %>%
      dplyr::mutate(Value = Value * weight) %>%
      RenameDimensionColumns(cop_category)
  } else{
    joined_data %>%
      RenameDimensionColumns(cop_category)
  }
}


#' @export
#' @title getDatasetUids
#' 
#' @description returns character verctor of dataset uids for a given FY {"19", "20", "21"}
#' and type {"targets", "results"}
#' @param fiscal_year character - one of {"19", "20", "21"} 
#' @param type character - one of {"targets", "results"}
#' @return returns a character verstor of the related dataset uids
#'
getDatasetUids <-  function(fiscal_year, type){
  if(fiscal_year == "21" & type == "targets") {
    c("Pmc0yYAIi1t", # MER Target Setting: PSNU (Facility and Community Combined)
      "s1sxJuqXsvV")  # MER Target Setting: PSNU (Facility and Community Combined) - DoD ONLY)
  } else if( fiscal_year == "21" & type == "subnat_impatt") {
    c("jxnjnBAb1VD", # Planning Attributes: COP Prioritization SNU 
      "j7jzezIhgPj") # Host Country Targets: COP Prioritization SNU (USG)
    } else if( fiscal_year == "20" & type == "targets") {
    c("sBv1dj90IX6", # MER Targets: Facility Based FY2020
      "nIHNMxuPUOR", # MER Targets: Community Based FY2020
      "C2G7IyPPrvD", # MER Targets: Community Based - DoD ONLY FY2020
      "HiJieecLXxN") # MER Targets: Facility Based - DoD ONLY FY2020
  } else if( fiscal_year == "19" & type == "targets") {
    c("BWBS39fydnX", # MER Targets: Community Based - DoD ONLY FY2019
      "l796jk9SW7q", # MER Targets: Community Based FY2019
      "X8sn5HE5inC", # MER Targets: Facility Based - DoD ONLY FY2019
      "eyI0UOWJnDk") # MER Targets: Facility Based FY2019)
  } else if( fiscal_year == "19" & type == "results") {
    c("KWRj80vEfHU", # MER Results: Facility Based FY2019Q4
      "fi9yMqWLWVy", # MER Results: Facility Based - DoD ONLY FY2019Q4
      "zUoy5hk8r0q", # MER Results: Community Based FY2019Q4
      "PyD4x9oFwxJ") # MER Results: Community Based - DoD ONLY FY2019Q4
  } 
  else if( fiscal_year == "18" & type == "results") {
    c("uN01TT331OP", # MER Results: Community Based - DoD ONLY FY2018Q4
      "WbszaIdCi92", # MER Results: Community Based FY2018Q4
      "BxIx51zpAjh", # MER Results: Facility Based - DoD ONLY FY2018Q4
      "tz1bQ3ZwUKJ") # MER Results: Facility Based FY2018Q4
  } 
  else{
    stop("input not supported by getDatasetUids")
  }
}