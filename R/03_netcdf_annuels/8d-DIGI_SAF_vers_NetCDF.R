# source(".../4-Mise_en_forme/8d-DIGI_SAF_vers_NetCDF.R")
# ==============================================================================
# CONVERSION DIGI_SAF (downscaling SAFRAN IDW) -> NetCDF annuel WGS84
# 2026-06-08 : script INDIVIDUEL propre, extrait du master 8.1 (relegue) et calque
#   sur 8d-Conversion_DIGI_CHEL.R. Comble le trou "DIGI_SAF TIF->NC" (cf
#   [[project_pipeline_sandbox_drivable]]). Produit directement le NC WGS84 ->
#   l'ancienne etape 8e-DIGI_SAF_reprojection devient inutile.
#
# Source : TIFs IDW (L93), structure recursive
#          <SRC_ROOT>/<YYYY>/<MM>/precipitations/prec_DS_IDW_YYYYMMDD.tif
#                              /tmin/tmin_DS_IDW_YYYYMMDD.tif
#                              /tmax/tmax_DS_IDW_YYYYMMDD.tif
# Sortie : <DST>/DIGI_SAF_{prec|tmin|tmax}_{YYYY}.nc  (WGS84, axe temps CF)
#
# Sandbox (test bout-en-bout) : SANDBOX_ANNEES / SANDBOX_OUT / SANDBOX_CROP_EXT.
# ==============================================================================

# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
suppressPackageStartupMessages({ library(terra); library(lubridate); library(ncdf4) })

ROOT_LOC <- LOCAL_ROOT
ROOT_SRV <- PROJET

SRC_ROOT    <- file.path(ROOT_SRV, "3-Donnees", "5-DIGITALIS", "4-DIGITALIS_daily_DS_SAFRAN_IDW")
DST         <- file.path(ROOT_LOC, "ECE_data", "5-DIGI_SAF_1km")
COMPRESSION <- 5
CRS_NATIVE  <- "EPSG:2154"   # Lambert-93 (grille IDW)

# --- Surcharge SANDBOX (test) : restreint source / sortie / periode / emprise --
# En sandbox, le downscaling a ecrit les TIFs dans SANDBOX_OUT/DIGI_SAF_IDW_TIF
# (cf 1-Production_SAFRAN_DS_IDW) -> on lit la, et on ecrit dans le ECE_data sandbox.
if (exists("SANDBOX_OUT")) {
  SRC_ROOT <- file.path(SANDBOX_OUT, "DIGI_SAF_IDW_TIF")
  DST      <- file.path(SANDBOX_OUT, "ECE_data", "5-DIGI_SAF_1km")
}
ANNEES_CIBLE <- if (exists("SANDBOX_ANNEES")) SANDBOX_ANNEES else NULL   # NULL = toutes
CROP_EXT     <- if (exists("SANDBOX_CROP_EXT")) terra::ext(SANDBOX_CROP_EXT) else NULL

if (!dir.exists(DST)) dir.create(DST, recursive = TRUE)

# prec en mm, temp en degC (downscaling deja en unites finales) -> pas de conversion.
VARS <- list(
  list(prefixe_tif = "prec", prefixe_nc = "DIGI_SAF_prec",
       varname = "prec", unit = "mm",   longname = "Daily precipitation DIGI_SAF (DS SAFRAN IDW)"),
  list(prefixe_tif = "tmax", prefixe_nc = "DIGI_SAF_tmax",
       varname = "tmax", unit = "degC", longname = "Daily max temperature DIGI_SAF (DS SAFRAN IDW)"),
  list(prefixe_tif = "tmin", prefixe_nc = "DIGI_SAF_tmin",
       varname = "tmin", unit = "degC", longname = "Daily min temperature DIGI_SAF (DS SAFRAN IDW)")
)

# Liste recursive des TIFs d'une variable (+ dates), filtre eventuel sur ANNEES_CIBLE.
lister_tifs <- function(prefixe) {
  f <- list.files(SRC_ROOT, pattern = sprintf("^%s_DS_IDW_\\d{8}\\.tif$", prefixe),
                  full.names = TRUE, recursive = TRUE)
  d <- as.Date(sub(".*_DS_IDW_(\\d{8})\\.tif$", "\\1", basename(f)), format = "%Y%m%d")
  ok <- !is.na(d)
  f <- f[ok]; d <- d[ok]
  if (!is.null(ANNEES_CIBLE)) { keep <- year(d) %in% ANNEES_CIBLE; f <- f[keep]; d <- d[keep] }
  list(f = f, d = d)
}

# Template WGS84 : depuis un TIF L93 (project), eventuellement croppe (sandbox).
get_template <- function() {
  f0 <- lister_tifs("prec")$f
  if (length(f0) == 0) stop("Aucun TIF DIGI_SAF trouve sous : ", SRC_ROOT)
  r <- rast(f0[1])[[1]]
  if (is.na(crs(r)) || nchar(crs(r)) == 0) crs(r) <- CRS_NATIVE
  tmpl <- project(r, "EPSG:4326", method = "bilinear")
  if (!is.null(CROP_EXT)) tmpl <- crop(tmpl, CROP_EXT)   # emprise sandbox (WGS84)
  cat(sprintf("  Template WGS84 : %d x %d (res ~%.5f deg)\n",
              nrow(tmpl), ncol(tmpl), mean(res(tmpl))))
  tmpl
}

cat(sprintf("\n=== CONVERSION DIGI_SAF -> NetCDF WGS84 ===\n  source : %s\n  sortie : %s\n",
            SRC_ROOT, DST))
if (!is.null(ANNEES_CIBLE)) cat(sprintf("  [SANDBOX] annees : %s\n", paste(ANNEES_CIBLE, collapse=", ")))

tmpl <- get_template()
nlon <- ncol(tmpl); nlat <- nrow(tmpl)
lon_vals <- xFromCol(tmpl, 1:nlon); lat_vals <- yFromRow(tmpl, 1:nlat)
t0_global <- Sys.time()

for (v in VARS) {
  cat(sprintf("\n--- Variable : %s ---\n", v$varname))
  inv <- lister_tifs(v$prefixe_tif)
  if (length(inv$f) == 0) { cat("  aucun TIF -> skip\n"); next }
  annees <- sort(unique(year(inv$d)))
  manquants <- annees[!file.exists(file.path(DST, sprintf("%s_%d.nc", v$prefixe_nc, annees)))]
  if (length(manquants) == 0) { cat(sprintf("  %s : complet, rien a faire\n", v$varname)); next }
  cat(sprintf("  %d annee(s) a produire : %s\n", length(manquants), paste(manquants, collapse=", ")))

  for (an in manquants) {
    f_nc  <- file.path(DST, sprintf("%s_%d.nc", v$prefixe_nc, an))
    f_tmp <- paste0(f_nc, ".tmp.nc")
    if (file.exists(f_tmp)) file.remove(f_tmp)
    idx  <- which(year(inv$d) == an)
    f_an <- inv$f[idx[order(inv$d[idx])]]
    d_an <- sort(inv$d[idx])
    cat(sprintf("  -> %s %d (%d jours)...", v$varname, an, length(f_an)))
    nc_out <- NULL
    tryCatch({
      dim_x <- ncdim_def("longitude", "degrees_east",  lon_vals)
      dim_y <- ncdim_def("latitude",  "degrees_north", lat_vals)
      dim_t <- ncdim_def("time", "days since 1970-01-01",
                         as.numeric(d_an - as.Date("1970-01-01")),
                         unlim = TRUE, calendar = "standard")
      var_def <- ncvar_def(v$varname, v$unit, list(dim_x, dim_y, dim_t),
                           missval = -9999, longname = v$longname,
                           prec = "float", compression = COMPRESSION,
                           chunksizes = c(nlon, nlat, 1L))
      nc_out <- nc_create(f_tmp, var_def, force_v4 = TRUE)
      for (i in seq_along(f_an)) {
        r_i <- rast(f_an[i])
        if (is.na(crs(r_i)) || nchar(crs(r_i)) == 0) crs(r_i) <- CRS_NATIVE
        r_i <- project(r_i, tmpl, method = "bilinear")   # L93 -> WGS84 + grille template
        vals <- t(as.matrix(r_i, wide = TRUE))
        ncvar_put(nc_out, v$varname, vals, start = c(1L,1L,i), count = c(nlon,nlat,1L))
        rm(r_i, vals); if (i %% 30L == 0L) gc()
      }
      nc_close(nc_out); nc_out <- NULL
      file.rename(f_tmp, f_nc)
      cat(sprintf(" OK (%.0f Mo)\n", file.size(f_nc)/1e6))
      .rr <- terra::rast(f_nc)   # VALIDATION CONTENU (#6) : refuser une annee tout-NaN
      if (as.numeric(terra::global(.rr[[1]], "notNA")[1, 1]) +
          as.numeric(terra::global(.rr[[terra::nlyr(.rr)]], "notNA")[1, 1]) == 0) {
        rm(.rr); file.remove(f_nc)
        cat("    [REFUS] annee tout-NaN -> fichier retire\n")
      }
    }, error = function(e) {
      cat(sprintf("\n    ERREUR : %s\n", conditionMessage(e)))
      if (!is.null(nc_out)) try(nc_close(nc_out), silent = TRUE)
      if (file.exists(f_tmp)) file.remove(f_tmp)
    })
    gc()
  }
}
cat(sprintf("\n=== TERMINE en %.1f min ===\n", as.numeric(difftime(Sys.time(), t0_global, "mins"))))
