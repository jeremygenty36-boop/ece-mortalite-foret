# ======================================================================
# SAFRAN — Lecture horaire + agregation journaliere
# Variables : precipitations (ForcPRCP) + temperature (ForcT)
# Source    : BD_SIG/climat/france/SAFRAN/0_donnees_brutes/
# Grille    : Lambert IIE 8 km x 8 km | 143 x 134 points
#
# Conventions SAFRAN :
#   - precip  : variable "product" en kg/m2/s  -> mm/h (x3600) -> mm/j (somme 24h)
#   - temp    : variable "product" en Kelvin    -> Celsius (-273.15)
#               Tmoy = moyenne 24h | Tmin = min 24h | Tmax = max 24h
#
# Etapes :
#   1. Ouverture NC + metadonnees
#   2. Lecture et nettoyage (FillValue -> NA)
#   3. Conversion des unites
#   4. Agregation journaliere
#   5. Extraction serie temporelle a un point
#   6. Visualisation cartes + series
#   7. Sauvegarde NC journalier
# ======================================================================

# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
if (!requireNamespace("ncdf4",   quietly = TRUE)) install.packages("ncdf4")
if (!requireNamespace("ggplot2", quietly = TRUE)) install.packages("ggplot2")
if (!requireNamespace("reshape2",quietly = TRUE)) install.packages("reshape2")
library(ncdf4)
library(ggplot2)
library(reshape2)

# --- Parametres -------------------------------------------------------
DIR_SAFRAN <- file.path(.PFX, "BD_SIG", "climat/france/SAFRAN/0_donnees_brutes")
F_PRCP_IN  <- file.path(DIR_SAFRAN, "ForcPRCP/ForcPRCP_france_SAFRAN_8Km_1hour_2014080100_2015073123_V1-3L_01.nc")
F_TEMP_IN  <- file.path(DIR_SAFRAN, "ForcT/ForcT_france_SAFRAN_8Km_1hour_2014080100_2015073123_V1-3L_01.nc")
DIR_OUT    <- file.path(PROJET, "3-Donnees/1-SAFRAN/1-2014_SAFRAN/")
F_NC_OUT   <- file.path(DIR_OUT, "SAFRAN_8Km_daily_2014_2015.nc")

# Periode d'interet pour visualisation / extraction point
DATE_DEB <- as.Date("2014-09-01")
DATE_FIN <- as.Date("2014-09-30")

# Point de reference (coordonnees WGS84)
LAT_PT <- 48.692   # Nancy
LON_PT <- 6.184

FILL_VAL <- 9.96920996838687e+36   # FillValue SAFRAN

# ======================================================================
# FONCTION UTILITAIRE : agregation horaire -> journalier
# ======================================================================
agreger_journalier <- function(arr_3d, dates_h, fun = "sum") {
  jours     <- unique(dates_h)
  n_x       <- dim(arr_3d)[1]
  n_y       <- dim(arr_3d)[2]
  out       <- array(NA_real_, dim = c(n_x, n_y, length(jours)))
  agg_fn    <- switch(fun,
                      sum  = function(x) sum(x,  na.rm = TRUE),
                      mean = function(x) mean(x, na.rm = TRUE),
                      min  = function(x) min(x,  na.rm = TRUE),
                      max  = function(x) max(x,  na.rm = TRUE))
  for (d in seq_along(jours)) {
    idx        <- which(dates_h == jours[d])
    out[,,d]   <- apply(arr_3d[,,idx, drop = FALSE], c(1, 2), agg_fn)
  }
  out
}

# ======================================================================
# 1. PRECIPITATIONS
# ======================================================================
cat("--- Precipitations ---\n")
cat("Ouverture :", basename(F_PRCP_IN), "\n")
nc    <- nc_open(F_PRCP_IN)
prcp  <- ncvar_get(nc, "product")   # kg/m2/s
lon   <- ncvar_get(nc, "lon")
lat   <- ncvar_get(nc, "lat")
x     <- ncvar_get(nc, "x")
y     <- ncvar_get(nc, "y")
time  <- ncvar_get(nc, "time")      # heures depuis 1900-01-01
nc_close(nc)
cat(sprintf("  Dimensions : %d x %d x %d\n", dim(prcp)[1], dim(prcp)[2], dim(prcp)[3]))

# Nettoyage + conversion kg/m2/s -> mm/h
prcp[prcp >= FILL_VAL * 0.9] <- NA
prcp_mm_h <- prcp * 3600

# Axe temporel
dates_h   <- as.Date(as.POSIXct("1900-01-01", tz = "UTC") + as.numeric(time) * 3600, tz = "UTC")
jours_uni <- unique(dates_h)
cat(sprintf("  Periode : %s -> %s (%d jours)\n", min(jours_uni), max(jours_uni), length(jours_uni)))

# Agregation journaliere (somme)
cat("  Agregation journaliere (somme 24h)...\n")
prcp_daily <- agreger_journalier(prcp_mm_h, dates_h, fun = "sum")
cat(sprintf("  -> %d jours traites\n", dim(prcp_daily)[3]))

# ======================================================================
# 2. TEMPERATURE
# ======================================================================
cat("\n--- Temperature ---\n")
cat("Ouverture :", basename(F_TEMP_IN), "\n")
nc   <- nc_open(F_TEMP_IN)
temp <- ncvar_get(nc, "product")   # Kelvin
nc_close(nc)
cat(sprintf("  Dimensions : %d x %d x %d\n", dim(temp)[1], dim(temp)[2], dim(temp)[3]))

# Nettoyage + conversion K -> C
temp[temp >= FILL_VAL * 0.9] <- NA
temp_c <- temp - 273.15

# Agregation journaliere
cat("  Agregation journaliere (mean / min / max)...\n")
tmoy_daily <- agreger_journalier(temp_c, dates_h, fun = "mean")
tmin_daily <- agreger_journalier(temp_c, dates_h, fun = "min")
tmax_daily <- agreger_journalier(temp_c, dates_h, fun = "max")
cat(sprintf("  -> %d jours traites\n", dim(tmoy_daily)[3]))

# ======================================================================
# 3. EXTRACTION SERIE TEMPORELLE AU POINT DE REFERENCE
# ======================================================================
cat("\n--- Extraction point de reference ---\n")
dist2 <- (lat - LAT_PT)^2 + (lon - LON_PT)^2
ij    <- which(dist2 == min(dist2), arr.ind = TRUE)
ix <- ij[1]; iy <- ij[2]
cat(sprintf("  Point : lat=%.3f lon=%.3f (maille [%d,%d])\n", lat[ix,iy], lon[ix,iy], ix, iy))

idx_per <- which(jours_uni >= DATE_DEB & jours_uni <= DATE_FIN)
dates_p <- jours_uni[idx_per]

df_pt <- data.frame(
  date     = dates_p,
  prcp     = prcp_daily [ix, iy, idx_per],
  tmoy     = tmoy_daily [ix, iy, idx_per],
  tmin     = tmin_daily [ix, iy, idx_per],
  tmax     = tmax_daily [ix, iy, idx_per]
)

cat(sprintf("  Cumul precip  : %.1f mm\n", sum(df_pt$prcp,  na.rm = TRUE)))
cat(sprintf("  Tmoy moyenne  : %.1f degC\n", mean(df_pt$tmoy, na.rm = TRUE)))
cat(sprintf("  Tmin absolue  : %.1f degC\n", min(df_pt$tmin,  na.rm = TRUE)))
cat(sprintf("  Tmax absolue  : %.1f degC\n", max(df_pt$tmax,  na.rm = TRUE)))

# ======================================================================
# 4. VISUALISATION — SERIES TEMPORELLES
# ======================================================================
# Precipitations
p_prcp <- ggplot(df_pt, aes(x = date, y = prcp)) +
  geom_col(fill = "steelblue") +
  labs(title = sprintf("SAFRAN — Precipitations journalieres\n(%.3fdegN / %.3fdegE)", LAT_PT, LON_PT),
       x = NULL, y = "Precipitation (mm/jour)") +
  theme_minimal()

# Temperatures
p_temp <- ggplot(df_pt, aes(x = date)) +
  geom_ribbon(aes(ymin = tmin, ymax = tmax), fill = "salmon", alpha = 0.4) +
  geom_line(aes(y = tmoy), colour = "red3", linewidth = 0.8) +
  labs(title = sprintf("SAFRAN — Temperatures journalieres\n(%.3fdegN / %.3fdegE) | rouge = Tmoy | ombre = Tmin-Tmax", LAT_PT, LON_PT),
       x = "Date", y = "Temperature (degC)") +
  theme_minimal()

print(p_prcp)
print(p_temp)

# ======================================================================
# 5. VISUALISATION — CARTES (premier jour periode d'interet)
# ======================================================================
jour_c <- idx_per[1]
n_x    <- dim(prcp_daily)[1]
n_y    <- dim(prcp_daily)[2]

# Helper : array 2D -> data.frame avec lon/lat
arr2df <- function(mat, lon2d, lat2d, nx) {
  df        <- melt(mat)
  colnames(df) <- c("xi", "yi", "val")
  df$lon    <- as.vector(lon2d)[df$xi + (df$yi - 1) * nx]
  df$lat    <- as.vector(lat2d)[df$xi + (df$yi - 1) * nx]
  df
}

df_prcp_c <- arr2df(prcp_daily[,,jour_c], lon, lat, n_x)
df_tmax_c <- arr2df(tmax_daily[,,jour_c], lon, lat, n_x)

p_carte_prcp <- ggplot(df_prcp_c, aes(x = lon, y = lat, fill = val)) +
  geom_raster() +
  scale_fill_gradient(low = "white", high = "steelblue", name = "mm/j", na.value = "grey90") +
  coord_fixed() +
  labs(title = paste("SAFRAN — Precip —", jours_uni[jour_c]), x = "Lon", y = "Lat") +
  theme_minimal()

p_carte_tmax <- ggplot(df_tmax_c, aes(x = lon, y = lat, fill = val)) +
  geom_raster() +
  scale_fill_gradient2(low = "steelblue", mid = "white", high = "red3",
                       midpoint = 15, name = "degC", na.value = "grey90") +
  coord_fixed() +
  labs(title = paste("SAFRAN — Tmax —", jours_uni[jour_c]), x = "Lon", y = "Lat") +
  theme_minimal()

print(p_carte_prcp)
print(p_carte_tmax)

# ======================================================================
# 6. SAUVEGARDE NC JOURNALIER
# ======================================================================
cat("\n--- Sauvegarde NC journalier ---\n")
dir.create(DIR_OUT, recursive = TRUE, showWarnings = FALSE)

time_j_num <- as.numeric(jours_uni - as.Date("1900-01-01"))

dim_x    <- ncdim_def("x",    "km",                  x)
dim_y    <- ncdim_def("y",    "km",                  y)
dim_time <- ncdim_def("time", "days since 1900-01-01", time_j_num, unlim = TRUE)

mk_var <- function(name, longname, units)
  ncvar_def(name, units, list(dim_x, dim_y, dim_time),
            missval = -9999, longname = longname, prec = "float")

var_prcp  <- mk_var("prcp",  "Daily precipitation (sum 24h)",       "mm/day")
var_tmoy  <- mk_var("tmoy",  "Daily mean temperature",              "degC")
var_tmin  <- mk_var("tmin",  "Daily minimum temperature",           "degC")
var_tmax  <- mk_var("tmax",  "Daily maximum temperature",           "degC")
var_lon   <- ncvar_def("lon", "degrees_east",  list(dim_x, dim_y), prec = "float")
var_lat   <- ncvar_def("lat", "degrees_north", list(dim_x, dim_y), prec = "float")

nc_out <- nc_create(F_NC_OUT, list(var_prcp, var_tmoy, var_tmin, var_tmax, var_lon, var_lat))
ncvar_put(nc_out, var_prcp,  prcp_daily)
ncvar_put(nc_out, var_tmoy,  tmoy_daily)
ncvar_put(nc_out, var_tmin,  tmin_daily)
ncvar_put(nc_out, var_tmax,  tmax_daily)
ncvar_put(nc_out, var_lon,   lon)
ncvar_put(nc_out, var_lat,   lat)
ncatt_put(nc_out, 0, "title",  "SAFRAN — agregation journaliere (precip + temperature)")
ncatt_put(nc_out, 0, "source", "ForcPRCP (kg/m2/s->mm/j) + ForcT (K->degC), SAFRAN 8km Lambert IIE")
nc_close(nc_out)

cat(sprintf("Sauvegarde : %s (%.1f MB)\n", basename(F_NC_OUT), file.size(F_NC_OUT) / 1e6))
cat("=== TERMINE ===\n")
