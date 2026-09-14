# source("R/06_modele/2-Figures/20-Fig_RI_par_variable.R")   # depuis la racine du depot
# ============================================================================
# IMPORTANCE RELATIVE PAR VARIABLE INDIVIDUELLE (toutes variables : ECE + fixes).
#   Meme structure que 5-Fig_Carletti_RI.R mais avec chaque variable separee,
#   sans agregation par type de stress.
#   Lit RI_par_variable.csv (produit par 1-Modele_mortalite.R).
#   Sortie : 5-Resultats/5-Modeles/Figures/Fig_RI_par_variable.png
# ============================================================================
# Chemins : config/chemins.R (lancer depuis la racine du depot, ou definir ECE_DEPOT)
if (!exists("DEPOT")) source(file.path(Sys.getenv("ECE_DEPOT", getwd()), "config", "chemins.R"))
suppressPackageStartupMessages({ library(data.table); library(ggplot2) })

# .PFX : fourni par config/chemins.R
if (!exists("RUN_TAG")) RUN_TAG <- "Mortalite_2009-2023_r075"
.VARIANTE_DIR <- if (grepl("_dominants$", RUN_TAG)) "dominants" else if (grepl("_domines$", RUN_TAG)) "domines" else if (grepl("_pur080$", RUN_TAG)) "pur080" else "standard"  # niveau jeu de donnees (cf 6-Extraction_bases_variantes.R)
DIRM    <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/5-Modeles", .VARIANTE_DIR, RUN_TAG)
DIRM_SY <- file.path(DIRM, "2-Syntheses")
DIRF <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/5-Modeles", .VARIANTE_DIR, RUN_TAG, "Figures", "2-Importance_relative")
dir.create(DIRF, showWarnings = FALSE, recursive = TRUE)
.run_suffix <- sub("^Mortalite_", "", RUN_TAG)

ri <- fread(file.path(DIRM_SY, "RI_par_variable.csv"))
ri <- ri[base_code != "CHEDS"]   # CHE-C ecartee de l'analyse

# ---- suppression suffixe base des indices ECE -------------------------------
SUFFS <- c("EOB10","EOBDS","SAF8","SAFDS","CHE1","CHEDS")
ri[, var_base := sub(paste0("_(", paste(SUFFS, collapse="|"), ")$"), "", variable)]

# ---- moyenne RI sur les 6 bases par (espece, variable) ----------------------
agg <- ri[, .(RI_moy = mean(RI, na.rm = TRUE)), by = .(espece, esp_code, var_base)]

# ---- ordre des variables : Froid -> Chaleur -> Secheresse -> Peuplement/sol -
VAR_ORD <- c("TNn","CWN","TXx","HWN","SPEI6","WG10P",
             "prop_G","c13_moy_sp","Gini","G_ha_tot","pH")
VAR_LABS <- c("TNn","CWN","TXx","HWN","SPEI6","WG10P",
              "prop G","c13 sp","Gini","G tot","pH")
names(VAR_LABS) <- VAR_ORD

COL_VAR <- c(
  "TNn"       = "#2166AC",   # bleu fonce  (froid)
  "CWN"       = "#92C5DE",   # bleu clair  (froid)
  "TXx"       = "#D73027",   # rouge       (chaleur)
  "HWN"       = "#F4A582",   # saumon      (chaleur)
  "SPEI6"     = "#8C510A",   # brun fonce  (secheresse)
  "WG10P"     = "#DFC27D",   # brun clair  (secheresse)
  "prop_G"    = "#252525",   # gris tres fonce  (peuplement)
  "c13_moy_sp"= "#525252",   # gris fonce
  "Gini"      = "#737373",   # gris moyen
  "G_ha_tot"  = "#BDBDBD",   # gris clair
  "pH"        = "#E0E0E0"    # gris tres clair  (sol)
)

agg[, var_base := factor(var_base, levels = VAR_ORD)]
agg <- agg[!is.na(var_base)]  # exclure variables non reconnues

# ---- ordre especes : croissant par somme ECE ; fallback RI total si pas d'ECE -----
ECE_VARS  <- c("TNn","CWN","TXx","HWN","SPEI6","WG10P")
ece_tot   <- agg[var_base %in% ECE_VARS, .(ECE_tot = sum(RI_moy)), by = esp_code]
if (nrow(ece_tot) == 0L)  # modele sans ECE (ex. Peuplement) : ordre par RI total
  ece_tot <- agg[, .(ECE_tot = sum(RI_moy)), by = esp_code]
setorder(ece_tot, ECE_tot)   # ABAL en premier = sera en bas sur l'axe y

ESP_NOMS <- c(
  ABAL="Abies alba", PINI="Pinus nigra subsp. nigra", PIAB="Picea abies",
  FASY="Fagus sylvatica", PISY="Pinus sylvestris", QURO="Quercus robur",
  QUPE="Quercus petraea", BEPE="Betula pendula")

agg[, espece_nom := ESP_NOMS[esp_code]]
agg[, espece_nom := factor(espece_nom, levels = ESP_NOMS[ece_tot$esp_code])]

# Especes cibles ECARTEES par le modele (effectif insuffisant) -> note sur la figure
.COD8 <- c("QURO","QUPE","FASY","PISY","PINI","ABAL","PIAB","BEPE")
.NOM8 <- c("Quercus robur","Quercus petraea","Fagus sylvatica","Pinus sylvestris",
           "Pinus nigra subsp. nigra","Abies alba","Picea abies","Betula pendula")
.absi <- which(!.COD8 %in% as.character(unique(agg$esp_code)))
.cap_abs <- if (length(.absi))
  paste0("Especes non modelisees (effectif insuffisant : < 50 placettes ou < 10 morts par base) : ",
         paste(.NOM8[.absi], collapse = ", ")) else NULL

# ---- figure -----------------------------------------------------------------
g <- ggplot(agg, aes(y = espece_nom, x = RI_moy, fill = var_base)) +
  geom_col(width = 0.72, color = "white", linewidth = 0.3) +
  scale_fill_manual(
    values = COL_VAR,
    labels = VAR_LABS,
    name   = "Variable",
    breaks = VAR_ORD,
    guide  = guide_legend(ncol = 1, byrow = FALSE,
                          override.aes = list(linewidth = 0))) +
  scale_x_continuous(expand = c(0, 0), limits = c(0, 101),
                     breaks = c(0, 25, 50, 75, 100),
                     labels = c("0","25","50","75","100")) +
  labs(
    title    = paste0("Importance relative par variable -- Modele : ", .run_suffix),
    subtitle = "Moyenne sur 6 bases climatiques et 100 iterations",
    caption  = .cap_abs,
    x        = "RI cumulee (%)",
    y        = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title       = element_text(face = "bold", size = 12),
    plot.subtitle    = element_text(size = 9, color = "grey40"),
    plot.caption     = element_text(size = 8.5, color = "#C0392B", hjust = 0),
    axis.text.y      = element_text(face = "italic", size = 10),
    axis.text.x      = element_text(size = 9),
    panel.grid.major.y = element_blank(),
    panel.grid.minor   = element_blank(),
    legend.position  = "right",
    legend.text      = element_text(size = 9),
    legend.title     = element_text(size = 9, face = "bold"),
    legend.key.size  = unit(0.55, "cm"),
    plot.margin      = margin(10, 10, 10, 10)
  )

fout <- file.path(DIRF, sprintf("Fig_RI_par_variable_%s.png", .run_suffix))
ggsave(fout, g, width = 9, height = 5.5, dpi = 180, bg = "white")
cat("Figure :", fout, "\n")
