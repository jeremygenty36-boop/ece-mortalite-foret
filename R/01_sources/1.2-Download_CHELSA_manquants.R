# ======================================================================
# Telechargement des fichiers CHELSA manquants
# Lit manquants_CHELSA.csv genere par 3.4_Verification_CHELSA.R
# et tente de telecharger chaque fichier manquant
# ======================================================================

if (!requireNamespace("curl",  quietly = TRUE)) install.packages("curl")
if (!requireNamespace("terra", quietly = TRUE)) install.packages("terra")
library(curl)
library(terra)

PATH_OUT  <- "S:/Projets/stage_JeremyG/3-Donnees/2-CHELSA/3-1960_2026_CHELSA_FR/"
PATH_TMP  <- "S:/Projets/stage_JeremyG/3-Donnees/2-CHELSA/1-tmp/manquants/"
URL_BASE  <- "https://os.unil.cloud.switch.ch/chelsa02/chelsa/global/daily"
CSV_PATH  <- file.path(PATH_OUT, "manquants_CHELSA.csv")

emprise_france_wgs84 <- ext(-5.5, 10.0, 41.0, 51.5)

dir.create(PATH_TMP, recursive = TRUE, showWarnings = FALSE)

# --- Lecture du CSV ---------------------------------------------------
manquants <- read.csv(CSV_PATH, stringsAsFactors = FALSE)$fichier
cat(sprintf("%d fichiers manquants a telecharger\n\n", length(manquants)))

# --- Reconstruction des URLs depuis les chemins -----------------------
# Chemin : .../pr/CHELSA_pr_DD_MM_YYYY_V.2.1.tif
#          .../tasmin/CHELSA_tasmin_DD_MM_YYYY_V.2.1.tif
build_url <- function(f_out) {
  fname <- basename(f_out)
  parts <- strsplit(gsub("_V\\.2\\.1\\.tif$", "", fname), "_")[[1]]
  var   <- parts[2]
  dd    <- parts[3]
  mm    <- parts[4]
  yyyy  <- parts[5]
  
  # Dossier URL : "prec" (fichiers récents 2025+) → dossier reste "pr"
  vdir <- var
  if (var == "prec") vdir <- "pr"
  
  paste0(URL_BASE, "/", vdir, "/", yyyy, "/", fname)
}

todo <- data.frame(
  out = manquants,
  tmp = file.path(PATH_TMP, basename(manquants)),
  url = sapply(manquants, build_url),
  stringsAsFactors = FALSE
)

# --- Boucle de telechargement -----------------------------------------
n_ok <- 0; n_missing <- 0; n_err <- 0
t_start <- proc.time()
n_total <- nrow(todo)

for (i in seq_len(n_total)) {
  f_out <- todo$out[i]
  f_tmp <- todo$tmp[i]
  url   <- todo$url[i]

  # Sauter si deja present entre-temps
  if (file.exists(f_out) && file.size(f_out) >= 1000) {
    n_ok <- n_ok + 1
    next
  }

  dl_res <- tryCatch(
    curl::multi_download(url, f_tmp, resume = FALSE,
                         progress = FALSE, timeout = 300,
                         multiplex = FALSE),
    error = function(e) NULL
  )

  if (is.null(dl_res)) {
    n_err <- n_err + 1
  } else {
    statut <- dl_res$status_code[1]

    if (is.na(statut) || statut != 200) {
      if (file.exists(f_tmp)) file.remove(f_tmp)
      if (!is.na(statut) && statut == 404) n_missing <- n_missing + 1
      else n_err <- n_err + 1
    } else {
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
  pct     <- i / n_total
  elapsed <- (proc.time() - t_start)["elapsed"]
  eta_s   <- if (pct > 0.001) elapsed / pct * (1 - pct) else NA
  eta_str <- if (!is.na(eta_s)) {
    h <- floor(eta_s / 3600); m <- floor((eta_s %% 3600) / 60)
    if (h > 0) sprintf("%dh%02dm%02ds", h, m, floor(eta_s %% 60))
    else sprintf("%dm%02ds", m, floor(eta_s %% 60))
  } else "..."
  filled <- round(pct * 30)
  bar    <- paste0(strrep("=", filled), strrep("-", 30 - filled))
  cat(sprintf("\r[MQ] [%s] %5.1f%% | OK:%d Miss:%d Err:%d | ETA:%s   ",
              bar, pct * 100, n_ok, n_missing, n_err, eta_str))
  flush.console()
}

cat("\n")
cat(sprintf("\n=== MANQUANTS TERMINE ===\n OK:%d  Missing(404):%d  Erreurs:%d\n",
            n_ok, n_missing, n_err))

# Mettre a jour le CSV avec les fichiers encore manquants
encore_manquants <- todo$out[!file.exists(todo$out) |
                               file.size(todo$out) < 50000]
if (length(encore_manquants) > 0) {
  write.csv(data.frame(fichier = encore_manquants), CSV_PATH, row.names = FALSE)
  cat(sprintf("CSV mis a jour : %d fichiers encore manquants\n",
              length(encore_manquants)))
} else {
  file.remove(CSV_PATH)
  cat("Tout est telecharge ! CSV supprime.\n")
}
