# ======================================================================
# Production DIGITALIS daily downscale IDW - Periode complete 1960-2024 (fusion 5+7)
# Parallelisation par annee sur CALCULUS (36 coeurs physiques, 384 Go RAM)
#
# PARTAGE CALCULUS : script configure pour cohabiter avec les autres
# utilisateurs du serveur de calcul.
# Regler N_WORKERS selon la charge au moment du lancement :
#   Serveur libre (nuit/week-end) : 16 workers
#   Charge moderee (quelques users) :  8 workers  <- valeur par defaut
#   Serveur charge                  :  4 workers
#
# MODIFICATIONS v2 (anti-pic CPU) :
#   [1] OMP_NUM_THREADS = 2 : bloque les pics interpIDW/resample
#       (ces fonctions ignorent terraOptions et utilisent OpenMP directement)
#   [2] N_WORKERS adaptatif : detecte la charge CPU avant de se lancer
#   [3] Priorite processus via PowerShell (wmic deprecie sur Server 2019)
#   [4] terraOptions enrichis dans chaque worker : memmax + memfrac + tempdir
#
# Structure :
#   Phase 0 : Pre-cache des annees SAFRAN depuis les CSV decennaux (1 fois)
#   Phase 1 : Production parallele - 1 worker par annee
#             Chaque worker traite les 12 mois -> TIF journaliers
#
# Sorties : OUT_SAFRAN/{ANNEE}/ (cf config_chemins.R)
#           prec_DS_IDW_YYYYMMDD.tif    <- produit principal
#           safran_IDW_1km_YYYYMMDD.tif <- SAFRAN interpole (diagnostics)
#           safran_brut_8km_YYYYMMDD.tif <- SAFRAN brut (diagnostics)
# ======================================================================

library(parallel)
library(terra)
library(data.table)
library(lubridate)

# Chemins du pipeline : editer config_chemins.R (racine des donnees via DIGI_ROOT).
# Lancer depuis R/02_downscaling/ (ou avoir config_chemins.R dans le working dir).
if (!exists("DIGI_PREC")) source("config_chemins.R")

# ======================================================================
# 1. Parametres globaux
# ======================================================================

IDW_POWER  <- 0.5      # optimise sur septembre 2014
IDW_RADIUS <- 50000    # 50 km

# Periode disponible (CSV SAFRAN par decennie : 1960-2019)
# Surcharge SANDBOX (test bout-en-bout) : si defini avant source(), restreint sortie/periode/emprise.
ANNEES       <- if (exists("SANDBOX_ANNEES")) SANDBOX_ANNEES else 1960:2024
# en vecteur numerique (xmin,xmax,ymin,ymax) : un SpatExtent terra ne survit PAS
# a l'export vers les workers PSOCK (pointeur externe) -> reconstruit via ext() cote worker.
SANDBOX_CROP <- if (exists("SANDBOX_CROP_EXT")) as.vector(terra::ext(SANDBOX_CROP_EXT)) else NULL

# ====== MODIF v2 [1] : limiter OMP avant tout calcul ===============================================================
# interpIDW() et resample() utilisent OpenMP/BLAS en interne
# sans respecter terraOptions(threads=1) -> pics a 100% CPU
# Avec OMP_NUM_THREADS = 2 :
#   N_WORKERS x 2 threads OMP = charge maitrisee
#   ex : 8 workers x 2 = 16 threads / 36 coeurs = 44% max
Sys.setenv(OMP_NUM_THREADS      = "2")
Sys.setenv(OPENBLAS_NUM_THREADS = "2")
Sys.setenv(MKL_NUM_THREADS      = "2")
cat("Threads OMP/BLAS limites a 2 par worker\n")

# ====== MODIF v2 [2] : N_WORKERS adaptatif selon charge CPU courante ==================
cpu_actuel <- tryCatch({
  out <- system(
    paste0('powershell -Command "Get-Counter ',
           "\'\\\\Processor(_Total)\\\\% Processor Time\'",
           ' | Select-Object -ExpandProperty CounterSamples',
           ' | Select-Object -ExpandProperty CookedValue"'),
    intern = TRUE)
  val <- suppressWarnings(as.numeric(trimws(out[length(out)])))
  if (is.na(val)) stop("valeur NA")
  val
}, error   = function(e) { 30 },
warning = function(w) { 30 })

# Garantie anti-NA : si la detection a malgre tout echoue
if (is.na(cpu_actuel) || length(cpu_actuel) == 0) cpu_actuel <- 30

cat(sprintf("Charge CPU actuelle : %.0f%%\n", cpu_actuel))

N_WORKERS <- if (cpu_actuel < 20) {
  cat("Serveur libre -> 16 workers\n");  16L
} else if (cpu_actuel < 50) {
  cat("Charge moderee -> 8 workers\n");   8L
} else {
  cat("Serveur charge -> 4 workers\n");   4L
}

cat(sprintf("Workers retenus : %d  |  charge max estimee : ~%.0f%%\n\n",
            N_WORKERS, N_WORKERS * 2 / 36 * 100))

# ====== MODIF v2 [3] : priorite processus via PowerShell ======================================================
# wmic est deprecie sur Windows Server 2019
if (.Platform$OS.type == "windows") {
  tryCatch({
    system(paste0(
      'powershell -Command "Get-Process Rscript,Rgui -ErrorAction SilentlyContinue',
      ' | ForEach-Object {',
      ' $_.PriorityClass =',
      ' [System.Diagnostics.ProcessPriorityClass]::BelowNormal}"'),
      ignore.stdout = TRUE, ignore.stderr = TRUE)
    cat("Priorite processus R : Sous la normale\n")
  }, error = function(e) cat("Note : impossible de changer la priorite\n"))
}

# Chemins : issus de 0-Config_chemins.R (source de verite unique)
PATH_SAFRAN_BASE <- SAFRAN_CSV_DIR
PATH_DIGI_PREC   <- DIGI_PREC   # prec_YYYY_M.tif (0.1 mm  -> /10)
PATH_DIGI_TMIN   <- DIGI_TMIN   # tmin_YYYY_M.tif (0.1 degC -> /10)
PATH_DIGI_TMAX   <- DIGI_TMAX   # tmax_YYYY_M.tif (0.1 degC -> /10)
PATH_FRANCE      <- FRANCE_SHP
PATH_OUT_BASE    <- if (exists("SANDBOX_OUT")) file.path(SANDBOX_OUT, "DIGI_SAF_IDW_TIF") else OUT_SAFRAN
PATH_CACHE       <- CACHE_SAFRAN

# Dossier temp terra dedie (evite de saturer %TEMP% systeme)
PATH_TERRA_TMP   <- file.path(PATH_OUT_BASE, "tmp_terra")

# Colonnes SAFRAN temperature
COL_TMIN <- "TINF_H_Q"   # temperature minimale journaliere SAFRAN
COL_TMAX <- "TSUP_H_Q"   # temperature maximale journaliere SAFRAN

dir.create(PATH_OUT_BASE,   recursive = TRUE, showWarnings = FALSE)
dir.create(PATH_CACHE,      recursive = TRUE, showWarnings = FALSE)
dir.create(PATH_TERRA_TMP,  recursive = TRUE, showWarnings = FALSE)

# Fichier de log global
PATH_LOG <- file.path(PATH_OUT_BASE, sprintf("production_log_%s.txt",
                                             format(Sys.time(), "%Y%m%d_%H%M%S")))

log_msg <- function(...) {
  msg <- paste0(format(Sys.time(), "[%H:%M:%S] "), ...)
  cat(msg, "\n")
  cat(msg, "\n", file = PATH_LOG, append = TRUE)
}

log_msg("=== DEMARRAGE PRODUCTION COMPLETE IDW v2 ===")
log_msg(sprintf("Periode : %d - %d (%d annees)",
                min(ANNEES), max(ANNEES), length(ANNEES)))
log_msg(sprintf("Parametres : IDW power=%g  radius=%g km", IDW_POWER, IDW_RADIUS / 1000))
log_msg(sprintf("Workers : %d / %d coeurs physiques",
                N_WORKERS, parallel::detectCores(logical = FALSE)))
log_msg(sprintf("OMP threads par worker : 2  |  charge max ~%.0f%%",
                N_WORKERS * 2 / 36 * 100))

# ======================================================================
# 2. Utilitaire : CSV SAFRAN par decennie
# ======================================================================
get_safran_csv <- function(annee) {
  # 2026-06-08 : fusion de 7-Completion_IDW_2020_2024. 1960-2019 = CSV decennaux
  # gzippes ; 2020-2024 = CSV SIM2 "previous" non-decennal (meme format de colonnes,
  # lu par le meme reader generique en Phase 0), avec fallback 202402.
  if (annee >= 2020L) {
    f1 <- file.path(PATH_SAFRAN_BASE, "QUOT_SIM2_previous-2020-202410.csv")
    f2 <- file.path(PATH_SAFRAN_BASE, "QUOT_SIM2_previous-2020-202402.csv")
    return(if (file.exists(f1)) f1 else f2)
  }
  d0 <- floor(annee / 10) * 10
  file.path(PATH_SAFRAN_BASE,
            sprintf("QUOT_SIM2_%d-%d.csv.gz", d0, d0 + 9))
}

# ======================================================================
# Phase 0 : Pre-cache des annees SAFRAN
# Chaque CSV decennal est lu UNE SEULE FOIS -> 10 RDS annuels par CSV
# Evite les race conditions entre workers
# ======================================================================
log_msg("\n--- Phase 0 : Pre-cache SAFRAN ---")

csv_files <- unique(sapply(ANNEES, get_safran_csv))

for (f_csv in csv_files) {
  
  if (!file.exists(f_csv)) {
    log_msg(sprintf("ATTENTION : CSV introuvable -> %s", basename(f_csv)))
    next
  }
  
  annees_csv <- ANNEES[sapply(ANNEES, get_safran_csv) == f_csv]
  
  mtime_str <- format(file.mtime(f_csv), "%Y%m%d%H%M")
  annees_a_cacher <- annees_csv[!sapply(annees_csv, function(a) {
    file.exists(file.path(PATH_CACHE,
                          sprintf("safran_annee_%d_%s.rds", a, mtime_str)))
  })]
  
  if (length(annees_a_cacher) == 0) {
    log_msg(sprintf("  %s : caches deja presents (%d annees)",
                    basename(f_csv), length(annees_csv)))
    next
  }
  
  log_msg(sprintf("  Lecture %s -> %d annees a cacher...", basename(f_csv),
                  length(annees_a_cacher)))
  t0 <- proc.time()
  
  raw <- fread(f_csv, sep = ";", na.strings = c("", "NA"))
  raw[, DATE := {
    d <- as.character(DATE)
    if (grepl("-", d[1])) as.Date(d) else as.Date(d, format = "%Y%m%d")
  }]
  raw[, ANNEE_COL := year(DATE)]
  raw[, MOIS      := month(DATE)]
  
  cols_num <- c("LAMBX", "LAMBY", "PRELIQ_Q", "PRENEI_Q",
                "TINF_H_Q", "TSUP_H_Q")
  for (col in cols_num[cols_num %in% names(raw)])
    set(raw, j = col, value = as.numeric(gsub(",", ".", raw[[col]])))
  
  if (all(c("PRELIQ_Q", "PRENEI_Q") %in% names(raw))) {
    raw[, PRECIP_J := PRELIQ_Q + PRENEI_Q]
  } else if ("PRECIP_J" %in% names(raw)) {
    # colonne deja presente
  } else {
    log_msg(sprintf("  ERREUR : colonnes precip introuvables dans %s", basename(f_csv)))
    rm(raw); gc(); next
  }
  
  for (col_t in c("TINF_H_Q", "TSUP_H_Q")) {
    if (!col_t %in% names(raw))
      log_msg(sprintf("  ATTENTION : %s absent du CSV -> tmin/tmax ignores", col_t))
  }
  
  log_msg(sprintf("  Lecture CSV : %.0f sec", (proc.time() - t0)["elapsed"]))
  
  for (a in annees_a_cacher) {
    f_rds <- file.path(PATH_CACHE,
                       sprintf("safran_annee_%d_%s.rds", a, mtime_str))
    dt_a  <- raw[ANNEE_COL == a]
    if (nrow(dt_a) == 0) {
      log_msg(sprintf("  ATTENTION : annee %d absente du CSV", a))
      next
    }
    saveRDS(dt_a, f_rds, compress = TRUE)
    log_msg(sprintf("  Cache cree : %s (%.1f Mo | %d lignes)",
                    basename(f_rds), file.size(f_rds) / 1024^2, nrow(dt_a)))
  }
  
  rm(raw); gc()
}

log_msg("--- Phase 0 terminee ---\n")

# ======================================================================
# Phase 1 : Production parallele par annee
# ======================================================================
log_msg("--- Phase 1 : Production parallele ---")

process_annee <- function(annee, idw_power, idw_radius,
                          path_cache, path_safran_base,
                          path_digi_prec, path_digi_tmin, path_digi_tmax,
                          col_tmin, col_tmax,
                          path_france, path_out_base,
                          path_terra_tmp, path_log_worker, crop_ext = NULL) {
  
  suppressPackageStartupMessages({
    library(terra)
    library(data.table)
    library(lubridate)
  })
  
  # ====== MODIF v2 [4] : terraOptions enrichis =======================================================================================
  # threads = 1  : terra n'utilise qu'1 thread (OMP gere les 2 autorises)
  # memmax  = 8  : max 8 Go RAM par worker
  #                (384 Go / 8 workers = 48 Go dispo, on prend 8 par securite)
  # memfrac = 0.3 : terra n'utilise pas plus de 30% de la RAM detectee
  # tempdir      : evite de saturer %TEMP% systeme avec les fichiers temporaires
  terraOptions(threads = 1,
               memmax  = 8,
               memfrac = 0.3,
               progress = 0,
               tempdir  = path_terra_tmp)
  
  # Propager les limites OMP dans le worker
  Sys.setenv(OMP_NUM_THREADS      = "2")
  Sys.setenv(OPENBLAS_NUM_THREADS = "2")
  Sys.setenv(MKL_NUM_THREADS      = "2")
  
  wlog <- function(...) {
    msg <- paste0(format(Sys.time(), "[%H:%M:%S] "), sprintf("[%d] ", annee), ...)
    cat(msg, "\n", file = path_log_worker, append = TRUE)
  }
  
  wlog(sprintf("=== Debut traitement annee %d ===", annee))
  
  # -- Charger le cache SAFRAN ------------------------------------------
  d0 <- floor(annee / 10) * 10
  f_csv <- file.path(path_safran_base,
                     sprintf("QUOT_SIM2_%d-%d.csv.gz", d0, d0 + 9))
  if (!file.exists(f_csv)) {
    wlog("ERREUR : CSV SAFRAN introuvable")
    return(list(annee = annee, ok = 0L, miss = 0L, err = "csv_absent"))
  }
  
  mtime_str <- format(file.mtime(f_csv), "%Y%m%d%H%M")
  f_rds <- file.path(path_cache,
                     sprintf("safran_annee_%d_%s.rds", annee, mtime_str))
  if (!file.exists(f_rds)) {
    wlog("ERREUR : cache RDS absent (phase 0 incomplete ?)")
    return(list(annee = annee, ok = 0L, miss = 0L, err = "cache_absent"))
  }
  
  safran_annee <- readRDS(f_rds)
  wlog(sprintf("Cache charge : %d lignes", nrow(safran_annee)))
  
  france      <- vect(path_france)
  crs(france) <- "EPSG:2154"
  emp_france  <- ext(france)
  
  safran_idw_fn <- function(df, col_v, tmpl) {
    vals <- df[[col_v]]
    ok   <- !is.na(vals) & !is.na(df$LAMBX) & !is.na(df$LAMBY)
    if (sum(ok) < 3) return(NULL)
    pts <- vect(data.frame(x = df$LAMBX[ok] * 100,
                           y = df$LAMBY[ok] * 100,
                           v = vals[ok]),
                geom = c("x", "y"), crs = "EPSG:27572")
    pts <- project(pts, crs(tmpl))
    tryCatch(interpIDW(tmpl, pts, field = "v",
                       power = idw_power, radius = idw_radius),
             error = function(e) NULL)
  }
  
  safran_brut_fn <- function(df, col_v, tmpl) {
    vals <- df[[col_v]]
    ok   <- !is.na(vals) & !is.na(df$LAMBX) & !is.na(df$LAMBY)
    if (sum(ok) < 1) return(NULL)
    pts <- vect(data.frame(x = df$LAMBX[ok] * 100,
                           y = df$LAMBY[ok] * 100,
                           v = vals[ok]),
                geom = c("x", "y"), crs = "EPSG:27572")
    pts <- project(pts, crs(tmpl))
    tmpl_8km <- rast(ext = ext(tmpl), res = 8000, crs = crs(tmpl))
    rasterize(pts, tmpl_8km, field = "v", fun = "mean")
  }
  
  n_ok_total   <- 0L
  n_miss_total <- 0L
  
  for (mois in 1:12) {
    
    safran_m <- safran_annee[month(DATE) == mois]
    if (nrow(safran_m) == 0) {
      wlog(sprintf("  Mois %02d : pas de donnees SAFRAN", mois))
      next
    }
    
    path_out_m <- file.path(path_out_base, as.character(annee),
                            sprintf("%02d", mois))
    for (sub in c("precipitations", "safran_idw", "tmin", "tmax"))
      dir.create(file.path(path_out_m, sub),
                 recursive = TRUE, showWarnings = FALSE)
    
    f_digi <- file.path(path_digi_prec,
                        sprintf("prec_%d_%d.tif", annee, mois))
    if (!file.exists(f_digi)) {
      wlog(sprintf("  Mois %02d : DIGITALIS prec introuvable -> %s",
                   mois, basename(f_digi)))
      next
    }
    
    tmpl   <- rast(f_digi)
    if (!is.null(crop_ext)) {   # SANDBOX : restreint la grille de calcul a l'emprise test (WGS84 -> crs grille)
      .cp  <- terra::project(terra::as.polygons(terra::ext(crop_ext), crs = "EPSG:4326"), terra::crs(tmpl))
      tmpl <- terra::crop(tmpl, .cp)
    }
    digi_m <- clamp(tmpl / 10, lower = 0, values = FALSE)
    
    safran_m_sum <- safran_m[, .(
      LAMBX    = LAMBX[1],
      LAMBY    = LAMBY[1],
      PRECIP_M = sum(PRECIP_J, na.rm = TRUE)
    ), by = .(LAMBX, LAMBY)]
    
    r_idw_sum <- safran_idw_fn(safran_m_sum, "PRECIP_M", tmpl)
    if (is.null(r_idw_sum)) {
      wlog(sprintf("  Mois %02d : IDW mensuel precip echoue", mois))
      next
    }
    denom_m <- ifel(r_idw_sum < 0.001, 0.001, r_idw_sum)
    ratio_m <- clamp(digi_m / denom_m, lower = 0.001, upper = 5)
    if (!compareGeom(ratio_m, tmpl, stopOnError = FALSE))
      ratio_m <- resample(ratio_m, tmpl, method = "bilinear")
    
    has_tmin <- col_tmin %in% names(safran_m) &&
      file.exists(file.path(path_digi_tmin,
                            sprintf("tmin_%d_%d.tif", annee, mois)))
    has_tmax <- col_tmax %in% names(safran_m) &&
      file.exists(file.path(path_digi_tmax,
                            sprintf("tmax_%d_%d.tif", annee, mois)))
    
    if (has_tmin) {
      digi_tmin_m <- rast(file.path(path_digi_tmin,
                                    sprintf("tmin_%d_%d.tif", annee, mois))) / 10
      if (!compareGeom(digi_tmin_m, tmpl, stopOnError = FALSE))
        digi_tmin_m <- resample(digi_tmin_m, tmpl, method = "bilinear")
      
      safran_m_mean_tn <- safran_m[, .(
        LAMBX  = LAMBX[1], LAMBY = LAMBY[1],
        TMIN_M = mean(get(col_tmin), na.rm = TRUE)
      ), by = .(LAMBX, LAMBY)]
      r_idw_tmin_mean <- safran_idw_fn(safran_m_mean_tn, "TMIN_M", tmpl)
      if (is.null(r_idw_tmin_mean)) {
        has_tmin <- FALSE
      } else {
        delta_tmin_m <- digi_tmin_m - r_idw_tmin_mean
        if (!compareGeom(delta_tmin_m, tmpl, stopOnError = FALSE))
          delta_tmin_m <- resample(delta_tmin_m, tmpl, method = "bilinear")
      }
    }
    
    if (has_tmax) {
      digi_tmax_m <- rast(file.path(path_digi_tmax,
                                    sprintf("tmax_%d_%d.tif", annee, mois))) / 10
      if (!compareGeom(digi_tmax_m, tmpl, stopOnError = FALSE))
        digi_tmax_m <- resample(digi_tmax_m, tmpl, method = "bilinear")
      
      safran_m_mean_tx <- safran_m[, .(
        LAMBX  = LAMBX[1], LAMBY = LAMBY[1],
        TMAX_M = mean(get(col_tmax), na.rm = TRUE)
      ), by = .(LAMBX, LAMBY)]
      r_idw_tmax_mean <- safran_idw_fn(safran_m_mean_tx, "TMAX_M", tmpl)
      if (is.null(r_idw_tmax_mean)) {
        has_tmax <- FALSE
      } else {
        delta_tmax_m <- digi_tmax_m - r_idw_tmax_mean
        if (!compareGeom(delta_tmax_m, tmpl, stopOnError = FALSE))
          delta_tmax_m <- resample(delta_tmax_m, tmpl, method = "bilinear")
      }
    }
    
    jours_m <- sort(unique(safran_m$DATE))
    n_ok    <- 0L
    n_miss  <- 0L
    
    for (date_j in jours_m) {
      
      date_j_obj <- as.Date(date_j, origin = "1970-01-01")
      date_str   <- format(date_j_obj, "%Y%m%d")
      
      f_out_ds  <- file.path(path_out_m, "precipitations",
                             paste0("prec_DS_IDW_",     date_str, ".tif"))
      f_out_idw <- file.path(path_out_m, "safran_idw",
                             paste0("safran_IDW_1km_",  date_str, ".tif"))
      f_out_8km <- file.path(path_out_m, "safran_idw",
                             paste0("safran_brut_8km_", date_str, ".tif"))
      f_out_tn  <- file.path(path_out_m, "tmin",
                             paste0("tmin_DS_IDW_",     date_str, ".tif"))
      f_out_tx  <- file.path(path_out_m, "tmax",
                             paste0("tmax_DS_IDW_",     date_str, ".tif"))
      
      prec_done <- file.exists(f_out_ds)  && file.exists(f_out_idw)
      tn_done   <- !has_tmin || file.exists(f_out_tn)
      tx_done   <- !has_tmax || file.exists(f_out_tx)
      if (prec_done && tn_done && tx_done) { n_ok <- n_ok + 1L; next }
      
      safran_j <- safran_m[DATE == date_j_obj]
      
      if (!prec_done) {
        r_idw_j <- safran_idw_fn(safran_j, "PRECIP_J", tmpl)
        if (is.null(r_idw_j)) { n_miss <- n_miss + 1L; next }
        r_idw_j <- clamp(r_idw_j, lower = 0, values = FALSE)
        
        r_brut <- safran_brut_fn(safran_j, "PRECIP_J", tmpl)
        if (!is.null(r_brut))
          r_brut <- clamp(r_brut, lower = 0, values = FALSE)
        
        result_j  <- clamp(r_idw_j * ratio_m, lower = 0, values = FALSE)
        result_j  <- crop(mask(result_j, france), emp_france)
        r_idw_j_m <- crop(mask(r_idw_j,  france), emp_france)
        
        writeRaster(result_j,  f_out_ds,  overwrite = TRUE,
                    datatype = "FLT4S", gdal = "COMPRESS=LZW")
        writeRaster(r_idw_j_m, f_out_idw, overwrite = TRUE,
                    datatype = "FLT4S", gdal = "COMPRESS=LZW")
        if (!is.null(r_brut)) {
          writeRaster(crop(mask(r_brut, france), emp_france),
                      f_out_8km, overwrite = TRUE,
                      datatype = "FLT4S", gdal = "COMPRESS=LZW")
        }
      }
      
      if (has_tmin && !tn_done) {
        r_idw_tn <- safran_idw_fn(safran_j, col_tmin, tmpl)
        if (!is.null(r_idw_tn)) {
          tmin_ds <- crop(mask(r_idw_tn + delta_tmin_m, france), emp_france)
          writeRaster(tmin_ds, f_out_tn, overwrite = TRUE,
                      datatype = "FLT4S", gdal = "COMPRESS=LZW")
        }
      }
      
      if (has_tmax && !tx_done) {
        r_idw_tx <- safran_idw_fn(safran_j, col_tmax, tmpl)
        if (!is.null(r_idw_tx)) {
          tmax_ds <- crop(mask(r_idw_tx + delta_tmax_m, france), emp_france)
          writeRaster(tmax_ds, f_out_tx, overwrite = TRUE,
                      datatype = "FLT4S", gdal = "COMPRESS=LZW")
        }
      }
      
      n_ok <- n_ok + 1L
    }
    
    n_ok_total   <- n_ok_total   + n_ok
    n_miss_total <- n_miss_total + n_miss
    wlog(sprintf("  Mois %02d/%d : %d jours OK  %d manquants  [prec+tn:%s+tx:%s]",
                 mois, annee, n_ok, n_miss,
                 if (has_tmin) "OK" else "absent",
                 if (has_tmax) "OK" else "absent"))
  }
  
  wlog(sprintf("=== Fin annee %d : %d jours OK | %d manquants ===",
               annee, n_ok_total, n_miss_total))
  
  list(annee = annee, ok = n_ok_total, miss = n_miss_total, err = NA)
}

# -----------------------------------------------------------------------
# Lancement du cluster PSOCK (compatible Windows)
# -----------------------------------------------------------------------
log_msg(sprintf("Lancement cluster PSOCK : %d workers...", N_WORKERS))

cl <- makeCluster(N_WORKERS, type = "PSOCK")

# Log individuel par worker (evite conflits d'ecriture sur le log global)
path_log_workers <- file.path(PATH_OUT_BASE, "logs_workers")
dir.create(path_log_workers, showWarnings = FALSE)

clusterExport(cl, varlist = c(
  "process_annee",
  "IDW_POWER", "IDW_RADIUS",
  "PATH_CACHE", "PATH_SAFRAN_BASE",
  "PATH_DIGI_PREC", "PATH_DIGI_TMIN", "PATH_DIGI_TMAX",
  "PATH_FRANCE", "PATH_OUT_BASE",
  "PATH_TERRA_TMP",              # -> ajout v2
  "COL_TMIN", "COL_TMAX",
  "path_log_workers", "SANDBOX_CROP"
), envir = environment())

# ====== MODIF v2 : propager les limites OMP a chaque worker au demarrage ======
clusterEvalQ(cl, {
  Sys.setenv(OMP_NUM_THREADS      = "2")
  Sys.setenv(OPENBLAS_NUM_THREADS = "2")
  Sys.setenv(MKL_NUM_THREADS      = "2")
})

log_msg(sprintf("Traitement de %d annees...", length(ANNEES)))
t_start <- proc.time()

resultats <- parLapply(cl, ANNEES, function(a) {
  f_log_w <- file.path(path_log_workers,
                       sprintf("worker_%d.txt", a))
  process_annee(
    annee            = a,
    idw_power        = IDW_POWER,
    idw_radius       = IDW_RADIUS,
    path_cache       = PATH_CACHE,
    path_safran_base = PATH_SAFRAN_BASE,
    path_digi_prec   = PATH_DIGI_PREC,
    path_digi_tmin   = PATH_DIGI_TMIN,
    path_digi_tmax   = PATH_DIGI_TMAX,
    col_tmin         = COL_TMIN,
    col_tmax         = COL_TMAX,
    path_france      = PATH_FRANCE,
    path_out_base    = PATH_OUT_BASE,
    path_terra_tmp   = PATH_TERRA_TMP,   # -> ajout v2
    path_log_worker  = f_log_w,
    crop_ext         = SANDBOX_CROP
  )
})

stopCluster(cl)

t_elapsed <- (proc.time() - t_start)["elapsed"]

# ======================================================================
# Bilan final
# ======================================================================
bilan <- rbindlist(lapply(resultats, as.data.table))
n_ok_total   <- sum(bilan$ok,   na.rm = TRUE)
n_miss_total <- sum(bilan$miss, na.rm = TRUE)
n_err        <- sum(!is.na(bilan$err))

log_msg("\n=== BILAN PRODUCTION COMPLETE ===")
log_msg(sprintf("  Duree totale    : %.0f min", t_elapsed / 60))
log_msg(sprintf("  Jours produits  : %d", n_ok_total))
log_msg(sprintf("  Jours manquants : %d", n_miss_total))
log_msg(sprintf("  Annees en erreur: %d", n_err))
log_msg(sprintf("  Sorties : %s", PATH_OUT_BASE))

if (n_err > 0) {
  log_msg("  Annees avec erreurs :")
  print(bilan[!is.na(err)])
}

print(bilan)