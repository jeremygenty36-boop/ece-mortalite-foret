# source("S:/Projets/stage_JeremyG/4-Travail_bis/4-Modeles/1-Mortalite/3-Tableaux/19-Tableau_effectifs_mortalite.R")
# ============================================================================
# TABLEAU DES EFFECTIFS DE MORTALITE par espece, pour le jeu EXACTEMENT modelise.
#   Memes filtres que 1-Modele_mortalite_optimise.R :
#     Corse exclue (dep 2A/2B), FILTRE_GRECO (zone), campagne (CAMPAGNE_MIN/MAX),
#     presence == 1, prop_G >= PROP_G_MIN. Memes patterns d'especes (PINI = subsp. nigra).
#   Niveau placette ET niveau tige :
#     n_placettes | n_plac_mortalite | pct_plac_mortalite | n_tiges | n_morts | pct_tiges_mortes
#   Sorties : <run>/2-Syntheses/Effectifs_mortalite_<run>.csv  (+ .xlsx si openxlsx)
# ============================================================================
suppressPackageStartupMessages({ library(data.table) })

if (!exists(".PFX")) .PFX <- if (dir.exists("S:/Projets")) "S:" else "/Volumes/_donnees"
if (!exists("F_IFN"))   # surchargeable : ne PAS ecraser la base d'une variante
  F_IFN <- file.path(.PFX, "Projets/stage_JeremyG/3-Donnees/6-IFN/IFN_placette.csv")
if (!exists("RUN_TAG")) RUN_TAG <- "Mortalite_2015-2024_r070_n1000"
.VARIANTE_DIR <- if (grepl("_dominants$", RUN_TAG)) "dominants" else if (grepl("_domines$", RUN_TAG)) "domines" else if (grepl("_pur080$", RUN_TAG)) "pur080" else "standard"
DIRM_SY <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/5-Modeles", .VARIANTE_DIR, RUN_TAG, "2-Syntheses")
dir.create(DIRM_SY, showWarnings = FALSE, recursive = TRUE)
.run_suffix <- sub("^Mortalite_", "", RUN_TAG)
if (!exists("PROP_G_MIN")) PROP_G_MIN <- 0

# Zone : si FILTRE_GRECO non fourni par la session, deduit du RUN_TAG (sinon France entiere).
if (!exists("FILTRE_GRECO"))
  FILTRE_GRECO <- if (grepl("Montagne", RUN_TAG)) c("D","E","G","H","I") else
                  if (grepl("Plaine",   RUN_TAG)) c("A","B","C","F","J") else NULL
# Campagne : deduit du RUN_TAG (ex. 2015-2024) si non fournie.
if (!exists("CAMPAGNE_MIN") || !exists("CAMPAGNE_MAX")) {
  .yy <- regmatches(RUN_TAG, regexpr("[0-9]{4}-[0-9]{4}", RUN_TAG))
  if (length(.yy) == 1L) {
    if (!exists("CAMPAGNE_MIN")) CAMPAGNE_MIN <- as.integer(substr(.yy, 1, 4))
    if (!exists("CAMPAGNE_MAX")) CAMPAGNE_MAX <- as.integer(substr(.yy, 6, 9))
  }
}

# memes patterns que 1-Modele (ordre d'affichage = par effectif decroissant ensuite)
ESPECES <- c(
  QURO = "Quercus robur",            QUPE = "Quercus petraea",
  FASY = "Fagus sylvatica",          PISY = "Pinus sylvestris",
  PINI = "Pinus nigra subsp. nigra", ABAL = "Abies alba",
  PIAB = "Picea abies",              BEPE = "Betula pendula")

d <- fread(F_IFN, sep = ";")

# --- memes filtres que 1-Modele ---------------------------------------------
if ("dep" %in% names(d)) d <- d[!(dep %in% c("2A", "2B"))]                 # Corse exclue
if (exists("CAMPAGNE_MIN") && !is.null(CAMPAGNE_MIN) && "campagne" %in% names(d)) d <- d[campagne >= CAMPAGNE_MIN]
if (exists("CAMPAGNE_MAX") && !is.null(CAMPAGNE_MAX) && "campagne" %in% names(d)) d <- d[campagne <= CAMPAGNE_MAX]
if (exists("FILTRE_GRECO") && !is.null(FILTRE_GRECO) && "GRECO" %in% names(d)) d <- d[GRECO %in% FILTRE_GRECO]
d <- d[presence == 1L & prop_G >= PROP_G_MIN]

.zone <- if (exists("FILTRE_GRECO") && !is.null(FILTRE_GRECO)) paste(FILTRE_GRECO, collapse = "/") else "France (toutes zones)"

tab <- rbindlist(lapply(names(ESPECES), function(code) {
  s <- d[grepl(ESPECES[code], species_name, fixed = FALSE)]
  data.table(
    esp_code           = code,
    espece             = ESPECES[code],
    n_placettes        = nrow(s),
    n_plac_mortalite   = sum(s$n_mort_sp > 0, na.rm = TRUE),
    pct_plac_mortalite = if (nrow(s) > 0L) round(100 * mean(s$n_mort_sp > 0, na.rm = TRUE), 2) else NA_real_,
    n_tiges            = sum(s$n_tiges,   na.rm = TRUE),
    n_morts            = sum(s$n_mort_sp, na.rm = TRUE),
    pct_tiges_mortes   = if (sum(s$n_tiges, na.rm = TRUE) > 0) round(100 * sum(s$n_mort_sp, na.rm = TRUE) / sum(s$n_tiges, na.rm = TRUE), 2) else NA_real_
  )
}))
setorder(tab, -n_placettes)

# ligne ENSEMBLE (8 especes d'interet)
tot <- data.table(
  esp_code = "TOTAL", espece = "Ensemble 8 especes",
  n_placettes        = sum(tab$n_placettes),
  n_plac_mortalite   = sum(tab$n_plac_mortalite),
  pct_plac_mortalite = round(100 * sum(tab$n_plac_mortalite) / sum(tab$n_placettes), 2),
  n_tiges            = sum(tab$n_tiges),
  n_morts            = sum(tab$n_morts),
  pct_tiges_mortes   = round(100 * sum(tab$n_morts) / sum(tab$n_tiges), 2))
tab <- rbind(tab, tot)

fout <- file.path(DIRM_SY, sprintf("Effectifs_mortalite_%s.csv", .run_suffix))
fwrite(tab, fout, sep = ";")
cat(sprintf("Effectifs mortalite [zone : %s] -> %s\n", .zone, fout))
if (requireNamespace("openxlsx", quietly = TRUE))
  try(openxlsx::write.xlsx(tab, sub("\\.csv$", ".xlsx", fout)), silent = TRUE)
print(tab)
