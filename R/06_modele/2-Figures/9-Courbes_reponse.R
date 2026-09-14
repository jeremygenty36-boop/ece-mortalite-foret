# source("R/06_modele/2-Figures/9-Courbes_reponse.R")   # depuis la racine du depot
# ============================================================================
# COURBES DE REPONSE du modele de mortalite.
#   Pour chaque espece x base, on REFIT un modele "consensus" sur l'ensemble des
#   placettes : variables fixes + indices ECE RETENUS (RI>0 dans RI_par_variable.csv),
#   GLM binomial cloglog avec termes quadratiques (meme structure que 1-Modele).
#   Puis, pour chaque variable, on predit la mortalite (proba qu'une tige meure)
#   en faisant varier cette variable de son p2.5 a son p97.5, les autres a leur moyenne.
#   -> 1 figure par espece (facettes = indices ECE + prop_G ; 1 courbe par base)
#      + Courbes_reponse.csv (tous les points).
# IMPORTANT : garder VAR_FIXES / PROP_G_MIN / filtre SYNCHRONISES avec 1-Modele_mortalite.R.
# Sorties : 5-Resultats/5-Modeles/Figures/  et  .../Mortalite/Courbes_reponse.csv
# ============================================================================
# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
suppressPackageStartupMessages({ library(data.table); library(ggplot2) })
# .PFX : fourni par config/chemins.R
if (!exists("RUN_TAG")) RUN_TAG <- "Mortalite_2015-2023_r070_n1000_binaire"
.VARIANTE_DIR <- if (grepl("_dominants$", RUN_TAG)) "dominants" else if (grepl("_domines$", RUN_TAG)) "domines" else if (grepl("_pur080$", RUN_TAG)) "pur080" else "standard"  # niveau jeu de donnees (cf 6-Extraction_bases_variantes.R)
if (!exists("F_IFN")) {  # surchargeable ; sinon DEDUIT de la variante (RUN_TAG) -- evite d'utiliser la base standard pour dominants/domines/pur080
  .IFN_FILE <- c(standard="IFN_placette.csv", dominants="IFN_placette_dominants.csv",
                 domines="IFN_placette_domines.csv", pur080="IFN_placette_pur080.csv")[.VARIANTE_DIR]
  F_IFN <- file.path(.PFX, "Projets/stage_JeremyG/3-Donnees/6-IFN", .IFN_FILE)
}
# Zone (GRECO) et campagnes DEDUITES du RUN_TAG si non fournies -- robustesse quand
# appele hors session (0-Figures_variante ne pose pas FILTRE_GRECO/CAMPAGNE) : sinon
# les courbes Montagne/Plaine seraient calculees sur TOUTE la France.
if (!exists("FILTRE_GRECO"))
  FILTRE_GRECO <- if (grepl("Montagne", RUN_TAG)) c("D","E","G","H","I") else
                  if (grepl("Plaine",   RUN_TAG)) c("A","B","C","F","J") else NULL
# v1.1 : periode lue dans RUN_TAG (AAAA-AAAA), sinon 2015-2023
.yy_run <- as.integer(unlist(strsplit(regmatches(RUN_TAG, regexpr("[0-9]{4}-[0-9]{4}", RUN_TAG)), "-")))
if (!exists("CAMPAGNE_MIN")) CAMPAGNE_MIN <- if (length(.yy_run) == 2L) .yy_run[1] else 2015L
if (!exists("CAMPAGNE_MAX")) CAMPAGNE_MAX <- if (length(.yy_run) == 2L) .yy_run[2] else 2023L
DIRM    <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/5-Modeles", .VARIANTE_DIR, RUN_TAG)
DIRM_SY <- file.path(DIRM, "2-Syntheses")
DIRF <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/5-Modeles", .VARIANTE_DIR, RUN_TAG, "Figures", "2-Importance_relative", "Courbes_reponse")
dir.create(DIRF, showWarnings = FALSE, recursive = TRUE)
.run_suffix <- sub("^Mortalite_", "", RUN_TAG)

# --- doit correspondre a 1-Modele_mortalite.R --------------------------------
if (!exists("VAR_FIXES")) VAR_FIXES <- c("pH", "G_ha_tot", "Gini", "c13_moy_sp", "prop_G")
PROP_G_MIN <- 0
NPT        <- 40L     # points par courbe
ESPECES <- list(
  list(code="QURO", label="Quercus robur",    pattern="Quercus robur"),
  list(code="QUPE", label="Quercus petraea",  pattern="Quercus petraea"),
  list(code="FASY", label="Fagus sylvatica",  pattern="Fagus sylvatica"),
  list(code="PISY", label="Pinus sylvestris", pattern="Pinus sylvestris"),
  list(code="PINI", label="Pinus nigra subsp. nigra", pattern="Pinus nigra subsp. nigra"),
  list(code="ABAL", label="Abies alba",       pattern="Abies alba"),
  list(code="PIAB", label="Picea abies",      pattern="Picea abies"),
  list(code="BEPE", label="Betula pendula",   pattern="Betula pendula"))
BASES <- list(
  list(code="EOB10",label="EOB-10"), list(code="SAF8",label="SAF-8"),  list(code="CHE1", label="CHE-1"),
  list(code="EOBDS",label="EOB-DS"), list(code="SAFDS",label="SAF-DS"))  # CHE-C (CHEDS) ecartee de l'analyse
COL_BASE <- c("EOB-10"="#1B9E77","SAF-8"="#D95F02","CHE-1"="#7570B3",
              "EOB-DS"="#66C2A5","SAF-DS"="#FC8D62","CHE-C"="#8DA0CB",
              "Peuplement"="#444444")
ECE_IND <- c("TXx","TNn","SPEI6","WG10P","HWN","CWN")
# variables a tracer (toutes VAR_FIXES + ECE retenus) et libelle d'axe
LAB_VAR <- c(
  pH         = "pH (sol)",
  G_ha_tot   = "G tot (m2/ha)",
  Gini       = "Gini (heterogeneite)",
  c13_moy_sp = "c13 moy sp (cm)",
  prop_G     = "prop G (ST espece)",
  TNn="TNn (<- +froid)", CWN="CWN (+froid ->)",
  TXx="TXx (+chaud ->)", HWN="HWN (+chaud ->)",
  SPEI6="SPEI6 (<- +sec)", WG10P="WG10P (+sec ->)")
ORD_FACET <- c("pH","G_ha_tot","Gini","c13_moy_sp","prop_G","TNn","CWN","TXx","HWN","SPEI6","WG10P")

d_raw <- fread(F_IFN, sep = ";")
ri    <- fread(file.path(DIRM_SY, "RI_par_variable.csv"))
BC    <- sapply(BASES, function(b) b$code)
ri[, indice := gsub(paste0("_(", paste(BC, collapse="|"), ")$"), "", variable)]

# exclusion Corse et filtre campagne (synchronise avec 1-Modele)
if ("dep" %in% names(d_raw)) d_raw <- d_raw[!(dep %in% c("2A","2B"))]
if (exists("CAMPAGNE_MIN") && !is.null(CAMPAGNE_MIN) && "campagne" %in% names(d_raw))
  d_raw <- d_raw[campagne >= CAMPAGNE_MIN]
if (exists("CAMPAGNE_MAX") && !is.null(CAMPAGNE_MAX) && "campagne" %in% names(d_raw))
  d_raw <- d_raw[campagne <= CAMPAGNE_MAX]
if (exists("FILTRE_GRECO") && !is.null(FILTRE_GRECO) && "GRECO" %in% names(d_raw))
  d_raw <- d_raw[GRECO %in% FILTRE_GRECO]

# courbe de reponse d'un modele ajuste : 1 ligne (variable, x, y) par point
courbe_modele <- function(glm_fit, plac, vars_in) {
  mu        <- as.list(sapply(VAR_FIXES, function(p) mean(plac[[p]], na.rm = TRUE)))
  vars_plot <- c(VAR_FIXES, vars_in)                    # toutes variables fixes + ECE retenus
  vars_plot <- vars_plot[vars_plot %in% names(plac)]
  rbindlist(lapply(vars_plot, function(v) {
    rg <- quantile(plac[[v]], c(0.025, 0.975), na.rm = TRUE)
    if (!is.finite(diff(rg)) || diff(rg) == 0) return(NULL)
    xs <- seq(rg[1], rg[2], length.out = NPT)
    nd <- as.data.table(mu)[rep(1L, NPT)]
    for (e in vars_in) if (!e %in% names(nd)) nd[[e]] <- mean(plac[[e]], na.rm = TRUE)
    nd[[v]] <- xs
    y  <- tryCatch(predict(glm_fit, newdata = nd, type = "response"),
                   error = function(e) rep(NA_real_, NPT))
    ind <- sub(paste0("_(", paste(BC, collapse="|"), ")$"), "", v)
    data.table(variable = v, indice = ind, x = xs, y = y)
  }))
}

# --- ajustement ROBUSTE : evite les courbes en "creneaux" (quasi-separation) --
# A faible effectif (peu de morts), un GLM cloglog quadratique peut "separer" :
# la mortalite predite saute a 100% sur une bande (ex. Pinus nigra, 71 morts).
# On detecte la SATURATION du balayage (proba/tige predite > SAT_Y) et on replie
# sur un fit LINEAIRE (monotone, pas de bosse) ; si encore sature, on ECARTE la
# courbe et on le signale en legende. Seuils surchargeables.
SAT_Y <- if (exists("SAT_Y")) SAT_Y else 0.5   # mortalite/tige predite max toleree sur le balayage
.flags <- list()                               # "esp base" -> note affichee en legende
.mk_glm <- function(plac, vars, quad) {
  tt <- if (quad) sapply(vars, function(v) paste0(v, " + I(", v, "^2)")) else vars
  f  <- as.formula(paste("cbind(n_mort_sp, n_tiges - n_mort_sp) ~", paste(tt, collapse = " + ")))
  tryCatch(suppressWarnings(glm(f, family = binomial("cloglog"), data = plac, na.action = na.exclude)),
           error = function(e) NULL)
}
courbe_stable <- function(plac, vars, vars_in, esp_code, base_lab) {
  essai <- function(quad) {
    fit <- .mk_glm(plac, vars, quad)
    if (is.null(fit) || !isTRUE(fit$converged)) return(NULL)
    cb <- courbe_modele(fit, plac, vars_in)
    if (is.null(cb) || nrow(cb) == 0L) return(NULL)
    cb
  }
  cb <- essai(TRUE)                                                 # quadratique
  if (!is.null(cb) && max(cb$y, na.rm = TRUE) <= SAT_Y) return(cb)
  cb_lin <- essai(FALSE)                                            # repli lineaire
  if (!is.null(cb_lin) && max(cb_lin$y, na.rm = TRUE) <= SAT_Y) {
    .flags[[paste(esp_code, base_lab)]] <<- "lineaire (quadratique sature)"
    return(cb_lin)
  }
  .flags[[paste(esp_code, base_lab)]] <<- "ecartee (saturation, effectif faible)"
  NULL
}

courbes <- list()
for (esp in ESPECES) {
  d_esp <- d_raw[grepl(esp$pattern, species_name) & presence == 1L & prop_G >= PROP_G_MIN]
  cat(sprintf("  %s : %d lignes\n", esp$code, nrow(d_esp)))
  if (nrow(d_esp) == 0L) next
  # detecter si au moins une base a retenu des ECE
  ece_any <- any(sapply(BASES, function(.b) {
    rb <- ri[esp_code == esp$code & base_code == .b$code & RI > 0]
    nrow(rb[indice %in% ECE_IND]) > 0L
  }))
  if (!ece_any) {
    # pas d'ECE retenus : modele identique pour toutes les bases -> 1 ajustement commun
    cols <- c("n_tiges","n_mort_sp", VAR_FIXES)
    miss <- cols[!cols %in% names(d_esp)]
    if (length(miss) > 0L) { cat("  COLONNES MANQUANTES:", paste(miss, collapse=", "), "\n"); next }
    plac <- na.omit(d_esp[, ..cols]); plac <- plac[n_tiges > 0L]
    cat(sprintf("    (sans ECE) : %d plac, %d morts\n", nrow(plac), sum(plac$n_mort_sp)))
    if (nrow(plac) < 50L || sum(plac$n_mort_sp) < 10L) next
    cb <- courbe_stable(plac, VAR_FIXES, character(0), esp$code, "Peuplement")
    if (is.null(cb)) next
    cb[, `:=`(esp_code=esp$code, espece=esp$label, base="Peuplement")]
    courbes[[paste(esp$code, "PEU", sep="_")]] <- cb
  } else {
    for (.b in BASES) {
      rb  <- ri[esp_code == esp$code & base_code == .b$code & RI > 0]
      ece <- rb[indice %in% ECE_IND, variable]
      ece <- ece[ece %in% names(d_esp)]
      cols <- c("n_tiges","n_mort_sp", VAR_FIXES, ece)
      miss <- cols[!cols %in% names(d_esp)]
      if (length(miss) > 0L) { cat("  COLONNES MANQUANTES:", paste(miss, collapse=", "), "\n"); next }
      plac <- na.omit(d_esp[, ..cols]); plac <- plac[n_tiges > 0L]
      cat(sprintf("    %s : %d plac, %d morts, %d ece\n", .b$code, nrow(plac), sum(plac$n_mort_sp), length(ece)))
      if (nrow(plac) < 50L || sum(plac$n_mort_sp) < 10L) next
      cb <- courbe_stable(plac, c(VAR_FIXES, ece), ece, esp$code, .b$label)
      if (is.null(cb)) next
      cb[, `:=`(esp_code = esp$code, espece = esp$label, base = .b$label)]
      courbes[[paste(esp$code, .b$code, sep = "_")]] <- cb
    }
  }
}

if (length(courbes) == 0L) {
  cat("AVERTISSEMENT : Aucune courbe produite -- verifier RI_par_variable.csv et seuils nrow/nmort.\n")
} else {
cr <- rbindlist(courbes)
cr[, indice_f := factor(indice, levels = ORD_FACET)]
cr[, base := factor(base, levels = names(COL_BASE))]
fwrite(cr, file.path(DIRM_SY, "Courbes_reponse.csv"), sep = ";")
cat("Courbes_reponse.csv ecrit (", nrow(cr), "points ).\n")

# Note de convention pour comparer ces courbes (variable BRUTE) a la fig 32 (IR, convention STRESS)
.CAP_CONV <- paste0(
  "Axes en valeur BRUTE ; le stress augmente dans le sens de la fleche du titre (TNn, SPEI6 : stress vers la GAUCHE).\n",
  "La fig 32 (IR) code le sens en convention STRESS -> pour TNn/SPEI6 le signe y est l'OPPOSE de la pente brute ci-dessus. ",
  "Courbe = refit GLM simplifie (illustratif), distinct du modele bootstrap des IR.")
.cap_flags <- if (length(.flags))
  paste0("Faible effectif : ", paste(sprintf("%s [%s]", names(.flags), unlist(.flags)), collapse = " ; "))
  else NULL

# --- 1 figure par espece -----------------------------------------------------
for (esp in ESPECES) {
  sub <- cr[esp_code == esp$code]
  if (nrow(sub) == 0L) next
  g <- ggplot(sub, aes(x, 100 * y, color = base)) +
    geom_line(linewidth = 0.7) +
    facet_wrap(~ indice_f, scales = "free", ncol = 4,
               labeller = as_labeller(LAB_VAR)) +
    scale_color_manual(values = COL_BASE, name = "Base", drop = TRUE) +
    labs(title = bquote("Courbes de reponse -- "*italic(.(esp$label))),
         subtitle = paste0("Modele : ", .run_suffix,
                           " ; Mortalite predite (%) vs chaque variable, les autres a leur moyenne"),
         caption = .CAP_CONV, x = NULL, y = "Mortalite predite (%)") +
    theme_minimal(base_size = 9) +
    theme(plot.title = element_text(face = "bold"), legend.position = "bottom",
          strip.text = element_text(face = "bold"),
          plot.caption = element_text(size = 7, color = "grey45", hjust = 0))
  ggsave(file.path(DIRF, sprintf("Courbes_reponse_%s_%s.png", esp$code, .run_suffix)),
         g, width = 11, height = 5.5, dpi = 150, bg = "white")
}
cat("Figures Courbes_reponse_<esp>.png ecrites dans", DIRF, "\n")

# --- figure combinee toutes especes (grille espece x variable) ---------------
SHORT <- c(QURO="Q. robur", QUPE="Q. petraea", FASY="F. sylvatica", PISY="P. sylvestris",
           PINI="P. nigra", ABAL="A. alba", PIAB="P. abies", BEPE="B. pendula")
lev_court <- unname(SHORT[sapply(ESPECES, function(e) e$code)])
cr[, esp_court := factor(SHORT[esp_code], levels = lev_court)]

# Especes cibles ECARTEES par le modele (effectif insuffisant) -> note sur la figure
.COD8 <- c("QURO","QUPE","FASY","PISY","PINI","ABAL","PIAB","BEPE")
.NOM8 <- c("Quercus robur","Quercus petraea","Fagus sylvatica","Pinus sylvestris",
           "Pinus nigra subsp. nigra","Abies alba","Picea abies","Betula pendula")
.absi <- which(!.COD8 %in% as.character(unique(cr$esp_code)))
.cap_abs <- if (length(.absi))
  paste0("Especes non modelisees (effectif insuffisant : < 50 placettes ou < 10 morts par base) : ",
         paste(.NOM8[.absi], collapse = ", ")) else NULL
gC <- ggplot(cr, aes(x, 100 * y, color = base)) +
  geom_line(linewidth = 0.45) +
  facet_grid(esp_court ~ indice_f, scales = "free", switch = "y",
             labeller = labeller(indice_f = as_labeller(LAB_VAR), esp_court = label_value)) +
  scale_color_manual(values = COL_BASE, name = "Base") +
  labs(title = paste0("Courbes de reponse -- toutes especes -- Modele : ", .run_suffix),
       subtitle = "Mortalite predite (%) vs chaque variable (les autres a leur moyenne) ; 1 ligne par base climatique",
       caption = paste(c(.cap_abs, .cap_flags, .CAP_CONV), collapse = "\n"),
       x = NULL, y = "Mortalite predite (%)") +
  theme_minimal(base_size = 8) +
  theme(plot.title = element_text(face = "bold"), legend.position = "bottom",
        strip.text.x = element_text(face = "bold"),
        strip.text.y.left = element_text(face = "italic", angle = 0),
        strip.placement = "outside", panel.spacing = unit(0.4, "lines"),
        axis.text = element_text(size = 6),
        plot.caption = element_text(size = 8, color = "#C0392B", hjust = 0))
ggsave(file.path(DIRF, sprintf("Courbes_reponse_TOUTES_especes_%s.png", .run_suffix)), gC,
       width = 15, height = 13, dpi = 150, bg = "white", limitsize = FALSE)
cat("Figure combinee Courbes_reponse_TOUTES_especes.png ecrite.\n")
} # end if (length(courbes) > 0L)
