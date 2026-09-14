# source("S:/Projets/stage_JeremyG/4-Travail/1-Bases_de_donnees/1-Telechargement/6-Diagnostic_TIF_CHELSA_corrompus.R")
# ==============================================================================
# DIAGNOSTIC TIFS CHELSA CORROMPUS - scan global tasmin / tasmax / pr
#
# Pattern detecte (ex : 29 avril 2022) :
#   - 75 % de la grille globale a 0 K (devient -273.15 deg C apres K->C)
#   - max a 6553 K (= 65534 * 0.1, overflow int16)
#
# Test minimal et rapide par TIF :
#   n_zero    = nb pixels EXACTEMENT a 0
#   n_overflw = nb pixels > 1000 (impossible pour temp ou prec en unite source)
#   max_val   = valeur max
#
# Sortie : CSV par variable, dans le meme dossier
# ==============================================================================

suppressPackageStartupMessages({
  library(terra)
  library(parallel)
})

.PFX <- if (dir.exists("S:/Projets")) "S:" else "/Volumes/_donnees"
DIR_BASE <- file.path(.PFX, "Projets/stage_JeremyG/3-Donnees/2-CHELSA/2-1960_2026_CHELSA_FR")
DIR_OUT  <- file.path(.PFX, "Projets/stage_JeremyG/4-Travail/1-Bases_de_donnees/1-Telechargement")
N_WORKERS <- 8L

VARS <- c("tasmin", "tasmax", "pr")

# Helper NULL coalescing (compat R < 4.4)
`%||%` <- function(a, b) if (is.null(a)) b else a

# Fonction worker : 1 TIF -> 1 ligne de stats
scan_tif <- function(f) {
  tryCatch({
    v <- terra::values(terra::rast(f))
    list(
      file       = basename(f),
      n_pixels   = length(v),
      n_zero     = sum(v == 0, na.rm = TRUE),
      n_overflw  = sum(v > 1000, na.rm = TRUE),
      max_val    = max(v, na.rm = TRUE),
      min_val    = min(v, na.rm = TRUE),
      n_na       = sum(is.na(v))
    )
  }, error = function(e) {
    list(file = basename(f), n_pixels = NA, n_zero = NA, n_overflw = NA,
         max_val = NA, min_val = NA, n_na = NA, err = conditionMessage(e))
  })
}

for (var in VARS) {
  dir_var <- file.path(DIR_BASE, var)
  if (!dir.exists(dir_var)) {
    cat(sprintf("[SKIP] dossier absent : %s\n", dir_var)); next
  }

  tifs <- list.files(dir_var, pattern = "_V\\.2\\.1\\.tif$", full.names = TRUE)
  cat(sprintf("\n=== %s : %d TIFs a scanner ===\n", var, length(tifs)))

  if (length(tifs) == 0) next
  t0 <- Sys.time()

  # Cluster PSOCK avec outfile = "" (fix Windows)
  cl <- makeCluster(min(length(tifs), N_WORKERS), type = "PSOCK", outfile = "")
  on.exit(try(stopCluster(cl), silent = TRUE), add = TRUE)
  clusterEvalQ(cl, suppressPackageStartupMessages(library(terra)))

  res <- parLapply(cl, tifs, scan_tif)
  stopCluster(cl)

  # Aplatir liste -> data.frame
  df <- do.call(rbind, lapply(res, function(r) {
    data.frame(
      file      = r$file,
      n_pixels  = r$n_pixels  %||% NA,
      n_zero    = r$n_zero    %||% NA,
      n_overflw = r$n_overflw %||% NA,
      max_val   = r$max_val   %||% NA,
      min_val   = r$min_val   %||% NA,
      n_na      = r$n_na      %||% NA,
      stringsAsFactors = FALSE
    )
  }))

  # Calcule pourcentage de pixels valides (hors NA) a 0 et en overflow
  df$pct_zero  <- 100 * df$n_zero    / (df$n_pixels - df$n_na)
  df$pct_ovflw <- 100 * df$n_overflw / (df$n_pixels - df$n_na)

  # Extrait date depuis le nom : CHELSA_<var>_DD_MM_YYYY_V.2.1.tif
  # Approche regex robuste : capture les 3 derniers groupes numeriques avant V.2.1
  m <- regmatches(df$file,
                  regexec("_(\\d{2})_(\\d{2})_(\\d{4})_V\\.2\\.1\\.tif$", df$file))
  df$date <- as.Date(sapply(m, function(x) {
    if (length(x) < 4) return(NA_character_)
    sprintf("%s-%s-%s", x[4], x[3], x[2])   # YYYY-MM-DD
  }))
  n_bad_dates <- sum(is.na(df$date))
  if (n_bad_dates > 0) {
    cat(sprintf("  [WARN] %d fichier(s) avec date impossible a parser\n", n_bad_dates))
  }

  # Sauvegarde IMMEDIATE du CSV (avant tri et affichage suspects) - on ne perd
  # jamais le travail du scan meme si l'etape suivante echoue
  f_out <- file.path(DIR_OUT, sprintf("diagnostic_CHELSA_%s_corrompus.csv", var))
  df <- df[order(-df$pct_zero, -df$max_val), ]
  write.csv(df, f_out, row.names = FALSE)

  # Affiche les jours suspects
  suspects <- df[df$pct_zero > 10 | df$max_val > 1000 | df$pct_ovflw > 0.1, ]
  cat(sprintf("\n  %d jours suspects (pct_zero > 10%% OU max > 1000 OU pct_ovflw > 0.1%%) :\n",
              nrow(suspects)))
  if (nrow(suspects) > 0) {
    print(head(suspects[, c("date", "pct_zero", "pct_ovflw", "max_val", "n_zero")], 20))
  }

  cat(sprintf("\n  -> %s (%.0f s)\n", basename(f_out),
              as.numeric(Sys.time() - t0, units = "secs")))
}

cat("\n=== Diagnostic termine ===\n")
cat("Fichiers de sortie :\n")
for (var in VARS) {
  f <- file.path(DIR_OUT, sprintf("diagnostic_CHELSA_%s_corrompus.csv", var))
  if (file.exists(f)) cat(sprintf("  %s (%.1f ko)\n", f, file.size(f)/1024))
}
