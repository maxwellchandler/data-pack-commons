% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/dhis2api.R
\name{GetData_DataPack}
\alias{GetData_DataPack}
\title{GetData_DataPack}
\usage{
GetData_DataPack(
  parameters,
  org_units,
  dim_item_sets = datapackcommons::dim_item_sets,
  org_unit_groups = c("nwQbMeALRjL", "AVy8gJXym2D"),
  org_unit_levels = NULL,
  base_url = getOption("baseurl")
)
}
\value{
A list with $time = time the function was called, 
$api_call = api call used, and 
$results = the data returnd by the analytics call
}
\description{
GetData_DataPack
}
