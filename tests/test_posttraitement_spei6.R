# Lancer depuis la racine du depot : Rscript tests/test_posttraitement_spei6.R
# Test synthetique : relance v1.1 (SPEI6 min) par-dessus des sorties v1.0 (SPEI6 moyenne)
suppressPackageStartupMessages({ library(terra); library(ncdf4) })
racine <- file.path(tempdir(), "nas"); unlink(racine, recursive = TRUE)
d <- file.path(racine, "Projets/stage_JeremyG/5-Resultats/3-ECE/1-ECE_1979-2024/1-EOBS_11km")
dir.create(file.path(d, "_avant_posttraitement"), recursive = TRUE)
gab <- rast(nrows = 4, ncols = 4, xmin = 2, xmax = 6, ymin = 44, ymax = 48, nlyrs = 46, crs = "EPSG:4326")
ecrire <- function(val, f, att = NULL) {
  r <- gab; values(r) <- val; time(r) <- as.Date(sprintf("%d-08-15", 1979:2024)); writeCDF(r, f, varname = "ECE_EOBS_SPEI6_MAR-AUG", overwrite = TRUE)
  if (!is.null(att)) { nc <- nc_open(f, write = TRUE); ncatt_put(nc, 0, "agregation_annuelle", att); nc_close(nc) }
}
f_main <- file.path(d, "ECE_EOBS_SPEI6_MAR-AUG.nc")
f_bk   <- file.path(d, "_avant_posttraitement", "ECE_EOBS_SPEI6_MAR-AUG.nc")
ecrire(-0.5, f_bk)            # sauvegarde v1.0 : moyenne, sans attribut
ecrire(-2.0, f_main, "min")   # nouveau calcul v1.1 : minimum, avec attribut
masque <- vect("POLYGON ((1 43, 7 43, 7 49, 1 49, 1 43))", crs = "EPSG:4326")
writeVector(masque, file.path(tempdir(), "masque.gpkg"), overwrite = TRUE)
Sys.setenv(ECE_NAS_ROOT = racine, ECE_MASQUE_FRANCE = file.path(tempdir(), "masque.gpkg"))
BASE <- "EOBS"; INDICES_PT <- "SPEI6"
source("R/04_indices_ece/11-ECE_POSTTRAITEMENT.R")
val <- unique(round(values(rast(f_main)), 3))
nc <- nc_open(f_main); att <- ncatt_get(nc, 0, "agregation_annuelle")$value; nc_close(nc)
corb <- list.files(file.path(d, "_corbeille"))
cat("\nRESULTAT : valeurs =", val, "| attribut =", att, "| corbeille =", corb, "\n")
stopifnot(all(val == -2), att == "min", length(corb) == 1)
# Deuxieme passage : idempotent, la nouvelle sauvegarde (min) est reutilisee, rien a la corbeille en plus
rm(DEPOT); source("R/04_indices_ece/11-ECE_POSTTRAITEMENT.R")
stopifnot(n_ok == 1L, all(unique(round(values(rast(f_main)), 3)) == -2), length(list.files(file.path(d, "_corbeille"))) == 1)
cat("TEST OK : sauvegarde perimee ecartee, SPEI6 min conserve, second passage idempotent\n")
