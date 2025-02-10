# Tutorial for arcgis R package
# Created: 02/06/2025
# Source: https://developers.arcgis.com/r-bridge/get-started/

# Notes:
#  - Needs module rust for installation

install.packages("arcgis", repos = c("https://r-arcgis.r-universe.dev", "https://cloud.r-project.org"))
install.packages("usethis")

# Need to modify the environment file to point to the correct ArcGIS Host
usethis::edit_r_environ()

# Add the following to the .Renviron file:
# ARCGIS_HOST=https://bucas.maps.arcgis.com/

# Restart the R Session

# Need to store authentication credentials in .Renviron
# https://developers.arcgis.com/r-bridge/authentication/storing-credentials/

# Need to obtain Client ID
# https://developers.arcgis.com/r-bridge/authentication/connecting-to-a-portal/#obtaining-a-client-id

# Example Entry:
# 
# used for OAuth Code & Client
# ARCGIS_CLIENT=your-client-id
# used for OAuth Client flow
# ARCGIS_SECRET=your-super-secret-key
# used for publishing and Username/Password auth
# ARCGIS_USER=your-user-name
# used for API Key auth
# ARCGIS_API_KEY=your-developer-api-key
# specify if not using ArcGIS Online
# ARCGIS_HOST=https://your-portal.com/ 

# Running the package
library(arcgis)
token <- auth_client()

## READING IN FEATURE SERVICE

# Get the feature url from ArcGIS Online Atlas
# 1. Go to ArcGIS Online Atlas (https://livingatlas.arcgis.com/)
# 2. Search for "Massachusetts Census 2020 Redistricting Blocks"
# 3. Go to layer description and explore the data within Map Viewer.
# 4. Click the "view in ArcGIS Online" link to access the meta data for the server.
# 5. Find the attribute definition information for the layer
# 6. Copy the FeatureServer URL from the layer description.

furl <- "https://services.arcgis.com/P3ePLMYs2RVChkJx/arcgis/rest/services/Massachusetts_Census_2020_Redistricting_Blocks/FeatureServer"

# feature layer
# If layer is not shared, authentication via token is required.
# e.g flayer <- arc_open(furl, token=token)
feature_server <- arc_open(furl)
feature_server


# List items that are available
items <- list_items(feature_server)
items

# There is only one item available so let's specify that item by index id 0
fblock <- get_layer(feature_server, id=0)
fblock

fields <- list_fields(fblock)
fields$name

# Let's specify what fields we want to retrieve
sel_fields <- c("P0010001", "County_Name", "NAME")

# Let's fetch the attribute table only
result <- arc_select( fblock, 
                      fields = sel_fields, 
                      geometry = FALSE)

result

# Let's get a list of unique counties
unique(result$County_Name)


# Let's request for data within a specific county
# Select only fields of interest
result <- arc_select(
  fblock, 
  where = "County_Name = 'Berkshire County'",
  fields = sel_fields
)

# Check the class of the objectg to see it is an SF object.
class(result)

# Confirm the query worked
unique(result$County_Name)
# symbolize on a map the population data only
plot(result["P0010001"])

# Let's look at the summary stats
summary(result)

# Maybe we are interested in a dense population areas only

result <- arc_select(
  fblock, 
  where = "County_Name = 'Berkshire County' and P0010001 > 100",
  fields = sel_fields
)
plot(result["P0010001"])


## READING IN IMAGE SERVICE
# Go to an image service example
# example one: https://www.arcgis.com/home/item.html?id=d9b466d6a9e647ce8d1dd5fe12eb434b

# Get the URL for the image service

url <- "https://landsat2.arcgis.com/arcgis/rest/services/Landsat/MS/ImageServer"

imgsrv <- arc_open(url)
imgsrv


sample_image <- arc_raster(
  imgsrv,
  xmin = -12509225,
  ymin = 4278090,
  xmax = -12426979,
  ymax = 4349482
)
sample_image

# Check the class of the resulting object and we see it is a terra object
class(sample_image)

# Let's plot the image
terra::plotRGB(sample_image, stretch="lin")

## PUBLISHING LAYERS

# Let's read in an example file

nc <- sf::read_sf(system.file("shape/nc.shp", package = "sf"))
nc

plot(nc$geometry)

# We need to first create an access token
token <- auth_code() 
set_arc_token(token) 

# Now publish the layer
res <- publish_layer(nc, "North Carolina SIDS")
res

# Go to ArcGIS Online to view the layer.

# We can use the returned information to open the layer in R as well.
nc_fserver <- arc_open(res[[c("services", "encodedServiceURL")]])
nc_fserver

## Adding Feature to existing layer
https://developers.arcgis.com/r-bridge/editing/editing-add-features/

library(sf)
nc_sf <- read_sf(system.file("shape/nc.shp", package = "sf"))
nc_sf

# Create a summary
# "Let’s calculate the average birth rate, SIDS rate, 
# and the non-white birth rate and SIDS rate for the entire 
# state. We will add this as a single feature to our existing 
# feature layer."
library(dplyr)

nc_summary <- nc_sf |>  
  summarise(
    across( # <1>
      .cols = c(ends_with("74"), ends_with("79")), # <2>
      .fns = mean # <3>
    ),
    NAME = "Total" # Value for "NAME column.
  ) 

nc_summary
plot(nc_summary)

# Look at ArcGIS Online to see the existing number of features

# Get the host name of the layer
nc_layer <- get_layer(nc_fserver, id=0)
nc_layer

# Add the layer
add_res <- add_features(nc_layer, nc_summary)
add_res

nc_layer <- refresh_layer(nc_layer)

# Go to ArcGIS Online and check the new feature added.
# We can also check within R

nc <- arc_select(nc_layer)

nc_avgs <- nc |> 
  filter(NAME == "Total") |> 
  collect()

nc_avgs


## Updating features
# https://developers.arcgis.com/r-bridge/editing/update-features/

# Look at the ArcGIS Online layer and notice AREA and PERIMETER for the feature are not populated.
# May need to make Perimeter column visible within Portal

# Calculate those values.
nc_area_perim <- nc_avgs |> 
  mutate(
    AREA = st_area(geometry) / 1e10,
    PERIMETER = s2::s2_perimeter(geometry) / 1e5
  )

nc_area_perim

# Only select what we want to update
# Otherwise everything will be updated.
to_update <- nc_area_perim |> 
  st_drop_geometry() |> 
  select(object_id, AREA, PERIMETER)

to_update

# Apply the update
update_res <- update_features(nc_layer, to_update)

# Confirm update on ArcGIS Online

## Delete feature
# https://developers.arcgis.com/r-bridge/editing/editing-delete-features/

# First select what feature to delete by object_id
nc

# Then delete that feature using the object_id
delete_res <- delete_features(nc_layer, object_ids = 101)
delete_res





