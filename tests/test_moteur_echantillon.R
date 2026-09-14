# Lancer depuis la racine du depot : ECE_F_IFN=/chemin/IFN_placette.csv Rscript tests/test_moteur_echantillon.R
# Necessite data.table, MLmetrics. Environ 15 s (ABAL, 5 iterations).
# Test local du moteur v1.1 sur le vrai IFN_placette.csv (copie backup), version reduite
suppressPackageStartupMessages(library(data.table))
racine <- file.path(tempdir(), "nas"); dir.create(racine, showWarnings = FALSE)
Sys.setenv(ECE_NAS_ROOT = racine)
lancer <- function(tag, bases_only = NULL) {
  rm(list = intersect(c("BASES_ONLY", "BASES", "BASES_ECHANTILLON"), ls(.GlobalEnv)), envir = .GlobalEnv)
  assign("RUN_TAG", tag, .GlobalEnv)
  if (!is.null(bases_only)) assign("BASES_ONLY", bases_only, .GlobalEnv)
  source("R/06_modele/1-Modele_mortalite_optimise.R")
}
F_IFN <- Sys.getenv("ECE_F_IFN")   # chemin de IFN_placette.csv
if (!nzchar(F_IFN) || !file.exists(F_IFN)) stop("Definir ECE_F_IFN vers IFN_placette.csv")
MODE_REPONSE <- "binaire"; CAMPAGNE_MIN <- 2015L; CAMPAGNE_MAX <- 2023L
ESPECES_ONLY <- "ABAL"; BASES_EXCLUDE <- "CHEDS"; N_ITER <- 5L; N_PARALLEL <- 1L
lancer("TEST_complet")
lancer("TEST_CHE1_seul", bases_only = "CHE1")
rd <- function(tag, b) fread(file.path(racine, "Projets/stage_JeremyG/5-Resultats/5-Modeles/standard", tag, "1-Iterations", sprintf("Resultats_ABAL_%s.csv", b)))
b5 <- c("EOB10", "SAF8", "CHE1", "EOBDS", "SAFDS")
it <- rbindlist(lapply(b5, function(b) rd("TEST_complet", b)))
cat("\n--- partitions par base (n_cal, n_val, morts cal/val, iteration 1 a 5) ---\n")
print(dcast(it, iteration ~ base_code, value.var = "n_morts_cal"))
sig <- it[, .(sig = paste(n_cal, n_val, n_morts_cal, n_morts_val)), by = .(base_code, iteration)]
stopifnot(uniqueN(sig[, .(iteration, sig)]) == 5L)          # meme partition pour les 5 bases
seul <- rd("TEST_CHE1_seul", "CHE1")
stopifnot(identical(seul[, .(n_cal, n_morts_cal, n_morts_val)], rd("TEST_complet", "CHE1")[, .(n_cal, n_morts_cal, n_morts_val)]))
stopifnot(identical(seul$AUC, rd("TEST_complet", "CHE1")$AUC))
cat("TEST OK : memes placettes et memes partitions pour les 5 bases ; run filtre (CHE1 seul) identique au run complet\n")
