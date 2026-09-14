# source("S:/Projets/stage_JeremyG/4-Travail_bis/5-Figures/4-IFN/4-Carte_combinee_barplot_Focus.R")
# ============================================================================
# (A) Carte COMBINEE : les 8 essences ETUDIEES sur une seule carte (couleur
#     par essence ; essence dominante de la placette).
# (B) Barplot : SEULEMENT les 8 essences etudiees, par nombre de placettes,
#     aux MEMES couleurs que la carte ; portion sombre = placettes avec mort.
# (C) Figure COMBINEE (a) carte + (b) barplot.
# Corse hors etude (dep 2A/2B). Projection Lambert-93. Palette partagee.
# ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(sf); library(ggplot2); library(grid); library(patchwork); library(ggtext)
})

.PFX    <- if (dir.exists("S:/Projets")) "S:" else "/Volumes/_donnees"
F_IFN   <- file.path(.PFX, "Projets/stage_JeremyG/3-Donnees/6-IFN/IFN_placette.csv")
F_FOND  <- file.path(.PFX, "Projets/stage_JeremyG/4-Travail_bis/1-Bases_de_donnees/3-Limites_geo/France_GADM_L0.gpkg")
DIR_OUT <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/6-Figures et tableaux redaction/2-Materiel_methodes")
if (!dir.exists(DIR_OUT)) dir.create(DIR_OUT, recursive=TRUE)

# 8 essences etudiees + palette qualitative partagee (carte ET barplot)
FOCUS <- c("Quercus petraea", "Pinus sylvestris", "Abies alba", "Quercus robur",
           "Betula pendula", "Picea abies", "Fagus sylvatica",
           "Pinus nigra subsp. nigra")
PAL8  <- c("#1b9e77","#d95f02","#7570b3","#e7298a","#66a61e","#e6ab02","#a6761d","#1f78b4")

# --- Lignes (placette x essence PRESENTE), periode d'etude, Corse exclue -----
# JEU DE MODELISATION : essence focus PRESENTE (presence==1, PAS dominante),
# campagnes 2015-2023 (restriction VOLONTAIRE a la periode de hausse de mortalite,
# justif. facon Helene, cf figure annexe), hors Corse. Une placette portant
# 2 essences focus apparait pour chacune (redondance assumee, coherent modele).
d    <- fread(F_IFN, sep=";")
dd   <- d[species_name %in% FOCUS & presence == 1 &
          campagne >= 2015L & campagne <= 2023L &
          is.finite(lon) & is.finite(lat) & !(dep %in% c("2A","2B"))]

# Ordre des essences par nb de placettes PRESENTES (desc) + couleurs PARTAGEES
n_foc <- dd[, .(N = .N), by = species_name][order(-N)]
COL_FOCUS <- setNames(PAL8, n_foc$species_name)   # essence -> couleur (ordre effectif desc)
n_foc[, couleur := PAL8]
cat("Essences etudiees, placettes presentes (2015-2023, hors Corse) et couleur :\n"); print(n_foc)

# ============================================================================
# (A) CARTE FACETTEE : un panneau par essence etudiee (8), une couleur par
#     essence (= meme rendu que 3-Carte_placettes_Focus.R). Sert de panneau
#     (a) de la figure combinee, a la place de l'ancienne carte unique.
# ============================================================================
fr0     <- st_make_valid(st_read(F_FOND, quiet = TRUE))
fr_main <- suppressWarnings(st_crop(fr0, xmin = -5.5, ymin = 41, xmax = 8.5, ymax = 51.6))
fr_l93  <- st_transform(fr_main, 2154)

foc  <- dd[, .(idp, lon, lat, species_name)]
n_by <- foc[, .N, by = species_name][order(-N)]              # placettes presentes desc (= barplot)
# Strip = 2 lignes (ggtext) : nom d'espece (grand italique) + effectif dessous.
# NB ggplot2 4.0 : theme_void OK avec element_markdown (theme_minimal casse).
n_by[, disp := gsub(" subsp\\. ", "<br>subsp. ", species_name)]   # coupe le nom long (Pinus nigra) sur 2 lignes
n_by[, lab := sprintf(
  "<span style='font-size:17pt'><i>%s</i></span><br><span style='font-size:15pt;color:#333333'>n = %s</span>",
  disp, format(N, big.mark = " ", trim = TRUE))]
foc[, panel := factor(species_name, levels = n_by$species_name, labels = n_by$lab)]
foc_sf  <- st_transform(st_as_sf(foc, coords = c("lon","lat"), crs = 4326), 2154)

# Couleurs PARTAGEES carte/barplot : PAL8 dans l'ordre d'effectif decroissant
COL_PANEL <- setNames(PAL8, n_by$lab)

# Fleche nord (panneau haut-droite = Pinus sylvestris) + echelle 200 km
# (panneau bas-droite = Pinus nigra), placees dans les marges (hors France).
lev    <- levels(foc$panel)
parrow <- factor(lev[4],            levels = lev)
pscale <- factor(lev[length(lev)],  levels = lev)
bb   <- st_bbox(fr_l93)
xmin <- as.numeric(bb["xmin"]); xmax <- as.numeric(bb["xmax"])
ymin <- as.numeric(bb["ymin"]); ymax <- as.numeric(bb["ymax"])
xr   <- xmax - xmin; yr <- ymax - ymin; L <- 200000
xR <- xmax - 0.02 * xr; yb <- ymin - 0.030 * yr
sb <- data.frame(panel = pscale, x = xR - L, xend = xR, y = yb)
tk <- data.frame(panel = pscale, x = c(xR - L, xR - L/2, xR), y = yb, yend = yb + 0.018 * yr)
sl <- data.frame(panel = pscale, x = xR - L/2, y = yb - 0.042 * yr, lab = "200 km")
xn <- xmax - 0.04 * xr
na <- data.frame(panel = parrow, x = xn, y = ymax - 0.010 * yr, xend = xn, yend = ymax + 0.150 * yr)
nl <- data.frame(panel = parrow, x = xn, y = ymax + 0.190 * yr, lab = "N")

p_map <- ggplot() +
  geom_sf(data = fr_l93, fill = "grey94", colour = "grey55", linewidth = 0.3) +
  geom_sf(data = foc_sf, aes(colour = panel), size = 0.32, alpha = 0.7) +
  geom_segment(data = sb, aes(x = x, xend = xend, y = y, yend = y), linewidth = 1.1, colour = "grey15") +
  geom_segment(data = tk, aes(x = x, xend = x, y = y, yend = yend), linewidth = 1.0, colour = "grey15") +
  geom_text(data = sl, aes(x = x, y = y, label = lab), size = 4.2, colour = "grey15") +
  geom_segment(data = na, aes(x = x, y = y, xend = xend, yend = yend),
               arrow = grid::arrow(length = grid::unit(0.34, "cm"), angle = 19, type = "closed"),
               linewidth = 1.1, colour = "grey15") +
  geom_text(data = nl, aes(x = x, y = y, label = lab), size = 5.5, fontface = "bold", colour = "grey15") +
  scale_colour_manual(values = COL_PANEL, guide = "none") +
  facet_wrap(~ panel, ncol = 4) +
  coord_sf(datum = NA, xlim = c(xmin, xmax + 0.015 * xr),
           ylim = c(ymin - 0.120 * yr, ymax + 0.245 * yr), expand = FALSE) +
  labs(title = "Placettes IFN du jeu de modélisation : 8 essences étudiées",
       subtitle = "Essence présente sur la placette ; un panneau par essence ; Corse hors étude.") +
  theme_void(base_size = 11) +
  theme(plot.background = element_rect(fill = "white", colour = NA),
        strip.text    = ggtext::element_markdown(lineheight = 1.15, margin = margin(b = 3)),
        plot.title    = element_text(face = "bold", size = 13, margin = margin(b = 2)),
        plot.subtitle = element_text(size = 9, colour = "grey30", margin = margin(b = 6)),
        plot.margin   = margin(10, 10, 10, 10))

# Carte facettee SEULE : panneau (a) de la figure combinee ; export standalone
# deja produit par 3-Carte_placettes_Focus.R, donc non re-exporte ici.

# ============================================================================
# (B) BARPLOT EMPILE : barre = NOMBRE de placettes de l'essence ; portion
#     claire = placettes saines (couleur essence), portion NOIRE = placettes
#     avec >=1 arbre mort. Etiquette = nombre de ces placettes (+ %). Effectif
#     total non chiffre (deja sur les cartes via le "n=" des panneaux).
# ============================================================================
# Par essence PRESENTE : placettes avec >=1 arbre DE L'ESSENCE mort (n_mort_sp > 0)
agg <- dd[, .(n_plac = .N, n_mort = sum(n_mort_sp > 0, na.rm = TRUE)), by = species_name][order(-n_plac)]
agg[, prop_t := n_mort / n_plac]
sp8 <- as.character(agg$species_name)
cat("Barplot : placettes avec >=1 arbre de l'essence mort (effectif desc) :\n"); print(agg)

fillvec <- c(COL_FOCUS, "_mort_" = "grey15")                    # couleur essence + portion morts (noir)
agg[, species_name := factor(species_name, levels = rev(sp8))]  # plus gros effectif en haut
long <- rbind(
  agg[, .(species_name, n = n_plac - n_mort, part = "sain")],
  agg[, .(species_name, n = n_mort,          part = "mort")]
)
long[, fill_key := fifelse(part == "mort", "_mort_", as.character(species_name))]
long[, fill_key := factor(fill_key, levels = c(sp8, "_mort_"))]   # _mort_ (noir) en bout de barre

# Axe y du barplot = nom d'espece seul (effectif retire : redondant avec les cartes).
p_bar <- ggplot(long, aes(n, species_name, fill = fill_key)) +
  geom_col(width = 0.78, position = position_stack(reverse = TRUE)) +  # noir au bout droit
  geom_text(data = agg, inherit.aes = FALSE,
            aes(x = n_plac, y = species_name,
                label = sprintf("%s  (%.1f %%)", format(n_mort, big.mark = " "), 100 * prop_t)),
            hjust = -0.06, size = 4.2, colour = "grey10") +
  scale_fill_manual(values = fillvec, guide = "none") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.30))) +
  labs(title = "Proportion de placettes avec au moins un arbre mort",
       subtitle = "Barre = nombre de placettes ; portion noire = placettes avec ≥1 arbre de l'essence mort ; étiquette = leur nombre (et %)",
       x = "Nombre de placettes", y = NULL) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.major.y = element_blank(),
        panel.grid.minor    = element_blank(),
        plot.title    = element_text(face = "bold"),
        plot.subtitle = element_text(size = 8.6, colour = "grey30"),
        axis.text.y   = element_text(face = "italic", size = 13, colour = "grey10"))

# Barplot SEUL : intermediaire (= panneau (b) de la figure combinee), non exporte.
# Reactiver si besoin :
# ggsave(file.path(DIR_OUT, "IFN_barplot_essences_etudiees.png"), p_bar, width = 9, height = 4.6, dpi = 160)

# ============================================================================
# (C) FIGURE COMBINEE : carte (a) + barplot (b), couleurs partagees.
#     Legende de la carte retiree : les barres colorees du barplot servent
#     de cle de couleur commune.
# ============================================================================
# Lettres de panneau integrees aux titres (hjust = 0) -> "a"/"b" alignes avec
# leur titre, plutot que les tags patchwork places sur une ligne separee.
p_map_c <- p_map +
  labs(title = "a   Répartition spatiale des placettes", subtitle = NULL) +
  theme(legend.position = "none", plot.title = element_text(face = "bold", size = 14, hjust = 0))
p_bar_c <- p_bar +
  labs(title = "b   Proportion de placettes touchées par la mortalité", subtitle = NULL) +
  theme(plot.title = element_text(face = "bold", size = 14, hjust = 0))

# Carte facettee (8 mini-cartes) plus large -> on lui donne plus de place que
# le barplot et on elargit la figure pour garder les panneaux lisibles.
combo <- p_map_c + p_bar_c + plot_layout(widths = c(1.5, 1)) +
  plot_annotation(
    title = "Placettes du jeu de modélisation : répartition spatiale et mortalité par essence",
    theme = theme(plot.title = element_text(face = "bold", size = 15)))

OUT_COMBO <- file.path(DIR_OUT, "IFN_figure_combinee_carte_barplot.png")
ggsave(OUT_COMBO, combo, width = 16.5, height = 7.6, dpi = 300)
cat(sprintf("Figure combinee : %s\n", OUT_COMBO))
