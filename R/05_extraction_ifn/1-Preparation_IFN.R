# source("S:/Projets/stage_JeremyG/4-Travail/3-IFN/1-Preparation_IFN.R")
# ==============================================================================
# PREPARATION BASE IFN (dfCCRNv2) -- agregation a l'echelle de la placette
#
# Entrees :
#   dfArbresCCRNv2.csv    -- niveau arbre (1 197 990 lignes)
#   dfPlacettesCCRNv2.csv -- niveau placette (88 075 lignes) + coord L93
#   ph_ess2_L93.tif       -- raster pH sol France 1 km (BD_SIG, 2014)
#
# Traitement :
#   1. Lecture des trois CSV (arbres, placettes, GMN dates)
#   2. Filtre visite 1 uniquement + tous les arbres (dominants + domines)
#   3. Indicateur mortalite : mort = 1 si veget_gen %in% c("5","M"), 0 sinon
#   4. Agregation :
#        - par placette : G_ha_tot, c13_moy, Gini, n_tot, prop_mort, esp_maj
#        - par placette x espece cible : presence (0/1), G_ha_sp, prop_G,
#                                        n_tiges, n_mort_sp, prop_mort_sp,
#                                        c13_moy_sp
#   5. Jointure coord L93 + WGS84 + date_releve depuis GMN (IFN uniquement)
#   6. Extraction pH sol au centroide de chaque placette (raster L93)
#   7. Export format long (placette x 8 especes cibles) : IFN_placette.csv
#      --> 8 lignes par placette, presence=0 si espece absente
#
# USAGE : sourcer depuis CALCULUS ou Mac (chemins auto-detectes).
# ==============================================================================

library(data.table)
library(terra)

# --- CHEMINS ------------------------------------------------------------------
.PFX    <- if (dir.exists("S:/Projets")) "S:" else "/Volumes/_donnees"
DIR_IFN <- file.path(.PFX, "Projets/stage_JeremyG/3-Donnees/6-IFN/dfCCRNv2")
DIR_OUT <- file.path(.PFX, "Projets/stage_JeremyG/3-Donnees/6-IFN")
F_PH    <- file.path(.PFX, "BD_SIG/nutrition/France/2014/ph_ess2_L93.tif")

F_ARBRES    <- file.path(DIR_IFN, "dfArbresCCRNv2.csv")
F_PLACETTES <- file.path(DIR_IFN, "dfPlacettesCCRNv2.csv")
F_GMN       <- file.path(DIR_IFN, "Synthese_placettes_all_GMN.csv")

# 8 especes cibles (colonnes presence/absence par placette)
SP_CIBLES <- c("Quercus petraea",       "Pinus sylvestris", "Abies alba",
               "Quercus robur",         "Betula pendula",   "Picea abies",
               "Pinus nigra subsp. nigra", "Fagus sylvatica")
SP_CODES  <- c("QUPE",                 "PISY",             "ABAL",
               "QURO",                 "BEPE",             "PIAB",
               "PINI",                 "FASY")

cat(strrep("=", 70), "\n", sep="")
cat("  PREPARATION IFN -- visite 1, tous arbres, date_releve GMN\n")
cat(sprintf("  %s\n", format(Sys.time())))
cat(strrep("=", 70), "\n\n", sep="")

# --- 1. LECTURE ---------------------------------------------------------------
cat("Lecture des fichiers CSV...\n")
t0 <- proc.time()

arbres <- fread(F_ARBRES,    sep=";", encoding="Latin-1")
plac   <- fread(F_PLACETTES, sep=";", encoding="Latin-1")
gmn    <- fread(F_GMN,       sep=";", encoding="Latin-1",
                select = c("idp", "BD", "date"))

# Dates de releve IFN : une date par old_idp (format DD/MM/YYYY)
gmn_dates <- unique(gmn[BD == "IFN", .(old_idp = as.character(idp), date_releve = date)])

cat(sprintf("  Arbres    : %d lignes, %d colonnes\n", nrow(arbres), ncol(arbres)))
cat(sprintf("  Placettes : %d lignes, %d colonnes\n", nrow(plac),   ncol(plac)))
cat(sprintf("  GMN dates : %d placettes IFN avec date exacte\n", nrow(gmn_dates)))
cat(sprintf("  Lecture : %.1f s\n\n", (proc.time()-t0)[["elapsed"]]))

# --- 2. FILTRE VISITE 1 + TOUS LES ARBRES -------------------------------------
# Visite 1 UNIQUEMENT (decision avec l'encadrement) : effectifs suffisants, et
# inclure la 2e visite introduirait de la non-independance / un biais (une meme
# placette comptee deux fois). -> on modelise l'etat observe au 1er releve.
# Pas de filtre sur statut_indiv : dominants + domines
tous  <- arbres[visite == 1]
n_dom <- sum(tous$statut_indiv == "dominant")
n_sup <- sum(tous$statut_indiv == "suppressed")
cat(sprintf("Visite 1 : %d arbres (sur %d total, %.1f%% retenus)\n",
            nrow(tous), nrow(arbres), 100 * nrow(tous) / nrow(arbres)))
cat(sprintf("  dont dominants : %d (%.1f%%) | domines : %d (%.1f%%)\n\n",
            n_dom, 100 * n_dom / nrow(tous),
            n_sup, 100 * n_sup / nrow(tous)))

# --- 3. INDICATEUR MORTALITE --------------------------------------------------
# veget_gen : etat de l'arbre AU RELEVE. En visite 1 -> 0=vivant, 5=mort sur pied.
# Le code M (mort inter-visite) n'existe qu'en visite 2 (verifie sur donnees
# completes le 2026-06-11 : 0 ligne M en visite 1), donc ici mort == (veget_gen=5).
# "M" est conserve dans le test (sans effet en v1) par robustesse.
# mort = 1 (arbre mort sur pied), mort = 0 (arbre vivant)
tous[, mort := as.integer(veget_gen %in% c("5", "M"))]
cat(sprintf("Mortalite : %d morts / %d arbres (%.1f%%)\n\n",
            sum(tous$mort), nrow(tous), 100 * mean(tous$mort)))

# --- 4. AGREGATION ------------------------------------------------------------
cat("Agregation par placette...\n")

# 4a. Metriques placette (Gini_c13 = peuplement entier, recupere tel quel)
agg_plac <- tous[, .(
  n_tot    = .N,
  n_mort   = sum(mort),
  G_ha_tot = sum(ba_ha_indiv, na.rm=TRUE),
  c13_moy  = mean(c13, na.rm=TRUE),
  Gini     = first(Gini_c13)
), by = idp]
agg_plac[, prop_mort := n_mort / n_tot]

# 4b. Surface terriere + mortalite + c13 moyen par essence par placette
agg_sp <- tous[, .(
  G_ha_sp    = sum(ba_ha_indiv_vivant, na.rm=TRUE),
  n_tiges    = .N,
  n_mort_sp  = sum(mort),
  c13_moy_sp = mean(c13, na.rm=TRUE)
), by = .(idp, species_name)]
agg_sp[, prop_mort_sp := n_mort_sp / n_tiges]

# Proportion de la surface terriere de l'essence dans la placette
agg_sp <- merge(agg_sp, agg_plac[, .(idp, G_ha_tot)], by="idp")
agg_sp[, prop_G := fifelse(G_ha_tot > 0, G_ha_sp / G_ha_tot, NA_real_)]
agg_sp[, G_ha_tot := NULL]

# Exclure les placettes avec G_ha_tot = 0 (ba_ha_indiv_vivant absent ou nul)
n_excl <- sum(agg_plac$G_ha_tot == 0, na.rm=TRUE)
if (n_excl > 0) {
  cat(sprintf("  Exclusion : %d placettes avec G_ha_tot = 0\n", n_excl))
  agg_plac <- agg_plac[G_ha_tot > 0]
  agg_sp   <- agg_sp[!is.na(prop_G)]
}

# Essence majoritaire (plus grande G_ha) par placette
esp_maj <- agg_sp[, .SD[which.max(G_ha_sp)], by=idp][, .(idp, esp_maj=species_name)]
agg_plac <- merge(agg_plac, esp_maj, by="idp", all.x=TRUE)

cat(sprintf("  Placettes avec >= 1 arbre : %d\n", nrow(agg_plac)))
cat(sprintf("  Essences representees     : %d\n\n", uniqueN(agg_sp$species_name)))


# --- 5. COORDONNEES L93 + CONVERSION WGS84 ------------------------------------
cat("Jointure coordonnees et conversion L93 -> WGS84...\n")

coord_cols <- c("idp", "campagne", "xl", "yl", "GRECO", "NOM", "dep", "nom_biogeo", "biogeo", "old_idp")
coord_cols <- coord_cols[coord_cols %in% names(plac)]
plac_coord <- plac[visite == 1, ..coord_cols]
agg_plac   <- merge(agg_plac, plac_coord, by="idp", all.x=TRUE)

# Jointure date_releve depuis GMN (old_idp = identifiant IFN original)
plac_coord[, old_idp := as.character(old_idp)]
agg_plac[,  old_idp  := as.character(old_idp)]
agg_plac <- merge(agg_plac, gmn_dates, by="old_idp", all.x=TRUE)
cat(sprintf("  date_releve : %d / %d placettes renseignees (%.1f%%)\n",
            sum(!is.na(agg_plac$date_releve)), nrow(agg_plac),
            100 * mean(!is.na(agg_plac$date_releve))))
agg_plac[, old_idp := NULL]

n_sans_coord <- sum(is.na(agg_plac$xl) | is.na(agg_plac$yl))
if (n_sans_coord > 0)
  cat(sprintf("  Attention : %d placettes sans coordonnees\n", n_sans_coord))

sub_coord  <- agg_plac[!is.na(xl) & !is.na(yl)]
pts_l93    <- vect(sub_coord, geom=c("xl","yl"), crs="EPSG:2154")
pts_wgs    <- project(pts_l93, "EPSG:4326")
coords_wgs <- as.data.table(crds(pts_wgs))
setnames(coords_wgs, c("lon", "lat"))
agg_plac[!is.na(xl) & !is.na(yl), c("lon","lat") := coords_wgs]

cat(sprintf("  Placettes converties : %d\n\n", nrow(coords_wgs)))

# --- 6. EXTRACTION pH ---------------------------------------------------------
cat("Extraction pH sol (ph_ess2_L93.tif)...\n")
r_ph  <- rast(F_PH)
vals  <- extract(r_ph, pts_l93)
agg_plac[!is.na(xl) & !is.na(yl), pH := vals[[2]]]
cat(sprintf("  pH : min=%.2f max=%.2f NA=%d\n\n",
            min(agg_plac$pH, na.rm=TRUE),
            max(agg_plac$pH, na.rm=TRUE),
            sum(is.na(agg_plac$pH))))

# --- 7. ASSEMBLAGE FICHIER UNIQUE (format long placette x 8 especes cibles) --
# Grille complete : toutes les placettes x 8 especes cibles (= 8 lignes/placette)
cat("Assemblage grille placette x 8 especes cibles...\n")
grid <- CJ(idp = unique(agg_plac$idp), species_name = SP_CIBLES)

# Jointure avec metriques par espece (especes absentes -> NA)
out_sp <- merge(grid, agg_sp, by = c("idp", "species_name"), all.x = TRUE)

# Colonne presence : 1 si l'espece a au moins 1 arbre sur la placette, 0 sinon
out_sp[, presence := as.integer(!is.na(n_tiges))]

# Pour les especes absentes : compter 0, metriques incoherentes restent NA
out_sp[is.na(n_tiges),  `:=`(n_tiges    = 0L,
                              n_mort_sp  = 0L,
                              G_ha_sp    = 0,
                              prop_G     = 0,
                              prop_mort_sp = NA_real_,
                              c13_moy_sp   = NA_real_)]

cat(sprintf("  %d placettes x 8 especes = %d lignes\n",
            uniqueN(out_sp$idp), nrow(out_sp)))
cat(sprintf("  dont presence=1 : %d | presence=0 : %d\n\n",
            sum(out_sp$presence), sum(!out_sp$presence)))

# Jointure avec metriques placette
out <- merge(out_sp, agg_plac, by = "idp", all.x = TRUE)

setcolorder(out, c("idp", "species_name", "presence",
                   "G_ha_sp", "prop_G",
                   "n_tiges", "n_mort_sp", "prop_mort_sp", "c13_moy_sp",
                   "G_ha_tot", "c13_moy", "Gini", "n_tot", "n_mort", "prop_mort",
                   "esp_maj", "pH",
                   intersect(setdiff(coord_cols, c("idp", "old_idp")), names(out)),
                   "date_releve",
                   c("lon", "lat")))
setorder(out, idp, -G_ha_sp)

# --- 8. EXPORT ----------------------------------------------------------------
f_out <- file.path(DIR_OUT, "IFN_placette.csv")
fwrite(out, f_out, sep=";")

cat(sprintf("Export : %s  (%d lignes, %d colonnes)\n\n",
            basename(f_out), nrow(out), ncol(out)))

# --- RESUME -------------------------------------------------------------------
cat(strrep("-", 70), "\n", sep="")
cat(sprintf("Lignes exportees (placette x essence) : %d\n", nrow(out)))
cat(sprintf("Placettes uniques                     : %d\n", uniqueN(out$idp)))
cat(sprintf("Essences uniques                      : %d\n", uniqueN(out$species_name)))
cat(sprintf("prop_mort [%.3f, %.3f] | moy=%.3f\n",
            min(out$prop_mort, na.rm=TRUE), max(out$prop_mort, na.rm=TRUE),
            mean(out$prop_mort, na.rm=TRUE)))
cat(sprintf("pH        [%.2f, %.2f]\n",
            min(out$pH, na.rm=TRUE), max(out$pH, na.rm=TRUE)))
cat(sprintf("G_ha_tot  [%.2f, %.2f] m2/ha\n",
            min(out$G_ha_tot, na.rm=TRUE), max(out$G_ha_tot, na.rm=TRUE)))
cat(sprintf("Gini      [%.3f, %.3f]\n",
            min(out$Gini, na.rm=TRUE), max(out$Gini, na.rm=TRUE)))
cat(sprintf("Lon       [%.2f, %.2f] deg\n",
            min(out$lon, na.rm=TRUE), max(out$lon, na.rm=TRUE)))
cat(sprintf("Lat       [%.2f, %.2f] deg\n",
            min(out$lat, na.rm=TRUE), max(out$lat, na.rm=TRUE)))
cat(strrep("=", 70), "\n", sep="")
cat(sprintf("  TERMINE en %.0f s\n", (proc.time()-t0)[["elapsed"]]))
cat(strrep("=", 70), "\n", sep="")
