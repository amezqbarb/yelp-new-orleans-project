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

category_reviews <- new_orleans_reviews |>
  semi_join(
    selected_restaurants |>
      distinct(business_id),
    by = "business_id"
  ) |>
  mutate(
    review_datetime = ymd_hms(date, quiet = TRUE),
    review_date = as.Date(review_datetime),
    review_year = year(review_datetime)
  )

sum(is.na(category_reviews$review_datetime))

all_reviewer_summary <- category_reviews |>
  group_by(business_id) |>
  summarise(
    number_of_reviews_all_reviewers = n(),
    average_stars_all_reviewers = mean(stars, na.rm = TRUE),
    median_stars_all_reviewers = median(stars, na.rm = TRUE),
    .groups = "drop"
  )

all_reviewer_summary |>
  arrange(desc(average_stars_all_reviewers)) |>
  slice_head(n = 10)

reviewer_activity <- category_reviews |>
  count(
    user_id,
    name = "reviews_in_selected_categories"
  ) |>
  arrange(desc(reviews_in_selected_categories))

eligible_reviewers <- reviewer_activity |>
  filter(reviews_in_selected_categories >= 5)

selected_reviewer_reviews <- category_reviews |>
  semi_join(
    eligible_reviewers,
    by = "user_id"
  )

reviewer_coverage <- tibble(
  total_reviewers = n_distinct(category_reviews$user_id),
  eligible_reviewers = n_distinct(selected_reviewer_reviews$user_id),
  total_category_reviews = nrow(category_reviews),
  eligible_category_reviews = nrow(selected_reviewer_reviews),
  percent_reviews_from_eligible_reviewers =
    100 * nrow(selected_reviewer_reviews) / nrow(category_reviews)
)

reviewer_coverage

reviewer_baselines <- category_reviews |>
  group_by(user_id) |>
  summarise(
    reviewer_mean = mean(stars, na.rm = TRUE),
    reviewer_median = median(stars, na.rm = TRUE),
    reviewer_review_count = n(),
    .groups = "drop"
  )

category_reviews_adjusted <- category_reviews |>
  left_join(
    reviewer_baselines,
    by = "user_id"
  ) |>
  mutate(
    normalized_mean_score = stars - reviewer_mean,
    normalized_median_score = stars - reviewer_median
  )

eligible_adjusted_reviews <- category_reviews_adjusted |>
  semi_join(
    eligible_reviewers,
    by = "user_id"
  )
restaurant_summary <- selected_restaurants |>
  select(
    business_id,
    business_name
  ) |>
  distinct() |>
  left_join(
    all_reviewer_summary,
    by = "business_id"
  ) |>
  left_join(
    eligible_adjusted_reviews |>
      group_by(business_id) |>
      summarise(
        number_of_reviews_eligible_reviewers = n(),
        average_stars_eligible_reviewers =
          mean(stars, na.rm = TRUE),
        average_normalized_score =
          mean(normalized_mean_score, na.rm = TRUE),
        median_normalized_score =
          median(normalized_mean_score, na.rm = TRUE),
        .groups = "drop"
      ),
    by = "business_id"
  ) |>
  arrange(desc(average_normalized_score))

top_adjusted_restaurants <- restaurant_summary |>
  filter(
    number_of_reviews_eligible_reviewers >= 5
  ) |>
  slice_head(n = 10)

top_adjusted_restaurants

dir.create(
  "results",
  showWarnings = FALSE
)

write_csv(
  restaurant_summary,
  "results/restaurant_summary.csv"
)

write_csv(
  top_adjusted_restaurants,
  "results/top_adjusted_restaurants.csv"
)

write_csv(
  geography_comparison,
  "results/geography_comparison.csv"
)

rating_plot_data <- restaurant_summary |>
  filter(
    !is.na(average_stars_all_reviewers),
    !is.na(average_normalized_score)
  )

rating_comparison_plot <- ggplot(
  rating_plot_data,
  aes(
    x = average_stars_all_reviewers,
    y = average_normalized_score
  )
) +
  geom_hline(
    yintercept = 0,
    color = "grey70"
  ) +
  geom_point(
    aes(size = number_of_reviews_all_reviewers),
    alpha = 0.60
  ) +
  labs(
    title = "Raw Ratings Compared with Reviewer-Adjusted Scores",
    x = "Average stars from all reviewers",
    y = "Average normalized score",
    size = "Total reviews"
  ) +
  theme_minimal()

rating_comparison_plot

ggsave(
  "figures/raw_vs_adjusted_ratings.png",
  plot = rating_comparison_plot,
  width = 8,
  height = 6,
  dpi = 300
)

top10_map_data <- top_adjusted_restaurants |>
  left_join(
    selected_restaurants |>
      select(
        business_id,
        latitude,
        longitude
      ) |>
      distinct(),
    by = "business_id"
  )

top10_points <- top10_map_data |>
  filter(
    !is.na(latitude),
    !is.na(longitude)
  ) |>
  st_as_sf(
    coords = c("longitude", "latitude"),
    crs = 4326,
    remove = FALSE
  ) |>
  st_transform(st_crs(zcta_boundaries))

top10_zcta_names <- top10_points |>
  st_join(
    zcta_boundaries |>
      select(zcta_name),
    join = st_within,
    left = TRUE
  ) |>
  st_drop_geometry() |>
  distinct(zcta_name) |>
  filter(!is.na(zcta_name)) |>
  pull(zcta_name)

top10_zcta_boundaries <- zcta_boundaries |>
  filter(zcta_name %in% top10_zcta_names) |>
  st_transform(3857)

top10_points_map <- top10_points |>
  st_transform(3857)

new_orleans_boundary_map <- new_orleans_boundary |>
  st_transform(3857)

top10_map <- ggplot() +
  geom_sf(
    data = top10_zcta_boundaries,
    fill = NA,
    color = "grey55",
    linewidth = 0.6
  ) +
  geom_sf(
    data = new_orleans_boundary_map,
    fill = NA,
    color = "black",
    linewidth = 0.8
  ) +
  geom_sf(
    data = top10_points_map,
    aes(
      color = average_normalized_score,
      size = average_stars_all_reviewers
    ),
    alpha = 0.9
  ) +
  geom_sf_text(
    data = top10_points_map,
    aes(label = business_name),
    size = 2.8,
    check_overlap = TRUE
  ) +
  scale_color_viridis_c(option = "C") +
  labs(
    title = "Top 10 Regional Restaurants by ZIP/ZCTA",
    subtitle = "ZIP/ZCTA boundaries and the official New Orleans boundary",
    color = "Reviewer-adjusted score",
    size = "Average stars"
  ) +
  theme_minimal()

top10_map

ggsave(
  "figures/top_10_restaurants_map.png",
  plot = top10_map,
  width = 10,
  height = 8,
  dpi = 300
)

category_pairs <- restaurant_categories_long |>
  filter(category %in% selected_categories) |>
  distinct(business_id, category) |>
  inner_join(
    restaurant_categories_long |>
      filter(category %in% selected_categories) |>
      distinct(business_id, category),
    by = "business_id",
    relationship = "many-to-many"
  ) |>
  filter(category.x < category.y) |>
  count(
    category.x,
    category.y,
    name = "businesses_in_both_categories"
  )

category_pairs

write_csv(
  category_pairs,
  "results/category_pairs.csv"
)