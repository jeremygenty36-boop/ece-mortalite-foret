# Comparaison m�t�o - SAFRAN / CHELSA / E-OBS / ERA5-Land / DIGITALIS ----
# Auteur : J�r�my Genty | Stage EvenementsExtremes | Mars 2026

# 0. FIX PROJ - OBLIGATOIREMENT EN PREMIER (avant tout library()) ----
Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"))
old_path <- Sys.getenv("PATH")
Sys.setenv(PATH = gsub("C:\\\\OSGeo4W64[^;]*;?", "", old_path))

# 1. PACKAGES ----
if (!requireNamespace("ecmwfr",   quietly = TRUE)) install.packages("ecmwfr")
if (!requireNamespace("cowplot",  quietly = TRUE)) install.packages("cowplot")
if (!requireNamespace("RColorBrewer", quietly = TRUE)) install.packages("RColorBrewer")
if (!requireNamespace("viridis", quietly = TRUE)) install.packages("viridis")
library(viridis)
library(raster)
library(terra)
library(ecmwfr)
library(data.table)
library(dplyr)
library(lubridate)
library(ggplot2)
library(sf)
library(RColorBrewer)
library(rnaturalearth)
library(rnaturalearthdata)
library(ggspatial)
library(patchwork)
library(scales)
library(cowplot)   # ??? n�cessaire pour get_legend()

# 2. PARAM�TRES GLOBAUX ----
ANNEE <- 2014

## Dossiers sources ----
dir_safran    <- "S:/Projets/stage_JeremyG/3-Donnees/1-SAFRAN/1-2014_SAFRAN"
dir_chelsa    <- "S:/Projets/stage_JeremyG/3-Donnees/2-CHELSA/1-2014_CHELSA_FR"
dir_eobs      <- "S:/Projets/stage_JeremyG/3-Donnees/3-E_OBS/1-2014_E_OBS"
dir_era5      <- "S:/Projets/stage_JeremyG/3-Donnees/4-ERA5/1-2014_ERA5"
dir_digitalis_v3    <- "S:/BD_SIG/climat/france/DIGITALIS_v3"                                  # tmin, tmax
dir_digitalis_v4    <- "S:/Projets/stage_JeremyG/3-Donnees/5-DIGITALIS/2-1960_2025_DIGITALIS_v4/1-prec_1960_2025"  # prec
dir_digitalis_daily <- "S:/Projets/stage_JeremyG/3-Donnees/5-DIGITALIS/3-DIGITALIS_daily/2014"
dir_out             <- "S:/Projets/stage_JeremyG/5-Resultats"


length(list.files(dir_digitalis_v4))
list.files(dir_digitalis_v4)
  
## Dossiers cache ----
dir_cache_safran    <- file.path(dir_safran,    "cache")
dir_cache_chelsa    <- file.path(dir_chelsa,    "cache")
dir_cache_eobs      <- file.path(dir_eobs,      "cache")
dir_cache_era5      <- file.path(dir_era5,      "cache")
dir_cache_digitalis <- "S:/Projets/stage_JeremyG/3-Donnees/5-DIGITALIS/2-1960_2025_DIGITALIS_v4/1-prec_1960_2025/cache"
## Param�tres ERA5 ----
emprise_france <- c(51.5, -5.5, 41.0, 10.0)
mois_noms      <- sprintf("%02d", 1:12)

# 3. CR�ATION DES DOSSIERS ----
for (d in c(dir_cache_safran, dir_cache_chelsa, dir_cache_eobs,
            dir_cache_era5, dir_cache_digitalis, dir_out)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# 4. FOND DE CARTE FRANCE + TH�ME CARTOGRAPHIQUE ----
france_wgs84 <- ne_countries(
  country = "France", scale = "medium", returnclass = "sf"
) %>%
  st_make_valid() %>%
  # D�coupe bbox France m�tropolitaine + Corse - exclut DOM-TOM
  st_crop(xmin = -5.5, ymin = 41.0, xmax = 10.0, ymax = 51.5)

france_l93        <- st_transform(france_wgs84, crs = 2154)
france_vect       <- vect(france_l93)
france_vect_wgs84 <- vect(france_wgs84)

theme_carto <- function() {
  list(
    geom_sf(data = france_l93, fill = NA, color = "grey30",
            linewidth = 0.4, inherit.aes = FALSE),
    coord_sf(crs  = 2154,
             xlim = c(80000, 1270000), ylim = c(6030000, 7160000),
             expand = FALSE),
    annotation_scale(location = "bl", dist = 200, dist_unit = "km",
                     text_cex = 0.9, bar_cols = c("grey20", "white"),
                     line_width = 0.5),
    annotation_north_arrow(
      location = "tl", which_north = "true",
      pad_x = unit(0.3, "cm"), pad_y = unit(0.3, "cm"),
      style = north_arrow_fancy_orienteering(
        fill = c("grey80", "grey20"),
        line_col = "grey20", text_col = "grey20", text_size = 12  # ??? +2
      )
    ),
    theme_void(base_size = 14),                                   # ??? 12 ??? 14
    theme(
      plot.title        = element_text(face = "bold", hjust = 0.5, size = 14),
      plot.subtitle     = element_text(hjust = 0.5, color = "grey40", size = 10),
      plot.caption      = element_text(hjust = 0.5, color = "grey20", size = 11,  # ??? 9 ??? 11
                                       face = "bold", margin = margin(t = 6)),
      legend.position   = "right",
      legend.title      = element_text(face = "bold", size = 12),   # ??? 9 ??? 12
      legend.text       = element_text(size = 10),                  # ??? ajout�
      legend.key.height = unit(0.8, "cm"),                          # ??? 0.6 ??? 0.8
      legend.key.width  = unit(0.5, "cm"),                          # ??? 0.4 ??? 0.5
      plot.margin       = margin(10, 10, 10, 10)
    )
  )
}


# 5. �CHELLES DE COULEURS ----
breaks_tmax   <- c(25, 27.5, 29, 30, 31, 32, 33, 34, 36, 39)
breaks_tmin   <- c(-15, -10, -5, -3, -2, -1, 0, 1, 3, 10)
breaks_precip <- c(400, 700, 800, 900, 1000, 1100, 1200, 1300, 1400,2000)

scale_tmax <- function() {
  scale_fill_fermenter(
    palette  = "YlOrRd", direction = 1,
    breaks   = breaks_tmax,
    limits   = c(min(breaks_tmax), max(breaks_tmax)),
    oob      = squish, name = "�C", na.value = "transparent"
  )
}

scale_tmin <- function() {
  scale_fill_fermenter(
    palette  = "RdYlBu", direction = -1,
    breaks   = breaks_tmin,
    limits   = c(min(breaks_tmin), max(breaks_tmin)),
    oob      = squish, name = "�C", na.value = "transparent"
  )
}

blues_custom <- c(
  "#dceefb",  # tr�s clair (400-700)
  "#bddff7",  # 700-900
  "#9cccf2",  # 900-1100
  "#77b7eb",  # 1100-1300
  "#519fe3",  # 1300-1500
  "#2c86d9",  # 1500-1800
  "#136dc7",  # 1800-2100
  "#0b51a3",  # 2100-2400
  "#063475",  # 2400-2700
  "#021a3c"   # 2700-3100 (extr�me sombre)
)

scale_precip <- function() {
  scale_fill_stepsn(
    colours  = blues_custom,
    breaks   = breaks_precip,
    limits   = c(400, 3100),
    oob      = squish,
    name     = "mm",
    na.value = "transparent",
    guide    = guide_colorsteps(
      barheight    = unit(18, "cm"),
      barwidth     = unit(0.8, "cm"),
      show.limits  = TRUE,
      ticks        = TRUE,
      ticks.colour = "grey30",
      frame.colour = "grey30",
      title.theme  = element_text(face = "bold", size = 15),
      label.theme  = element_text(size = 11)
    )
  )
}

scale_precip_panel <- scale_precip

# 6. FONCTIONS UTILITAIRES ----
calculer_ou_charger <- function(chemin_tif, fun_calcul) {
  if (file.exists(chemin_tif)) {
    cat("  [CACHE] Chargement :", basename(chemin_tif), "\n")
    return(rast(chemin_tif))
  }
  cat("  [CALCUL] Calcul en cours...\n")
  r <- fun_calcul()
  writeRaster(r, chemin_tif, overwrite = FALSE)
  cat("  [CACHE] Sauvegard� :", basename(chemin_tif), "\n")
  return(r)
}



# PARTIE I - TRAITEMENT DES DONN�ES ----

## II.1 SAFRAN ----
cat("\n[SAFRAN] Lecture du CSV 2014...\n")
chemin_cache_safran <- file.path(dir_cache_safran, "safran_fr_2014.rds")
if (file.exists(chemin_cache_safran)) {
  cat("  [CACHE] Chargement safran_fr\n")
  safran_fr <- readRDS(chemin_cache_safran)
} else {
  safran_an <- read.csv(file.path(dir_safran, "2014_SAFRAN_QUOT_SIM2"), as.is = TRUE)
  safran_an <- safran_an %>%
    mutate(
      TSUP_H_Q = as.numeric(as.character(TSUP_H_Q)),
      TINF_H_Q = as.numeric(as.character(TINF_H_Q)),
      PRELIQ_Q = as.numeric(as.character(PRELIQ_Q)),
      PRENEI_Q = as.numeric(as.character(PRENEI_Q))
    )
  safran_stats <- safran_an %>%
    mutate(PRECIP_J = PRELIQ_Q + PRENEI_Q) %>%
    group_by(LAMBX, LAMBY) %>%
    summarise(T_MAX = max(TSUP_H_Q, na.rm = TRUE),
              T_MIN = min(TINF_H_Q, na.rm = TRUE),
              PRECIP = sum(PRECIP_J, na.rm = TRUE), .groups = "drop")
  safran_sf    <- safran_stats %>%
    mutate(X_m = LAMBX * 100, Y_m = LAMBY * 100) %>%
    st_as_sf(coords = c("X_m", "Y_m"), crs = 27572)
  france_27572 <- st_transform(france_l93, crs = 27572)
  safran_fr <- st_intersection(safran_sf, france_27572) %>%
    st_transform(crs = 2154) %>%
    mutate(lon = st_coordinates(.)[, 1], lat = st_coordinates(.)[, 2]) %>%
    st_drop_geometry()
  saveRDS(safran_fr, chemin_cache_safran)
}
cat("Pixels SAFRAN :", nrow(safran_fr), "\n")
cat("T_MAX  :", round(min(safran_fr$T_MAX), 1), "???", round(max(safran_fr$T_MAX), 1), "�C\n")
cat("T_MIN  :", round(min(safran_fr$T_MIN), 1), "???", round(max(safran_fr$T_MIN), 1), "�C\n")
cat("PRECIP :", round(min(safran_fr$PRECIP)), "???", round(max(safran_fr$PRECIP)), "mm\n")


## II.2 CHELSA ----
cat("\n[CHELSA] Agr�gation des rasters journaliers...\n")

dir_chelsa       <- "S:/Projets/stage_JeremyG/3-Donnees/2-CHELSA/1-2014_et_2020_CHELSA_FR/1-2014_CHELSA_FR"
dir_cache_chelsa <- file.path(dir_chelsa, "cache")
if (!dir.exists(dir_cache_chelsa)) dir.create(dir_cache_chelsa, recursive = TRUE)

path_tmax   <- file.path(dir_cache_chelsa, "chelsa_tmax_2014.tif")
path_tmin   <- file.path(dir_cache_chelsa, "chelsa_tmin_2014.tif")
path_precip <- file.path(dir_cache_chelsa, "chelsa_precip_2014.tif")

agreger_chelsa <- function(variable, fun = c("max", "min", "sum")) {
  fun      <- match.arg(fun)
  dossier  <- file.path(dir_chelsa, variable)
  fichiers <- list.files(dossier, pattern = "\\.tif$", full.names = TRUE)
  n        <- length(fichiers)
  if (n == 0) stop("Aucun fichier .tif dans : ", dossier)
  cat("   ", variable, ":", n, "fichiers\n")
  r_res <- rast(fichiers[1])
  for (i in seq(2, n)) {
    if (i %% 60 == 0) cat("    ...", i, "/", n, "\n")
    r_j <- rast(fichiers[i])
    if      (fun == "max") r_res <- max(r_res, r_j, na.rm = TRUE)
    else if (fun == "min") r_res <- min(r_res, r_j, na.rm = TRUE)
    else { r_j[is.na(r_j)] <- 0; r_res <- r_res + r_j }
  }
  return(r_res)
}

# Vecteur France en WGS84 (CRS natif CHELSA) - calcul� une seule fois
fr_vect_wgs84 <- project(france_vect, "EPSG:4326")

# --- T_MAX -----------------------------------------------------------
if (!file.exists(path_tmax)) {
  cat("  [tasmax] Agr�gation...\n")
  r <- agreger_chelsa("tasmax", fun = "max")
  cat("  [tasmax] Clip France...\n")
  r <- crop(r, fr_vect_wgs84) |> mask(fr_vect_wgs84)
  r <- r - 273.15          # Kelvin ??? Celsius
  writeRaster(r, path_tmax, overwrite = TRUE)
  cat("  [tasmax] Cache �crit.\n")
}
r_tmax <- rast(path_tmax)

# --- T_MIN -----------------------------------------------------------
if (!file.exists(path_tmin)) {
  cat("  [tasmin] Agr�gation...\n")
  r <- agreger_chelsa("tasmin", fun = "min")
  cat("  [tasmin] Clip France...\n")
  r <- crop(r, fr_vect_wgs84) |> mask(fr_vect_wgs84)
  r <- r - 273.15          # Kelvin ??? Celsius
  writeRaster(r, path_tmin, overwrite = TRUE)
  cat("  [tasmin] Cache �crit.\n")
}
r_tmin <- rast(path_tmin)

# --- PRECIP ----------------------------------------------------------
if (!file.exists(path_precip)) {
  cat("  [pr] Agr�gation...\n")
  r <- agreger_chelsa("pr", fun = "sum")
  cat("  [pr] Clip France...\n")
  r <- crop(r, fr_vect_wgs84) |> mask(fr_vect_wgs84)
  # kg m-2 day-1 = mm/jour ??? somme annuelle d�j� en mm, pas de conversion
  writeRaster(r, path_precip, overwrite = TRUE)
  cat("  [pr] Cache �crit.\n")
}
r_precip <- rast(path_precip)

# --- Harmonisation des extents sur une grille commune ----------------
# r_tmax sert de r�f�rence
r_tmin   <- resample(r_tmin,   r_tmax, method = "bilinear")
r_precip <- resample(r_precip, r_tmax, method = "near")
# "near" pour pr�cip car c'est une somme (�vite interpolation des bords)

# --- Stack + reprojection L93 ----------------------------------------
chelsa_stack     <- c(r_tmax, r_tmin, r_precip)
names(chelsa_stack) <- c("T_MAX", "T_MIN", "PRECIP")
chelsa_stack_l93 <- project(chelsa_stack, "EPSG:2154", method = "bilinear")

# Filtre sur les 3 variables (pas seulement T_MAX)
chelsa_fr <- as.data.frame(chelsa_stack_l93, xy = TRUE) %>%
  rename(lon = x, lat = y) %>%
  filter(!is.na(T_MAX), !is.na(T_MIN), !is.na(PRECIP))

# na.rm = TRUE dans les diagnostics (s�curit�)
cat("Pixels CHELSA :", nrow(chelsa_fr), "\n")
cat("T_MAX  :", round(min(chelsa_fr$T_MAX,  na.rm = TRUE), 1), "-", round(max(chelsa_fr$T_MAX,  na.rm = TRUE), 1), "�C\n")
cat("T_MIN  :", round(min(chelsa_fr$T_MIN,  na.rm = TRUE), 1), "-", round(max(chelsa_fr$T_MIN,  na.rm = TRUE), 1), "�C\n")
cat("PRECIP :", round(min(chelsa_fr$PRECIP, na.rm = TRUE)),     "-", round(max(chelsa_fr$PRECIP, na.rm = TRUE)),     "mm\n")


## II.3 E-OBS ----
cat("\n[E-OBS] Lecture des fichiers NetCDF...\n")
lire_filtrer_eobs <- function(fichier, annee) {
  r   <- rast(fichier)
  idx <- which(year(time(r)) == annee)
  cat("  ", basename(fichier), ":", nlyr(r), "couches |", length(idx), "pour", annee, "\n")
  return(r[[idx]])
}

eobs_tmax_r <- calculer_ou_charger(
  file.path(dir_cache_eobs, "eobs_tmax_2014.tif"), function() {
    r <- lire_filtrer_eobs(file.path(dir_eobs, "tx_ens_mean_0.1deg_reg_2011-2021_v25.0e.nc"), ANNEE)
    mask(crop(app(r, fun = max, na.rm = TRUE), france_vect_wgs84), france_vect_wgs84)
  })
eobs_tmin_r <- calculer_ou_charger(
  file.path(dir_cache_eobs, "eobs_tmin_2014.tif"), function() {
    r <- lire_filtrer_eobs(file.path(dir_eobs, "tn_ens_mean_0.1deg_reg_2011-2021_v25.0e.nc"), ANNEE)
    mask(crop(app(r, fun = min, na.rm = TRUE), france_vect_wgs84), france_vect_wgs84)
  })
eobs_precip_r <- calculer_ou_charger(
  file.path(dir_cache_eobs, "eobs_precip_2014.tif"), function() {
    r <- lire_filtrer_eobs(file.path(dir_eobs, "rr_ens_mean_0.1deg_reg_2011-2021_v25.0e.nc"), ANNEE)
    mask(crop(app(r, fun = sum, na.rm = TRUE), france_vect_wgs84), france_vect_wgs84)
  })

chemin_cache_eobs_fr <- file.path(dir_cache_eobs, "eobs_fr_2014.rds")
if (file.exists(chemin_cache_eobs_fr)) {
  cat("  [CACHE] Chargement eobs_fr\n")
  eobs_fr <- readRDS(chemin_cache_eobs_fr)
} else {
  eobs_stack        <- c(eobs_tmax_r, eobs_tmin_r, eobs_precip_r)
  names(eobs_stack) <- c("T_MAX", "T_MIN", "PRECIP")
  eobs_stack_l93    <- project(eobs_stack, "EPSG:2154", method = "bilinear")
  eobs_fr <- as.data.frame(eobs_stack_l93, xy = TRUE) %>%
    rename(lon = x, lat = y) %>% filter(!is.na(T_MAX))
  saveRDS(eobs_fr, chemin_cache_eobs_fr)
}
cat("Pixels E-OBS :", nrow(eobs_fr), "\n")
cat("T_MAX  :", round(min(eobs_fr$T_MAX), 1), "???", round(max(eobs_fr$T_MAX), 1), "�C\n")
cat("T_MIN  :", round(min(eobs_fr$T_MIN), 1), "???", round(max(eobs_fr$T_MIN), 1), "�C\n")
cat("PRECIP :", round(min(eobs_fr$PRECIP)), "???", round(max(eobs_fr$PRECIP)), "mm\n")

## II.4 ERA5-Land ----
cat("\n[ERA5] Calcul des indicateurs annuels...\n")
era5_tmax_r <- calculer_ou_charger(
  file.path(dir_cache_era5, "era5_tmax_2014.tif"), function() {
    f <- list.files(dir_era5, pattern = "era5_tmax_2014_.*\\.nc$", full.names = TRUE)
    app(rast(f), fun = max, na.rm = TRUE) - 273.15
  })
era5_tmin_r <- calculer_ou_charger(
  file.path(dir_cache_era5, "era5_tmin_2014.tif"), function() {
    f <- list.files(dir_era5, pattern = "era5_tmin_2014_.*\\.nc$", full.names = TRUE)
    app(rast(f), fun = min, na.rm = TRUE) - 273.15
  })
era5_precip_r <- calculer_ou_charger(
  file.path(dir_cache_era5, "era5_precip_2014.tif"), function() {
    f <- list.files(dir_era5, pattern = "era5_pr_2014_.*\\.nc$", full.names = TRUE)
    era5_precip_h <- rast(f)
    vals  <- values(era5_precip_h)
    n_h   <- ncol(vals)
    incr  <- matrix(0, nrow = nrow(vals), ncol = n_h)
    incr[, 1] <- pmax(vals[, 1], 0)
    for (h in seq(2, n_h)) {
      diff_h    <- vals[, h] - vals[, h - 1]
      incr[, h] <- ifelse(diff_h < 0, vals[, h], diff_h)
    }
    era5_precip_incr         <- era5_precip_h
    values(era5_precip_incr) <- incr
    rm(vals, incr, era5_precip_h)
    dates_h <- as.Date(seq(as.POSIXct("2014-01-01 00:00:00", tz = "UTC"),
                           by = "hour", length.out = nlyr(era5_precip_incr)))
    era5_precip_j <- tapp(era5_precip_incr, index = dates_h, fun = sum, na.rm = TRUE)
    rm(era5_precip_incr)
    app(era5_precip_j, fun = sum, na.rm = TRUE) * 1000
  })

chemin_cache_era5_fr <- file.path(dir_cache_era5, "era5_fr_2014.rds")
if (file.exists(chemin_cache_era5_fr)) {
  cat("  [CACHE] Chargement era5_fr\n")
  era5_fr <- readRDS(chemin_cache_era5_fr)
} else {
  era5_tmax_fr   <- mask(crop(era5_tmax_r,   france_vect_wgs84), france_vect_wgs84)
  era5_tmin_fr   <- mask(crop(era5_tmin_r,   france_vect_wgs84), france_vect_wgs84)
  era5_precip_fr <- mask(crop(era5_precip_r, france_vect_wgs84), france_vect_wgs84)
  era5_stack        <- c(era5_tmax_fr, era5_tmin_fr, era5_precip_fr)
  names(era5_stack) <- c("T_MAX", "T_MIN", "PRECIP")
  era5_stack_l93    <- project(era5_stack, "EPSG:2154", res = 9000, method = "bilinear")
  era5_fr <- as.data.frame(era5_stack_l93, xy = TRUE) %>%
    rename(lon = x, lat = y) %>% filter(!is.na(T_MAX))
  saveRDS(era5_fr, chemin_cache_era5_fr)
}
cat("Pixels ERA5 :", nrow(era5_fr), "\n")
cat("T_MAX  :", round(min(era5_fr$T_MAX), 1), "???", round(max(era5_fr$T_MAX), 1), "�C\n")
cat("T_MIN  :", round(min(era5_fr$T_MIN), 1), "???", round(max(era5_fr$T_MIN), 1), "�C\n")
cat("PRECIP :", round(min(era5_fr$PRECIP)), "???", round(max(era5_fr$PRECIP)), "mm\n")

## II.5 DIGITALIS v3 - tmin / tmax ----
cat("\n[DIGITALIS v3] Lecture tmax 2014...\n")

digitalis_tmax_r <- calculer_ou_charger(
  file.path(dir_cache_digitalis, "digitalis_v3_tmax_2014.tif"),
  function() {
    chemin <- file.path(dir_digitalis_v3, "tmax", "tmax_2014_13.tif")
    if (!file.exists(chemin)) stop("Fichier introuvable : ", chemin)
    cat("  tmax : chargement indicateur annuel (mois 13)\n")
    rast(chemin)
  }
)

cat("\n[DIGITALIS v3] Lecture tmin 2014...\n")

digitalis_tmin_r <- calculer_ou_charger(
  file.path(dir_cache_digitalis, "digitalis_v3_tmin_2014.tif"),
  function() {
    chemin <- file.path(dir_digitalis_v3, "tmin", "tmin_2014_13.tif")
    if (!file.exists(chemin)) stop("Fichier introuvable : ", chemin)
    cat("  tmin : chargement indicateur annuel (mois 13)\n")
    rast(chemin)
  }
)

## II.6 DIGITALIS v4 - pr�cipitations uniquement ----
cat("\n[DIGITALIS v4] Lecture pr�cipitations 2014...\n")

digitalis_precip_r <- calculer_ou_charger(
  file.path(dir_cache_digitalis, "digitalis_v4_prec_2014.tif"),
  function() {
    chemin <- file.path(dir_digitalis_v4, "prec_2014_13.tif")
    if (!file.exists(chemin)) stop("Fichier introuvable : ", chemin)
    cat("  Pr�cip : chargement indicateur annuel (mois 13)\n")
    rast(chemin) / 10   # DIGITALIS encode en dixi�mes de mm ??? conversion en mm
  }
)

chemin_cache_digitalis_fr <- file.path(dir_cache_digitalis, "digitalis_v4_fr_2014.rds")
if (file.exists(chemin_cache_digitalis_fr)) {
  cat("  [CACHE] Chargement digitalis_fr\n")
  digitalis_fr <- readRDS(chemin_cache_digitalis_fr)
} else {
  cat("  [CALCUL] Reprojection Lambert 93 DIGITALIS v4...\n")
  precip_l93   <- project(digitalis_precip_r, "EPSG:2154", method = "bilinear")
  precip_fr    <- mask(crop(precip_l93, france_vect), france_vect)
  digitalis_fr <- as.data.frame(precip_fr, xy = TRUE) %>%
    rename(lon = x, lat = y, PRECIP = 3) %>%
    filter(!is.na(PRECIP))
  saveRDS(digitalis_fr, chemin_cache_digitalis_fr)
  cat("  [CACHE] Sauvegard� :", chemin_cache_digitalis_fr, "\n")
}
cat("PRECIP DIGITALIS v4 :", round(min(digitalis_fr$PRECIP)), "???",
    round(max(digitalis_fr$PRECIP)), "mm\n")

## II.7 DIGITALIS Daily - pr�cipitations uniquement ----
cat("\n[DIGITALIS Daily] Lecture pr�cipitations 2014...\n")
digitalis_daily_precip_r <- calculer_ou_charger(
  file.path(dir_cache_digitalis, "digitalis_daily_prec_2014.tif"),
  function() {
    fichiers <- list.files(dir_digitalis_daily, pattern = "^prec_DS_2014.*\\.tif$", full.names = TRUE)
    n <- length(fichiers)
    if (n == 0) stop("Aucun fichier .tif dans : ", dir_digitalis_daily)
    cat("  Pr�cip : agr�gation de", n, "fichiers journaliers...\n")
    r_sum <- rast(fichiers[1])
    for (i in seq(2, n)) {
      if (i %% 50 == 0) cat("    ...", i, "/", n, "\n")
      r_sum <- r_sum + rast(fichiers[i])
    }
    r_sum
  }
)

digitalis_daily_precip_r <- calculer_ou_charger(
  file.path(dir_cache_digitalis, "digitalis_daily_prec_2014.tif"),
  function() {
    fichiers <- list.files(dir_digitalis_daily, pattern = "^prec_DS_2014.*\\.tif$", full.names = TRUE)
    n <- length(fichiers)
    if (n == 0) stop("Aucun fichier .tif dans : ", dir_digitalis_daily)
    cat("  Pr�cip : agr�gation de", n, "fichiers journaliers...\n")
    r_sum <- rast(fichiers[1])
    for (i in seq(2, n)) {
      if (i %% 50 == 0) cat("    ...", i, "/", n, "\n")
      r_sum <- r_sum + rast(fichiers[i])
    }
    r_sum
  }
) 


chemin_cache_digitalis_daily_fr <- file.path(dir_cache_digitalis, "digitalis_daily_fr_2014.rds")
if (file.exists(chemin_cache_digitalis_daily_fr)) {
  cat("  [CACHE] Chargement digitalis_daily_fr\n")
  digitalis_daily_fr <- readRDS(chemin_cache_digitalis_daily_fr)
} else {
  cat("  [CALCUL] Reprojection Lambert 93 DIGITALIS Daily...\n")
  precip_l93         <- project(digitalis_daily_precip_r, "EPSG:2154", method = "bilinear")
  precip_fr          <- mask(crop(precip_l93, france_vect), france_vect)
  digitalis_daily_fr <- as.data.frame(precip_fr, xy = TRUE) %>%
    rename(lon = x, lat = y, PRECIP = 3) %>%
    filter(!is.na(PRECIP))
  saveRDS(digitalis_daily_fr, chemin_cache_digitalis_daily_fr)
  cat("  [CACHE] Sauvegard� :", chemin_cache_digitalis_daily_fr, "\n")
}

cat("PRECIP DIGITALIS Daily :", round(min(digitalis_daily_fr$PRECIP)), "???",
    round(max(digitalis_daily_fr$PRECIP)), "mm\n")                         # ??? corrig�




# PARTIE III - CARTOGRAPHIE ----
cat("\n[CARTES] Cr�ation des cartes...\n")

## III.1 SAFRAN ----
p_tmax_safran <- ggplot(safran_fr) +
  geom_tile(aes(x = lon, y = lat, fill = T_MAX), width = 8000, height = 8000) +
  scale_tmax() + theme_carto() +
  labs(title    = "Temp�rature maximale annuelle - 2014",
       subtitle = "SAFRAN | France m�tropolitaine | ~8 km",
       caption  = "J�r�my Genty | Source : M�t�o-France SAFRAN")

p_tmin_safran <- ggplot(safran_fr) +
  geom_tile(aes(x = lon, y = lat, fill = T_MIN), width = 8000, height = 8000) +
  scale_tmin() + theme_carto() +
  labs(title    = "Temp�rature minimale annuelle - 2014",
       subtitle = "SAFRAN | France m�tropolitaine | ~8 km",
       caption  = "J�r�my Genty | Source : M�t�o-France SAFRAN")

p_precip_safran <- ggplot(safran_fr) +
  geom_tile(aes(x = lon, y = lat, fill = PRECIP), width = 8000, height = 8000) +
  scale_precip() + theme_carto() +
  labs(title    = "Cumul annuel des pr�cipitations - 2014",
       subtitle = "SAFRAN | France m�tropolitaine | ~8 km",
       caption  = "J�r�my Genty | Source : M�t�o-France SAFRAN")

## III.2 CHELSA ----
p_tmax_chelsa <- ggplot(chelsa_fr) +
  geom_raster(aes(x = lon, y = lat, fill = T_MAX)) +
  scale_tmax() + theme_carto() +
  labs(title    = "Temp�rature maximale annuelle - 2014",
       subtitle = "CHELSA Daily V2.1 | France m�tropolitaine | ~1 km",
       caption  = "J�r�my Genty | Source : CHELSA / WSL")

p_tmin_chelsa <- ggplot(chelsa_fr) +
  geom_raster(aes(x = lon, y = lat, fill = T_MIN)) +
  scale_tmin() + theme_carto() +
  labs(title    = "Temp�rature minimale annuelle - 2014",
       subtitle = "CHELSA Daily V2.1 | France m�tropolitaine | ~1 km",
       caption  = "J�r�my Genty | Source : CHELSA / WSL")

p_precip_chelsa <- ggplot(chelsa_fr) +
  geom_raster(aes(x = lon, y = lat, fill = PRECIP)) +
  scale_precip() + theme_carto() +
  labs(title    = "Cumul annuel des pr�cipitations - 2014",
       subtitle = "CHELSA Daily V2.1 | France m�tropolitaine | ~1 km",
       caption  = "J�r�my Genty | Source : CHELSA / WSL")

## III.3 E-OBS ----
p_tmax_eobs <- ggplot(eobs_fr) +
  geom_tile(aes(x = lon, y = lat, fill = T_MAX), width = 11000, height = 11000) +
  scale_tmax() + theme_carto() +
  labs(title    = "Temp�rature maximale annuelle - 2014",
       subtitle = "E-OBS v25.0e | France m�tropolitaine | ~11 km (0.1�)",
       caption  = "J�r�my Genty | Source : Copernicus / ECAD")

p_tmin_eobs <- ggplot(eobs_fr) +
  geom_tile(aes(x = lon, y = lat, fill = T_MIN), width = 11000, height = 11000) +
  scale_tmin() + theme_carto() +
  labs(title    = "Temp�rature minimale annuelle - 2014",
       subtitle = "E-OBS v25.0e | France m�tropolitaine | ~11 km (0.1�)",
       caption  = "J�r�my Genty | Source : Copernicus / ECAD")

p_precip_eobs <- ggplot(eobs_fr) +
  geom_tile(aes(x = lon, y = lat, fill = PRECIP), width = 11000, height = 11000) +
  scale_precip() + theme_carto() +
  labs(title    = "Cumul annuel des pr�cipitations - 2014",
       subtitle = "E-OBS v25.0e | France m�tropolitaine | ~11 km (0.1�)",
       caption  = "J�r�my Genty | Source : Copernicus / ECAD")

## III.4 ERA5-Land ----
p_tmax_era5 <- ggplot(era5_fr) +
  geom_tile(aes(x = lon, y = lat, fill = T_MAX), width = 9000, height = 9000) +
  scale_tmax() + theme_carto() +
  labs(title    = "Temp�rature maximale annuelle - 2014",
       subtitle = "ERA5-Land | France m�tropolitaine | ~9 km",
       caption  = "J�r�my Genty | Source : ERA5-Land / ECMWF")

p_tmin_era5 <- ggplot(era5_fr) +
  geom_tile(aes(x = lon, y = lat, fill = T_MIN), width = 9000, height = 9000) +
  scale_tmin() + theme_carto() +
  labs(title    = "Temp�rature minimale annuelle - 2014",
       subtitle = "ERA5-Land | France m�tropolitaine | ~9 km",
       caption  = "J�r�my Genty | Source : ERA5-Land / ECMWF")

p_precip_era5 <- ggplot(era5_fr) +
  geom_tile(aes(x = lon, y = lat, fill = PRECIP), width = 9000, height = 9000) +
  scale_precip() + theme_carto() +
  labs(title    = "Cumul annuel des pr�cipitations - 2014",
       subtitle = "ERA5-Land | France m�tropolitaine | ~9 km",
       caption  = "J�r�my Genty | Source : ERA5-Land / ECMWF")

## III.5 DIGITALIS v4 - pr�cipitations ----
p_precip_digitalis <- ggplot(digitalis_fr) +
  geom_raster(aes(x = lon, y = lat, fill = PRECIP)) +
  scale_precip() + theme_carto() +
  labs(title    = "Cumul annuel des pr�cipitations - 2014",
       subtitle = "DIGITALIS v4 | France m�tropolitaine | ~1 km",
       caption  = "J�r�my Genty | Source : DIGITALIS v4")

## III.6 DIGITALIS Daily - pr�cipitations ----
p_precip_digitalis_daily <- ggplot(digitalis_daily_fr) +
  geom_raster(aes(x = lon, y = lat, fill = PRECIP)) +
  scale_precip() + theme_carto() +
  labs(title    = "Cumul annuel des pr�cipitations - 2014",
       subtitle = "DIGITALIS Daily | France m�tropolitaine | ~1 km",
       caption  = "J�r�my Genty | Source : DIGITALIS Daily")

## III.7 DIGITALIS Daily - tmax / tmin (� activer quand donn�es disponibles) ----
# p_tmax_digitalis_daily <- ggplot(digitalis_daily_fr) +
#   geom_raster(aes(x = lon, y = lat, fill = T_MAX)) +
#   scale_tmax() + theme_carto() +
#   labs(title    = "Temp�rature maximale annuelle - 2014",
#        subtitle = "DIGITALIS Daily | France m�tropolitaine | ~1 km",
#        caption  = "J�r�my Genty | Source : DIGITALIS Daily")
#
# p_tmin_digitalis_daily <- ggplot(digitalis_daily_fr) +
#   geom_raster(aes(x = lon, y = lat, fill = T_MIN)) +
#   scale_tmin() + theme_carto() +
#   labs(title    = "Temp�rature minimale annuelle - 2014",
#        subtitle = "DIGITALIS Daily | France m�tropolitaine | ~1 km",
#        caption  = "J�r�my Genty | Source : DIGITALIS Daily")

# PARTIE IV - EXPORT PDF ----

## IV.1 PDF individuels ----
cat("\n[EXPORT] PDF individuels...\n")
cartes_indiv <- list(
  # SAFRAN
  list(p = p_tmax_safran,             f = "2014_tmax_SAFRAN.pdf",             w = 6, h = 7),
  list(p = p_tmin_safran,             f = "2014_tmin_SAFRAN.pdf",             w = 6, h = 7),
  list(p = p_precip_safran,           f = "2014_precip_SAFRAN.pdf",           w = 6, h = 7),
  # CHELSA
  list(p = p_tmax_chelsa,             f = "2014_tmax_CHELSA.pdf",             w = 6, h = 7),
  list(p = p_tmin_chelsa,             f = "2014_tmin_CHELSA.pdf",             w = 6, h = 7),
  list(p = p_precip_chelsa,           f = "2014_precip_CHELSA.pdf",           w = 6, h = 7),
  # E-OBS
  list(p = p_tmax_eobs,               f = "2014_tmax_EOBS.pdf",               w = 6, h = 7),
  list(p = p_tmin_eobs,               f = "2014_tmin_EOBS.pdf",               w = 6, h = 7),
  list(p = p_precip_eobs,             f = "2014_precip_EOBS.pdf",             w = 6, h = 7),
  # ERA5-Land
  list(p = p_tmax_era5,               f = "2014_tmax_ERA5.pdf",               w = 6, h = 7),
  list(p = p_tmin_era5,               f = "2014_tmin_ERA5.pdf",               w = 6, h = 7),
  list(p = p_precip_era5,             f = "2014_precip_ERA5.pdf",             w = 6, h = 7),
  # DIGITALIS v4
  list(p = p_precip_digitalis,        f = "2014_precip_DIGITALIS_v4.pdf",     w = 6, h = 7),
  # DIGITALIS Daily
  list(p = p_precip_digitalis_daily,  f = "2014_precip_DIGITALIS_daily.pdf",  w = 6, h = 7)
  # D�commenter quand tmax/tmin DIGITALIS Daily disponibles :
  # list(p = p_tmax_digitalis_daily,  f = "2014_tmax_DIGITALIS_daily.pdf",    w = 6, h = 7),
  # list(p = p_tmin_digitalis_daily,  f = "2014_tmin_DIGITALIS_daily.pdf",    w = 6, h = 7)
)

for (carte in cartes_indiv) {
  ggsave(file.path(dir_out, carte$f), carte$p,
         width = carte$w, height = carte$h, dpi = 200, bg = "white")
  cat("  ???", carte$f, "\n")
}

## IV.2 Panneaux comparatifs ----

# Titre global
annotation_commune <- function(titre, sous_titre) {
  plot_annotation(
    title    = titre,
    subtitle = sous_titre,
    caption  = paste0("J�r�my Genty - Stage EvenementsExtremes | ",
                      "France m�tropolitaine - ", ANNEE,
                      " | Lambert 93 (EPSG:2154)"),
    theme = theme(
      plot.title    = element_text(face = "bold", hjust = 0.5, size = 18),
      plot.subtitle = element_text(hjust = 0.5, color = "grey40", size = 13),
      plot.caption  = element_text(hjust = 1,   color = "grey60", size = 10)
    )
  )
}

# Utilitaires
sans_leg       <- function(p) p + theme(legend.position = "none")
sans_leg_titre <- function(p) p + theme(legend.position = "none") +
  labs(title = NULL, subtitle = NULL)
espace_vide    <- wrap_elements(grid::nullGrob())

# ?????? Extraction l�gendes ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

leg_tmax <- cowplot::get_legend(
  p_tmax_safran +
    theme(legend.position   = "right",
          legend.key.height = unit(1.8, "cm"),
          legend.key.width  = unit(0.7, "cm"),
          legend.title      = element_text(face = "bold", size = 15),
          legend.text       = element_text(size = 13))
)

leg_tmin <- cowplot::get_legend(
  p_tmin_safran +
    theme(legend.position   = "right",
          legend.key.height = unit(1.8, "cm"),
          legend.key.width  = unit(0.7, "cm"),
          legend.title      = element_text(face = "bold", size = 15),
          legend.text       = element_text(size = 13))
)

scale_precip_panel <- function() {
  scale_fill_stepsn(
    colours  = blues_custom,
    breaks   = breaks_precip,
    limits   = c(min(breaks_precip), max(breaks_precip)),
    oob      = squish,
    name     = "mm",
    na.value = "transparent",
    guide    = guide_colorsteps(
      barheight    = unit(18, "cm"),
      barwidth     = unit(0.8, "cm"),
      show.limits  = TRUE,
      ticks        = TRUE,
      ticks.colour = "grey30",
      frame.colour = "grey30",
      title.theme  = element_text(face = "bold", size = 15),
      label.theme  = element_text(size = 11)
    )
  )
}

# Reconstruction cartes pr�cip avec scale_precip_panel
p_precip_safran_p         <- p_precip_safran         + scale_precip_panel()
p_precip_chelsa_p         <- p_precip_chelsa         + scale_precip_panel()
p_precip_eobs_p           <- p_precip_eobs           + scale_precip_panel()
p_precip_era5_p           <- p_precip_era5           + scale_precip_panel()
p_precip_digitalis_p      <- p_precip_digitalis      + scale_precip_panel()
p_precip_digitalis_daily_p <- p_precip_digitalis_daily + scale_precip_panel()

leg_precip <- cowplot::get_legend(
  p_precip_safran_p +
    theme(legend.position   = "right",
          legend.key.height = unit(1.0, "cm"),
          legend.key.width  = unit(0.7, "cm"),
          legend.title      = element_text(face = "bold", size = 15),
          legend.text       = element_text(size = 11))
)

# ?????? Panneau Tmax - 2�2, l�gende BAS DROITE ??????????????????????????????????????????????????????????????????????????????????????????????????????
# Layout : [grille 2�2] | [vide / l�gende]
# La l�gende se retrouve dans la cellule bas-droite

grille_tmax <- (
  sans_leg_titre(p_tmax_safran) + sans_leg_titre(p_tmax_chelsa) +
    sans_leg_titre(p_tmax_eobs)   + sans_leg_titre(p_tmax_era5)
) + plot_layout(ncol = 2, nrow = 2)

comp_tmax <- (grille_tmax | (espace_vide / wrap_elements(leg_tmax))) +
  plot_layout(widths = c(4, 0.8),
              heights = c(1, 1)) +
  annotation_commune(
    "Temp�rature maximale annuelle - 2014",
    "SAFRAN / CHELSA / E-OBS / ERA5-Land | Maximum annuel"
    # D�commenter quand DIGITALIS Daily tmax disponible :
    # "SAFRAN / CHELSA / E-OBS / ERA5-Land / DIGITALIS Daily | Maximum annuel"
  )

# ?????? Panneau Tmin - 2�2, l�gende BAS DROITE ??????????????????????????????????????????????????????????????????????????????????????????????????????
grille_tmin <- (
  sans_leg_titre(p_tmin_safran) + sans_leg_titre(p_tmin_chelsa) +
    sans_leg_titre(p_tmin_eobs)   + sans_leg_titre(p_tmin_era5)
) + plot_layout(ncol = 2, nrow = 2)

comp_tmin <- (grille_tmin | (espace_vide / wrap_elements(leg_tmin))) +
  plot_layout(widths = c(4, 0.8),
              heights = c(1, 1)) +
  annotation_commune(
    "Temp�rature minimale annuelle - 2014",
    "SAFRAN / CHELSA / E-OBS / ERA5-Land | Minimum annuel"
    # D�commenter quand DIGITALIS Daily tmin disponible :
    # "SAFRAN / CHELSA / E-OBS / ERA5-Land / DIGITALIS Daily | Minimum annuel"
  )

# ?????? Panneau Pr�cipitations - 3 gauche / 3 droite, l�gende MILIEU DROITE ???????????????
#col_gauche (w=1)   col_centre (w=1)   col_legende (w=0.25)
????????????????????????????????????????????????   ????????????????????????????????????????????????   ????????????????????????????????????????????????????????????
SAFRAN             CHELSA             [vide]
E-OBS              ERA5               [l�gende]
DIGI v4            DIGI Daily         [vide]

# Col gauche : SAFRAN / E-OBS / DIGITALIS v4
col_gauche <- (
  sans_leg_titre(p_precip_safran_p)         /
    sans_leg_titre(p_precip_eobs_p)           /
    sans_leg_titre(p_precip_digitalis_p)
) + plot_layout(nrow = 3)

# Col centre : CHELSA / ERA5 / DIGITALIS Daily
col_centre <- (
  sans_leg_titre(p_precip_chelsa_p)         /
    sans_leg_titre(p_precip_era5_p)           /
    sans_leg_titre(p_precip_digitalis_daily_p)
) + plot_layout(nrow = 3)

# Col droite : l�gende seule centr�e verticalement
col_legende <- (
  espace_vide                    /
    wrap_elements(leg_precip)      /
    espace_vide
) + plot_layout(nrow = 3,
                heights = c(1, 1, 1))   # ??? ajuster si l�gende trop haute/basse

comp_precip <- (col_gauche | col_centre | col_legende) +
  plot_layout(widths = c(1, 1, 0.25)) +  # ??? col l�gende �troite
  annotation_commune(
    "Cumul annuel des pr�cipitations - 2014",
    "SAFRAN / CHELSA / E-OBS / ERA5-Land / DIGITALIS v4 / DIGITALIS Daily"
  )

ggsave(file.path(dir_out, "COMP_2014_precip_6BDD.pdf"),
       comp_precip, width = 28, height = 36, dpi = 200, bg = "white")
cat("  ??? COMP_2014_precip_6BDD.pdf\n")
## IV.3 Export PDF panneaux ----
cat("\n[EXPORT] PDF panneaux comparatifs...\n")

ggsave(file.path(dir_out, "COMP_2014_tmax_4BDD.pdf"),
       comp_tmax,   width = 22, height = 18, dpi = 200, bg = "white")
cat("  ??? COMP_2014_tmax_4BDD.pdf\n")

ggsave(file.path(dir_out, "COMP_2014_tmin_4BDD.pdf"),
       comp_tmin,   width = 22, height = 18, dpi = 200, bg = "white")
cat("  ??? COMP_2014_tmin_4BDD.pdf\n")

ggsave(file.path(dir_out, "COMP_2014_precip_6BDD.pdf"),         # ??? 6BDD
       comp_precip, width = 20, height = 36, dpi = 200, bg = "white")  # ??? hauteur augment�e
cat("  ??? COMP_2014_precip_6BDD.pdf\n")

message("\n=== TERMIN� - ", length(cartes_indiv),
        " cartes individuelles + 3 panneaux export�s dans : ", dir_out, " ===")

# EXPORT RASTERS EN LAMBERT 93 ----
cat("\n[EXPORT RASTERS] Export des couches GeoTIFF en Lambert 93...\n")

dir_rasters <- file.path(dir_out, "rasters_L93")
dir.create(dir_rasters, recursive = TRUE, showWarnings = FALSE)

vers_l93 <- function(r) {
  if (crs(r, describe = TRUE)$code == "2154") return(r)
  cat("    Reprojection L93...\n")
  project(r, "EPSG:2154", method = "bilinear")
}

rasters_export <- list(
  # SAFRAN
  list(nom = "SAFRAN_tmax_2014.tif", r = rasterize(
    vect(st_as_sf(safran_fr, coords = c("lon","lat"), crs = 2154)),
    rast(ext(vect(france_l93)), res = 8000, crs = "EPSG:2154"), "T_MAX")),
  list(nom = "SAFRAN_tmin_2014.tif", r = rasterize(
    vect(st_as_sf(safran_fr, coords = c("lon","lat"), crs = 2154)),
    rast(ext(vect(france_l93)), res = 8000, crs = "EPSG:2154"), "T_MIN")),
  list(nom = "SAFRAN_precip_2014.tif", r = rasterize(
    vect(st_as_sf(safran_fr, coords = c("lon","lat"), crs = 2154)),
    rast(ext(vect(france_l93)), res = 8000, crs = "EPSG:2154"), "PRECIP")),
  # CHELSA
  list(nom = "CHELSA_tmax_2014.tif",   r = vers_l93(rast(chelsa_tmax_r))),
  list(nom = "CHELSA_tmin_2014.tif",   r = vers_l93(rast(chelsa_tmin_r))),
  list(nom = "CHELSA_precip_2014.tif", r = vers_l93(rast(chelsa_precip_r))),
  # E-OBS
  list(nom = "EOBS_tmax_2014.tif",     r = vers_l93(eobs_tmax_r)),
  list(nom = "EOBS_tmin_2014.tif",     r = vers_l93(eobs_tmin_r)),
  list(nom = "EOBS_precip_2014.tif",   r = vers_l93(eobs_precip_r)),
  # ERA5-Land
  list(nom = "ERA5_tmax_2014.tif",     r = vers_l93(era5_tmax_r)),
  list(nom = "ERA5_tmin_2014.tif",     r = vers_l93(era5_tmin_r)),
  list(nom = "ERA5_precip_2014.tif",   r = vers_l93(era5_precip_r)),
  # DIGITALIS v4
  list(nom = "DIGITALIS_v4_precip_2014.tif",    r = vers_l93(digitalis_precip_r)),
  # DIGITALIS Daily
  list(nom = "DIGITALIS_daily_precip_2014.tif", r = vers_l93(digitalis_daily_precip_r))
  # D�commenter quand tmax/tmin DIGITALIS Daily disponibles :
  # list(nom = "DIGITALIS_daily_tmax_2014.tif", r = vers_l93(digitalis_daily_tmax_r)),
  # list(nom = "DIGITALIS_daily_tmin_2014.tif", r = vers_l93(digitalis_daily_tmin_r))
)

for (item in rasters_export) {
  chemin <- file.path(dir_rasters, item$nom)
  cat(" ", item$nom, "... ")
  if (file.exists(chemin)) {
    cat("[EXISTE]\n")
  } else {
    writeRaster(item$r, chemin, overwrite = FALSE)
    cat("???\n")
  }
}

cat("\n[EXPORT RASTERS] Termin\u00e9 -", length(rasters_export),
    "fichiers dans :", dir_rasters, "\n")

# ======================================================================
# PARTIE V - PANNEAUX CALENDRIER JUILLET 2014 (3 panneaux par variable)
# Pour chaque variable (pr / tmin / tmax) un seul PDF contenant
# 3 calendriers empiles verticalement :
#   1. CHELSA daily
#   2. DIGITALIS daily (downscale CHELSA, script 4.2)
#   3. DIGITALIS daily (downscale SAFRAN, script 2)
# ======================================================================
cat("\n[CALENDRIER] Construction des panneaux journaliers juillet 2014...\n")

if (!requireNamespace("grid",      quietly = TRUE)) install.packages("grid")
if (!requireNamespace("gridExtra", quietly = TRUE)) install.packages("gridExtra")
library(grid)
library(gridExtra)

MOIS_CAL  <- 7
ANNEE_CAL <- 2014
dates_juil <- seq(as.Date("2014-07-01"), as.Date("2014-07-31"), by = "day")

# 2014-07-01 = mardi (u=2) -> 1 case vide avant
jours_semaine <- c("Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche")
premier_jour  <- as.integer(format(dates_juil[1], "%u"))  # 1=lundi 7=dimanche
n_vides_debut <- premier_jour - 1

# --- Chemins DIGITALIS downscale CHELSA (script 4.2) -----------------
dir_digi_chelsa <- "S:/Projets/stage_JeremyG/3-Donnees/5-DIGITALIS/3-DIGITALIS_daily/2014"

# --- Chemins DIGITALIS downscale SAFRAN (script 2) -------------------
dir_digi_safran_prec <- "S:/Projets/stage_JeremyG/5-Resultats/5-DIGITALIS/4-DIGITALIS_daily/2014/precipitations"
dir_digi_safran_temp <- "S:/Projets/stage_JeremyG/5-Resultats/5-DIGITALIS/4-DIGITALIS_daily/2014/temperatures"

# --- Theme minimaliste pour les petites cartes de calendrier ---------
theme_cal <- function() {
  list(
    geom_sf(data = france_l93, fill = NA, color = "grey50",
            linewidth = 0.2, inherit.aes = FALSE),
    coord_sf(crs  = 2154,
             xlim = c(80000, 1270000), ylim = c(6030000, 7160000),
             expand = FALSE),
    theme_void(base_size = 6),
    theme(
      plot.title      = element_text(hjust = 0.5, size = 7, face = "bold",
                                     margin = margin(b = 1)),
      legend.position = "none",
      plot.margin     = margin(1, 1, 1, 1)
    )
  )
}

# --- Echelles journalieres -------------------------------------------
scale_precip_j <- function() {
  scale_fill_gradientn(
    colours = c("#f7fbff", "#c6dbef", "#6baed6", "#2171b5", "#08306b"),
    limits  = c(0, 30), oob = scales::squish,
    name = "mm/j", na.value = "transparent"
  )
}

scale_tmax_j <- function() {
  scale_fill_gradientn(
    colours = rev(RColorBrewer::brewer.pal(9, "RdYlBu")),
    limits  = c(15, 40), oob = scales::squish,
    name = "\u00b0C", na.value = "transparent"
  )
}

scale_tmin_j <- function() {
  scale_fill_gradientn(
    colours = RColorBrewer::brewer.pal(9, "RdYlBu"),
    limits  = c(5, 25), oob = scales::squish,
    name = "\u00b0C", na.value = "transparent"
  )
}

# --- Fonction generique : construit UNE grille calendrier ------------
# get_df_fun : function(date) -> data.frame(lon, lat, val) ou NULL
# scale_fun  : objet ggplot scale_fill_* (deja appele, pas une fonction)
# titre_panel: titre affiche au-dessus de la grille

construire_calendrier <- function(bdd_label, var_label, get_df_fun,
                                  scale_fun, titre_panel) {

  cat(sprintf("    [%s - %s] chargement des 31 jours...\n", bdd_label, var_label))

  grob_vide <- function(label = "") {
    ggplotGrob(
      ggplot() +
        theme_void() +
        theme(plot.background = element_rect(fill = "grey92", color = NA)) +
        { if (nchar(label) > 0)
            annotate("text", x = 0.5, y = 0.5, label = label,
                     size = 3, color = "grey60", fontface = "bold")
          else geom_blank() }
    )
  }

  grobs_header <- lapply(jours_semaine, function(j) {
    ggplotGrob(
      ggplot() + theme_void() +
        annotate("text", x = 0.5, y = 0.5, label = j,
                 size = 3.5, color = "#1a4e8a", fontface = "bold")
    )
  })

  grobs_vides <- if (n_vides_debut > 0)
    lapply(seq_len(n_vides_debut), function(i) grob_vide()) else list()

  grobs_jours <- lapply(dates_juil, function(d) {
    df       <- get_df_fun(d)
    num_jour <- as.integer(format(d, "%d"))
    if (is.null(df)) return(grob_vide(as.character(num_jour)))
    p <- ggplot(df, aes(x = lon, y = lat, fill = val)) +
      geom_raster() + scale_fun + theme_cal() +
      labs(title = as.character(num_jour))
    ggplotGrob(p)
  })

  total_cases <- n_vides_debut + length(dates_juil)
  n_vides_fin <- (7 - total_cases %% 7) %% 7
  grobs_fin   <- if (n_vides_fin > 0)
    lapply(seq_len(n_vides_fin), function(i) grob_vide()) else list()

  all_grobs <- c(grobs_header, grobs_vides, grobs_jours, grobs_fin)
  n_lignes  <- 1 + ceiling(total_cases / 7)

  titre_grob <- textGrob(
    titre_panel,
    gp = gpar(fontsize = 13, fontface = "bold", col = "grey20")
  )

  arrangeGrob(grobs = all_grobs, ncol = 7, nrow = n_lignes, top = titre_grob)
}

# --- Chargeurs de donnees journalieres --------------------------------
fr_vect_l93 <- france_vect  # deja en L93

## CHELSA pr (WGS84 -> L93)
get_chelsa_pr <- function(d) {
  fname <- sprintf("CHELSA_pr_%s_%s_%d_V.2.1.tif",
                   format(d, "%d"), format(d, "%m"), as.integer(format(d, "%Y")))
  f <- file.path(dir_chelsa, "pr", fname)
  if (!file.exists(f) || file.size(f) < 50000) return(NULL)
  r <- rast(f); crs(r) <- "EPSG:4326"
  r_l93 <- project(r, "EPSG:2154", method = "bilinear")
  r_l93 <- mask(crop(r_l93, fr_vect_l93), fr_vect_l93)
  df <- as.data.frame(r_l93, xy = TRUE); names(df) <- c("lon", "lat", "val")
  df[!is.na(df$val), ]
}

## CHELSA tmin (Kelvin -> degC, WGS84 -> L93)
get_chelsa_tmin <- function(d) {
  fname <- sprintf("CHELSA_tasmin_%s_%s_%d_V.2.1.tif",
                   format(d, "%d"), format(d, "%m"), as.integer(format(d, "%Y")))
  f <- file.path(dir_chelsa, "tasmin", fname)
  if (!file.exists(f) || file.size(f) < 50000) return(NULL)
  r <- rast(f) - 273.15; crs(r) <- "EPSG:4326"
  r_l93 <- project(r, "EPSG:2154", method = "bilinear")
  r_l93 <- mask(crop(r_l93, fr_vect_l93), fr_vect_l93)
  df <- as.data.frame(r_l93, xy = TRUE); names(df) <- c("lon", "lat", "val")
  df[!is.na(df$val), ]
}

## CHELSA tmax (Kelvin -> degC, WGS84 -> L93)
get_chelsa_tmax <- function(d) {
  fname <- sprintf("CHELSA_tasmax_%s_%s_%d_V.2.1.tif",
                   format(d, "%d"), format(d, "%m"), as.integer(format(d, "%Y")))
  f <- file.path(dir_chelsa, "tasmax", fname)
  if (!file.exists(f) || file.size(f) < 50000) return(NULL)
  r <- rast(f) - 273.15; crs(r) <- "EPSG:4326"
  r_l93 <- project(r, "EPSG:2154", method = "bilinear")
  r_l93 <- mask(crop(r_l93, fr_vect_l93), fr_vect_l93)
  df <- as.data.frame(r_l93, xy = TRUE); names(df) <- c("lon", "lat", "val")
  df[!is.na(df$val), ]
}

## DIGITALIS daily (downscale CHELSA) - pr / tmin / tmax
get_digi_chelsa_pr <- function(d) {
  f <- file.path(dir_digi_chelsa, sprintf("prec_DS_%s.tif", format(d, "%Y%m%d")))
  if (!file.exists(f) || file.size(f) < 1000) return(NULL)
  r <- rast(f); crs(r) <- "EPSG:2154"
  r <- mask(crop(r, fr_vect_l93), fr_vect_l93)
  df <- as.data.frame(r, xy = TRUE); names(df) <- c("lon", "lat", "val")
  df[!is.na(df$val), ]
}

get_digi_chelsa_tmin <- function(d) {
  f <- file.path(dir_digi_chelsa, sprintf("tmin_DS_%s.tif", format(d, "%Y%m%d")))
  if (!file.exists(f) || file.size(f) < 1000) return(NULL)
  r <- rast(f); crs(r) <- "EPSG:2154"
  r <- mask(crop(r, fr_vect_l93), fr_vect_l93)
  df <- as.data.frame(r, xy = TRUE); names(df) <- c("lon", "lat", "val")
  df[!is.na(df$val), ]
}

get_digi_chelsa_tmax <- function(d) {
  f <- file.path(dir_digi_chelsa, sprintf("tmax_DS_%s.tif", format(d, "%Y%m%d")))
  if (!file.exists(f) || file.size(f) < 1000) return(NULL)
  r <- rast(f); crs(r) <- "EPSG:2154"
  r <- mask(crop(r, fr_vect_l93), fr_vect_l93)
  df <- as.data.frame(r, xy = TRUE); names(df) <- c("lon", "lat", "val")
  df[!is.na(df$val), ]
}

## DIGITALIS daily (downscale SAFRAN) - pr / tmin / tmax
get_digi_safran_pr <- function(d) {
  f <- file.path(dir_digi_safran_prec, sprintf("prec_DS_%s.tif", format(d, "%Y%m%d")))
  if (!file.exists(f) || file.size(f) < 1000) return(NULL)
  r <- rast(f); crs(r) <- "EPSG:2154"
  r <- mask(crop(r, fr_vect_l93), fr_vect_l93)
  df <- as.data.frame(r, xy = TRUE); names(df) <- c("lon", "lat", "val")
  df[!is.na(df$val), ]
}

get_digi_safran_tmin <- function(d) {
  f <- file.path(dir_digi_safran_temp, sprintf("tmin_DS_%s.tif", format(d, "%Y%m%d")))
  if (!file.exists(f) || file.size(f) < 1000) return(NULL)
  r <- rast(f); crs(r) <- "EPSG:2154"
  r <- mask(crop(r, fr_vect_l93), fr_vect_l93)
  df <- as.data.frame(r, xy = TRUE); names(df) <- c("lon", "lat", "val")
  df[!is.na(df$val), ]
}

get_digi_safran_tmax <- function(d) {
  f <- file.path(dir_digi_safran_temp, sprintf("tmax_DS_%s.tif", format(d, "%Y%m%d")))
  if (!file.exists(f) || file.size(f) < 1000) return(NULL)
  r <- rast(f); crs(r) <- "EPSG:2154"
  r <- mask(crop(r, fr_vect_l93), fr_vect_l93)
  df <- as.data.frame(r, xy = TRUE); names(df) <- c("lon", "lat", "val")
  df[!is.na(df$val), ]
}

# --- Dossier de sortie -----------------------------------------------
dir_cal <- file.path(dir_out, "1-Comparaison_BDD")
dir.create(dir_cal, recursive = TRUE, showWarnings = FALSE)

# --- Definition des 3 panneaux (1 par variable) ----------------------
# Chaque panneau = 3 calendriers empiles : CHELSA / Digi-CHELSA / Digi-SAFRAN

configs_panneaux <- list(

  pr = list(
    label = "Pr\u00e9cipitations journali\u00e8res - Juillet 2014",
    scale = scale_precip_j(),
    fname = "CAL_2014_07_pr_3BDD.pdf",
    lignes = list(
      list(fun = get_chelsa_pr,
           titre = "Pr\u00e9cipitations journali\u00e8res - Juillet 2014 | CHELSA Daily V2.1 (~1 km)"),
      list(fun = get_digi_chelsa_pr,
           titre = "Pr\u00e9cipitations journali\u00e8res - Juillet 2014 | DIGITALIS Daily / downscale CHELSA (~1 km)"),
      list(fun = get_digi_safran_pr,
           titre = "Pr\u00e9cipitations journali\u00e8res - Juillet 2014 | DIGITALIS Daily / downscale SAFRAN (~1 km)")
    )
  ),

  tmin = list(
    label = "Temp\u00e9rature minimale journali\u00e8re - Juillet 2014",
    scale = scale_tmin_j(),
    fname = "CAL_2014_07_tmin_3BDD.pdf",
    lignes = list(
      list(fun = get_chelsa_tmin,
           titre = "Tmin journali\u00e8re - Juillet 2014 | CHELSA Daily V2.1 (~1 km)"),
      list(fun = get_digi_chelsa_tmin,
           titre = "Tmin journali\u00e8re - Juillet 2014 | DIGITALIS Daily / downscale CHELSA (~1 km)"),
      list(fun = get_digi_safran_tmin,
           titre = "Tmin journali\u00e8re - Juillet 2014 | DIGITALIS Daily / downscale SAFRAN (~1 km)")
    )
  ),

  tmax = list(
    label = "Temp\u00e9rature maximale journali\u00e8re - Juillet 2014",
    scale = scale_tmax_j(),
    fname = "CAL_2014_07_tmax_3BDD.pdf",
    lignes = list(
      list(fun = get_chelsa_tmax,
           titre = "Tmax journali\u00e8re - Juillet 2014 | CHELSA Daily V2.1 (~1 km)"),
      list(fun = get_digi_chelsa_tmax,
           titre = "Tmax journali\u00e8re - Juillet 2014 | DIGITALIS Daily / downscale CHELSA (~1 km)"),
      list(fun = get_digi_safran_tmax,
           titre = "Tmax journali\u00e8re - Juillet 2014 | DIGITALIS Daily / downscale SAFRAN (~1 km)")
    )
  )
)

# --- Construction et export ------------------------------------------
for (var_name in names(configs_panneaux)) {
  cfg <- configs_panneaux[[var_name]]
  cat(sprintf("\n  [CALENDRIER] Panneau %s (%s)...\n", var_name, cfg$label))

  # Construit les 3 grilles calendrier
  grilles <- lapply(cfg$lignes, function(lig) {
    construire_calendrier(
      bdd_label   = lig$titre,
      var_label   = var_name,
      get_df_fun  = lig$fun,
      scale_fun   = cfg$scale,   # objet scale partage (meme palette)
      titre_panel = lig$titre
    )
  })

  # Empilage vertical des 3 grilles + titre global du panneau
  titre_global <- textGrob(
    paste0(cfg$label, "  |  CHELSA  /  DIGITALIS-CHELSA  /  DIGITALIS-SAFRAN"),
    gp = gpar(fontsize = 16, fontface = "bold", col = "grey10")
  )

  panneau_complet <- arrangeGrob(
    grobs  = grilles,
    ncol   = 1,
    nrow   = 3,
    top    = titre_global
  )

  chemin_pdf <- file.path(dir_cal, cfg$fname)
  # Largeur 28 po (7 jours x 4 po), hauteur 3 x 20 po = 60 po
  pdf(chemin_pdf, width = 28, height = 60)
  grid.draw(panneau_complet)
  dev.off()
  cat(sprintf("  -> %s\n", cfg$fname))
}

cat("\n=== PANNEAUX CALENDRIER TERMINES ===\n",
    length(configs_panneaux), "panneaux (pr / tmin / tmax) export\u00e9s dans :", dir_cal, "\n")


maintenant je voudrais que tu me rajoute une planche avec (lorsque c'est possible pour : ERA_5/E-OBS/DIGITALIS daily downscale avec SAFRAN/DIGITALIS daily DOWNSCLAE avec CHELSA/CHELSA daily) avec tout les jours du mois de juilet de 2014 au format agenda semaine, et avec chaque carte de chaque base de donn�e chaque jour