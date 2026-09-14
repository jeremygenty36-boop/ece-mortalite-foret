# source("S:/Projets/stage_JeremyG/4-Travail/2-ECE/0-Lanceurs/11-ECE_POSTTRAITEMENT.R")
# ==============================================================================
# POST-TRAITEMENT des sorties ECE : nettoyage des fichiers ECE_<base>_*.nc.
#
#   1. CLAMP aux plages physiques valides (VALID_RANGES) -> toute valeur hors
#      plage passe a NA. Elimine les pixels aberrants (ex. ~-273 C = pixels
#      "manquants" CHELSA codes 0 puis convertis K->C ; valeurs SPEI extremes).
#   2. MASQUE France -> met NA tout pixel hors du territoire (coherence avec
#      les autres bases, et elimine l'ocean / pays voisins).
#   3. AXE TEMPS -> reassigne les dates : TXx/TNn/SPEI6 sortent d'agreger()
#      avec des dates "Inf" (time() ecrit avant la boucle de remplissage).
#
# Les fichiers originaux sont sauvegardes dans <dir>/_avant_posttraitement/
# avant ecrasement.
#
# USAGE : editer BASE ci-dessous puis sourcer. Repeter pour chaque base.
# ==============================================================================

# --- CONFIG : base a traiter --------------------------------------------------
# Surchargeable AVANT source() : poser BASE et (optionnel) INDICES_PT.
if (!exists("BASE")) BASE <- "DIGI_SAF"   # CHELSA | DIGI_EOBS | DIGI_SAF | DIGI_CHEL

# 2026-05-28 : decision avec maitre de stage - passer les valeurs aberrantes
# a NA (retour sur la decision du 2026-05-26). Les aberrants (CHELSA 0K ->
# -273 C pour TNn, SPEI extremes) sont traites comme des donnees manquantes.
APPLIQUER_CLAMP <- TRUE

# --- CHEMINS ------------------------------------------------------------------
.PFX      <- if (dir.exists("S:/Projets")) "S:" else "/Volumes/_donnees"  # CALCULUS (S:) ou Mac (NAS monte)
ROOT      <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/3-ECE/1-ECE_1979-2024")
OUT_DIRS  <- list(EOBS="1-EOBS_11km", SAFRAN="2-SAFRAN_8km",
                  CHELSA="3-CHELSA_1km", DIGI_EOBS="4-DIGI_EOBS_1km",
                  DIGI_SAF="5-DIGI_SAF_1km", DIGI_CHEL="6-DIGI_CHEL_1km")
MASQUE_F  <- file.path(.PFX, "Projets/stage_JeremyG/4-Travail/1-Bases_de_donnees/3-Limites_geo/France_GADM_L0.gpkg")

# Plages physiques valides par indice (cf VALID_RANGES des scripts ECE)
RANGES <- list(
  TXx   = c(-10,  55),   # deg C
  TNn   = c(-60,  20),   # deg C (seuil -60 retenu le 2026-05-28 : -40 trop
                         # agressif sur CHELSA 1km qui resout les pixels alpins
                         # haute altitude ; seul le -273 C du bug 0K 2022 est
                         # reellement impossible)
  SPEI6 = c( -5,   5),   # ecart-type (elargi de [-4,4] a [-5,5] le 2026-05-28
                         # pour conserver les secheresses extremes reelles)
  WG10P = c(  0, 100),   # %
  HWN   = c(  0, 366),   # nb d'episodes / an (>=0 ; borne haute = nb jours/an,
                         # non clippante : sert juste a passer a NA les fill aberrants)
  CWN   = c(  0, 366)    # nb d'episodes / an (idem HWN)
)

# Reassignation de l'axe temps : 1 couche par annee, AN_DEBUT.. (donnees 1979-2024).
# Date conventionnelle = 15 du dernier mois de saison = max(saison_mois) dans
# agreger() (cf 3-ECE_CHELSA.R l.905). TXx MAR-NOV->11 ; TNn SEP-MAY->12
# (max(c(1:5,9:12))=12) ; SPEI6/WG10P MAR-AUG->8 ; HWN MAY-SEP->9 ; CWN SEP-MAY->12.
AN_DEBUT <- 1979L
MOIS_FIN <- list(TXx=11L, TNn=12L, SPEI6=8L, WG10P=8L, HWN=9L, CWN=12L)

suppressPackageStartupMessages(library(terra))

DIR_BASE <- file.path(ROOT, OUT_DIRS[[BASE]])
if (!dir.exists(DIR_BASE)) stop("Dossier base introuvable : ", DIR_BASE)
if (!file.exists(MASQUE_F)) stop("Masque France introuvable : ", MASQUE_F)

masque <- vect(MASQUE_F)
DIR_BK <- file.path(DIR_BASE, "_avant_posttraitement")
if (!dir.exists(DIR_BK)) dir.create(DIR_BK, recursive=TRUE)

cat(strrep("=", 70), "\n", sep="")
cat(sprintf("  POST-TRAITEMENT ECE - base %s\n", BASE))
cat(sprintf("  %s\n", format(Sys.time())))
cat(strrep("=", 70), "\n\n", sep="")

# Sous-ensemble d'indices a post-traiter (surchargeable : ex. INDICES_PT <- "TXx"
# pour ne PAS toucher WG10P/SPEI6/TNn - utile si leurs backups sont perimes).
if (!exists("INDICES_PT")) INDICES_PT <- names(RANGES)
idx_a_traiter <- intersect(names(RANGES), INDICES_PT)
cat(sprintf("  Indices traites : %s\n\n", paste(idx_a_traiter, collapse=", ")))

n_ok <- 0L
for (idx in idx_a_traiter) {
  fics <- list.files(DIR_BASE, pattern=sprintf("^ECE_%s_%s_.*\\.nc$", BASE, idx),
                     full.names=TRUE)
  if (length(fics) == 0) { cat(sprintf("  %-6s : ABSENT (skip)\n", idx)); next }
  f <- fics[1]
  rg <- RANGES[[idx]]

  # Lecture : prefere _avant_posttraitement/ si dispo (= post-traitement
  # anterieur, on repart de l'original), sinon le main (= premier passage).
  # Rend le script idempotent et permet de basculer clampe / non clampe.
  f_orig <- file.path(DIR_BK, basename(f))
  f_read <- if (file.exists(f_orig)) f_orig else f
  r <- tryCatch(rast(f_read), error=function(e) NULL)
  if (is.null(r)) { cat(sprintf("  %-6s : ILLISIBLE (skip)\n", idx)); next }
  vn <- names(r)[1]

  # --- Stats avant ---
  v0  <- values(r)
  n0  <- sum(!is.na(v0))
  n_hors <- sum(v0 < rg[1] | v0 > rg[2], na.rm=TRUE)

  # --- 1) Clamp (optionnel) : hors plage valide -> NA ---
  if (APPLIQUER_CLAMP) {
    r[r < rg[1] | r > rg[2]] <- NA
  }

  # --- 2) Masque France ---
  r <- mask(r, masque)

  # --- 2b) Exclusion Corse (lon > 8.5 ET lat < 43.1) ---
  # Bug DIGITALIS_v3 tmax non corrigeable sur ~1000 pixels Corse centre-sud
  # depuis fevrier 2022 -> decision d'exclure la Corse de l'etude (2026-05-28).
  # Applique a TOUTES les bases pour coherence de la comparaison inter-bases.
  x_r <- init(r[[1]], "x")
  y_r <- init(r[[1]], "y")
  m_corse <- ifel((x_r > 8.5) & (y_r < 43.1), NA, 1)
  r <- mask(r, m_corse)

  # --- 3) Reassignation de l'axe temps (dates "Inf" en sortie d'agreger) ---
  annees_r <- seq(AN_DEBUT, by=1L, length.out=nlyr(r))
  time(r)  <- as.Date(sprintf("%d-%02d-15", annees_r, MOIS_FIN[[idx]]))

  # --- Stats apres ---
  v1 <- values(r); vv <- v1[!is.na(v1)]
  n1 <- length(vv)

  # --- Backup original puis ecrasement ---
  bk <- file.path(DIR_BK, basename(f))
  if (!file.exists(bk)) file.copy(f, bk, copy.date=TRUE)
  tryCatch({
    writeCDF(r, f, varname=vn, overwrite=TRUE, compression=1L)
    n_ok <- n_ok + 1L
    msg_clamp <- if (APPLIQUER_CLAMP)
                   sprintf("clamp [%g, %g] : %d val. hors plage -> NA", rg[1], rg[2], n_hors)
                 else
                   sprintf("clamp DESACTIVE : %d val. hors [%g, %g] conservees", n_hors, rg[1], rg[2])
    cat(sprintf("  %-6s : %s | masque France + exclusion Corse\n", idx, msg_clamp))
    cat(sprintf("           pixels valides : %d -> %d | range final [%.2f, %.2f]\n",
                n0, n1, if(n1>0) min(vv) else NA, if(n1>0) max(vv) else NA))
    cat(sprintf("           axe temps : %s -> %s (%d couches)\n",
                format(min(time(r))), format(max(time(r))), nlyr(r)))
  }, error=function(e) cat(sprintf("  %-6s : ERREUR ecriture : %s\n", idx, conditionMessage(e))))
}

cat(sprintf("\n%d/%d indices post-traites. Originaux sauvegardes dans :\n  %s\n",
            n_ok, length(idx_a_traiter), DIR_BK))
cat(strrep("=", 70), "\n", sep="")
