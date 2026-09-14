# ======================================================================
# E-OBS v31.0e - Diagnostic NA + Visualisation journaliere
# Variables : precipitations (rr) + temperature max (tx) + temperature min (tn)
# Source    : 3-Donnees/3-E_OBS/2-1950_2024_EOBS_FR/
# Grille    : reguliere WGS84 0.1deg x 0.1deg
# Unites    : rr en mm/jour | tx et tn en degC (ensemble_mean)
#
# IMPORTANT : fichiers de 1.5 a 5 GB - chargement pleine periode avec
#   sous-fenetre spatiale uniquement (start + count sur lon/lat).
#
# Sections :
#   1. Chargement (France, 1950-2024)
#   2. Taux global de NA par variable
#   3. NA par jour : proportion de pixels NA chaque jour
#   4. NA par pixel : nombre de jours NA par cellule (carte)
#   5. Tableau recapitulatif
#   6. Visualisation septembre 2014 : series + cartes + export rasters
# ======================================================================

if (!requireNamespace("ncdf4",   quietly = TRUE)) install.packages("ncdf4")
if (!requireNamespace("ggplot2", quietly = TRUE)) install.packages("ggplot2")
if (!requireNamespace("terra",   quietly = TRUE)) install.packages("terra")
library(ncdf4)
library(ggplot2)
library(terra)

# --- Parametres -------------------------------------------------------
DIR_EOBS <- "S:/Projets/stage_JeremyG/3-Donnees/3-E_OBS/2-1950_2024_EOBS_FR"
F_RR_IN  <- file.path(DIR_EOBS, "rr_ens_mean_0.1deg_reg_v31.0e.nc")
F_TX_IN  <- file.path(DIR_EOBS, "tx_ens_mean_0.1deg_reg_v31.0e.nc")
F_TN_IN  <- file.path(DIR_EOBS, "tn_ens_mean_0.1deg_reg_v31.0e.nc")

# Emprise France (WGS84)
LON_MIN <- -5.5;  LON_MAX <- 10.0
LAT_MIN <- 41.0;  LAT_MAX <- 51.5

# Seuil d'alerte NA
SEUIL_PCT_NA <- 10   # %

# Periode de visualisation
DATE_VIZ_DEB <- as.Date("2014-09-01")
DATE_VIZ_FIN <- as.Date("2014-09-30")

# Jour exporte en raster
DATE_RAS     <- as.Date("2014-09-19")

# Point de reference
LAT_PT <- 48.692   # Nancy
LON_PT <- 6.184

# Dossiers de sortie
DIR_OUT     <- "S:/Projets/stage_JeremyG/5-Resultats/3-Downscaling/2-E_OBS"
DIR_OUT_RAS <- file.path(DIR_OUT, "rasters")
dir.create(DIR_OUT,     recursive = TRUE, showWarnings = FALSE)
dir.create(DIR_OUT_RAS, recursive = TRUE, showWarnings = FALSE)

# Cache : evite de relire les fichiers NC a chaque execution
# Le nom encode l'emprise -> invalide automatiquement si on change la fenetre
DIR_CACHE <- file.path(DIR_EOBS, "cache")
dir.create(DIR_CACHE, recursive = TRUE, showWarnings = FALSE)
F_CACHE   <- file.path(DIR_CACHE,
               sprintf("EOBS_rrtxtn_lon%.1f_%.1f_lat%.1f_%.1f.rds",
                       LON_MIN, LON_MAX, LAT_MIN, LAT_MAX))

# ======================================================================
# FONCTIONS
# ======================================================================

# Chargement pleine periode avec sous-fenetre spatiale uniquement
charger_subset <- function(f_nc, varname,
                            lon_min, lon_max, lat_min, lat_max) {
  cat(sprintf("Chargement %-4s : %s ...", varname, basename(f_nc)))
  nc    <- nc_open(f_nc)
  lon   <- ncvar_get(nc, "longitude")
  lat   <- ncvar_get(nc, "latitude")
  time  <- ncvar_get(nc, "time")
  dates <- as.Date("1950-01-01") + as.numeric(time)

  ix <- which(lon >= lon_min & lon <= lon_max)
  iy <- which(lat >= lat_min & lat <= lat_max)

  dat <- ncvar_get(nc, varname,
                   start = c(min(ix), min(iy), 1),
                   count = c(length(ix), length(iy), length(time)))
  nc_close(nc)
  dat[dat < -999 | dat > 1e10] <- NA
  cat(sprintf(" %d lon x %d lat x %d jours\n", length(ix), length(iy), length(time)))
  list(data = dat, lon = lon[ix], lat = lat[iy], dates = dates)
}


# ======================================================================
# 1. CHARGEMENT (pleine periode, emprise France)
#    Lecture depuis le cache si disponible, sinon extraction + sauvegarde
# ======================================================================
if (file.exists(F_CACHE)) {
  cat(sprintf("Cache trouve : %s\nChargement...\n", basename(F_CACHE)))
  cache <- readRDS(F_CACHE)
  rr <- cache$rr;  tx <- cache$tx;  tn <- cache$tn
  cat(sprintf("  %d lon x %d lat x %d jours charges depuis le cache.\n",
              length(rr$lon), length(rr$lat), length(rr$dates)))
  rm(cache)
} else {
  cat("Aucun cache trouve - extraction depuis les fichiers NC...\n")
  rr <- charger_subset(F_RR_IN, "rr", LON_MIN, LON_MAX, LAT_MIN, LAT_MAX)
  tx <- charger_subset(F_TX_IN, "tx", LON_MIN, LON_MAX, LAT_MIN, LAT_MAX)
  tn <- charger_subset(F_TN_IN, "tn", LON_MIN, LON_MAX, LAT_MIN, LAT_MAX)
  cat(sprintf("Sauvegarde cache : %s ...", basename(F_CACHE)))
  saveRDS(list(rr = rr, tx = tx, tn = tn), F_CACHE)
  cat(sprintf(" OK (%.1f MB)\n", file.size(F_CACHE) / 1e6))
}

lon   <- rr$lon
lat   <- rr$lat
dates <- rr$dates
n_pix <- length(lon) * length(lat)
n_j   <- length(dates)

# ======================================================================
# 2. TAUX GLOBAL DE NA PAR VARIABLE
# ======================================================================
cat("\n========== TAUX GLOBAL DE NA ==========\n")
for (nm in c("rr", "tx", "tn")) {
  d   <- get(nm)$data
  pct <- mean(is.na(d)) * 100
  cat(sprintf("  %-4s : %6.2f %% de valeurs NA  (%d / %d)\n",
              nm, pct, sum(is.na(d)), length(d)))
}

# ======================================================================
# 3. NA PAR JOUR : proportion de pixels NA chaque jour
# ======================================================================
cat("\n========== NA PAR JOUR ==========\n")
na_par_jour <- function(arr3d) {
  apply(arr3d, 3, function(sl) mean(is.na(sl)) * 100)
}

pct_na_rr <- na_par_jour(rr$data)
pct_na_tx <- na_par_jour(tx$data)
pct_na_tn <- na_par_jour(tn$data)

for (nm in c("rr", "tx", "tn")) {
  pct      <- get(paste0("pct_na_", nm))
  jours_pb <- sum(pct > SEUIL_PCT_NA)
  cat(sprintf("  %-4s : %d jours avec > %d%% de pixels NA\n", nm, jours_pb, SEUIL_PCT_NA))
  if (jours_pb > 0) {
    idx_pb <- which(pct > SEUIL_PCT_NA)
    cat(sprintf("         Premier : %s (%.1f%%)\n", dates[idx_pb[1]],      pct[idx_pb[1]]))
    cat(sprintf("         Dernier : %s (%.1f%%)\n", dates[tail(idx_pb,1)], pct[tail(idx_pb,1)]))
  }
}

df_na_j <- data.frame(
  date     = rep(dates, 3),
  pct_na   = c(pct_na_rr, pct_na_tx, pct_na_tn),
  variable = rep(c("rr (precip)", "tx (Tmax)", "tn (Tmin)"), each = n_j)
)

p_na_jour <- ggplot(df_na_j, aes(x = date, y = pct_na, colour = variable)) +
  geom_line(linewidth = 0.4, alpha = 0.8) +
  geom_hline(yintercept = SEUIL_PCT_NA, linetype = "dashed", colour = "red") +
  facet_wrap(~variable, ncol = 1, scales = "free_y") +
  labs(title    = "E-OBS v31.0e - % pixels NA par jour (France)",
       subtitle = sprintf("Ligne rouge = seuil %d%%", SEUIL_PCT_NA),
       x = "Date", y = "% pixels NA") +
  theme_minimal() +
  theme(legend.position = "none")
print(p_na_jour)
ggsave(file.path(DIR_OUT, "EOBS_NA_par_jour.png"), p_na_jour,
       width = 10, height = 8, dpi = 150)

# ======================================================================
# 4. NA PAR PIXEL : nombre de jours NA par cellule (carte)
# ======================================================================
cat("\n========== NA PAR PIXEL ==========\n")
na_par_pixel <- function(arr3d) {
  apply(arr3d, c(1, 2), function(x) sum(is.na(x)))
}

na_pix_rr <- na_par_pixel(rr$data)
na_pix_tx <- na_par_pixel(tx$data)
na_pix_tn <- na_par_pixel(tn$data)

for (nm in c("rr", "tx", "tn")) {
  m      <- get(paste0("na_pix_", nm))
  pix_pb <- sum(m > 0)
  cat(sprintf("  %-4s : %d pixels avec au moins 1 jour NA (/ %d total)\n",
              nm, pix_pb, n_pix))
  cat(sprintf("         Max jours NA sur un pixel : %d / %d jours\n", max(m), n_j))
}

carte_na <- function(na_mat, lon1d, lat1d, titre) {
  df        <- expand.grid(lon = lon1d, lat = lat1d)
  df$na_j   <- as.vector(na_mat)
  df$na_j[df$na_j == 0] <- NA
  ggplot(df, aes(x = lon, y = lat, fill = na_j)) +
    geom_raster() +
    scale_fill_gradient(low = "yellow", high = "red3",
                        name = "nb jours\nNA", na.value = "grey95") +
    coord_fixed() +
    labs(title = titre, x = "Lon", y = "Lat") +
    theme_minimal()
}

p_na_pix_rr <- carte_na(na_pix_rr, lon, lat, "E-OBS v31.0e - Jours NA par pixel - rr (precip)")
p_na_pix_tx <- carte_na(na_pix_tx, lon, lat, "E-OBS v31.0e - Jours NA par pixel - tx (Tmax)")
p_na_pix_tn <- carte_na(na_pix_tn, lon, lat, "E-OBS v31.0e - Jours NA par pixel - tn (Tmin)")
print(p_na_pix_rr); print(p_na_pix_tx); print(p_na_pix_tn)
ggsave(file.path(DIR_OUT, "EOBS_NA_par_pixel_rr.png"), p_na_pix_rr, width = 7, height = 6, dpi = 150)
ggsave(file.path(DIR_OUT, "EOBS_NA_par_pixel_tx.png"), p_na_pix_tx, width = 7, height = 6, dpi = 150)
ggsave(file.path(DIR_OUT, "EOBS_NA_par_pixel_tn.png"), p_na_pix_tn, width = 7, height = 6, dpi = 150)

# ======================================================================
# 5. TABLEAU RECAPITULATIF
# ======================================================================
cat("\n========== RECAPITULATIF ==========\n")
cat(sprintf("  Periode      : %s -> %s (%d jours)\n", min(dates), max(dates), n_j))
cat(sprintf("  Emprise      : lon [%.1f ; %.1f] | lat [%.1f ; %.1f]\n",
            min(lon), max(lon), min(lat), max(lat)))
cat(sprintf("  Pixels total : %d (%d lon x %d lat)\n", n_pix, length(lon), length(lat)))
cat("\n")
cat(sprintf("  %-6s | %-10s | %-18s | %-15s\n",
            "Var", "% NA global", "Jours >10% NA", "Max jours NA/pixel"))
cat(rep("-", 60), "\n", sep = "")
for (nm in c("rr", "tx", "tn")) {
  d      <- get(nm)$data
  pct_g  <- mean(is.na(d)) * 100
  pct_j  <- get(paste0("pct_na_", nm))
  na_pix <- get(paste0("na_pix_", nm))
  cat(sprintf("  %-6s | %9.2f%% | %-18d | %d\n",
              nm, pct_g, sum(pct_j > SEUIL_PCT_NA), max(na_pix)))
}

# ======================================================================
# 6. VISUALISATION - PERIODE D'INTERET
# ======================================================================
cat(sprintf("\n========== VISUALISATION %s - %s ==========\n",
            DATE_VIZ_DEB, DATE_VIZ_FIN))

idx_viz   <- which(dates >= DATE_VIZ_DEB & dates <= DATE_VIZ_FIN)
if (length(idx_viz) == 0) stop("Periode de visualisation absente des donnees.")
dates_viz <- dates[idx_viz]
cat(sprintf("  Periode : %d jours\n", length(idx_viz)))

# Indices du point de reference
ix_pt <- which.min(abs(lon - LON_PT))
iy_pt <- which.min(abs(lat - LAT_PT))
cat(sprintf("  Point ref : lat=%.3f lon=%.3f\n", lat[iy_pt], lon[ix_pt]))

# --- 6.1 Stats au point de reference ----------------------------------
df_viz <- data.frame(
  date = dates_viz,
  rr   = rr$data[ix_pt, iy_pt, idx_viz],
  tx   = tx$data[ix_pt, iy_pt, idx_viz],
  tn   = tn$data[ix_pt, iy_pt, idx_viz]
)
cat(sprintf("  Cumul precip   : %.1f mm\n",  sum(df_viz$rr,  na.rm = TRUE)))
cat(sprintf("  Tx moyenne     : %.1f degC\n", mean(df_viz$tx, na.rm = TRUE)))
cat(sprintf("  Tn moyenne     : %.1f degC\n", mean(df_viz$tn, na.rm = TRUE)))
cat(sprintf("  Tx max absolu  : %.1f degC\n", max(df_viz$tx,  na.rm = TRUE)))
cat(sprintf("  Tn min absolu  : %.1f degC\n", min(df_viz$tn,  na.rm = TRUE)))

# --- 6.2 Series temporelles -------------------------------------------
lbl_pt <- sprintf("%.3fdegN / %.3fdegE", LAT_PT, LON_PT)

p_rr_viz <- ggplot(df_viz, aes(x = date, y = rr)) +
  geom_col(fill = "steelblue") +
  labs(title = sprintf("E-OBS v31.0e - Precipitations journalieres\n%s - %s | %s",
                       DATE_VIZ_DEB, DATE_VIZ_FIN, lbl_pt),
       x = NULL, y = "rr (mm/jour)") +
  theme_minimal()

p_t_viz <- ggplot(df_viz, aes(x = date)) +
  geom_ribbon(aes(ymin = tn, ymax = tx), fill = "salmon", alpha = 0.4) +
  geom_line(aes(y = (tx + tn) / 2), colour = "red3", linewidth = 0.8) +
  labs(title = sprintf("E-OBS v31.0e - Temperatures journalieres\n%s - %s | %s | rouge = (Tx+Tn)/2",
                       DATE_VIZ_DEB, DATE_VIZ_FIN, lbl_pt),
       x = "Date", y = "Temperature (degC)") +
  theme_minimal()

print(p_rr_viz); print(p_t_viz)
ggsave(file.path(DIR_OUT, "EOBS_viz_serie_rr_Nancy.png"),   p_rr_viz, width = 8, height = 4, dpi = 150)
ggsave(file.path(DIR_OUT, "EOBS_viz_serie_temp_Nancy.png"), p_t_viz,  width = 8, height = 4, dpi = 150)

# --- 6.3 Cartes journalieres (small multiples) ------------------------
build_facet_df <- function(arr3d, lon1d, lat1d, idx_t, dates_t) {
  do.call(rbind, lapply(seq_along(idx_t), function(k) {
    df      <- expand.grid(lon = lon1d, lat = lat1d)
    df$val  <- as.vector(arr3d[, , idx_t[k]])
    df$jour <- format(dates_t[k], "%d %b")
    df
  }))
}

cat("  Construction des cartes rr...\n")
df_rr_viz <- build_facet_df(rr$data, lon, lat, idx_viz, dates_viz)
cat("  Construction des cartes tx...\n")
df_tx_viz <- build_facet_df(tx$data, lon, lat, idx_viz, dates_viz)
cat("  Construction des cartes tn...\n")
df_tn_viz <- build_facet_df(tn$data, lon, lat, idx_viz, dates_viz)

# Precipitations : palette multi-etapes sans limits (evite les gris parasites)
p_cartes_rr <- ggplot(df_rr_viz, aes(x = lon, y = lat, fill = val)) +
  geom_raster() +
  scale_fill_gradientn(
    colours  = c("white", "#c6dbef", "#6baed6", "#2171b5", "#08306b"),
    values   = c(0, 0.05, 0.20, 0.50, 1),
    na.value = "grey85",
    name     = "mm/j"
  ) +
  coord_fixed() +
  facet_wrap(~jour, ncol = 6) +
  labs(title = sprintf("E-OBS v31.0e - Precipitations journalieres - %s / %s",
                       DATE_VIZ_DEB, DATE_VIZ_FIN),
       x = "Lon", y = "Lat") +
  theme_minimal(base_size = 8) +
  theme(axis.text = element_blank(), axis.ticks = element_blank(),
        panel.spacing = unit(0.2, "lines"))

# Temperature maximale
p_cartes_tx <- ggplot(df_tx_viz, aes(x = lon, y = lat, fill = val)) +
  geom_raster() +
  scale_fill_gradient2(low = "steelblue", mid = "white", high = "red3",
                       midpoint = 20, name = "degC", na.value = "grey85") +
  coord_fixed() +
  facet_wrap(~jour, ncol = 6) +
  labs(title = sprintf("E-OBS v31.0e - Temperature maximale (Tx) - %s / %s",
                       DATE_VIZ_DEB, DATE_VIZ_FIN),
       x = "Lon", y = "Lat") +
  theme_minimal(base_size = 8) +
  theme(axis.text = element_blank(), axis.ticks = element_blank(),
        panel.spacing = unit(0.2, "lines"))

# Temperature minimale
p_cartes_tn <- ggplot(df_tn_viz, aes(x = lon, y = lat, fill = val)) +
  geom_raster() +
  scale_fill_gradient2(low = "steelblue", mid = "white", high = "red3",
                       midpoint = 12, name = "degC", na.value = "grey85") +
  coord_fixed() +
  facet_wrap(~jour, ncol = 6) +
  labs(title = sprintf("E-OBS v31.0e - Temperature minimale (Tn) - %s / %s",
                       DATE_VIZ_DEB, DATE_VIZ_FIN),
       x = "Lon", y = "Lat") +
  theme_minimal(base_size = 8) +
  theme(axis.text = element_blank(), axis.ticks = element_blank(),
        panel.spacing = unit(0.2, "lines"))

print(p_cartes_rr); print(p_cartes_tx); print(p_cartes_tn)

periode_lbl <- format(DATE_VIZ_DEB, "%Y%m")
ggsave(file.path(DIR_OUT, sprintf("EOBS_cartes_rr_%s.png", periode_lbl)),
       p_cartes_rr, width = 14, height = 10, dpi = 150)
ggsave(file.path(DIR_OUT, sprintf("EOBS_cartes_tx_%s.png", periode_lbl)),
       p_cartes_tx, width = 14, height = 10, dpi = 150)
ggsave(file.path(DIR_OUT, sprintf("EOBS_cartes_tn_%s.png", periode_lbl)),
       p_cartes_tn, width = 14, height = 10, dpi = 150)
cat(sprintf("Cartes enregistrees dans : %s\n", DIR_OUT))

# --- 6.4 Export raster GeoTIFF (jour unique) --------------------------
cat(sprintf("\n--- Export rasters GeoTIFF : %s ---\n", DATE_RAS))

idx_ras <- which(dates == DATE_RAS)
if (length(idx_ras) == 0) stop(sprintf("Date %s absente des donnees.", DATE_RAS))
ras_lbl <- format(DATE_RAS, "%Y%m%d")

# Fonction : array 2D [lon, lat] -> SpatRaster 1 couche
arr2d_to_rast <- function(mat2d, lon1d, lat1d, date_r) {
  res <- 0.1
  r   <- terra::rast(
    nrows = length(lat1d), ncols = length(lon1d), nlyr = 1,
    xmin  = min(lon1d) - res / 2, xmax = max(lon1d) + res / 2,
    ymin  = min(lat1d) - res / 2, ymax = max(lat1d) + res / 2,
    crs   = "EPSG:4326"
  )
  terra::values(r) <- as.vector(t(mat2d)[length(lat1d):1, ])
  names(r)         <- format(date_r, "%Y-%m-%d")
  r
}

cat("  rr ...\n")
terra::writeRaster(arr2d_to_rast(rr$data[, , idx_ras], lon, lat, DATE_RAS),
                   file.path(DIR_OUT_RAS, sprintf("EOBS_rr_%s.tif", ras_lbl)),
                   overwrite = TRUE)
cat("  tx ...\n")
terra::writeRaster(arr2d_to_rast(tx$data[, , idx_ras], lon, lat, DATE_RAS),
                   file.path(DIR_OUT_RAS, sprintf("EOBS_tx_%s.tif", ras_lbl)),
                   overwrite = TRUE)
cat("  tn ...\n")
terra::writeRaster(arr2d_to_rast(tn$data[, , idx_ras], lon, lat, DATE_RAS),
                   file.path(DIR_OUT_RAS, sprintf("EOBS_tn_%s.tif", ras_lbl)),
                   overwrite = TRUE)
cat(sprintf("Rasters enregistres dans : %s\n", DIR_OUT_RAS))

cat("=== TERMINE ===\n")
