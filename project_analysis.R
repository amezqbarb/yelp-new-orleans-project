library(tidyverse)
library(jsonlite)
library(lubridate)
library(sf)
library(tigris)
library(scales)
library(viridis)

new_orleans_restaurants <- readRDS(
  "data/new_orleans/business_new_orleans.rds"
)

new_orleans_reviews <- readRDS(
  "data/new_orleans/reviews_new_orleans.rds"
)

dim(new_orleans_restaurants)
dim(new_orleans_reviews)

restaurant_categories <- new_orleans_restaurants |>
  separate_rows(categories, sep = ",") |>
  mutate(
    category = str_to_lower(str_squish(categories))
  ) |>
  count(category, sort = TRUE)

restaurant_categories |>
  slice_head(n = 30)

restaurant_categories_long <- new_orleans_restaurants |>
  separate_rows(categories, sep = ",") |>
  mutate(
    category = str_to_lower(str_squish(categories))
  )

selected_categories <- c(
  "cajun/creole",
  "seafood",
  "southern"
)

selected_restaurants <- restaurant_categories_long |>
  filter(category %in% selected_categories) |>
  distinct(business_id, .keep_all = TRUE)

selected_restaurants |>
  summarise(
    number_of_selected_restaurants = n(),
    number_of_geographic_locations = n_distinct(postal_code)
  )

selected_restaurants |>
  count(category, sort = TRUE)

selected_restaurants |>
  summarise(
    number_of_selected_restaurants = n_distinct(business_id),
    number_of_zip_codes = n_distinct(postal_code, na.rm = TRUE),
    missing_zip_codes = sum(is.na(postal_code))
  )

selected_reviews <- new_orleans_reviews |>
  semi_join(
    selected_restaurants |>
      distinct(business_id),
    by = "business_id"
  )

dim(selected_reviews)
glimpse(selected_reviews)

louisiana_places <- tigris::places(
  state = "LA",
  cb = TRUE,
  year = 2024,
  class = "sf"
) |>
  rename(place_name = NAME)

restaurant_points <- selected_restaurants |>
  filter(
    !is.na(longitude),
    !is.na(latitude)
  ) |>
  st_as_sf(
    coords = c("longitude", "latitude"),
    crs = 4326,
    remove = FALSE
  ) |>
  st_transform(st_crs(louisiana_places))

restaurants_with_place <- restaurant_points |>
  st_join(
    louisiana_places |>
      select(GEOID, place_name),
    join = st_within,
    left = TRUE
  )

restaurants_with_place |>
  st_drop_geometry() |>
  count(city, place_name, sort = TRUE)

new_orleans_boundary <- louisiana_places |>
  filter(place_name == "New Orleans")

new_orleans_map_data <- restaurants_with_place |>
  filter(place_name == "New Orleans")

ggplot() +
  geom_sf(
    data = new_orleans_boundary,
    fill = "grey95",
    color = "grey35"
  ) +
  geom_sf(
    data = new_orleans_map_data,
    aes(color = stars),
    alpha = 0.65,
    size = 1.5
  ) +
  scale_color_viridis_c(
    option = "C",
    limits = c(1, 5)
  ) +
  labs(
    title = "Selected Regional Restaurants Located Within New Orleans",
    color = "Business stars"
  ) +
  theme_minimal()

orleans_tracts <- tigris::tracts(
  state = "LA",
  county = "071",
  cb = TRUE,
  year = 2024,
  class = "sf"
) |>
  st_transform(st_crs(restaurant_points))

restaurants_by_tract <- restaurant_points |>
  st_join(
    orleans_tracts |>
      select(GEOID, tract_name = NAMELSAD),
    join = st_within,
    left = TRUE
  )

tract_summary <- restaurants_by_tract |>
  st_drop_geometry() |>
  group_by(tract_name) |>
  summarise(
    number_of_restaurants = n(),
    average_business_stars = mean(stars, na.rm = TRUE),
    median_business_stars = median(stars, na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(desc(number_of_restaurants))

tract_summary

tract_counts <- restaurants_by_tract |>
  st_drop_geometry() |>
  filter(!is.na(tract_name)) |>
  count(tract_name)

tract_comparison <- tibble(
  geographic_system = "Census tract",
  number_of_areas = n_distinct(tract_counts$tract_name),
  restaurants_assigned = sum(tract_counts$n),
  unmatched_restaurants = sum(
    is.na(restaurants_by_tract$tract_name)
  ),
  smallest_area_count = min(tract_counts$n),
  largest_area_count = max(tract_counts$n)
)

tract_comparison
print(tract_comparison, width = Inf)

zcta_all <- tigris::zctas(
  cb = TRUE,
  year = 2020,
  class = "sf"
) |>
  st_transform(st_crs(restaurant_points))

zcta_id_col <- names(zcta_all)[
  str_detect(names(zcta_all), "ZCTA5CE|GEOID")
][1]

zcta_boundaries <- zcta_all |>
  mutate(
    zcta_name = .data[[zcta_id_col]]
  )

new_orleans_boundary_zcta <- new_orleans_boundary |>
  st_transform(st_crs(zcta_boundaries))

zctas_near_new_orleans <- zcta_boundaries |>
  st_filter(new_orleans_boundary_zcta)

restaurants_by_zcta <- restaurant_points |>
  st_join(
    zcta_boundaries |>
      select(zcta_name),
    join = st_within,
    left = TRUE
  )

zcta_summary <- restaurants_by_zcta |>
  st_drop_geometry() |>
  filter(!is.na(zcta_name)) |>
  group_by(zcta_name) |>
  summarise(
    number_of_restaurants = n(),
    average_business_stars = mean(stars, na.rm = TRUE),
    median_business_stars = median(stars, na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(desc(number_of_restaurants))

zcta_summary

zcta_counts <- restaurants_by_zcta |>
  st_drop_geometry() |>
  filter(!is.na(zcta_name)) |>
  count(zcta_name)

zcta_comparison <- tibble(
  geographic_system = "ZIP/ZCTA",
  number_of_areas = n_distinct(zcta_counts$zcta_name),
  restaurants_assigned = sum(zcta_counts$n),
  unmatched_restaurants = sum(
    is.na(restaurants_by_zcta$zcta_name)
  ),
  smallest_area_count = min(zcta_counts$n),
  largest_area_count = max(zcta_counts$n)
)

print(zcta_comparison, width = Inf)

geography_comparison <- bind_rows(
  tract_comparison,
  zcta_comparison
)

print(geography_comparison, width = Inf)

tract_plot_data <- tract_summary |>
  filter(!is.na(tract_name)) |>
  slice_max(number_of_restaurants, n = 10)

ggplot(
  tract_plot_data,
  aes(
    x = reorder(tract_name, number_of_restaurants),
    y = number_of_restaurants
  )
) +
  geom_col(fill = "steelblue") +
  coord_flip() +
  labs(
    title = "Selected Restaurants in the Largest Census Tracts",
    x = "Census tract",
    y = "Number of restaurants"
  ) +
  theme_minimal()
zcta_plot_data <- zcta_summary |>
  slice_max(number_of_restaurants, n = 10)

ggplot(
  zcta_plot_data,
  aes(
    x = reorder(zcta_name, number_of_restaurants),
    y = number_of_restaurants
  )
) +
  geom_col(fill = "darkorange") +
  coord_flip() +
  labs(
    title = "Selected Restaurants in the Largest ZIP/ZCTAs",
    x = "ZIP/ZCTA",
    y = "Number of restaurants"
  ) +
  theme_minimal()