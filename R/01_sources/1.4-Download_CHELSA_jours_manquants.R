# ==============================================================================
# TELECHARGEMENT CHELSA - Jours manquants identifies par diagnostic
#
# Jours manquants confirmes (diagnostic 0-Diagnostic_DIGI_detail.R) :
#
#   tasmax :
#     - 1979-12-31  (manquant dans CHELSA NC tmax + DIGI_CHEL tmax)
#     - 2022-10-19  (manquant dans DIGI_CHEL tmax - TIF confirme absent)
#     - 2022-12-31  (manquant dans CHELSA NC tmax)
#
#   tasmin :
#     - 1979-12-31  (manquant dans CHELSA NC tmin + DIGI_CHEL tmin)
#
#   pr :
#     - 1979-05-01, 1979-06-01, 1979-06-02  (manquants dans DIGI_CHEL prec)
#     - 1979-07-01, 1979-07-02
#     - 1979-08-01, 1979-08-02
#     - 1979-09-01, 1979-09-02
#     - 2020-12-26 -> 2020-12-31
#
# Methode identique a 2-Download_CHELSA_manquants.R :
#   curl::multi_download -> crop France -> writeRaster
# ==============================================================================

if (!requireNamespace("curl",  quietly=TRUE)) install.packages("curl")
if (!requireNamespace("terra", quietly=TRUE)) install.packages("terra")
library(curl)
library(terra)

# Dossiers de destination (structure existante sur S:)
DIR_TASMAX <- "S:/Projets/stage_JeremyG/2-1960-2026/tasmax"
DIR_TASMIN <- "S:/Projets/stage_JeremyG/2-1960-2026/tasmin"
DIR_PR     <- "S:/Projets/stage_JeremyG/2-1960-2026/pr"

# Dossier temporaire (download brut avant crop)
PATH_TMP   <- "S:/Projets/stage_JeremyG/3-Donnees/2-CHELSA/1-tmp/manquants/"
dir.create(PATH_TMP, recursive=TRUE, showWarnings=FALSE)

# URL de base (meme serveur que 2-Download_CHELSA_manquants.R)
URL_BASE <- "https://os.unil.cloud.switch.ch/chelsa02/chelsa/global/daily"

# Emprise France (meme que le script de reference)
EMPRISE_FR <- ext(-5.5, 10.0, 41.0, 51.5)

# ==============================================================================
# LISTE DES JOURS A TELECHARGER
# ==============================================================================

# Chaque entree : list(var, dir_dest, date)
jours <- list(
  # tasmax
  list(var="tasmax", dir=DIR_TASMAX, date=as.Date("1979-12-31")),
  list(var="tasmax", dir=DIR_TASMAX, date=as.Date("2022-10-19")),
  list(var="tasmax", dir=DIR_TASMAX, date=as.Date("2022-12-31")),
  # tasmin
  list(var="tasmin", dir=DIR_TASMIN, date=as.Date("1979-12-31")),
  # pr 1979
  list(var="pr", dir=DIR_PR, date=as.Date("1979-05-01")),
  list(var="pr", dir=DIR_PR, date=as.Date("1979-06-01")),
  list(var="pr", dir=DIR_PR, date=as.Date("1979-06-02")),
  list(var="pr", dir=DIR_PR, date=as.Date("1979-07-01")),
  list(var="pr", dir=DIR_PR, date=as.Date("1979-07-02")),
  list(var="pr", dir=DIR_PR, date=as.Date("1979-08-01")),
  list(var="pr", dir=DIR_PR, date=as.Date("1979-08-02")),
  list(var="pr", dir=DIR_PR, date=as.Date("1979-09-01")),
  list(var="pr", dir=DIR_PR, date=as.Date("1979-09-02")),
  # pr 2020
  list(var="pr", dir=DIR_PR, date=as.Date("2020-12-26")),
  list(var="pr", dir=DIR_PR, date=as.Date("2020-12-27")),
  list(var="pr", dir=DIR_PR, date=as.Date("2020-12-28")),
  list(var="pr", dir=DIR_PR, date=as.Date("2020-12-29")),
  list(var="pr", dir=DIR_PR, date=as.Date("2020-12-30")),
  list(var="pr", dir=DIR_PR, date=as.Date("2020-12-31"))
)

# Nommage fichier CHELSA : CHELSA_{var}_{DD}_{MM}_{YYYY}_V.2.1.tif
nom_chelsa <- function(var, date) {
  sprintf("CHELSA_%s_%02d_%02d_%04d_V.2.1.tif",
          var,
          as.integer(format(date, "%d")),
          as.integer(format(date, "%m")),
          as.integer(format(date, "%Y")))
}

# URL : {BASE}/{var}/{yyyy}/{fichier}  (meme structure que build_url() de reference)
build_url <- function(var, date) {
  yyyy <- format(date, "%Y")
  nom  <- nom_chelsa(var, date)
  sprintf("%s/%s/%s/%s", URL_BASE, var, yyyy, nom)
}

# ==============================================================================
# CONSTRUCTION DU TABLEAU DE TACHES
# ==============================================================================

todo <- do.call(rbind, lapply(jours, function(j) {
  nom <- nom_chelsa(j$var, j$date)
  data.frame(
    var  = j$var,
    date = as.character(j$date),
    nom  = nom,
    out  = file.path(j$dir, nom),
    tmp  = file.path(PATH_TMP, nom),
    url  = build_url(j$var, j$date),
    stringsAsFactors = FALSE
  )
}))

# ==============================================================================
# ETAPE 1 : DIAGNOSTIC
# ==============================================================================

cat("\n=== Diagnostic TIFs manquants ===\n\n")

deja_presents <- file.exists(todo$out) & file.size(todo$out) >= 1000
cat(sprintf("  Deja presents : %d\n", sum(deja_presents)))
cat(sprintf("  A telecharger : %d\n\n", sum(!deja_presents)))

for (i in which(deja_presents))  cat(sprintf("  [OK] %s\n", todo$nom[i]))
for (i in which(!deja_presents)) cat(sprintf("  [--] %s\n", todo$nom[i]))

todo_dl <- todo[!deja_presents, ]

if (nrow(todo_dl) == 0) {
  cat("\nTous les TIFs sont deja presents.\n")
  stop("Rien a faire.", call.=FALSE)
}

# ==============================================================================
# ETAPE 2 : TELECHARGEMENT
# ==============================================================================

cat(sprintf("\n=== Telechargement de %d fichier(s) ===\n\n", nrow(todo_dl)))

n_ok      <- 0L
n_missing <- 0L
n_err     <- 0L
t_start   <- proc.time()
n_total   <- nrow(todo_dl)

for (i in seq_len(n_total)) {
  f_out <- todo_dl$out[i]
  f_tmp <- todo_dl$tmp[i]
  url   <- todo_dl$url[i]
  nom   <- todo_dl$nom[i]

  cat(sprintf("  [%d/%d] %s\n         %s\n", i, n_total, nom, url))

  # Supprimer tmp precedent si existe
  if (file.exists(f_tmp)) file.remove(f_tmp)

  # Telecharger
  dl_res <- tryCatch(
    curl::multi_download(url, f_tmp, resume=FALSE,
                         progress=FALSE, timeout=300, multiplex=FALSE),
    error=function(e) NULL
  )

  if (is.null(dl_res)) {
    cat("         -> ERREUR curl\n")
    n_err <- n_err + 1L
    next
  }

  statut <- dl_res$status_code[1]

  if (is.na(statut) || statut != 200L) {
    if (file.exists(f_tmp)) file.remove(f_tmp)
    if (!is.na(statut) && statut == 404L) {
      cat("         -> 404 : fichier absent sur le serveur CHELSA\n")
      n_missing <- n_missing + 1L
    } else {
      cat(sprintf("         -> ERREUR HTTP %s\n", statut))
      n_err <- n_err + 1L
    }
    next
  }

  # Crop France + writeRaster (meme traitement que le script de reference)
  res <- tryCatch({
    r      <- terra::rast(f_tmp)
    r_fr   <- terra::crop(r, EMPRISE_FR)
    if (!dir.exists(dirname(f_out)))
      dir.create(dirname(f_out), recursive=TRUE)
    terra::writeRaster(r_fr, f_out, overwrite=TRUE,
                       datatype="FLT4S", gdal=c("COMPRESS=DEFLATE"))
    if (file.exists(f_tmp)) file.remove(f_tmp)
    "ok"
  }, error=function(e) {
    if (file.exists(f_tmp)) file.remove(f_tmp)
    cat(sprintf("         -> ERREUR traitement : %s\n", e$message))
    "err"
  })

  if (res == "ok") {
    cat(sprintf("         -> OK (%.1f Mo)\n", file.size(f_out)/1e6))
    n_ok <- n_ok + 1L
  } else {
    n_err <- n_err + 1L
  }
}

# ==============================================================================
# BILAN
# ==============================================================================

elapsed <- (proc.time() - t_start)["elapsed"]
cat(sprintf("\n=== Bilan : %d OK | %d absents (404) | %d erreurs | %.0f s ===\n",
            n_ok, n_missing, n_err, elapsed))

if (n_missing > 0) {
  cat("\nFichiers absents du serveur (404) :\n")
  # Lister ceux qui ne sont toujours pas presents
  for (i in seq_len(nrow(todo_dl))) {
    if (!file.exists(todo_dl$out[i]))
      cat(sprintf("  %s\n  URL : %s\n", todo_dl$nom[i], todo_dl$url[i]))
  }
}

if (n_ok > 0 && (n_missing + n_err) == 0) {
  cat("\nTous les TIFs telecharges avec succes.\n")
  cat("Etapes suivantes :\n")
  cat("  1. Relancer 3-ECE_CHELSA.R pour inserer les jours dans les NC CHELSA\n")
  cat("  2. Relancer 14-Correction_dates_DIGI_CHEL.R pour corriger DIGI_CHEL\n")
}
