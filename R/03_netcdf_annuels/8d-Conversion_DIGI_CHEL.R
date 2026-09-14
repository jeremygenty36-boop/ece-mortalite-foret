# ==============================================================================
# CONVERSION DIGI_CHELSA -> NetCDF WGS84
# DERNIERE VERSION : v1.1 - 2026-04-21 10:19
# Adapte de 8c-Verification_completion_CHELSA.R
#
# Source  : TIF journaliers - deux cas selon annee et variable :
#           * tmax/tmin TOUTES annees : L93 sans tag CRS (res=1000m, EPSG:2154)
#           * prec <= 1989            : WGS84 natif CHELSA (res ~0.00833 deg)
#           * prec >= 1990            : WGS84
#           Convention : {varname}_DS_{YYYYMMDD}.tif
#           Dossier    : S:/Projets/stage_JeremyG/3-Donnees/5-DIGITALIS/3-DIGITALIS_daily_DS_CHELSA/{YYYY}/
# Sortie  : NetCDF annuels WGS84 - D:/Stage_JeremyG/ECE_data/6-DIGI_CHEL_1km/
#           Convention : DIGI_CHEL_{varname}_{YYYY}.nc
#
# La projection de chaque fichier source est detectee automatiquement :
#   - Fichier deja en WGS84 (is.lonlat = TRUE) : resampling vers le template
#   - Fichier en L93 (is.lonlat = FALSE)        : CRS assigne si absent, puis reprojection
# Template WGS84 derive en priorite depuis un fichier L93 pour avoir la resolution 1km exacte
# ==============================================================================

suppressPackageStartupMessages({
  library(terra)
  library(lubridate)
  library(ncdf4)
})

ROOT_LOC <- "D:/Stage_JeremyG"
ROOT_SRV <- "S:/Projets/stage_JeremyG"

SRC_ROOT    <- file.path(ROOT_SRV, "3-Donnees", "5-DIGITALIS", "3-DIGITALIS_daily_DS_CHELSA")
DST         <- file.path(ROOT_LOC, "ECE_data", "6-DIGI_CHEL_1km")
COMPRESSION <- 5
CRS_NATIVE  <- "EPSG:2154"   # Lambert-93 verifie (res=1000m, meme grille que DIGI_SAF)

# Facteurs de conversion (verifies sur fichiers 1984)
FACTEUR_TEMP <- 1   ; OFFSET_TEMP <- 0          # deja en degC (verifie : -6.76 / 16.81)
FACTEUR_PREC <- 1                               # deja en mm   (verifie :  0    /  2.99)

if (!dir.exists(DST)) dir.create(DST, recursive = TRUE)

# ==============================================================================
# UTILITAIRES
# ==============================================================================

parse_date_ds <- function(nom) {
  # Format attendu : {varname}_DS_{YYYYMMDD}.tif
  date_str <- sub(".*_(\\d{8})\\.tif$", "\\1", nom)
  tryCatch(as.Date(date_str, format = "%Y%m%d"), error = function(e) NA)
}

ecrire_nc_safe <- function(r, f_nc, varname, unit, longname, compression) {
  # NORMALISATION AXE TEMPS (2026-06-08 : fusion des Correction_dates_*) : fichier annuel
  # -> axe journalier propre Jan1 + 0..(nt-1), annee deduite du nom ..._YYYY.nc. Garde-fou nlyr>=360.
  .an_nc <- suppressWarnings(as.integer(sub(".*_(\\d{4})\\.nc$", "\\1", basename(f_nc))))
  if (!is.na(.an_nc) && terra::nlyr(r) >= 360L)
    terra::time(r) <- as.Date(sprintf("%d-01-01", .an_nc)) + 0:(terra::nlyr(r) - 1L)
  f_tmp <- paste0(f_nc, ".tmp.nc")
  if (file.exists(f_tmp)) file.remove(f_tmp)
  tryCatch({
    writeCDF(r, f_tmp, varname = varname, unit = unit,
             longname = longname, compression = compression, overwrite = TRUE)
    file.rename(f_tmp, f_nc)
    TRUE
  }, error = function(e) {
    if (file.exists(f_tmp)) file.remove(f_tmp)
    cat(sprintf("  ERREUR ecriture %s : %s\n", basename(f_nc), conditionMessage(e)))
    FALSE
  })
}

VARS <- list(
  list(prefixe_tif = "prec",   prefixe_nc = "DIGI_CHEL_prec",
       varname = "prec", unit = "mm",   longname = "Daily precipitation DIGI_CHEL",
       conv = function(r) r * FACTEUR_PREC),
  list(prefixe_tif = "tmax",   prefixe_nc = "DIGI_CHEL_tmax",
       varname = "tmax", unit = "degC", longname = "Daily max temperature DIGI_CHEL",
       conv = function(r) r * FACTEUR_TEMP + OFFSET_TEMP),
  list(prefixe_tif = "tmin",   prefixe_nc = "DIGI_CHEL_tmin",
       varname = "tmin", unit = "degC", longname = "Daily min temperature DIGI_CHEL",
       conv = function(r) r * FACTEUR_TEMP + OFFSET_TEMP)
)

# ==============================================================================
# TEMPLATE WGS84 : calcule une seule fois -> grille coherente pour tous les jours
# ==============================================================================

template_wgs84 <- NULL

get_template <- function() {
  if (!is.null(template_wgs84)) return(template_wgs84)
  annees <- sort(list.dirs(SRC_ROOT, full.names = FALSE, recursive = FALSE))
  annees <- annees[grepl("^\\d{4}$", annees)]

  # Priorite : fichier L93 (projete) pour avoir la resolution 1km exacte apres reprojection.
  # Les fichiers prec <= 1989 sont en WGS84 natif -> on cherche tmax ou tmin en premier.
  for (an in annees) {
    fics <- list.files(file.path(SRC_ROOT, an), pattern = "\\.tif$", full.names = TRUE)
    for (f in fics) {
      r <- tryCatch(rast(f)[[1]], error = function(e) NULL)
      if (is.null(r)) next
      if (!is.lonlat(r)) {
        if (is.na(crs(r)) || nchar(crs(r)) == 0) crs(r) <- CRS_NATIVE
        template_wgs84 <<- project(r, "EPSG:4326", method = "bilinear")
        cat(sprintf("  Template WGS84 (depuis L93 %s) : %d x %d cellules (res ~%.5f deg)\n",
                    basename(f), nrow(template_wgs84), ncol(template_wgs84),
                    mean(res(template_wgs84))))
        return(template_wgs84)
      }
    }
  }

  # Aucun fichier L93 : utiliser le premier fichier WGS84 directement
  for (an in annees) {
    f <- list.files(file.path(SRC_ROOT, an), pattern = "\\.tif$", full.names = TRUE)[1]
    if (!is.na(f) && file.exists(f)) {
      r <- tryCatch(rast(f)[[1]], error = function(e) NULL)
      if (!is.null(r)) {
        template_wgs84 <<- r
        cat(sprintf("  Template WGS84 (natif %s) : %d x %d cellules (res ~%.5f deg)\n",
                    basename(f), nrow(template_wgs84), ncol(template_wgs84),
                    mean(res(template_wgs84))))
        return(template_wgs84)
      }
    }
  }
  stop("Aucun fichier TIF source trouve pour calculer le template WGS84")
}

# ==============================================================================
# DIAGNOSTIC
# ==============================================================================

cat("=== DIAGNOSTIC DIGI_CHEL ===\n\n")

annees_src <- sort(list.dirs(SRC_ROOT, full.names = FALSE, recursive = FALSE))
annees_src <- annees_src[grepl("^\\d{4}$", annees_src)]
cat(sprintf("  Dossiers annees source : %d  (%s - %s)\n",
            length(annees_src), annees_src[1], annees_src[length(annees_src)]))

for (v in VARS) {
  f_all   <- unlist(lapply(annees_src, function(an)
    list.files(file.path(SRC_ROOT, an),
               pattern = sprintf("^%s_DS_\\d{8}\\.tif$", v$prefixe_tif),
               full.names = TRUE)))
  annees  <- sort(unique(year(as.Date(sub(".*_(\\d{8})\\.tif$", "\\1",
                                         basename(f_all)), format = "%Y%m%d"))))
  presents  <- file.exists(file.path(DST, sprintf("%s_%d.nc", v$prefixe_nc, annees)))
  manquants <- annees[!presents]
  cat(sprintf("  %-10s : %d/%d annees presentes | %d TIF sources",
              v$varname, sum(presents), length(annees), length(f_all)))
  if (length(manquants) > 0)
    cat(sprintf("\n             MANQUANTS : %s", paste(manquants, collapse = ", ")))
  cat("\n")
}

n_total <- length(list.files(DST, pattern = "\\.nc$"))
taille  <- sum(file.size(list.files(DST, pattern = "\\.nc$", full.names = TRUE))) / 1e9
cat(sprintf("\n  Destination : %d fichiers | %.1f Go\n\n", n_total, taille))

# ==============================================================================
# CONVERSION (fichiers manquants uniquement)
# ==============================================================================

cat("=== CONVERSION DIGI_CHEL ===\n\n")

tmpl <- get_template()
nlon <- ncol(tmpl); nlat <- nrow(tmpl)
lon_vals <- xFromCol(tmpl, 1:nlon)
lat_vals <- yFromRow(tmpl, 1:nlat)

t0_global <- Sys.time()

for (v in VARS) {
  cat(sprintf("\n--- Variable : %s ---\n", v$varname))

  # Lister tous les TIF sources et leurs dates
  f_all <- unlist(lapply(annees_src, function(an)
    list.files(file.path(SRC_ROOT, an),
               pattern = sprintf("^%s_DS_\\d{8}\\.tif$", v$prefixe_tif),
               full.names = TRUE)))
  dates  <- as.Date(sub(".*_(\\d{8})\\.tif$", "\\1", basename(f_all)), format = "%Y%m%d")
  valides <- !is.na(dates)
  f_all <- f_all[valides]; dates <- dates[valides]
  annees <- sort(unique(year(dates)))

  # Recalcul cible : si ANNEES_CIBLE est defini AVANT source(), ne (re)convertir
  # que ces annees-la (ex. recalcul cible 2022). Sinon : toutes (comportement normal).
  if (exists("ANNEES_CIBLE")) annees <- annees[annees %in% ANNEES_CIBLE]

  manquants <- annees[!file.exists(
    file.path(DST, sprintf("%s_%d.nc", v$prefixe_nc, annees))
  )]

  if (length(manquants) == 0) {
    cat(sprintf("  %s : complet, rien a faire\n", v$varname)); next
  }

  cat(sprintf("  %d annees a produire : %s\n",
              length(manquants), paste(manquants, collapse = ", ")))

  t0_var <- Sys.time()

  for (an in manquants) {
    f_nc  <- file.path(DST, sprintf("%s_%d.nc", v$prefixe_nc, an))
    f_tmp <- paste0(f_nc, ".tmp.nc")
    if (file.exists(f_tmp)) file.remove(f_tmp)

    idx  <- which(year(dates) == an)
    f_an <- f_all[idx[order(dates[idx])]]
    d_an <- sort(dates[idx])

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
        # Assigner L93 seulement si le fichier est projete et sans tag CRS
        if (!is.lonlat(r_i) && (is.na(crs(r_i)) || nchar(crs(r_i)) == 0))
          crs(r_i) <- CRS_NATIVE
        # project() gere les deux cas : L93->WGS84 et resampling WGS84->WGS84
        r_i <- project(r_i, tmpl, method = "bilinear")
        r_i <- v$conv(r_i)                                  # conversion unites
        vals <- t(as.matrix(r_i, wide = TRUE))
        ncvar_put(nc_out, v$varname, vals,
                  start = c(1L, 1L, i), count = c(nlon, nlat, 1L))
        rm(r_i, vals)
        if (i %% 30L == 0L) gc()
      }

      nc_close(nc_out); nc_out <- NULL
      file.rename(f_tmp, f_nc)
      cat(sprintf(" OK (%.0f Mo)\n", file.size(f_nc) / 1e6))
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

  dur <- as.numeric(difftime(Sys.time(), t0_var, units = "secs"))
  cat(sprintf("  -> %s termine en %.0f sec (%.1f min)\n", v$varname, dur, dur / 60))
}

dur_total <- as.numeric(difftime(Sys.time(), t0_global, units = "secs"))
cat(sprintf("\n=== TERMINE en %.0f sec (%.1f min) ===\n", dur_total, dur_total / 60))
