# ======================================================================
# Downscaling temporel CHELSA -> DIGITALIS daily (1979-2024)
# 3 variables : pr / tasmin / tasmax
#
# Methode precipitation (Delta multiplicatif) :
#   ratio_m  = DIGITALIS_mensuel / CHELSA_mensuel_sum   [clamp 0.001-5]
#   prec_j   = CHELSA_j_1km * ratio_m
#   => somme mensuelle conservee, jours secs preserves
#
# Methode temperature (delta additif) :
#   delta_m  = DIGITALIS_mensuel_moyen - CHELSA_mensuel_moyen (degC)
#   temp_j   = CHELSA_j_1km + delta_m
#   => la moyenne mensuelle est calee sur DIGITALIS
#
# Unites :
#   CHELSA pr      : mm/jour (kg/m2/day)
#   CHELSA tasmin/tasmax : Kelvin -> converti en degC (-273.15)
#   DIGITALIS prec : encode *10 (0.1 mm) -> divise par 10
#   DIGITALIS tmin/tmax : encode *10 (0.1 degC) -> divise par 10
#
# Entrees :
#   CHELSA pr      : 3-Donnees/0-Brut/2-CHELSA/2-1960_2026_CHELSA_FR/pr/
#   CHELSA tasmin  : 3-Donnees/0-Brut/2-CHELSA/2-1960_2026_CHELSA_FR/tasmin/
#   CHELSA tasmax  : 3-Donnees/0-Brut/2-CHELSA/2-1960_2026_CHELSA_FR/tasmax/
#   DIGITALIS prec : 3-Donnees/5-DIGITALIS/2-1960_2025_DIGITALIS_v4/prec/
#   DIGITALIS tmin : DIGI_TMIN (cf config_chemins.R)
#   DIGITALIS tmax : DIGI_TMAX (cf config_chemins.R)
#
# Sorties :
#   3-Donnees/5-DIGITALIS/3-DIGITALIS_daily_DS_CHELSA/YYYY/   (lu par 8d-Conversion_DIGI_CHEL.R)
#     prec_DS_YYYYMMDD.tif   (mm/jour)
#     tmin_DS_YYYYMMDD.tif   (degC)
#     tmax_DS_YYYYMMDD.tif   (degC)
# ======================================================================

if (!requireNamespace("terra", quietly = TRUE)) install.packages("terra")

# Forcer PROJ   utiliser sa propre base ( vite le conflit OSGeo4W)
Sys.setenv(PROJ_LIB = system.file("proj", package = "terra"))

library(terra)
CRS_L93 <- "+proj=lcc +lat_0=46.5 +lon_0=3 +lat_1=49 +lat_2=44 +x_0=700000 +y_0=6600000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs"

# Chemins du pipeline : editer config_chemins.R (racine des donnees via DIGI_ROOT).
# Lancer depuis le dossier r/ du depot (ou avoir config_chemins.R dans le working dir).
if (!exists("DIGI_PREC")) source("config_chemins.R")

# --- Parametres -------------------------------------------------------
PATH_CHELSA_PR     <- CHELSA_PR
PATH_CHELSA_TASMIN <- CHELSA_TASMIN
PATH_CHELSA_TASMAX <- CHELSA_TASMAX

PATH_DIGI_PREC <- DIGI_PREC
PATH_DIGI_TMIN <- DIGI_TMIN
PATH_DIGI_TMAX <- DIGI_TMAX

# PATCH 2026-06-09 (bug A) : ecrivait dans le generique "3-DIGITALIS_daily/" alors que
# la conversion 8d-Conversion_DIGI_CHEL.R LIT "3-DIGITALIS_daily_DS_CHELSA/" (convention
# par base, cf 8d-DIGI_SAF -> "4-DIGITALIS_daily_DS_SAFRAN_IDW"). La chaine downscale->8d
# etait donc DECONNECTEE. Aligne sur le dossier attendu par 8d (et rempli par la prod).
PATH_OUT <- if (exists("SANDBOX_OUT")) file.path(SANDBOX_OUT, "DIGI_CHEL_daily") else OUT_CHELSA

ANNEE_DEBUT      <- 1979
ANNEE_FIN        <- 2024
# Surcharge SANDBOX (test bout-en-bout) : restreint la periode si defini avant source().
if (exists("SANDBOX_ANNEES")) { ANNEE_DEBUT <- min(SANDBOX_ANNEES); ANNEE_FIN <- max(SANDBOX_ANNEES) }
ANNEE_BASCULE_PR <- 2021   # bascule pr/ -> prec/ dans les noms CHELSA

RATIO_MIN <- 0.001
RATIO_MAX <- 5

# --- Table des variables ----------------------------------------------
# Pour chaque variable : chemins, prefixes, methode, facteur DIGITALIS
variables <- list(
  pr = list(
    chelsa_path   = PATH_CHELSA_PR,
    chelsa_prefix = NA,              # gere via vdir (pr/prec selon annee)
    digi_path     = PATH_DIGI_PREC,
    digi_prefix   = "prec",
    out_prefix    = "prec_DS",
    methode       = "multiplicatif", # ratio Delta
    digi_factor   = 1/10,            # 0.1mm -> mm
    chelsa_offset = 0                # pas de conversion
  ),
  tasmin = list(
    chelsa_path   = PATH_CHELSA_TASMIN,
    chelsa_prefix = "tasmin",
    digi_path     = PATH_DIGI_TMIN,
    digi_prefix   = "tmin",
    out_prefix    = "tmin_DS",
    methode       = "additif",       # delta mensuel
    digi_factor   = 1/10,            # 0.1degC -> degC
    chelsa_offset = -273.15          # Kelvin -> degC
  ),
  tasmax = list(
    chelsa_path   = PATH_CHELSA_TASMAX,
    chelsa_prefix = "tasmax",
    digi_path     = PATH_DIGI_TMAX,
    digi_prefix   = "tmax",
    out_prefix    = "tmax_DS",
    methode       = "additif",
    digi_factor   = 1/10,
    chelsa_offset = -273.15
  )
)
Sys.getenv("PROJ_LIB")   # doit pointer vers le dossier de terra, pas OSGeo4W
# --- Template DIGITALIS (grille L93 1km de reference) -----------------
cat("Chargement template DIGITALIS...\n")
template <- rast(file.path(PATH_DIGI_PREC, "prec_1979_1.tif"))
crs(template) <- CRS_L93   # pas de lookup proj.db ? pas d'erreur
# Surcharge SANDBOX : restreint la grille de calcul a l'emprise test (WGS84 -> L93).
if (exists("SANDBOX_CROP_EXT"))
  template <- crop(template, project(as.polygons(ext(SANDBOX_CROP_EXT), crs = "EPSG:4326"), crs(template)))
cat(sprintf("  CRS    : %s\n", crs(template, describe = TRUE)[["code"]]))
cat(sprintf("  Res    : %.0f m\n", res(template)[1]))
cat(sprintf("  Extent : %.0f %.0f %.0f %.0f\n\n",
            ext(template)[1], ext(template)[2],
            ext(template)[3], ext(template)[4]))


# ======================================================================
# CHECK GLOBAL : bilan des sorties deja calculees (avant de demarrer)
# ======================================================================
cat("=== Bilan des sorties existantes ===\n\n")
cat(sprintf("  %-6s  %-8s  %-8s  %-8s  %s\n",
            "Annee", "prec_DS", "tmin_DS", "tmax_DS", "Statut"))
cat(strrep("-", 55), "\n")

annees_a_faire <- c()  # annees avec au moins un fichier manquant

for (annee_chk in ANNEE_DEBUT:ANNEE_FIN) {
  dates_chk <- seq(as.Date(sprintf("%d-01-01", annee_chk)),
                   as.Date(sprintf("%d-12-31", annee_chk)), by = "day")
  n_j_chk   <- length(dates_chk)
  dir_chk   <- file.path(PATH_OUT, annee_chk)
  
  statuts <- sapply(names(variables), function(vn) {
    v_chk <- variables[[vn]]
    f_chk <- file.path(dir_chk,
                       paste0(v_chk$out_prefix, "_",
                              format(dates_chk, "%Y%m%d"), ".tif"))
    sum(file.exists(f_chk) & file.size(f_chk) > 1000)
  })
  
  complet <- all(statuts == n_j_chk)
  if (!complet) annees_a_faire <- c(annees_a_faire, annee_chk)
  
  cat(sprintf("  %-6d  %3d/%-3d  %3d/%-3d  %3d/%-3d  %s\n",
              annee_chk,
              statuts["pr"],     n_j_chk,
              statuts["tasmin"], n_j_chk,
              statuts["tasmax"], n_j_chk,
              if (complet) "[COMPLET]" else ""))
}

cat(strrep("-", 55), "\n")
if (length(annees_a_faire) == 0) {
  cat("\n  -> TOUT EST DEJA CALCULE. Rien a faire.\n\n")
  message("=== Downscaling complet pour toutes les annees ===")
  stop("Downscaling deja complet (arret normal).")
} else {
  cat(sprintf("\n  -> %d annee(s) a traiter : %s\n\n",
              length(annees_a_faire),
              paste(annees_a_faire, collapse = ", ")))
}

# --- Compteurs globaux ------------------------------------------------
n_ok_total <- 0; n_miss_total <- 0; n_skip_total <- 0
t_start_global <- proc.time()

# ======================================================================
# Boucle annee / variable / mois
# ======================================================================
for (annee in ANNEE_DEBUT:ANNEE_FIN) {
  
  dir_out_annee <- file.path(PATH_OUT, annee)
  dir.create(dir_out_annee, recursive = TRUE, showWarnings = FALSE)
  
  # --- Skip annee entierement calculee ---------------------------------
  dates_annee_cur <- seq(as.Date(sprintf("%d-01-01", annee)),
                         as.Date(sprintf("%d-12-31", annee)), by = "day")
  annee_complete  <- all(sapply(names(variables), function(vn) {
    v_cur <- variables[[vn]]
    f_cur <- file.path(dir_out_annee,
                       paste0(v_cur$out_prefix, "_",
                              format(dates_annee_cur, "%Y%m%d"), ".tif"))
    all(file.exists(f_cur) & file.size(f_cur) > 1000)
  }))
  
  if (annee_complete) {
    cat(sprintf("\n======= %d ======= [COMPLET - ignore]\n", annee))
    next
  }
  
  cat(sprintf("\n======= %d =======\n", annee))
  n_ok_annee <- 0; n_miss_annee <- 0; n_skip_annee <- 0
  
  for (var_name in names(variables)) {
    v <- variables[[var_name]]
    
    cat(sprintf("  [%s]\n", var_name))
    
    for (mois in 1:12) {
      
      cat(sprintf("    Mois %02d ... ", mois))
      
      # Dernier jour du mois
      dates_mois <- seq(
        as.Date(sprintf("%d-%02d-01", annee, mois)),
        {
          if (mois < 12) as.Date(sprintf("%d-%02d-01", annee, mois + 1)) - 1
          else           as.Date(sprintf("%d-12-31", annee))
        },
        by = "day"
      )
      n_jours_total <- length(dates_mois)
      
      # Verifier si tous les fichiers de sortie existent deja
      f_outs <- file.path(dir_out_annee,
                          paste0(v$out_prefix, "_",
                                 format(dates_mois, "%Y%m%d"), ".tif"))
      deja_ok <- file.exists(f_outs) & (file.size(f_outs) > 1000)
      
      if (all(deja_ok)) {
        cat(sprintf("skip (%d jours)\n", n_jours_total))
        n_skip_annee <- n_skip_annee + n_jours_total
        next
      }
      
      # --- DIGITALIS mensuel ------------------------------------------
      f_digi <- file.path(v$digi_path,
                          sprintf("%s_%d_%d.tif", v$digi_prefix, annee, mois))
      if (!file.exists(f_digi)) {
        cat("DIGITALIS absent -> passe\n")
        n_miss_annee <- n_miss_annee + n_jours_total
        next
      }
      digi_m <- rast(f_digi) * v$digi_factor
      # DIGITALIS v3 et v4 ont un CRS "engineering" non reconnu par PROJ.
      # On force le CRS L93 directement (pas de transformation de coordonnees :
      # les donnees SONT deja en L93, juste le label CRS est incorrect).
      crs(digi_m) <- CRS_L93
      
      # Aligner sur la grille template si extents differents
      # (pas besoin de project() : meme CRS maintenant)
      if (!compareGeom(digi_m, template, stopOnError = FALSE))
        digi_m <- resample(digi_m, template, method = "bilinear")
      
      # --- Fichiers CHELSA du mois ------------------------------------
      if (var_name == "pr") {
        vdir <- if (annee < ANNEE_BASCULE_PR) "pr" else "prec"
        fnames_chelsa <- sprintf("CHELSA_%s_%s_%s_%d_V.2.1.tif",
                                 vdir,
                                 format(dates_mois, "%d"),
                                 format(dates_mois, "%m"),
                                 annee)
      } else {
        fnames_chelsa <- sprintf("CHELSA_%s_%s_%s_%d_V.2.1.tif",
                                 v$chelsa_prefix,
                                 format(dates_mois, "%d"),
                                 format(dates_mois, "%m"),
                                 annee)
      }
      
      paths_chelsa <- file.path(v$chelsa_path, fnames_chelsa)
      exist_chelsa <- file.exists(paths_chelsa) & (file.size(paths_chelsa) > 50000)
      n_jours_dispo <- sum(exist_chelsa)
      
      if (n_jours_dispo == 0) {
        cat("aucun CHELSA -> passe\n")
        n_miss_annee <- n_miss_annee + n_jours_total
        next
      }
      if (n_jours_dispo < n_jours_total)
        cat(sprintf("[%d/%d jours] ", n_jours_dispo, n_jours_total))
      
      # --- Reprojection CHELSA -> L93 1km -----------------------------
      chelsa_l93 <- vector("list", n_jours_total)
      for (j in seq_len(n_jours_total)) {
        if (!exist_chelsa[j]) {
          cat(sprintf("  [SKIP] CHELSA absent : %s\n", fnames_chelsa[j]))
          chelsa_l93[[j]] <- NA
          next
        }
        r_raw <- rast(paths_chelsa[j])
        # --- Masquage aberrants CHELSA v2.1 (MEME critere que 8c-CHELSA_vers_NetCDF.R,
        # cf journal SS5.21) : jour fill 0 K (>10% pixels) ou overflow int16 (>1000 K)
        # -> traite comme jour MANQUANT (sortie NA + EXCLU de la correction mensuelle).
        # Indispensable ICI car le downscaling lit le TIF BRUT (pas la sortie 8c) et la
        # correction delta AMPLIFIE l'aberrant (+125 C, SS5.14). On l'EXCLUT (et non un
        # simple NA) car Reduce("+") n'est pas na.rm -> un jour NA casserait tout le mois.
        # Temperature uniquement (offset != 0 ; 0/1000 K hors-sens pour prec). Idempotent.
        if (v$chelsa_offset != 0) {
          .vv <- values(r_raw, mat = FALSE)
          .ab <- sum(is.finite(.vv)) > 0 && (
                   mean(.vv == 0,   na.rm = TRUE) > 0.10 ||
                   max(.vv,         na.rm = TRUE) > 1000 ||
                   mean(.vv > 1000, na.rm = TRUE) > 0.001)
          if (isTRUE(.ab)) {
            cat(sprintf("  [ABERRANT->manquant CHELSA %s]\n", fnames_chelsa[j]))
            exist_chelsa[j] <- FALSE; chelsa_l93[[j]] <- NA; next
          }
        }
        r <- r_raw + v$chelsa_offset   # Kelvin->degC ou noop
        # Separation en 2 etapes : projet CRS d'abord, resample ensuite
        # project(r, template) en 1 passe peut lever "cannot do this transformation"
        r_proj          <- project(r, crs(template), method = "bilinear")
        chelsa_l93[[j]] <- resample(r_proj, template,  method = "bilinear")
        rm(r_proj)
      }
      # Recompter apres exclusion d'eventuels jours aberrants (masquage ci-dessus) :
      # la correction mensuelle (delta / ratio) doit ignorer ces jours.
      n_jours_dispo <- sum(exist_chelsa)
      if (n_jours_dispo == 0) { cat(" [tous CHELSA aberrants/absents -> mois NA]\n"); next }
      
      # --- Correction mensuelle ---------------------------------------
      chelsa_dispo <- chelsa_l93[exist_chelsa]
      
      if (v$methode == "multiplicatif") {
        # Delta multiplicatif : ratio DIGITALIS/CHELSA sur la somme mensuelle
        chelsa_sum_m <- Reduce("+", chelsa_dispo)
        chelsa_sum_m <- clamp(chelsa_sum_m, lower = 0, values = FALSE)
        denom   <- ifel(chelsa_sum_m < RATIO_MIN, RATIO_MIN, chelsa_sum_m)
        corr_m  <- clamp(digi_m / denom, lower = RATIO_MIN, upper = RATIO_MAX)
        
      } else {
        # Additif : delta = DIGITALIS_moyen - CHELSA_moyen
        chelsa_mean_m <- Reduce("+", chelsa_dispo) / n_jours_dispo
        corr_m <- digi_m - chelsa_mean_m
      }
      
      # --- Application jour par jour ----------------------------------
      n_ok_mois <- 0; n_skip_mois <- 0
      
      for (j in seq_len(n_jours_total)) {
        if (deja_ok[j])                  { n_skip_mois <- n_skip_mois + 1; next }
        if (!inherits(chelsa_l93[[j]], "SpatRaster")) { n_miss_annee <- n_miss_annee + 1; next }
        
        if (v$methode == "multiplicatif") {
          result_j <- clamp(chelsa_l93[[j]] * corr_m, lower = 0, values = FALSE)
        } else {
          result_j <- chelsa_l93[[j]] + corr_m
        }
        
        writeRaster(result_j, f_outs[j], overwrite = TRUE,
                    datatype = "FLT4S", gdal = c("COMPRESS=LZW"))
        n_ok_mois  <- n_ok_mois  + 1
        n_ok_annee <- n_ok_annee + 1
      }
      
      n_skip_annee <- n_skip_annee + n_skip_mois
      cat(sprintf("OK:%d Skip:%d\n", n_ok_mois, n_skip_mois))
      
      rm(chelsa_l93, corr_m, digi_m); gc(verbose = FALSE)
    }
  }
  
  elapsed    <- (proc.time() - t_start_global)["elapsed"]
  avancement <- (annee - ANNEE_DEBUT + 1) / (ANNEE_FIN - ANNEE_DEBUT + 1)
  eta_s      <- if (avancement > 0.01) elapsed / avancement * (1 - avancement) else NA
  eta_str    <- if (!is.na(eta_s)) {
    h <- floor(eta_s / 3600); m <- floor((eta_s %% 3600) / 60)
    if (h > 0) sprintf("%dh%02dm", h, m) else sprintf("%dm", m)
  } else "..."
  
  n_ok_total   <- n_ok_total   + n_ok_annee
  n_miss_total <- n_miss_total + n_miss_annee
  n_skip_total <- n_skip_total + n_skip_annee
  
  cat(sprintf("  -> %d : OK:%d Skip:%d Miss:%d | ETA global: %s\n",
              annee, n_ok_annee, n_skip_annee, n_miss_annee, eta_str))
}

# --- Bilan final ------------------------------------------------------
elapsed_total <- (proc.time() - t_start_global)["elapsed"]
cat(sprintf(
  "\n=== DOWNSCALING TERMINE ===\n OK:%d  Skip:%d  Miss:%d\n Duree: %.0f min\n",
  n_ok_total, n_skip_total, n_miss_total, elapsed_total / 60))