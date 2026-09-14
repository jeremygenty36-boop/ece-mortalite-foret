# source("S:/Projets/stage_JeremyG/4-Travail_bis/4-Modeles/1-Mortalite/1-Modele_mortalite_optimise.R")
# ==============================================================================
# MODELE GLM MORTALITE -- PARALLELISME PAR ESPECE
#
#   Structure : 1 worker PSOCK par espece (max 8 workers simultanees).
#   Chaque worker :
#     - recoit ses donnees pre-filtrees (pas de d_raw dans les workers)
#     - boucle sur les 6 bases climatiques (sequentiel)
#     - tourne N_ITER=1000 iterations par base (sequentiel)
#
#   Avantages vs version combo-level (48 workers) :
#     + Serialisation minimale : seul plac_b par espece envoye aux workers
#     + Chaque worker entierement autonome ; crash d'une espece n'affecte pas
#       les autres
#     + Organisation naturelle par espece pour la collecte des resultats
#
#   Inconvenient vs combo-level :
#     - N'utilise que 8/72 coeurs (6x moins parallele)
#     - Desequilibre de charge : QURO (~16000 plac) finit bien apres PINI (~1100)
#
#   AUC et Sensibilite par trapeze/Youden (sans pROC, ~15x plus rapide).
#   Sorties identiques a la version originale (memes CSV, meme structure).
#
#   FLAGS avant source() :
#     RUN_TAG       <- "Mortalite_1989-2024_r075"  # dossier de sortie
#     N_PARALLEL    <- 8        # nb workers (<=8, un par espece)
#     ESPECES_ONLY  <- "QURO"  # filtre espece (vecteur ou scalaire)
#     BASES_ONLY    <- c("CHE1","SAF8")
#     BASES_EXCLUDE <- "SAFDS"
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(MLmetrics)
  library(parallel)
})

# --- CHEMINS ------------------------------------------------------------------
if (!exists(".PFX")) .PFX <- if (dir.exists("S:/Projets")) "S:" else "/Volumes/_donnees"
# F_IFN surchargeable : permet de modeliser une variante d'extraction des
# placettes (base dominants, essence pure...) sans toucher au coeur.
if (!exists("F_IFN"))
  F_IFN <- file.path(.PFX, "Projets/stage_JeremyG/3-Donnees/6-IFN/IFN_placette.csv")
if (!exists("RUN_TAG")) RUN_TAG <- "Mortalite_1989-2024_r070"
.VARIANTE_DIR <- if (grepl("_dominants$", RUN_TAG)) "dominants" else if (grepl("_domines$", RUN_TAG)) "domines" else if (grepl("_pur080$", RUN_TAG)) "pur080" else "standard"  # niveau jeu de donnees (cf 6-Extraction_bases_variantes.R)
DIR_OUT  <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/5-Modeles", .VARIANTE_DIR, RUN_TAG)
DIR_ITER <- file.path(DIR_OUT, "1-Iterations")
DIR_SYN  <- file.path(DIR_OUT, "2-Syntheses")
DIR_PRED <- file.path(DIR_OUT, "3-Predictions")
DIR_PROG <- file.path(DIR_OUT, "_progression")   # 1 fichier par espece : avancement live (detecter un blocage)
for (.d in c(DIR_OUT, DIR_ITER, DIR_SYN, DIR_PRED, DIR_PROG))
  dir.create(.d, showWarnings = FALSE, recursive = TRUE)

# --- PARAMETRES ---------------------------------------------------------------
if (!exists("N_ITER")) N_ITER <- 1000
PROP_CAL   <- 0.70
PVAL_SEUIL <- 0.01
if (!exists("COR_SEUIL")) COR_SEUIL <- 0.70   # -> r070 dans le nom du run
# Forme de la reponse quadratique (facon Helene : echantillonnage de la courbe ajustee sur
# une grille de percentiles, sans calcul de sommet -> on ne regarde la courbe que la ou il y a
# des donnees). Codes : "+"/"-" monotone, "U" creux interieur, "n" bosse interieure (cf fn_forme).
if (!exists("PROBS_FORME")) PROBS_FORME <- seq(0.1, 0.9, by = 0.1)
if (!exists("TOL_FORME"))   TOL_FORME   <- 0.05  # proeminence min. de l'extremum interieur (frac. de l'amplitude)
if (!exists("SEUIL_FORME")) SEUIL_FORME <- 0.5   # frac. min. d'iterations pour retenir U/n (sinon repli sur le signe)
PROP_G_MIN <- 0
N_ANS      <- 10L
if (!exists("N_PARALLEL"))
  N_PARALLEL <- min(8L, max(1L, parallel::detectCores() - 2L))

# --- ESPECES ------------------------------------------------------------------
ESPECES <- list(
  list(code = "QUPE", label = "Quercus petraea",         pattern = "Quercus petraea"),
  list(code = "PISY", label = "Pinus sylvestris",         pattern = "Pinus sylvestris"),
  list(code = "ABAL", label = "Abies alba",               pattern = "Abies alba"),
  list(code = "QURO", label = "Quercus robur",            pattern = "Quercus robur"),
  list(code = "BEPE", label = "Betula pendula",           pattern = "Betula pendula"),
  list(code = "PIAB", label = "Picea abies",              pattern = "Picea abies"),
  list(code = "PINI", label = "Pinus nigra subsp. nigra", pattern = "Pinus nigra subsp. nigra"),
  list(code = "FASY", label = "Fagus sylvatica",          pattern = "Fagus sylvatica")
)

# --- BASES --------------------------------------------------------------------
if (!exists("BASES") || is.null(BASES)) {
  BASES <- list(
    list(code = "EOB10", label = "EOB-10"),
    list(code = "SAF8",  label = "SAF-8"),
    list(code = "CHE1",  label = "CHE-1"),
    list(code = "EOBDS", label = "EOB-DS"),
    list(code = "SAFDS", label = "SAF-DS"),
    list(code = "CHEDS", label = "CHE-C")
  )
}

.alias_bases <- c(EOBS="EOB10", SAFRAN="SAF8", CHELSA="CHE1",
                  DIGI_EOBS="EOBDS", DIGI_SAF="SAFDS", DIGI_CHEL="CHEDS")
.norm_base <- function(x) { y <- .alias_bases[x]; unname(ifelse(is.na(y), x, y)) }
if (exists("ESPECES_ONLY"))
  ESPECES <- Filter(function(e) e$code %in% ESPECES_ONLY, ESPECES)
if (exists("BASES_ONLY"))
  BASES <- Filter(function(b) b$code %in% .norm_base(BASES_ONLY), BASES)
if (exists("BASES_EXCLUDE"))
  BASES <- Filter(function(b) !(b$code %in% .norm_base(BASES_EXCLUDE)), BASES)
stopifnot(length(BASES) > 0L)

INDICES   <- c("TXx", "TNn", "SPEI6", "WG10P", "HWN", "CWN")
if (!exists("INDICES_AUTORISES")) INDICES_AUTORISES <- INDICES
if (!exists("VAR_FIXES")) VAR_FIXES <- c("pH", "G_ha_tot", "Gini", "c13_moy_sp", "prop_G")

# Mode de reponse : "binomial" = cbind(morts, vivants) par arbre (historique, defaut) ;
#   "binaire" = placette morte des qu'au moins un arbre de l'essence est mort (facon Helene/Carletti).
if (!exists("MODE_REPONSE")) MODE_REPONSE <- "binomial"
stopifnot(MODE_REPONSE %in% c("binomial", "binaire"))
.lhs_reponse <- if (MODE_REPONSE == "binaire") "mort_bin" else "cbind(n_mort_sp, n_tiges - n_mort_sp)"

formule_fixe_str <- paste0(
  .lhs_reponse, " ~ ",
  paste(sapply(VAR_FIXES, function(v) paste0(v, " + I(", v, "^2)")),
        collapse = " + "))
FORMULE_FIXE <- as.formula(formule_fixe_str)
cat(sprintf("  MODE_REPONSE = %s | reponse = %s\n", MODE_REPONSE, .lhs_reponse))

cat(strrep("=", 70), "\n", sep = "")
cat("  MODELE MORTALITE -- PARALLELISME PAR ESPECE\n")
cat(sprintf("  %s\n", format(Sys.time())))
cat(sprintf("  RUN_TAG    = %s\n", RUN_TAG))
cat(sprintf("  F_IFN      = %s\n", basename(F_IFN)))
cat(sprintf("  N_ITER=%d | N_PARALLEL=%d | PROP_CAL=%.0f%%\n",
            N_ITER, N_PARALLEL, 100 * PROP_CAL))
cat(sprintf("  PROP_G_MIN=%.0f%% | COR_SEUIL=%.2f | N_ANS=%d\n",
            100 * PROP_G_MIN, COR_SEUIL, N_ANS))
cat(sprintf("  Especes (%d) : %s\n",
            length(ESPECES), paste(vapply(ESPECES, `[[`, "", "code"), collapse = ", ")))
cat(sprintf("  Bases   (%d) : %s\n",
            length(BASES),   paste(vapply(BASES,   `[[`, "", "code"), collapse = ", ")))
cat(sprintf("  VAR_FIXES = %s\n", paste(VAR_FIXES, collapse = ", ")))
cat(sprintf("  INDICES_AUTORISES = %s\n",
            if (length(INDICES_AUTORISES) == 0L) "(aucun)"
            else paste(INDICES_AUTORISES, collapse = ", ")))
cat(sprintf("  Periode campagne : %s - %s\n",
            if (exists("CAMPAGNE_MIN")) as.character(CAMPAGNE_MIN) else "debut",
            if (exists("CAMPAGNE_MAX")) as.character(CAMPAGNE_MAX) else "fin"))
cat(sprintf("  FILTRE_GRECO : %s\n",
            if (exists("FILTRE_GRECO") && !is.null(FILTRE_GRECO))
              paste(FILTRE_GRECO, collapse = "/") else "aucun (toutes zones)"))
cat(strrep("=", 70), "\n\n", sep = "")

# --- LECTURE IFN --------------------------------------------------------------
cat("Lecture IFN...\n")
d_raw <- fread(F_IFN, sep = ";")
cat(sprintf("  %d lignes, %d colonnes\n", nrow(d_raw), ncol(d_raw)))

n_av <- nrow(d_raw)
if ("dep" %in% names(d_raw)) {
  idx_c <- d_raw[, which(dep %in% c("2A", "2B"))]; crit <- "dep 2A/2B"
} else if (all(c("lon", "lat") %in% names(d_raw))) {
  idx_c <- d_raw[, which(lon > 8.5 & lat < 43.1)]; crit <- "boite lon/lat"
} else { idx_c <- integer(0); crit <- "aucun critere" }
if (length(idx_c) > 0L) d_raw <- d_raw[-idx_c]
cat(sprintf("Exclusion Corse (%s) : %d -> %d lignes\n", crit, n_av, nrow(d_raw)))

# filtre par zone GRECO (ex. montagne : c("D","E","G","H","I"))
if (exists("FILTRE_GRECO") && !is.null(FILTRE_GRECO) && "GRECO" %in% names(d_raw)) {
  n_av <- nrow(d_raw); d_raw <- d_raw[GRECO %in% FILTRE_GRECO]
  cat(sprintf("Filtre GRECO (%s) : %d -> %d lignes\n",
              paste(FILTRE_GRECO, collapse = "/"), n_av, nrow(d_raw)))
}

# filtre par annee de campagne (ex. 2015-2024)
if (exists("CAMPAGNE_MIN") && !is.null(CAMPAGNE_MIN) && "campagne" %in% names(d_raw)) {
  n_av <- nrow(d_raw); d_raw <- d_raw[campagne >= CAMPAGNE_MIN]
  cat(sprintf("Filtre campagne >= %d : %d -> %d lignes\n", CAMPAGNE_MIN, n_av, nrow(d_raw)))
}
if (exists("CAMPAGNE_MAX") && !is.null(CAMPAGNE_MAX) && "campagne" %in% names(d_raw)) {
  n_av <- nrow(d_raw); d_raw <- d_raw[campagne <= CAMPAGNE_MAX]
  cat(sprintf("Filtre campagne <= %d : %d -> %d lignes\n", CAMPAGNE_MAX, n_av, nrow(d_raw)))
}
cat("\n")

# ==============================================================================
# FONCTIONS (exportees aux workers via clusterExport)
# ==============================================================================

auc_trapeze <- function(obs, pred) {
  if (length(unique(obs)) < 2L || all(is.na(pred))) return(NA_real_)
  ord   <- order(pred, decreasing = TRUE)
  obs_s <- as.integer(obs[ord])
  n_pos <- sum(obs_s); n_neg <- length(obs_s) - n_pos
  if (n_pos == 0L || n_neg == 0L) return(NA_real_)
  tp  <- cumsum(obs_s); fp <- seq_along(obs_s) - tp
  fpr <- c(0, fp / n_neg, 1L); tpr <- c(0, tp / n_pos, 1L)
  sum(diff(fpr) * (head(tpr, -1) + tail(tpr, -1)) / 2)
}

youden_metrics <- function(obs, pred) {
  na_r <- c(sens=NA_real_, spec=NA_real_, tss=NA_real_, kappa=NA_real_, acc=NA_real_)
  if (length(unique(obs)) < 2L || all(is.na(pred))) return(na_r)
  ord   <- order(pred, decreasing = TRUE)
  obs_s <- as.integer(obs[ord])
  n_pos <- sum(obs_s); n_neg <- length(obs_s) - n_pos
  if (n_pos == 0L || n_neg == 0L) return(na_r)
  N   <- n_pos + n_neg
  tp  <- cumsum(obs_s); fp <- seq_along(obs_s) - tp
  fn  <- n_pos - tp;    tn  <- n_neg - fp
  tpr <- tp / n_pos;    tnr <- tn / n_neg
  idx    <- which.max(tpr + tnr)
  tp_i   <- tp[idx]; fp_i <- fp[idx]; fn_i <- fn[idx]; tn_i <- tn[idx]
  sens_i <- tp_i / n_pos
  spec_i <- tn_i / n_neg
  tss_i  <- sens_i + spec_i - 1
  po     <- (tp_i + tn_i) / N
  pe     <- ((tp_i + fn_i)/N) * ((tp_i + fp_i)/N) +
            ((tn_i + fp_i)/N) * ((tn_i + fn_i)/N)
  kap_i  <- if (abs(1 - pe) < 1e-10) NA_real_ else (po - pe) / (1 - pe)
  c(sens  = round(sens_i, 3L),
    spec  = round(spec_i, 3L),
    tss   = round(tss_i,  3L),
    kappa = round(kap_i,  3L),
    acc   = round(po,     3L))
}

fn_excl_cor <- function(base_cal, v_sel, candidats) {
  ref  <- base_cal[[v_sel]]; excl <- character(0)
  for (v in candidats) {
    cr <- suppressWarnings(cor(base_cal[[v]], ref, use = "complete.obs", method = "pearson"))
    if (!is.na(cr) && abs(cr) > COR_SEUIL) excl <- c(excl, v)
  }
  excl
}

fn_test_candidats <- function(base_cal, formule_courante, candidats) {
  if (length(candidats) == 0L) return(NULL)
  m_null <- glm(formule_courante, family = binomial(link = "cloglog"),
                data = base_cal, na.action = na.exclude)
  res <- lapply(candidats, function(v) {
    f_test <- update(formule_courante,
                     as.formula(paste0("~ . + ", v, " + I(", v, "^2)")))
    m_test <- tryCatch(
      suppressWarnings(glm(f_test, family = binomial(link = "cloglog"),
                           data = base_cal, na.action = na.exclude)),
      error = function(e) NULL)
    if (is.null(m_test))
      return(data.frame(variable = v, BIC = NA_real_, pval = NA_real_))
    pv <- tryCatch(
      as.numeric(anova(m_test, m_null, test = "Chisq")[["Pr(>Chi)"]][2]),
      error = function(e) NA_real_)
    data.frame(variable = v, BIC = BIC(m_test), pval = pv)
  })
  rbindlist(res)
}

fn_ri <- function(glm_full, formule_full, base_cal, vars_in) {
  dev_full <- deviance(glm_full); null_dev <- glm_full$null.deviance
  sapply(vars_in, function(v) {
    f_d <- update(formule_full, as.formula(paste0("~ . - ", v, " - I(", v, "^2)")))
    m_d <- tryCatch(suppressWarnings(glm(f_d, family = binomial(link = "cloglog"),
                    data = base_cal, na.action = na.exclude)), error = function(e) NULL)
    if (is.null(m_d)) NA_real_ else 100 * (deviance(m_d) - dev_full) / null_dev
  })
}

fn_dir <- function(glm_full, base_cal, predicteurs) {
  mu <- as.data.frame(as.list(sapply(predicteurs,
                       function(p) mean(base_cal[[p]], na.rm = TRUE))))
  sapply(predicteurs, function(v) {
    q  <- quantile(base_cal[[v]], c(0.1, 0.9), na.rm = TRUE)
    nd <- mu[c(1, 1), , drop = FALSE]; nd[[v]] <- q
    p  <- tryCatch(predict(glm_full, nd, type = "response"), error = function(e) c(NA, NA))
    as.numeric(p[2] - p[1])
  })
}

# Forme de la courbe de reponse, facon Helene : on predit la mortalite sur la grille de
# percentiles (autres variables a leur moyenne) et on classe la forme la ou il y a des donnees.
#   "+"/"-" monotone ; "U" creux interieur ; "n" bosse interieure (extremum > TOL_FORME de l'amplitude).
fn_forme <- function(glm_full, base_cal, predicteurs) {
  mu <- as.data.frame(as.list(sapply(predicteurs,
                       function(p) mean(base_cal[[p]], na.rm = TRUE))))
  vapply(predicteurs, function(v) {
    qs <- quantile(base_cal[[v]], PROBS_FORME, na.rm = TRUE)
    nd <- mu[rep(1L, length(qs)), , drop = FALSE]; nd[[v]] <- qs
    y  <- tryCatch(predict(glm_full, nd, type = "response"),
                   error = function(e) rep(NA_real_, length(qs)))
    if (anyNA(y)) return(NA_character_)
    rng <- max(y) - min(y); if (rng <= 0) return(NA_character_)
    n <- length(y); imin <- which.min(y); imax <- which.max(y)
    lo <- min(y[1L], y[n]); hi <- max(y[1L], y[n])
    dip  <- if (imin > 1L && imin < n) (lo - y[imin]) / rng else 0   # creux sous les deux bornes
    bump <- if (imax > 1L && imax < n) (y[imax] - hi) / rng else 0   # bosse au-dessus des deux bornes
    if (bump > TOL_FORME && bump >= dip) return("n")
    if (dip  > TOL_FORME && dip  >  bump) return("U")
    if (y[n] >= y[1L]) "+" else "-"
  }, character(1))
}

# ==============================================================================
# FONCTION PAR ESPECE
#   esp_data = list(esp, bases=list(base_code -> list(base, plac_b, ece_present,
#              base_idx)), esp_idx)
#   Retourne une liste nommee par base_code, chaque element = resultats 1 combo.
#   Note : cat() dans les workers n'est pas visible en mode parallele PSOCK.
# ==============================================================================
run_espece <- function(esp_data) {
  esp        <- esp_data$esp
  result_esp <- list()

  for (b_code in names(esp_data$bases)) {
    bdata       <- esp_data$bases[[b_code]]
    base        <- bdata$base
    plac_b      <- bdata$plac_b
    ece_present <- bdata$ece_present
    cand_all    <- c(VAR_FIXES, ece_present)

    # Seed deterministe par (espece, base) -> reproductible au re-run
    set.seed(42L + esp_data$esp_idx * 100L + bdata$base_idx)

    .t_b <- Sys.time(); .hb <- max(1L, N_ITER %/% 5L)   # battement de progression : 5x par base
    .prog <- function(txt) { cat(txt, "\n"); try(writeLines(txt, file.path(DIR_PROG, paste0(esp$code, ".txt"))), silent = TRUE) }
    .prog(sprintf("[%-4s x %-5s] start (%d placettes)  %s", esp$code, b_code, nrow(plac_b), format(Sys.time(), "%H:%M:%S")))

    res_iter   <- vector("list", N_ITER)
    ri_list    <- vector("list", N_ITER)
    dir_list   <- vector("list", N_ITER)
    forme_list <- vector("list", N_ITER)
    pred_last  <- NULL

    for (iter in seq_len(N_ITER)) {
      if (iter %% .hb == 0L)
        .prog(sprintf("[%-4s x %-5s] %d/%d  (%.0fs)  %s", esp$code, b_code, iter, N_ITER,
                      as.numeric(difftime(Sys.time(), .t_b, units = "secs")), format(Sys.time(), "%H:%M:%S")))
      idx_cal  <- sample(nrow(plac_b), floor(PROP_CAL * nrow(plac_b)), replace = FALSE)
      base_cal <- plac_b[idx_cal]
      base_val <- plac_b[-idx_cal]

      glm_fixe <- suppressWarnings(
        glm(FORMULE_FIXE, family = binomial(link = "cloglog"),
            data = base_cal, na.action = na.exclude))
      BIC_courant      <- BIC(glm_fixe)
      formule_courante <- FORMULE_FIXE
      glm_courant      <- glm_fixe
      vars_sel         <- character(0)
      vars_excl        <- character(0)

      # Selection forward par BIC + filtre correlation
      candidats <- ece_present
      repeat {
        a_tester <- setdiff(candidats, c(vars_sel, vars_excl))
        if (length(a_tester) == 0L) break
        step <- fn_test_candidats(base_cal, formule_courante, a_tester)
        if (is.null(step) || nrow(step) == 0L) break
        step_ok <- step[!is.na(step$pval) & step$pval <= PVAL_SEUIL & !is.na(step$BIC), ]
        if (nrow(step_ok) == 0L) break
        step_ok <- step_ok[order(step_ok$BIC), ]
        best    <- step_ok[1L, ]
        if (best$BIC >= BIC_courant) break
        BIC_courant      <- best$BIC
        v_ajout          <- best$variable
        vars_sel         <- c(vars_sel, v_ajout)
        formule_courante <- update(formule_courante,
                                    as.formula(paste0("~ . + ", v_ajout, " + I(", v_ajout, "^2)")))
        glm_courant <- suppressWarnings(
          glm(formule_courante, family = binomial(link = "cloglog"),
              data = base_cal, na.action = na.exclude))
        vars_excl <- c(vars_excl, fn_excl_cor(base_cal, v_ajout, a_tester))
      }

      pred_val <- tryCatch(
        predict(glm_courant, newdata = base_val, type = "response"),
        error = function(e) rep(NA_real_, nrow(base_val)))

      obs_bin  <- as.integer(base_val$n_mort_sp > 0)
      # binaire : p est deja au niveau placette -> pas de conversion ; binomial : proba d'au moins un mort
      pred_bin <- if (MODE_REPONSE == "binaire") pred_val else 1 - (1 - pred_val)^base_val$n_tiges
      obs_rate <- if (MODE_REPONSE == "binaire") as.numeric(obs_bin) else base_val$prop_mort_sp

      auc_val   <- auc_trapeze(obs_bin, pred_bin)
      yd_m      <- youden_metrics(obs_bin, pred_bin)
      sens_val  <- unname(yd_m["sens"])
      spec_val  <- unname(yd_m["spec"])
      tss_val   <- unname(yd_m["tss"])
      kappa_val <- unname(yd_m["kappa"])
      acc_val   <- unname(yd_m["acc"])
      prauc_val <- tryCatch(
        as.numeric(MLmetrics::PRAUC(y_pred = pred_bin, y_true = obs_bin)),
        error = function(e) NA_real_)
      cor_val  <- tryCatch(cor(obs_rate, pred_val, use = "complete.obs"),
                           error = function(e) NA_real_)
      rmse_val <- sqrt(mean((obs_rate - pred_val)^2, na.rm = TRUE))

      d2_global <- 1 - glm_courant$deviance / glm_courant$null.deviance
      d2pct_ece <- if (length(vars_sel) > 0L)
        round(100 * (glm_fixe$deviance - glm_courant$deviance) /
                glm_courant$null.deviance, 1) else 0

      ri_v    <- fn_ri(glm_courant, formule_courante, base_cal, c(VAR_FIXES, vars_sel))
      ri_full <- setNames(numeric(length(cand_all)), cand_all); ri_full[names(ri_v)] <- ri_v
      ri_list[[iter]] <- ri_full

      dir_v    <- fn_dir(glm_courant, base_cal, c(VAR_FIXES, vars_sel))
      dir_full <- setNames(rep(NA_real_, length(cand_all)), cand_all)
      dir_full[names(dir_v)] <- dir_v
      dir_list[[iter]] <- dir_full

      forme_v    <- fn_forme(glm_courant, base_cal, c(VAR_FIXES, vars_sel))
      forme_full <- setNames(rep(NA_character_, length(cand_all)), cand_all)
      forme_full[names(forme_v)] <- forme_v
      forme_list[[iter]] <- forme_full

      res_iter[[iter]] <- data.table(
        espece       = esp$label,
        esp_code     = esp$code,
        base         = base$label,
        base_code    = base$code,
        iteration    = iter,
        n_cal        = nrow(base_cal),
        n_val        = nrow(base_val),
        n_morts_cal  = sum(base_cal$n_mort_sp),
        n_morts_val  = sum(base_val$n_mort_sp),
        vars_ece     = paste(vars_sel, collapse = ";"),
        n_vars_ece   = length(vars_sel),
        BIC_final    = round(BIC_courant, 1L),
        D2_global    = round(d2_global, 3L),
        D2pct_ece    = d2pct_ece,
        AUC          = round(auc_val,   3L),
        Sensitivity  = sens_val,
        Specificity  = spec_val,
        TSS          = tss_val,
        Kappa        = kappa_val,
        Accuracy     = acc_val,
        PRAUC        = round(prauc_val, 3L),
        COR_obs_pred = round(cor_val,   3L),
        RMSE         = round(rmse_val,  5L)
      )

      if (iter == N_ITER && !any(is.na(pred_bin)) && length(obs_bin) > 0L)
        pred_last <- data.table(idp = base_val$idp, obs = obs_bin, pred = pred_bin)
    }

    result_esp[[b_code]] <- list(
      res_iter   = res_iter,
      ri_list    = ri_list,
      dir_list   = dir_list,
      forme_list = forme_list,
      pred_last  = pred_last,
      esp        = esp,
      base       = base,
      cand_all   = cand_all
    )
  }

  result_esp
}

# ==============================================================================
# PRE-CALCUL PAR ESPECE
#   Filtre + validation avant envoi aux workers.
#   plac_b (donnees de la base) est envoye directement -> pas de d_raw dans workers.
# ==============================================================================
cat("Pre-filtrage par espece...\n")
especes_data <- list()
n_combos_tot <- 0L

for (e_idx in seq_along(ESPECES)) {
  esp   <- ESPECES[[e_idx]]
  d_esp <- d_raw[grepl(esp$pattern, species_name, fixed = FALSE) &
                   presence == 1L & prop_G >= PROP_G_MIN]

  if (nrow(d_esp) == 0L) {
    cat(sprintf("  SKIP %s : aucune placette\n", esp$code)); next
  }

  bases_data <- list()
  for (b_idx in seq_along(BASES)) {
    base        <- BASES[[b_idx]]
    ece_cols    <- paste0(INDICES_AUTORISES, "_", base$code)
    ece_present <- ece_cols[ece_cols %in% names(d_esp)]
    # skip only if ECE cols were expected but none found (not if INDICES_AUTORISES is empty on purpose)
    if (length(ece_present) == 0L && length(INDICES_AUTORISES) > 0L) next

    cols_b <- c("idp", "n_tiges", "n_mort_sp", "prop_mort_sp", VAR_FIXES, ece_present)
    cols_b <- cols_b[cols_b %in% names(d_esp)]
    plac_b <- na.omit(d_esp[, ..cols_b])
    plac_b <- plac_b[n_tiges > 0L]
    plac_b[, mort_bin := as.integer(n_mort_sp > 0L)]   # placette morte si >=1 arbre mort de l'essence

    # minimum d'evenements : placettes mortes en mode binaire, arbres morts en binomial
    n_events <- if (MODE_REPONSE == "binaire") sum(plac_b$mort_bin) else sum(plac_b$n_mort_sp)
    if (nrow(plac_b) < 50L || n_events < 10L) {
      cat(sprintf("  SKIP %s x %s : %d plac / %d %s (minimum non atteint)\n",
                  esp$code, base$code, nrow(plac_b), n_events,
                  if (MODE_REPONSE == "binaire") "placettes mortes" else "morts")); next
    }

    bases_data[[base$code]] <- list(
      base        = base,
      plac_b      = plac_b,
      ece_present = ece_present,
      base_idx    = b_idx
    )
    n_combos_tot <- n_combos_tot + 1L
  }

  if (length(bases_data) == 0L) {
    cat(sprintf("  SKIP %s : aucune base valide\n", esp$code)); next
  }

  especes_data[[esp$code]] <- list(esp = esp, bases = bases_data, esp_idx = e_idx)
  cat(sprintf("  %s : %d bases valides | %d placettes | %d morts (%.1f%%)\n",
              esp$code, length(bases_data), nrow(d_esp),
              sum(d_esp$n_mort_sp > 0, na.rm = TRUE),
              100 * mean(d_esp$n_mort_sp > 0, na.rm = TRUE)))
}

cat(sprintf("\n%d especes | %d combos espece x base\n\n",
            length(especes_data), n_combos_tot))
if (length(especes_data) == 0L) stop("Aucune espece valide -- verifier IFN_placette.csv.")

# ==============================================================================
# CLUSTER PSOCK (1 worker par espece, fallback sequentiel)
# ==============================================================================
.exports <- c("N_ITER", "PROP_CAL", "PVAL_SEUIL", "COR_SEUIL", "VAR_FIXES", "FORMULE_FIXE",
              "MODE_REPONSE",
              "fn_excl_cor", "fn_test_candidats", "fn_ri", "fn_dir", "fn_forme",
              "PROBS_FORME", "TOL_FORME",
              "auc_trapeze", "youden_metrics", "DIR_PROG")
.env_src <- environment()

n_workers <- min(N_PARALLEL, length(especes_data))
cat(sprintf("Cluster PSOCK : tentative avec %d workers (1 par espece)...\n", n_workers))

cl <- tryCatch({
  rscript <- if (.Platform$OS.type == "windows")
    file.path(R.home("bin"), "Rscript.exe") else file.path(R.home("bin"), "Rscript")
  .cl <- makeCluster(n_workers, type = "PSOCK", rscript = rscript, outfile = "")  # outfile="" -> sortie des workers visible (progression)
  clusterEvalQ(.cl, suppressPackageStartupMessages({
    library(data.table)
    library(MLmetrics)
  }))
  clusterExport(.cl, .exports, envir = .env_src)
  cat(sprintf("  Cluster OK (%d workers, Rscript = %s)\n\n", n_workers, rscript))
  .cl
}, error = function(e) {
  cat(sprintf("  makeCluster echoue : %s\n", conditionMessage(e)))
  cat("  -> Fallback sequentiel (calcul correct, sans parallelisme)\n\n")
  NULL
})

t0 <- proc.time()

if (!is.null(cl)) {
  on.exit(stopCluster(cl), add = TRUE)
  cat("Lancement parallele (1 worker par espece)...\n"); flush.console()
  results <- tryCatch(
    parLapply(cl, especes_data, run_espece),
    error = function(e) {
      cat(sprintf("\n!! ERREUR CLUSTER parLapply : %s\n", conditionMessage(e)))
      cat("   -> Basculement en mode sequentiel (calcul correct, sans parallelisme)\n\n")
      flush.console()
      lapply(especes_data, function(ed) {
        cat(sprintf("  -> %s (%d bases)\n", ed$esp$code, length(ed$bases)))
        flush.console()
        run_espece(ed)
      })
    }
  )
} else {
  cat(sprintf("Lancement sequentiel (%d especes)...\n", length(especes_data)))
  flush.console()
  results <- lapply(especes_data, function(ed) {
    cat(sprintf("  -> %s (%d bases)\n", ed$esp$code, length(ed$bases)))
    flush.console()
    run_espece(ed)
  })
}

cat(sprintf("\nCalculs termines en %.0f s\n\n", (proc.time() - t0)[["elapsed"]]))

# ==============================================================================
# COLLECTE ET ECRITURE DES RESULTATS
#   Structure de results : list[esp_code] -> list[base_code] -> (res_iter, ...)
# ==============================================================================
resultats_globaux <- list()
ri_globaux        <- list()

for (esp_results in results) {
  for (b_code in names(esp_results)) {
    res      <- esp_results[[b_code]]
    esp      <- res$esp
    base     <- res$base
    cand_all <- res$cand_all
    key      <- paste(esp$code, base$code, sep = "_")

    res_base <- rbindlist(res$res_iter)
    resultats_globaux[[key]] <- res_base

    if (!is.null(res$pred_last))
      fwrite(res$pred_last,
             file.path(DIR_PRED, sprintf("Predictions_%s_%s.csv", esp$code, base$code)),
             sep = ";")

    .rl <- res$ri_list[!vapply(res$ri_list,  is.null, logical(1))]
    .dl <- res$dir_list[!vapply(res$dir_list, is.null, logical(1))]
    .fl <- res$forme_list[!vapply(res$forme_list, is.null, logical(1))]
    if (length(.rl) > 0L) {
      ri_moy  <- colMeans(do.call(rbind, .rl), na.rm = TRUE)
      ri_abs  <- ri_moy
      s_ri    <- sum(ri_abs, na.rm = TRUE)
      ri_rel  <- if (is.finite(s_ri) && s_ri > 0) 100 * ri_abs / s_ri else ri_abs * NA_real_
      dir_mat <- do.call(rbind, .dl)
      dmort   <- colMeans(dir_mat, na.rm = TRUE)[names(ri_moy)]
      pct_pos <- colMeans(dir_mat > 0, na.rm = TRUE)[names(ri_moy)]
      sens_v  <- fifelse(is.na(dmort), NA_character_, fifelse(dmort > 0, "+", "-"))
      # forme dominante inter-iterations : U/n retenu seulement si frequence >= SEUIL_FORME, sinon le signe
      forme_mat <- if (length(.fl) > 0L) do.call(rbind, .fl) else NULL
      forme_v <- vapply(names(ri_moy), function(v) {
        if (is.null(forme_mat) || !v %in% colnames(forme_mat)) return(unname(sens_v[v]))
        col <- forme_mat[, v]; col <- col[!is.na(col)]
        if (length(col) == 0L) return(unname(sens_v[v]))
        tb <- sort(table(col), decreasing = TRUE)
        if (names(tb)[1L] %in% c("U", "n") && tb[1L] / length(col) >= SEUIL_FORME)
          names(tb)[1L] else unname(sens_v[v])
      }, character(1))
      ri_globaux[[key]] <- data.table(
        espece = esp$label, esp_code = esp$code, base = base$label, base_code = base$code,
        variable          = names(ri_moy),
        RI                = round(as.numeric(ri_rel), 3),
        RI_abs            = round(as.numeric(ri_abs), 3),
        dmort             = round(as.numeric(dmort), 6),
        sens              = sens_v,
        forme             = as.character(forme_v),
        pct_effet_positif = round(100 * as.numeric(pct_pos)))
    }

    fwrite(res_base,
           file.path(DIR_ITER, sprintf("Resultats_%s_%s.csv", esp$code, base$code)),
           sep = ";")
    cat(sprintf("  [OK] %s x %s  AUC=%.3f +/- %.3f | n=%d iter\n",
                esp$code, base$code,
                mean(res_base$AUC, na.rm = TRUE),
                sd(res_base$AUC,   na.rm = TRUE),
                nrow(res_base)))
  }
}

# Synthese par espece
for (esp in ESPECES) {
  keys_esp <- grep(paste0("^", esp$code, "_"), names(resultats_globaux), value = TRUE)
  if (length(keys_esp) == 0L) next
  res_esp_all <- rbindlist(resultats_globaux[keys_esp])
  synth_esp <- res_esp_all[, .(
    AUC_moy       = round(mean(AUC,          na.rm = TRUE), 3),
    AUC_sd        = round(sd(AUC,            na.rm = TRUE), 3),
    PRAUC_moy     = round(mean(PRAUC,        na.rm = TRUE), 3),
    PRAUC_sd      = round(sd(PRAUC,          na.rm = TRUE), 3),
    Sens_moy      = round(mean(Sensitivity,  na.rm = TRUE), 3),
    Spec_moy      = round(mean(Specificity,  na.rm = TRUE), 3),
    TSS_moy       = round(mean(TSS,          na.rm = TRUE), 3),
    TSS_sd        = round(sd(TSS,            na.rm = TRUE), 3),
    Kappa_moy     = round(mean(Kappa,        na.rm = TRUE), 3),
    Kappa_sd      = round(sd(Kappa,          na.rm = TRUE), 3),
    Acc_moy       = round(mean(Accuracy,     na.rm = TRUE), 3),
    Acc_sd        = round(sd(Accuracy,       na.rm = TRUE), 3),
    COR_moy       = round(mean(COR_obs_pred, na.rm = TRUE), 3),
    D2_moy        = round(mean(D2_global,    na.rm = TRUE), 3),
    D2pct_ece_moy = round(mean(D2pct_ece,    na.rm = TRUE), 1),
    ECE_freq      = {
      vs <- unlist(strsplit(vars_ece[vars_ece != ""], ";"))
      if (length(vs) == 0L) NA_character_
      else paste(names(sort(table(vs), decreasing = TRUE)), collapse = ";")
    },
    n_vars_moy = round(mean(n_vars_ece, na.rm = TRUE), 2)
  ), by = .(base, base_code)]
  fwrite(synth_esp[order(-AUC_moy)],
         file.path(DIR_SYN, sprintf("Synthese_%s.csv", esp$code)), sep = ";")
}

# RI global
if (length(ri_globaux) > 0L) {
  ri_all <- rbindlist(ri_globaux)
  fwrite(ri_all, file.path(DIR_SYN, "RI_par_variable.csv"), sep = ";")
  cat(sprintf("\nRI_par_variable.csv : %d lignes\n", nrow(ri_all)))
}

# Synthese globale
if (length(resultats_globaux) > 0L) {
  all_res    <- rbindlist(resultats_globaux)
  synth_glob <- all_res[, .(
    AUC_moy       = round(mean(AUC,          na.rm = TRUE), 3),
    AUC_sd        = round(sd(AUC,            na.rm = TRUE), 3),
    PRAUC_moy     = round(mean(PRAUC,        na.rm = TRUE), 3),
    PRAUC_sd      = round(sd(PRAUC,          na.rm = TRUE), 3),
    Sens_moy      = round(mean(Sensitivity,  na.rm = TRUE), 3),
    Spec_moy      = round(mean(Specificity,  na.rm = TRUE), 3),
    TSS_moy       = round(mean(TSS,          na.rm = TRUE), 3),
    TSS_sd        = round(sd(TSS,            na.rm = TRUE), 3),
    Kappa_moy     = round(mean(Kappa,        na.rm = TRUE), 3),
    Kappa_sd      = round(sd(Kappa,          na.rm = TRUE), 3),
    Acc_moy       = round(mean(Accuracy,     na.rm = TRUE), 3),
    Acc_sd        = round(sd(Accuracy,       na.rm = TRUE), 3),
    COR_moy       = round(mean(COR_obs_pred, na.rm = TRUE), 3),
    D2_moy        = round(mean(D2_global,    na.rm = TRUE), 3),
    D2pct_ece_moy = round(mean(D2pct_ece,    na.rm = TRUE), 1),
    n_plac        = round(mean(n_cal + n_val, na.rm = TRUE)),
    n_morts       = round(mean(n_morts_cal + n_morts_val, na.rm = TRUE))
  ), by = .(espece, esp_code, base, base_code)]

  fwrite(synth_glob[order(espece, -AUC_moy)],
         file.path(DIR_SYN, "Synthese_globale.csv"), sep = ";")

  cat(strrep("=", 70), "\n", sep = "")
  cat("SYNTHESE GLOBALE :\n\n")
  print(synth_glob[order(espece, -AUC_moy),
                    .(espece, base, AUC_moy, AUC_sd, COR_moy, D2_moy, n_plac)])
}

cat(strrep("=", 70), "\n", sep = "")
cat(sprintf("  TERMINE : %s\n", format(Sys.time())))
cat(strrep("=", 70), "\n", sep = "")
