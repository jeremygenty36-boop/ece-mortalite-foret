# source("R/04_indices_ece/6-ECE_DIGI_SAFRAN.R")   # depuis la racine du depot
# ==============================================================================
# CALCUL INDICES ECE - BASE 5 : DIGITALIS downscale SAFRAN 1km
# CRS natif : EPSG:4326 (WGS84 natif - pas de correction necessaire)
# Resolution : ~1km | Periode : 1979-1989 (base) / 1961-2024 (complet)
# ETP : formule de Turc (radiation estimee par Hargreaves-Samani)
# TNn : calcul mensuel (agregation saisonniere reportee)
# Pas de decoupage spatial : grille complete pour diagnostic NA
# ==============================================================================

# Verifier que climdex.pcic.ncdf est installe (depuis source locale).
# IMPORTANT : ne PAS reinstaller en parallele (race condition sur 00LOCK).
# Si pas installe, faire UNE installation manuelle avant de lancer les 5 periodes :
#   pkg_src <- file.path(CLIMPACT_RACINE, "server", "pcic_packages", "climdex.pcic.ncdf")
#   install.packages(pkg_src, repos=NULL, type="source")
# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
{
  .pkg_src <- file.path(CLIMPACT_RACINE, "server", "pcic_packages", "climdex.pcic.ncdf")
  if (!requireNamespace("climdex.pcic.ncdf", quietly=TRUE)) {
    .lock_dir <- file.path(.libPaths()[1], "00LOCK-climdex.pcic.ncdf")
    if (dir.exists(.lock_dir)) unlink(.lock_dir, recursive=TRUE)
    cat("[INSTALL] climdex.pcic.ncdf absent - installation depuis source locale...\n")
    install.packages(.pkg_src, repos=NULL, type="source", quiet=TRUE)
    if (!requireNamespace("climdex.pcic.ncdf", quietly=TRUE))
      stop("Echec installation climdex.pcic.ncdf - lancer manuellement install.packages('", .pkg_src, "', repos=NULL, type='source')")
    cat("[INSTALL] OK\n")
  } else {
    cat("[INSTALL] climdex.pcic.ncdf deja installe - skip\n")
  }
}

suppressPackageStartupMessages({
  library(terra)
  library(lubridate)
  library(climdex.pcic.ncdf)
  library(parallel)
})

pkgs_requis <- c("SPEI", "ncdf4", "ncdf4.helpers", "PCICt", "snow", "proj4")
manquants <- pkgs_requis[!sapply(pkgs_requis, requireNamespace, quietly=TRUE)]
if (length(manquants) > 0) install.packages(manquants)

# ==============================================================================
# PARAMETRES
# ==============================================================================

ROOT_LOC     <- LOCAL_ROOT
ECE_ROOT     <- file.path(PROJET, "ECE_data")             # donnees sources sur reseau partage (S:)
MERGE_DIR    <- file.path(ROOT_LOC, "ECE_merge", "DIGI_SAFRAN")  # fusion locale (I/O rapide)
OUT_DIR      <- file.path(PROJET, "5-Resultats", "3-ECE", "1-ECE_1979-2024", "5-DIGI_SAF_1km")
CLIMPACT_DIR <- CLIMPACT_RACINE

BASE <- list(
  code       = "DIGI_SAF",
  dir        = local({
    .loc <- file.path(LOCAL_ROOT, "ECE_data/5-DIGI_SAF_1km")
    .nas <- file.path(PROJET, "3-Donnees/5-DIGITALIS/5-DIGI_SAF_1km_nc")
    # 2026-05-22 : dir.exists() seul validait un dossier D:/ vide (copie locale
    #   jamais terminee) -> fusionner() ne trouvait aucun .nc -> "Fichiers
    #   sources manquants". On ne bascule sur D:/ que s'il est complet.
    .n_loc <- if (dir.exists(.loc)) length(list.files(.loc, "\\.nc$")) else 0L
    .n_nas <- length(list.files(.nas, "\\.nc$"))
    if (.n_loc > 0L && .n_loc >= .n_nas) .loc else .nas
  }),
  debut      = 1979L,  # 1979-2024 (46 ans, ne calcule plus avant 1979)
  fin        = 2024L,
  etp_native = FALSE,
  wg_native  = FALSE,
  crs_native = NULL   # EPSG:4326 natif
)

BASE_START    <- 1979L
BASE_END      <- 1989L
FULL_DEBUT    <- 1979L
FULL_FIN      <- 2024L

# ---------------------------------------------------------------------------
# DECOUPAGE TEMPOREL EN 5 PERIODES (execution parallele via Rscript)
# Usage : Rscript X-ECE_BASE.R <1|2|3|4|5>   (1 periode sur 5)
#         Rscript X-ECE_BASE.R               (toutes les periodes : FULL_DEBUT/FULL_FIN)
#
# Chaque periode inclut 1 an de chevauchement au debut pour le precalcul SPEI-6
# (le fichier fusionne commence 1 an avant le debut de calcul effectif)
# ---------------------------------------------------------------------------
PERIODES <- list(
  list(debut=1979L, fin=1987L, tag="1979-1987"),  # P1 : pas de warmup (debut absolu)
  list(debut=1987L, fin=1996L, tag="1987-1996"),  # P2 : 1987 = warmup pour SPEI jan 1988
  list(debut=1996L, fin=2005L, tag="1996-2005"),  # P3
  list(debut=2005L, fin=2014L, tag="2005-2014"),  # P4
  list(debut=2014L, fin=2024L, tag="2014-2024")   # P5
)

# Lecture de l'index de periode (argument Rscript ou variable locale)
# PERIODE_IDX = 0 → toute la periode (FULL_DEBUT/FULL_FIN inchanges)
# PERIODE_IDX = 1..5 → periode specifique
PERIODE_IDX <- 0L
.args_cli <- tryCatch(commandArgs(trailingOnly=TRUE), error=function(e) character(0))
if (length(.args_cli) >= 1 && grepl("^[0-5]$", .args_cli[1]))
  PERIODE_IDX <- as.integer(.args_cli[1])

if (PERIODE_IDX >= 1L && PERIODE_IDX <= 5L) {
  FULL_DEBUT <- PERIODES[[PERIODE_IDX]]$debut
  FULL_FIN   <- PERIODES[[PERIODE_IDX]]$fin
  cat(sprintf("[PERIODE] P%d : %d-%d\n", PERIODE_IDX, FULL_DEBUT, FULL_FIN))
  # Sous-dossier P1..P5 pour eviter race condition entre periodes paralleles
  MERGE_DIR <- file.path(MERGE_DIR, sprintf("P%d", PERIODE_IDX))
}

# Nombre de periodes lancees simultanement sur cette machine (argument 2, defaut=5)
# Passe automatiquement par les scripts 0-Lancer_MACHINE.R
if (!exists("N_PARALLEL_ECE")) N_PARALLEL_ECE <- tryCatch({
  val <- if (length(.args_cli) >= 2L) as.integer(.args_cli[2]) else 5L
  if (is.na(val) || val < 1L || val > 5L) 5L else val
}, error=function(e) 5L)
if (PERIODE_IDX >= 1L)
  cat(sprintf("[MACHINE]  %d periode(s) en simultane sur cette machine\n", N_PARALLEL_ECE))

# --- Surcharge SANDBOX (test bout-en-bout) : entree/sortie isolees + periode ---
# Le NC d'entree est deja croppe par la conversion -> pas de crop a gerer ici.
# ATTENTION : avec une periode tres courte, la reference climpact (BASE_START/END)
# est degeneree -> indices ref-dependants (SPEI/WG10/HWN/CWN) non significatifs (cf demarche test).
if (exists("SANDBOX_OUT")) {
  ECE_ROOT  <- file.path(SANDBOX_OUT, "ECE_data")
  MERGE_DIR <- file.path(SANDBOX_OUT, "ECE_merge", "DIGI_SAFRAN")
  OUT_DIR   <- file.path(SANDBOX_OUT, "results_ECE", "5-DIGI_SAF_1km")
  BASE$dir  <- file.path(SANDBOX_OUT, "ECE_data", "5-DIGI_SAF_1km")
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
}

# --- Plan B (2026-06-12) : SORTIE en LOCAL pour eviter les stalls d'ecriture NAS ---
# Poser OUT_DIR_LOCAL avant le source() -> climpact_raw + sorties agregees ecrites en
# LOCAL (D:, I/O fiable et rapide), les ENTREES restant inchangees (ECE_ROOT/MERGE_DIR/
# BASE$dir). On copie ENSUITE le seul ECE_DIGI_SAF_TNn_SEP-MAY.nc final sur S: a la main
# (backup corbeille + verif). N'altere RIEN sur S: pendant le run.
if (exists("OUT_DIR_LOCAL")) {
  OUT_DIR <- OUT_DIR_LOCAL
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("[PLAN B] sortie redirigee en LOCAL : %s\n", OUT_DIR))
}
if (exists("SANDBOX_ANNEES")) {
  FULL_DEBUT <- min(SANDBOX_ANNEES); FULL_FIN <- max(SANDBOX_ANNEES)
  BASE$debut <- FULL_DEBUT; BASE$fin <- FULL_FIN
  # Reference : on CONSERVE la ref prod 1979-1989 si la periode la couvre entierement
  # (cas A -> indices comparables au prod, ref per-pixel identique meme croppee).
  # Sinon (cas B, periode courte type 2014) la ref degenere a la periode -> indices
  # ref-dependants NON significatifs / non comparables (validation code seulement).
  if (!(FULL_DEBUT <= 1979L && FULL_FIN >= 1989L)) { BASE_START <- FULL_DEBUT; BASE_END <- FULL_FIN }
}

# ============================================================================
# 2026-06-03 : RECALCUL CIBLE apres reparation DIGI_SAF_prec_1987.nc
# 1987 est dans la periode de reference SPEI (base.range 1979-1989). Seuls les
# indices dependant des precipitations changent (SPEI, WG10P). TXx/TNn sont des
# indices de temperature -> NON affectes -> on evite de les recalculer (gros gain
# sur Climpact). ETP et fusions tmax/tmin (temperature) sont conserves/skippes.
# Repasser RECOMPUTE_PREC_ONLY <- FALSE pour un run complet normal.
# 2026-06-08 : repasse a FALSE. prec_1987 verifie sain (0-Verif_prec_1987.py),
#   SPEI6 restaure depuis le .bak verifie. Ne plus invalider prec/SPEI/WG10P.
# ============================================================================
RECOMPUTE_PREC_ONLY <- FALSE

INDICES_CIBLE <- if (RECOMPUTE_PREC_ONLY) c("spei") else c("txx", "tnn", "spei")
SAISONS       <- list(MAM=3:5, JJA=6:8, SON=9:11, DJF=c(12L,1L,2L), VEG=4:9)
COMPRESSION   <- 5L
CROP_EXT      <- NULL  # sera defini depuis le masque France ci-dessous
# PATCH 2026-05-06 : plafond CPU global - regle a 70% (= 50 sur 72) pour run
# avec utilisateur SEUL sur CALCULUS. calc_etp DIGI 1km est RAM-bound (~11 workers
# max via .max_workers_ram), CPU eleve impacte surtout Climpact + fusion 3-vars.
# Marge RAM ~90 GB sur 382 conservee. Pour run en parallele -> repasser a 0.20.
if (!exists("MAX_CPU_FRAC")) MAX_CPU_FRAC <- 0.90  # DEBRIDE (seul sur CALCULUS) ; surchargeable avant source()
.n_cores_max  <- max(2L, floor(parallel::detectCores() * MAX_CPU_FRAC))
# PATCH 2026-05-21 : plafond RAM. Les formules de parallelisme ne reservaient
# que 8 GB de marge -> 20 workers ETP x 17 GB = 97% RAM sur CALCULUS (machine
# partagee). Le job se limite desormais a MAX_RAM_FRAC de la RAM libre.
if (!exists("MAX_RAM_FRAC")) MAX_RAM_FRAC <- 0.85  # DEBRIDE ; surchargeable avant source()
N_CORES       <- if (N_PARALLEL_ECE > 1L) max(2L, floor((parallel::detectCores() - 2L) / N_PARALLEL_ECE)) else max(2L, parallel::detectCores() - 2L)
N_CORES       <- min(N_CORES, .n_cores_max)
cat(sprintf("[CPU] Plafond %.0f%% : N_CORES = %d / %d\n",
            MAX_CPU_FRAC*100, N_CORES, parallel::detectCores()))
AUTHOR_DATA   <- list(institution="UMR Silva / AgroParisTech", institution_id="SILVA")
VALID_RANGES  <- list(
  txx  = list(min=-10,  max=55,  unit="C",  desc="Max temperature max"),
  tnn  = list(min=-40,  max=20,  unit="C",  desc="Min temperature min"),
  spei6= list(min=-4,   max=4,   unit="sd", desc="SPEI-6"),
  wg10p= list(min=0,    max=100, unit="%",  desc="% jours WG < Q10")
)

terraOptions(progress=1, memfrac=0.9, threads=N_CORES)
for (d in c(MERGE_DIR, OUT_DIR)) if (!dir.exists(d)) dir.create(d, recursive=TRUE)

MASQUE_FRANCE_F <- MASQUE_FRANCE_GPKG
MASQUE_FRANCE <- if (file.exists(MASQUE_FRANCE_F)) {
  tryCatch(vect(MASQUE_FRANCE_F), error=function(e) { cat("[WARN] Masque France illisible\n"); NULL })
} else {
  cat("[WARN] Masque France absent, calcul sans masque :", MASQUE_FRANCE_F, "\n"); NULL
}
# CROP_EXT : bbox du masque France + buffer 0.2 deg
# Reduit la grille d'entree a France uniquement avant Climpact (gain x10-100 sur 1km)
CROP_EXT <- if (!is.null(MASQUE_FRANCE)) {
  tryCatch(ext(MASQUE_FRANCE) + 0.2, error=function(e) NULL)
} else NULL
if (!is.null(CROP_EXT))
  cat(sprintf("[CROP] Domaine restreint a France + buffer : lon [%.1f, %.1f]  lat [%.1f, %.1f]\n",
              CROP_EXT$xmin, CROP_EXT$xmax, CROP_EXT$ymin, CROP_EXT$ymax))

# ==============================================================================
# FONCTIONS UTILITAIRES
# ==============================================================================

ok  <- function(msg) cat(sprintf("    [OK]  %s\n", msg))
err <- function(msg) cat(sprintf("    [ERR] %s\n", msg))
inf <- function(msg) cat(sprintf("    [..]  %s\n", msg))

# Suppression SECURISEE : deplace vers _corbeille/ (horodate, meme volume = instantane)
# au lieu de supprimer definitivement. Drop-in de file.remove (paths -> logical).
# Reserve aux fichiers DATA (journaliers fusionnes, sorties ECE). Les _tmp volumineux
# restent en file.remove (sinon _corbeille sature le disque).
supprimer <- function(paths) {
  paths <- paths[!is.na(paths) & file.exists(paths)]
  if (!length(paths)) return(invisible(logical(0)))
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  vapply(paths, function(p) {
    cb <- file.path(dirname(p), "_corbeille")
    if (!dir.exists(cb)) dir.create(cb, showWarnings = FALSE, recursive = TRUE)
    dest <- file.path(cb, sprintf("%s.%s.bak", basename(p), stamp))
    okm <- tryCatch(file.rename(p, dest), error = function(e) FALSE)
    if (!okm) okm <- tryCatch(file.copy(p, dest, overwrite = FALSE) && file.remove(p), error = function(e) FALSE)
    if (isTRUE(okm)) inf(sprintf("CORBEILLE : %s -> _corbeille/", basename(p)))
    isTRUE(okm)
  }, logical(1))
}

# Logging timestampe direct sur D: (bypass Tee-Object PowerShell qui ne flush jamais).
.PROGRESS_LOG <- NULL
log_d <- function(msg) {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  ligne <- sprintf("[%s] %s\n", ts, msg)
  cat(ligne)
  if (!is.null(.PROGRESS_LOG)) {
    tryCatch({
      con <- file(.PROGRESS_LOG, open="a", encoding="UTF-8")
      writeLines(ligne, con, sep=""); close(con)
    }, error=function(e) NULL)
  }
}
log_d_init <- function(merge_dir) {
  if (!dir.exists(merge_dir)) dir.create(merge_dir, recursive=TRUE)
  .PROGRESS_LOG <<- file.path(merge_dir, "_progress.log")
  log_d(sprintf("=== Init progress log : %s (PID=%d) ===", .PROGRESS_LOG, Sys.getpid()))
}

# PATCH 2026-05-22 : assemblage NC 100% ncdf4, lit directement les fichiers
# sources annuels (l'etape per-annee rast()->writeCDF() est supprimee, cf
# fusionner). Rebascule le temps : chaque fichier annuel a sa propre origine
# ("days since AAAA-01-01") -> conversion en dates absolues + axe temps unique.
# --- Avancement partage (lu par 0-Watcher_ntfy.R) -----------------------------
# Ecrit l etat courant d une etape longue dans un petit fichier (1 ligne, ecrase
# a chaque maj). Jamais bloquant (try). Format : ts|base|etape|courant|total|msg
STATUS_AVANCEMENT <- file.path(if (dir.exists(LOCAL_ROOT)) file.path(LOCAL_ROOT, "ECE_merge") else tempdir(), "_avancement.txt")
maj_avancement <- function(base, etape, courant = NA, total = NA, msg = "") {
  try({
    d <- dirname(STATUS_AVANCEMENT)
    if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
    writeLines(paste(as.integer(Sys.time()), base, etape, courant, total, msg, sep = "|"),
               STATUS_AVANCEMENT)
  }, silent = TRUE)
}

.assemble_ncdf4 <- function(fics, f_out, varname, units = "") {
  ncs <- lapply(fics, ncdf4::nc_open)
  on.exit(lapply(ncs, function(nc) try(ncdf4::nc_close(nc), silent = TRUE)), add = TRUE)

  vexcl  <- c("lon","lat","longitude","latitude","x","y",
              "time","time_bnds","time_bounds","crs","bnds")
  vn1    <- names(ncs[[1]]$var)[!tolower(names(ncs[[1]]$var)) %in% vexcl]
  vn_src <- if (length(vn1) > 0)
              vn1[which.max(vapply(vn1, function(v) length(ncs[[1]]$var[[v]]$dim), 1L))]
            else varname
  v1     <- ncs[[1]]$var[[vn_src]]
  dims   <- v1$dim
  dnames <- vapply(dims, function(d) d$name, "")
  t_pos  <- which(dnames == "time")
  if (length(t_pos) != 1L) stop("dimension 'time' introuvable dans ", basename(fics[1]))

  # Rebasage du temps : chaque fichier annuel a sa propre origine
  .dates_fic <- function(nc) {
    td <- nc$dim[["time"]]
    if (is.null(td)) stop("dimension 'time' absente")
    tu <- td$units
    sc <- if      (grepl("hour", tu, ignore.case = TRUE)) 1/24
          else if (grepl("min",  tu, ignore.case = TRUE)) 1/1440
          else if (grepl("sec",  tu, ignore.case = TRUE)) 1/86400
          else 1
    orig <- regmatches(tu, regexpr("[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}", tu))
    if (length(orig) == 0L) stop("origine temps illisible : ", tu)
    as.Date(as.numeric(td$vals) * sc, origin = orig)
  }
  dates_fic <- lapply(ncs, .dates_fic)
  all_dates <- do.call(c, dates_fic)
  if (is.unsorted(all_dates))
    stop("axe temps non croissant - fichiers dans le desordre ?")
  origine <- min(all_dates)
  all_t   <- as.numeric(all_dates - origine)
  t_unit  <- sprintf("days since %s 00:00:00", format(origine, "%Y-%m-%d"))

  out_dims <- vector("list", length(dims))
  for (i in seq_along(dims)) {
    if (i == t_pos) {
      out_dims[[i]] <- ncdf4::ncdim_def("time", t_unit, all_t,
                                        unlim = TRUE, calendar = "standard")
    } else {
      out_dims[[i]] <- ncdf4::ncdim_def(dims[[i]]$name, dims[[i]]$units,
                                        as.numeric(dims[[i]]$vals))
    }
  }
  v_out  <- ncdf4::ncvar_def(varname, units, out_dims, missval = v1$missval,
                             prec = "float", compression = 1L)
  nc_out <- ncdf4::nc_create(f_out, v_out)
  on.exit(try(ncdf4::nc_close(nc_out), silent = TRUE), add = TRUE)

  start_t <- 1L
  .pb <- utils::txtProgressBar(min = 0, max = length(ncs), style = 3)  # avancement assemblage
  for (k in seq_along(ncs)) {
    dat   <- ncdf4::ncvar_get(ncs[[k]], vn_src, collapse_degen = FALSE)
    start <- rep(1L, length(dim(dat))); start[t_pos] <- start_t
    ncdf4::ncvar_put(nc_out, varname, dat, start = start, count = dim(dat))
    log_d(sprintf("  [%s] assemble %d/%d (%d couches)",
                  varname, k, length(ncs), dim(dat)[t_pos]))
    start_t <- start_t + dim(dat)[t_pos]
    rm(dat); gc(verbose = FALSE); utils::setTxtProgressBar(.pb, k)
    maj_avancement(sub("_(tmax|tmin|prec).*$", "", basename(f_out)), paste0("assemblage_", varname), k, length(ncs))
  }
  close(.pb)
  if (start_t - 1L != length(all_t))
    stop(sprintf("incoherence : %d couches ecrites / %d attendues",
                 start_t - 1L, length(all_t)))
  invisible(f_out)
}

fmt_dur <- function(s) {
  s <- as.numeric(s)
  if (s < 60)   return(sprintf("%.0f s", s))
  if (s < 3600) return(sprintf("%d min %02.0f s", s%/%60, s%%60))
  return(sprintf("%d h %02d min", s%/%3600, (s%%3600)%/%60))
}

prog_bar <- function(i, n, label="", width=30) {
  pct  <- i/n; done <- round(pct*width)
  bar  <- paste0("[", strrep("=", done), strrep(" ", width-done), "]")
  cat(sprintf("\r  %s %s %3.0f%% (%d/%d)", bar, label, pct*100, i, n))
  flush.console()
  if (i==n) cat("\n")
}

# Corrige OGC:CRS84 -> EPSG:4326 si necessaire (meme datum, ordre des axes different)
corriger_crs <- function(r) {
  desc <- tryCatch(crs(r, describe=TRUE), error=function(e) NULL)
  if (!is.null(desc) && !is.na(desc$authority) &&
      desc$authority == "OGC" && desc$code == "CRS84") {
    crs(r) <- "EPSG:4326"
  }
  r
}

# PATCH 2026-05-22 : fusion = assemblage ncdf4 direct des fichiers sources.
# L'ancienne etape per-annee (rast() -> writeCDF(), ~1.2 Mo/s) est supprimee.
fusionner <- function(base_dir, base_code, varname, debut, fin, merge_dir, crop_ext = NULL) {
  f_out <- file.path(merge_dir, sprintf("%s_%s_%d-%d_TEST.nc", base_code, varname, debut, fin))

  if (file.exists(f_out)) {                       # SKIP si deja produit et complet
    n_attendu <- sum(vapply(debut:fin, function(y)
      if (y %% 4 == 0 && (y %% 100 != 0 || y %% 400 == 0)) 366L else 365L, 1L))
    besoin_recreer <- tryCatch({
      # Garde-fou anti-fichier-vide (1 MB) ; completude reelle jugee par nlyr,
      # regime-independant (France entiere multi-GB ET crop sandbox ~0.1 GB).
      # Avant : 500 MB en dur -> recalcul force des fichiers sandbox valides.
      if (file.size(f_out) / 1e6 < 1) TRUE else nlyr(rast(f_out)) < n_attendu * 0.95
    }, error = function(e) TRUE)
    if (!besoin_recreer) { inf(sprintf("SKIP fusion (existe) : %s", basename(f_out))); return(f_out) }
    supprimer(f_out)
  }

  fics <- file.path(base_dir, sprintf("%s_%s_%d.nc", base_code, varname, debut:fin))
  fics <- fics[file.exists(fics)]
  if (length(fics) == 0) { err(sprintf("Aucun fichier %s_%s", base_code, varname)); return(NULL) }
  log_d(sprintf("Fusion %s %s : %d fichiers, assemblage ncdf4 direct", base_code, varname, length(fics)))
  inf(sprintf("Fusion %s %s (%d ans) - assemblage direct...", base_code, varname, length(fics)))
  t0 <- proc.time()[["elapsed"]]

  u_src <- tryCatch({                             # unite de la variable
    nc1 <- ncdf4::nc_open(fics[1])
    vexcl <- c("lon","lat","longitude","latitude","x","y","time","time_bnds","time_bounds","crs","bnds")
    vd <- names(nc1$var)[!tolower(names(nc1$var)) %in% vexcl]
    u  <- if (length(vd) > 0)
            nc1$var[[ vd[which.max(vapply(vd, function(v) length(nc1$var[[v]]$dim), 1L))] ]]$units
          else ""
    ncdf4::nc_close(nc1)
    if (is.null(u)) "" else u
  }, error = function(e) "")

  # Seuil de succes RELATIF aux entrees (0.5x la somme des sources, deja
  # compressees) : valable France entiere (multi-GB) ET crop sandbox (~0.1 GB).
  # Avant : 5e8 en dur. (Ici on assemble fics directement, deja croppes en sandbox.)
  min_ok <- 0.5 * sum(file.size(fics))
  ok_w <- tryCatch({                              # Strategie 1 : ncdf4 direct
    .assemble_ncdf4(fics, f_out, varname, u_src)
    file.exists(f_out) && file.size(f_out) > min_ok
  }, error = function(e) { log_d(sprintf("Assemblage ncdf4 ERR : %s", conditionMessage(e))); FALSE })

  if (!ok_w) {                                    # Strategie 2 : fallback terra
    log_d("Fallback assemblage via terra::writeCDF")
    if (file.exists(f_out)) supprimer(f_out)
    r_all <- tryCatch(corriger_crs(rast(fics)), error = function(e) { err(conditionMessage(e)); NULL })
    if (!is.null(r_all)) {
      ok_w <- tryCatch({ writeCDF(r_all, f_out, varname = varname, compression = 1, overwrite = TRUE); TRUE },
                       error = function(e) { log_d(sprintf("ERR writeCDF fallback : %s", conditionMessage(e))); FALSE })
      rm(r_all); gc()
    }
  }

  if (ok_w) {
    dt <- (proc.time()[["elapsed"]] - t0) / 60
    log_d(sprintf("Fusion %s OK : %.0f Mo en %.1f min", varname, file.size(f_out) / 1e6, dt))
    ok(sprintf("Fusion %s OK : %.0f Mo (%.1f min)", varname, file.size(f_out) / 1e6, dt))
    f_out
  } else { log_d(sprintf("Fusion %s ECHEC", varname)); err(sprintf("Fusion %s ECHEC", varname)); NULL }
}

# ETP par la formule de Turc
# Rs estimee par modele de Hargreaves : Rs = 0.16 * sqrt(Tmax-Tmin) * Ra
# Conversion : 1 MJ/m2 = 23.884 cal/cm2
# Turc : ETP = 0.013 * Tm/(Tm+15) * (Rs_cal + 50)  [mm/jour, si Tm > 0]
# PATCH 2026-05-06 : fusion ETP via Python (netCDF4) - cf 3-ECE_CHELSA.R pour details.
.fusion_etp_via_python <- function(tmp_files, f_out,
                                   py_exe = PYTHON_EXE,
                                   py_script = file.path(DEPOT, "python", "ece_helpers", "_fusion_etp_concat.py")) {
  if (!file.exists(py_exe))    stop("Python introuvable : ", py_exe)
  if (!file.exists(py_script)) stop("Script Python introuvable : ", py_script)
  merge_dir <- dirname(f_out[1]); out_name <- basename(f_out[1])
  cat(sprintf("[FUSION ETP] Delegation a Python (%s)\n", py_script))
  cmd <- paste(shQuote(py_exe), shQuote(py_script),
               shQuote(merge_dir), shQuote(out_name))
  ts0 <- Sys.time()
  ret <- system(cmd)
  dur <- as.numeric(Sys.time() - ts0, units = "mins")
  if (ret != 0L) stop(sprintf("Fusion Python echouee (exit %d, %.1f min)", ret, dur))
  cat(sprintf("[FUSION ETP] Python OK : %.1f min, %.2f GB\n",
              dur, file.size(f_out)/1e9))
  invisible(f_out)
}

# Validation de CONTENU pour les SKIP "deja fait" : un fichier n'est accepte que
# s'il est lisible ET qu'au moins la moitie des couches echantillonnees portent de
# la donnee (sinon perime / tronque / quasi-100% NA -> on regenere). Le seuil 50%
# tolere quelques annees NA intentionnelles (ex. 2022 CHE-C) mais rejette un fichier
# essentiellement NA (ex. SAF-DS TNn). Echantillonne (spatSample) -> peu couteux
# meme sur les gros journaliers (ETP). Doute (illisible) -> invalide (on regenere).
index_valide <- function(f, n_couches = 24L, frac_min = 0.5) {
  if (!file.exists(f)) return(FALSE)
  r <- tryCatch(terra::rast(f), error = function(e) NULL)
  if (is.null(r) || terra::nlyr(r) == 0L) return(FALSE)
  js <- unique(round(seq(1L, terra::nlyr(r), length.out = min(terra::nlyr(r), n_couches))))
  ok <- tryCatch(
    vapply(js, function(j) nrow(terra::spatSample(r[[j]], 300L, "regular", na.rm = TRUE)) > 0L, logical(1)),
    error = function(e) NA)
  if (anyNA(ok)) return(FALSE)
  mean(ok) >= frac_min
}

calc_etp_turc <- function(f_tmax, f_tmin, f_out, compression=1) {
  # SKIP seulement si existe, > 1 MB (pas un residu de crash) ET contenu valide (non-NA)
  if (file.exists(f_out) && file.size(f_out) > 1e6 && index_valide(f_out)) {
    inf(sprintf("SKIP ETP : %s (%.0f Mo)", basename(f_out), file.size(f_out)/1e6))
    return(f_out)
  }
  if (file.exists(f_out)) {
    cat(sprintf("  [WARN] %s existe mais < 1 Mo (residu crash) - regenere\n", basename(f_out)))
    supprimer(f_out)
  }
  inf("Calcul ETP Turc (Rs estimee par Hargreaves)...")
  dates   <- time(rast(f_tmax))
  years   <- sort(unique(year(dates)))
  lat_rad <- mean(yFromRow(rast(f_tmax)[[1]], seq(1, nrow(rast(f_tmax)[[1]]), length.out=10))) * pi/180

  # Ra journalier (MJ/m2/jour) pour chaque pas de temps
  ra_vec <- sapply(yday(dates), function(J) {
    dr <- 1 + 0.033*cos(2*pi*J/365)
    d  <- 0.409*sin(2*pi*J/365 - 1.39)
    ws <- acos(pmax(-1, pmin(1, -tan(lat_rad)*tan(d))))
    (24*60/pi)*0.082*dr*(ws*sin(lat_rad)*sin(d) + cos(lat_rad)*cos(d)*sin(ws))
  })

  # PATCH 2026-05-06 : pre-check tmp existants - reprise apres crash de fusion
  tmp_files_attendus <- vapply(years, function(an)
    sub("\\.nc$", sprintf("_etpturc_tmp_%d.nc", an), f_out),
    character(1))
  tmp_existants <- file.exists(tmp_files_attendus) &
                   file.size(tmp_files_attendus) > 1e6
  if (all(tmp_existants)) {
    inf(sprintf("REUSE ETP : %d tmp annuels existants - skip calcul parallele",
                length(years)))
    tmp_files <- tmp_files_attendus
  } else {
    # PATCH 2026-05-06 : check RAM-aware (cap par RAM libre, eviter OOM avec MAX_CPU_FRAC eleve)
    .ram_free_gb_etp <- tryCatch({
      if (.Platform$OS.type == "windows") {
        .raw <- system("wmic OS get FreePhysicalMemory /format:list", intern=TRUE,
                       ignore.stderr=TRUE)
        as.numeric(sub("^FreePhysicalMemory=", "",
                       .raw[grepl("FreePhysicalMemory=", .raw)])) / 1024^2
      } else 32
    }, error = function(e) 32)
    .ncol_e <- ncol(rast(f_tmax)); .nrow_e <- nrow(rast(f_tmax))
    .gb_par_worker <- 18  # worker cappe a memmax=16 Go (+marge R) ; ancien x10 sous-utilisait (RAM a 10%) -> plus de workers
    .max_workers_ram <- max(1L, floor(.ram_free_gb_etp * MAX_RAM_FRAC / max(1, .gb_par_worker)))
    n_c <- max(1L, min(length(years), N_CORES, .max_workers_ram))
    inf(sprintf("ETP : %d workers (RAM libre %.0f GB, ~%.1f GB/worker)",
                n_c, .ram_free_gb_etp, .gb_par_worker))
    cl  <- makeCluster(n_c, type="PSOCK")
    on.exit(stopCluster(cl), add=TRUE)
    clusterEvalQ(cl, { library(terra); library(lubridate); terraOptions(memmax = 16, threads = 4) })  # PATCH 2026-05-21 : bride la RAM terra par worker (sinon memfrac 0.6 par defaut -> pics 100%)
    clusterExport(cl, c("f_tmax","f_tmin","dates","ra_vec","f_out"), envir=environment())

    tmp_list <- parLapply(cl, seq_along(years), function(i) {
      an  <- years[i]
      idx <- which(year(dates) == an)
      f_tmp <- sub("\\.nc$", sprintf("_etpturc_tmp_%d.nc", an), f_out)
      # PATCH 2026-05-06 : skip si tmp annuel deja calcule (reprise)
      if (file.exists(f_tmp) && file.size(f_tmp) > 1e6) return(f_tmp)
      r_tx <- rast(f_tmax)[[idx]]
      r_tn <- rast(f_tmin)[[idx]]
      r_tm <- (r_tx + r_tn) / 2
      r_dt <- ifel(r_tx > r_tn, sqrt(r_tx - r_tn), 0)
      ra_i <- ra_vec[idx]
      r_list <- lapply(seq_along(idx), function(j) {
        Rs_cal <- r_dt[[j]] * 0.16 * ra_i[j] * 23.884
        ifel(r_tm[[j]] > 0,
             0.013 * r_tm[[j]] / (r_tm[[j]] + 15) * (Rs_cal + 50),
             0)
      })
      r_etp <- do.call(c, r_list)
      time(r_etp) <- dates[idx]
      writeCDF(r_etp, f_tmp, varname="etp", compression=1, overwrite=TRUE)
      f_tmp
    })
    tmp_files <- unlist(tmp_list); tmp_files <- tmp_files[file.exists(tmp_files)]
  }

  # PATCH 2026-05-06 : fusion via Python (contourne bug long vector)
  tryCatch({
    .fusion_etp_via_python(tmp_files, f_out)
    .nlyr_tot <- sum(vapply(tmp_files,
                            function(f) tryCatch(nlyr(rast(f)),
                                                 error=function(e) 0L),
                            numeric(1)))
    ok(sprintf("ETP Turc OK : %d couches, %.0f Mo",
               .nlyr_tot, file.size(f_out)/1e6))
  }, error=function(e) err(sprintf("Fusion ETP : %s", conditionMessage(e))))

  # PATCH 2026-05-04 + 2026-05-06 : test sur la couche du milieu (couche 1 peut etre NA)
  .etp_check_ok <- FALSE
  if (file.exists(f_out) && file.size(f_out) > 1e6) {
    .etp_check_ok <- tryCatch({
      r_chk <- rast(f_out)
      if (nlyr(r_chk) == 0) FALSE
      else {
        .lyr_milieu <- max(1L, round(nlyr(r_chk) / 2))
        n_valid <- global(r_chk[[.lyr_milieu]], "notNA")$notNA
        !is.null(n_valid) && n_valid > 0
      }
    }, error=function(e) FALSE)
  }
  if (.etp_check_ok) {
    file.remove(tmp_files[file.exists(tmp_files)])
  } else {
    err(sprintf("ETP final CORROMPU (100%% NA ou absent, %.1f GB) - tmp_files conserves pour reprise manuelle",
                if (file.exists(f_out)) file.size(f_out)/1e9 else 0))
    stop("ETP corrompu, arret avant Climpact (SPEI necessite ETP). ",
         "Voir tmp_files dans MERGE_DIR pour diagnostic ou reprise manuelle.")
  }
  gc(); f_out
}

lire_climpact_ncdf4 <- function(f_nc, template_r, spei_scale=2) {
  nc <- tryCatch(ncdf4::nc_open(f_nc), error=function(e) NULL)
  if (is.null(nc)) return(NULL)
  on.exit(ncdf4::nc_close(nc))
  excl <- c("lon","lat","longitude","latitude","x","y","time","time_bnds","crs","bnds")
  # 2026-06-08 : exclure les variables compagnes day_of_* (jour du max/min) pour ne
  # JAMAIS les agreger avec l'indice (cf bug TXx day_of_txx). Robuste a l'ordre des var.
  vn_data <- names(nc$var)[!tolower(names(nc$var)) %in% excl & !grepl("^day_of", names(nc$var), ignore.case = TRUE)]
  if (length(vn_data)==0) vn_data <- names(nc$var)
  vname <- vn_data[which.max(sapply(vn_data, function(v) length(nc$var[[v]]$dim)))]
  dat <- tryCatch(ncdf4::ncvar_get(nc, vname, collapse_degen=FALSE), error=function(e) NULL)
  if (is.null(dat)) return(NULL)
  d <- dim(dat)
  if (length(d)==4) {
    if (d[4]<=4 && d[3]>4) { dat <- dat[,,,min(spei_scale,d[4])] } else { dat <- dat[,,min(spei_scale,d[3]),] }
    d <- dim(dat)
  }
  if (length(d)==2) dim(dat) <- c(d[1],d[2],1)
  nt <- dim(dat)[3]; storage.mode(dat) <- "double"
  dates_out <- tryCatch({
    t_val <- ncdf4::ncvar_get(nc,"time"); t_unit <- ncdf4::ncatt_get(nc,"time","units")$value
    if (grepl("months since", t_unit, ignore.case=TRUE)) {
      origin_d <- as.Date(trimws(sub("(?i)months since","",t_unit)))
      tot_m <- as.integer(format(origin_d,"%Y"))*12L+as.integer(format(origin_d,"%m"))-1L+as.integer(round(t_val))
      as.Date(sprintf("%d-%02d-15", tot_m%/%12L, tot_m%%12L+1L))
    } else {
      sc <- if(grepl("hours",t_unit,ignore.case=TRUE)) 1/24 else if(grepl("seconds",t_unit,ignore.case=TRUE)) 1/86400 else 1
      as.Date(t_val*sc, origin=trimws(sub("(?i)(days|hours|seconds) since","",t_unit)))
    }
  }, error=function(e) seq(as.Date("1988-01-15"), by="month", length.out=nt))
  if (length(dates_out)!=nt) dates_out <- dates_out[seq_len(nt)]
  r_out <- rast(nrows=nrow(template_r), ncols=ncol(template_r), nlyr=nt, crs=crs(template_r), extent=ext(template_r))
  time(r_out) <- dates_out
  # PATCH 2026-05-21 : remplacement de la boucle values(r_out[[t]])<- couche par
  # couche (anti-pattern terra : recopie le raster a chaque iteration -> O(n^2),
  # ~370 GB RAM observe). dim()<- reshape EN PLACE, values()<- remplit en 1 coup.
  dim(dat) <- c(length(dat) %/% nt, nt)
  values(r_out) <- dat
  rm(dat); gc(verbose=FALSE)
  r_out
}

agreger <- function(f_mensuel, nom_indice, saison_mois, type_agg, out_dir, base_code, template_r=NULL, nom_saison=NULL) {
  if (!file.exists(f_mensuel)) { err(sprintf("Absent : %s", basename(f_mensuel))); return(NULL) }
  nom_sais <- if (!is.null(nom_saison)) nom_saison else
              switch(paste(sort(saison_mois), collapse="-"),
                "3-4-5"="MAM","6-7-8"="JJA","9-10-11"="SON","1-2-12"="DJF","4-5-6-7-8-9"="veg",
                paste(saison_mois, collapse=""))
  label <- sprintf("ECE_%s_%s_%s", base_code, nom_indice, nom_sais)
  f_out <- file.path(out_dir, paste0(label,".nc"))
  if (index_valide(f_out)) { inf(sprintf("SKIP agregation : %s", basename(f_out))); return(f_out) }
  if (file.exists(f_out)) supprimer(f_out)   # present mais invalide (NA/tronque) -> on regenere
  spei_sc <- if (grepl("spei", tolower(nom_indice))) 2L else 1L
  r_men <- if (!is.null(template_r))
    tryCatch(lire_climpact_ncdf4(f_mensuel, template_r, spei_scale=spei_sc), error=function(e) NULL)
  else NULL
  if (is.null(r_men)||nlyr(r_men)==0) r_men <- tryCatch(rast(f_mensuel), error=function(e) NULL)
  if (is.null(r_men)||nlyr(r_men)==0) r_men <- tryCatch(rast(f_mensuel,subds=1), error=function(e) NULL)
  if (!is.null(r_men)&&nlyr(r_men)>0&&!is.null(template_r)) {
    v1 <- tryCatch(as.vector(values(r_men[[1]])), error=function(e) NA_real_)
    if (all(is.na(v1))) r_men <- lire_climpact_ncdf4(f_mensuel, template_r, spei_scale=spei_sc)
  }
  if (is.null(r_men)||nlyr(r_men)==0) { err(sprintf("Illisible : %s", basename(f_mensuel))); return(NULL) }
  dates <- time(r_men)
  if (sum(!is.na(dates)) < nlyr(r_men)*0.5 && !is.null(template_r)) {
    r2 <- lire_climpact_ncdf4(f_mensuel, template_r, spei_scale=spei_sc)
    if (!is.null(r2)) { r_men <- r2; dates <- time(r_men) }
  }
  annees <- sort(unique(year(dates))); annees <- annees[!is.na(annees)]
  if (length(annees)==0) { err("Dates illisibles"); return(NULL) }
  djf    <- identical(sort(as.integer(saison_mois)), c(1L,2L,12L))
  sepmay <- identical(sort(as.integer(saison_mois)), c(1L,2L,3L,4L,5L,9L,10L,11L,12L))
  r_out <- rast(nrows=nrow(r_men), ncols=ncol(r_men), nlyr=length(annees), crs=crs(r_men), extent=ext(r_men))
  for (an_i in seq_along(annees)) {
    an  <- annees[an_i]
    idx <- if (djf) which((year(dates)==an&month(dates)==12L)|(year(dates)==an+1L&month(dates)%in%c(1L,2L)))
           else if (sepmay) which((year(dates)==an-1L&month(dates)%in%9:12)|(year(dates)==an&month(dates)%in%1:5))  # hiver complet a cheval : SEP(an-1)..MAI(an)
           else     which(year(dates)==an & month(dates)%in%saison_mois)
    if (length(idx)==0) next
    r_an <- r_men[[idx]]
    r_out[[an_i]] <- switch(type_agg,
      "max"=app(r_an,max,na.rm=TRUE), "min"=app(r_an,min,na.rm=TRUE),
      "mean"=app(r_an,mean,na.rm=TRUE), "sum"=app(r_an,sum,na.rm=TRUE),
      "last"=r_an[[length(idx)]])
  }
  # PATCH 2026-05-21 : time() pose APRES la boucle de remplissage. Avant,
  # time(r_out) etait defini sur le raster vide puis r_out[[an_i]] <- app(...)
  # ecrasait la date de chaque couche (sortie de app() sans time) -> axe temps
  # "Inf" en sortie. Corrige a la source dans les 4 scripts ECE.
  time(r_out) <- as.Date(sprintf("%d-%02d-15", annees, max(saison_mois)))
  tryCatch({ writeCDF(r_out, f_out, varname=label, compression=COMPRESSION, overwrite=TRUE)
             ok(sprintf("Agregation OK : %s (%d ans)", basename(f_out), length(annees))) },
           error=function(e) err(conditionMessage(e)))
  rm(r_men,r_out); gc(); f_out
}

valider <- function(f_nc, nom_indice, base_code) {
  if (!file.exists(f_nc)) { cat(sprintf("    [ERR] Absent : %s\n", basename(f_nc))); return(FALSE) }
  r <- tryCatch(rast(f_nc), error=function(e) NULL)
  if (is.null(r)) { cat(sprintf("    [ERR] Illisible : %s\n", basename(f_nc))); return(FALSE) }
  v <- tryCatch(as.vector(values(r)), error=function(e) NULL)
  if (is.null(v)||all(is.na(v))) { cat(sprintf("    [ERR] 100%% NA : %s\n", basename(f_nc))); return(FALSE) }
  vv <- v[!is.na(v)]
  cat(sprintf("    [OK] %s : %d cou | NA: %.1f%% | [%.2f, %.2f]\n",
    basename(f_nc), nlyr(r), 100*mean(is.na(v)), min(vv), max(vv)))
  TRUE
}

trouver <- function(out_climpact, indice) {
  f <- list.files(out_climpact, pattern=sprintf("(?i)%s_MON_.*\\.nc$",indice), full.names=TRUE)
  if (length(f)>0) return(f[1])
  f <- list.files(out_climpact, pattern=sprintf("(?i)%s.*\\.nc$",indice), full.names=TRUE)
  if (length(f)>0) f[1] else NULL
}

calc_wg10p_prec_etp <- function(f_prec, f_etp, base_code, ref_debut, ref_fin,
                                 out_dir, saisons,
                                 n_threads = max(1L, parallel::detectCores() - 1L)) {
  # Parallelisme interne terra : accelere app(), sum(), comparaisons raster
  terraOptions(threads = n_threads)
  on.exit(terraOptions(threads = 1L), add = TRUE)
  f_outs <- file.path(out_dir, sprintf("ECE_%s_WG10P_%s.nc", base_code, names(saisons)))
  if (!(exists("FORCE_WG10P") && isTRUE(FORCE_WG10P)) &&
      all(vapply(f_outs, index_valide, logical(1)))) { inf("SKIP WG10P"); return(invisible(NULL)) }
  inf(sprintf("Calcul WG10P (bilan hydrique approche = prec - etp, %d threads)...", n_threads))
  r_prec <- tryCatch(rast(f_prec), error=function(e) NULL)
  r_etp  <- tryCatch(rast(f_etp),  error=function(e) NULL)
  if (is.null(r_prec)||is.null(r_etp)) { err("WG10P : fichiers prec/etp illisibles"); return(NULL) }
  dates_p <- time(r_prec); dates_e <- time(r_etp)
  if (!identical(as.character(dates_p), as.character(dates_e))) {
    common <- intersect(as.character(dates_p), as.character(dates_e))
    if (length(common)==0) { err("WG10P : aucune date commune prec/etp"); return(NULL) }
    r_prec <- r_prec[[match(common, as.character(dates_p))]]
    r_etp  <- r_etp [[match(common, as.character(dates_e))]]
    dates_p <- as.Date(common)
  }
  mv <- month(dates_p); av <- year(dates_p)
  q10 <- lapply(1:12, function(m) {
    idx <- which(av >= ref_debut & av <= ref_fin & mv == m)
    if (length(idx)==0) return(NULL)
    app(r_prec[[idx]] - r_etp[[idx]], function(x) quantile(x, 0.10, na.rm=TRUE))
  })
  ann <- sort(unique(av))

  # Boucle annuelle parallelisee : chaque worker traite 1 annee (1 thread terra interne)
  # Fallback automatique en sequentiel si le cluster PSOCK echoue (ex: terra temp files)
  n_par <- min(n_threads, length(ann), 16L)

  calc_une_annee_wg <- function(an) {
    ml <- list(); md <- as.Date(character(0))
    for (m in 1:12) {
      if (is.null(q10[[m]])) next
      idx_am <- which(av == an & mv == m)
      if (length(idx_am) == 0) next
      r_wg <- r_prec[[idx_am]] - r_etp[[idx_am]]
      # PATCH 2026-06-03 : NA-safe. Avant, NA en entree (ETP/prec/Q10 manquant) ->
      # sum(na.rm=TRUE)=0 -> pct=0 parasite (jusqu'a 50-69% des cellules en annee seche).
      # Denominateur = jours valides ; NA (et non 0) si aucun jour valide.
      lt   <- r_wg < q10[[m]]
      cnt  <- app(lt, function(x) sum(x, na.rm = TRUE))
      nval <- app(lt, function(x) sum(!is.na(x)))
      pct  <- ifel(nval > 0, cnt / nval * 100, NA)
      ml   <- base::c(ml, base::list(pct))
      md   <- base::c(md, as.Date(sprintf("%d-%02d-15", an, m)))
    }
    list(ml = ml, md = md)
  }

  # WG10P : calcul SEQUENTIEL par annee. Le parallele PSOCK a ete RETIRE (2026-06-10) :
  # exporter des SpatRaster terra (r_prec/r_etp) vers des workers PSOCK est impossible
  # (pointeur C++ invalide) -> il echouait SYSTEMATIQUEMENT puis rebasculait ici. Le
  # parallelisme utile reste INTERNE a terra (terraOptions(threads=n_threads), plus haut).
  men_results <- lapply(ann, calc_une_annee_wg)
  gc()

  men_list  <- unlist(lapply(men_results, `[[`, "ml"), recursive = FALSE)
  men_dates <- as.Date(unlist(lapply(lapply(men_results, `[[`, "md"), as.character)))
  if (length(men_list)==0) { err("WG10P : aucune donnee calculee"); return(NULL) }
  r_men <- rast(men_list); time(r_men) <- men_dates
  for (nom_s in names(saisons)) {
    f_out <- file.path(out_dir, sprintf("ECE_%s_WG10P_%s.nc", base_code, nom_s))
    if (!(exists("FORCE_WG10P") && isTRUE(FORCE_WG10P)) && index_valide(f_out)) { inf(sprintf("SKIP WG10P %s", nom_s)); next }
    mois_s <- saisons[[nom_s]]; r_list <- list(); dates_an <- list()
    for (an in ann) {
      idx_s <- which(year(men_dates)==an & month(men_dates) %in% mois_s)
      if (length(idx_s)==0) next
      r_list   <- c(r_list,   list(app(r_men[[idx_s]], mean, na.rm=TRUE)))
      dates_an <- c(dates_an, list(as.Date(sprintf("%d-%02d-15", an, max(mois_s)))))
    }
    if (length(r_list)==0) next
    r_out <- rast(r_list); time(r_out) <- do.call(c, dates_an)
    tryCatch({ writeCDF(r_out, f_out, varname=sprintf("ECE_%s_WG10P_%s", base_code, nom_s),
                        compression=COMPRESSION, overwrite=TRUE)
               ok(sprintf("WG10P %s OK : %d couches", nom_s, nlyr(r_out))) },
             error=function(e) err(conditionMessage(e)))
  }
  rm(r_men); gc(); invisible(NULL)
}

# ==============================================================================
# CHARGEMENT CLIMPACT
# ==============================================================================

cat("Chargement climpact...\n")
if (!dir.exists(CLIMPACT_DIR)) stop("Dossier introuvable : ", CLIMPACT_DIR)
f_ncdf_local <- file.path(CLIMPACT_DIR, "server", "pcic_packages", "climdex.pcic.ncdf", "R", "ncdf.R")
if (!file.exists(f_ncdf_local)) stop("ncdf.R local introuvable : ", f_ncdf_local)
modules_dir <- file.path(CLIMPACT_DIR, "modules")
if (dir.exists(modules_dir)) lapply(list.files(modules_dir, pattern="\\.R$", full.names=TRUE), source)
source(f_ncdf_local)
cat(sprintf("  climdex.pcic.ncdf v%s\n\n", packageVersion("climdex.pcic.ncdf")))

# ==============================================================================
# TRAITEMENT DIGI_SAF
# ==============================================================================

cat(sprintf("\n%s\n  ECE - %s  %d-%d\n%s\n", strrep("=",70), BASE$code, BASE$debut, BASE$fin, strrep("=",70)))
t0_base <- proc.time()[["elapsed"]]

out_climpact <- file.path(OUT_DIR,
  if (PERIODE_IDX >= 1L && PERIODE_IDX <= 5L)
    sprintf("climpact_raw_%s", PERIODES[[PERIODE_IDX]]$tag)
  else "climpact_raw")
if (!dir.exists(out_climpact)) dir.create(out_climpact, recursive=TRUE)

# --- 2026-06-03 : invalidation ciblee pour RECOMPUTE_PREC_ONLY ---
# Le SKIP par existence de fichier reutiliserait sinon (1) le prec fusionne
# perime (contenant encore le 1987 corrompu) et (2) les sorties SPEI/WG10P
# perimees. On force leur regeneration. tmax/tmin/ETP (temperature, non affectes)
# sont conserves et seront skippes normalement -> gros gain de temps.
if (RECOMPUTE_PREC_ONLY) {
  cat("\n--- RECOMPUTE_PREC_ONLY : invalidation ciblee (prec / SPEI / WG10P) ---\n")
  # SECURITE : les SORTIES (SPEI climpact + agregats finaux) sont ARCHIVEES (copie
  # horodatee, verifiee, jamais ecrasee) AVANT retrait -> aucune perte si le
  # recalcul casse. Si la copie echoue -> on NE retire PAS (SKIP, zero perte).
  # Le prec fusionne est un intermediaire journalier regenerable -> retire direct.
  .arch_dir <- file.path(OUT_DIR, "_archive_supprimes")
  .archive_then_remove <- function(f) {
    if (!file.exists(f)) return(invisible())
    dir.create(.arch_dir, showWarnings = FALSE, recursive = TRUE)
    fa <- file.path(.arch_dir, sprintf("%s.%s.bak", basename(f), format(Sys.time(), "%Y%m%d_%H%M%S")))
    if (file.copy(f, fa, overwrite = FALSE) && file.exists(fa) &&
        file.info(fa)$size == file.info(f)$size) {
      suppressWarnings(file.remove(f)); inf(sprintf("ARCHIVE+retire : %s", basename(f)))
    } else inf(sprintf("[!! CONSERVE] archive KO -> NON retire : %s", basename(f)))
  }
  .f_prec_merge <- file.path(MERGE_DIR,
    sprintf("%s_prec_%d-%d_TEST.nc", BASE$code, BASE$debut, BASE$fin))
  if (file.exists(.f_prec_merge)) {
    supprimer(.f_prec_merge)
    inf(sprintf("INVALIDATION prec fusionne (intermediaire regenerable) : %s", basename(.f_prec_merge)))
  }
  for (.s in list.files(out_climpact, pattern = "(?i)spei.*\\.nc$", full.names = TRUE))
    .archive_then_remove(.s)
  for (.a in file.path(OUT_DIR, c(sprintf("ECE_%s_SPEI6_MAR-AUG.nc", BASE$code),
                                  sprintf("ECE_%s_WG10P_MAR-AUG.nc", BASE$code))))
    .archive_then_remove(.a)
}

# --- Etape A : Fusion (3 variables en parallele) ---
# Avant : 3 appels sequentiels a fusionner() (~30 min/var sur 1km).
# Apres : 3 workers PSOCK lisent/cropent/ecrivent leurs annees en parallele.
# Fallback automatique en sequentiel si le cluster echoue.
cat("\n--- ETAPE A : Fusion (3 variables en parallele) ---\n")
log_d_init(MERGE_DIR)  # Active le progress log sur D: (bypass Tee-Object PowerShell)
log_d(sprintf("ETAPE A debut | base=%s | periode=%d-%d | merge_dir=%s",
              BASE$code, BASE$debut, BASE$fin, MERGE_DIR))
t0_fus <- proc.time()[["elapsed"]]

# Threads internes terra par worker : ne pas saturer le CPU global
.n_threads_par_worker <- max(1L, floor(N_CORES / 3L))

cl_fus <- tryCatch(parallel::makeCluster(3L, type = "PSOCK"),
                    error = function(e) NULL)

fus_results <- NULL
if (!is.null(cl_fus)) {
  fus_results <- tryCatch({
    parallel::clusterEvalQ(cl_fus, {
      suppressPackageStartupMessages({
        library(terra); library(ncdf4)
      })
    })
    parallel::clusterExport(cl_fus,
      c("fusionner", "supprimer", ".assemble_ncdf4", "corriger_crs", "ok", "err", "inf",
        "log_d", "log_d_init", ".PROGRESS_LOG",
        "BASE", "MERGE_DIR", "CROP_EXT",
        ".n_threads_par_worker"),
      envir = environment())
    parallel::clusterEvalQ(cl_fus, terraOptions(threads = .n_threads_par_worker))
    parallel::clusterEvalQ(cl_fus, {
      .PROGRESS_LOG <<- file.path(MERGE_DIR, sprintf("_progress_w%d.log", Sys.getpid()))
      log_d(sprintf("Worker %d demarre, log: %s", Sys.getpid(), .PROGRESS_LOG))
    })

    parallel::parLapply(cl_fus, c("tmax", "tmin", "prec"), function(v) {
      cat(sprintf("[%s] DEBUT fusion\n", v))
      log_d(sprintf("[%s] DEBUT fusion (worker)", v))
      res <- fusionner(BASE$dir, BASE$code, v, BASE$debut, BASE$fin, MERGE_DIR, CROP_EXT)
      log_d(sprintf("[%s] FIN fusion (worker)", v))
      cat(sprintf("[%s] FIN fusion\n", v))
      res
    })
  }, error = function(e) {
    cat(sprintf("  [WARN] fusion parallele echec : %s\n", conditionMessage(e)))
    NULL
  })
  try(parallel::stopCluster(cl_fus), silent = TRUE)
}

# Fallback sequentiel si parallele a echoue
if (is.null(fus_results)) {
  cat("  -> Fallback en sequentiel (3 appels successifs)\n")
  f_tmax <- fusionner(BASE$dir, BASE$code, "tmax", BASE$debut, BASE$fin, MERGE_DIR, CROP_EXT)
  f_tmin <- fusionner(BASE$dir, BASE$code, "tmin", BASE$debut, BASE$fin, MERGE_DIR, CROP_EXT)
  f_prec <- fusionner(BASE$dir, BASE$code, "prec", BASE$debut, BASE$fin, MERGE_DIR, CROP_EXT)
} else {
  f_tmax <- fus_results[[1]]
  f_tmin <- fus_results[[2]]
  f_prec <- fus_results[[3]]
}

cat(sprintf("\n  [TIMING] Fusion 3 vars : %s\n",
            fmt_dur(proc.time()[["elapsed"]] - t0_fus)))

if (is.null(f_tmax)||is.null(f_tmin)||is.null(f_prec)) stop("Fichiers sources manquants - arret.")
f_etp  <- calc_etp_turc(
  f_tmax, f_tmin,
  file.path(MERGE_DIR, sprintf("%s_etp_turc_%d-%d_TEST.nc", BASE$code, BASE$debut, BASE$fin))
)

# --- Etape B : Climpact ---
if (!exists("ONLY_WG10P_HWN_CWN")) ONLY_WG10P_HWN_CWN <- FALSE
cat("\n--- ETAPE B : Climpact ---\n")
# --- Calcul adaptatif RAM/CPU (CALCULUS) ---
# Detecter la RAM disponible (Linux /proc/meminfo ; Windows wmic)
.ram_free_gb <- tryCatch({
  if (.Platform$OS.type == "windows") {
    .raw <- system("wmic OS get FreePhysicalMemory /format:list", intern=TRUE, ignore.stderr=TRUE)
    as.numeric(sub("^FreePhysicalMemory=", "", .raw[grepl("FreePhysicalMemory=", .raw)])) / 1024^2
  } else {
    as.numeric(system("awk '/MemAvailable/ {print $2}' /proc/meminfo", intern=TRUE)) / 1024^2
  }
}, error=function(e) 32)

# Cores disponibles : diviser par N_PARALLEL_ECE quand plusieurs jobs tournent en simultane
.n_cores_totaux <- parallel::detectCores()
.n_cores_dispo  <- if (N_PARALLEL_ECE > 1L) {
  max(2L, floor((.n_cores_totaux - 2L) / N_PARALLEL_ECE))
} else {
  max(2L, .n_cores_totaux - 2L)
}
# PATCH 2026-05-06 : applique le plafond CPU global (cf MAX_CPU_FRAC en tete)
.n_cores_dispo <- min(.n_cores_dispo, .n_cores_max)

# Dimensions reelles de la grille (apres fusion + crop France)
nlat_grid       <- tryCatch(nrow(rast(f_tmax)), error=function(e) 100L)
.ncol_grid      <- tryCatch(ncol(rast(f_tmax)), error=function(e) 200L)
.n_jours_approx <- (FULL_FIN - FULL_DEBUT + 1L) * 365L
.n_vars         <- 3L

# RAM par ligne de latitude : ncol x n_jours x 3vars x 8 bytes x facteur_4
# (facteur_4 : tmax + tmin + prec en RAM + matrices internes climpact)
.ram_par_ligne_mb <- .ncol_grid * .n_jours_approx * .n_vars * 8 * 4 / 1e6

# Workers optimaux : minimum des 3 contraintes (RAM, CPU, lignes de grille)
.ram_usable_mb  <- max(4096, .ram_free_gb * MAX_RAM_FRAC * 1024)  # PATCH 2026-05-21 : MAX_RAM_FRAC (avant : libre - 8 GB)
.n_workers_ram  <- max(1L, floor(.ram_usable_mb / max(1, .ram_par_ligne_mb)))
.bottleneck <- if (.n_workers_ram <= .n_cores_dispo && .n_workers_ram <= nlat_grid) "RAM" else if (nlat_grid <= .n_cores_dispo) "GRILLE" else "CPU"
n_workers <- as.integer(min(.n_cores_dispo, nlat_grid, .n_workers_ram))
if (ONLY_WG10P_HWN_CWN) cat("\n--- [ONLY_WG10P_HWN_CWN] SKIP climpact (ETAPE B) ; agregation + validation TXx/TNn/SPEI sautees (sorties supposees deja presentes) ---\n")
if (!ONLY_WG10P_HWN_CWN) {
# --- Climpact bride a <= 40% du CPU ET de la RAM de la machine (partagee).
#     HWN/CWN/WG10P gardent n_workers ; SEUL l'appel climpact prend n_workers_climpact. ---
.MAX_CLIMPACT_FRAC <- 0.40
.ram_total_gb <- tryCatch({
  if (.Platform$OS.type == "windows") {
    .rt <- system("wmic OS get TotalVisibleMemorySize /format:list", intern = TRUE, ignore.stderr = TRUE)
    as.numeric(sub("^TotalVisibleMemorySize=", "", .rt[grepl("TotalVisibleMemorySize=", .rt)])) / 1024^2
  } else as.numeric(system("awk '/MemTotal/ {print $2}' /proc/meminfo", intern = TRUE)) / 1024^2
}, error = function(e) .ram_free_gb)
n_workers_climpact <- as.integer(max(1L, min(
  n_workers,
  floor(.MAX_CLIMPACT_FRAC * .n_cores_totaux),
  floor(.MAX_CLIMPACT_FRAC * .ram_total_gb * 1024 / max(1, .ram_par_ligne_mb)))))
cat(sprintf("  Climpact   : %d workers (bride <= %.0f%% CPU/RAM ; machine %d coeurs / %.0f GB)\n",
            n_workers_climpact, .MAX_CLIMPACT_FRAC * 100, .n_cores_totaux, .ram_total_gb))

# Taille des tranches adaptee au nombre de workers reel
## max_vals_millions : DOIT garantir rows.per.slice >= 1 dans Climpact.
## rows.per.slice = floor(max_vals_millions * 1e6 / (ncol * timesteps))
## donc max_vals_millions >= ncol*timesteps/1e6. On prend 5x cette valeur, min 10.
.min_safe_mvm  <- (.ncol_grid * .n_jours_approx) / 1e6
max_vals_millions <- max(10, .min_safe_mvm * 5)

cat(sprintf("  RAM libre  : %.1f GB | Cores : %d / %d (periode %d/5)\n",
            .ram_free_gb, .n_cores_dispo, .n_cores_totaux, max(1L, PERIODE_IDX)))
cat(sprintf("  Workers    : %d (limite : %s) | RAM/worker : %.0f MB\n",
            n_workers, .bottleneck, .ram_par_ligne_mb))
cat(sprintf("  max.vals.millions : %.2f  (~%d tranches)\n",
            max_vals_millions, n_workers))

periode_tag  <- sprintf("%d-%d", BASE$debut, BASE$fin)
fics_obs <- list.files(out_climpact, pattern="\\.nc$", full.names=TRUE)
fics_hors_periode <- fics_obs[!grepl(periode_tag, fics_obs)]
fics_periode <- fics_obs[grepl(periode_tag, fics_obs)]
fics_corrompus <- fics_periode[vapply(fics_periode, function(f) {
  inherits(tryCatch(rast(f), error = function(e) structure(list(), class="error")), "error")
}, logical(1))]
fics_a_supprimer <- unique(fics_corrompus)   # CORRIGE : ne supprime QUE les corrompus (les "hors periode" sont en fait valides, juste nommes avec la periode de reference)
if (length(fics_a_supprimer) > 0) {
  cat(sprintf("  Nettoyage : %d fichier(s) obsoletes/corrompus supprimes\n", length(fics_a_supprimer)))
  gc(); Sys.sleep(0.5)
  suppressWarnings(file.remove(fics_a_supprimer))
}

indices_presents <- sapply(INDICES_CIBLE, function(idx) {
  # CORRIGE : climpact nomme ses mensuels avec la periode de REFERENCE (pas la
  # periode de donnees) -> on ne met PLUS le tag periode dans le pattern. Valide =
  # lisible + couvre BASE$debut..BASE$fin + au moins une couche a de la donnee.
  # On NE supprime RIEN ici (l'ancien file.remove sur 1ere-couche-NA effacait a tort
  # des mensuels valides dont la 1ere copie est NA, ex. DIGI_SAF).
  fics <- list.files(out_climpact, pattern = sprintf("%s[0-9]*_(MON|ANN)_.*\\.nc$", idx),
                     full.names = TRUE, ignore.case = TRUE)
  if (length(fics) == 0) return(FALSE)
  tryCatch({
    r_chk <- rast(fics[1]); if (nlyr(r_chk) == 0) return(FALSE)
    an     <- as.integer(format(time(r_chk), "%Y"))
    couvre <- !all(is.na(an)) && min(an, na.rm = TRUE) <= BASE$debut && max(an, na.rm = TRUE) >= BASE$fin
    js     <- unique(round(seq(1, nlyr(r_chk), length.out = min(nlyr(r_chk), 12L))))
    a_data <- any(vapply(js, function(j) nrow(terra::spatSample(r_chk[[j]], 300, "regular", na.rm = TRUE)) > 0, logical(1)))
    isTRUE(couvre && a_data)
  }, error = function(e) FALSE)
})

# FORCE_CLIMPACT (test sandbox) : ignore un cache climpact_raw eventuel (potentiellement
# d'une autre emprise/crop) et force le recalcul -> evite l'agregation 100% NA sur un raw
# mal aligne avec le template courant. Non defini ou FALSE en prod (aucun effet).
if (exists("FORCE_CLIMPACT") && isTRUE(FORCE_CLIMPACT) && any(indices_presents)) {
  inf("[FORCE_CLIMPACT] recalcul climpact force (cache climpact_raw ignore)")
  indices_presents[] <- FALSE
}

if (!all(indices_presents)) {
  infiles <- Filter(function(x) !is.null(x)&&file.exists(x), list(f_tmax,f_tmin,f_prec))

  tmpl <- sprintf("var_daily_%s_historical_NA_%d-%d.nc", tolower(BASE$code), BASE$debut, BASE$fin)
  tryCatch(
    create.indices.from.files(
      input.files=unlist(infiles), out.dir=out_climpact,
      output.filename.template=tmpl, author.data=AUTHOR_DATA,
      variable.name.map=c(tmax="tmax",tmin="tmin",prec="prec"),
      base.range=c(BASE_START,BASE_END), parallel=n_workers_climpact, axis.to.split.on="Y",
      climdex.time.resolution="monthly",
      climdex.vars.subset=INDICES_CIBLE, thresholds.files=NULL, fclimdex.compatible=FALSE,
      root.dir=CLIMPACT_DIR, cluster.type="SOCK", ehfdef="NF13", max.vals.millions=max_vals_millions,
      wsdin_n=5,csdin_n=5,hddheatn_n=18,cddcoldn_n=18,gddgrown_n=10,rxnday_n=7,
      rnnmm_n=30,ntxntn_n=3,ntxbntnb_n=3,project.lat2d.coords=FALSE),
    error=function(e) err(sprintf("ERREUR climpact : %s", conditionMessage(e))))
} else {
  inf(sprintf("SKIP climpact (indices presents : %s)", paste(INDICES_CIBLE,collapse=",")))
}

# --- Etape C : Agregation multi-saisonniere (4 indices, 1 valeur/an) ---
}  # fin du bloc saute par ONLY_WG10P_HWN_CWN (climpact ETAPE B)
cat("\n--- ETAPE C : Agregation multi-saisonniere (4 indices) ---\n")
# TXx   : MAR-NOV (max sur 9 mois, hors hiver)
# TNn   : SEP-MAY (min ; hiver COMPLET a cheval : SEP(Y-1)..MAI(Y), comme CWN)
# SPEI6 : MAR-AUG (mean sur 6 mois, printemps + ete)
# WG10P : MAR-AUG (% jours WG < Q10 sur 6 mois, printemps + ete)
tmpl_r <- tryCatch(rast(f_tmax)[[1]], error=function(e) NULL)

f_txx <- trouver(out_climpact,"txx")
if (!is.null(f_txx)) {
  f_out <- agreger(f_txx, "TXx", 3:11, "max", OUT_DIR, BASE$code, tmpl_r, nom_saison="MAR-NOV")
  if (!ONLY_WG10P_HWN_CWN && !is.null(f_out)) valider(f_out,"txx",BASE$code)
}

f_tnn <- trouver(out_climpact,"tnn")
if (!is.null(f_tnn)) {
  f_out <- agreger(f_tnn, "TNn", c(1:5, 9:12), "min", OUT_DIR, BASE$code, tmpl_r, nom_saison="SEP-MAY")
  if (!ONLY_WG10P_HWN_CWN && !is.null(f_out)) valider(f_out,"tnn",BASE$code)
}

f_spei <- trouver(out_climpact,"spei6")
if (is.null(f_spei)) f_spei <- trouver(out_climpact,"spei")
if (!is.null(f_spei)) {
  f_out <- agreger(f_spei, "SPEI6", 3:8, "mean", OUT_DIR, BASE$code, tmpl_r, nom_saison="MAR-AUG")
  if (!ONLY_WG10P_HWN_CWN && !is.null(f_out)) valider(f_out,"spei6",BASE$code)
}

# WG10P : bilan hydrique approche (prec - etp), % jours sous Q10 de reference
# Calcule sur la periode printemps + ete (Mar-Aug)
# ==============================================================================
# HWN / CWN  -  frequence des vagues de chaleur / froid  (Carletti et al. 2026)
# HWN (chaleur) : nb d'evenements de >= 3 jours consecutifs avec Tmax > q90,
#                 fenetre saisonniere MAI-SEP   (Perkins-Kirkpatrick & Alexander 2013)
# CWN (froid)   : nb d'evenements de >= 3 jours consecutifs avec Tmin < q10,
#                 fenetre saisonniere SEP-MAY (hiver a cheval, comme TNn)   (Nairn & Fawcett 2013)
# Seuil : percentile jour-calendaire (DOY) sur fenetre glissante +/- 7 j,
#         calcule PAR PIXEL sur la periode de reference 1979-1989 (BASE_START/END).
# Sortie : ECE_<base>_<HWN|CWN>_<saison>.nc, 1 couche par annee = nb d'evenements.
# ==============================================================================
calc_hwn_cwn <- function(f_daily, type, base_code, ref_debut, ref_fin, out_dir,
                         demi_fenetre = 7L, min_duree = 3L,
                         n_threads = max(1L, parallel::detectCores() - 1L),
                         compression = 5L,
                         ram_seuils_gb = 8, layers_par_lot = 365L) {
  if (!type %in% c("HWN", "CWN")) { err("calc_hwn_cwn : type doit etre HWN ou CWN"); return(NULL) }
  cfg <- if (type == "HWN") list(prob = 0.90, sens = "sup", saison = 5:9,         nom = "MAY-SEP", wrap = FALSE)
         else               list(prob = 0.10, sens = "inf", saison = c(9:12, 1:5), nom = "SEP-MAY", wrap = TRUE)
  label <- sprintf("ECE_%s_%s_%s", base_code, type, cfg$nom)
  f_out <- file.path(out_dir, paste0(label, ".nc"))
  if (!(exists("FORCE_HWN_CWN") && isTRUE(FORCE_HWN_CWN)) && index_valide(f_out)) {
    inf(sprintf("SKIP %s : %s", type, basename(f_out))); return(f_out)
  }
  if (file.exists(f_out)) supprimer(f_out)   # present mais invalide / force -> on regenere
  if (!file.exists(f_daily)) { err(sprintf("%s : daily absent : %s", type, basename(f_daily))); return(NULL) }
  has_ms <- requireNamespace("matrixStats", quietly = TRUE)
  terraOptions(threads = n_threads); on.exit(terraOptions(threads = 1L), add = TRUE)
  inf(sprintf("Calcul %s (STREAMING, %s q%d, ref %d-%d)...", type,
              if (cfg$sens == "sup") "Tmax >" else "Tmin <", round(cfg$prob*100), ref_debut, ref_fin))
  r <- tryCatch(rast(f_daily), error = function(e) NULL)
  if (is.null(r) || nlyr(r) == 0) { err(sprintf("%s : daily illisible", type)); return(NULL) }
  dates <- time(r)
  if (sum(!is.na(dates)) < nlyr(r) * 0.5) { err(sprintf("%s : dates illisibles", type)); return(NULL) }
  yr  <- as.integer(format(dates, "%Y")); mo <- as.integer(format(dates, "%m")); doy <- as.integer(format(dates, "%j"))
  # Annee de SAISON : pour une saison a cheval (CWN SEP-MAI), les mois d automne
  # (9-12) sont rattaches a l annee de printemps suivante -> saison Y = SEP(Y-1)..MAI(Y),
  # hiver complet preserve. HWN (saison estivale contigue) : sy = yr.
  sy <- if (isTRUE(cfg$wrap)) ifelse(mo %in% 9:12, yr + 1L, yr) else yr
  idx_ref <- which(yr >= ref_debut & yr <= ref_fin)
  if (length(idx_ref) == 0) { err(sprintf("%s : aucune annee de ref %d-%d", type, ref_debut, ref_fin)); return(NULL) }
  doy_ref     <- doy[idx_ref]
  doys_saison <- sort(unique(doy[mo %in% cfg$saison])); ndoy <- length(doys_saison)
  doy2col <- integer(366L); doy2col[doys_saison] <- seq_len(ndoy)
  annees  <- sort(unique(yr)); annees <- annees[!is.na(annees)]
  ncel <- ncell(r); nc <- ncol(r); nr <- nrow(r)
  seuils_mat <- matrix(NA_real_, ncel, ndoy)

  maj_avancement(base_code, paste0("seuils_", type), 0L, 1L, "calcul des seuils (percentiles)")
  # ---- 1. SEUILS : cache, sinon calcul par blocs de lignes SUR LA PERIODE DE REF ----
  seuils_cache <- file.path(dirname(f_daily),
                            sprintf("_seuils_%s_%s_ref%d-%d_w%d.nc", base_code, type, ref_debut, ref_fin, demi_fenetre))
  r_cache <- if (file.exists(seuils_cache)) tryCatch(rast(seuils_cache), error = function(e) NULL) else NULL
  cache_ok <- !is.null(r_cache) && nlyr(r_cache) == ndoy &&
              isTRUE(file.info(seuils_cache)$mtime >= file.info(f_daily)$mtime) &&
              isTRUE(tryCatch(terra::compareGeom(r_cache, r, stopOnError = FALSE), error = function(e) FALSE)) &&
              !all(is.na(values(r_cache[[1]])))
  if (cache_ok) {
    inf(sprintf("Seuils %s : cache reutilise -> %s", type, basename(seuils_cache)))
    seuils_mat[] <- values(r_cache)
  } else {
    sel_list <- lapply(doys_saison, function(d) { dist <- pmin(abs(doy_ref - d), 365L - abs(doy_ref - d)); idx_ref[dist <= demi_fenetre] })
    computed <- vapply(sel_list, length, 1L) > 0L; ok_idx <- which(computed)
    if (!any(computed)) { err(sprintf("%s : aucun seuil calculable", type)); return(NULL) }
    pos_ref <- integer(nlyr(r)); pos_ref[idx_ref] <- seq_along(idx_ref)   # global -> position dans r_ref
    sel_ref <- lapply(sel_list, function(s) pos_ref[s])
    # Phase seuils PARALLELISEE : on decoupe la grille en blocs de lignes ; chaque
    # worker lit SES lignes de la periode de ref (pas tout le cube) et calcule ses
    # rowQuantiles (le goulot CPU). Les blocs PARTITIONNENT la grille -> la RAM totale
    # reste ~ la taille de la ref (comme en 1 bloc), mais le calcul est //. Cache ensuite.
    n_par_s <- if (exists("N_PAR_HWN")) max(1L, as.integer(N_PAR_HWN)) else max(1L, min(n_threads, floor(parallel::detectCores() * 0.5)))  # PATCH 2026-06-09 : seuils HWN/CWN brides a <=50% des coeurs par defaut (machine PARTAGEE) + respecte MAX_CPU_FRAC via n_threads ; surchargeable via N_PAR_HWN
    n_par_s <- min(n_par_s, nr)
    # N_WAVES_HWN > 1 : PLUS de blocs que de workers -> traites en VAGUES (clusterApply)
    # -> pic RAM ~ total / N_WAVES_HWN (la ref n'est pas toute en memoire a la fois).
    .nw  <- if (exists("N_WAVES_HWN")) max(1L, as.integer(N_WAVES_HWN)) else 1L
    rb   <- as.integer(ceiling(nr / (n_par_s * .nw)))
    rngs <- lapply(seq(1L, nr, by = rb), function(r0) c(r0 = r0, nrb = min(rb, nr - r0 + 1L)))
    inf(sprintf("Seuils %s : %d couches de ref, %d bloc(s) // (%d workers)", type, length(idx_ref), length(rngs), min(n_par_s, length(rngs))))
    .seuils_bloc <- function(rng, f_daily, idx_ref, sel_ref, ok_idx, prob, ndoy, has_ms) {
      suppressPackageStartupMessages(library(terra)); terra::terraOptions(threads = 1L)
      rr <- terra::rast(f_daily)[[idx_ref]]
      terra::readStart(rr); on.exit(try(terra::readStop(rr), silent = TRUE), add = TRUE)
      M <- terra::readValues(rr, row = rng[["r0"]], nrows = rng[["nrb"]], mat = TRUE)
      np <- nrow(M); S <- matrix(NA_real_, np, ndoy)
      for (j in ok_idx) {
        sub <- M[, sel_ref[[j]], drop = FALSE]
        S[, j] <- if (has_ms) matrixStats::rowQuantiles(sub, probs = prob, na.rm = TRUE)
                  else apply(sub, 1L, quantile, probs = prob, na.rm = TRUE)
      }
      S
    }
    parts <- NULL
    if (n_par_s > 1L && length(rngs) > 1L) {
      cl <- tryCatch(parallel::makeCluster(min(n_par_s, length(rngs)), type = "PSOCK"), error = function(e) NULL)
      if (!is.null(cl)) {
        parts <- tryCatch(parallel::clusterApply(cl, rngs, .seuils_bloc, f_daily, idx_ref, sel_ref, ok_idx, cfg$prob, ndoy, has_ms),
                          error = function(e) { inf(sprintf("Seuils %s : // echoue (%s) -> sequentiel", type, conditionMessage(e))); NULL })
        try(parallel::stopCluster(cl), silent = TRUE)
      }
    }
    if (is.null(parts)) parts <- lapply(rngs, function(rng) .seuils_bloc(rng, f_daily, idx_ref, sel_ref, ok_idx, cfg$prob, ndoy, has_ms))
    for (i in seq_along(rngs)) {
      rng <- rngs[[i]]; cells <- ((rng[["r0"]] - 1L) * nc + 1L):((rng[["r0"]] - 1L + rng[["nrb"]]) * nc)
      seuils_mat[cells, ] <- parts[[i]]
    }
    for (j in which(!computed)) seuils_mat[, j] <- seuils_mat[, ok_idx[which.min(abs(ok_idx - j))]]
    tryCatch({ rs <- rast(r[[1]], nlyrs = ndoy); values(rs) <- seuils_mat
               writeCDF(rs, seuils_cache, varname = sprintf("seuil_%s", type), overwrite = TRUE)
               inf(sprintf("Seuils %s : cache ecrit", type)) },
             error = function(e) inf(sprintf("Seuils %s : cache non ecrit (%s)", type, conditionMessage(e))))
  }

  # ---- 2. COMPTAGE EN STREAMING : couche par couche, ordre chronologique --------
  ord    <- order(dates)                       # ordre chronologique (file order si deja trie)
  count  <- matrix(0L, ncel, length(annees))   # evenements par pixel x annee
  hasd   <- matrix(FALSE, ncel, length(annees)) # au moins un jour valide ?
  run    <- integer(ncel); prev_day <- NA_integer_
  an2col <- integer(max(annees) + 1L); an2col[annees] <- seq_along(annees)
  inf(sprintf("%s : comptage streaming (%d couches, lots de %d, RAM ~constante)", type, length(ord), layers_par_lot))
  # NB : on lit via values(r[[...]]) (pas readValues+readStart) -> ne PAS appeler
  # readStart(r) ici (le melanger avec values() provoque un segfault terra).
  lots <- split(ord, ceiling(seq_along(ord) / layers_par_lot))
  maj_avancement(base_code, paste0("comptage_", type), 0L, length(lots), "comptage des vagues")
  pb <- utils::txtProgressBar(min = 0, max = length(lots), style = 3)   # barre d'avancement
  for (li in seq_along(lots)) {
    lot <- lots[[li]]                           # indices CONTIGUS (ord chrono = ordre fichier si trie)
    if (any(mo[lot] %in% cfg$saison)) {
      # LECTURE CONTIGUE de tout le lot d'un coup : efficace QUEL QUE SOIT le chunking
      # du NetCDF (lire des couches eparpillees provoque une sur-lecture massive si le
      # fichier n'est pas chunke par couche). On traite ensuite les jours de saison.
      Mlot <- values(r[[lot]]); if (is.null(dim(Mlot))) Mlot <- matrix(Mlot, ncol = length(lot))
      for (cc in seq_along(lot)) {
        k <- lot[cc]; if (!(mo[k] %in% cfg$saison)) next   # jour hors saison -> ignore
        y <- sy[k]; yc <- an2col[y]
        if (yc == 0L) next   # saison hors plage de sortie (ex. automne 2024 -> saison 2025 non produite)
        di <- as.integer(dates[k])
        # Reset si jours de saison NON consecutifs (trou estival entre saisons, ou
        # jour manquant) : une vague exige des jours calendaires consecutifs. Un hiver
        # a cheval (Dec->Jan, jours consecutifs, meme sy) reste intact.
        if (is.na(prev_day) || di - prev_day != 1L) run[] <- 0L
        prev_day <- di
        val <- Mlot[, cc]; thr <- seuils_mat[, doy2col[doy[k]]]
        valid <- !is.na(val) & !is.na(thr)
        ex <- valid & (if (cfg$sens == "sup") val > thr else val < thr)
        run <- ifelse(ex, run + 1L, 0L)
        hit <- run == min_duree
        if (any(hit)) count[hit, yc] <- count[hit, yc] + 1L
        if (any(valid)) hasd[valid, yc] <- TRUE
      }
      rm(Mlot); gc(FALSE)
    }
    utils::setTxtProgressBar(pb, li)
    if (li %% max(1L, length(lots) %/% 100L) == 0L || li == length(lots))
      maj_avancement(base_code, paste0("comptage_", type), li, length(lots))
  }
  close(pb)
  out <- count; storage.mode(out) <- "double"; out[!hasd] <- NA_real_

  r_out <- rast(r[[1]], nlyrs = length(annees)); values(r_out) <- out
  time(r_out)  <- as.Date(sprintf("%d-%02d-15", annees, max(cfg$saison)))
  names(r_out) <- sprintf("%s_%d", type, annees)
  tryCatch({ writeCDF(r_out, f_out, varname = label, compression = compression, overwrite = TRUE)
             ok(sprintf("%s OK : %s (%d ans)", type, basename(f_out), length(annees))) },
           error = function(e) err(conditionMessage(e)))
  rm(r, r_out, seuils_mat, count, hasd); gc(); f_out
}

# --- ETAPE C bis : HWN / CWN (frequence des vagues chaleur/froid, Carletti 2026) ---
# SKIP_HWN_CWN : passe HWN/CWN, ne calcule QUE WG10P (priorite WG10P avant HWN/CWN).
# On annule f_tmax/f_tmin -> les blocs HWN/CWN (gardes par if(!is.null(...))) sont sautes ;
# WG10P utilise f_prec/f_etp, intacts.
if (exists("SKIP_HWN_CWN") && isTRUE(SKIP_HWN_CWN)) { f_tmax <- NULL; f_tmin <- NULL; inf("[SKIP_HWN_CWN] HWN/CWN sautes -> WG10P uniquement") }
cat("\n--- ETAPE C bis : HWN / CWN (frequence vagues chaleur/froid, Carletti 2026) ---\n")
if (!is.null(f_tmax)) {
  f_out <- calc_hwn_cwn(f_tmax, "HWN", BASE$code, BASE_START, BASE_END, OUT_DIR, n_threads = n_workers)
  if (!is.null(f_out)) valider(f_out, "HWN", BASE$code)
}
if (!is.null(f_tmin)) {
  f_out <- calc_hwn_cwn(f_tmin, "CWN", BASE$code, BASE_START, BASE_END, OUT_DIR, n_threads = n_workers)
  if (!is.null(f_out)) valider(f_out, "CWN", BASE$code)
}

saisons_wg <- list("MAR-AUG" = 3:8)
if (!is.null(f_etp) && !is.null(f_prec))
  calc_wg10p_prec_etp(f_prec, f_etp, BASE$code, BASE_START, BASE_END, OUT_DIR, saisons_wg,
                     n_threads = n_workers)

dur <- proc.time()[["elapsed"]] - t0_base
cat(sprintf("\n%s\n  DIGI_SAF termine en %s\n  Sorties : %s\n%s\n",
    strrep("=",70), fmt_dur(dur), OUT_DIR, strrep("=",70)))
