# ======================================================================
# config_chemins.R - Chemins du pipeline de downscaling (a ADAPTER)
# ----------------------------------------------------------------------
# Source de verite unique des chemins d'entree/sortie, sourcee par les 3
# scripts de production. ADAPTER a votre environnement via :
#   - la variable d'environnement DIGI_ROOT (racine des donnees), ou
#   - en editant RACINE ci-dessous.
# La sortie va dans DIGI_OUT (env) ou <RACINE>/sorties_downscaling par defaut.
#
# ASCII pur. Aucun effet de bord (ne cree pas de dossier, ne lit rien).
# Voir docs/sources_donnees.md pour l'origine et le format des donnees.
# ======================================================================

RACINE <- Sys.getenv("DIGI_ROOT", unset = "")
if (!nzchar(RACINE)) {
  # A defaut de DIGI_ROOT, editer la ligne suivante avec votre racine locale :
  RACINE <- ""   # ex. "/data/downscaling" ou "D:/donnees"
}
if (!nzchar(RACINE))
  stop("Definir la variable d'environnement DIGI_ROOT (racine des donnees) ",
       "ou editer RACINE dans config_chemins.R")

SORTIE <- Sys.getenv("DIGI_OUT", unset = file.path(RACINE, "sorties_downscaling"))

# ======================================================================
# 1. DIGITALIS - climatologie mensuelle 1 km L93 (cible de la correction)
#    Motifs de fichiers : {prec,tmin,tmax}_ANNEE_MOIS.tif
#    (prec encode en 0.1 mm ; tmin/tmax en 0.1 degC : /10 dans les scripts)
# ======================================================================
DIGI_PREC <- file.path(RACINE, "DIGITALIS", "prec")
DIGI_TMIN <- file.path(RACINE, "DIGITALIS", "tmin")
DIGI_TMAX <- file.path(RACINE, "DIGITALIS", "tmax")

# Variantes "miroir local rapide" : specifiques au serveur d'origine (disque
# local vs reseau). Sans objet ici -> memes chemins.
DIGI_PREC_LOCAL <- DIGI_PREC
DIGI_TMIN_LOCAL <- DIGI_TMIN
DIGI_TMAX_LOCAL <- DIGI_TMAX

# ======================================================================
# 2. Sources brutes a downscaler
# ======================================================================
SAFRAN_CSV_DIR <- file.path(RACINE, "SAFRAN")   # QUOT_SIM2_YYYY-YYYY.csv[.gz]
EOBS_RESEAU    <- file.path(RACINE, "E-OBS")     # rr/tn/tx_ens_mean_0.1deg_*.nc
EOBS_DIR       <- EOBS_RESEAU
CHELSA_PR      <- file.path(RACINE, "CHELSA", "pr")       # CHELSA_pr_DD_MM_YYYY_V.2.1.tif
CHELSA_TASMIN  <- file.path(RACINE, "CHELSA", "tasmin")
CHELSA_TASMAX  <- file.path(RACINE, "CHELSA", "tasmax")

# ======================================================================
# 3. Masque / gabarit spatial (grille cible 1 km L93)
# ======================================================================
FRANCE_SHP      <- file.path(RACINE, "masque", "FRANCE.shp")
GABARIT_1KM_DIR <- file.path(RACINE, "gabarit_1km")   # >= 1 TIF 1 km L93 de reference

# ======================================================================
# 4. Sorties (un dossier par base)
# ======================================================================
OUT_SAFRAN   <- file.path(SORTIE, "SAFRAN_DS")
OUT_CHELSA   <- file.path(SORTIE, "CHELSA_DS")
OUT_EOBS     <- file.path(SORTIE, "EOBS_DS")
CACHE_SAFRAN <- file.path(SORTIE, "cache_SAFRAN")

message(sprintf("[config] RACINE = %s | SORTIE = %s", RACINE, SORTIE))
