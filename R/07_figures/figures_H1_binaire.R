# =====================================================================
# Figures H1 (downscaling) en REPONSE BINAIRE (occurrence de mortalite)
# Run : Mortalite France 2015-2023, r070, n1000, binaire (CHE-C exclue)
#
# Source de donnees : BACKUP LOCAL (developpement/validation hors-ligne).
# La version qui fait foi doit tourner sur CALCULUS (repointer DATA_DIR
# vers S:/.../5-Resultats/5-Modeles/standard/...).
#
# Produit 3 figures (PDF livrable + PNG apercu) :
#   Fig1 : AUC par espece x base (natif vs downscale)   -> H1 sans gain + effet espece
#   Fig2 : somme des IR des 6 indices ECE par espece x base -> les IR bougent avec le DS
#   Fig3 : heatmap IR par indice ECE x espece (moyen inter-bases) -> quel ECE pour quelle essence
# ASCII pur dans le script ; accents/degres via \u.... dans les labels affiches.
# =====================================================================

suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(tidyr); library(forcats)
})

## ---- Parametres --------------------------------------------------------
RUN_TAG   <- "2015-2024_r070_n1000_binaire"
OVERWRITE <- TRUE   # flag explicite d'ecrasement (charte : jamais ecraser sans flag)

BASE_DIR <- path.expand("~/Documents/stage_JeremyG_backup/stage_JeremyG")
DATA_DIR <- file.path(BASE_DIR, "5-Resultats", "5-Modeles", "standard",
                      "Mortalite_2015-2024_r070_n1000_binaire", "2-Syntheses")
OUT_DIR  <- path.expand("~/Documents/stage_JeremyG_backup/figures_H1_binaire")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

rd <- function(f) read.table(file.path(DATA_DIR, f), sep = ";", header = TRUE,
                             dec = ".", quote = "\"", stringsAsFactors = FALSE,
                             encoding = "UTF-8", check.names = FALSE)

## ---- Referentiels (ordre, libelles, palette) ---------------------------
ECE6   <- c("TXx","HWN","TNn","CWN","SPEI6","WG10P")            # ordre chaud/froid/sec
base_lv <- c("SAF-8","SAF-DS","EOB-10","EOB-DS","CHE-1")
base_pal <- c("SAF-8"="#9ecae1","SAF-DS"="#3182bd",
              "EOB-10"="#a1d99b","EOB-DS"="#31a354","CHE-1"="#fd8d3c")

esp_lab <- c(
  QURO = "QURO Chêne péd.", QUPE = "QUPE Chêne sess.",
  FASY = "FASY Hêtre",           PISY = "PISY Pin sylv.",
  PINI = "PINI Pin noir",             ABAL = "ABAL Sapin",
  PIAB = "PIAB Épicéa",      BEPE = "BEPE Bouleau")

## ---- Lecture -----------------------------------------------------------
sg <- rd("Synthese_globale.csv")
ri <- rd("RI_par_variable.csv")

## ordre des especes = AUC moyenne decroissante (meilleures en haut)
esp_order <- sg %>% group_by(esp_code) %>% summarise(a = mean(AUC_moy), .groups="drop") %>%
  arrange(desc(a)) %>% pull(esp_code)
mk_esp <- function(code) factor(esp_lab[code], levels = esp_lab[rev(esp_order)])  # meilleures AUC en haut

## =====================================================================
## Fig 1 : AUC par espece x base (natif vs downscale)
## =====================================================================
d1 <- sg %>% transmute(esp_code, base = factor(base, levels = base_lv),
                       AUC_moy, AUC_sd) %>%
  mutate(esp = mk_esp(esp_code))

stopifnot(all(c("AUC_moy","AUC_sd") %in% names(sg)))   # preflight colonnes aes()

g1 <- ggplot(d1, aes(x = AUC_moy, y = esp, color = base)) +
  geom_pointrange(aes(xmin = AUC_moy - AUC_sd, xmax = AUC_moy + AUC_sd),
                  position = position_dodge(width = 0.62), size = 0.4, linewidth = 0.5) +
  scale_color_manual(values = base_pal, name = "Base (natif / 1 km downscalé)") +
  scale_x_continuous(breaks = seq(0.6, 0.9, 0.05)) +
  labs(title = "Discrimination (AUC) par essence et base : réponse binaire",
       subtitle = paste0(RUN_TAG, "  |  barres = ±1 écart-type bootstrap ; paires natif/DS non significatives (Holm)"),
       x = "AUC (validation)", y = NULL,
       caption = "Bleus = SAFRAN, verts = E-OBS (clair = natif, foncé = 1 km downscalé), orange = CHELSA natif 1 km") +
  theme_bw(base_size = 12) +
  theme(plot.title = element_text(face = "bold"),
        panel.grid.minor = element_blank(),
        legend.position = "right")

## =====================================================================
## Fig 2 : somme des IR des 6 indices ECE, par espece x base
## =====================================================================
strip_base <- function(v) sub("_(SAF8|SAFDS|EOB10|EOBDS|CHE1|CHEDS)$", "", v)
ri2 <- ri %>% mutate(indice = strip_base(variable)) %>% filter(indice %in% ECE6)

d2 <- ri2 %>% group_by(esp_code, base) %>% summarise(IR_ECE = sum(RI), .groups = "drop") %>%
  mutate(base = factor(base, levels = base_lv), esp = mk_esp(esp_code))

g2 <- ggplot(d2, aes(x = IR_ECE, y = esp, fill = base)) +
  geom_col(position = position_dodge(width = 0.72), width = 0.66) +
  scale_fill_manual(values = base_pal, name = "Base (natif / 1 km downscalé)") +
  labs(title = "Poids des ECE (somme des IR des 6 indices) par essence et base : réponse binaire",
       subtitle = paste0(RUN_TAG, "  |  le downscaling gonfle l'IR des ECE (PINI, BEPE, ABAL) sans gain d'AUC"),
       x = "Somme des IR des indices ECE (%)", y = NULL,
       caption = "IR = importance relative (part de la déviance du modèle, normalisée). Peuplement = complément à 100 %.") +
  theme_bw(base_size = 12) +
  theme(plot.title = element_text(face = "bold"),
        panel.grid.minor = element_blank(),
        panel.grid.major.y = element_blank(),
        legend.position = "right")

## =====================================================================
## Fig 3 : heatmap IR par indice ECE x espece (moyen inter-bases)
## =====================================================================
d3 <- ri2 %>% group_by(esp_code, indice) %>% summarise(IR = mean(RI), .groups = "drop") %>%
  tidyr::complete(esp_code, indice = ECE6, fill = list(IR = 0)) %>%
  mutate(indice = factor(indice, levels = ECE6), esp = mk_esp(esp_code))

fam_lab <- c(TXx="TXx\n(chaud)", HWN="HWN\n(canicule)", TNn="TNn\n(froid)",
             CWN="CWN\n(froid)", SPEI6="SPEI6\n(sec)", WG10P="WG10P\n(humide)")

g3 <- ggplot(d3, aes(x = indice, y = esp, fill = IR)) +
  geom_tile(color = "white", linewidth = 0.6) +
  geom_text(aes(label = ifelse(IR >= 0.1, sprintf("%.1f", IR), "")),
            size = 3.4,
            color = ifelse(d3$IR > 12, "white", "grey15")) +
  scale_fill_gradient(low = "#f7f7f7", high = "#b2182b", name = "IR moyen (%)") +
  scale_x_discrete(labels = fam_lab) +
  labs(title = "Quel indice ECE explique quelle essence : réponse binaire",
       subtitle = paste0(RUN_TAG, "  |  IR moyen inter-bases (5 bases), en % de déviance"),
       x = NULL, y = NULL,
       caption = "Chaud : TXx, HWN  |  froid : TNn, CWN  |  sécheresse/humidité : SPEI6, WG10P") +
  theme_bw(base_size = 12) +
  theme(plot.title = element_text(face = "bold"),
        panel.grid = element_blank())

## ---- Sauvegarde (garde-fou ecrasement) ---------------------------------
save_fig <- function(g, stem, w, h) {
  for (ext in c("pdf","png")) {
    f <- file.path(OUT_DIR, sprintf("%s__%s.%s", stem, RUN_TAG, ext))
    if (file.exists(f) && !OVERWRITE) stop("Existe deja (OVERWRITE=FALSE) : ", f)
    ggsave(f, g, width = w, height = h, dpi = 150,
           device = ext, bg = "white")
    cat("  ecrit :", normalizePath(f), "\n")
  }
}
cat("Figures produites :\n")
save_fig(g1, "Fig1_AUC_par_base_espece", 9.2, 5.6)
save_fig(g2, "Fig2_IR_ECE_par_base_espece", 9.2, 5.6)
save_fig(g3, "Fig3_heatmap_ECE_par_espece", 8.6, 5.4)
cat("\nDossier de sortie :", OUT_DIR, "\n")
