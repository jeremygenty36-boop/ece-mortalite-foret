# source("R/06_modele/0N2-Session_France_binaire_complet.R")   # depuis la racine du depot
# =============================================================================
# FRANCE -- MODELE BINAIRE COMPLET (placette morte si >=1 arbre mort), n=1000
#
#   Clone de 0E-Session_France_complet.R, en MODE_REPONSE="binaire".
#   NE LANCER QU'APRES validation du test 0N (n=100) : ce run est long.
#   Deux modeles sequentiels + figures/tableaux, RUN_TAG suffixe _binaire :
#     - Mortalite_2015-2023_Peuplement_n1000_binaire
#     - Mortalite_2015-2023_r070_n1000_binaire
#   v1.1 : periode nommee 2015-2023 (les donnees s'arretent en 2023), CHE-C exclue
#   explicitement, et les deux modeles portent sur le MEME echantillon de placettes
#   (lignes completes pour les 6 ECE des 5 bases), y compris le modele peuplement.
#   Le run binomial existant n'est PAS ecrase (RUN_TAG different).
# =============================================================================

# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
.DIR <- file.path(DEPOT, "R", "06_modele")

.args <- commandArgs(trailingOnly = TRUE)
if (!exists("VARIANTE"))
  VARIANTE <- if (length(.args) >= 1L && nzchar(.args[1])) .args[1] else "standard"
.VARIANTES <- list(
  standard  = list(fichier = "IFN_placette.csv",           suffixe = ""),
  dominants = list(fichier = "IFN_placette_dominants.csv", suffixe = "_dominants"),
  domines   = list(fichier = "IFN_placette_domines.csv",   suffixe = "_domines"),
  pur080    = list(fichier = "IFN_placette_pur080.csv",    suffixe = "_pur080")
)
if (!VARIANTE %in% names(.VARIANTES)) stop("VARIANTE inconnue : '", VARIANTE, "'")
# .PFX : fourni par config/chemins.R
F_IFN <- file.path(.PFX, "Projets/stage_JeremyG/3-Donnees/6-IFN", .VARIANTES[[VARIANTE]]$fichier)
.SUF  <- .VARIANTES[[VARIANTE]]$suffixe
if (!file.exists(F_IFN)) stop("Base IFN absente : ", F_IFN)
cat(sprintf("\n>>> VARIANTE = %s | base = %s | suffixe = '%s'\n\n", VARIANTE, basename(F_IFN), .SUF))

# --- MODE binaire ------------------------------------------------------------
MODE_REPONSE <- "binaire"

# --- parametres (identiques a 0E-France) -------------------------------------
CAMPAGNE_MIN <- 2015L
CAMPAGNE_MAX <- 2023L
VAR_FIXES    <- c("pH", "G_ha_tot", "Gini", "c13_moy_sp", "prop_G")
COR_SEUIL    <- 0.70
N_ITER       <- 1000L
N_PARALLEL   <- 8L
FILTRE_GRECO <- NULL
# v1.1 : 5 bases de l'etude (CHE-C exclue) et echantillon commun aux deux modeles
BASES_EXCLUDE       <- "CHEDS"
ECHANTILLON_COMMUN  <- TRUE
INDICES_ECHANTILLON <- c("TXx", "TNn", "SPEI6", "WG10P", "HWN", "CWN")

.SCRIPTS_COMPLET <- c("1-Modele_mortalite_optimise.R",
                      "3-Tableaux/7-Tableau_synthese_modele.R",
                      "2-Figures/8-Figure_tableau_modele.R",
                      "2-Figures/20-Fig_RI_par_variable.R",
                      "2-Figures/22-Fig_synthese_IR_modele.R",
                      "2-Figures/9-Courbes_reponse.R",
                      "3-Tableaux/19-Tableau_effectifs_mortalite.R")

.lancer <- function(tag, indices, scripts) {
  cat("\n", strrep("*", 70), "\n  MODELE BINAIRE : ", tag, "\n",
      "  INDICES : ", if (length(indices) == 0L) "(aucun)" else paste(indices, collapse = ", "),
      "\n", strrep("*", 70), "\n\n", sep = "")
  RUN_TAG           <<- tag
  INDICES_AUTORISES <<- indices
  for (s in scripts) source(file.path(.DIR, s))
  rm(list = c("RUN_TAG", "INDICES_AUTORISES"), envir = .GlobalEnv)
  invisible(NULL)
}

t0 <- proc.time()
.lancer(paste0("Mortalite_2015-2023_Peuplement_n1000_binaire", .SUF), character(0), .SCRIPTS_COMPLET)
.lancer(paste0("Mortalite_2015-2023_r070_n1000_binaire", .SUF),
        c("TXx", "TNn", "SPEI6", "WG10P", "HWN", "CWN"), .SCRIPTS_COMPLET)
cat(strrep("=", 70), "\n",
    sprintf("  FRANCE BINAIRE : 2 modeles termines en %.0f min\n", (proc.time() - t0)[["elapsed"]] / 60),
    strrep("=", 70), "\n", sep = "")
