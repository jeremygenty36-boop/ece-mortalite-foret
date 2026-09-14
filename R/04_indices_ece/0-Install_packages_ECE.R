# source("R/04_indices_ece/0-Install_packages_ECE.R")   # depuis la racine du depot
# ==============================================================================
# INSTALLATION DES PACKAGES R NECESSAIRES AUX SCRIPTS ECE
#
#   Concu pour fonctionner sur N'IMPORTE QUELLE machine, AVEC OU SANS Rtools :
#
#     1. Packages CRAN classiques (terra, ncdf4, etc.)
#     2. Packages ARCHIVES de CRAN (PCICt, ncdf4.helpers, climdex.pcic) :
#        on les recupere en BINAIRE depuis Posit Public Package Manager
#        (snapshot du 2025-04-01, avant l'archivage du 2025-05-03)
#        -> pas besoin de Rtools pour compiler
#     3. Tarballs locaux (fallback) si Posit indispo
#     4. climdex.pcic.ncdf depuis le tarball Climpact local
#
#   Usage : sur chaque machine, dans une session R fraiche :
#     source("R/04_indices_ece/0-Install_packages_ECE.R")
# ==============================================================================

# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
cat(sprintf("%s\n  INSTALL PACKAGES ECE - %s\n%s\n",
            strrep("=", 70), Sys.info()[["nodename"]], strrep("=", 70)))
cat(sprintf("R version : %s.%s\n", R.version$major, R.version$minor))
cat(sprintf("Library   : %s\n\n", .libPaths()[1]))

PKG_DIR     <- file.path(CLIMPACT_RACINE, "server", "pcic_packages")
REPO_CRAN   <- "https://cran.rstudio.com"
REPO_POSIT  <- "https://packagemanager.posit.co/cran/2025-04-01"  # avant archivage
SAVE_REPOS  <- getOption("repos")

# ------------------------------------------------------------------------------
# Helper : tester l'acces a un repo
# ------------------------------------------------------------------------------
test_repo <- function(url) {
  tryCatch({
    con <- url(paste0(url, "/src/contrib/PACKAGES"), open = "rt")
    on.exit(close(con))
    readLines(con, n = 1)
    TRUE
  }, error = function(e) FALSE)
}

# ==============================================================================
# 1) PACKAGES CRAN CLASSIQUES (binaires, install rapide)
# ==============================================================================

deps_cran <- c(
  "terra", "lubridate", "ncdf4", "SPEI", "snow", "udunits2", "functional",
  "proj4", "abind", "sf", "ggplot2", "dplyr", "gridExtra", "matrixStats"
)

cat(sprintf("\n=== ETAPE 1/3 : %d packages CRAN classiques ===\n", length(deps_cran)))
options(repos = c(CRAN = REPO_CRAN))
manquants <- deps_cran[!sapply(deps_cran, requireNamespace, quietly = TRUE)]
if (length(manquants) > 0) {
  cat(sprintf("A installer (%d) : %s\n", length(manquants),
              paste(manquants, collapse = ", ")))
  install.packages(manquants)
} else {
  cat("Tous deja installes.\n")
}
manquants <- deps_cran[!sapply(deps_cran, requireNamespace, quietly = TRUE)]
if (length(manquants) > 0) {
  stop("Echec install CRAN : ", paste(manquants, collapse = ", "),
       "\nVerifier connexion / proxy.")
}
cat("[OK] Tous les packages CRAN classiques installes.\n")

# ==============================================================================
# 2) PACKAGES ARCHIVES DE CRAN -> via Posit (binaires) ou tarballs locaux (source)
#    PCICt, ncdf4.helpers, climdex.pcic ont ete archives le 2025-05-03.
# ==============================================================================

deps_archived <- c("PCICt", "ncdf4.helpers", "climdex.pcic")

cat(sprintf("\n=== ETAPE 2/3 : %d packages archives de CRAN ===\n", length(deps_archived)))
deja_installes <- deps_archived[sapply(deps_archived, requireNamespace, quietly = TRUE)]
a_installer    <- setdiff(deps_archived, deja_installes)
if (length(deja_installes) > 0) {
  cat(sprintf("Deja installes : %s\n", paste(deja_installes, collapse = ", ")))
}

if (length(a_installer) > 0) {
  cat(sprintf("A installer : %s\n", paste(a_installer, collapse = ", ")))

  # -- Tentative 1 : Posit Public Package Manager (binaires, pas besoin Rtools)
  cat(sprintf("\n[Tentative 1/3] Binaires depuis Posit (snapshot %s)...\n",
              sub(".*cran/", "", REPO_POSIT)))
  if (test_repo(REPO_POSIT)) {
    options(repos = c(CRAN = REPO_POSIT))
    tryCatch(install.packages(a_installer),
             error = function(e) cat(sprintf("  [WARN] %s\n", conditionMessage(e))))
  } else {
    cat("  [WARN] Posit indisponible, on saute.\n")
  }

  # -- Tentative 2 : binaire .zip pre-compile sur CALCULUS (pour climdex.pcic
  #    qui n'a pas de binaire CRAN/Posit)
  manquants <- a_installer[!sapply(a_installer, requireNamespace, quietly = TRUE)]
  if (length(manquants) > 0) {
    cat(sprintf("\n[Tentative 2/3] Binaires pre-compiles (zips Windows) ...\n"))
    binaires_locaux <- c(
      `climdex.pcic`  = "climdex.pcic_1.1-11_win-binary.zip"
    )
    for (nom_pkg in intersect(manquants, names(binaires_locaux))) {
      f_zip <- file.path(PKG_DIR, binaires_locaux[[nom_pkg]])
      if (!file.exists(f_zip)) {
        cat(sprintf("  [SKIP] binaire .zip introuvable pour %s\n", nom_pkg)); next
      }
      unlink(file.path(.libPaths()[1], paste0("00LOCK-", nom_pkg)), recursive = TRUE)
      cat(sprintf("  Extraction %s depuis %s ...\n", nom_pkg, basename(f_zip)))
      tryCatch(unzip(f_zip, exdir = .libPaths()[1]),
               error = function(e) cat(sprintf("    [ERR] %s\n", conditionMessage(e))))
    }
  }

  # -- Tentative 3 : tarballs locaux (source, necessite Rtools)
  manquants <- a_installer[!sapply(a_installer, requireNamespace, quietly = TRUE)]
  if (length(manquants) > 0) {
    cat(sprintf("\n[Tentative 3/3] Tarballs locaux source (necessite Rtools)...\n"))
    tarballs_locaux <- c(
      PCICt           = "PCICt_0.5-4.4.tar.gz",
      `ncdf4.helpers` = "ncdf4.helpers_0.3-7.tar.gz",
      `climdex.pcic`  = "climdex.pcic_1.1-11.tar.gz"
    )
    for (nom_pkg in manquants) {
      f_tar <- file.path(PKG_DIR, tarballs_locaux[[nom_pkg]])
      if (!file.exists(f_tar)) {
        cat(sprintf("  [SKIP] tarball local introuvable pour %s\n", nom_pkg)); next
      }
      unlink(file.path(.libPaths()[1], paste0("00LOCK-", nom_pkg)), recursive = TRUE)
      cat(sprintf("  Install %s depuis %s ...\n", nom_pkg, basename(f_tar)))
      tryCatch(install.packages(f_tar, repos = NULL, type = "source"),
               error = function(e) cat(sprintf("    [ERR] %s\n", conditionMessage(e))))
    }
  }

  # Verification finale
  manquants <- deps_archived[!sapply(deps_archived, requireNamespace, quietly = TRUE)]
  if (length(manquants) > 0) {
    cat("\n", strrep("!", 70), "\n", sep = "")
    cat("ECHEC : packages encore manquants : ", paste(manquants, collapse = ", "), "\n",
        sep = "")
    cat("Causes possibles :\n")
    cat("  - Rtools non installe (necessaire pour compiler les .tar.gz)\n")
    cat("    -> https://cran.r-project.org/bin/windows/Rtools/rtools43/\n")
    cat("  - Reseau bloque vers Posit\n")
    cat("    -> verifier proxy / firewall\n")
    cat(strrep("!", 70), "\n", sep = "")
    options(repos = SAVE_REPOS)
    stop("Installation incomplete")
  }
}
cat("[OK] Tous les packages archives installes.\n")

# Restaurer le repo CRAN classique
options(repos = c(CRAN = REPO_CRAN))

# ==============================================================================
# 3) PACKAGE PRINCIPAL : climdex.pcic.ncdf (depuis le tarball Climpact local)
# ==============================================================================

cat("\n=== ETAPE 3/3 : climdex.pcic.ncdf (Climpact) ===\n")
if (requireNamespace("climdex.pcic.ncdf", quietly = TRUE)) {
  cat("[SKIP] climdex.pcic.ncdf deja installe\n")
} else {
  unlink(file.path(.libPaths()[1], "00LOCK-climdex.pcic.ncdf"), recursive = TRUE)
  f_tar <- file.path(PKG_DIR, "climdex.pcic.ncdf.climpact.tar.gz")
  if (!file.exists(f_tar)) stop("Tarball Climpact introuvable : ", f_tar)
  cat(sprintf("Installation depuis %s ...\n", basename(f_tar)))
  install.packages(f_tar, repos = NULL, type = "source")
  if (!requireNamespace("climdex.pcic.ncdf", quietly = TRUE)) {
    stop("Echec installation climdex.pcic.ncdf - voir log d'install")
  }
  cat("[OK] climdex.pcic.ncdf installe\n")
}

# ==============================================================================
# TEST FINAL
# ==============================================================================

cat(sprintf("\n%s\n  TEST FINAL\n%s\n", strrep("=", 70), strrep("=", 70)))
suppressPackageStartupMessages({
  library(terra)
  library(lubridate)
  library(climdex.pcic.ncdf)
})

a_verifier <- c("terra", "lubridate", "ncdf4", "SPEI", "PCICt", "snow", "udunits2",
                "functional", "proj4", "abind", "sf", "ggplot2", "dplyr",
                "gridExtra", "climdex.pcic", "ncdf4.helpers", "climdex.pcic.ncdf")
for (p in a_verifier) {
  ok <- requireNamespace(p, quietly = TRUE)
  cat(sprintf("  %-22s %s  v%s\n", p, if (ok) "[OK]" else "[KO]",
              if (ok) as.character(packageVersion(p)) else "?"))
}

cat(sprintf("\n%s\n  MACHINE PRETE POUR ECE - %s\n%s\n",
            strrep("=", 70), Sys.info()[["nodename"]], strrep("=", 70)))
