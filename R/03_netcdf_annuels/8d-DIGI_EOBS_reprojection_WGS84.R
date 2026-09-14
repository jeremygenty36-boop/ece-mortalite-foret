suppressPackageStartupMessages({
  library(terra)
})

DST_DIGI_EOBS <- "D:/Stage_JeremyG/ECE_data/4-DIGI_EOBS_1km"
COMPRESSION   <- 5

META <- list(
  prec = list(unit = "mm",   longname = "Daily precipitation DIGITALIS DS EOBS"),
  tmax = list(unit = "degC", longname = "Daily max temperature DIGITALIS DS EOBS"),
  tmin = list(unit = "degC", longname = "Daily min temperature DIGITALIS DS EOBS")
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
    # VALIDATION CONTENU (2026-06-08) : refuser une sortie degeneree (annee tout-NaN,
    # cf bug assemblage DIGI prec 1987/1994/1962 ecrit en NaN sans detection a la production).
    # Compare les cellules finies (1er et dernier jour) entree vs sortie ; si la sortie a
    # perdu l'essentiel des donnees -> echec (tmp supprime, original conserve).
    .fin <- function(rr) as.numeric(terra::global(rr, "notNA")[1, 1])
    .rt  <- terra::rast(f_tmp)
    .ni1 <- .fin(r[[1]]); .niN <- .fin(r[[terra::nlyr(r)]])
    .no1 <- .fin(.rt[[1]]); .noN <- .fin(.rt[[terra::nlyr(.rt)]])
    if ((.ni1 > 0 && (is.na(.no1) || .no1 < 0.5 * .ni1)) ||
        (.niN > 0 && (is.na(.noN) || .noN < 0.5 * .niN))) {
      if (file.exists(f_tmp)) file.remove(f_tmp)
      cat(sprintf("  [REFUS] %s : sortie degeneree (finies entree j1=%.0f jN=%.0f / sortie j1=%.0f jN=%.0f) -> NON ecrit\n",
                  basename(f_nc), .ni1, .niN, .no1, .noN))
      return(FALSE)
    }
    file.rename(f_tmp, f_nc)
    return(TRUE)
  }, error = function(e) {
    if (file.exists(f_tmp)) file.remove(f_tmp)
    cat(sprintf("  ERREUR ecriture %s : %s\n", basename(f_nc), conditionMessage(e)))
    return(FALSE)
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# BASE 4 - DIGITALIS DS EOBS : correction CRS + reprojection -> WGS84
# Les fichiers ont des coordonnees Lambert 93 (EPSG:2154) mais le CRS
# declare est WGS84 -> reassigner EPSG:2154 puis reprojeter en EPSG:4326
# ──────────────────────────────────────────────────────────────────────────────

cat(sprintf("[%s] DEBUT reprojection DIGI EOBS\n", format(Sys.time(), "%H:%M:%S")))
t0 <- Sys.time()

f_list <- list.files(DST_DIGI_EOBS, pattern = "^DIGI_EOBS_.*\\.nc$", full.names = TRUE)
cat(sprintf("  %d fichiers NetCDF trouves\n\n", length(f_list)))

for (f in f_list) {
  nom <- basename(f)

  # Verifier si deja correctement en WGS84 (etendue coherente en degres)
  r_meta <- rast(f, lyrs = 1)
  ex     <- as.vector(ext(r_meta))
  deja_wgs <- ex[1] >= -180 && ex[2] <= 180 && ex[3] >= -90 && ex[4] <= 90 &&
              max(abs(ex)) < 180
  if (deja_wgs) {
    cat(sprintf("  SKIP (deja WGS84) : %s\n", nom)); next
  }

  # Extraire le nom de variable : DIGI_EOBS_prec_1961.nc
  varname <- regmatches(nom, regexpr("(?<=DIGI_EOBS_)[a-z]+(?=_\\d{4})", nom, perl = TRUE))
  if (length(varname) == 0 || !varname %in% names(META)) {
    cat(sprintf("  SKIP (variable inconnue) : %s\n", nom)); next
  }

  cat(sprintf("  -> %s ...", nom))
  r     <- rast(f)
  dates <- time(r)

  # Etape 1 : reassigner le vrai CRS (coordonnees en metres Lambert 93)
  crs(r) <- "EPSG:2154"

  # Etape 2 : reprojeter en WGS84
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
cat(sprintf("\n[%s] FIN reprojection DIGI EOBS (%.1f sec / %.1f min)\n",
            format(Sys.time(), "%H:%M:%S"), dur, dur/60))

f_nc <- list.files(DST_DIGI_EOBS, pattern = "\\.nc$", full.names = TRUE)
cat(sprintf("BILAN DIGI EOBS : %d fichiers | %.1f Go\n",
            length(f_nc), sum(file.size(f_nc)) / 1e9))
