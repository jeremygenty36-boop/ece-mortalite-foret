# source("R/07_figures/71-Fig_correlation_indices_ECE_MM.R")   # depuis la racine du depot
# ==============================================================================
# M&M : correlation des 6 indices ECE -- UN CARRE (matrice complete) PAR BASE.
#   Illustration du filtre de colinearite : dans chaque base, les paires
#   |r| > 0.70 (encadrees) declenchent le retrait d'un des deux indices correles.
#   Version simple et non ambigue (matrice complete par base), demandee par
#   l'encadrant.
#
#   Pearson sur les placettes du jeu modele (2015-2023) ; ECE au niveau placette
#   -> dedup par idp (pas de pseudo-replication). CHE-C exclue (comme le rapport).
#   Rangee du haut = bases natives, rangee du bas = downscalees.
#
#   NON TESTE (job en cours) : a lancer APRES l'overnight. Sortie CALCULUS = foi.
# ==============================================================================
# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
suppressPackageStartupMessages({ library(data.table); library(ggplot2) })

# .PFX : fourni par config/chemins.R
if (!exists("SEUIL_COR")) SEUIL_COR <- 0.70
if (!exists("BASES"))     BASES     <- c("EOB10", "SAF8", "CHE1", "EOBDS", "SAFDS")  # natifs puis DS ; CHE-C exclue
CAMP_MIN <- 2015L; CAMP_MAX <- 2023L

ECE      <- c("TXx", "TNn", "SPEI6", "WG10P", "HWN", "CWN")
LAB_BASE <- c(EOB10 = "EOB-10", SAF8 = "SAF-8", CHE1 = "CHE-1",
              EOBDS = "EOB-DS", SAFDS = "SAF-DS", CHEDS = "CHE-C")

if (!exists("F_IFN")) F_IFN <- file.path(.PFX, "Projets/stage_JeremyG/3-Donnees/6-IFN/IFN_placette.csv")
cols_all <- as.vector(outer(ECE, BASES, paste, sep = "_"))

d <- fread(F_IFN, select = c("idp", "campagne", cols_all))
d <- d[campagne >= CAMP_MIN & campagne <= CAMP_MAX]
d <- unique(d, by = "idp")                        # 1 ligne / placette

# ---- une matrice complete par base -> long ----------------------------------
res <- rbindlist(lapply(BASES, function(b) {
  M <- cor(d[, paste0(ECE, "_", b), with = FALSE], use = "pairwise.complete.obs", method = "pearson")
  dimnames(M) <- list(ECE, ECE)
  x <- as.data.table(as.table(M)); setnames(x, c("Var1", "Var2", "r"))
  x[, base := unname(LAB_BASE[b])][]
}))
res[, Var1 := factor(Var1, levels = ECE)]
res[, Var2 := factor(Var2, levels = rev(ECE))]
res[, base := factor(base, levels = unname(LAB_BASE[BASES]))]
res[, sup  := abs(r) > SEUIL_COR & as.character(Var1) != as.character(Var2)]
# --- ne garder que le triangle inferieur (sous la diagonale, diagonale incluse) ---
res <- res[match(as.character(Var2), ECE) >= match(as.character(Var1), ECE)]

g <- ggplot(res, aes(Var1, Var2, fill = r)) +
  geom_tile(color = "grey85") +
  geom_tile(data = res[sup == TRUE], fill = NA, color = "black", linewidth = 0.9) +
  geom_text(aes(label = sprintf("%.2f", r), color = abs(r) > 0.55),
            size = 3.2, fontface = "bold", show.legend = FALSE) +
  facet_wrap(~ base, nrow = 2) +
  scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B",
                       midpoint = 0, limits = c(-1, 1), name = "r (Pearson)",
                       breaks = c(-1, -0.5, 0, 0.5, 1)) +
  scale_color_manual(values = c(`TRUE` = "white", `FALSE` = "grey20")) +
  coord_equal() +
  labs(title = "Correlation des indices ECE par base climatique",
       subtitle = paste0("Placettes du jeu modele ", CAMP_MIN, "-", CAMP_MAX,
                         " : les paires |r| > ", format(SEUIL_COR),
                         " (encadrees) declenchent le filtre de colinearite (un seul indice retenu par paire)"),
       x = NULL, y = NULL) +
  theme_minimal(base_size = 10) +
  theme(panel.grid = element_blank(),
        axis.text.x = element_text(face = "bold", angle = 30, hjust = 1, size = 8),
        axis.text.y = element_text(face = "bold", size = 8),
        strip.text = element_text(face = "bold", size = 10),
        plot.title = element_text(face = "bold", size = 12),
        plot.subtitle = element_text(size = 8.5, color = "grey35"),
        panel.spacing = unit(0.8, "lines"),
        legend.position = "right")

DIRF <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/5-Modeles/Figures/2-Materiel_methodes")
dir.create(DIRF, showWarnings = FALSE, recursive = TRUE)
f_png <- file.path(DIRF, "Fig_correlation_indices_ECE_par_base.png")
ggsave(f_png, g, width = 11, height = 7.5, dpi = 200, bg = "white")
cat("PNG :", f_png, "\n")
cat("n placettes :", nrow(d), " | bases :", paste(BASES, collapse = ", "), "\n")
for (b in BASES) { cat("\n---", LAB_BASE[[b]], "---\n"); print(round(cor(d[, paste0(ECE, "_", b), with = FALSE], use = "pairwise.complete.obs"), 2)) }
