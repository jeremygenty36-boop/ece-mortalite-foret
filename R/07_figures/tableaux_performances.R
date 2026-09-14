# source("R/07_figures/tableaux_performances.R")   # depuis la racine du depot
# ==============================================================================
# TABLEAUX DE PERFORMANCES ET D'IR (Tableau I et Tableau A.III du rapport)
#   v1.1 : calcules depuis les syntheses des runs, au lieu d'etre saisis a la main.
#
#   Entrees (surchargeables avant source()) :
#     DIR_MODELES   dossier des runs          (defaut PROJET/5-Resultats/5-Modeles/standard)
#     RUN_PEUPL     run peuplement + sol seul (defaut Mortalite_2015-2023_Peuplement_n1000_binaire)
#     RUN_ECE       run peuplement + ECE      (defaut Mortalite_2015-2023_r070_n1000_binaire)
#     BASES_TAB     bases retenues            (defaut les 5 bases, CHE-C exclue)
#     DIR_TAB       dossier de sortie         (defaut PROJET/5-Resultats/6-Figures et tableaux redaction/3-Resultats)
#
#   Sorties (CSV, separateur ";", decimale ",") :
#     Tableau_I_performances_par_base.csv
#     Tableau_AIII_a_performances_peuplement.csv   (modele peuplement + sol)
#     Tableau_AIII_a_performances_avec_ECE.csv     (modele avec ECE : valeurs imprimees en A.III (a) dans le rapport)
#     Tableau_AIII_b_IR_variables_peuplement.csv
#
#   Ecart-type : ecart-type de population (diviseur n), comme dans le rapport.
#   Moyennes calculees sur les valeurs deja arrondies a 3 decimales des syntheses :
#   ecarts possibles de 0,001 avec un calcul sur les iterations brutes.
#   ASCII pur.
# ==============================================================================

# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
suppressPackageStartupMessages(library(data.table))

if (!exists("DIR_MODELES")) DIR_MODELES <- file.path(PROJET, "5-Resultats", "5-Modeles", "standard")
if (!exists("RUN_PEUPL"))   RUN_PEUPL   <- "Mortalite_2015-2023_Peuplement_n1000_binaire"
if (!exists("RUN_ECE"))     RUN_ECE     <- "Mortalite_2015-2023_r070_n1000_binaire"
if (!exists("BASES_TAB"))   BASES_TAB   <- c(SAF8 = "SAF-8", EOB10 = "EOBS-10", CHE1 = "CHE-1",
                                             SAFDS = "SAF-DS", EOBDS = "EOBS-DS")
if (!exists("DIR_TAB"))     DIR_TAB     <- file.path(PROJET, "5-Resultats", "6-Figures et tableaux redaction", "3-Resultats")
dir.create(DIR_TAB, showWarnings = FALSE, recursive = TRUE)

METRIQUES <- c(AUC = "AUC_moy", prAUC = "PRAUC_moy", Sensibilite = "Sens_moy",
               Specificite = "Spec_moy", TSS = "TSS_moy", Kappa = "Kappa_moy", Succes = "Acc_moy")
VAR_PEUPL <- c(prop_G = "prop_G", c13_moy_sp = "c13_moy_sp", G = "G_ha_tot", Gini = "Gini", pH_sol = "pH")

lire <- function(run, fichier) {
  f <- file.path(DIR_MODELES, run, "2-Syntheses", fichier)
  if (!file.exists(f)) stop("Fichier absent : ", f)
  d <- fread(f)[base_code %in% names(BASES_TAB)]
  if (nrow(d) == 0L) stop("Aucune ligne pour les bases ", paste(names(BASES_TAB), collapse = ", "), " dans ", f)
  d
}
sd_pop <- function(x) sqrt(mean((x - mean(x))^2))
r3     <- function(x) round(x, 3)

sy_p <- lire(RUN_PEUPL, "Synthese_globale.csv")
sy_e <- lire(RUN_ECE,   "Synthese_globale.csv")
ri_p <- lire(RUN_PEUPL, "RI_par_variable.csv")
ri_e <- lire(RUN_ECE,   "RI_par_variable.csv")
cat(sprintf("Runs : %s (%d lignes) | %s (%d lignes)\n", RUN_PEUPL, nrow(sy_p), RUN_ECE, nrow(sy_e)))

# ---- Tableau I : moyenne entre essences, par base ------------------------------
par_base <- function(sy) sy[, lapply(.SD, mean), by = base_code, .SDcols = unname(METRIQUES)]
pb_p <- par_base(sy_p); pb_e <- par_base(sy_e)
tab1 <- rbindlist(lapply(names(BASES_TAB), function(b) {
  ligne <- data.table(Base = BASES_TAB[[b]])
  for (m in names(METRIQUES)) {
    ligne[[paste0(m, "_Peupl")]] <- r3(pb_p[base_code == b][[METRIQUES[[m]]]])
    ligne[[paste0(m, "_ECE")]]   <- r3(pb_e[base_code == b][[METRIQUES[[m]]]])
  }
  ligne
}))
lig_stat <- function(lab, fun) {
  ligne <- data.table(Base = lab)
  for (m in names(METRIQUES)) {
    v <- fun(pb_p[[METRIQUES[[m]]]], pb_e[[METRIQUES[[m]]]])
    ligne[[paste0(m, "_Peupl")]] <- r3(v[1]); ligne[[paste0(m, "_ECE")]] <- r3(v[2])
  }
  ligne
}
tab1 <- rbind(tab1,
  lig_stat("Moyenne toutes bases",                 function(p, e) c(mean(p), mean(e))),
  lig_stat("Ecart max entre bases (max - min)",    function(p, e) c(max(p) - min(p), max(e) - min(e))),
  lig_stat("Difference moyenne ECE - Peupl.",      function(p, e) c(NA, mean(e) - mean(p))),
  lig_stat("Difference max ECE - Peupl. (base)",   function(p, e) c(NA, max(e - p))))
fwrite(tab1, file.path(DIR_TAB, "Tableau_I_performances_par_base.csv"), sep = ";", dec = ",")

# ---- Tableau A.III (a) : moyenne, ecart-type, min, max sur essences x bases -----
stats_perf <- function(sy) rbindlist(lapply(names(METRIQUES), function(m) {
  x <- sy[[METRIQUES[[m]]]]
  data.table(Indicateur = m, Moyenne = r3(mean(x)), Ecart_type = r3(sd_pop(x)), Min = r3(min(x)), Max = r3(max(x)))
}))
fwrite(stats_perf(sy_p), file.path(DIR_TAB, "Tableau_AIII_a_performances_peuplement.csv"), sep = ";", dec = ",")
fwrite(stats_perf(sy_e), file.path(DIR_TAB, "Tableau_AIII_a_performances_avec_ECE.csv"),  sep = ";", dec = ",")

# ---- Tableau A.III (b) : IR des variables de peuplement -------------------------
ir_var <- function(ri, v) ri[variable == v, RI]
tab_b <- rbindlist(lapply(names(VAR_PEUPL), function(lab) {
  x <- ir_var(ri_e, VAR_PEUPL[[lab]])
  data.table(Variable = lab, IR_moy_modele_ECE = round(mean(x), 1), IR_min_modele_ECE = round(min(x), 1),
             IR_max_modele_ECE = round(max(x), 1),
             IR_moy_modele_peuplement = round(mean(ir_var(ri_p, VAR_PEUPL[[lab]])), 1))
}))
sommes <- ri_e[, .(peupl = sum(RI[variable %in% VAR_PEUPL]), ece = sum(RI[!variable %in% VAR_PEUPL])),
               by = .(esp_code, base_code)]
tab_b <- rbind(tab_b,
  data.table(Variable = "Somme IR peuplement", IR_moy_modele_ECE = round(mean(sommes$peupl), 1),
             IR_min_modele_ECE = round(min(sommes$peupl), 1), IR_max_modele_ECE = round(max(sommes$peupl), 1),
             IR_moy_modele_peuplement = 100),
  data.table(Variable = "Somme IR ECE", IR_moy_modele_ECE = round(mean(sommes$ece), 1),
             IR_min_modele_ECE = round(min(sommes$ece), 1), IR_max_modele_ECE = round(max(sommes$ece), 1),
             IR_moy_modele_peuplement = 0))
fwrite(tab_b, file.path(DIR_TAB, "Tableau_AIII_b_IR_variables_peuplement.csv"), sep = ";", dec = ",")

cat("\nTableau I (extrait AUC) :\n"); print(tab1[, .(Base, AUC_Peupl, AUC_ECE)])
cat("\nTableau A.III (a), modele peuplement :\n"); print(stats_perf(sy_p))
cat("\nTableau A.III (a), modele avec ECE :\n");   print(stats_perf(sy_e))
cat("\nTableau A.III (b) :\n"); print(tab_b)
cat(sprintf("\nSorties : %s\n", DIR_TAB))
