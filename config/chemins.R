# ==============================================================================
# config/chemins.R - Racines des chemins de tout le pipeline (hors module 02)
# ------------------------------------------------------------------------------
# Source par chaque script (ligne "if (!exists("DEPOT")) source(...)" en tete).
# Lancer les scripts DEPUIS LA RACINE DU DEPOT, ou definir ECE_DEPOT :
#   setwd("C:/chemin/vers/ece-mortalite-foret")
#   source("R/04_indices_ece/1-ECE_EOBS.R")
#
# Seules les RACINES sont configurables. Sous chaque racine, les scripts gardent
# l'arborescence du projet telle qu'elle etait au moment des calculs (juin-juillet
# 2026) : voir docs/pipeline.md, section "Arborescence attendue des donnees".
#
# Variables d'environnement reconnues (toutes facultatives) :
#   ECE_DEPOT          racine du depot                    (defaut : repertoire courant)
#   ECE_NAS_ROOT       racine contenant Projets/ et BD_SIG/ (defaut : S: sinon /Volumes/_donnees)
#   ECE_LOCAL_ROOT     disque local rapide de la machine de calcul
#                      (defaut : D:/Stage_JeremyG, sinon C:/Stage_JeremyG)
#   ECE_CLIMPACT_DIR   dossier climpact-master MODIFIE (cf. third_party/climpact/README.md)
#   ECE_MASQUE_FRANCE  GeoPackage France_GADM_L0.gpkg (non redistribue, cf. R/01_sources)
#   ECE_PYTHON         interpreteur Python avec netCDF4 (helpers de fusion)
#
# Effet de bord nul : ne cree aucun dossier, ne lit aucune donnee. ASCII pur.
# ==============================================================================

.env_ou <- function(var, defaut) {
  v <- Sys.getenv(var, unset = "")
  if (nzchar(v)) v else defaut
}

DEPOT <- normalizePath(.env_ou("ECE_DEPOT", getwd()), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(DEPOT, "config", "chemins.R")))
  stop("config/chemins.R introuvable sous '", DEPOT, "'. Lancer les scripts depuis ",
       "la racine du depot (setwd) ou definir la variable d'environnement ECE_DEPOT.")

# Racine du stockage partage : contient Projets/stage_JeremyG/ et BD_SIG/
.PFX <- .env_ou("ECE_NAS_ROOT", if (dir.exists("S:/Projets")) "S:" else "/Volumes/_donnees")

# Projet : 3-Donnees/, 5-Resultats/, ECE_data/
PROJET <- file.path(.PFX, "Projets", "stage_JeremyG")

# Disque local rapide (NetCDF annuels formates, fusions climpact, temporaires)
LOCAL_ROOT <- .env_ou("ECE_LOCAL_ROOT",
                      if (dir.exists("D:/")) "D:/Stage_JeremyG" else "C:/Stage_JeremyG")

# Climpact 3.3.2 avec les modifications du projet (third_party/climpact)
CLIMPACT_RACINE <- .env_ou("ECE_CLIMPACT_DIR",
                           file.path(DEPOT, "third_party", "climpact", "climpact-master"))

# Masque France (GADM niveau 0), telecharge par R/01_sources/0-Telecharger_limites_France.R
MASQUE_FRANCE_GPKG <- .env_ou("ECE_MASQUE_FRANCE",
                              file.path(PROJET, "4-Travail_bis", "1-Bases_de_donnees",
                                        "3-Limites_geo", "France_GADM_L0.gpkg"))

# Python des helpers de fusion NetCDF (OSGeo4W sur la machine de calcul d'origine)
PYTHON_EXE <- .env_ou("ECE_PYTHON",
                      if (file.exists("C:/OSGeo4W64/bin/python.exe")) "C:/OSGeo4W64/bin/python.exe" else "python3")

message(sprintf("[config] DEPOT=%s | NAS=%s | LOCAL=%s", DEPOT, .PFX, LOCAL_ROOT))
