# source("R/05_extraction_ifn/3b-Extraction_Classique_SAFDS.R")   # depuis la racine du depot
# ==============================================================================
# EXTRACTION MOYENNES SAISONNIERES CLASSIQUES -> PLACETTES IFN
#
# 5 variables pour le modele de comparaison ECE vs classique (base DIGI) :
#   BHC_MAM, BHC_JJA   -- DIGITALIS v4 BHC (L93 1km, bhc_YYYY_pr/et.tif)
#   Tmax_MAM, Tmax_JJA -- DIGITALIS v3 tmax (L93 1km, tmax_YYYY_pr/et.tif)
#   Tmin_hiver          -- DIGITALIS v3 tmin (L93 1km, tmin_YYYY_hi.tif)
#
# Saisons alignees sur les indices ECE correspondants :
#   Tmin->froid (TNn/CWN sep-mai) -> hiver DJF (tmin_YYYY_hi.tif), cutoff 15-fev
#   Tmax->chaud (TXx/HWN mar-nov) -> printemps+ete (MAM+JJA),       cutoff 15-avr/jul
#   BHC ->secheresse (SPEI6)      -> printemps+ete (MAM+JJA),       cutoff 15-avr/jul
#
# Colonnes produites dans IFN_placette.csv (5 colonnes, suffix _DIGI) :
#   BHC_MAM_DIGI  BHC_JJA_DIGI
#   Tmax_MAM_DIGI Tmax_JJA_DIGI
#   Tmin_hiver_DIGI
#
# Note : valeurs Tmax/Tmin en 1/10 degC (convention DIGITALIS v3),
#        BHC en 1/10 mm -- unite coherente entre variables, pas d'impact
#        sur la selection BIC ni l'AUC du modele.
# ==============================================================================

# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
suppressPackageStartupMessages({
  library(terra)
  library(data.table)
})

# --- CHEMINS ------------------------------------------------------------------
# .PFX : fourni par config/chemins.R
.BD     <- .PFX   # racine contenant BD_SIG/ (config/chemins.R)
DIR_BHC  <- file.path(.PFX, "Projets/stage_JeremyG/3-Donnees/5-DIGITALIS/2-1960_2025_DIGITALIS_v4/3-1960_2024_BHC")
DIR_TMAX <- file.path(.BD,  "BD_SIG/climat/france/DIGITALIS_v3/tmax")
DIR_TMIN <- file.path(.BD,  "BD_SIG/climat/france/DIGITALIS_v3/tmin")
F_IFN    <- file.path(.PFX, "Projets/stage_JeremyG/3-Donnees/6-IFN/IFN_placette.csv")

# --- PARAMETRES ---------------------------------------------------------------
if (!exists("N_ANS")) N_ANS <- 10L

cat(strrep("=", 70), "\n", sep="")
cat("  EXTRACTION MOYENNES SAISONNIERES CLASSIQUES -> PLACETTES IFN\n")
cat(sprintf("  %s\n", format(Sys.time())))
cat(sprintf("  N_ANS = %d\n", N_ANS))
cat("  MAM cutoff 15-avr | JJA cutoff 15-jul | Hiver cutoff 15-fev\n")
cat("  BHC : DIGITALIS v4 | Tmax/Tmin : DIGITALIS v3 (rasters L93 1km)\n")
cat("  Saisons : BHC=MAM+JJA | Tmax=MAM+JJA | Tmin=Hiver(DJF)\n")
cat("  Agregation : moyenne fenetre N_ANS ans sur valeurs saisonnieres annuelles\n")
cat(strrep("=", 70), "\n\n", sep="")

# --- LECTURE IFN --------------------------------------------------------------
d    <- fread(F_IFN, sep=";")
cat(sprintf("IFN : %d lignes, %d placettes uniques\n", nrow(d), uniqueN(d$idp)))

plac <- unique(d[, .(idp, lon, lat, campagne, date_releve)])
cat(sprintf("Placettes a extraire : %d | campagne %d-%d\n\n",
            nrow(plac), min(plac$campagne), max(plac$campagne)))

# Points L93 (toutes sources sont en L93)
pts_l93 <- project(vect(plac, geom=c("lon","lat"), crs="EPSG:4326"), "EPSG:2154")

# Plage annees
ann_min <- min(plac$campagne) - N_ANS
ann_max <- max(plac$campagne)
annees  <- ann_min:ann_max
n_plac  <- nrow(plac)
n_ans   <- length(annees)
cat(sprintf("Plage annees requises : %d - %d (%d ans)\n\n", ann_min, ann_max, n_ans))

# --- CONFIG 6 VARIABLES -------------------------------------------------------
# pat = pattern sprintf pour sprintf(pat, annee)
# cm/cj = mois/jour du cutoff de mi-saison
VARS <- list(
  list(name="BHC_MAM",  dir=DIR_BHC,  pat="bhc_%d_pr.tif",  cm=4L, cj=15L),
  list(name="BHC_JJA",  dir=DIR_BHC,  pat="bhc_%d_et.tif",  cm=7L, cj=15L),
  list(name="Tmax_MAM", dir=DIR_TMAX, pat="tmax_%d_pr.tif", cm=4L, cj=15L),
  list(name="Tmax_JJA", dir=DIR_TMAX, pat="tmax_%d_et.tif", cm=7L, cj=15L),
  list(name="Tmin_hiver", dir=DIR_TMIN, pat="tmin_%d_hi.tif", cm=2L, cj=15L)
)

# --- FONCTION FENETRE GLISSANTE -----------------------------------------------
fn_agg_mean <- function(mat, annees, cutoff_m, cutoff_j) {
  mapply(function(camp, i_row, date_rel) {
    incl_camp <- TRUE
    if (!is.na(date_rel) && nchar(date_rel) == 10L) {
      cutoff <- as.Date(sprintf("%02d/%02d/%04d", cutoff_j, cutoff_m, camp),
                        format="%d/%m/%Y")
      releve  <- as.Date(date_rel, format="%d/%m/%Y")
      if (!is.na(releve) && releve < cutoff) incl_camp <- FALSE
    }
    annee_fin   <- if (incl_camp) camp     else camp - 1L
    annee_debut <- if (incl_camp) camp - N_ANS + 1L else camp - N_ANS
    idx <- which(annees >= annee_debut & annees <= annee_fin)
    if (length(idx) == 0L) return(NA_real_)
    v <- mat[i_row, idx]
    if (all(is.na(v))) NA_real_ else mean(v, na.rm=TRUE)
  }, plac$campagne, seq_len(n_plac), plac$date_releve)
}

# ==============================================================================
# EXTRACTION : 1 passe par variable (stack annees -> extract en bloc)
# ==============================================================================
t0   <- proc.time()
clsc <- copy(plac[, .(idp, campagne)])

for (v in VARS) {
  col_name <- paste0(v$name, "_DIGI")
  files    <- file.path(v$dir, sprintf(v$pat, annees))
  ok       <- file.exists(files)

  if (!any(ok)) {
    cat(sprintf("  ABSENT  : %-10s -- aucun fichier trouve\n", v$name))
    clsc[, (col_name) := NA_real_]
    next
  }

  # Tentative directe ; si les etendues divergent (ex. tmin 2021-2024 ymin+3km)
  # -> fallback : chargement individuel + crop a l'intersection commune
  stk <- tryCatch(
    rast(files[ok]),
    error = function(e) {
      cat(sprintf("  INFO  %s : etendues heterogenes, fallback crop-intersection\n", v$name))
      r_list <- lapply(files[ok], function(f) tryCatch(rast(f), error=function(e2) NULL))
      r_list <- Filter(Negate(is.null), r_list)
      if (length(r_list) == 0L) return(NULL)
      e_com <- Reduce(intersect, lapply(r_list, ext))
      tryCatch(rast(lapply(r_list, function(r) crop(r, e_com))),
               error = function(e2) { cat(sprintf("  ERREUR stack %s\n", v$name)); NULL })
    }
  )
  if (is.null(stk)) { clsc[, (col_name) := NA_real_]; next }

  ext_mat  <- as.matrix(extract(stk, pts_l93)[, -1L, drop=FALSE])

  mat_full <- matrix(NA_real_, n_plac, n_ans)
  mat_full[, which(ok)] <- ext_mat
  rm(stk, ext_mat); gc()

  vals <- fn_agg_mean(mat_full, annees, v$cm, v$cj)
  clsc[, (col_name) := as.numeric(vals)]

  n_dec <- sum(!is.na(plac$date_releve) & {
    cutoff_d <- as.Date(sprintf("%02d/%02d/%04d", v$cj, v$cm, plac$campagne),
                        format="%d/%m/%Y")
    releve_d <- as.Date(plac$date_releve, format="%d/%m/%Y")
    !is.na(releve_d) & releve_d < cutoff_d
  })
  cat(sprintf("  OK mean : DIGI %-10s -> %-22s | valides=%d | decales=%d | [%.1f, %.1f]\n",
              v$name, col_name, sum(!is.na(vals)), n_dec,
              min(vals, na.rm=TRUE), max(vals, na.rm=TRUE)))
}
cat(sprintf("\nExtraction terminee en %.0f s\n\n", (proc.time()-t0)[["elapsed"]]))

# ==============================================================================
# JOINTURE ET EXPORT
# ==============================================================================
cat("--- Jointure + export ---\n")

col_clsc <- setdiff(names(clsc), c("idp", "campagne"))

# Suppression des colonnes si deja presentes (re-extraction incrementale)
d[, (intersect(col_clsc, names(d))) := NULL]
d <- merge(d, clsc, by=c("idp","campagne"), all.x=TRUE)

# Corse : NA les colonnes classiques DIGI
.idx_corse <- d[, which(lon > 8.5 & lat < 43.1)]
if (length(.idx_corse) > 0L) {
  for (.c in col_clsc) d[.idx_corse, (.c) := NA_real_]
  cat(sprintf("Corse : %d lignes -> %d colonnes DIGI mises a NA\n",
              length(.idx_corse), length(col_clsc)))
}

fwrite(d, F_IFN, sep=";")

cat(sprintf("\nExport : %s\n", basename(F_IFN)))
cat(sprintf("  %d lignes, %d colonnes\n", nrow(d), ncol(d)))
cat(sprintf("  Nouvelles colonnes (%d) : %s\n",
            length(col_clsc), paste(sort(col_clsc), collapse=", ")))
cat(strrep("=", 70), "\n", sep="")
cat(sprintf("  TERMINE : %s\n", format(Sys.time())))
cat(strrep("=", 70), "\n", sep="")
