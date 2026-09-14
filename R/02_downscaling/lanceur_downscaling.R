# Lancer depuis le dossier r/ du depot :  source("lanceur_downscaling.R")
# ==============================================================================
# LANCEUR DOWNSCALING - ENCHAINEMENT AUTOMATIQUE DE LA PRODUCTION DES 3 BASES
# Lance les 3 scripts de production les uns apres les autres. En cas d'erreur
# sur un script, le lanceur LOGUE puis continue avec le suivant (log horodate).
#
# Chaque script se lance sans argument : le nombre de workers paralleles est
# AUTO-DETECTE selon la charge CPU/RAM au demarrage (SAFRAN et EOBS).
#
# Production lourde (plusieurs jours sur la periode complete). Les chemins
# d'entree/sortie sont centralises dans config_chemins.R (a adapter).
# ==============================================================================

# Dossier des scripts = repertoire courant (lancer depuis r/).
ROOT_DS  <- getwd()

# ------------------------------------------------------------------------------
# LISTE DES SCRIPTS (commenter/decommenter selon ce qui reste a produire)
# phase : etiquette de log | nom : libelle court | fichier : chemin relatif a ROOT_DS
# ------------------------------------------------------------------------------
SCRIPTS <- list(
  # Un seul script de production par base (cf README).
  list(phase="PROD", nom="SAFRAN (IDW)", fichier="production_SAFRAN_IDW.R"),
  list(phase="PROD", nom="CHELSA",       fichier="production_CHELSA_bilineaire.R"),
  list(phase="PROD", nom="EOBS",         fichier="production_EOBS_bilineaire.R")
)

# ==============================================================================
# Fichier log (horodatage dans le nom)
f_log   <- file.path(ROOT_DS, sprintf("log_lanceur_downscaling_%s.txt",
                                      format(Sys.time(), "%Y%m%d_%H%M%S")))
con_log <- file(f_log, open = "wt")

log <- function(...) {
  msg <- sprintf(...)
  cat(msg, "\n")
  writeLines(msg, con_log)
  flush(con_log)
}

fmt_dur <- function(s) {
  s <- as.numeric(s)
  if (s < 60)   return(sprintf("%.0f s", s))
  if (s < 3600) return(sprintf("%d min %02.0f s", s%/%60, s%%60))
  sprintf("%d h %02d min", s%/%3600, (s%%3600)%/%60)
}

# ==============================================================================

t0_total <- proc.time()[["elapsed"]]
statuts  <- character(length(SCRIPTS))

log("============================================================")
log("  LANCEUR DOWNSCALING  -  debut : %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
log("  Racine  : %s", ROOT_DS)
log("  %d scripts a executer", length(SCRIPTS))
log("============================================================\n")

for (i in seq_along(SCRIPTS)) {
  s     <- SCRIPTS[[i]]
  f_scr <- file.path(ROOT_DS, s$fichier)

  log("\n------------------------------------------------------------")
  log("  [%d/%d] (%s) %s  -  debut : %s",
      i, length(SCRIPTS), s$phase, s$nom, format(Sys.time(), "%H:%M:%S"))
  log("  Fichier : %s", s$fichier)
  log("------------------------------------------------------------")

  if (!file.exists(f_scr)) {
    log("  [!!] SCRIPT INTROUVABLE : %s", f_scr)
    statuts[i] <- "SCRIPT ABSENT"
    next
  }

  t0 <- proc.time()[["elapsed"]]

  resultat <- tryCatch(
    withCallingHandlers(
      { source(f_scr, echo = FALSE, local = FALSE); "OK" },
      warning = function(w) {
        log("  [WARN] %s", conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      log("  [ERREUR] %s", conditionMessage(e))
      paste0("ERREUR : ", conditionMessage(e))
    }
  )

  dur <- proc.time()[["elapsed"]] - t0
  statuts[i] <- if (identical(resultat, "OK")) "OK" else resultat

  log("  --> %s  |  duree : %s", statuts[i], fmt_dur(dur))
}

# ==============================================================================
# BILAN FINAL
# ==============================================================================

dur_tot <- proc.time()[["elapsed"]] - t0_total

log("\n============================================================")
log("  BILAN FINAL  -  fin : %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
log("  Duree totale : %s", fmt_dur(dur_tot))
log("============================================================")
log("  %-16s  %-8s  %s", "Base/etape", "Phase", "Statut")
log("  %s", strrep("-", 50))
for (i in seq_along(SCRIPTS))
  log("  %-16s  %-8s  %s", SCRIPTS[[i]]$nom, SCRIPTS[[i]]$phase, statuts[i])

n_ok  <- sum(statuts == "OK")
n_err <- sum(statuts != "OK")
log("\n  %d/%d OK  |  %d erreur(s)", n_ok, length(SCRIPTS), n_err)
log("  Log sauvegarde : %s", f_log)

close(con_log)
cat(sprintf("\nLog complet : %s\n", f_log))
