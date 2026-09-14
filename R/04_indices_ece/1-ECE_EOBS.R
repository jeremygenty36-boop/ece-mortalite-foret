# source("R/04_indices_ece/1-ECE_EOBS.R")   # depuis la racine du depot
# ==============================================================================
# CALCUL INDICES ECE - BASE 1 : E-OBS 11km
# CRS : WGS84 | Resolution : ~11km | Periode : 1979-1989 (test)
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

# OMP threads : adaptatif (CALCULUS - 5 periodes en simultane -> 1/5 des cores)
Sys.setenv("OMP_NUM_THREADS" = as.character(max(1L, floor((parallel::detectCores() - 2L) / 5L))))

# ==============================================================================
# PARAMETRES
# ==============================================================================

ROOT_LOC     <- LOCAL_ROOT
ECE_ROOT     <- if (dir.exists(file.path(LOCAL_ROOT, "ECE_data"))) file.path(LOCAL_ROOT, "ECE_data") else file.path(PROJET, "ECE_data")
MERGE_DIR    <- file.path(ROOT_LOC, "ECE_merge", "EOBS")      # fusion locale (I/O rapide)
OUT_DIR      <- file.path(PROJET, "5-Resultats", "3-ECE", "1-ECE_1979-2024", "1-EOBS_11km")
CLIMPACT_DIR <- CLIMPACT_RACINE

BASE <- list(
  code       = "EOBS",
  dir        = file.path(ECE_ROOT, "1-EOBS_11km"),
  debut      = 1979L,
  fin        = 1989L,
  etp_native = FALSE,
  wg_native  = FALSE,
  crs_native = NULL   # WGS84 natif
)

BASE_START   <- 1979L
BASE_END     <- 1989L
FULL_DEBUT   <- 1979L
FULL_FIN     <- 2024L

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
if (length(.args_cli) >= 1 && grepl("^[1-5]$", .args_cli[1]))
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
# Exemple : Rscript 1-ECE_EOBS.R 3 2  → periode 3, seulement 2 periodes en meme temps
if (!exists("N_PARALLEL_ECE")) N_PARALLEL_ECE <- tryCatch({
  val <- if (length(.args_cli) >= 2L) as.integer(.args_cli[2]) else 5L
  if (is.na(val) || val < 1L || val > 5L) 5L else val
}, error=function(e) 5L)
if (PERIODE_IDX >= 1L)
  cat(sprintf("[MACHINE]  %d periode(s) en simultane sur cette machine\n", N_PARALLEL_ECE))

# --- Surcharge SANDBOX (test bout-en-bout) : entree/sortie isolees + periode ---
# NC d'entree deja croppe par la conversion -> pas de crop ici. Bloc generique
# (sous-dossier base derive de OUT_DIR/MERGE_DIR). Reference 1979-1989 conservee
# si la periode la couvre (test comparable au prod), sinon degeneree (validation code).
if (exists("SANDBOX_OUT")) {
  .sub      <- basename(OUT_DIR)
  .mrg      <- basename(MERGE_DIR)
  ECE_ROOT  <- file.path(SANDBOX_OUT, "ECE_data")
  MERGE_DIR <- file.path(SANDBOX_OUT, "ECE_merge", .mrg)
  OUT_DIR   <- file.path(SANDBOX_OUT, "results_ECE", .sub)
  BASE$dir  <- file.path(SANDBOX_OUT, "ECE_data", .sub)
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
}
if (exists("SANDBOX_ANNEES")) {
  FULL_DEBUT <- min(SANDBOX_ANNEES); FULL_FIN <- max(SANDBOX_ANNEES)
  BASE$debut <- FULL_DEBUT; BASE$fin <- FULL_FIN
  if (!(FULL_DEBUT <= 1979L && FULL_FIN >= 1989L)) { BASE_START <- FULL_DEBUT; BASE_END <- FULL_FIN }
}

INDICES_CIBLE <- c("txx", "tnn", "spei")
SAISONS      <- list(MAM=3:5, JJA=6:8, SON=9:11, DJF=c(12L,1L,2L), VEG=4:9)
COMPRESSION  <- 5L
CROP_EXT     <- NULL  # sera defini depuis le masque France ci-dessous (bbox + buffer)
N_CORES      <- if (PERIODE_IDX >= 1L) max(2L, floor((parallel::detectCores() - 2L) / N_PARALLEL_ECE)) else max(2L, parallel::detectCores() - 2L)
AUTHOR_DATA  <- list(institution="UMR Silva / AgroParisTech", institution_id="SILVA")
VALID_RANGES <- list(
  txx  = list(min=-10,  max=55,  unit="C",  desc="Max temperature max"),
  tnn  = list(min=-40,  max=20,  unit="C",  desc="Min temperature min"),
  spei6= list(min=-4,   max=4,   unit="sd", desc="SPEI-6"),
  wg10p= list(min=0,    max=100, unit="%",  desc="% jours WG < Q10")
)

terraOptions(progress=1, memfrac=0.75, threads=N_CORES)  # Réduit à 0.75 pour safeguard RAM
for (d in c(MERGE_DIR, OUT_DIR)) if (!dir.exists(d)) dir.create(d, recursive=TRUE)

# Masque France (mainland + Corse) - elimine les pixels mer/hors-France
# Telecharger d'abord via : R/01_sources/0-Telecharger_limites_France.R
MASQUE_FRANCE_F <- MASQUE_FRANCE_GPKG
MASQUE_FRANCE <- if (file.exists(MASQUE_FRANCE_F)) {
  tryCatch(vect(MASQUE_FRANCE_F), error=function(e) { cat("[WARN] Masque France illisible\n"); NULL })
} else {
  cat("[WARN] Masque France absent, calcul sans masque :", MASQUE_FRANCE_F, "\n"); NULL
}

# CROP_EXT : bbox du masque France + buffer 0.3 deg
# Evite de traiter les ~172 000 pixels hors-France du domaine EOBS europeen
# (705x266=187530 px -> ~165x100=16500 px France : gain x11 sur le temps Climpact)
CROP_EXT <- if (!is.null(MASQUE_FRANCE)) {
  tryCatch(ext(MASQUE_FRANCE) + 0.3, error=function(e) NULL)
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

fusionner <- function(base_dir, base_code, varname, debut, fin, merge_dir, crop_ext=NULL, var_unit="") {
  f_out <- file.path(merge_dir, sprintf("%s_%s_%d-%d_TEST.nc", base_code, varname, debut, fin))
  if (file.exists(f_out)) {
    n_attendu <- sum(sapply(debut:fin, function(y) if(y%%4==0&&(y%%100!=0||y%%400==0)) 366L else 365L))
    besoin_recreer <- tryCatch({
      mb <- file.size(f_out)/1e6
      if (mb < 0.1) TRUE
      else {
        r_ex <- rast(f_out)
        if (nlyr(r_ex) < n_attendu*0.95) TRUE
        else if (!is.null(crop_ext)) {
          ex_f <- ext(r_ex[[1]])
          crop_crs <- tryCatch({ p <- as.polygons(crop_ext, crs="EPSG:4326"); ext(project(p, crs(r_ex))) }, error=function(e) crop_ext)
          aire_crop <- (crop_crs$xmax-crop_crs$xmin)*(crop_crs$ymax-crop_crs$ymin)
          aire_f    <- (ex_f$xmax-ex_f$xmin)*(ex_f$ymax-ex_f$ymin)
          aire_f > aire_crop*2
        } else FALSE
      }
    }, error=function(e) TRUE)
    if (!besoin_recreer) { inf(sprintf("SKIP fusion (existe) : %s", basename(f_out))); return(f_out) }
    gc(); Sys.sleep(0.3)  # Liberer handles GDAL/terra avant suppression (Windows file lock)
    if (!supprimer(f_out) && file.exists(f_out)) {
      err(sprintf("Impossible de supprimer le fichier existant (verrou ?) : %s", basename(f_out)))
      return(NULL)
    }
  }
  fics <- file.path(base_dir, sprintf("%s_%s_%d.nc", base_code, varname, debut:fin))
  fics <- fics[file.exists(fics)]
  if (length(fics)==0) { err(sprintf("Aucun fichier %s_%s", base_code, varname)); return(NULL) }
  inf(sprintf("Fusion %s %s (%d ans)...", base_code, varname, length(fics)))
  tmp_files <- c()
  for (i in seq_along(fics)) {
    an <- as.integer(sub(".*_(\\d{4})\\.nc$", "\\1", fics[i]))
    cat(sprintf("\r      %d/%d : %d ...", i, length(fics), an)); flush.console()
    r_yr <- tryCatch(rast(fics[i]), error=function(e) NULL)
    if (is.null(r_yr)) next
    if (!is.null(crop_ext)) {
      crop_local <- tryCatch({ p <- as.polygons(ext(crop_ext), crs="EPSG:4326"); ext(project(p, crs(r_yr))) }, error=function(e) crop_ext)
      r_yr <- tryCatch(crop(r_yr, crop_local), error=function(e) r_yr)
    }
    # NE PAS masquer ici : le masque France sera applique en Etape C (apres Climpact),
    # en meme temps que la reprojection WGS84 -> L93.
    # Masquer avant Climpact avec CRS84 vs EPSG:4326 provoque une confusion d'axes
    # qui rend NA tous les pixels au sud de ~44 degres N.
    # if (!is.null(MASQUE_FRANCE))
    #   r_yr <- tryCatch(mask(r_yr, MASQUE_FRANCE), error=function(e) r_yr)
    f_tmp <- file.path(merge_dir, sprintf("_tmp_%s_%s_%d.nc", base_code, varname, i))
    ok_i <- tryCatch({ writeCDF(r_yr, f_tmp, varname=varname, unit=var_unit, compression=1, overwrite=TRUE); TRUE }, error=function(e) FALSE)
    rm(r_yr); gc()
    if (ok_i) { tmp_files <- c(tmp_files, f_tmp); cat(sprintf("\r      %d/%d : %d OK\n", i, length(fics), an)) }
  }
  if (length(tmp_files)==0) return(NULL)
  cat(sprintf("  Assemblage (%d fichiers)...\n", length(tmp_files)))
  # Assemblage ncdf4 annee par annee : evite la limite "long vectors" de terra
  # (nrow x ncol x nlyr > 2^31 sur grandes grilles, ex. EOBS europeen 353x524x16800)
  nc_w <- NULL
  ok_w <- tryCatch({
    # Infos spatiales + nom variable depuis le 1er fichier temporaire
    nc0   <- ncdf4::nc_open(tmp_files[1])
    dn    <- names(nc0$dim)
    d_lon <- dn[grepl("^lon|^x$", dn, ignore.case=TRUE)][1]
    d_lat <- dn[grepl("^lat|^y$", dn, ignore.case=TRUE)][1]
    if (is.na(d_lon) || is.na(d_lat))
      stop("Dimensions lon/lat introuvables dans ", basename(tmp_files[1]))
    lon_v  <- ncdf4::ncvar_get(nc0, d_lon)
    lat_v  <- ncdf4::ncvar_get(nc0, d_lat)
    vn_tmp <- names(nc0$var)[!tolower(names(nc0$var)) %in%
                c("lon","lat","x","y","time","crs","time_bnds","bounds")][1]
    if (is.na(vn_tmp)) vn_tmp <- varname
    ncdf4::nc_close(nc0)
    nx <- length(lon_v); ny <- length(lat_v)
    # Axe temps commun : dates terra → "days since 1970-01-01"
    all_dates <- do.call(c, lapply(tmp_files, function(f) time(rast(f))))
    t_orig <- as.Date("1970-01-01")
    t_vals <- as.numeric(all_dates - t_orig)
    # Creer le NC de sortie
    dim_x <- ncdf4::ncdim_def(d_lon, "degrees_east",  lon_v)
    dim_y <- ncdf4::ncdim_def(d_lat, "degrees_north", lat_v)
    dim_t <- ncdf4::ncdim_def("time",
                              paste("days since", format(t_orig)), t_vals, unlim=TRUE)
    v_def <- ncdf4::ncvar_def(varname, var_unit, list(dim_x, dim_y, dim_t),
                              missval=NA_real_, compression=1)
    nc_w  <- ncdf4::nc_create(f_out, list(v_def))
    # Ecrire annee par annee (1 seule annee en RAM a la fois)
    t_off <- 0L
    for (f_t in tmp_files) {
      nc_i <- ncdf4::nc_open(f_t)
      vnr  <- names(nc_i$var)[!tolower(names(nc_i$var)) %in%
                 c("lon","lat","x","y","time","crs","time_bnds","bounds")][1]
      if (is.na(vnr)) vnr <- varname
      dat  <- ncdf4::ncvar_get(nc_i, vnr, collapse_degen=FALSE)
      ncdf4::nc_close(nc_i)
      n_ly <- dim(dat)[3]
      ncdf4::ncvar_put(nc_w, varname, dat,
                       start=c(1L, 1L, t_off + 1L),
                       count=c(nx, ny, n_ly))
      t_off <- t_off + n_ly
      rm(dat); gc()
    }
    ncdf4::nc_close(nc_w); nc_w <- NULL
    TRUE
  }, error=function(e) {
    if (!is.null(nc_w)) try(ncdf4::nc_close(nc_w), silent=TRUE)
    err(sprintf("Assemblage ncdf4 echoue : %s", conditionMessage(e)))
    if (file.exists(f_out)) supprimer(f_out)
    FALSE
  })
  gc(); file.remove(tmp_files)
  if (ok_w) { ok(sprintf("Fusion OK : %.0f Mo", file.size(f_out)/1e6)); f_out } else NULL
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

calc_etp <- function(f_tmax, f_tmin, f_out, compression=5) {
  if (index_valide(f_out)) { inf(sprintf("SKIP ETP : %s", basename(f_out))); return(f_out) }
  inf("Calcul ETP Turc (Rs estimee par Hargreaves : Rs = 0.16*sqrt(dT)*Ra)...")
  dates   <- time(rast(f_tmax))
  years   <- sort(unique(year(dates)))
  lat_rad <- mean(yFromRow(rast(f_tmax)[[1]], seq(1, nrow(rast(f_tmax)[[1]]), length.out=10))) * pi/180
  ra_vec  <- sapply(yday(dates), function(J) {
    dr <- 1+0.033*cos(2*pi*J/365); d <- 0.409*sin(2*pi*J/365-1.39)
    ws <- acos(pmax(-1, pmin(1, -tan(lat_rad)*tan(d))))
    (24*60/pi)*0.082*dr*(ws*sin(lat_rad)*sin(d)+cos(lat_rad)*cos(d)*sin(ws))
  })
  n_c <- max(1L, min(length(years), N_CORES))
  cl  <- makeCluster(n_c, type="PSOCK")
  on.exit(stopCluster(cl), add=TRUE)
  clusterEvalQ(cl, { library(terra); library(lubridate) })
  clusterExport(cl, c("f_tmax","f_tmin","dates","ra_vec","f_out"), envir=environment())
  tmp_list <- parLapply(cl, seq_along(years), function(i) {
    an <- years[i]; idx <- which(year(dates)==an)
    r_tx <- rast(f_tmax)[[idx]]; r_tn <- rast(f_tmin)[[idx]]
    r_tm <- (r_tx + r_tn) / 2
    r_dt <- ifel(r_tx > r_tn, sqrt(r_tx - r_tn), 0)
    # Rs (cal/cm2/jour) = 0.16 * sqrt(dT) * Ra [MJ/m2] * 23.884 ; Ra layer-wise
    Rs_cal <- r_dt * (0.16 * 23.884 * ra_vec[idx])
    r_e    <- ifel(r_tm > 0, 0.013 * r_tm / (r_tm + 15) * (Rs_cal + 50), 0)
    time(r_e) <- dates[idx]
    f_tmp <- sub("\\.nc$", sprintf("_etpturc_tmp_%d.nc", an), f_out)
    writeCDF(r_e, f_tmp, varname="etp", compression=1, overwrite=TRUE); f_tmp
  })
  tmp_files <- unlist(tmp_list); tmp_files <- tmp_files[file.exists(tmp_files)]
  r_etp <- rast(tmp_files)
  tryCatch({ writeCDF(r_etp, f_out, varname="etp", unit="mm", compression=compression, overwrite=TRUE)
             ok(sprintf("ETP Turc OK : %d couches, %.0f Mo", nlyr(r_etp), file.size(f_out)/1e6)) },
           error=function(e) err(conditionMessage(e)))
  file.remove(tmp_files[file.exists(tmp_files)]); rm(r_etp); gc(); f_out
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
  for (t in seq_len(nt)) values(r_out[[t]]) <- as.vector(dat[,,t])
  r_out
}

agreger <- function(f_mensuel, nom_indice, saison_mois, type_agg, out_dir, base_code, template_r=NULL, nom_saison=NULL) {
  if (!file.exists(f_mensuel)) { err(sprintf("Absent : %s", basename(f_mensuel))); return(NULL) }
  nom_sais <- if (!is.null(nom_saison)) nom_saison else
              switch(paste(sort(saison_mois), collapse="-"),
                "3-4-5"="MAM","6-7-8"="JJA","9-10-11"="SON","1-2-12"="DJF","4-5-6-7-8-9"="veg",
                paste(saison_mois,collapse=""))
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
  # Axe temps fixe APRES la boucle de remplissage : r_out[[i]]<- efface le time
  # s'il est pose avant -> dates "Inf"/NA en sortie (bug corrige 2026-06-10).
  # Conventionnel : 15 du dernier mois de saison (SEP-MAI->12, MAR-NOV->11, MAR-AUG->8).
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

# WG10P approche : bilan hydrique journalier (prec - etp) sous le Q10 de reference
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

  # Parallele via fichiers NC : les workers ne recoivent que chemins + vecteurs plain R
  # (terra SpatRaster non serialisable en PSOCK → erreur "NULL symbolic address")
  wg_tmp_dir <- NULL
  men_results <- if (n_par > 1) {
    wg_tmp_dir <- file.path(dirname(f_prec), "_wg10p_tmp")
    dir.create(wg_tmp_dir, showWarnings = FALSE, recursive = TRUE)
    # Ecrire q10 mensuels sur disque pour les workers
    q10_paths <- lapply(seq_along(q10), function(m) {
      if (is.null(q10[[m]])) return(NULL)
      fp <- file.path(wg_tmp_dir, sprintf("q10_m%02d.nc", m))
      writeCDF(q10[[m]], fp, varname = "q10", overwrite = TRUE); fp
    })
    # Fonction worker : entrees/sorties = chemins de fichiers uniquement
    .worker_wg <- function(an) {
      library(terra); library(lubridate)
      rp <- rast(.wg_fp); re <- rast(.wg_fe)
      avw <- year(time(rp)); mvw <- month(time(rp))
      out_f <- character(0); out_d <- character(0)
      for (m in seq_along(.wg_q10)) {
        if (is.null(.wg_q10[[m]])) next
        idx <- which(avw == an & mvw == m)
        if (!length(idx)) next
        rwg  <- rp[[idx]] - re[[idx]]
        # PATCH NA-safe (le worker parallele avait ete oublie par le fix 2026-06-03) :
        # denominateur = jours VALIDES (pas total) ; NA si aucun jour valide (pas 0 parasite).
        lt   <- rwg < rast(.wg_q10[[m]])
        cnt  <- app(lt, function(x) sum(x, na.rm = TRUE))
        nval <- app(lt, function(x) sum(!is.na(x)))
        pct  <- ifel(nval > 0, cnt / nval * 100, NA)
        fp  <- file.path(.wg_td, sprintf("res_%d_m%02d.nc", an, m))
        writeCDF(pct, fp, varname = "wg10p", overwrite = TRUE)
        out_f <- c(out_f, fp); out_d <- c(out_d, sprintf("%d-%02d-15", an, m))
      }
      list(files = out_f, dates = out_d)
    }
    env_w <- new.env(parent = emptyenv())
    env_w$.wg_fp <- f_prec; env_w$.wg_fe <- f_etp
    env_w$.wg_q10 <- q10_paths; env_w$.wg_td <- wg_tmp_dir
    cl_wg <- tryCatch(parallel::makeCluster(n_par, type = "PSOCK"), error = function(e) NULL)
    res_par <- NULL
    if (!is.null(cl_wg)) {
      res_par <- tryCatch({
        parallel::clusterEvalQ(cl_wg, { library(terra); terraOptions(threads = 1L) })
        # all.names=TRUE : les variables exportees (.wg_fp/.wg_fe/.wg_q10/.wg_td)
        # commencent par un point ; sans cette option ls() les masque et le worker
        # echoue avec "objet '.wg_fp' introuvable" (bascule sequentielle silencieuse).
        parallel::clusterExport(cl_wg, ls(envir = env_w, all.names = TRUE), envir = env_w)
        parallel::parLapply(cl_wg, ann, .worker_wg)
      }, error = function(e) {
        cat(sprintf("  [WG10P] parallele echoue (%s) -> sequentiel\n", conditionMessage(e))); NULL
      })
      parallel::stopCluster(cl_wg)
    }
    if (!is.null(res_par)) {
      # Relire resultats depuis disque → format attendu par la suite (list ml + md)
      lapply(res_par, function(r) {
        list(ml = Filter(Negate(is.null),
                         lapply(r$files, function(f) tryCatch(rast(f), error = function(e) NULL))),
             md = as.Date(r$dates))
      })
    } else lapply(ann, calc_une_annee_wg)
  } else {
    lapply(ann, calc_une_annee_wg)
  }
  gc()
  if (!is.null(wg_tmp_dir) && dir.exists(wg_tmp_dir)) unlink(wg_tmp_dir, recursive = TRUE)

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
# TRAITEMENT EOBS
# ==============================================================================

cat(sprintf("\n%s\n  ECE - %s  %d-%d\n%s\n", strrep("=",70), BASE$code, BASE$debut, BASE$fin, strrep("=",70)))
t0_base <- proc.time()[["elapsed"]]

out_climpact <- file.path(OUT_DIR,
  if (PERIODE_IDX >= 1L && PERIODE_IDX <= 5L)
    sprintf("climpact_raw_%s", PERIODES[[PERIODE_IDX]]$tag)
  else "climpact_raw")
if (!dir.exists(out_climpact)) dir.create(out_climpact, recursive=TRUE)

# --- Etape A : Fusion ---
cat("\n--- ETAPE A : Fusion ---\n")
# IMPORTANT : var_unit="celsius" est indispensable — udunits2::ud.convert("","degrees_C") -> 100% NA
f_tmax <- fusionner(BASE$dir, BASE$code, "tmax", FULL_DEBUT, FULL_FIN, MERGE_DIR, CROP_EXT, var_unit="celsius")
f_tmin <- fusionner(BASE$dir, BASE$code, "tmin", FULL_DEBUT, FULL_FIN, MERGE_DIR, CROP_EXT, var_unit="celsius")
f_prec <- fusionner(BASE$dir, BASE$code, "prec", FULL_DEBUT, FULL_FIN, MERGE_DIR, CROP_EXT, var_unit="kg m-2 d-1")
if (is.null(f_tmax)||is.null(f_tmin)||is.null(f_prec)) stop("Fichiers sources manquants - arret.")

# Patch in-place : si les fichiers ont ete crees avant ce correctif (units=""),
# les ouvrir en mode ecriture et ajouter l'attribut units sans recalculer les donnees.
# udunits2::ud.convert echoue silencieusement avec units="" -> 100% NA dans Climpact.
patcher_units <- function(f_nc, varname, units_val) {
  if (is.null(f_nc) || !file.exists(f_nc)) return(invisible(NULL))
  nc <- tryCatch(ncdf4::nc_open(f_nc, write = TRUE), error = function(e) NULL)
  if (is.null(nc)) {
    cat(sprintf("  [WARN] patcher_units : impossible d'ouvrir %s\n", basename(f_nc)))
    return(invisible(NULL))
  }
  u <- tryCatch(ncdf4::ncatt_get(nc, varname, "units")$value, error = function(e) "")
  if (!nzchar(trimws(u))) {
    ncdf4::ncatt_put(nc, varname, "units", units_val)
    cat(sprintf("  [PATCH units] %-45s  %s -> '%s'\n", basename(f_nc), varname, units_val))
  } else {
    cat(sprintf("  [OK units]    %-45s  %s = '%s'\n", basename(f_nc), varname, u))
  }
  ncdf4::nc_close(nc)
  invisible(NULL)
}
cat("  Verification/correction attribut units :\n")
patcher_units(f_tmax, "tmax", "celsius")
patcher_units(f_tmin, "tmin", "celsius")

f_etp  <- calc_etp(f_tmax, f_tmin, file.path(MERGE_DIR, sprintf("%s_etp_turc_%d-%d.nc", BASE$code, FULL_DEBUT, FULL_FIN)))

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

# Cores disponibles : diviser par 5 quand 5 periodes tournent en simultane
.n_cores_totaux <- parallel::detectCores()
.n_cores_dispo  <- if (PERIODE_IDX >= 1L) {
  max(2L, floor((.n_cores_totaux - 2L) / N_PARALLEL_ECE))
} else {
  max(2L, .n_cores_totaux - 2L)
}

# Dimensions reelles de la grille (apres fusion + crop France)
nlat_grid       <- tryCatch(nrow(rast(f_tmax)), error=function(e) 100L)
.ncol_grid      <- tryCatch(ncol(rast(f_tmax)), error=function(e) 200L)
.n_jours_approx <- (FULL_FIN - FULL_DEBUT + 1L) * 365L
.n_vars         <- 3L

# RAM par ligne de latitude : ncol x n_jours x 3vars x 8 bytes x facteur_4
# (facteur_4 : tmax + tmin + prec en RAM + matrices internes climpact)
.ram_par_ligne_mb <- .ncol_grid * .n_jours_approx * .n_vars * 8 * 4 / 1e6

# Workers optimaux : minimum des 3 contraintes (RAM, CPU, lignes de grille)
.ram_usable_mb  <- max(4096, (.ram_free_gb - 8) * 1024)  # reserver 8 GB pour OS + autres process
.n_workers_ram  <- max(1L, floor(.ram_usable_mb / max(1, .ram_par_ligne_mb)))
.bottleneck     <- if (.n_workers_ram <= .n_cores_dispo && .n_workers_ram <= nlat_grid) "RAM" else if (nlat_grid <= .n_cores_dispo) "GRILLE" else "CPU"
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
# Nettoyage : supprimer fichiers d'une periode differente ET fichiers illisibles/corrompus
fics_obs <- list.files(out_climpact, pattern="\\.nc$", full.names=TRUE)
# 1. Fichiers hors periode courante (restes de configs precedentes)
fics_hors_periode <- fics_obs[!grepl(periode_tag, fics_obs)]
# 2. Fichiers de la periode courante mais corrompus (illisibles par terra)
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

# ── DIAGNOSTIC : structure des fichiers fusionnes ───────────────────────────
# (execute avant le test indices_presents pour diagnostiquer les bugs CF)
infiles_diag <- Filter(function(x) !is.null(x)&&file.exists(x), list(f_tmax,f_tmin,f_prec))
cat("  [DIAG] Verification structure fichiers NC :\n")
for (fic in infiles_diag) {
  nc_d <- tryCatch(ncdf4::nc_open(fic), error=function(e) NULL)
  if (is.null(nc_d)) { cat(sprintf("    ERREUR ouverture : %s\n", basename(fic))); next }
  cat(sprintf("    %s\n", basename(fic)))
  cat(sprintf("      variables  : %s\n", paste(names(nc_d$var), collapse=", ")))
  cat(sprintf("      dimensions : %s\n", paste(names(nc_d$dim), collapse=", ")))
  for (d in names(nc_d$dim)) {
    ax <- tryCatch(ncdf4::ncatt_get(nc_d, d, "axis")$value,         error=function(e) "ERR")
    un <- tryCatch(ncdf4::ncatt_get(nc_d, d, "units")$value,        error=function(e) "ERR")
    sn <- tryCatch(ncdf4::ncatt_get(nc_d, d, "standard_name")$value,error=function(e) "")
    cat(sprintf("        [%s] len=%-6d axis='%s'  units='%s'  std_name='%s'\n",
                d, nc_d$dim[[d]]$len, ax, un, sn))
  }
  vdata <- names(nc_d$var)[!tolower(names(nc_d$var)) %in%
              c("lon","lat","longitude","latitude","x","y","time","crs")]
  if (length(vdata) > 0) {
    axes_result <- tryCatch(
      { ax2 <- ncdf4.helpers::nc.get.dim.axes(nc_d, vdata[1])
        paste(names(ax2), ax2, sep="=", collapse=", ") },
      error=function(e) paste("ERREUR:", conditionMessage(e)))
    cat(sprintf("      nc.get.dim.axes('%s') : %s\n", vdata[1], axes_result))
  }
  ncdf4::nc_close(nc_d)
}
cat("\n")
# ── FIN DIAGNOSTIC ──────────────────────────────────────────────────────────

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

  # EOBS est WGS84 natif : pas de reprojection necessaire
  tmpl <- sprintf("var_daily_%s_historical_NA_%d-%d.nc", tolower(BASE$code), BASE$debut, BASE$fin)
  withCallingHandlers(
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
      error=function(e) {
        err(sprintf("ERREUR climpact : %s", conditionMessage(e)))
        ec <- conditionCall(e)
        if (!is.null(ec)) cat(sprintf("    [CALL] %s\n", paste(deparse(ec), collapse=" ")))
      }),
    error=function(e) {
      # Capture traceback avant que tryCatch ne debrobe la pile
      cat("  [TRACEBACK Climpact]\n")
      sc <- sys.calls()
      # Afficher les 15 derniers appels de la pile
      n_show <- min(15L, length(sc))
      for (i in seq(length(sc)-n_show+1L, length(sc))) {
        line1 <- tryCatch(deparse(sc[[i]])[1], error=function(e2) "?")
        cat(sprintf("    %2d: %s\n", i, substr(line1, 1, 120)))
      }
    })
} else {
  inf(sprintf("SKIP climpact (indices presents : %s)", paste(INDICES_CIBLE,collapse=",")))
}

# --- Etape C : Agregation multi-saisonniere (4 indices, 1 valeur/an) ---
# TXx   : MAR-NOV (max sur 9 mois, hors hiver)
# TNn   : SEP-MAY (min ; hiver COMPLET a cheval : SEP(Y-1)..MAI(Y), comme CWN)
# SPEI6 : MAR-AUG (mean sur 6 mois, printemps + ete)
# WG10P : MAR-AUG (% jours WG < Q10 sur 6 mois, printemps + ete)
}  # fin du bloc saute par ONLY_WG10P_HWN_CWN (climpact ETAPE B)
cat("\n--- ETAPE C : Agregation multi-saisonniere (4 indices) ---\n")
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
    rb   <- as.integer(ceiling(nr / n_par_s))
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
cat(sprintf("\n%s\n  EOBS termine en %s\n  Sorties : %s\n%s\n",
    strrep("=",70), fmt_dur(dur), OUT_DIR, strrep("=",70)))
