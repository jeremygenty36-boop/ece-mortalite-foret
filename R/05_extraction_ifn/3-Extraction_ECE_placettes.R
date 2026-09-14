# source("S:/Projets/stage_JeremyG/4-Travail/3-IFN/3-Extraction_ECE_placettes.R")
# ==============================================================================
# EXTRACTION ECE AUX PLACETTES IFN  -- fenetre glissante N_ANS ans
#
# Pour chaque placette, extrait l'ECE sur les N_ANS annees precedant
# (et incluant) l'annee de visite (campagne) dans chacune des 6 bases x
# 6 indices = 36 colonnes.
#
# Agregation sur la fenetre (par indice) :
#   TXx   -> max   (pic de chaleur le plus fort de la decennie)
#   TNn   -> min   (gel le plus severe de la decennie)
#   SPEI6 -> min   (secheresse la plus forte de la decennie, saison de vegetation)
#   WG10P -> mean  (stress hydrique moyen, saison de vegetation)
#   HWN, CWN -> sum  (nb total d'episodes sur la decennie)
#
# Entree  : IFN_placette.csv (coord lon/lat + campagne)
# Sortie  : IFN_placette.csv mis a jour (36 colonnes ECE ajoutees)
#
# Principe : pour chaque base x indice, on charge le NC une seule fois,
# on extrait toutes les placettes en une passe (terra::extract), puis
# on agrege (moyenne ou somme selon l'indice) les couches correspondant
# a [campagne-N_ANS+1 ... campagne].
#
# Lancer sur CALCULUS (bases 1 km = gros rasters).
# ==============================================================================

suppressPackageStartupMessages(library(terra))
suppressPackageStartupMessages(library(data.table))

# --- CHEMINS ------------------------------------------------------------------
.PFX    <- if (dir.exists("S:/Projets")) "S:" else "/Volumes/_donnees"
DIR_ECE <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/3-ECE/1-ECE_1979-2024")
F_IFN   <- file.path(.PFX, "Projets/stage_JeremyG/3-Donnees/6-IFN/IFN_placette.csv")

# --- PARAMETRES ---------------------------------------------------------------
N_ANS <- 10L   # largeur de la fenetre glissante (annees precedant campagne incluse)

cat(strrep("=", 70), "\n", sep="")
cat("  EXTRACTION ECE -> PLACETTES IFN  (fenetre glissante)\n")
cat(sprintf("  %s\n", format(Sys.time())))
cat(sprintf("  N_ANS = %d  (fenetre [campagne-%d+1 ... campagne])\n",
            N_ANS, N_ANS))
cat("  Annee campagne exclue si releve avant mi-periode -> fenetre DECALEE\n")
cat("  d'un an vers le passe [camp-10 ... camp-1] (toujours 10 ans)\n")
cat("  TXx:max | TNn:min | SPEI6:min | WG10P:moyenne sur la fenetre\n")
cat("  HWN / CWN : somme sur la fenetre (nb d'episodes)\n")
cat(strrep("=", 70), "\n\n", sep="")

# --- LECTURE IFN --------------------------------------------------------------
d <- fread(F_IFN, sep=";")
cat(sprintf("IFN : %d lignes, %d placettes uniques\n", nrow(d), uniqueN(d$idp)))
cat(sprintf("campagne : %d - %d\n\n", min(d$campagne), max(d$campagne)))

# Une ligne par placette (coord + annee de visite + date exacte si disponible)
plac <- unique(d[, .(idp, lon, lat, campagne, date_releve)])
cat(sprintf("Placettes a extraire : %d\n\n", nrow(plac)))

# Points spatiaux (WGS84 -- terra reprojette si besoin)
pts <- vect(plac, geom=c("lon","lat"), crs="EPSG:4326")

# --- CONFIG BASES x INDICES ---------------------------------------------------
BASES <- list(
  list(code="EOBS",      dir="1-EOBS_11km",    col="EOB10"),
  list(code="SAFRAN",    dir="2-SAFRAN_8km",   col="SAF8"),
  list(code="CHELSA",    dir="3-CHELSA_1km",   col="CHE1"),
  list(code="DIGI_EOBS", dir="4-DIGI_EOBS_1km",col="EOBDS"),
  list(code="DIGI_SAF",  dir="5-DIGI_SAF_1km", col="SAFDS"),
  list(code="DIGI_CHEL", dir="6-DIGI_CHEL_1km",col="CHEDS")
)

# --- Filtre optionnel de bases (override AVANT le source) ----------------------
# Extraction INCREMENTALE par base. Poser, avant source(), au choix :
#   BASES_EXCLUDE <- "DIGI_SAF"     # toutes les bases SAUF DIGI_SAF (ex. TNn pas pret)
#   BASES_ONLY    <- "DIGI_SAF"     # UNIQUEMENT DIGI_SAF (ajout differe plus tard)
# Codes valides : EOBS, SAFRAN, CHELSA, DIGI_EOBS, DIGI_SAF, DIGI_CHEL.
# Surete : la jointure finale (cf. col_ece) ne retire/recalcule QUE les colonnes
# des bases traitees -> les colonnes des bases NON traitees deja presentes dans
# IFN_placette.csv sont PRESERVEES (aucun ecrasement) -> extraction en plusieurs
# passes possible (5 bases maintenant, DIGI_SAF ajoute plus tard).
if (exists("BASES_ONLY"))
  BASES <- Filter(function(b) b$code %in% BASES_ONLY, BASES)
if (exists("BASES_EXCLUDE"))
  BASES <- Filter(function(b) !(b$code %in% BASES_EXCLUDE), BASES)
stopifnot(length(BASES) > 0L)
cat(sprintf("Bases traitees (%d/6) : %s\n",
            length(BASES), paste(vapply(BASES, function(b) b$code, ""), collapse=", ")))

# cutoff_mois/jour = mi-periode de l'indice dans l'annee campagne :
#   si date_releve < cutoff -> annee campagne exclue (periode incomplete)
#   TNn : periode SEP(camp-1)-MAI(camp), mi-periode = 15 jan de l'annee camp
INDICES <- list(
  list(code="TXx",   fichier="TXx_MAR-NOV",   agg="max",  cutoff_mois=7L, cutoff_jour=15L),
  list(code="TNn",   fichier="TNn_SEP-MAY",    agg="min",  cutoff_mois=1L, cutoff_jour=15L),
  list(code="SPEI6", fichier="SPEI6_MAR-AUG",  agg="min",  cutoff_mois=6L, cutoff_jour= 1L),
  list(code="WG10P", fichier="WG10P_MAR-AUG",  agg="mean", cutoff_mois=6L, cutoff_jour= 1L),
  # HWN/CWN ajoutes (2026-06-09) : frequence d'episodes -> somme sur la fenetre.
  # CWN : MEME periode que TNn (SEP-MAI, hiver complet a cheval) -> cutoff mi-periode 15/01.
  # HWN : periode MAY-SEP (ete) -> cutoff mi-periode 15/07.
  list(code="HWN",   fichier="HWN_MAY-SEP",    agg="sum",  cutoff_mois=7L, cutoff_jour=15L),
  list(code="CWN",   fichier="CWN_SEP-MAY",    agg="sum",  cutoff_mois=1L, cutoff_jour=15L)
)

# --- EXTRACTION ---------------------------------------------------------------
t0 <- proc.time()
ece_plac <- copy(plac[, .(idp, campagne)])

for (b in BASES) {
  for (idx in INDICES) {
    col_name <- paste0(idx$code, "_", b$col)
    f <- file.path(DIR_ECE, b$dir,
                   sprintf("ECE_%s_%s.nc", b$code, idx$fichier))

    if (!file.exists(f)) {
      cat(sprintf("  ABSENT  : %-6s %-6s -> %s\n", b$col, idx$code, col_name))
      ece_plac[, (col_name) := NA_real_]
      next
    }

    r <- tryCatch(rast(f), error=function(e) NULL)
    if (is.null(r)) {
      cat(sprintf("  ERREUR  : %-6s %-6s -> %s\n", b$col, idx$code, col_name))
      ece_plac[, (col_name) := NA_real_]
      next
    }

    # Annees des couches
    annees_r <- as.integer(substr(as.character(as.Date(time(r))), 1, 4))

    # Extraction de toutes les placettes sur toutes les couches (1 passe)
    mat <- as.data.table(extract(r, pts))  # nrow=n_plac, ncol=1+nlyr

    # --- TNn 2022 CHE-1/CHE-C : RECALCULE le 2026-06-12 -> PLUS d'exclusion.
    # Le jour corrompu 29-04-2022 (fill 0K -> -273degC) faisait deraper le min ; il a
    # ete ecarte et TNn 2022 recalcule hors climpact (CHE-C : avril entier exclu, car
    # contamine par le delta mensuel du downscale). Valeurs valides et coherentes avec
    # les pairs (CHE-1 = -4,53 / CHE-C = -4,34). On lit donc la couche 2022 normalement.
    # cf 2-Corrections/0-TNn_CHELSA_2022_recalc_local.R ; les 6 bases ont TNn 2022 valide.

    # Fonction d'agregation selon l'indice (max, min, mean ou sum)
    agg_fct <- switch(idx$agg, mean = mean, sum = sum, max = max, min = min)

    # Seuil de mi-periode pour l'annee campagne (DD/MM -> Date)
    cutoff_fmt <- sprintf("%02d/%02d", idx$cutoff_jour, idx$cutoff_mois)

    # Pour chaque placette : fenetre [debut, fin] selon presence de date_releve
    n_decale <- 0L
    vals <- mapply(function(camp, i_row, date_rel) {

      # Campagne incluse par defaut ; exclue si date connue et anterieure au seuil
      incl_camp <- TRUE
      if (!is.na(date_rel) && nchar(date_rel) == 10L) {
        cutoff <- as.Date(sprintf("%02d/%02d/%04d",
                                 idx$cutoff_jour, idx$cutoff_mois, camp),
                          format = "%d/%m/%Y")
        releve  <- as.Date(date_rel, format = "%d/%m/%Y")
        if (!is.na(releve) && releve < cutoff) incl_camp <- FALSE
      }

      # Fenetre TOUJOURS de N_ANS=10 ans (decision C. Piedallu, 2026-06-10).
      # Si l'annee campagne est exclue (releve avant mi-periode), on DECALE la
      # fenetre d'un an vers le passe -> [camp-N_ANS ... camp-1] (10 ans), au
      # lieu de la raccourcir a 9 ans. Le decalage depend de la date de la
      # placette (pas de la base) -> il s'applique aux 6 bases a l'identique
      # (comparabilite preservee).
      annee_fin   <- if (incl_camp) camp else camp - 1L
      annee_debut <- if (incl_camp) camp - N_ANS + 1L else camp - N_ANS

      idx_lyr <- which(annees_r >= annee_debut & annees_r <= annee_fin)
      if (length(idx_lyr) == 0L) return(NA_real_)
      v <- as.numeric(mat[i_row, idx_lyr + 1L, with=FALSE])
      # Fenetre entierement NA -> NA (sinon max/min renverraient -Inf/+Inf et
      # sum renverrait 0, faux "aucun episode"). Une fenetre partiellement NA
      # (ex. couche 2022 CHELSA TNn/CWN) reste agregee sur les annees valides.
      if (all(is.na(v))) return(NA_real_)
      agg_fct(v, na.rm = TRUE)

    }, plac$campagne, seq_len(nrow(plac)), plac$date_releve)

    n_decale <- sum(!is.na(plac$date_releve) & {
      cutoff_dates <- as.Date(sprintf("%02d/%02d/%04d",
                                     idx$cutoff_jour, idx$cutoff_mois, plac$campagne),
                              format = "%d/%m/%Y")
      releve_dates <- as.Date(plac$date_releve, format = "%d/%m/%Y")
      !is.na(releve_dates) & releve_dates < cutoff_dates
    })

    ece_plac[, (col_name) := as.numeric(vals)]

    n_ok  <- sum(!is.na(vals))
    n_ann <- mean(mapply(function(camp) {
      sum(annees_r >= (camp - N_ANS + 1L) & annees_r <= camp)
    }, plac$campagne))
    cat(sprintf("  OK %-3s  : %-6s %-6s -> %-20s | valides=%d | decales=%d | [%.2f, %.2f]\n",
                idx$agg, b$col, idx$code, col_name, n_ok, n_decale,
                min(vals, na.rm=TRUE), max(vals, na.rm=TRUE)))
  }
}

cat(sprintf("\nExtraction terminee en %.0f s\n\n", (proc.time()-t0)[["elapsed"]]))

# --- JOINTURE ET EXPORT -------------------------------------------------------
# Supprimer les anciennes colonnes ECE si deja presentes
col_ece <- setdiff(names(ece_plac), c("idp","campagne"))
d[, (intersect(col_ece, names(d))) := NULL]

# Joindre (une valeur par placette, repetee sur chaque ligne essence)
d <- merge(d, ece_plac, by=c("idp","campagne"), all.x=TRUE)

# EXCLUSION CORSE (2026-06-08 : fusion de 7-Correction_Corse_DIGITALIS) :
# DIGITALIS DS peu fiable sur la Corse -> NA des colonnes _EOBDS/_SAFDS/_CHEDS pour
# les placettes corses (lon > 8.5 & lat < 43.1). La sortie est directement propre.
.idx_corse <- d[, which(lon > 8.5 & lat < 43.1)]
.cols_ds   <- grep("_(EOBDS|SAFDS|CHEDS)$", names(d), value = TRUE)
if (length(.idx_corse) > 0L && length(.cols_ds) > 0L) {
  for (.c in .cols_ds) d[.idx_corse, (.c) := NA_real_]
  cat(sprintf("Corse : %d lignes -> %d colonnes DIGITALIS DS mises a NA\n",
              length(.idx_corse), length(.cols_ds)))
}

fwrite(d, F_IFN, sep=";")

cat(sprintf("Export : %s\n", basename(F_IFN)))
cat(sprintf("  %d lignes, %d colonnes\n", nrow(d), ncol(d)))
cat(sprintf("  Colonnes ECE ajoutees/MAJ ce run (%d) : %s\n",
            length(col_ece), paste(col_ece, collapse=", ")))
n_ece_tot <- length(grep("_(EOB10|SAF8|CHE1|EOBDS|SAFDS|CHEDS)$", names(d)))
cat(sprintf("  Colonnes ECE TOTALES dans le fichier : %d / 36 (6 indices x 6 bases)\n", n_ece_tot))
if (n_ece_tot < 36L)
  cat("  -> extraction PARTIELLE : relancer pour les bases manquantes",
      "(ex. BASES_ONLY <- \"DIGI_SAF\") pour completer a 36.\n")
cat(strrep("=", 70), "\n", sep="")
