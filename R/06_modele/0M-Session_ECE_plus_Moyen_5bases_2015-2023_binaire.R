# source("R/06_modele/0M-Session_ECE_plus_Moyen_5bases_2015-2023_binaire.R")   # depuis la racine du depot
# ==============================================================================
# 5 BASES : ECE + MOYENNES SAISONNIERES PAR BASE -- VERSION BINAIRE (mort_bin)
#   Clone de 0M-...2015-2023.R, en MODE_REPONSE="binaire".
#   Chaque base = ses 6 ECE + ses 6 moyennes (12 candidats), forward BIC.
#   5 bases distinctes (CHE-C exclue). RUN_TAG suffixe _binaire.
#
#   Prerequis : colonnes <MOY>_<base> deja dans IFN_placette.csv (script 3c).
#   Reglages identiques au run ECE binaire de reference.
# ==============================================================================
# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
.DIR <- file.path(DEPOT, "R", "06_modele")
# .PFX : fourni par config/chemins.R

MODE_REPONSE      <- "binaire"
RUN_TAG           <- "ECE_Moyen_5bases_2015-2023_binaire"
CAMPAGNE_MIN      <- 2015L
CAMPAGNE_MAX      <- 2023L
ECE_IND           <- c("TXx", "TNn", "SPEI6", "WG10P", "HWN", "CWN")
MOY_IND           <- c("Tmax_MAM", "Tmax_JJA", "Tmin_hiver", "Tmin_MAM", "BHC_MAM", "BHC_JJA")
INDICES_AUTORISES <- c(ECE_IND, MOY_IND)
VAR_FIXES         <- c("pH", "G_ha_tot", "Gini", "c13_moy_sp", "prop_G")
BASES             <- list(
  list(code = "EOB10", label = "EOB-10"),
  list(code = "SAF8",  label = "SAF-8"),
  list(code = "CHE1",  label = "CHE-1"),
  list(code = "EOBDS", label = "EOB-DS"),
  list(code = "SAFDS", label = "SAF-DS")
)
COR_SEUIL         <- 0.70
N_ITER            <- 1000L
N_PARALLEL        <- 8L

# --- garde-fou : les colonnes de moyennes par base doivent exister -----------
.f_ifn <- file.path(.PFX, "Projets/stage_JeremyG/3-Donnees/6-IFN/IFN_placette.csv")
.hdr   <- strsplit(readLines(.f_ifn, n = 1L), ";", fixed = TRUE)[[1]]
.attendu <- as.vector(outer(MOY_IND, vapply(BASES, `[[`, "", "code"), paste, sep = "_"))
.manque  <- setdiff(.attendu, .hdr)
if (length(.manque) > 0L)
  stop("Colonnes de moyennes par base ABSENTES de IFN_placette.csv (", length(.manque),
       ") : ", paste(head(.manque, 6), collapse = ", "), " ...\n",
       "  -> lancer d'abord 3-IFN/3c-Extraction_Moyennes_par_base.R")

source(file.path(.DIR, "1-Modele_mortalite_optimise.R"))
source(file.path(.DIR, "3-Tableaux/7-Tableau_synthese_modele.R"))
# Figures 32b / 64 / 65 / 66 / 67 : a lancer apres, pointees sur ce RUN_TAG binaire.
