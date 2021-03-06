get_test_aois <- function() {
  left <- data.frame(aoi_name = "left", top_left_x = 0, 
                     bottom_right_x = 555, top_left_y = 262,
                     bottom_right_y = 788)
  
  right <- data.frame(aoi_name = "right", top_left_x = 1125, 
                      bottom_right_x = 1680, top_left_y = 262, 
                      bottom_right_y = 788) 
  
  times <- data.frame(Time = seq(0, TEST_LENGTH, (1 / FRAME_RATE)))
  
  bind_rows(left_join(mutate(times, aoi_name = "left"), left),
            left_join(mutate(times, aoi_name = "right"), right))
}

get_train_aois <- function(video, annotations) {
  xmls <- list.files(paste0(path = 'processed_data/aois/train_aois/', 
                            video, '/'), pattern = '*.xml',
                     all.files = FALSE, full.names = TRUE)
  
  train_aois <- lapply(xmls, xmlToList)
   
  make_aoi_keyframe = function(aoi, key_frame) {

    key_frame_df <- aoi$KeyFrames[key_frame]$KeyFrame
    if(key_frame_df$Visible == "false") {
      data.frame(Time = as.numeric(key_frame_df$Timestamp)/1000000,
                 top_left_x = NA,
                 top_left_y = NA,
                 bottom_right_x = NA,
                 bottom_right_y = NA)
    }
    
    # CONVERTED FIRST TO 16/10 and then 1/1
    # Started at 960 x 540
    # Then padded to to 960 x 720 -- should shift y's up by 90
    # Then cropped to 720 x 720 -- should shift x's left by 120
    else {
      data.frame(Time = as.numeric(key_frame_df$Timestamp)/1000000,
                 top_left_x = (as.numeric(key_frame_df$Points[1]$Point$X) 
                               - 120) * SCALE_X,
                 top_left_y = (as.numeric(key_frame_df$Points[1]$Point$Y) 
                               + 90) * SCALE_Y,
                 bottom_right_x = (as.numeric(key_frame_df$Points[2]$Point$X) 
                                   - 120) * SCALE_X,
                 bottom_right_y = (as.numeric(key_frame_df$Points[2]$Point$Y) 
                                   + 90) * SCALE_Y)
    }
  }
  
  make_train_aoi <- function(aoi, end_time = NA) {
    
    # Get the AOIs for each manually coded keyframe
    aoi_df <- bind_rows(lapply(1:length(aoi$KeyFrames), 
                               function(key_frame) {
                                 make_aoi_keyframe(aoi, key_frame)})) %>%
      mutate(aoi_name = aoi$Name) %>%
      mutate(Time = floor(FRAME_RATE * Time) / FRAME_RATE)
    
    # Single keyframe
    if(nrow(aoi_df) == 1) {
      aoi_df[2,] = aoi_df[1,]
      aoi_df[2,"Time"] = end_time
    }
    
    # Find the times between keyframes
    all_times <- seq(min(aoi_df$Time),max(aoi_df$Time), 1 / FRAME_RATE)
    
    #Drop the last frame if it was the invisible point
    if(is.na(tail(aoi_df,1)$top_left_x)) {
      aoi_df <- aoi_df[1:(nrow(aoi_df) - 1),]
      all_times <- all_times[1:(length(all_times) - 1)]
    }
    
    # Floating point tolerance issue fix for setdiff
    diff_times <- all_times[sapply(all_times, function(x) {
      Reduce(and, abs((aoi_df$Time-x)) >= 1e-5)})]
    
    # Make a NA-filled array for the times between keyframes
    fills <- data.frame(Time = diff_times,
                        aoi_name = aoi_df[1,"aoi_name"],
                        top_left_x = as.numeric(NA),
                        top_left_y = as.numeric(NA),
                        bottom_right_x = as.numeric(NA),
                        bottom_right_y = as.numeric(NA))
    
    # Do constant interpolation to fill in AOIs for these between-times
    all_pts <- bind_rows(aoi_df, fills) %>%
      arrange(Time) 
    
    all_pts %>%
      mutate_each(funs(na.approx(., Time, method = "constant", rule = 2)),
                  top_left_x, top_left_y, bottom_right_x, bottom_right_y)
  }
  
  per_trial_pts <- function(trial) {
    trial_aois <- train_aois[[trial]]
    end_time <- annotations[trial,"end"]
    
    bind_rows(lapply(1:length(trial_aois), function(aoi_num) {
      make_train_aoi(trial_aois[aoi_num]$DynamicAOI, end_time)})) %>%
      arrange(Time) %>%
      mutate(trial = trial)
  }
  
  train_aoi_pts <- bind_rows(lapply(1:length(train_aois), per_trial_pts))
  
}
