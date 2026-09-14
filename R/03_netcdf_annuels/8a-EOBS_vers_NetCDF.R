# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
suppressPackageStartupMessages({
  library(terra)
  library(lubridate)
  library(sf)
  library(rnaturalearth)
})

ROOT_LOC <- LOCAL_ROOT
ROOT_SRV <- PROJET

SRC_EOBS  <- file.path(ROOT_SRV, "3-Donnees", "3-E_OBS", "2-1950_2024_EOBS_FR")
DST_EOBS  <- file.path(ROOT_LOC, "ECE_data", "1-EOBS_11km")

COMPRESSION    <- 5
DATE_ORIG_EOBS <- as.Date("1950-01-01")

if (!dir.exists(DST_EOBS)) dir.create(DST_EOBS, recursive = TRUE)

rtime_block <- function(nom, expr) {
  cat(sprintf("[%s] DEBUT : %s\n", format(Sys.time(), "%H:%M:%S"), nom))
  t0 <- Sys.time()
  force(expr)
  dur <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("[%s] FIN   : %s (%.1f sec / %.1f min)\n\n",
              format(Sys.time(), "%H:%M:%S"), nom, dur, dur/60))
}

ecrire_nc_safe <- function(r, f_nc, varname, unit, longname, compression) {
  # NORMALISATION AXE TEMPS (2026-06-08 : fusion des Correction_dates_*) : fichier annuel
  # -> axe journalier propre Jan1 + 0..(nt-1), annee deduite du nom ..._YYYY.nc. terra ecrit
  # alors un temps CF correct -> rend les scripts Correction_dates_* inutiles. Garde-fou nlyr>=360.
  .an_nc <- suppressWarnings(as.integer(sub(".*_(\\d{4})\\.nc$", "\\1", basename(f_nc))))
  if (!is.na(.an_nc) && terra::nlyr(r) >= 360L)
    terra::time(r) <- as.Date(sprintf("%d-01-01", .an_nc)) + 0:(terra::nlyr(r) - 1L)
  f_tmp <- paste0(f_nc, ".tmp.nc")
  if (file.exists(f_tmp)) file.remove(f_tmp)
  tryCatch({
    writeCDF(r, f_tmp, varname = varname, unit = unit,
             longname = longname, compression = compression, overwrite = TRUE)
    file.rename(f_tmp, f_nc)
    return(TRUE)
  }, error = function(e) {
    if (file.exists(f_tmp)) file.remove(f_tmp)
    cat(sprintf("  ERREUR ecriture %s : %s\n", basename(f_nc), conditionMessage(e)))
    return(FALSE)
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# BASE 1 - E-OBS : crop France + split annuel
# CRS : WGS84 (EPSG:4326) | Resolution : ~11 km
# Variables : rr (prec), tn (tmin), tx (tmax)
# ──────────────────────────────────────────────────────────────────────────────

rtime_block("BASE 1 - E-OBS split annuel", {

  france_wgs <- sf::st_transform(
    rnaturalearth::ne_countries(scale = "medium", country = "France",
                                returnclass = "sf"), 4326)
  emprise_fr <- ext(terra::vect(france_wgs)) + 0.5

  vars_eobs <- list(
    list(fichier = "rr_ens_mean_0.1deg_reg_v31.0e.nc",
         varname = "prec", unit = "mm",
         longname = "Daily precipitation E-OBS"),
    list(fichier = "tn_ens_mean_0.1deg_reg_v31.0e.nc",
         varname = "tmin", unit = "degC",
         longname = "Daily min temperature E-OBS"),
    list(fichier = "tx_ens_mean_0.1deg_reg_v31.0e.nc",
         varname = "tmax", unit = "degC",
         longname = "Daily max temperature E-OBS")
  )

  for (v in vars_eobs) {
    f_src <- file.path(SRC_EOBS, v$fichier)
    if (!file.exists(f_src)) {
      cat(sprintf("  ABSENT : %s\n", v$fichier)); next
    }

    cat(sprintf("\n  Traitement %s...\n", v$varname))
    r_all     <- rast(f_src)
    dates_all <- DATE_ORIG_EOBS + 0:(nlyr(r_all) - 1)
    r_fr      <- crop(r_all, emprise_fr)

    for (an in 1961:2024) {
      f_nc <- file.path(DST_EOBS, sprintf("EOBS_%s_%d.nc", v$varname, an))
      if (file.exists(f_nc)) {
        cat(sprintf("  SKIP EOBS_%s_%d\n", v$varname, an)); next
      }

      idx <- which(year(dates_all) == an)
      if (length(idx) == 0) next

      r_an      <- r_fr[[idx]]
      time(r_an) <- dates_all[idx]

      ok <- ecrire_nc_safe(r_an, f_nc, v$varname, v$unit, v$longname, COMPRESSION)
      cat(sprintf("  %s %s %d %s\n", if(ok) "OK" else "ERR", v$varname, an,
                  if(ok) sprintf("%.0f Mo", file.size(f_nc)/1e6) else ""))
      rm(r_an); gc()
    }
    rm(r_fr, r_all); gc()
  }
})

f_nc <- list.files(DST_EOBS, pattern = "\\.nc$", full.names = TRUE)
cat(sprintf("\nBILAN EOBS : %d fichiers | %.1f Go\n",
            length(f_nc), sum(file.size(f_nc)) / 1e9))
