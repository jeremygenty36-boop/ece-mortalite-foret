suppressPackageStartupMessages({
  library(terra)
  library(ncdf4)
  library(lubridate)
  library(sf)
  library(rnaturalearth)
})

ROOT_LOC <- "D:/Stage_JeremyG"
ROOT_SRV <- "S:/Projets/stage_JeremyG"

SRC_CHELSA <- list(
  pr    = file.path(ROOT_SRV, "3-Donnees", "2-CHELSA", "2-1960_2026_CHELSA_FR", "pr"),
  tasmax = file.path(ROOT_SRV, "3-Donnees", "2-CHELSA", "2-1960_2026_CHELSA_FR", "tasmax"),
  tasmin = file.path(ROOT_SRV, "3-Donnees", "2-CHELSA", "2-1960_2026_CHELSA_FR", "tasmin")
)
DST_CHELSA <- file.path(ROOT_LOC, "ECE_data", "3-CHELSA_1km")

COMPRESSION <- 5

# Mettre TRUE pour re-generer les fichiers deja existants (utile apres correction bug)
# FALSE = mode normal (SKIP si le fichier existe deja)
FORCER_RECONVERSION <- FALSE

if (!dir.exists(DST_CHELSA)) dir.create(DST_CHELSA, recursive = TRUE)

rtime_block <- function(nom, expr) {
  cat(sprintf("[%s] DEBUT : %s\n", format(Sys.time(), "%H:%M:%S"), nom))
  t0 <- Sys.time()
  force(expr)
  dur <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("[%s] FIN   : %s (%.1f sec / %.1f min)\n\n",
              format(Sys.time(), "%H:%M:%S"), nom, dur, dur/60))
}

ecrire_nc_safe <- function(r, f_nc, varname, unit, longname, compression, year) {
  # NORMALISATION AXE TEMPS (2026-06-08 : fusion des Correction_dates_*) : fichier annuel
  # -> axe journalier propre Jan1 + 0..(nt-1), annee deduite du nom ..._YYYY.nc. terra ecrit
  # alors un temps CF correct -> rend les scripts Correction_dates_* inutiles. Garde-fou nlyr>=360.
  .an_nc <- suppressWarnings(as.integer(sub(".*_(\\d{4})\\.nc$", "\\1", basename(f_nc))))
  if (!is.na(.an_nc) && terra::nlyr(r) >= 360L)
    terra::time(r) <- as.Date(sprintf("%d-01-01", .an_nc)) + 0:(terra::nlyr(r) - 1L)
  f_tmp <- paste0(f_nc, ".tmp.nc")
  if (file.exists(f_tmp)) file.remove(f_tmp)
  tryCatch({
    # 1. Ecriture terra (dates encodees par terra, potentiellement non-standard)
    writeCDF(r, f_tmp, varname = varname, unit = unit,
             longname = longname, compression = compression, overwrite = TRUE)

    # 2. Correction immediate de la variable temps (CF-compliant)
    #    terra peut encoder l'origine de facon non standard -> on reecrit proprement
    nc_w <- nc_open(f_tmp, write = TRUE)
    noms_temps <- c("time", "Time", "TIME", "t")
    tvar <- intersect(noms_temps, c(names(nc_w$var), names(nc_w$dim)))
    if (length(tvar) > 0) {
      nt <- tryCatch(length(ncvar_get(nc_w, tvar[1])),
                     error = function(e) nc_w$dim[[tvar[1]]]$len)
      ncvar_put(nc_w, tvar[1], 0:(nt - 1))
      ncatt_put(nc_w, tvar[1], "units",
                paste0("days since ", year, "-01-01 00:00:00"), prec = "text")
      ncatt_put(nc_w, tvar[1], "calendar", "standard", prec = "text")
    }
    nc_close(nc_w)

    file.rename(f_tmp, f_nc)
    return(TRUE)
  }, error = function(e) {
    if (file.exists(f_tmp)) file.remove(f_tmp)
    cat(sprintf("  ERREUR ecriture %s : %s\n", basename(f_nc), conditionMessage(e)))
    return(FALSE)
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# BASE 3 - CHELSA daily : TIF -> NetCDF annuel
# Pattern : CHELSA_VAR_DD_MM_YYYY_V.2.1.tif
# CRS : WGS84 | Resolution : ~1 km
# ──────────────────────────────────────────────────────────────────────────────

parse_chelsa_date <- function(nom) {
  # Pattern : CHELSA_VAR_DD_MM_YYYY_V.2.1.tif
  # ex : CHELSA_tasmax_15_01_1980_V.2.1.tif
  #      parts = [CHELSA, tasmax, 15, 01, 1980, V.2.1]  n=6
  #      DD=parts[n-3], MM=parts[n-2], YYYY=parts[n-1]
  parts <- strsplit(gsub("\\.tif$", "", nom), "_")[[1]]
  n <- length(parts)
  tryCatch(
    as.Date(sprintf("%s-%s-%s", parts[n-1], parts[n-2], parts[n-3]),
            format = "%Y-%m-%d"),
    error = function(e) NA
  )
}

rtime_block("BASE 3 - CHELSA TIF -> NetCDF", {

  france_wgs <- sf::st_transform(
    rnaturalearth::ne_countries(scale = "medium", country = "France",
                                returnclass = "sf"), 4326)
  emprise_fr <- ext(terra::vect(france_wgs)) + 0.5

  VARS_CHELSA <- list(
    list(dir = SRC_CHELSA$pr,     prefixe = "chelsa_prec",
         varname = "prec", unit = "mm",
         longname = "Daily precipitation CHELSA"),
    list(dir = SRC_CHELSA$tasmax, prefixe = "chelsa_tmax",
         varname = "tmax", unit = "degC",
         longname = "Daily max temperature CHELSA"),
    list(dir = SRC_CHELSA$tasmin, prefixe = "chelsa_tmin",
         varname = "tmin", unit = "degC",
         longname = "Daily min temperature CHELSA")
  )

  for (v in VARS_CHELSA) {
    if (!dir.exists(v$dir)) {
      cat(sprintf("  ABSENT dossier : %s\n", v$dir)); next
    }

    cat(sprintf("\n  CHELSA %s...\n", v$varname))
    f_all <- list.files(v$dir, pattern = "\\.tif$", full.names = TRUE)
    cat(sprintf("  %d fichiers trouves\n", length(f_all)))

    dates  <- as.Date(sapply(basename(f_all), parse_chelsa_date))
    valides <- !is.na(dates)
    f_all  <- f_all[valides]; dates <- dates[valides]
    annees <- year(dates)

    for (an in sort(unique(annees))) {
      f_nc <- file.path(DST_CHELSA, sprintf("CHELSA_%s_%d.nc", v$varname, an))
      if (file.exists(f_nc) && !FORCER_RECONVERSION) {
        cat(sprintf("  SKIP CHELSA_%s_%d\n", v$varname, an)); next
      }
      if (file.exists(f_nc) && FORCER_RECONVERSION) {
        cat(sprintf("  RECONVERSION (ecrasement) CHELSA_%s_%d\n", v$varname, an))
      }

      idx  <- which(annees == an)
      f_an <- f_all[idx[order(dates[idx])]]
      d_an <- sort(dates[idx])

      n_attendu <- if (an %% 4 == 0 && (an %% 100 != 0 || an %% 400 == 0)) 366L else 365L
      cat(sprintf("  -> %s %d (%d jours, attendu %d)...", v$prefixe, an, length(f_an), n_attendu))

      # Seuil : accepter si >= 90% des jours sont disponibles (annee incomplete = partielle ok)
      # Refuser si < 90% => annee trop incomplete pour etre utile
      if (length(f_an) < round(n_attendu * 0.9)) {
        cat(sprintf(" SKIP (annee incomplete : %d/%d jours)\n", length(f_an), n_attendu)); next
      }

      # Lecture avec protection individuelle par TIF (evite un seul TIF corrompu de tout bloquer)
      r_ref <- NULL  # raster de reference pour creer des couches NA si besoin
      couches <- lapply(seq_along(f_an), function(i) {
        r <- tryCatch(suppressWarnings({
          rc <- crop(rast(f_an[i]), emprise_fr)
          if (nlyr(rc) == 0 || ncell(rc) == 0) return(NULL)
          # MASQUAGE ABERRANTS CHELSA (2026-06-08 : fusion de 7-Patch_jours_aberrants_CHELSA) :
          # jours v2.1 avec fill 0 K (>10% pixels) ou overflow int16 (>1000 K) -> jour entier a NA.
          # Seuils sur valeurs brutes en K, TEMPERATURE uniquement (0/1000 K hors-sens pour prec).
          if (v$varname %in% c("tmax", "tmin")) {
            .vv <- values(rc, mat = FALSE)
            .ab <- sum(is.finite(.vv)) > 0 && (
                     mean(.vv == 0,   na.rm = TRUE) > 0.10  ||
                     max(.vv,         na.rm = TRUE) > 1000  ||
                     mean(.vv > 1000, na.rm = TRUE) > 0.001)
            if (isTRUE(.ab)) { values(rc) <- NA_real_
                               cat(sprintf(" [ABERRANT->NA %s]", format(d_an[i], "%d-%m"))) }
            else rc <- rc - 273.15
          }
          time(rc) <- d_an[i]
          rc
        }), error = function(e) NULL)
        # Si echec ou raster vide : couche NA (seulement si on a un modele de geometrie)
        if (is.null(r)) {
          if (!is.null(r_ref)) {
            r_na <- r_ref[[1]]; values(r_na) <- NA_real_; time(r_na) <- d_an[i]; r_na
          } else NULL
        } else {
          if (is.null(r_ref)) r_ref <<- r  # premier raster valide = modele
          r
        }
      })

      n_avant  <- length(f_an)
      couches  <- Filter(Negate(is.null), couches)
      n_perdu  <- n_avant - length(couches)   # jours perdus (NULL non recuperables)

      if (length(couches) == 0) {
        cat(sprintf(" SKIP (aucune couche valide)\n")); next
      }
      if (n_perdu > 0) cat(sprintf(" [%d jours perdus/corrompus]", n_perdu))

      # Combler les dates manquantes par des couches NA pour garantir
      # exactement 365/366 couches par annee (coherence inter-variables pour Climpact)
      if (!is.null(r_ref) && length(couches) < n_attendu) {
        d_presentes <- as.Date(unlist(lapply(couches, function(r) format(time(r)))))
        d_complete  <- seq(as.Date(sprintf("%d-01-01", an)),
                           as.Date(sprintf("%d-12-31", an)), by = "day")
        d_absentes  <- d_complete[!d_complete %in% d_presentes]
        if (length(d_absentes) > 0) {
          cat(sprintf(" [+%d NA dates absentes]", length(d_absentes)))
          couches_na <- lapply(d_absentes, function(d) {
            r_na <- r_ref[[1]]; values(r_na) <- NA_real_; time(r_na) <- d; r_na
          })
          couches <- c(couches, couches_na)
          ord     <- order(as.Date(unlist(lapply(couches, function(r) format(time(r))))))
          couches <- couches[ord]
        }
      }

      # Assemblage + ecriture dans un seul tryCatch
      # rast(liste) = methode terra pour combiner SpatRasters sans passer par c()
      r_an  <- NULL
      msg_ok <- tryCatch({
        r_an <- rast(couches)
        if (ecrire_nc_safe(r_an, f_nc, v$varname, v$unit, v$longname, COMPRESSION, an))
          sprintf(" OK (%.0f Mo)\n", file.size(f_nc)/1e6)
        else
          " ERREUR\n"
      }, error = function(e) sprintf(" ERREUR assemblage : %s\n", conditionMessage(e)))
      cat(msg_ok)
      rm(couches); if (!is.null(r_an)) rm(r_an); if (!is.null(r_ref)) rm(r_ref); gc()
    }
  }
})

f_nc <- list.files(DST_CHELSA, pattern = "\\.nc$", full.names = TRUE)
cat(sprintf("\nBILAN CHELSA : %d fichiers | %.1f Go\n",
            length(f_nc), sum(file.size(f_nc)) / 1e9))
