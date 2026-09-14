# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
suppressPackageStartupMessages({
  library(terra)
})

ROOT_LOC <- LOCAL_ROOT
ROOT_SRV <- PROJET

SRC_DIGI_EOBS <- file.path(ROOT_SRV, "3-Donnees", "5-DIGITALIS",
                            "5-DIGITALIS_daily_DS_EOBS_BCSD_bilinear")
DST_DIGI_EOBS <- file.path(ROOT_LOC, "ECE_data", "4-DIGI_EOBS_1km")

if (!dir.exists(DST_DIGI_EOBS)) dir.create(DST_DIGI_EOBS, recursive = TRUE)

rtime_block <- function(nom, expr) {
  cat(sprintf("[%s] DEBUT : %s\n", format(Sys.time(), "%H:%M:%S"), nom))
  t0 <- Sys.time()
  force(expr)
  dur <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("[%s] FIN   : %s (%.1f sec / %.1f min)\n\n",
              format(Sys.time(), "%H:%M:%S"), nom, dur, dur/60))
}

# ──────────────────────────────────────────────────────────────────────────────
# BASE 4 - DIGITALIS DS EOBS : copie locale depuis S:
# Source : deja NetCDF sur S:/.../5-DIGITALIS_daily_DS_EOBS_BCSD_bilinear/
# CRS source : WGS84 (herite de E-OBS) — pas de reprojection necessaire
# ──────────────────────────────────────────────────────────────────────────────

rtime_block("BASE 4 - DIGITALIS DS EOBS copie locale", {

  if (!dir.exists(SRC_DIGI_EOBS)) {
    cat("  ABSENT :", SRC_DIGI_EOBS, "\n")
    stop("Source DIGI EOBS introuvable.")
  }

  f_nc <- list.files(SRC_DIGI_EOBS, pattern = "\\.nc$", full.names = TRUE)
  cat(sprintf("  %d fichiers NC a copier...\n", length(f_nc)))

  n_ok <- 0; n_skip <- 0
  for (f in f_nc) {
    nom_src <- basename(f)
    an_m  <- regmatches(nom_src, regexpr("\\d{4}\\.nc$", nom_src))
    var_m <- if (grepl("^prec", nom_src)) "prec" else if (grepl("^tmax", nom_src)) "tmax" else "tmin"
    nom_dst <- if (length(an_m) > 0) sprintf("DIGI_EOBS_%s_%s", var_m, an_m) else nom_src
    dest <- file.path(DST_DIGI_EOBS, nom_dst)
    if (file.exists(dest)) { n_skip <- n_skip + 1; next }
    if (file.copy(f, dest)) n_ok <- n_ok + 1
  }
  cat(sprintf("  Copies : %d | Deja presents : %d\n", n_ok, n_skip))
})

f_nc <- list.files(DST_DIGI_EOBS, pattern = "\\.nc$", full.names = TRUE)
cat(sprintf("\nBILAN DIGI EOBS : %d fichiers | %.1f Go\n",
            length(f_nc), sum(file.size(f_nc)) / 1e9))
