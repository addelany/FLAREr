##' @title Create matrix of observations in the format required by run_da_forecast
##' @details Creates a matrix of observations that maps the modeled states to the observed states. The function uses information from columns the obs_config file.
##' @param cleaned_observations_file_long string; file name (with full path) of the long-format observation file
##' @param obs_config list; observations configuration list
##' @param config list; flare configuration list
##' @return matrix that is based to generate_initial_conditions() and run_da_forecast()
##' @export
##' @import readr
##' @importFrom lubridate as_datetime as_date hour days
##' @importFrom dplyr filter
##' @author Quinn Thomas
##' @examples
##' \dontrun{
##' obs <- create_obs_matrix(cleaned_observations_file_long, obs_config, config)
##' }

create_obs_matrix <- function(cleaned_observations_file_long,
                              obs_config,
                              config){

  start_datetime <- lubridate::as_datetime(config$run_config$start_datetime)
  if(is.na(config$run_config$forecast_start_datetime)){
    end_datetime <- lubridate::as_datetime(config$run_config$end_datetime)
    forecast_start_datetime <- end_datetime
  }else{
    forecast_start_datetime <- lubridate::as_datetime(config$run_config$forecast_start_datetime)
    end_datetime <- forecast_start_datetime + lubridate::days(config$run_config$forecast_horizon)
  }

  full_time <- seq(start_datetime, end_datetime, by = "1 day")

  if(!is.null(cleaned_observations_file_long)){
    d <- readr::read_csv(cleaned_observations_file_long, show_col_types = FALSE, guess_max = 1000000)

    if("observed" %in% names(d)){
      d <- d |>
        dplyr::rename(value = observed)
    }else if ("observation" %in% names(d)){
      d <- d |>
        dplyr::rename(value = observation)
    }
    if("time" %in% names(d)){
      d <- d |>
        dplyr::mutate(hour = lubridate::hour(time),
               date = lubridate::as_date(time))
    }else if("datetime" %in% names(d)){
      d <- d |>
        dplyr::mutate(hour = lubridate::hour(datetime),
                      date = lubridate::as_date(datetime))
    }

    if(!("multi_depth" %in% names(obs_config))){
      obs_config <- obs_config |> dplyr::mutate(multi_depth = 1)
    }

    obs_config <- obs_config |>
      dplyr::filter(multi_depth == 1)

    if(config$model_settings$ncore == 1){
      future::plan("future::sequential", workers = config$model_settings$ncore)
    }else{
      future::plan("future::multisession", workers = config$model_settings$ncore)
    }

    obs_list <- furrr::future_map(1:length(obs_config$state_names_obs), function(i) {

      obs_tmp <- array(NA,dim = c(length(full_time), length(config$model_settings$modeled_depths)))

      for(k in 1:length(full_time)){
        for(j in 1:length(config$model_settings$modeled_depths)){
          d1 <- d %>%
            dplyr::filter(variable == obs_config$target_variable[i])
          # if(nrow(d1) == 0){
          #   warning("No observations for ", obs_config$target_variable[i])
          # }
          d1 <- d1 %>%
            dplyr::filter(date == lubridate::as_date(full_time[k]))
          # if(nrow(d1) == 0){
          #   warning("No observations for ", obs_config$target_variable[i], " on ", lubridate::as_date(full_time[k]))
          # }
          d1 <- d1 %>%
            dplyr::filter((is.na(hour) | hour == lubridate::hour(full_time[k])))
          # if(nrow(d1) == 0){
          #   warning("No observations for ", obs_config$target_variable[i], " on ", lubridate::as_date(full_time[k]),
          #           " at ", lubridate::hour(full_time[k]), ":00:00")
          # }

          d1 <- d1 %>%
            dplyr::filter(abs(d1$depth-config$model_settings$modeled_depths[j]) < obs_config$distance_threshold[i])

          if(nrow(d1) == 0){
            # warning("No observations for ", obs_config$target_variable[i], " on ", lubridate::as_date(full_time[k]),
            # " at ", lubridate::hour(full_time[k]), ":00:00", " within ", obs_config$distance_threshold[i],
            # "m of the modeled depth ", config$model_settings$modeled_depths[j], "m")
          }
          if(nrow(d1) >= 1){
            if(nrow(d1) > 1){
              warning("There are multiple observations for ", obs_config$target_variable[i], " at depth ",config$model_settings$modeled_depths[j],"\nUsing the mean")
              obs_tmp[k,j] <- mean(d1$value, na.rm = TRUE)
            }else{
              obs_tmp[k,j] <- d1$value
            }
          }
        }
      }

      # Check for NAs
      if(sum(is.na(obs_tmp)) == (dim(obs_tmp)[1] * dim(obs_tmp)[2]) ) {
        warning("All values are NA for ", obs_config$target_variable[i])
      }
      return(obs_tmp)
    })

    obs <- array(NA, dim = c(length(obs_config$state_names_obs), length(full_time), length(config$model_settings$modeled_depths)))
    for(i in 1:nrow(obs_config)) {
      obs[i , , ] <-  obs_list[[i]]
    }

    full_time_forecast <- seq(start_datetime, end_datetime, by = "1 day")
    obs[ , which(full_time_forecast > forecast_start_datetime), ] <- NA
  }else{
    obs <- array(NA, dim = c(1, length(full_time), length(config$model_settings$modeled_depths)))
  }

  return(obs)
}
