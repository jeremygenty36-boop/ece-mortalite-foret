# ==================================================================================================================================================================================================================
# PRODUCTION DOWNSCALING BILINEAIRE (methode Delta) - E-OBS 0.1 deg -> 1km - 1961-2024
# Emplacement (depot) : R/02_downscaling/production_EOBS_bilineaire.R
#
# Methode : Delta (facteur de correction mensuel) + interpolation bilineaire
#   1. Stat mensuelle E-OBS (sum pour prec, mean pour temp)
#   2. Reprojection bilineaire vers la grille 1km L93
#   3. Facteur de correction DIGITALIS mensuel (ratio ou delta)
#   4. Application du facteur a chaque jour du mois
#
# Sortie : un fichier NetCDF par annee x variable
#   prec_EOBS_BCSD_bilinear_ANNEE.nc
#   tmin_EOBS_BCSD_bilinear_ANNEE.nc
#   tmax_EOBS_BCSD_bilinear_ANNEE.nc
#
# Securite ecriture : ecriture vers .tmp.nc puis renommage atomique
#   -> un crash en cours d'ecriture ne produit pas de fichier corrompu
#   -> les fichiers .nc existants et valides sont ignores (resume)
#
# Parallelisation : parLapply PSOCK - N_WORKERS adaptatif selon CPU
#   Chaque worker traite une tache (annee x variable)
#
# Machine cible : CALCULUS (2x Xeon Gold 6254, 36 coeurs, 384 Go RAM)
# ==================================================================================================================================================================================================================

library(terra)
library(lubridate)
library(parallel)

# Chemins du pipeline : editer config_chemins.R (racine des donnees via DIGI_ROOT).
# Lancer depuis R/02_downscaling/ (ou avoir config_chemins.R dans le working dir).
if (!exists("DIGI_PREC")) source("config_chemins.R")

# ==================================================================================================================================================================================================================
# SECTION 0 - PARAMETRES
# ==================================================================================================================================================================================================================

# ====== Periode de production =======================================================================================================================================
# ====== Periode de production =======================================================================================================================================
# Limite haute : 2024 (derniere annee complete dans E-OBS v31.0e)
# DIGITALIS v4 prec couvre jusqu'a 2025
# DIGITALIS v3 tmin/tmax : si absent pour une annee/mois,
#   le script bascule automatiquement en bilinear pur (warning dans log)
ANNEES_RUN <- if (exists("SANDBOX_ANNEES")) SANDBOX_ANNEES else 1961:2024

# ====== Periode de reference pour les seuils ECE (ne pas modifier) =====================
# Independante de la periode de production :
# sert uniquement au calcul des indices ECE en aval
ANNEES_REF   <- 1961:1990

# ====== Parametres techniques =======================================================================================================================================
COMPRESSION  <- 5              # compression NetCDF (0-9)
DATE_ORIGINE <- as.Date("1950-01-01")

# ====== Chemins =================================================================================================================================================================================
# EOBS et DIGITALIS : miroir local D: si present (lecture rapide), sinon reseau S:.
PATHS <- list(
  eobs      = EOBS_DIR,          # E-OBS brut (NetCDF WGS84)
  digi_prec = DIGI_PREC_LOCAL,   # DIGITALIS v4 prec mensuel (0.1 mm)
  digi_tmin = DIGI_TMIN_LOCAL,   # DIGITALIS v3 tmin mensuel (0.1 degC)
  digi_tmax = DIGI_TMAX_LOCAL,   # DIGITALIS v3 tmax mensuel (0.1 degC)
  gabarit   = GABARIT_1KM_DIR,   # gabarit grille 1 km L93 (reseau)
  out       = OUT_EOBS,          # sorties NetCDF annuelles (reseau)
  logs      = file.path(OUT_EOBS, "logs"),
  tmp_terra = file.path(OUT_EOBS, "tmp_terra")
)

# Surcharge SANDBOX (test bout-en-bout) : redirige sorties + crop si defini avant source().
SANDBOX_CROP <- if (exists("SANDBOX_CROP_EXT")) as.vector(terra::ext(SANDBOX_CROP_EXT)) else NULL
if (exists("SANDBOX_OUT")) {
  PATHS$out       <- file.path(SANDBOX_OUT, "DIGI_EOBS_BCSD")
  PATHS$logs      <- file.path(SANDBOX_OUT, "DIGI_EOBS_BCSD", "logs")
  PATHS$tmp_terra <- file.path(SANDBOX_OUT, "DIGI_EOBS_BCSD", "tmp_terra")
}

# ====== Variables ===========================================================================================================================================================================
VARIABLES <- list(
  list(
    prefixe      = "prec",
    fichier_eobs = "rr_ens_mean_0.1deg_reg_v31.0e.nc",
    var_nc       = "rr",
    dir_digi     = PATHS$digi_prec,
    pattern_digi = "prec_%d_%d.tif",   # prec_ANNEE_MOIS.tif
    scale_digi   = 0.1,                # DIGITALIS v4 en dixiemes de mm
    methode_bcsd = "multiplicatif",    # ratio DIGITALIS / stat_mensuelle
    unite        = "mm",
    longname     = "Daily precipitation BCSD bilinear 1km"
  ),
  list(
    prefixe      = "tmin",
    fichier_eobs = "tn_ens_mean_0.1deg_reg_v31.0e.nc",
    var_nc       = "tn",
    dir_digi     = PATHS$digi_tmin,
    pattern_digi = "tmin_%d_%d.tif",   # tmin_ANNEE_MOIS.tif
    scale_digi   = 0.1,                # DIGITALIS v3 en dixiemes de degC
    methode_bcsd = "additif",          # delta DIGITALIS - stat_mensuelle
    unite        = "degC",
    longname     = "Daily minimum temperature BCSD bilinear 1km"
  ),
  list(
    prefixe      = "tmax",
    fichier_eobs = "tx_ens_mean_0.1deg_reg_v31.0e.nc",
    var_nc       = "tx",
    dir_digi     = PATHS$digi_tmax,
    pattern_digi = "tmax_%d_%d.tif",   # tmax_ANNEE_MOIS.tif
    scale_digi   = 0.1,
    methode_bcsd = "additif",
    unite        = "degC",
    longname     = "Daily maximum temperature BCSD bilinear 1km"
  )
)


# ====== Creation des dossiers =======================================================================================================================================
for (d in c(PATHS$out, PATHS$logs, PATHS$tmp_terra))
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)

# ==================================================================================================================================================================================================================
# UTILITAIRE - rtime_block (main process uniquement)
# ==================================================================================================================================================================================================================

rtime_block <- function(nom, expr) {
  cat(sprintf("[%s] %s\n", format(Sys.time(), "%H:%M:%S"), nom))
  t0 <- proc.time()
  eval(substitute(expr), envir = parent.frame())
  dur <- (proc.time() - t0)["elapsed"]
  cat(sprintf("  -> %.1f s (%.1f min)\n", dur, dur/60))
  invisible(dur)
}

# ==================================================================================================================================================================================================================
# SECTION 1 - GABARIT SPATIAL
# ==================================================================================================================================================================================================================

cat("\n== Gabarit spatial ==\n")

if (!dir.exists(PATHS$gabarit))
  stop("Dossier gabarit introuvable : ", PATHS$gabarit)

f_gab <- sort(list.files(PATHS$gabarit, pattern="\\.tif$",
                         full.names=TRUE))[1]
if (length(f_gab)==0 || !file.exists(f_gab))
  stop("Aucun TIF dans : ", PATHS$gabarit)

GABARIT <- rast(f_gab)
cat(sprintf("  %s\n  CRS : %s\n  Resolution : %.0f m\n  Dimensions : %d x %d\n",
            basename(f_gab),
            crs(GABARIT, describe=TRUE)$name,
            res(GABARIT)[1],
            nrow(GABARIT), ncol(GABARIT)))

# ==================================================================================================================================================================================================================
# SECTION 2 - DETECTION CPU -> N_WORKERS
# ==================================================================================================================================================================================================================

# ==================================================================================================================================================================================================================
# SECTION 2 - DETECTION CPU ET MEMOIRE -> N_WORKERS
#
# Machine : 2x Xeon Gold 6254, 36 coeurs, 384 Go RAM
# Strategie :
#   - Chaque worker : 2 threads OMP -> 16 workers = 32 threads
#     (4 coeurs de marge pour le systeme et les autres utilisateurs)
#   - Memoire : ~270 Go libres au lancement -> 40 Go par worker max
#   - N_WORKERS adaptatif selon la charge CPU courante
# ==================================================================================================================================================================================================================

N_COEURS_TOTAL  <- parallel::detectCores(logical=FALSE)  # coeurs physiques
N_THREADS_WORKER <- 2L       # threads OMP par worker
N_COEURS_MARGE   <- 4L       # coeurs reserves pour le systeme

# Charge CPU via PowerShell (Windows) - fallback 30% si indisponible
cpu_actuel <- tryCatch({
  out <- system(
    paste0('powershell -Command "Get-Counter ',
           "'\\\\Processor(_Total)\\\\% Processor Time'",
           ' | Select-Object -ExpandProperty CounterSamples',
           ' | Select-Object -ExpandProperty CookedValue"'),
    intern=TRUE)
  val <- suppressWarnings(as.numeric(trimws(out[length(out)])))
  if (is.na(val) || length(val)==0) stop("NA")
  val
}, error=function(e) 30, warning=function(w) 30)
if (is.na(cpu_actuel) || length(cpu_actuel)==0) cpu_actuel <- 30

# Memoire disponible via PowerShell - fallback 270 Go si indisponible
ram_libre_go <- tryCatch({
  out <- system(
    paste0('powershell -Command ',
           '"(Get-CimInstance Win32_OperatingSystem)',
           '.FreePhysicalMemory / 1MB"'),
    intern=TRUE)
  val <- suppressWarnings(as.numeric(trimws(out[length(out)])))
  if (is.na(val)) stop("NA")
  round(val, 1)
}, error=function(e) 270)

# Calcul N_WORKERS :
#   coeurs utilisables = total - marge - coeurs deja charges
coeurs_libres   <- max(4L, N_COEURS_TOTAL - N_COEURS_MARGE -
                         as.integer(N_COEURS_TOTAL * cpu_actuel / 100))
N_WORKERS_MAX   <- coeurs_libres %/% N_THREADS_WORKER

# Travail I/O-bound (lecture reseau S:) -> on peut depasser le ratio CPU
# Le vrai plafond est la bande passante reseau, pas les coeurs
# On monte jusqu'a 28 workers (vs 16 avant)
memmax_worker   <- 40L
N_WORKERS_RAM   <- as.integer(floor(ram_libre_go * 0.80 / memmax_worker))
N_WORKERS       <- max(2L, min(N_WORKERS_MAX, N_WORKERS_RAM, 28L))

cat(sprintf("\n  Coeurs physiques  : %d\n", N_COEURS_TOTAL))
cat(sprintf("  CPU actuel        : %.0f%%\n", cpu_actuel))
cat(sprintf("  RAM libre         : %.0f Go\n", ram_libre_go))
cat(sprintf("  Workers retenus   : %d (max CPU=%d | max RAM=%d | plafond=16)\n",
            N_WORKERS, N_WORKERS_MAX, N_WORKERS_RAM))
cat(sprintf("  Threads par worker: %d\n", N_THREADS_WORKER))
cat(sprintf("  Threads totaux    : %d / %d coeurs\n",
            N_WORKERS * N_THREADS_WORKER, N_COEURS_TOTAL))
cat(sprintf("  RAM reservee      : ~%.0f Go / %.0f Go libres\n",
            N_WORKERS * memmax_worker, ram_libre_go))

# ==================================================================================================================================================================================================================
# SECTION 3 - FONCTION WORKER (executee dans chaque worker parallele)
#
# Traite une tache = (variable, annee)
# Produit : prefixe_EOBS_BCSD_bilinear_ANNEE.nc
#
# Securite ecriture :
#   - Ecriture dans un fichier .tmp.nc
#   - Renommage en .nc uniquement si writeCDF reussit
#   - Un crash mid-write laisse un .tmp.nc orphelin mais pas de .nc corrompu
#   - Au prochain lancement, file.exists(.nc) == FALSE -> recalcul propre
#   - Les .tmp.nc orphelins sont nettoyes en debut de session (Section 4)
# ==================================================================================================================================================================================================================

worker_bcsd_chunk <- function(var, annees_chunk, paths, f_gabarit,
                              compression, date_origine_str,
                              f_log, f_diag, crop_ext = NULL) {
  suppressPackageStartupMessages({
    library(terra); library(lubridate)
    library(sf); library(rnaturalearth); library(rnaturalearthdata)
  })
  terraOptions(threads=2, memmax=40, memfrac=0.20, progress=0,
               tempdir=paths$tmp_terra)
  Sys.setenv(OMP_NUM_THREADS="2", OPENBLAS_NUM_THREADS="2")
  
  date_origine <- as.Date(date_origine_str)
  
  log_msg <- function(msg) {
    ligne <- sprintf("[%s] %s\n", format(Sys.time(), "%H:%M:%S"), msg)
    cat(ligne, file=f_log,  append=TRUE)
    cat(ligne, file=f_diag, append=TRUE)
  }
  
  gabarit       <- rast(f_gabarit)
  if (!is.null(crop_ext)) {   # SANDBOX : restreint la grille de calcul a l'emprise test
    .cp     <- terra::project(terra::as.polygons(terra::ext(crop_ext), crs = "EPSG:4326"), terra::crs(gabarit))
    gabarit <- terra::crop(gabarit, .cp)
  }
  emprise_wgs84 <- project(ext(gabarit), from=crs(gabarit), to="EPSG:4326")
  emprise_wgs84 <- ext(emprise_wgs84$xmin-0.2, emprise_wgs84$xmax+0.2,
                       emprise_wgs84$ymin-0.2, emprise_wgs84$ymax+0.2)
  
  # Masque France metropolitaine - construit une seule fois par worker
  france_vect <- terra::vect(
    sf::st_crop(
      sf::st_transform(
        rnaturalearth::ne_countries(scale="medium", country="France",
                                    returnclass="sf"), 2154),
      sf::st_bbox(c(xmin=99000, ymin=6049000, xmax=1242000, ymax=7208000),
                  crs=sf::st_crs(2154))
    )
  )
  
  # ====== E-OBS charge UNE SEULE FOIS pour tout le chunk =========================================================
  r_all     <- rast(file.path(paths$eobs, var$fichier_eobs))
  dates_all <- date_origine + 0:(nlyr(r_all) - 1)
  log_msg(sprintf("LOAD %s : %d couches | chunk %d annees [%d-%d]",
                  var$prefixe, nlyr(r_all), length(annees_chunk),
                  min(annees_chunk), max(annees_chunk)))
  
  resultats <- vector("list", length(annees_chunk))
  
  for (k in seq_along(annees_chunk)) {
    annee <- annees_chunk[k]
    f_nc  <- file.path(paths$out,
                       sprintf("%s_EOBS_BCSD_bilinear_%d.nc",
                               var$prefixe, annee))
    f_tmp <- paste0(f_nc, ".tmp.nc")
    
    if (file.exists(f_nc)) {
      log_msg(sprintf("SKIP %s %d (%.1f Mo)", var$prefixe, annee,
                      file.size(f_nc)/1e6))
      resultats[[k]] <- list(ok=TRUE, skip=TRUE); next
    }
    if (file.exists(f_tmp)) file.remove(f_tmp)
    
    idx_annee   <- which(year(dates_all) == annee)
    dates_annee <- dates_all[idx_annee]
    
    if (length(idx_annee)==0) {
      log_msg(sprintf("ERREUR %s %d : aucune donnee E-OBS", var$prefixe, annee))
      resultats[[k]] <- list(ok=FALSE, skip=FALSE, err="no_data"); next
    }
    
    couches_annee <- vector("list", 12)
    
    for (mois in 1:12) {
      idx_mois <- which(month(dates_annee) == mois)
      if (length(idx_mois)==0) next
      r_mois_wgs <- crop(r_all[[idx_annee[idx_mois]]], emprise_wgs84)
      f_digi     <- file.path(var$dir_digi,
                              sprintf(var$pattern_digi, annee, mois))
      if (!file.exists(f_digi)) {
        r_out <- project(r_mois_wgs, gabarit, method="bilinear")
        if (var$var_nc=="rr") r_out <- clamp(r_out, lower=0, values=FALSE)
        log_msg(sprintf("WARNING %s %d/%02d : DIGITALIS absent -> bilinear pur",
                        var$prefixe, annee, mois))
      } else {
        digi_s   <- project(rast(f_digi) * var$scale_digi, gabarit,
                            method="bilinear")
        stat_m   <- if (var$methode_bcsd=="multiplicatif")
          app(r_mois_wgs, sum, na.rm=TRUE)
        else app(r_mois_wgs, mean, na.rm=TRUE)
        stat_1km <- project(stat_m, gabarit, method="bilinear")
        corr_m   <- if (var$methode_bcsd=="multiplicatif")
          clamp(digi_s/ifel(stat_1km<0.001,0.001,stat_1km),
                lower=0.001, upper=5)
        else digi_s - stat_1km
        r_1km <- project(r_mois_wgs, gabarit, method="bilinear")
        r_out  <- if (var$methode_bcsd=="multiplicatif")
          clamp(r_1km * corr_m, lower=0, values=FALSE)
        else r_1km + corr_m
      }
      time(r_out) <- dates_annee[idx_mois]
      couches_annee[[mois]] <- r_out
    }
    
    r_annee <- mask(do.call(c, Filter(Negate(is.null), couches_annee)),
                    france_vect)
    tryCatch({
      writeCDF(r_annee, f_tmp, varname=var$prefixe, unit=var$unite,
               longname=var$longname, compression=compression, overwrite=TRUE)
      file.rename(f_tmp, f_nc)
      log_msg(sprintf("OK %s %d : %d jours | %.1f Mo",
                      var$prefixe, annee, nlyr(r_annee),
                      file.size(f_nc)/1e6))
      resultats[[k]] <- list(ok=TRUE, skip=FALSE)
    }, error=function(e) {
      if (file.exists(f_tmp)) file.remove(f_tmp)
      log_msg(sprintf("ERREUR ecriture %s %d : %s",
                      var$prefixe, annee, conditionMessage(e)))
      resultats[[k]] <<- list(ok=FALSE, skip=FALSE, err=conditionMessage(e))
    })
    rm(r_annee, couches_annee); gc()
  }
  resultats
}

# ==================================================================================================================================================================================================================
# SECTION 4 - NETTOYAGE DES FICHIERS TEMPORAIRES ORPHELINS
# Produits par un crash lors d'une execution precedente
# ==================================================================================================================================================================================================================

tmp_orphelins <- list.files(PATHS$out, pattern="\\.tmp\\.nc$",
                            full.names=TRUE)
if (length(tmp_orphelins) > 0) {
  cat(sprintf("\n  Nettoyage de %d fichier(s) .tmp.nc orphelin(s)\n",
              length(tmp_orphelins)))
  file.remove(tmp_orphelins)
}

# ==================================================================================================================================================================================================================
# SECTION 5 - FICHIER DIAGNOSTIQUE
#
# Genere un fichier TXT dans le dossier de sortie contenant :
#   [1] Methodologie de production (parametres, sources, formules)
#   [2] Inventaire des fichiers attendus vs presents
#   [3] Journal de production (fallbacks, warnings, erreurs)
#       mis a jour en temps reel pendant la production (append)
# ==================================================================================================================================================================================================================

f_diag <- file.path(PATHS$out,
                    sprintf("DIAGNOSTIC_%s.txt",
                            format(Sys.time(), "%Y%m%d_%H%M%S")))

writeLines(paste0(
  "======================================================================
FICHIER DIAGNOSTIQUE - PRODUCTION DOWNSCALING BILINEAIRE (methode Delta)
E-OBS 0.1deg -> 1km - ", min(ANNEES_RUN), "-", max(ANNEES_RUN), "
Genere le : ", format(Sys.time(), "%d/%m/%Y a %H:%M:%S"), "
======================================================================

----------------------------------------------------------------------
1. METHODOLOGIE
----------------------------------------------------------------------

Methode : Delta (facteur de correction mensuel : ratio precip / delta temp)
          avec interpolation spatiale bilineaire

Etapes de traitement (par variable, par mois, par annee) :

  [A] STAT MENSUELLE E-OBS
      Precipitation  : somme mensuelle des jours du mois (mm)
      Tmin / Tmax    : moyenne mensuelle des jours du mois (degC)
      Domaine        : France metropolitaine + marge 0.2 deg
      CRS source     : WGS84 (EPSG:4326), resolution 0.1 deg (~11 km)

  [B] INTERPOLATION SPATIALE BILINEAIRE
      Reprojection stat mensuelle E-OBS -> grille 1km L93
      Methode        : bilineaire (terra::project)
      CRS cible      : Lambert 93 (EPSG:2154)
      Resolution     : 1 km (gabarit DIGITALIS_daily_DS_CHELSA)
      Avantage vs IDW : meilleure preservation des extremes
                        (voir comparaison Bilinear_IDW_Janv1981)

  [C] FACTEUR DE CORRECTION DIGITALIS (mensuel, 1 km)
      Reprojection   : project(digi, gabarit, method='bilinear')
                       gere EPSG:27572 (v3) et tout autre CRS (v4)
      Precipitation  : ratio  = DIGITALIS_mensuel / max(eobs_1km, 0.001)
                       clamp  : [0.001 ; 5.0]
      Tmin / Tmax    : delta  = DIGITALIS_mensuel - eobs_1km (additif)

  [D] APPLICATION JOURNALIERE
      Pour chaque jour j du mois m :
        Precipitation  : jour_j_corr = bilinear(jour_j) * ratio_m
                         clamp(lower = 0)
        Tmin / Tmax    : jour_j_corr = bilinear(jour_j) + delta_m
      Interpolation bilineaire appliquee a chaque jour individuellement

  [E] ECRITURE ATOMIQUE NetCDF
      Ecriture dans fichier .tmp.nc
      Renommage en .nc uniquement si writeCDF() reussit
      Un crash mid-write ne produit pas de fichier .nc corrompu
      Compression : niveau ", COMPRESSION, "

  [F] FALLBACK (si DIGITALIS absent pour un mois)
      Interpolation bilineaire pure sans correction DIGITALIS
      Signale par WARNING dans ce fichier diagnostique

----------------------------------------------------------------------
2. SOURCES DE DONNEES
----------------------------------------------------------------------

  E-OBS v31.0e
    Resolution  : 0.1 deg (~11 km)
    CRS         : WGS84 (EPSG:4326)
    Periode     : 1950-2024
    Variables   : rr (precipitation), tn (tmin), tx (tmax)
    Chemin      : ", PATHS$eobs, "

  DIGITALIS v4 - Precipitation
    Resolution  : 1 km
    CRS         : Lambert 93 (EPSG:2154)
    Periode     : 1960-2025
    Unite brute : dixiemes de mm  ->  x0.1  ->  mm
    Chemin      : ", PATHS$digi_prec, "

  DIGITALIS v3 - Tmin
    Resolution  : 1 km
    CRS         : Lambert II etendu (EPSG:27572)
    Periode     : 1961-2024
    Unite brute : dixiemes de degC  ->  x0.1  ->  degC
    Chemin      : ", PATHS$digi_tmin, "

  DIGITALIS v3 - Tmax
    Resolution  : 1 km
    CRS         : Lambert II etendu (EPSG:27572)
    Periode     : 1961-2024
    Unite brute : dixiemes de degC  ->  x0.1  ->  degC
    Chemin      : ", PATHS$digi_tmax, "

  Gabarit spatial
    Fichier     : ", basename(f_gab), "
    CRS         : ", crs(GABARIT, describe=TRUE)$name, "
    Resolution  : ", res(GABARIT)[1], " m
    Dimensions  : ", nrow(GABARIT), " lignes x ", ncol(GABARIT), " colonnes
    Chemin      : ", PATHS$gabarit, "

----------------------------------------------------------------------
3. PARAMETRES DE PRODUCTION
----------------------------------------------------------------------

  Periode de production   : ", min(ANNEES_RUN), "-", max(ANNEES_RUN),
  " (", length(ANNEES_RUN), " ans)
  Periode de reference ECE: ", min(ANNEES_REF), "-", max(ANNEES_REF), "
  Variables               : ", length(VARIABLES), " (prec, tmin, tmax)
  Taches totales          : ", length(ANNEES_RUN) * length(VARIABLES), "
  Workers paralleles      : ", N_WORKERS, " (", N_WORKERS*N_THREADS_WORKER, " threads / ", N_COEURS_TOTAL, " coeurs)
  RAM libre au lancement  : ", ram_libre_go, " Go | RAM/worker : ", memmax_worker, " Go
  Compression NetCDF      : niveau ", COMPRESSION, "
  Dossier de sortie       : ", PATHS$out, "
  Date de lancement       : ", format(Sys.time(), "%d/%m/%Y %H:%M:%S"), "

----------------------------------------------------------------------
4. INVENTAIRE DES FICHIERS (attendus vs presents au lancement)
----------------------------------------------------------------------
"), f_diag)

# Inventaire fichier par fichier
cat(sprintf("%-6s | %-4s | %-45s | %s\n",
            "VAR", "AN", "FICHIER", "PRESENT"),
    file=f_diag, append=TRUE)
cat(strrep("-", 72), "\n", file=f_diag, append=TRUE)

for (vi in seq_along(VARIABLES)) {
  var <- VARIABLES[[vi]]
  for (an in ANNEES_RUN) {
    f_nc <- file.path(PATHS$out,
                      sprintf("%s_EOBS_BCSD_bilinear_%d.nc",
                              var$prefixe, an))
    statut <- if (file.exists(f_nc))
      sprintf("OUI (%.1f Mo)", file.size(f_nc)/1e6)
    else
      "NON - a produire"
    cat(sprintf("%-6s | %4d | %-45s | %s\n",
                var$prefixe, an, basename(f_nc), statut),
        file=f_diag, append=TRUE)
  }
}

cat(paste0(
  "\n----------------------------------------------------------------------\n",
  "5. JOURNAL DE PRODUCTION\n",
  "   (les lignes suivantes sont ajoutees en temps reel pendant le calcul)\n",
  "   OK      = fichier produit avec succes\n",
  "   SKIP    = fichier deja present, non recalcule\n",
  "   WARNING = DIGITALIS absent -> fallback bilinear pur pour ce mois\n",
  "   ERREUR  = echec du calcul ou de l'ecriture\n",
  "----------------------------------------------------------------------\n\n"),
  file=f_diag, append=TRUE)

cat(sprintf("  Fichier diagnostique : %s\n", basename(f_diag)))

# ==================================================================================================================================================================================================================
# SECTION 6 - INVENTAIRE DES TACHES
# ==================================================================================================================================================================================================================

cat("\n== Inventaire des taches ==\n")

taches <- expand.grid(var_idx = seq_along(VARIABLES),
                      annee   = ANNEES_RUN,
                      stringsAsFactors=FALSE)

# Identifier les taches deja faites (fichiers .nc existants)
taches$done <- mapply(function(vi, an) {
  f <- file.path(PATHS$out,
                 sprintf("%s_EOBS_BCSD_bilinear_%d.nc",
                         VARIABLES[[vi]]$prefixe, an))
  file.exists(f)
}, taches$var_idx, taches$annee)

n_total <- nrow(taches)
n_done  <- sum(taches$done)
n_reste <- n_total - n_done

cat(sprintf("  Total    : %d taches (%d annees x %d variables)\n",
            n_total, length(ANNEES_RUN), length(VARIABLES)))
cat(sprintf("  Deja OK  : %d\n", n_done))
cat(sprintf("  A faire  : %d\n", n_reste))

if (n_reste == 0) {
  cat("\n  Toutes les taches sont deja produites. Fin du script.\n")
  quit(save="no", status=0)
}

# Filtrer les taches restantes
taches_run <- taches[!taches$done, ]
cat(sprintf("\n  Workers  : %d\n", N_WORKERS))
cat(sprintf("  Taches/worker (aprox.) : %.1f\n", n_reste / N_WORKERS))

# ==================================================================================================================================================================================================================
# SECTION 6 - LANCEMENT PARALLELE
# ==================================================================================================================================================================================================================

cat("\n== Lancement downscaling bilineaire (methode Delta) ======\n")

# Fichier log global
f_log_global <- file.path(PATHS$logs,
                          sprintf("bcsd_bilinear_%s.log",
                                  format(Sys.time(), "%Y%m%d_%H%M%S")))
cat(sprintf("  Log : %s\n\n", basename(f_log_global)))

# ====== Fonction d'affichage de la progression ====================================================================================
afficher_progression <- function(n_fait, n_total, n_ok, n_skip, n_err,
                                 t_debut) {
  pct     <- 100 * n_fait / n_total
  elapsed <- as.numeric(proc.time()["elapsed"] - t_debut)
  eta     <- if (n_fait > 0)
    as.integer(elapsed / n_fait * (n_total - n_fait))
  else NA_integer_
  
  barre_len  <- 30
  n_plein    <- as.integer(barre_len * n_fait / n_total)
  barre      <- paste0(strrep("=", n_plein),
                       if (n_plein < barre_len) ">" else "",
                       strrep(" ", max(0, barre_len - n_plein - 1)))
  
  eta_str <- if (!is.na(eta)) {
    sprintf("%02d:%02d:%02d", eta %/% 3600, (eta %% 3600) %/% 60, eta %% 60)
  } else "--:--:--"
  
  cat(sprintf("\r  [%s] %3.0f%% | %d/%d | OK:%d SKIP:%d ERR:%d | ETA:%s   ",
              barre, pct, n_fait, n_total,
              n_ok, n_skip, n_err, eta_str))
  if (n_fait == n_total) cat("\n")
}

# ====== Traitement par lots - 1 lot = N_WORKERS taches ============================================================
# Avantage : la progression s'affiche apres chaque lot
# Les workers restent ouverts pendant toute la production (pas de
# makeCluster/stopCluster a chaque lot)

t_debut_prod <- proc.time()["elapsed"]

n_ok_cpt <- 0L; n_skip_cpt <- 0L; n_err_cpt <- 0L; n_fait <- 0L

cat(sprintf("  %d annees | %d variables | %d workers\n",
            length(ANNEES_RUN), length(VARIABLES), N_WORKERS))
cat(sprintf("  Strategie : E-OBS charge 1x par worker (chunk d'annees)\n"))
cat(sprintf("  Debut : %s\n\n", format(Sys.time(), "%H:%M:%S")))

# Affichage initial
n_total_annees <- length(ANNEES_RUN) * length(VARIABLES)
afficher_progression(0L, n_total_annees, 0L, 0L, 0L, t_debut_prod)

cl <- makeCluster(N_WORKERS, type="PSOCK")
clusterExport(cl,
              c("VARIABLES", "PATHS", "f_gab", "COMPRESSION",
                "DATE_ORIGINE", "worker_bcsd_chunk",
                "f_log_global", "f_diag", "SANDBOX_CROP"),
              envir=environment())
clusterEvalQ(cl, {
  Sys.setenv(OMP_NUM_THREADS="2", OPENBLAS_NUM_THREADS="2")
})

if (.Platform$OS.type == "windows") {
  tryCatch(system(paste0(
    'powershell -Command "Get-Process Rscript,Rgui',
    ' -ErrorAction SilentlyContinue | ForEach-Object {',
    ' $_.PriorityClass =',
    ' [System.Diagnostics.ProcessPriorityClass]::BelowNormal}"'),
    ignore.stdout=TRUE, ignore.stderr=TRUE), error=function(e) NULL)
}

resultats    <- list()
n_ok_cpt     <- 0L; n_skip_cpt <- 0L; n_err_cpt <- 0L; n_fait <- 0L

for (var in VARIABLES) {
  
  # Annees restantes pour cette variable
  annees_var <- ANNEES_RUN[!sapply(ANNEES_RUN, function(an) {
    file.exists(file.path(PATHS$out,
                          sprintf("%s_EOBS_BCSD_bilinear_%d.nc",
                                  var$prefixe, an)))
  })]
  
  n_skip_var <- length(ANNEES_RUN) - length(annees_var)
  n_skip_cpt <- n_skip_cpt + n_skip_var
  n_fait     <- n_fait + n_skip_var
  
  if (length(annees_var) == 0) {
    cat(sprintf("\n  %s : toutes les annees deja presentes (skip)\n",
                var$prefixe))
    afficher_progression(n_fait, n_total_annees,
                         n_ok_cpt, n_skip_cpt, n_err_cpt, t_debut_prod)
    next
  }
  
  # Decoupage en chunks - methode robuste quel que soit le nombre d'annees
  n_chunks  <- max(1L, min(N_WORKERS, length(annees_var)))
  chunk_ids <- ((seq_along(annees_var) - 1L) %% n_chunks) + 1L
  chunks    <- split(annees_var, chunk_ids)
  
  cat(sprintf("\n  %s : %d annees -> %d chunks\n",
              var$prefixe, length(annees_var), length(chunks)))
  
  # Construction de la liste de taches : chaque element = (var, chunk)
  taches_var <- lapply(chunks, function(ch) list(var=var, annees=ch))
  
  res_var <- parLapply(cl, taches_var, function(tache) {
    v          <- tache$var
    annees_ch  <- tache$annees
    f_log <- file.path(PATHS$logs,
                       sprintf("%s_%d_%d.txt", v$prefixe,
                               min(annees_ch), max(annees_ch)))
    tryCatch(
      worker_bcsd_chunk(v, annees_ch, PATHS, f_gab,
                        COMPRESSION, as.character(DATE_ORIGINE),
                        f_log, f_diag, crop_ext = SANDBOX_CROP),
      error=function(e) {
        msg <- sprintf("[%s] ERREUR chunk %s %d-%d : %s\n",
                       format(Sys.time(), "%H:%M:%S"),
                       v$prefixe, min(annees_ch),
                       max(annees_ch), conditionMessage(e))
        cat(msg, file=f_log_global, append=TRUE)
        cat(msg, file=f_diag,       append=TRUE)
        lapply(annees_ch, function(an)
          list(ok=FALSE, skip=FALSE, err=conditionMessage(e)))
      }
    )
  })
  
  # Aplatir : chaque chunk retourne une liste de resultats par annee
  res_flat <- unlist(res_var, recursive=FALSE)
  resultats <- c(resultats, res_flat)
  
  n_ok_cpt   <- n_ok_cpt   + sum(sapply(res_flat, function(r) isTRUE(r$ok) && !isTRUE(r$skip)))
  n_err_cpt  <- n_err_cpt  + sum(sapply(res_flat, function(r) !isTRUE(r$ok)))
  n_fait     <- n_fait + length(annees_var)
  
  afficher_progression(n_fait, n_total_annees,
                       n_ok_cpt, n_skip_cpt, n_err_cpt, t_debut_prod)
}

stopCluster(cl)

dur_prod <- as.numeric(proc.time()["elapsed"] - t_debut_prod)
cat(sprintf("\n  Duree totale : %.0f min (%.1f h)\n",
            dur_prod / 60, dur_prod / 3600))

# ==================================================================================================================================================================================================================
# SECTION 7 - BILAN
# ==================================================================================================================================================================================================================

n_ok   <- n_ok_cpt
n_skip <- n_skip_cpt
n_err  <- n_err_cpt

# Inventaire final des fichiers produits
fichiers_nc      <- list.files(PATHS$out, pattern="\\.nc$", full.names=TRUE)
taille_totale_go <- sum(file.size(fichiers_nc)) / 1e9

# ====== Bilan console ===============================================================================================================================================================
if (n_err > 0) {
  cat("\n  ERREURS :\n")
  for (i in seq_along(resultats)) {
    r <- resultats[[i]]
    if (!isTRUE(r$ok))
      cat(sprintf("    tache %d : %s\n", i,
                  if (!is.null(r$err)) r$err else "inconnue"))
  }
}

cat("\n======================================================\n")
cat("  PRODUCTION TERMINEE\n")
cat(sprintf("  Periode     : %d-%d (%d ans)\n",
            min(ANNEES_RUN), max(ANNEES_RUN), length(ANNEES_RUN)))
cat(sprintf("  Produits    : %d | Deja OK : %d | Erreurs : %d\n",
            n_ok, n_skip + n_done, n_err))
cat(sprintf("  Total NC    : %d fichiers | %.2f Go\n",
            length(fichiers_nc), taille_totale_go))
cat(sprintf("  Diagnostique: %s\n", basename(f_diag)))
cat("======================================================\n")

# ====== Bilan dans le fichier diagnostique ================================================================================================
bilan_diag <- paste0(
  "\n----------------------------------------------------------------------\n",
  "6. BILAN DE PRODUCTION\n",
  "----------------------------------------------------------------------\n\n",
  sprintf("  Date de fin         : %s\n", format(Sys.time(), "%d/%m/%Y %H:%M:%S")),
  sprintf("  Fichiers produits   : %d\n", n_ok),
  sprintf("  Fichiers deja OK    : %d (non recalcules)\n", n_skip + n_done),
  sprintf("  Erreurs             : %d\n", n_err),
  sprintf("  Total fichiers NC   : %d\n", length(fichiers_nc)),
  sprintf("  Taille totale       : %.2f Go\n", taille_totale_go),
  "\n  Detail par variable :\n"
)
cat(bilan_diag, file=f_diag, append=TRUE)

for (var in VARIABLES) {
  nc_var <- list.files(PATHS$out,
                       pattern=sprintf("%s_EOBS_BCSD_bilinear_.*\\.nc$",
                                       var$prefixe),
                       full.names=TRUE)
  cat(sprintf("    %-6s : %d fichiers | %.2f Go\n",
              var$prefixe, length(nc_var),
              sum(file.size(nc_var))/1e9),
      file=f_diag, append=TRUE)
}

if (n_err > 0) {
  cat("\n  Taches en erreur :\n", file=f_diag, append=TRUE)
  for (i in seq_along(resultats)) {
    r <- resultats[[i]]
    if (!isTRUE(r$ok)) {
      var   <- VARIABLES[[taches_run$var_idx[i]]]
      annee <- taches_run$annee[i]
      cat(sprintf("    %s %d : %s\n",
                  var$prefixe, annee,
                  if (!is.null(r$err)) r$err else "inconnue"),
          file=f_diag, append=TRUE)
    }
  }
}

cat(sprintf("\n  Fichier diagnostique complet : %s\n", f_diag),
    file=f_diag, append=TRUE)