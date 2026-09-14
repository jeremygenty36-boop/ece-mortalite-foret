# source("R/05_extraction_ifn/3c-Extraction_Moyennes_par_base.R")   # depuis la racine du depot
# ==============================================================================
# EXTRACTION MOYENNES SAISONNIERES *PAR BASE* -> PLACETTES IFN
#
# But : donner a CHAQUE base climatique ses PROPRES moyennes saisonnieres,
#   calculees depuis SES donnees journalieres (comme les ECE), et non les
#   moyennes DIGITALIS communes (colonnes *_DIGI, cf 3b).
#
# 6 variables par base (symetrie avec les 6 indices ECE) :
#   Tmax_MAM  Tmax_JJA    (chaud  <-> TXx/HWN)   : moyenne tmax journalier MAM / JJA
#   Tmin_hiver Tmin_MAM   (froid  <-> TNn/CWN)   : moyenne tmin journalier DJF / MAM
#   BHC_MAM   BHC_JJA     (sec    <-> SPEI6/WG10P): moyenne (prec - ETP) MAM / JJA
#
# Colonnes produites : <var>_<code_base>, code = EOB10 SAF8 CHE1 EOBDS SAFDS
#   -> compatibles avec le moteur (INDICES_AUTORISES + BASES), cf 0M.
#
# METHODE (tout AU POINT -> RAM basse, robuste CRS/etendues) :
#   1. Pour chaque base x annee, on lit les journaliers tmax/tmin/prec et on
#      EXTRAIT aux placettes (terra reprojette les points au CRS du raster).
#   2. ETP journaliere reproduite a l'identique de calc_etp (Turc, Rs par
#      Hargreaves : Rs = 0.16*sqrt(dT)*Ra), mais calculee sur les series de
#      POINTS via la latitude WGS84 de chaque placette -> BHC = prec - ETP.
#   3. Moyenne saisonniere par placette/annee, puis fenetre glissante N_ANS
#      ans (fn_agg_mean, identique au 3b : decalage si releve avant mi-saison).
#   Hiver = DJF vrai : Dec(annee-1) + Jan/Fev(annee).
#
# Donnees journalieres (CALCULUS) : <ECE_ROOT>/<dir>/<code_ece>_<var>_<an>.nc
#   ECE_ROOT = D:/Stage_JeremyG/ECE_data (local) sinon S:/.../ECE_data
#
# FLAGS avant source() :
#   ECE_BASES  <- "SAFDS"          # restreindre (valider une base d'abord)
#   ANNEES_TEST <- 2               # limiter aux 2 dernieres annees (smoke test)
#   FORCE       <- TRUE            # ignorer le cache RDS
#
# LOURD : lit tous les journaliers 1 km des bases demandees. Sequentiel.
# Non testable sur Mac (donnees sur CALCULUS). Lancer d'abord ECE_BASES<-"SAFDS".
# ==============================================================================
# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
suppressPackageStartupMessages({
  library(terra); library(data.table); library(lubridate)
})

# --- CHEMINS ------------------------------------------------------------------
# .PFX : fourni par config/chemins.R
ECE_ROOT <- if (dir.exists(file.path(LOCAL_ROOT, "ECE_data"))) file.path(LOCAL_ROOT, "ECE_data") else
            file.path(.PFX, "Projets/stage_JeremyG/ECE_data")
F_IFN    <- file.path(.PFX, "Projets/stage_JeremyG/3-Donnees/6-IFN/IFN_placette.csv")
DIR_CACHE <- file.path(.PFX, "Projets/stage_JeremyG/3-Donnees/6-IFN/_cache_moyennes_par_base")
dir.create(DIR_CACHE, showWarnings = FALSE, recursive = TRUE)

if (!exists("N_ANS"))  N_ANS  <- 10L
if (!exists("FORCE"))  FORCE  <- FALSE
terraOptions(memfrac = 0.6, progress = 0)   # garde-fou RAM sur machine partagee

# --- BASES (CHE-C exclue) -----------------------------------------------------
BASES <- list(
  list(ece = "EOBS",      dir = "1-EOBS_11km",     col = "EOB10"),
  list(ece = "SAFRAN",    dir = "2-SAFRAN_8km",    col = "SAF8"),
  list(ece = "CHELSA",    dir = "3-CHELSA_1km",    col = "CHE1"),
  list(ece = "DIGI_EOBS", dir = "4-DIGI_EOBS_1km", col = "EOBDS"),
  list(ece = "DIGI_SAF",  dir = "5-DIGI_SAF_1km",  col = "SAFDS")
)
if (exists("ECE_BASES"))
  BASES <- Filter(function(b) b$col %in% ECE_BASES || b$ece %in% ECE_BASES, BASES)
stopifnot(length(BASES) > 0L)

# 6 variables : source journaliere + saison + cutoff mi-saison (comme 3b)
#   mois : vecteur des mois de la saison ; hiver traite a part (DJF cross-annee)
VARS <- list(
  list(name = "Tmax_MAM",   src = "tmax", mois = 3:5,  cm = 4L, cj = 15L, hiver = FALSE),
  list(name = "Tmax_JJA",   src = "tmax", mois = 6:8,  cm = 7L, cj = 15L, hiver = FALSE),
  list(name = "Tmin_MAM",   src = "tmin", mois = 3:5,  cm = 4L, cj = 15L, hiver = FALSE),
  list(name = "Tmin_hiver", src = "tmin", mois = c(12L,1L,2L), cm = 2L, cj = 15L, hiver = TRUE),
  list(name = "BHC_MAM",    src = "bhc",  mois = 3:5,  cm = 4L, cj = 15L, hiver = FALSE),
  list(name = "BHC_JJA",    src = "bhc",  mois = 6:8,  cm = 7L, cj = 15L, hiver = FALSE)
)

cat(strrep("=", 70), "\n", sep = "")
cat("  EXTRACTION MOYENNES SAISONNIERES PAR BASE -> PLACETTES IFN\n")
cat(sprintf("  ECE_ROOT = %s\n", ECE_ROOT))
cat(sprintf("  Bases : %s | N_ANS = %d | FORCE = %s\n",
            paste(vapply(BASES, `[[`, "", "col"), collapse = ", "), N_ANS, FORCE))
cat(strrep("=", 70), "\n\n", sep = "")
if (!dir.exists(ECE_ROOT))
  stop("ECE_ROOT introuvable : ", ECE_ROOT, " (donnees journalieres sur CALCULUS)")

# --- LECTURE IFN + points -----------------------------------------------------
d    <- fread(F_IFN, sep = ";")
plac <- unique(d[, .(idp, lon, lat, campagne, date_releve)])
n_plac <- nrow(plac)
lat_vec <- plac$lat
pts_wgs <- vect(plac, geom = c("lon","lat"), crs = "EPSG:4326")
cat(sprintf("Placettes : %d | campagne %d-%d\n", n_plac, min(plac$campagne), max(plac$campagne)))

ann_max <- max(plac$campagne)
ann_min <- min(plac$campagne) - N_ANS
if (exists("ANNEES_TEST")) ann_min <- ann_max - as.integer(ANNEES_TEST) + 1L  # smoke test
annees  <- ann_min:ann_max
n_ans   <- length(annees)
cat(sprintf("Annees requises : %d-%d (%d ans)\n\n", ann_min, ann_max, n_ans))

# --- FENETRE GLISSANTE (identique 3b) -----------------------------------------
fn_agg_mean <- function(mat, annees, cutoff_m, cutoff_j) {
  mapply(function(camp, i_row, date_rel) {
    incl_camp <- TRUE
    if (!is.na(date_rel) && nchar(date_rel) == 10L) {
      cutoff <- as.Date(sprintf("%02d/%02d/%04d", cutoff_j, cutoff_m, camp), format = "%d/%m/%Y")
      releve <- as.Date(date_rel, format = "%d/%m/%Y")
      if (!is.na(releve) && releve < cutoff) incl_camp <- FALSE
    }
    annee_fin   <- if (incl_camp) camp else camp - 1L
    annee_debut <- if (incl_camp) camp - N_ANS + 1L else camp - N_ANS
    idx <- which(annees >= annee_debut & annees <= annee_fin)
    if (length(idx) == 0L) return(NA_real_)
    v <- mat[i_row, idx]
    if (all(is.na(v))) NA_real_ else mean(v, na.rm = TRUE)
  }, plac$campagne, seq_len(n_plac), plac$date_releve)
}

# --- ETP au point (reproduit calc_etp : Turc + Hargreaves) --------------------
ra_point <- function(lat_deg, J) {                 # J = jour julien (scalaire)
  lat <- lat_deg * pi/180
  dr  <- 1 + 0.033 * cos(2*pi*J/365)
  dcl <- 0.409 * sin(2*pi*J/365 - 1.39)
  ws  <- acos(pmax(-1, pmin(1, -tan(lat) * tan(dcl))))
  (24*60/pi) * 0.082 * dr * (ws*sin(lat)*sin(dcl) + cos(lat)*cos(dcl)*sin(ws))
}
etp_point <- function(tx, tn, ra) {                # vecteurs (placettes) pour 1 jour
  tm <- (tx + tn) / 2
  dt <- ifelse(!is.na(tx) & !is.na(tn) & tx > tn, sqrt(tx - tn), 0)
  Rs <- dt * (0.16 * 23.884 * ra)
  # NA-safe comme calc_etp : temp manquante -> ETP NA (et non 0), sinon 0 si gel
  ifelse(is.na(tm), NA_real_, ifelse(tm > 0, 0.013 * tm/(tm + 15) * (Rs + 50), 0))
}

# lit un journalier <code>_<var>_<an>.nc et extrait aux placettes -> list(mat, dates)
lire_extraire <- function(base, var, an, pts_b) {
  f <- file.path(ECE_ROOT, base$dir, sprintf("%s_%s_%d.nc", base$ece, var, an))
  if (!file.exists(f)) return(NULL)
  r <- tryCatch(rast(f), error = function(e) NULL); if (is.null(r)) return(NULL)
  dts <- tryCatch(as.Date(time(r)), error = function(e) NULL)
  m   <- tryCatch(as.matrix(extract(r, pts_b, ID = FALSE)), error = function(e) NULL)
  if (is.null(m) || is.null(dts) || length(dts) != ncol(m)) return(NULL)
  list(mat = m, dates = dts)
}

# moyenne saisonniere par placette a partir d'une matrice [plac x jours] + dates
saison_mean <- function(mat, dates, mois) {
  sel <- month(dates) %in% mois
  if (!any(sel)) return(rep(NA_real_, nrow(mat)))
  rowMeans(mat[, sel, drop = FALSE], na.rm = TRUE)
}

# ==============================================================================
# BOUCLE PAR BASE
# ==============================================================================
cols_produites <- character(0)

for (base in BASES) {
  f_cache <- file.path(DIR_CACHE, sprintf("moy_%s.rds", base$col))
  if (!FORCE && file.exists(f_cache)) {
    cat(sprintf("[%s] cache present -> SKIP (FORCE<-TRUE pour recalculer)\n", base$col))
    cols_produites <- c(cols_produites, paste0(vapply(VARS, `[[`, "", "name"), "_", base$col))
    next
  }
  t0 <- proc.time()
  cat(sprintf("\n[%s] extraction (%s) ...\n", base$col, base$ece))

  # points au CRS du raster de la base (SAFRAN/EOBS/CHELSA=WGS84, DIGI=L93)
  f0 <- NULL
  for (an in rev(annees)) { ff <- file.path(ECE_ROOT, base$dir, sprintf("%s_tmax_%d.nc", base$ece, an))
    if (file.exists(ff)) { f0 <- ff; break } }
  if (is.null(f0)) { cat(sprintf("  [ERR] aucun tmax trouve pour %s -> base ignoree\n", base$col)); next }
  crs_b  <- crs(rast(f0))
  pts_b  <- tryCatch(project(pts_wgs, crs_b), error = function(e) pts_wgs)

  # matrices saisonnieres [plac x annee]
  M <- setNames(lapply(VARS, function(v) matrix(NA_real_, n_plac, n_ans)),
                vapply(VARS, `[[`, "", "name"))
  # graine Dec(ann_min-1) pour l'hiver DJF de la 1ere annee
  prev_dec <- {
    e <- lire_extraire(base, "tmin", ann_min - 1L, pts_b)
    if (!is.null(e)) e$mat[, month(e$dates) == 12L, drop = FALSE] else NULL
  }

  for (iy in seq_along(annees)) {
    an <- annees[iy]
    e_tx <- lire_extraire(base, "tmax", an, pts_b)
    e_tn <- lire_extraire(base, "tmin", an, pts_b)
    e_pr <- lire_extraire(base, "prec", an, pts_b)

    if (!is.null(e_tx)) {
      M[["Tmax_MAM"]][, iy] <- saison_mean(e_tx$mat, e_tx$dates, 3:5)
      M[["Tmax_JJA"]][, iy] <- saison_mean(e_tx$mat, e_tx$dates, 6:8)
    }
    if (!is.null(e_tn)) {
      M[["Tmin_MAM"]][, iy] <- saison_mean(e_tn$mat, e_tn$dates, 3:5)
      jf <- e_tn$mat[, month(e_tn$dates) %in% c(1L,2L), drop = FALSE]
      hiv <- if (!is.null(prev_dec) && nrow(prev_dec) == n_plac) cbind(prev_dec, jf) else jf
      if (ncol(hiv) > 0L) M[["Tmin_hiver"]][, iy] <- rowMeans(hiv, na.rm = TRUE)
      prev_dec <- e_tn$mat[, month(e_tn$dates) == 12L, drop = FALSE]
    } else prev_dec <- NULL

    # BHC = prec - ETP (dates communes tmax/tmin/prec)
    if (!is.null(e_tx) && !is.null(e_tn) && !is.null(e_pr)) {
      dc <- Reduce(intersect, list(as.character(e_tx$dates), as.character(e_tn$dates), as.character(e_pr$dates)))
      if (length(dc) > 0L) {
        itx <- match(dc, as.character(e_tx$dates)); itn <- match(dc, as.character(e_tn$dates))
        ipr <- match(dc, as.character(e_pr$dates)); doy <- yday(as.Date(dc))
        bhc <- matrix(NA_real_, n_plac, length(dc))
        for (j in seq_along(dc)) {
          ra  <- ra_point(lat_vec, doy[j])
          etp <- etp_point(e_tx$mat[, itx[j]], e_tn$mat[, itn[j]], ra)
          bhc[, j] <- e_pr$mat[, ipr[j]] - etp
        }
        mo <- month(as.Date(dc))
        if (any(mo %in% 3:5)) M[["BHC_MAM"]][, iy] <- rowMeans(bhc[, mo %in% 3:5, drop = FALSE], na.rm = TRUE)
        if (any(mo %in% 6:8)) M[["BHC_JJA"]][, iy] <- rowMeans(bhc[, mo %in% 6:8, drop = FALSE], na.rm = TRUE)
      }
    }
    if (iy %% 3L == 0L || iy == n_ans)
      cat(sprintf("    %s : %d/%d annees (%.0fs)\n", base$col, iy, n_ans, (proc.time()-t0)[["elapsed"]]))
  }

  # fenetre glissante N_ANS -> 1 colonne par variable
  res <- copy(plac[, .(idp, campagne)])
  for (v in VARS) {
    col <- paste0(v$name, "_", base$col)
    res[, (col) := as.numeric(fn_agg_mean(M[[v$name]], annees, v$cm, v$cj))]
    vv <- res[[col]]
    cat(sprintf("  OK %-22s | valides=%d/%d | [%.2f, %.2f]\n", col, sum(!is.na(vv)), n_plac,
                suppressWarnings(min(vv, na.rm = TRUE)), suppressWarnings(max(vv, na.rm = TRUE))))
  }
  saveRDS(res, f_cache)
  cols_produites <- c(cols_produites, setdiff(names(res), c("idp","campagne")))
  cat(sprintf("[%s] termine en %.0f min -> %s\n", base$col, (proc.time()-t0)[["elapsed"]]/60, basename(f_cache)))
}

# ==============================================================================
# JOINTURE DES CACHES DANS IFN + EXPORT (une seule ecriture)
# ==============================================================================
cat("\n--- Jointure caches -> IFN + export ---\n")
d <- fread(F_IFN, sep = ";")
for (base in BASES) {
  f_cache <- file.path(DIR_CACHE, sprintf("moy_%s.rds", base$col))
  if (!file.exists(f_cache)) { cat(sprintf("  (pas de cache pour %s)\n", base$col)); next }
  res <- readRDS(f_cache)
  newc <- setdiff(names(res), c("idp","campagne"))
  d[, (intersect(newc, names(d))) := NULL]     # re-extraction incrementale propre
  d <- merge(d, res, by = c("idp","campagne"), all.x = TRUE)
}
# Corse : NA sur les nouvelles colonnes (coherent avec le reste du pipeline)
.idx_corse <- d[, which(lon > 8.5 & lat < 43.1)]
newcols <- intersect(cols_produites, names(d))
if (length(.idx_corse) > 0L) for (c in newcols) d[.idx_corse, (c) := NA_real_]

fwrite(d, F_IFN, sep = ";")
cat(sprintf("Export : %s | %d lignes, %d colonnes\n", basename(F_IFN), nrow(d), ncol(d)))
cat(sprintf("Nouvelles colonnes (%d) : %s\n", length(newcols), paste(sort(newcols), collapse = ", ")))
cat(strrep("=", 70), "\n  TERMINE\n", strrep("=", 70), "\n", sep = "")
