suppressPackageStartupMessages({
  library(terra)
})

DST_SAFRAN  <- "D:/Stage_JeremyG/ECE_data/2-SAFRAN_8km"
COMPRESSION <- 5

META <- list(
  tmax = list(unit = "degC", longname = "Daily max temperature SAFRAN"),
  tmin = list(unit = "degC", longname = "Daily min temperature SAFRAN"),
  prec = list(unit = "mm",   longname = "Daily total precipitation SAFRAN"),
  etp  = list(unit = "mm",   longname = "Daily ETP SAFRAN"),
  wg   = list(unit = "-",    longname = "Soil water root zone SAFRAN")
)

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
# BASE 2 - SAFRAN : reprojection NetCDF existants -> WGS84
# ──────────────────────────────────────────────────────────────────────────────

cat(sprintf("[%s] DEBUT reprojection SAFRAN\n", format(Sys.time(), "%H:%M:%S")))
t0 <- Sys.time()

f_list <- list.files(DST_SAFRAN, pattern = "^SAFRAN_.*\\.nc$", full.names = TRUE)
cat(sprintf("  %d fichiers NetCDF trouves\n\n", length(f_list)))

for (f in f_list) {
  nom <- basename(f)

  # Verifier si deja en WGS84
  r_meta <- rast(f, lyrs = 1)
  code   <- crs(r_meta, describe = TRUE)$code
  if (!is.na(code) && code == "4326") {
    cat(sprintf("  SKIP (deja WGS84) : %s\n", nom)); next
  }

  # Extraire le nom de variable depuis le nom de fichier : SAFRAN_tmax_2000.nc
  varname <- regmatches(nom, regexpr("(?<=SAFRAN_)[a-z]+(?=_\\d{4})", nom, perl = TRUE))
  if (length(varname) == 0 || !varname %in% names(META)) {
    cat(sprintf("  SKIP (variable inconnue) : %s\n", nom)); next
  }

  cat(sprintf("  -> %s ...", nom))
  r     <- rast(f)
  dates <- time(r)

  r_wgs <- project(r, "EPSG:4326", method = "bilinear")
  time(r_wgs) <- dates

  ok <- ecrire_nc_safe(r_wgs, f, varname,
                       META[[varname]]$unit,
                       META[[varname]]$longname,
                       COMPRESSION)
  cat(if(ok) sprintf(" OK (%.0f Mo)\n", file.size(f)/1e6) else " ERREUR\n")
  rm(r, r_wgs); gc()
}

dur <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("\n[%s] FIN reprojection SAFRAN (%.1f sec / %.1f min)\n",
            format(Sys.time(), "%H:%M:%S"), dur, dur/60))

f_nc <- list.files(DST_SAFRAN, pattern = "\\.nc$", full.names = TRUE)
cat(sprintf("BILAN SAFRAN : %d fichiers | %.1f Go\n",
            length(f_nc), sum(file.size(f_nc)) / 1e9))
