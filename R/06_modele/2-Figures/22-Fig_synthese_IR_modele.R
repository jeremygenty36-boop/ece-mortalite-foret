# source("R/06_modele/2-Figures/22-Fig_synthese_IR_modele.R")   # depuis la racine du depot
# ============================================================================
# TABLEAU SYNTHETIQUE IR PAR ESPECE x VARIABLE.
#   Lit RI_par_variable.csv ; produit un tableau heatmap :
#     Lignes  = espece x base (48 max : 8 esp. x 6 bases, groupees par espece)
#     Colonnes = variables (variables fixes + indices ECE presents dans le modele)
#     Valeurs  = RI normalise (%) moyen sur N_ITER iterations
#     Couleur  = vert/rose pour max/min par colonne (parmi lignes avec RI > 0)
#   Sortie : PNG dans Figures/2-Importance_relative/
# ============================================================================
# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
suppressPackageStartupMessages({ library(data.table); library(ggplot2) })

# .PFX : fourni par config/chemins.R
if (!exists("RUN_TAG")) RUN_TAG <- "Mortalite_2015-2023_r070_n1000_binaire"
.VARIANTE_DIR <- if (grepl("_dominants$", RUN_TAG)) "dominants" else if (grepl("_domines$", RUN_TAG)) "domines" else if (grepl("_pur080$", RUN_TAG)) "pur080" else "standard"  # niveau jeu de donnees (cf 6-Extraction_bases_variantes.R)
DIRM_SY <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/5-Modeles", .VARIANTE_DIR, RUN_TAG, "2-Syntheses")
DIRF    <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/5-Modeles", .VARIANTE_DIR, RUN_TAG, "Figures", "2-Importance_relative")
dir.create(DIRF, showWarnings = FALSE, recursive = TRUE)
.run_suffix <- sub("^Mortalite_", "", RUN_TAG)

# ---- lecture RI_par_variable.csv -------------------------------------------
ri <- fread(file.path(DIRM_SY, "RI_par_variable.csv"))

# strip suffixe base des noms de variables ECE (ex. TXx_EOB10 -> TXx)
SUFFS <- c("EOB10","EOBDS","SAF8","SAFDS","CHE1","CHEDS")
ri[, var_base := sub(paste0("_(", paste(SUFFS, collapse="|"), ")$"), "", variable)]

# ---- ordre canonique des variables (fixes puis ECE) -------------------------
VAR_ORD_ALL <- c("pH","G_ha_tot","Gini","c13_moy_sp","prop_G",
                 "TNn","CWN","TXx","HWN","SPEI6","WG10P")
VAR_LABS_ALL <- c(pH="pH", G_ha_tot="G tot", Gini="Gini", c13_moy_sp="c13 sp",
                  prop_G="prop G", TNn="TNn", CWN="CWN", TXx="TXx",
                  HWN="HWN", SPEI6="SPEI6", WG10P="WG10P")
# couleur d'en-tete de colonne par groupe de variable
COL_VAR_HDR <- c(pH="#BDBDBD", G_ha_tot="#BDBDBD", Gini="#BDBDBD",
                 c13_moy_sp="#BDBDBD", prop_G="#BDBDBD",
                 TNn="#C6DBEF", CWN="#C6DBEF",
                 TXx="#FCBBA1", HWN="#FCBBA1",
                 SPEI6="#D4A574", WG10P="#D4A574")

# variables effectivement presentes dans ce run
vars_presentes <- intersect(VAR_ORD_ALL, unique(ri$var_base))
ri <- ri[var_base %in% vars_presentes]

# ---- ordre des especes et bases --------------------------------------------
ORD_ESP  <- c("Quercus robur","Quercus petraea","Fagus sylvatica","Pinus sylvestris",
              "Pinus nigra subsp. nigra","Abies alba","Picea abies","Betula pendula")
ESP_COURT <- c("Quercus robur"="Q. robur", "Quercus petraea"="Q. petraea",
               "Fagus sylvatica"="F. sylvatica", "Pinus sylvestris"="P. sylvestris",
               "Pinus nigra subsp. nigra"="P. nigra", "Abies alba"="A. alba",
               "Picea abies"="P. abies", "Betula pendula"="B. pendula")
ORD_BASE <- c("EOB-10","SAF-8","CHE-1","EOB-DS","SAF-DS")   # CHE-C ecartee de l'analyse

COL_MAX <- "#C6EFC4"   # vert : max par colonne
COL_MIN <- "#FFE0D0"   # rose : min par colonne (parmi RI > 0)
COL_ZERO <- "grey93"   # variable non retenue

# ---- construction de la table longue (espece x base x var_base) -------------
dt <- ri[, .(RI = mean(RI, na.rm = TRUE)), by = .(espece, esp_code, base, base_code, var_base)]
dt <- dt[espece %in% ORD_ESP & base %in% ORD_BASE]
dt[, espece  := factor(espece,  levels = ORD_ESP)]

# Especes cibles ECARTEES par le modele (effectif insuffisant) -> note sur la figure
.abs <- setdiff(ORD_ESP, as.character(unique(dt$espece)))
.cap_abs <- if (length(.abs))
  paste0("Especes non modelisees (effectif insuffisant : < 50 placettes ou < 10 morts par base) : ",
         paste(.abs, collapse = ", ")) else NULL
dt[, base    := factor(base,    levels = ORD_BASE)]
dt[, var_f   := factor(var_base, levels = vars_presentes)]
setorder(dt, espece, base)

# etiquette de ligne : "Base" (la colonne espece s'affiche via facet)
dt[, row_lbl := base]

# ---- highlight : vert = max, rose = min par variable ------------------------
dt[, fill_cat := {
  ri_pos <- RI[RI > 0]
  mn <- if (length(ri_pos) > 0L) min(ri_pos, na.rm = TRUE) else NA_real_
  mx <- max(RI, na.rm = TRUE)
  fifelse(is.na(RI) | RI == 0, "zero",
  fifelse(!is.na(mx) & RI == mx & mx > 0, "max",
  fifelse(!is.na(mn) & RI == mn, "min", "normal")))
}, by = var_f]

dt[, lbl := fifelse(is.na(RI) | RI == 0, "", sprintf("%.1f", RI))]
dt[, face_lbl := fifelse(fill_cat %in% c("max","min"), "bold", "plain")]

# ---- figure -----------------------------------------------------------------
g <- ggplot(dt, aes(x = var_f, y = row_lbl, fill = fill_cat)) +
  geom_tile(color = "grey75", linewidth = 0.35) +
  geom_text(aes(label = lbl, fontface = face_lbl), size = 2.6, color = "black") +
  facet_grid(espece ~ ., scales = "free_y", space = "free_y", switch = "y") +
  scale_fill_manual(
    values = c(max = COL_MAX, min = COL_MIN, zero = COL_ZERO, normal = "white"),
    labels = c(max = "max colonne", min = "min colonne", zero = "non retenu", normal = ""),
    guide  = guide_legend(title = NULL, ncol = 2,
                          override.aes = list(color = "grey60", linewidth = 0.3))
  ) +
  scale_x_discrete(position = "top", labels = VAR_LABS_ALL[vars_presentes]) +
  scale_y_discrete(limits = rev(ORD_BASE)) +
  labs(
    title    = paste0("IR normalise (%) par espece et par base -- Modele : ", .run_suffix),
    subtitle = "Vert = max par colonne, rose = min (parmi variables retenues) ; valeur = moyenne sur 100 iterations",
    caption  = .cap_abs, x = NULL, y = NULL
  ) +
  theme_minimal(base_size = 9) +
  theme(
    plot.title         = element_text(face = "bold", size = 10),
    plot.subtitle      = element_text(size = 7.5, color = "grey40"),
    plot.caption       = element_text(size = 7.5, color = "#C0392B", hjust = 0),
    axis.text.x        = element_text(face = "bold", size = 8, angle = 0),
    axis.text.x.top    = element_text(face = "bold", size = 8),
    axis.text.y        = element_text(size = 7.5),
    strip.text.y.left  = element_text(face = "bold.italic", size = 8, angle = 0),
    strip.placement    = "outside",
    strip.background   = element_rect(fill = "#E8E8E8", color = "grey70", linewidth = 0.4),
    panel.grid         = element_blank(),
    panel.spacing.y    = unit(0.35, "lines"),
    legend.position    = "bottom",
    legend.text        = element_text(size = 7.5),
    plot.margin        = margin(8, 10, 8, 5)
  )

n_esp <- length(unique(dt$espece))
n_var <- length(vars_presentes)
h_fig <- 1.2 + n_esp * 1.35
w_fig <- 3.5 + n_var * 0.85

fout <- file.path(DIRF, sprintf("Fig_synthese_IR_%s.png", .run_suffix))
ggsave(fout, g, width = w_fig, height = h_fig, dpi = 180,
       bg = "white", limitsize = FALSE)
cat("Figure synthese IR :", fout, "\n")
cat(sprintf("  %d especes x %d variables x 6 bases\n", n_esp, n_var))
