# source("S:/Projets/stage_JeremyG/4-Travail_bis/4-Modeles/1-Mortalite/2-Figures/81-Fig_comparaison_ECE_vs_moyen_7metriques_binaire.R")
# ==============================================================================
# Objectif (iv), REPONSE BINAIRE, format "script 35" enrichi a 7 metriques.
#   Compare ECE (6 indices d'extremes) vs MOYENNES SAISONNIERES, sur les MEMES
#   5 bases (comparaison propre : seule difference = extreme vs moyenne).
#   A - Performances : AUC / prAUC / Sensibilite / TSS / Kappa / Justesse
#       (couleur = indice, forme = modele ; moyenne inter-bases, barre = range)
#   B - IR climat (dumbbell) : importance portee par le climat, ECE vs Moyennes
#   C - Tableau IR climat (ECE | Moyennes | delta), couleur = modele superieur
#   -> 6 metriques de perf + IR climat = 7 metriques.
# CHE-C exclue. ASCII pur. Sortie : <run ECE>/Figures/Perf_ECE_vs_moyen/.
# ==============================================================================
suppressPackageStartupMessages({ library(data.table); library(ggplot2); library(patchwork) })

if (!exists(".PFX")) .PFX <- if (dir.exists("S:/Projets")) "S:" else "/Volumes/_donnees"
.BASE <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/5-Modeles")
if (!exists("RUN_ECE")) RUN_ECE <- "Mortalite_2015-2024_r070_n1000_binaire"
if (!exists("RUN_MOY")) RUN_MOY <- "ECE_Moyen_5bases_2015-2023_binaire"
.cl_dir <- function(tag) { p <- file.path(.BASE, "standard", tag); if (dir.exists(p)) p else file.path(.BASE, tag) }
.DIRF_OUT <- file.path(.BASE, "standard", RUN_ECE, "Figures", "Perf_ECE_vs_moyen")
dir.create(.DIRF_OUT, showWarnings = FALSE, recursive = TRUE)

ORD_ESP  <- c("QURO","QUPE","FASY","PISY","PINI","ABAL","PIAB","BEPE")
ESP_NOMS <- c(QURO="Q. robur", QUPE="Q. petraea", FASY="F. sylvatica", PISY="P. sylvestris",
              PINI="P. nigra",  ABAL="A. alba",    PIAB="P. abies",     BEPE="B. pendula")

# ---- Chargement (ECE et Moyennes : 8 especes x 5 bases, CHE-C exclue) --------
sy_ece_raw <- fread(file.path(.BASE,"standard",RUN_ECE,"2-Syntheses","Synthese_globale.csv"))[base_code != "CHEDS" & esp_code %in% ORD_ESP]
sy_moy_raw <- fread(file.path(.cl_dir(RUN_MOY),"2-Syntheses","Synthese_globale.csv"))[base_code != "CHEDS" & esp_code %in% ORD_ESP]

# ---- IR climat (somme des IR des variables climatiques, RI a 100 %/modele) ---
VAR_FIXES_RI <- c("pH","G_ha_tot","Gini","c13_moy_sp","prop_G")
ri_sum_clim <- function(f) {
  ri <- fread(f)[base_code != "CHEDS" & esp_code %in% ORD_ESP]
  ri[, .(IRclim = sum(RI[!(variable %in% VAR_FIXES_RI)], na.rm = TRUE)), by = .(esp_code, base_code)]
}
ir_ece_ag <- ri_sum_clim(file.path(.BASE,"standard",RUN_ECE,"2-Syntheses","RI_par_variable.csv"))[
  , .(IR_ece = mean(IRclim), IR_ece_min = min(IRclim), IR_ece_max = max(IRclim)), by = esp_code]
ir_cl_ag  <- ri_sum_clim(file.path(.cl_dir(RUN_MOY),"2-Syntheses","RI_par_variable.csv"))[
  , .(IR_cl = mean(IRclim), IR_cl_min = min(IRclim), IR_cl_max = max(IRclim)), by = esp_code]

# ---- Agregation inter-bases (moyenne + range) pour les deux modeles ----------
agg_perf <- function(raw, lab) raw[, .(
  AUC_moy   = mean(AUC_moy),   AUC_min   = min(AUC_moy),   AUC_max   = max(AUC_moy),
  PRAUC_moy = mean(PRAUC_moy), PRAUC_min = min(PRAUC_moy), PRAUC_max = max(PRAUC_moy),
  Sens_moy  = mean(Sens_moy),  Sens_min  = min(Sens_moy),  Sens_max  = max(Sens_moy),
  TSS_moy   = mean(TSS_moy),   TSS_min   = min(TSS_moy),   TSS_max   = max(TSS_moy),
  Kappa_moy = mean(Kappa_moy), Kappa_min = min(Kappa_moy), Kappa_max = max(Kappa_moy),
  Acc_moy   = mean(Acc_moy),   Acc_min   = min(Acc_moy),   Acc_max   = max(Acc_moy)
), by = esp_code][, type := lab]
dt <- rbind(agg_perf(sy_ece_raw, "ECE"), agg_perf(sy_moy_raw, "Moyennes"))
dt[, esp_f  := factor(esp_code, levels = rev(ORD_ESP), labels = rev(ESP_NOMS[ORD_ESP]))]
dt[, type_f := factor(type, levels = c("ECE","Moyennes"))]

# ---- Palette + theme ---------------------------------------------------------
COL_MET <- c(AUC="#1B9E77", prAUC="#E7298A", Sensibilite="#D95F02",
             TSS="#7570B3", Kappa="#A6761D", Justesse="#E6AB02")           # couleur = indice (Kappa en ocre : pas 2 verts)
SHP_MOD <- c(ECE = 16L, Moyennes = 2L)                                      # cercle plein = ECE ; triangle vide = Moyennes
LBL_MOD <- c(ECE = "ECE (extremes)", Moyennes = "Moyennes saison.")
COL_MOD <- c(ECE = "#2166AC", Moyennes = "#D4834A")

N_ESP       <- length(ORD_ESP)
.bands_dt   <- data.table(k = seq_len(N_ESP))[k %% 2L == 0L][, .(ymin = k - 0.5, ymax = k + 0.5)]
.band_layer <- geom_rect(data = .bands_dt, aes(ymin = ymin, ymax = ymax),
                         xmin = -Inf, xmax = Inf, fill = "grey92", inherit.aes = FALSE)
.thm <- theme_bw(base_size = 10) + theme(
  panel.grid = element_blank(),                        # quadrillage retire (bandes alternees suffisent)
  axis.text.y        = element_text(face = "italic", size = 9),
  axis.title.x       = element_text(size = 9), axis.title.y = element_blank(),
  plot.title         = element_text(face = "bold", size = 11),
  legend.position    = "bottom", legend.title = element_text(size = 8),
  legend.text        = element_text(size = 8), legend.key.height = unit(0.38, "cm"),
  legend.margin      = margin(0,0,0,0), plot.margin = margin(4,8,2,4))

# ==============================================================================
# A : performances (6 metriques) -- couleur = indice ; forme = modele
# ==============================================================================
perf_long <- rbindlist(list(
  dt[, .(esp_f, type_f, metric="AUC",         val=AUC_moy,   lo=AUC_min,   hi=AUC_max)],
  dt[, .(esp_f, type_f, metric="prAUC",       val=PRAUC_moy, lo=PRAUC_min, hi=PRAUC_max)],
  dt[, .(esp_f, type_f, metric="Sensibilite", val=Sens_moy,  lo=Sens_min,  hi=Sens_max)],
  dt[, .(esp_f, type_f, metric="TSS",         val=TSS_moy,   lo=TSS_min,   hi=TSS_max)],
  dt[, .(esp_f, type_f, metric="Kappa",       val=Kappa_moy, lo=Kappa_min, hi=Kappa_max)],
  dt[, .(esp_f, type_f, metric="Justesse",    val=Acc_moy,   lo=Acc_min,   hi=Acc_max)]
))
perf_long[, metric := factor(metric, levels = c("AUC","prAUC","Sensibilite","TSS","Kappa","Justesse"))]
.pd <- position_dodge(width = 0.8)
gPerf <- ggplot(perf_long, aes(y = esp_f, x = val, color = metric, group = metric)) +
  .band_layer +
  geom_errorbar(aes(xmin = lo, xmax = hi), width = 0, linewidth = 0.42, alpha = 0.6,
                orientation = "y", position = .pd) +
  geom_point(aes(shape = type_f), size = 2.1, stroke = 0.75, position = .pd) +
  scale_color_manual(values = COL_MET, name = expression(underline(bold("Indice")))) +
  scale_shape_manual(values = SHP_MOD, labels = LBL_MOD, name = expression(underline(bold("Modele")))) +
  scale_x_continuous(name = "Valeur de l'indice (AUC / prAUC / Sensibilite / TSS / Kappa / Justesse)") +
  guides(color = guide_legend(order = 1, nrow = 2, override.aes = list(shape = 15, size = 3.4)),
         shape = guide_legend(order = 2, nrow = 2, override.aes = list(size = 3))) +
  labs(title = "A. Performances (6 indices)") + .thm

# ==============================================================================
# B : IR climat -- ECE vs Moyennes (dumbbell, range pour les deux)
# ==============================================================================
ir_dt <- merge(ir_ece_ag, ir_cl_ag, by = "esp_code")
ir_dt[, esp_f := factor(esp_code, levels = rev(ORD_ESP), labels = rev(ESP_NOMS[ORD_ESP]))]
gIR <- ggplot(ir_dt, aes(y = esp_f)) +
  .band_layer +
  geom_errorbar(aes(xmin = IR_cl_min,  xmax = IR_cl_max),  width = 0.22, linewidth = 0.5, color = COL_MOD[["Moyennes"]], alpha = 0.7) +
  geom_errorbar(aes(xmin = IR_ece_min, xmax = IR_ece_max), width = 0.22, linewidth = 0.5, color = COL_MOD[["ECE"]],      alpha = 0.7) +
  geom_point(aes(x = IR_cl,  color = "Moyennes"), shape = 17, size = 2.6) +
  geom_point(aes(x = IR_ece, color = "ECE"),      shape = 16, size = 2.6) +
  scale_color_manual(values = COL_MOD, name = expression(underline(bold("Modele"))),
                     breaks = c("ECE","Moyennes"),
                     labels = c(ECE = "ECE (barre = range)", Moyennes = "Moyennes (barre = range)"),
                     guide = guide_legend(nrow = 2)) +
  scale_x_continuous(name = "IR climat (%)") +
  labs(title = "B. Importance du climat (IR climat)") + .thm

# ==============================================================================
# C : tableau IR climat seul -- ECE vs Moyennes (couleur delta = superiorite)
# ==============================================================================
tab <- merge(ir_ece_ag[, .(esp_code, IR_ece)], ir_cl_ag[, .(esp_code, IR_cl)], by = "esp_code")
tab[, esp_code := factor(esp_code, levels = ORD_ESP)]; setorder(tab, esp_code)
MET <- list(list(lab = "IR climat (%)", ece = "IR_ece", cl = "IR_cl", dig = 1L))
F_ECE_W   <- "#CFE3F5"; F_CL_W   <- "#F6DDC4"
F_DELTA_E <- "#AECBE8"; F_DELTA_C <- "#EEC7A0"
T_ECE     <- "#1A5C9E"; T_CL     <- "#B5651B"

render_ir_table <- function(tab) {
  W_ESP <- 3.0; W_SUB <- 1.7; n_met <- length(MET)
  num_cols <- unique(unlist(lapply(MET, function(z) c(z$ece, z$cl))))
  m_vals   <- tab[, lapply(.SD, mean, na.rm = TRUE), .SDcols = num_cols]
  m_row    <- copy(tab[1L]); m_row[, (num_cols) := as.list(m_vals)]
  tabx     <- rbind(copy(tab)[, is_mean := FALSE], m_row[, is_mean := TRUE])
  nd <- nrow(tabx)
  sub_xl <- vector("list", n_met); cur <- W_ESP
  for (m in seq_len(n_met)) { sub_xl[[m]] <- cur + c(0, W_SUB, 2*W_SUB); cur <- cur + 3*W_SUB }
  WTOT <- cur; HR <- 1.0; HH1 <- 1.0; HH2 <- 0.9
  ytop0 <- nd*HR + HH1 + HH2
  R <- list(); TT <- list(); S <- list()
  aR <- function(x0,x1,y0,y1,f) R[[length(R)+1]] <<- data.table(xmin=x0,xmax=x1,ymin=y0,ymax=y1,fill=f)
  aT <- function(x,y,l,col="black",face="plain",sz=3.0,hj=0.5) TT[[length(TT)+1]] <<- data.table(x=x,y=y,label=l,col=col,face=face,sz=sz,hjust=hj)
  aS <- function(x0,x1,y0,y1,lw=0.4,col="grey55") S[[length(S)+1]] <<- data.table(x=x0,xend=x1,y=y0,yend=y1,lw=lw,col=col)
  y1 <- ytop0; y0 <- ytop0 - HH1
  aR(0, W_ESP, y0, y1, "#3E3E3E"); aT(W_ESP/2, (y0+y1)/2, "Espece", "white","bold.italic",3.4)
  for (m in seq_len(n_met)) { gx0 <- sub_xl[[m]][1]; gx1 <- sub_xl[[m]][3]+W_SUB
    aR(gx0, gx1, y0, y1, "#3E3E3E"); aT((gx0+gx1)/2, (y0+y1)/2, MET[[m]]$lab, "white","bold",3.0) }
  y1 <- y0; y0 <- y0 - HH2
  aR(0, W_ESP, y0, y1, "#6E6E6E")
  for (m in seq_len(n_met)) { sx <- sub_xl[[m]]
    aR(sx[1], sx[1]+W_SUB, y0, y1, "#2166AC"); aT(sx[1]+W_SUB/2, (y0+y1)/2, "ECE",     "white","bold",2.9)
    aR(sx[2], sx[2]+W_SUB, y0, y1, "#9C7B57"); aT(sx[2]+W_SUB/2, (y0+y1)/2, "Moyennes","white","bold",2.9)
    aR(sx[3], sx[3]+W_SUB, y0, y1, "#6E6E6E"); aT(sx[3]+W_SUB/2, (y0+y1)/2, "delta",   "white","bold",2.9) }
  yb <- y0
  for (i in seq_len(nd)) {
    r <- tabx[i]; is_mn <- isTRUE(r$is_mean); yT <- yb; yB <- yb - HR; ym <- (yT+yB)/2
    aR(0, W_ESP, yB, yT, if (is_mn) "#DCDCDC" else if (i %% 2 == 0) "#F2F2F2" else "white")
    lbl_esp <- if (is_mn) "Moyenne" else as.character(ESP_NOMS[as.character(r$esp_code)])
    aT(0.12, ym, lbl_esp, "black", if (is_mn) "bold" else "italic", 3.1, 0)
    for (m in seq_len(n_met)) {
      sx <- sub_xl[[m]]; ve <- r[[MET[[m]]$ece]]; vc <- r[[MET[[m]]$cl]]; dg <- MET[[m]]$dig
      dr <- round(ve - vc, dg)
      ece_win <- isTRUE(dr > 0); cl_win <- isTRUE(dr < 0)
      fE <- if (ece_win) F_ECE_W else "white"; fC <- if (cl_win) F_CL_W else "white"
      fD <- if (ece_win) F_DELTA_E else if (cl_win) F_DELTA_C else "white"
      tD <- if (ece_win) T_ECE     else if (cl_win) T_CL      else "grey55"
      dlab <- if (dr == 0) formatC(0, format="f", digits=dg) else formatC(dr, format="f", digits=dg, flag="+")
      aR(sx[1], sx[1]+W_SUB, yB, yT, fE); aT(sx[1]+W_SUB/2, ym, formatC(ve, format="f", digits=dg), "black", if (ece_win || is_mn) "bold" else "plain", 3.0)
      aR(sx[2], sx[2]+W_SUB, yB, yT, fC); aT(sx[2]+W_SUB/2, ym, formatC(vc, format="f", digits=dg), "black", if (cl_win  || is_mn) "bold" else "plain", 3.0)
      aR(sx[3], sx[3]+W_SUB, yB, yT, fD); aT(sx[3]+W_SUB/2, ym, dlab, tD, "bold", 3.0)
    }
    yb <- yB
  }
  y_bot <- yb
  aS(0, WTOT, y_bot + HR, y_bot + HR, 0.8, "grey25")
  xseps <- c(W_ESP, vapply(seq_len(n_met), function(m) sub_xl[[m]][3]+W_SUB, numeric(1)))
  for (xb in xseps) aS(xb, xb, y_bot, ytop0, 0.7, "grey35")
  for (m in seq_len(n_met)) for (xx in sub_xl[[m]]) aS(xx, xx, y_bot, y0, 0.25, "grey80")
  for (i in 0:nd) aS(0, WTOT, y_bot + i*HR, y_bot + i*HR, 0.25, "grey80")
  aS(0,0, y_bot, ytop0, 0.7, "grey35"); aS(WTOT,WTOT, y_bot, ytop0, 0.7, "grey35")
  aS(0, WTOT, ytop0, ytop0, 0.8, "grey25"); aS(0, WTOT, y_bot, y_bot, 0.8, "grey25")
  aS(0, WTOT, y0, y0, 0.6, "grey35")
  yl <- y_bot - 0.75
  aR(0.2, 0.7, yl-0.18, yl+0.18, F_DELTA_E); aT(0.85, yl, "delta > 0 : ECE superieur", T_ECE, "plain", 3.0, 0)
  aR(0.2, 0.7, yl-0.78-0.18, yl-0.78+0.18, F_DELTA_C); aT(0.85, yl-0.78, "delta < 0 : Moyennes superieur", T_CL, "plain", 3.0, 0)
  Rd <- rbindlist(R); Td <- rbindlist(TT); Sd <- rbindlist(S)
  ggplot() +
    geom_rect(data=Rd, aes(xmin=xmin,xmax=xmax,ymin=ymin,ymax=ymax,fill=fill), color="grey90", linewidth=0.12) +
    geom_segment(data=Sd, aes(x=x,xend=xend,y=y,yend=yend,linewidth=lw,color=col)) +
    geom_text(data=Td, aes(x=x,y=y,label=label,color=col,fontface=face,size=sz,hjust=hjust), family="sans") +
    scale_fill_identity() + scale_color_identity() + scale_size_identity() + scale_linewidth_identity() +
    coord_equal(expand=FALSE, clip="off") + theme_void() +
    ggtitle("C. IR climat (%)") +
    theme(plot.title = element_text(hjust=0.5, face="bold", size=11), plot.margin = margin(6,6,6,6))
}
g_tab <- render_ir_table(tab)

# ---- Assemblage --------------------------------------------------------------
g_all <- (gPerf | plot_spacer() | gIR | g_tab) +
  plot_layout(widths = c(2.2, 0.26, 1.35, 1.35)) +
  plot_annotation(
    title    = "Comparaison ECE (extremes) vs climat moyen saisonnier, par espece (modele binaire)",
    subtitle = paste0(
      "ECE : 6 indices d'extremes x 5 bases (moyenne inter-bases, barre = range) | ",
      "Moyennes : 6 moyennes saisonnieres x 5 bases (barre = range) ; memes bases, meme periode 2015-2023\n",
      "Variables fixes identiques dans les deux modeles (pH, G_ha_tot, Gini, c13_moy_sp, prop_G) | ",
      "IR climat = part d'importance relative portee par le climat (RI a 100 %/modele)"),
    theme = theme(plot.title = element_text(face = "bold", size = 13),
                  plot.subtitle = element_text(size = 8, color = "grey35")))

.suf <- sub("^Mortalite_", "", RUN_ECE)
f_pdf <- file.path(.DIRF_OUT, sprintf("Fig_comparaison_ECE_vs_moyen_7metriques__%s.pdf", .suf))
grDevices::pdf(f_pdf, width = 15, height = 8.5); suppressWarnings(print(g_all)); grDevices::dev.off()
cat("PDF :", f_pdf, "\n")
f_png <- file.path(.DIRF_OUT, sprintf("Fig_comparaison_ECE_vs_moyen_7metriques__%s.png", .suf))
suppressWarnings(ggsave(f_png, g_all, width = 15, height = 8.5, dpi = 150, bg = "white"))
cat("PNG :", f_png, "\n")

# ---- recap console -----------------------------------------------------------
recap <- merge(dt[type=="ECE", .(esp_code, AUC_ece=AUC_moy, Kappa_ece=Kappa_moy, Acc_ece=Acc_moy)],
               dt[type=="Moyennes", .(esp_code, AUC_moy2=AUC_moy, Kappa_moy2=Kappa_moy, Acc_moy2=Acc_moy)], by="esp_code")
recap <- merge(recap, tab[, .(esp_code, IR_ece, IR_cl)], by="esp_code")
cat("\n=== Recap ECE vs Moyennes (par espece) ===\n"); print(recap)
