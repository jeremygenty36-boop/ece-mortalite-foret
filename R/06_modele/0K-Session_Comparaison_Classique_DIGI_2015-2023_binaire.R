# source("R/06_modele/0K-Session_Comparaison_Classique_DIGI_2015-2023_binaire.R")   # depuis la racine du depot
# ==============================================================================
# CLIMAT MOYEN DIGITALIS (Classique) -- VERSION BINAIRE (mort_bin)
#   Clone de 0K-...2015-2023.R, en MODE_REPONSE="binaire".
#   6 moyennes saisonnieres DIGITALIS (symetrie avec les 6 ECE), base DIGI.
#   Sert a comparer ECE vs climat moyen dans le cadre BINAIRE, memes placettes.
#   RUN_TAG suffixe _binaire -> n'ecrase pas le run binomial.
# ==============================================================================
# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
.DIR <- file.path(DEPOT, "R", "06_modele")

MODE_REPONSE      <- "binaire"
RUN_TAG           <- "Comparaison_Classique_DIGI_2015-2023_binaire"
CAMPAGNE_MIN      <- 2015L
CAMPAGNE_MAX      <- 2023L
INDICES_AUTORISES <- c("BHC_MAM", "BHC_JJA", "Tmax_MAM", "Tmax_JJA", "Tmin_hiver", "Tmin_MAM")
VAR_FIXES         <- c("pH", "G_ha_tot", "Gini", "c13_moy_sp", "prop_G")
BASES             <- list(list(code = "DIGI", label = "DIGITALIS-v3/v4"))
COR_SEUIL         <- 0.70
N_ITER            <- 1000L
N_PARALLEL        <- 8L

source(file.path(.DIR, "1-Modele_mortalite_optimise.R"))
source(file.path(.DIR, "3-Tableaux/7-Tableau_synthese_modele.R"))
# Figures de comparaison ECE vs Classique (8K / 20K / 35b) : a lancer apres,
# une fois le run ECE binaire (r070_binaire) disponible, pour comparer les deux.
