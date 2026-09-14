# ======================================================================
# Verification des donnees CHELSA telechargees
# Verifie : presence, taille minimale, et liste les manquants
# ======================================================================

library(terra)

PATH_OUT <- "S:/Projets/stage_JeremyG/3-Donnees/2-CHELSA/3-1960_2026_CHELSA_FR/"

DATE_DEBUT       <- as.Date("1979-01-01")
DATE_FIN         <- as.Date("2025-12-31")
DATE_DEBUT_PR    <- as.Date("1979-01-01")
ANNEE_BASCULE_PR <- 2021
TAILLE_MIN       <- 50000   # 50 KB minimum (fichier France crop valide)

# --- Construction de la liste attendue --------------------------------
dates_all <- seq(DATE_DEBUT, DATE_FIN, by = "day")
dd_vec    <- format(dates_all, "%d")
mm_vec    <- format(dates_all, "%m")
yyyy_vec  <- format(dates_all, "%Y")
an_vec    <- as.integer(yyyy_vec)

# pr
idx_pr   <- dates_all >= DATE_DEBUT_PR
vdir_pr  <- ifelse(an_vec[idx_pr] < ANNEE_BASCULE_PR, "pr", "prec")
fname_pr <- sprintf("CHELSA_%s_%s_%s_%s_V.2.1.tif",
                    vdir_pr, dd_vec[idx_pr], mm_vec[idx_pr], yyyy_vec[idx_pr])
# le fichier de sortie est toujours dans pr/ avec prefixe pr ou prec
out_pr   <- file.path(PATH_OUT, "pr", fname_pr)

# tasmin / tasmax
make_expected <- function(vdir) {
  fname <- sprintf("CHELSA_%s_%s_%s_%s_V.2.1.tif", vdir, dd_vec, mm_vec, yyyy_vec)
  file.path(PATH_OUT, vdir, fname)
}
out_tasmin <- make_expected("tasmin")[dates_all >= DATE_DEBUT_PR]
out_tasmax <- make_expected("tasmax")[dates_all >= DATE_DEBUT_PR]

# --- Verification vectorisee ------------------------------------------
verif <- function(paths, label) {
  ex  <- file.exists(paths)
  sz  <- ifelse(ex, file.size(paths), 0L)
  ok  <- ex & sz >= TAILLE_MIN
  trop_petit <- ex & sz < TAILLE_MIN

  cat(sprintf("\n=== %s ===\n", label))
  cat(sprintf("  Attendus       : %d\n", length(paths)))
  cat(sprintf("  Presents OK    : %d\n", sum(ok)))
  cat(sprintf("  Manquants      : %d\n", sum(!ex)))
  cat(sprintf("  Trop petits    : %d  (< %d KB — probablement 404)\n",
              sum(trop_petit), TAILLE_MIN / 1000))

  manquants <- paths[!ok]
  list(ok = sum(ok), manquants = manquants, trop_petits = sum(trop_petit))
}

cat("Verification des donnees CHELSA...\n")
cat(sprintf("Periode : %s -> %s\n", DATE_DEBUT, DATE_FIN))

res_pr     <- verif(out_pr,     "pr     (1979-2025)")
res_tasmin <- verif(out_tasmin, "tasmin (1979-2025)")
res_tasmax <- verif(out_tasmax, "tasmax (1979-2025)")

total_attendu  <- length(out_pr) + length(out_tasmin) + length(out_tasmax)
total_ok       <- res_pr$ok + res_tasmin$ok + res_tasmax$ok
total_manquant <- length(res_pr$manquants) + length(res_tasmin$manquants) + length(res_tasmax$manquants)

cat(sprintf("\n=== BILAN GLOBAL ===\n"))
cat(sprintf("  Total attendu  : %d\n", total_attendu))
cat(sprintf("  Total OK       : %d  (%.1f%%)\n", total_ok, 100 * total_ok / total_attendu))
cat(sprintf("  Total manquant : %d  (%.1f%%)\n", total_manquant, 100 * total_manquant / total_attendu))

# --- Sauvegarde de la liste des manquants -----------------------------
tous_manquants <- c(res_pr$manquants, res_tasmin$manquants, res_tasmax$manquants)

if (length(tous_manquants) > 0) {
  f_csv <- file.path(PATH_OUT, "manquants_CHELSA.csv")
  write.csv(data.frame(fichier = tous_manquants), f_csv, row.names = FALSE)
  cat(sprintf("\n  Liste des manquants sauvegardee : %s\n", f_csv))

  # Afficher les 20 premiers
  cat("\n  Premiers fichiers manquants :\n")
  cat(paste(" ", head(basename(tous_manquants), 20), collapse = "\n"), "\n")
  if (length(tous_manquants) > 20)
    cat(sprintf("  ... et %d autres (voir le CSV)\n", length(tous_manquants) - 20))
} else {
  cat("\n  Tout est present et valide !\n")
}

