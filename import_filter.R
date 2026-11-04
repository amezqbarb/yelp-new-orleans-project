library(tidyverse)
library(jsonlite)
library(lubridate)
library(sf)
library(tigris)
library(scales)
library(viridis)

business_file <- "data/raw/yelp_academic_dataset_business.json"
review_file <- "data/raw/yelp_academic_dataset_review.json"

file.exists(business_file)
file.exists(review_file)

business_raw <- jsonlite::stream_in(
  file(business_file),
  verbose = TRUE
)
business <- business_raw |>
  select(
    business_id,
    name,
    address,
    city,
    state,
    postal_code,
    latitude,
    longitude,
    stars,
    review_count,
    categories
  )

new_orleans_restaurants <- business |>
  filter(
    state == "LA",
    city == "New Orleans",
    !is.na(categories),
    str_detect(
      categories,
      regex("Restaurants", ignore_case = TRUE)
    )
  ) |>
  mutate(
    postal_code = na_if(postal_code, ""),
    categories = str_squish(categories),
    business_name = str_squish(name)
  ) |>
  distinct(business_id, .keep_all = TRUE)

dir.create(
  "data/new_orleans",
  recursive = TRUE,
  showWarnings = FALSE
)

saveRDS(
  new_orleans_restaurants,
  "data/new_orleans/business_new_orleans.rds",
  compress = "xz"
)
review_ids <- new_orleans_restaurants$business_id

review_chunks <- list()
chunk_number <- 0

review_connection <- file(review_file, open = "r")

jsonlite::stream_in(
  review_connection,
  pagesize = 10000,
  verbose = TRUE,
  handler = function(chunk) {
    
    matching_reviews <- chunk |>
      filter(business_id %in% review_ids) |>
      select(
        business_id,
        user_id,
        stars,
        date,
        useful,
        funny,
        cool
      )
    
    if (nrow(matching_reviews) > 0) {
      chunk_number <<- chunk_number + 1
      review_chunks[[chunk_number]] <<- matching_reviews
    }
  }
)

close(review_connection)

new_orleans_reviews <- bind_rows(review_chunks)

dim(new_orleans_reviews)
glimpse(new_orleans_reviews)

saveRDS(
  new_orleans_reviews,
  "data/new_orleans/reviews_new_orleans.rds",
  compress = "xz"
)
restaurants_check <- readRDS(
  "data/new_orleans/business_new_orleans.rds"
)

reviews_check <- readRDS(
  "data/new_orleans/reviews_new_orleans.rds"
)

dim(restaurants_check)
dim(reviews_check)