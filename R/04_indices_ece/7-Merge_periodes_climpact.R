# source("S:/Projets/stage_JeremyG/4-Travail/2-ECE/0-Lanceurs/0-Merge_periodes_climpact.R")
# ==============================================================================
# FUSION DES 5 PERIODES CLIMPACT -> dossier climpact_raw/ unique
# A lancer UNE FOIS apres que les 5 periodes d'une base sont terminees.
# Usage : modifier BASE_CODE et OUT_DIR, puis sourcer.
# ==============================================================================

library(terra)
library(ncdf4)
library(lubridate)

# ==============================================================================
# PARAMETRES — modifier pour chaque base
# ==============================================================================

# Defaut "EOBS", mais NE PAS ECRASER si la variable est deja definie en amont
# (ex : wrapper de 3-ECE_CHELSA_FINAL.R qui passe BASE_CODE="CHELSA" avant source).
if (!exists("BASE_CODE")) BASE_CODE <- "EOBS"   # EOBS | SAFRAN | CHELSA | DIGI_EOBS | DIGI_CHEL | DIGI_SAF
cat(sprintf("[merge] BASE_CODE = %s\n", BASE_CODE))

OUT_DIRS <- list(
  EOBS      = "S:/Projets/stage_JeremyG/5-Resultats/3-ECE/1-ECE_1979-2024/1-EOBS_11km",
  SAFRAN    = "S:/Projets/stage_JeremyG/5-Resultats/3-ECE/1-ECE_1979-2024/2-SAFRAN_8km",
  CHELSA    = "S:/Projets/stage_JeremyG/5-Resultats/3-ECE/1-ECE_1979-2024/3-CHELSA_1km",
  DIGI_EOBS = "S:/Projets/stage_JeremyG/5-Resultats/3-ECE/1-ECE_1979-2024/4-DIGI_EOBS_1km",
  DIGI_CHEL = "S:/Projets/stage_JeremyG/5-Resultats/3-ECE/1-ECE_1979-2024/6-DIGI_CHEL_1km",
  DIGI_SAF  = "S:/Projets/stage_JeremyG/5-Resultats/3-ECE/1-ECE_1979-2024/5-DIGI_SAF_1km"
)

# Periodes : debut = debut reel du fichier (avec warmup), debut_effectif = 1er mois a garder
PERIODES <- list(
  list(tag="1979-1987", debut_effectif=1979L),  # P1 : tout garder
  list(tag="1987-1996", debut_effectif=1988L),  # P2 : trim annee warmup 1987
  list(tag="1996-2005", debut_effectif=1997L),  # P3
  list(tag="2005-2014", debut_effectif=2006L),  # P4
  list(tag="2014-2024", debut_effectif=2015L)   # P5
)

OUT_DIR      <- OUT_DIRS[[BASE_CODE]]
DIR_MERGED   <- file.path(OUT_DIR, "climpact_raw")
if (!dir.exists(DIR_MERGED)) dir.create(DIR_MERGED, recursive=TRUE)

# ==============================================================================
# FONCTIONS
# ==============================================================================

ok  <- function(msg) cat(sprintf("  [OK]  %s\n", msg))
err <- function(msg) cat(sprintf("  [ERR] %s\n", msg))
inf <- function(msg) cat(sprintf("  [..]  %s\n", msg))

# Lire les dates depuis un fichier NetCDF
lire_dates_nc <- function(f) {
  tryCatch({
    nc  <- ncdf4::nc_open(f)
    dn  <- names(nc$dim)
    tn  <- dn[grepl("^time", dn, ignore.case=TRUE)][1]
    tv  <- ncdf4::ncvar_get(nc, tn)
    tu  <- ncdf4::ncatt_get(nc, tn, "units")$value
    ncdf4::nc_close(nc)
    orig <- as.Date(trimws(sub("^.*since\\s+", "", tu)))
    sc   <- if (grepl("hours",  tu, ignore.case=TRUE)) 1/24
            else if (grepl("seconds", tu, ignore.case=TRUE)) 1/86400 else 1
    as.Date(tv * sc, origin=orig)
  }, error=function(e) NULL)
}

# Fusionner N fichiers NetCDF temporels en un seul
# PATCH 2026-05-06 v2 : delegation a Python (netCDF4) - terra::writeCDF bloque
# meme avec compression=1 sur 552 couches x 2.2M pixels (CHELSA 1km).
# Python n'a pas ce souci et fait le merge en quelques minutes.
fusionner_nc <- function(fichiers, dates_liste, f_out, varname,
                         py_exe = "C:/OSGeo4W64/bin/python.exe",
                         py_script = "S:/Projets/stage_JeremyG/4-Travail/2-ECE/1-Calcul_indices/_merge_climpact_concat.py") {
  if (length(fichiers) == 0) return(NULL)
  if (!file.exists(py_exe))    stop("Python introuvable : ", py_exe)
  if (!file.exists(py_script)) stop("Script Python introuvable : ", py_script)

  # Les fichiers ont deja ete subsettes (warmup trim) en amont si necessaire,
  # donc on n'a pas besoin de passer debut_effectif au Python.
  cmd <- paste(shQuote(py_exe), shQuote(py_script),
               paste(shQuote(fichiers), collapse=" "),
               shQuote(f_out))
  cat(sprintf("[merge py] %d fichiers -> %s\n", length(fichiers), basename(f_out)))
  ts0 <- Sys.time()
  ret <- system(cmd)
  dur <- as.numeric(Sys.time() - ts0, units="mins")
  if (ret != 0L) {
    err(sprintf("Python merge failed (exit %d, %.1f min)", ret, dur))
    return(NULL)
  }
  cat(sprintf("[merge py] OK : %.1f min, %.1f Mo\n",
              dur, file.size(f_out)/1e6))
  f_out
}

# ==============================================================================
# VERIFICATION DES DOSSIERS DE PERIODES
# ==============================================================================

cat(sprintf("\n=== MERGE PERIODES CLIMPACT : %s ===\n", BASE_CODE))

dirs_periodes <- lapply(PERIODES, function(p) {
  d <- file.path(OUT_DIR, sprintf("climpact_raw_%s", p$tag))
  list(tag=p$tag, debut_effectif=p$debut_effectif, dir=d,
       existe=dir.exists(d))
})

for (dp in dirs_periodes) {
  fics <- if (dp$existe) length(list.files(dp$dir, "\\.nc$")) else 0
  cat(sprintf("  P%s : %s  [%d fichiers]\n", dp$tag,
              if (dp$existe) "OK" else "ABSENT", fics))
}

dirs_ok <- Filter(function(dp) dp$existe, dirs_periodes)
if (length(dirs_ok) == 0) stop("Aucun dossier de periode trouve. Lancer les 5 periodes d'abord.")

# ==============================================================================
# IDENTIFIER TOUS LES INDICES DISPONIBLES
# ==============================================================================

# Prendre les noms de fichiers de la premiere periode disponible comme reference
fics_ref <- list.files(dirs_ok[[1]]$dir, "\\.nc$", full.names=FALSE)
# Supprimer le prefixe de periode du nom pour obtenir le nom canonique de l'indice
# ex: txx_MON_1979-1987_EOBS.nc  -> txx_MON
indices_noms <- unique(sub("_[0-9]{4}-[0-9]{4}.*$", "", fics_ref))
indices_noms <- unique(sub("\\.nc$", "", fics_ref))  # nom complet sans extension

# Approche plus robuste : pattern sans periode
# Les fichiers Climpact sont nomes : {indice}_{MON|ANN}_{periode_base}_{annee_debut}_{annee_fin}.nc
# On regroupe par prefixe commun (tout sauf les annees de debut/fin)
extract_canon <- function(fname) {
  # Enlever l'extension
  base <- sub("\\.nc$", "", fname)
  # Enlever les 4 derniers champs numeriques (annees debut/fin souvent en suffixe)
  # Format typique : txx_MON_1979-1987_EOBS_1979_1989 -> on garde txx_MON
  # En pratique, grouper par partie non-numerique initiale
  parts <- strsplit(base, "_")[[1]]
  non_num <- parts[!grepl("^[0-9]{4}$", parts) & !grepl("^[0-9]{4}-[0-9]{4}$", parts)]
  paste(non_num, collapse="_")
}

canoniques <- unique(sapply(fics_ref, extract_canon))
cat(sprintf("\n  %d indices identifies : %s\n", length(canoniques),
            paste(canoniques[seq_len(min(5, length(canoniques)))], collapse=", ")))

# ==============================================================================
# FUSION PERIODE PAR PERIODE POUR CHAQUE INDICE
# ==============================================================================

n_ok <- 0L; n_err <- 0L

for (nom_idx in canoniques) {
  # Trouver un exemple de fichier pour ce nom canonique dans la 1ere periode
  fic_ex <- list.files(dirs_ok[[1]]$dir, pattern=paste0("^", nom_idx, "[_\\.]"),
                       full.names=TRUE)[1]
  if (is.na(fic_ex)) next

  # Nom du fichier de sortie = meme nom que periode 1 mais dans DIR_MERGED
  f_out <- file.path(DIR_MERGED, basename(fic_ex))
  # Adapter le nom pour retirer le tag de periode si present
  # (laisser tel quel : les fichiers climpact ont des noms uniques par indice+resolution)

  if (file.exists(f_out)) {
    inf(sprintf("SKIP (existe) : %s", basename(f_out)))
    n_ok <- n_ok + 1L
    next
  }

  fichiers_a_merger <- c()
  dates_a_merger    <- list()

  for (dp in dirs_ok) {
    # Trouver le fichier correspondant dans ce dossier de periode
    fic_p <- list.files(dp$dir, pattern=paste0("^", nom_idx, "[_\\.]"),
                        full.names=TRUE)
    if (length(fic_p) == 0) next
    fic_p <- fic_p[1]

    # Lire les dates et filtrer selon debut_effectif (trim warmup)
    dates_p <- lire_dates_nc(fic_p)
    if (is.null(dates_p)) {
      # Fallback : lire via terra
      r_tmp <- tryCatch(rast(fic_p), error=function(e) NULL)
      if (!is.null(r_tmp)) {
        t_raw  <- time(r_tmp)
        dates_p <- tryCatch(
          as.Date(if (inherits(t_raw, c("Date","POSIXct","POSIXlt"))) t_raw
                  else as.numeric(t_raw), origin="1970-01-01"),
          error=function(e) NULL)
      }
    }

    if (!is.null(dates_p)) {
      # Garder seulement les dates >= debut_effectif (trim annee de warmup)
      annees_p <- as.integer(format(dates_p, "%Y"))
      idx_keep <- which(annees_p >= dp$debut_effectif)
      if (length(idx_keep) == 0) next

      # Creer un fichier temporaire avec uniquement les couches retenues
      r_p <- tryCatch(rast(fic_p), error=function(e) NULL)
      if (is.null(r_p)) next

      if (length(idx_keep) < nlyr(r_p)) {
        # Creer tmp avec subset
        f_tmp <- tempfile(fileext=".nc")
        r_sub <- r_p[[idx_keep]]
        if (!is.null(dates_p[idx_keep])) time(r_sub) <- dates_p[idx_keep]
        writeCDF(r_sub, f_tmp, varname=nom_idx, compression=1L, overwrite=TRUE)
        fichiers_a_merger <- c(fichiers_a_merger, f_tmp)
        dates_a_merger    <- c(dates_a_merger, list(dates_p[idx_keep]))
        rm(r_sub); gc()
      } else {
        fichiers_a_merger <- c(fichiers_a_merger, fic_p)
        dates_a_merger    <- c(dates_a_merger, list(dates_p))
      }
      rm(r_p); gc()
    } else {
      # Sans dates : merger tel quel
      fichiers_a_merger <- c(fichiers_a_merger, fic_p)
      dates_a_merger    <- c(dates_a_merger, list(NULL))
    }
  }

  if (length(fichiers_a_merger) == 0) {
    err(sprintf("Aucune periode trouvee pour %s", nom_idx))
    n_err <- n_err + 1L
    next
  }

  res <- tryCatch(
    fusionner_nc(fichiers_a_merger, dates_a_merger, f_out, nom_idx),
    error=function(e) { err(sprintf("%s : %s", nom_idx, conditionMessage(e))); NULL }
  )

  # Nettoyer les fichiers tmp
  tmp_mask <- grepl("^.*\\.nc$", fichiers_a_merger) &
              !sapply(fichiers_a_merger, function(f) any(sapply(dirs_ok, function(d) startsWith(f, d$dir))))
  invisible(sapply(fichiers_a_merger[tmp_mask], function(f) tryCatch(file.remove(f), error=function(e) NULL)))

  if (!is.null(res)) {
    ok(sprintf("%-50s (%d periodes)", basename(f_out), length(fichiers_a_merger)))
    n_ok <- n_ok + 1L
  } else {
    n_err <- n_err + 1L
  }
}

cat(sprintf("\n=== MERGE TERMINE : %d OK / %d ERR ===\n", n_ok, n_err))
cat(sprintf("  Sortie : %s\n", DIR_MERGED))
