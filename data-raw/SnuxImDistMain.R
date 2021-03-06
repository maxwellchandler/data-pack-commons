#' @title BuildDimensionList_DataPack(data_element_map_item, dim_item_sets, 
#' country_uid, mechanisms = NULL)
#' 
#' @description get list of dimensions (parameters) for analytics call to get data for SNUxIM 
#' distribution. Tightly coupled to DATIM as it contains some hard coded dimension uids 
#' for Funding Mechanism, technical area, num or denom, disagg type, support type, 
#' and type of organization unit. Also some hard coded dimension items for support type
#' @param data_element_map_item Single row of data_element_map being sliced and passed
#' @param dim_item_sets Dataframe containing all the dimension item sets e.g. datapackcommons::dim_item_sets
#' @param country_uid Country uid
#' @param mechanisms All historic mechanisms for the country filtered by id.
#' @param mil Set to True to pull the military data, false excludes military data when pulling PSNU
#' level data
#' When included the dimensions include psnu, mechanism, AND DSD/TA disaggregation.
#' When null psnu, mechanism and DSD/TA disaggregation are excluded giving country level totals.
#' @return  List of dimensions for the analytics call GetData_Analytics
BuildDimensionList_DataPack <- function(data_element_map_item, dim_item_sets, 
                                        country_uid, mechanisms = NULL,
                                        mil = FALSE){
  
  # prepare df of common dimensions and filters as expected by GetData_analytics  
  dimension_common <- 
    tibble::tribble(~type, ~dim_item_uid, ~dim_uid,
                    "filter", data_element_map_item[[1,"dx"]],"dx", 
                    "filter", data_element_map_item[[1,"pe"]], "pe",
                    "dimension", country_uid, "ou",
                    "dimension", data_element_map_item[[1,"technical_area_uid"]], "LxhLO68FcXm",
                    "dimension", data_element_map_item[[1,"num_or_den_uid"]],"lD2x0c8kywj",
                    "dimension", data_element_map_item[[1,"disagg_type_uid"]],"HWPJnUTMjEq"
    )
  
  # prepare df of dimensions and filters as expected by GetData_analytics  
  dimension_disaggs <- dim_item_sets %>% dplyr::mutate(type = "dimension") %>%  
    dplyr::filter(model_sets %in% c(data_element_map_item$age_set,
                                    data_element_map_item$sex_set,
                                    data_element_map_item$kp_set,
                                    data_element_map_item$other_disagg)) %>% 
    dplyr::select(type, dim_item_uid, dim_uid) %>%
    unique()  %>% 
    stats::na.omit() # there are some items in dim item sets with no source dimension
  
  if (is.null(mechanisms)){
    return(dplyr::bind_rows(dimension_common, dimension_disaggs))
  }
  
  
  dimension_mechanisms <- mechanisms["mechanism_co_uid"] %>% 
    dplyr::transmute(type = "dimension",
                     dim_item_uid = mechanism_co_uid,
                     dim_uid = "SH885jaRe0o")
  
  # remaining dimensions
  if (mil == FALSE) {  
    # need to select all org unit types EXCEPT military because it is 
    # possible for military to be below general PSNU level in org hierarchy   
    non_mil_types_of_org_units <- 
      datapackcommons::getMetadata(base_url = base_url, 
                                   "dimensions", 
                                   "id:eq:mINJi7rR1a6", 
                                   "items[name,id]") %>% 
      tidyr::unnest(c("items")) %>% 
      dplyr::filter(name != "Military") %>% 
      .[["id"]]
    
    tibble::tibble(type = "filter",
                   dim_item_uid = non_mil_types_of_org_units,
                   dim_uid = "mINJi7rR1a6") %>% 
    dplyr::bind_rows(tibble::tribble(~type, ~dim_item_uid, ~dim_uid, 
                  "dimension", "OU_GROUP-AVy8gJXym2D", "ou", # COP Prioritization SNU
                  "dimension", "iM13vdNLWKb", "TWXpUVE2MqL", #dsd and ta support types
                  "dimension", "cRAGKdWIDn4", "TWXpUVE2MqL")) %>% 
    dplyr::bind_rows(dimension_mechanisms, dimension_disaggs, dimension_common)
    } else {
  tibble::tribble(~type, ~dim_item_uid, ~dim_uid,
                  "dimension", "OU_GROUP-nwQbMeALRjL", "ou", # military
                  "dimension", "iM13vdNLWKb", "TWXpUVE2MqL", #dsd and ta support types
                  "dimension", "cRAGKdWIDn4", "TWXpUVE2MqL") %>% 
        dplyr::bind_rows(dimension_mechanisms, dimension_disaggs, dimension_common)
    }
}

GetFy20tMechs <- function(base_url = getOption("baseurl")){

  
  #TODO modify format data for api function so I can make this call with getData_Analytics
  
  mech_codes <- datapackcommons::getMetadata(base_url, 
                                            "categories",
                                            "id:eq:SH885jaRe0o",
                                            "categoryOptions[id,code]") %>% 
    .[["categoryOptions"]] %>% 
    .[[1]] %>% 
    dplyr::rename(mechanism_co_uid = "id", mechanism_code = "code")
  
  mechs <- paste0(base_url, "api/29/analytics.csv?dimension=SH885jaRe0o&dimension=ou:OU_GROUP-cNzfcPWEGSH;ybg3MO3hcf4&filter=pe:THIS_FINANCIAL_YEAR&filter=dx:DE_GROUP-XUA8pDYjPsw&displayProperty=SHORTNAME&outputIdScheme=UID") %>% 
    datapackcommons::RetryAPI("application/csv") %>% 
    httr::content() %>% 
    readr::read_csv() %>%
    dplyr::select(-Value) %>% 
    setNames(c("mechanism_co_uid", "country_uid")) %>% 
    dplyr::left_join(mech_codes)
  
  if(NROW(mechs) > 0){
    return(mechs)
  }
  # If I got here critical error
  stop("Unable to get 20T mechanisms")
}

getSnuxIm_density <- function(data_element_map_item, 
                              dim_item_sets = datapackcommons::dim_item_sets, 
                              country_uid,
                              mechanisms){ 
  
  
  data <-  BuildDimensionList_DataPack(data_element_map_item, 
                                       dim_item_sets,
                                       country_uid,
                                       mechanisms["mechanism_co_uid"],
                                       mil = FALSE) %>% 
    datapackcommons::GetData_Analytics() %>% .[["results"]]

  data <-  BuildDimensionList_DataPack(data_element_map_item, 
                                       dim_item_sets,
                                       country_uid,
                                       mechanisms["mechanism_co_uid"],
                                       mil = TRUE) %>% 
    datapackcommons::GetData_Analytics() %>% .[["results"]] %>% 
    dplyr::bind_rows(data)
  
  if (NROW(data) == 0) return(NULL)
  
  # quick check that data disaggregated by psnu, mechanism, and support type sum to country total    
  checksum <- BuildDimensionList_DataPack(data_element_map_item,
                                          dim_item_sets,
                                          country_uid) %>%
    datapackcommons::GetData_Analytics() %>% .[["results"]] %>% .[["Value"]] %>% sum()
  
  if(sum(data$Value) != checksum){
    stop(paste("Internal Error: Disaggregated data not summing up to aggregated data in getSnuxIm_density function", sum(data$Value), checksum))
  }
  
  disagg_sets  <-  c("age_set", 
                     "sex_set", 
                     "kp_set", 
                     "other_disagg") %>% 
    purrr::map(~dplyr::filter(dim_item_sets,
                              model_sets == data_element_map_item[[1, .]]))
  
  data <- purrr::reduce(disagg_sets,
                        datapackcommons::MapDimToOptions,
                        allocate = "distribute",
                        .init = data) %>% 
    dplyr::left_join(mechanisms, by = c("Funding Mechanism" = "mechanism_co_uid")) %>% 
    dplyr::mutate(indicator_code = data_element_map_item$indicator_code) %>%
    dplyr::rename("value" = "Value",
                  "psnu_uid" = "Organisation unit",
                  "type" = "Support Type") %>% 
    dplyr::select(dplyr::one_of("indicator_code", "psnu_uid",
                                "mechanism_code", "type",
                                "age_option_name", "age_option_uid",
                                "sex_option_name", "sex_option_uid",
                                "kp_option_name", "kp_option_uid",
                                "value"))
  
  if("age_option_name" %in% names(data)){
    data$age_option_name[data$age_option_name == "<1"] <- "<01"
    data$age_option_name[data$age_option_name == "1-4"] <- "01-04"
    data$age_option_name[data$age_option_name == "5-9"] <- "05-09"
    data$age_option_name[data$age_option_name == "<= 2 months"] <- "<= 02 months"
    data$age_option_name[data$age_option_name == "2 - 12 months"] <- "02 - 12 months"
  }
  data$type[data$type == "cRAGKdWIDn4"] <- "TA"
  data$type[data$type == "iM13vdNLWKb"] <- "DSD"
  
  return(data)
}

process_country <- function(country_uid, mechs){

  print(country_uid)
  # Get the mechanisms relevant for the specifc country being processed
  # cache options required for datimvalidation function to work.
  # cache age option reverts to original after calling datim validation
  
  mechs <-   dplyr::filter(mechs, country_uid == !!country_uid)
  if(NROW(mechs) == 0){return(NULL)}
  
  # alply to call SiteDensity for each row of data_element_map (each target data element)
  # will have a historic distribution for each target, DSD/TA, and site given psnu/IM
  # alply uses parallel processing here 
  
  doMC::registerDoMC(cores = 5)
  data <-  plyr::adply(datapackcommons::Map20Tto21T,
                     1, getSnuxIm_density,
                     datapackcommons::dim_item_sets,
                     country_uid,
                     mechs, 
                     .parallel = TRUE, .expand = FALSE, .id = NULL) 
  if(NROW(data) == 0){return(NULL)}
  
  data <-  data %>% 
    dplyr::group_by_at(dplyr::vars(-value)) %>% 
    dplyr::summarise(value = sum(value, na.rm = TRUE)) %>% 
    dplyr::ungroup()

  if(!("kp_option_uid" %in% names(data))){
    data <- dplyr::mutate(data,
                  "kp_option_uid" = NA_character_,
                  "kp_option_name" = NA_character_)
    }
    
    dplyr::group_by(data,
                    indicator_code, 
                    psnu_uid, 
                    age_option_uid, 
                    sex_option_uid, 
                    kp_option_uid) %>%
    dplyr::mutate(percent = value/sum(value)) %>% 
    dplyr::ungroup()
}

devtools::install(pkg = "/Users/sam/Documents/GitHub/data-pack-commons",
                  build = TRUE,
                  upgrade = FALSE)

library(datapackcommons)

library(dplyr)
DHISLogin("/users/sam/.secrets/datim.json")
base_url <- getOption("baseurl")
mechs = GetFy20tMechs()
country_details <-  datapackcommons::GetCountryLevels(base_url) 

data <-  country_details[["id"]] %>% 
  purrr::map(process_country, mechs)
data <- setNames(data,country_details$id)
#readr::write_rds(data,"/Users/sam/COP data/PSNUxIM_20200207.rds", compress = c("gz"))
data_old=readr::read_rds("/Users/sam/COP data/PSNUxIM_20200228.rds")
purrr::map(names(data), ~dplyr::all_equal(data[[.x]],data_old[[.x]])) %>% 
  setNames(country_details$country_name)
