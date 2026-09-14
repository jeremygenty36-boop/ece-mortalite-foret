# ======================================================================
# Telechargement CHELSA V2.1 daily — PC 1 : 1960-01-01 -> 1981-12-31
# Version optimisee : curl::multi_download (BATCH=N_DL en parallele) +
#                     crop parallele sur N_CROP coeurs
#
# Variables disponibles sur cette periode :
#   tasmin / tasmax : 1960-01-01 -> 1981-12-31 (trous irreguliers possibles)
#   pr              : 1979-01-01 -> 1981-12-31 (pas de donnee avant 1979)
#
# Sortie commune aux 3 scripts :
#   3-Donnees/2-CHELSA/3-1960_2026_CHELSA_FR/
#   ├── pr/      precipitation (mm/jour)
#   ├── tasmin/  temperature minimale (K — soustraire 273.15 pour degC)
#   └── tasmax/  temperature maximale (K — soustraire 273.15 pour degC)
# ======================================================================

if (!requireNamespace("curl",     quietly = TRUE)) install.packages("curl")
if (!requireNamespace("terra",    quietly = TRUE)) install.packages("terra")
library(curl)
library(terra)
library(parallel)

# --- Parametres -------------------------------------------------------
PATH_TMP <- "S:/Projets/stage_JeremyG/3-Donnees/2-CHELSA/1-tmp/PC1/"
PATH_OUT <- "S:/Projets/stage_JeremyG/3-Donnees/2-CHELSA/3-1960_2026_CHELSA_FR/"
URL_BASE <- "https://os.unil.cloud.switch.ch/chelsa02/chelsa/global/daily"

DATE_DEBUT       <- as.Date("1960-01-01")
DATE_FIN         <- as.Date("1981-12-31")
DATE_DEBUT_PR    <- as.Date("1979-01-01")  # pr inexistant avant 1979
ANNEE_BASCULE_PR <- 2021                   # bascule pr/ -> prec/ (hors periode ici)

emprise_france_wgs84 <- ext(-5.5, 10.0, 41.0, 51.5)

N_CROP <- max(1, detectCores() - 1)  # coeurs pour le crop parallele
BATCH  <- 1    # 1 fichier a la fois : le serveur CHELSA bloque les connexions multiples

cat(sprintf("Coeurs detectes : %d  -> crop sur %d coeurs\n", detectCores(), N_CROP))
cat(sprintf("Telechargements simultanees : %d  | Taille lot : %d\n\n", N_DL, BATCH))

# --- Creation des dossiers --------------------------------------------
for (d in c("pr", "tasmin", "tasmax"))
  dir.create(file.path(PATH_OUT, d), recursive = TRUE, showWarnings = FALSE)
dir.create(PATH_TMP, recursive = TRUE, showWarnings = FALSE)

# --- Construction vectorisee de la table complete ---------------------
cat("Construction de la liste des fichiers...\n")

dates_all <- seq(DATE_DEBUT, DATE_FIN, by = "day")
dd_vec    <- format(dates_all, "%d")
mm_vec    <- format(dates_all, "%m")
yyyy_vec  <- format(dates_all, "%Y")
an_vec    <- as.integer(yyyy_vec)

# pr uniquement a partir de DATE_DEBUT_PR (vecteurs filtres)
idx_pr  <- dates_all >= DATE_DEBUT_PR
dd_pr   <- dd_vec[idx_pr];  mm_pr <- mm_vec[idx_pr];  yyyy_pr <- yyyy_vec[idx_pr]
fname_pr <- sprintf("CHELSA_pr_%s_%s_%s_V.2.1.tif", dd_pr, mm_pr, yyyy_pr)
rows_pr <- data.frame(
  url = paste0(URL_BASE, "/pr/", yyyy_pr, "/", fname_pr),
  tmp = file.path(PATH_TMP, fname_pr),
  out = file.path(PATH_OUT, "pr", fname_pr),
  stringsAsFactors = FALSE
)

# tasmin / tasmax sur toute la periode
make_rows <- function(vdir, var_label) {
  fname <- sprintf("CHELSA_%s_%s_%s_%s_V.2.1.tif", vdir, dd_vec, mm_vec, yyyy_vec)
  data.frame(
    url = paste0(URL_BASE, "/", vdir, "/", yyyy_vec, "/", fname),
    tmp = file.path(PATH_TMP, fname),
    out = file.path(PATH_OUT, var_label, fname),
    stringsAsFactors = FALSE
  )
}
rows_tasmin <- make_rows("tasmin", "tasmin")
rows_tasmax <- make_rows("tasmax", "tasmax")

all_rows <- rbind(rows_pr, rows_tasmin, rows_tasmax)

# Verification vectorisee des fichiers existants
ex   <- file.exists(all_rows$out)
sz   <- ifelse(ex, file.size(all_rows$out), 0L)
todo <- all_rows[!ex | sz <= 1000, ]

n_skip_init <- nrow(all_rows) - nrow(todo)
cat(sprintf("Total : %d fichiers | Deja presents : %d | A telecharger : %d\n\n",
            nrow(all_rows), n_skip_init, nrow(todo)))

if (nrow(todo) == 0) {
  cat("Tout est deja telecharge !\n")
  quit(save = "no")
}

# --- Decoupage en lots ------------------------------------------------
lots <- split(seq_len(nrow(todo)), ceiling(seq_len(nrow(todo)) / BATCH))

n_ok <- 0; n_missing <- 0; n_err <- 0
t_start <- proc.time()

for (i_lot in seq_along(lots)) {
  idx <- lots[[i_lot]]
  lot <- todo[idx, ]

  # 1. Telechargement (1 fichier a la fois — serveur bloque les connexions multiples)
  dl_res <- tryCatch(
    curl::multi_download(lot$url, lot$tmp, resume = FALSE,
                         progress = FALSE, timeout = 300,
                         multiplex = FALSE),
    error = function(e) { cat("\nERREUR multi_download:", conditionMessage(e), "\n"); NULL }
  )

  if (is.null(dl_res)) {
    n_err <- n_err + nrow(lot)
  } else {
    statut <- dl_res$status_code[1]
    f_tmp  <- lot$tmp[1]
    f_out  <- lot$out[1]

    # Nettoyer les fichiers tmp non-200 (pages HTML 404 etc.)
    if (is.na(statut) || statut != 200) {
      if (file.exists(f_tmp)) file.remove(f_tmp)
      if (!is.na(statut) && statut == 404) n_missing <- n_missing + 1
      else n_err <- n_err + 1
    } else {
      # 2. Crop inline (BATCH=1 : lot a exactement 1 ligne)
      res <- tryCatch({
        r    <- terra::rast(f_tmp)
        r_fr <- terra::crop(r, emprise_france_wgs84)
        terra::writeRaster(r_fr, f_out, overwrite = TRUE,
                           datatype = "FLT4S", gdal = c("COMPRESS=DEFLATE"))
        if (file.exists(f_tmp)) file.remove(f_tmp)
        "ok"
      }, error = function(e) {
        if (file.exists(f_tmp)) file.remove(f_tmp)
        "missing"
      })
      if (res == "ok")      n_ok      <- n_ok      + 1
      if (res == "missing") n_missing <- n_missing + 1
    }
  }

  # Barre de progression
  i_done  <- i_lot * BATCH
  pct     <- min(i_done / nrow(todo), 1)
  elapsed <- (proc.time() - t_start)["elapsed"]
  eta_s   <- if (pct > 0.001) elapsed / pct * (1 - pct) else NA
  eta_str <- if (!is.na(eta_s)) {
    h <- floor(eta_s / 3600); m <- floor((eta_s %% 3600) / 60)
    if (h > 0) sprintf("%dh%02dm%02ds", h, m, floor(eta_s %% 60))
    else sprintf("%dm%02ds", m, floor(eta_s %% 60))
  } else "..."
  filled <- round(pct * 30)
  bar    <- paste0(strrep("=", filled), strrep("-", 30 - filled))
  cat(sprintf("\r[PC1] [%s] %5.1f%% | OK:%d Miss:%d Err:%d | ETA:%s   ",
              bar, pct * 100, n_ok, n_missing, n_err, eta_str))
  flush.console()
}

cat(sprintf(
  "\n=== PC1 1960-1981 TERMINE ===\n Skip:%d  OK:%d  Missing(404):%d  Erreurs:%d\n",
  n_skip_init, n_ok, n_missing, n_err))
if (n_err > 0) cat("Relancer pour retenter les erreurs (reprise auto).\n")
