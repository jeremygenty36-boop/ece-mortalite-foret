# ==============================================================================
# TELECHARGEMENT DES LIMITES ADMINISTRATIVES - FRANCE (mainland + Corse)
# Source : GADM v4.1 via package geodata
# Sortie  : France_GADM_L0.gpkg  (polygone national, WGS84)
# A lancer UNE SEULE FOIS
# ==============================================================================

library(terra)

if (!requireNamespace("geodata", quietly=TRUE)) install.packages("geodata")
library(geodata)

OUT_DIR <- file.path("S:", "Projets", "stage_JeremyG", "4-Travail", "3-Limites_geo")
f_out   <- file.path(OUT_DIR, "France_GADM_L0.gpkg")

if (file.exists(f_out)) {
  cat("Deja present :", f_out, "\n")
} else {
  cat("Telechargement GADM France niveau 0...\n")
  france <- tryCatch(
    gadm("FRA", level=0, path=OUT_DIR),
    error=function(e) { cat("ERREUR :", conditionMessage(e), "\n"); NULL })

  if (!is.null(france)) {
    writeVector(france, f_out, overwrite=TRUE)
    cat("Sauvegarde OK :", f_out, "\n")
    cat("  CRS    :", crs(france, proj=TRUE), "\n")
    cat("  Emprise:", paste(round(as.vector(ext(france)), 3), collapse=" / "), "\n")
    cat("  Surf.  : ~", round(expanse(france, unit="km")/1000), "milliers km2\n")
  }
}
