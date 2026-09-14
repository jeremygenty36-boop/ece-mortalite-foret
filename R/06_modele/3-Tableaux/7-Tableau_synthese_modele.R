# source("S:/Projets/stage_JeremyG/4-Travail/4-Modeles/1-Mortalite/3-Tableaux/7-Tableau_synthese_modele.R")
# ============================================================================
# TABLEAU DE SYNTHESE DU MODELE DE MORTALITE (style Carletti et al. 2026).
#   Une ligne par espece x base : AUC | Sensibilite | somme des IR ECE |
#   puis par type de stress (Froid / Chaud / Secheresse) les 2 indices,
#   ordonnes par importance decroissante : Nom / IR / Sens de l'effet.
#     IR   = importance relative (normalisee a 100 % par modele ; cf 1-Modele).
#     Sens = sens de l'effet du STRESS (convention "stress", cf STRESS_DIR) :
#            "+" le stress (froid/chaud/secheresse) augmente la mortalite, "-" il la diminue.
#            Pour TNn/SPEI6, le stress = baisse de l'indice (hiver plus froid / sol plus sec).
# Lit Synthese_globale.csv (AUC, Sensibilite) et RI_par_variable.csv (IR, sens),
#   tous deux produits par 1-Modele_mortalite.R.
# Sorties :
#   - CSV large (48 lignes) + version par espece (8 lignes, moyenne des bases)
#       -> 5-Resultats/5-Modeles/Mortalite/
#   - .tex publiables -> 5-Resultats/6-Figures et tableaux redaction/3-Resultats/Modele/
# Lecture/ecriture legere : tourne sur Mac ou Windows. ASCII pur dans le code.
# ============================================================================
suppressPackageStartupMessages({ library(data.table) })
if (!exists(".PFX")) .PFX <- if (dir.exists("S:/Projets")) "S:" else "/Volumes/_donnees"
if (!exists("RUN_TAG")) RUN_TAG <- "Mortalite_2009-2023_r075"
.VARIANTE_DIR <- if (grepl("_dominants$", RUN_TAG)) "dominants" else if (grepl("_domines$", RUN_TAG)) "domines" else if (grepl("_pur080$", RUN_TAG)) "pur080" else "standard"  # niveau jeu de donnees (cf 6-Extraction_bases_variantes.R)
# Masque effectifs faibles : metriques mises a NA ("--") si moins de SEUIL_MORTS
# placettes avec morts (n_morts) -- AUC/Sens peu fiables sur evenement rare.
if (!exists("SEUIL_MORTS")) SEUIL_MORTS <- 30L
DIRM    <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/5-Modeles", .VARIANTE_DIR, RUN_TAG)
DIRM_SY <- file.path(DIRM, "2-Syntheses")
DIRT <- file.path(.PFX, "Projets/stage_JeremyG",
                  "5-Resultats/6-Figures et tableaux redaction/3-Resultats/Modele", .VARIANTE_DIR)
dir.create(DIRT, showWarnings = FALSE, recursive = TRUE)

# --- lecture des sorties du modele ------------------------------------------
syn <- fread(file.path(DIRM_SY, "Synthese_globale.csv"))
ri  <- fread(file.path(DIRM_SY, "RI_par_variable.csv"))
if (!exists("BASES_EXCLUES_CODE")) BASES_EXCLUES_CODE <- "CHEDS"   # CHE-C ecartee de l'analyse
syn <- syn[!base_code %in% BASES_EXCLUES_CODE]
ri  <- ri[!base_code %in% BASES_EXCLUES_CODE]
# robustesse : si le modele n'a pas encore ete relance avec Sens/sens_effet
if (!"Sens_moy"   %in% names(syn)) { syn[, Sens_moy   := NA_real_]
  cat("ATTENTION : Sens_moy absent de Synthese_globale.csv -- relancer 1-Modele_mortalite.R.\n") }
if (!"PRAUC_moy" %in% names(syn)) { syn[, PRAUC_moy := NA_real_]
  cat("ATTENTION : PRAUC_moy absent de Synthese_globale.csv -- relancer 1-Modele_mortalite.R.\n") }
if (!"Acc_moy"   %in% names(syn)) { syn[, Acc_moy   := NA_real_]
  cat("ATTENTION : Acc_moy absent de Synthese_globale.csv -- relancer 1-Modele_mortalite.R.\n") }
if (!"n_morts"   %in% names(syn)) { syn[, n_morts   := NA_real_]
  cat("ATTENTION : n_morts absent de Synthese_globale.csv -- masque effectifs inactif.\n") }
if (!"sens"  %in% names(ri)) { ri[, sens  := NA_character_]
  cat("ATTENTION : colonne 'sens' absente de RI_par_variable.csv -- relancer le modele.\n") }
if (!"dmort" %in% names(ri))   ri[, dmort := NA_real_]

# --- indices ECE : retire le suffixe de base, mappe le groupe de stress ------
BC  <- c("EOB10", "SAF8", "CHE1", "EOBDS", "SAFDS", "CHEDS")
ri[, indice := gsub(paste0("_(", paste(BC, collapse = "|"), ")$"), "", variable)]
GRP <- c(TNn = "Froid", CWN = "Froid", TXx = "Chaud", HWN = "Chaud",
         SPEI6 = "Sec", WG10P = "Sec")
ece <- ri[indice %in% names(GRP)]
ece[, groupe := factor(GRP[indice], levels = c("Froid", "Chaud", "Sec"))]

# --- SENS de la fleche : convention d'interpretation ------------------------
# Le modele estime dmort = effet sur la mortalite d'une HAUSSE de l'indice (p90 vs p10).
# Or une hausse n'a pas le meme sens ecologique selon l'indice :
#   stress AUGMENTE avec l'indice (+1) : TXx, HWN (chaleur), CWN (froid), WG10P (jours secs)
#   stress DIMINUE avec l'indice (-1)  : TNn (hiver plus doux), SPEI6 (sol plus humide)
# SENS_CONVENTION = "stress" -> la fleche montre l'effet du STRESS (froid/chaud/secheresse)
#   sur la mortalite : coherent dans un groupe (WG10P et SPEI6 pointent dans le meme sens
#   quand la secheresse est deletere). "indice" -> effet brut d'une hausse de l'indice.
SENS_CONVENTION <- "stress"
STRESS_DIR <- c(TXx = 1, HWN = 1, CWN = 1, WG10P = 1, TNn = -1, SPEI6 = -1)
.sdir <- function(ind) if (SENS_CONVENTION == "stress") STRESS_DIR[ind] else rep(1, length(ind))
ece[, dmort_stress := dmort * .sdir(indice)]
ece[, sens := fifelse(is.na(dmort_stress), NA_character_, fifelse(dmort_stress > 0, "+", "-"))]

# --- construit le tableau large a partir d'une table ECE et de cles ----------
#   ordre fixe par indice : TNn/CWN (Froid), TXx/HWN (Chaud), SPEI6/WG10P (Sec)
IND_RANG <- c(TNn = 1L, CWN = 2L, TXx = 1L, HWN = 2L, SPEI6 = 1L, WG10P = 2L)
build_wide <- function(ece_dt, keys) {
  w <- ece_dt[, .(somme_IR_ECE = round(sum(RI, na.rm = TRUE), 2)), by = keys]
  e <- copy(ece_dt)
  e[, rang := IND_RANG[indice]]
  e[, sens_aff := fifelse(is.na(sens) | RI == 0, "", sens)]   # vide si non retenu
  for (g in c("Froid", "Chaud", "Sec")) for (rg in 1:2) {
    sub <- e[groupe == g & rang == rg, c(keys, "indice", "RI", "sens_aff"), with = FALSE]
    sub[, RI := round(RI, 2)]
    setnames(sub, c("indice", "RI", "sens_aff"),
             paste0(g, "_", c("nom", "IR", "sens"), rg))
    w <- merge(w, sub, by = keys, all.x = TRUE)
  }
  w
}

# ====== TABLEAU 1 : par espece x base (48 lignes) ===========================
KB   <- c("espece", "esp_code", "base", "base_code")
.wb <- build_wide(ece, KB)
wide <- merge(
  syn[, .(espece, esp_code, base, base_code, AUC=AUC_moy, PRAUC=PRAUC_moy, Sensibilite=Sens_moy, Accuracy=Acc_moy, n_morts)],
  .wb[, !c("esp_code","base_code"), with=FALSE],
  by = c("espece", "base"), all.x = TRUE)
wide[is.na(somme_IR_ECE), somme_IR_ECE := 0]

# --- MASQUE effectifs faibles : NA sur toutes les metriques si n_morts < seuil --
.MCOL_NUM <- c("AUC","PRAUC","Sensibilite","Accuracy","somme_IR_ECE",
               "Froid_IR1","Froid_IR2","Chaud_IR1","Chaud_IR2","Sec_IR1","Sec_IR2")
.MCOL_CHR <- c("Froid_nom1","Froid_sens1","Froid_nom2","Froid_sens2",
               "Chaud_nom1","Chaud_sens1","Chaud_nom2","Chaud_sens2",
               "Sec_nom1","Sec_sens1","Sec_nom2","Sec_sens2")
.masq <- !is.na(wide$n_morts) & wide$n_morts < SEUIL_MORTS
wide[.masq, (.MCOL_NUM) := NA_real_]
wide[.masq, (.MCOL_CHR) := NA_character_]
cat(sprintf("Masque effectifs (n_morts < %d) : %d / %d lignes espece x base masquees.\n",
            SEUIL_MORTS, sum(.masq), nrow(wide)))

ORD_ESP  <- c("Quercus robur", "Quercus petraea", "Fagus sylvatica",
              "Pinus sylvestris", "Pinus nigra subsp. nigra",
              "Abies alba", "Picea abies", "Betula pendula")
ORD_BASE <- c("EOB-10", "SAF-8", "CHE-1", "EOB-DS", "SAF-DS")   # CHE-C ecartee de l'analyse
wide[, espece := factor(espece, levels = ORD_ESP)]
wide[, base   := factor(base,   levels = ORD_BASE)]
setcolorder(wide, c(KB, "n_morts", "AUC", "PRAUC", "Sensibilite", "Accuracy", "somme_IR_ECE",
  "Froid_nom1","Froid_IR1","Froid_sens1","Froid_nom2","Froid_IR2","Froid_sens2",
  "Chaud_nom1","Chaud_IR1","Chaud_sens1","Chaud_nom2","Chaud_IR2","Chaud_sens2",
  "Sec_nom1","Sec_IR1","Sec_sens1","Sec_nom2","Sec_IR2","Sec_sens2"))
setorder(wide, espece, base)
f_csv <- file.path(DIRM_SY, "Tableau_synthese_modele.csv")
fwrite(wide, f_csv, sep = ";")
cat("CSV (espece x base) :", f_csv, "\n")

# ====== TABLEAU 2 : par espece (moyenne des 6 bases, 8 lignes) ==============
ece_esp <- ece[, .(RI = mean(RI, na.rm = TRUE), dmort = mean(dmort, na.rm = TRUE)),
               by = .(espece, esp_code, indice, groupe)]
ece_esp[, sens := { ds <- dmort * .sdir(indice)
  fifelse(is.na(ds), NA_character_, fifelse(ds > 0, "+", "-")) }]
wide_esp <- build_wide(ece_esp, c("espece", "esp_code"))
auc_esp  <- syn[, .(AUC         = round(mean(AUC_moy,   na.rm = TRUE), 3),
                    PRAUC       = round(mean(PRAUC_moy, na.rm = TRUE), 3),
                    Sensibilite = round(mean(Sens_moy,  na.rm = TRUE), 3),
                    Accuracy    = round(mean(Acc_moy,   na.rm = TRUE), 3),
                    n_morts     = round(mean(n_morts,   na.rm = TRUE))), by = espece]
wide_esp <- merge(auc_esp, wide_esp, by = "espece", all.x = TRUE)
wide_esp[is.na(somme_IR_ECE), somme_IR_ECE := 0]
.masq_e <- !is.na(wide_esp$n_morts) & wide_esp$n_morts < SEUIL_MORTS
wide_esp[.masq_e, (.MCOL_NUM) := NA_real_]
wide_esp[.masq_e, (.MCOL_CHR) := NA_character_]
wide_esp[, espece := factor(espece, levels = ORD_ESP)]
setcolorder(wide_esp, c("espece", "esp_code", "n_morts", "AUC", "PRAUC", "Sensibilite", "Accuracy", "somme_IR_ECE",
  "Froid_nom1","Froid_IR1","Froid_sens1","Froid_nom2","Froid_IR2","Froid_sens2",
  "Chaud_nom1","Chaud_IR1","Chaud_sens1","Chaud_nom2","Chaud_IR2","Chaud_sens2",
  "Sec_nom1","Sec_IR1","Sec_sens1","Sec_nom2","Sec_IR2","Sec_sens2"))
setorder(wide_esp, espece)
f_csv2 <- file.path(DIRM_SY, "Tableau_synthese_modele_par_espece.csv")
fwrite(wide_esp, f_csv2, sep = ";")
cat("CSV (par espece)    :", f_csv2, "\n")

# ===================== MISE EN FORME LISIBLE ===============================
# Chaque indice -> une cellule compacte "Nom IR (icone)" ; les 6 bases d'une
# meme espece sont regroupees (cellule espece fusionnee dans le xlsx et le tex).
UP <- intToUtf8(0x25B2); DN <- intToUtf8(0x25BC)   # triangles haut/bas (source ASCII)
.f <- function(x, d) fifelse(is.na(x), "--", formatC(x, format = "f", digits = d))  # NA masque -> "--"

mk_cell <- function(nom, IR, sens, glyph) {        # texte compact d'une cellule indice
  up <- if (glyph) UP else "+"; dn <- if (glyph) DN else "-"
  ic <- fifelse(!is.na(sens) & sens == "+", paste0(" ", up),
        fifelse(!is.na(sens) & sens == "-", paste0(" ", dn), ""))
  fifelse(is.na(IR) | is.na(nom) | nom == "", "",
    fifelse(IR == 0, nom,                            # indice non retenu -> nom seul
      paste0(nom, " ", formatC(IR, format = "f", digits = 2), ic)))
}
build_compact <- function(w, glyph) data.table(
  Espece  = as.character(w$espece),
  Base    = if ("base" %in% names(w)) as.character(w$base) else "moy. 6 bases",
  AUC     = .f(w$AUC,          3),
  PRAUC   = .f(w$PRAUC,        3),
  Sens    = .f(w$Sensibilite,  3),
  Acc     = .f(w$Accuracy,     3),
  Som_IR  = .f(w$somme_IR_ECE, 1),
  Froid_1 = mk_cell(w$Froid_nom1, w$Froid_IR1, w$Froid_sens1, glyph),
  Froid_2 = mk_cell(w$Froid_nom2, w$Froid_IR2, w$Froid_sens2, glyph),
  Chaud_1 = mk_cell(w$Chaud_nom1, w$Chaud_IR1, w$Chaud_sens1, glyph),
  Chaud_2 = mk_cell(w$Chaud_nom2, w$Chaud_IR2, w$Chaud_sens2, glyph),
  Sec_1   = mk_cell(w$Sec_nom1,   w$Sec_IR1,   w$Sec_sens1,   glyph),
  Sec_2   = mk_cell(w$Sec_nom2,   w$Sec_IR2,   w$Sec_sens2,   glyph))

# --- CSV compact lisible (sans tableur ; +/- au lieu des triangles) ---------
fwrite(build_compact(wide, glyph = FALSE),
       file.path(DIRM_SY, "Tableau_synthese_modele_lisible.csv"), sep = ";")

# --- XLSX : cellule espece fusionnee, bande de groupes, bordures, couleurs --
f_xlsx <- sub("\\.csv$", ".xlsx", f_csv)
add_sheet <- function(wb, nm, w) {
  oW <- openxlsx::writeData; oM <- openxlsx::mergeCells
  oA <- openxlsx::addStyle;  oC <- openxlsx::createStyle
  comp <- build_compact(w, glyph = TRUE); N <- nrow(comp); r0 <- 3L
  openxlsx::addWorksheet(wb, nm)
  oW(wb, nm, comp, startRow = r0, colNames = FALSE)
  for (j in 1:7) oW(wb, nm, c("Espece","Base","AUC","PRAUC","Sens.","Acc.","Som.IR")[j], startRow = 1, startCol = j, colNames = FALSE)
  oW(wb, nm, "Froid", startRow = 1, startCol = 8, colNames = FALSE)
  oW(wb, nm, "Chaud", startRow = 1, startCol = 10, colNames = FALSE)
  oW(wb, nm, "Secheresse", startRow = 1, startCol = 12, colNames = FALSE)
  for (j in 1:6) oW(wb, nm, c("(1)","(2)")[((j-1) %% 2) + 1], startRow = 2, startCol = 7 + j, colNames = FALSE)
  for (cc in 1:7) oM(wb, nm, cols = cc, rows = 1:2)
  oM(wb, nm, cols = 8:9, rows = 1); oM(wb, nm, cols = 10:11, rows = 1); oM(wb, nm, cols = 12:13, rows = 1)
  rl <- rle(comp$Espece); st <- r0 + c(0L, head(cumsum(rl$lengths), -1))   # blocs especes
  for (k in seq_along(rl$values)) { rs <- st[k]; re <- rs + rl$lengths[k] - 1L
    if (re > rs) oM(wb, nm, cols = 1, rows = rs:re) }
  B <- "#7F7F7F"; Bg <- "#D9D9D9"
  st_main <- oC(textDecoration="bold", halign="center", valign="center", fgFill="#D9D9D9", border="TopBottomLeftRight", borderColour=B, wrapText=TRUE)
  st_band <- oC(textDecoration="bold", halign="center", valign="center", fgFill="#BDD7EE", border="TopBottomLeftRight", borderColour=B)
  st_esp  <- oC(textDecoration="bold", halign="left",   valign="center", border="TopBottomLeftRight", borderColour=Bg)
  st_cell <- oC(halign="center", valign="center", border="TopBottomLeftRight", borderColour=Bg)
  st_red  <- oC(fontColour="#C0392B", halign="center", valign="center", border="TopBottomLeftRight", borderColour=Bg)
  st_grn  <- oC(fontColour="#1E8449", halign="center", valign="center", border="TopBottomLeftRight", borderColour=Bg)
  st_gry  <- oC(fontColour="#A6A6A6", halign="center", valign="center", border="TopBottomLeftRight", borderColour=Bg)
  st_sep  <- oC(border="Left",   borderStyle="medium", borderColour=B)
  st_spB  <- oC(border="Bottom", borderStyle="medium", borderColour=B)
  rr <- r0:(r0 + N - 1L)
  oA(wb, nm, st_main, rows=1:2, cols=1:7,  gridExpand=TRUE)
  oA(wb, nm, st_band, rows=1:2, cols=8:13, gridExpand=TRUE)
  oA(wb, nm, st_cell, rows=rr,  cols=2:13, gridExpand=TRUE)
  oA(wb, nm, st_esp,  rows=rr,  cols=1,    gridExpand=TRUE)
  gm <- list(list(8,w$Froid_IR1,w$Froid_sens1), list(9,w$Froid_IR2,w$Froid_sens2),
             list(10,w$Chaud_IR1,w$Chaud_sens1), list(11,w$Chaud_IR2,w$Chaud_sens2),
             list(12,w$Sec_IR1,w$Sec_sens1),    list(13,w$Sec_IR2,w$Sec_sens2))
  for (g in gm) { co <- g[[1]]; IR <- g[[2]]; sn <- g[[3]]
    red <- which(!is.na(IR) & IR>0 & sn=="+"); grn <- which(!is.na(IR) & IR>0 & sn=="-"); gry <- which(is.na(IR) | IR==0)
    if(length(red)) oA(wb,nm,st_red,rows=r0-1L+red,cols=co,gridExpand=FALSE,stack=TRUE)
    if(length(grn)) oA(wb,nm,st_grn,rows=r0-1L+grn,cols=co,gridExpand=FALSE,stack=TRUE)
    if(length(gry)) oA(wb,nm,st_gry,rows=r0-1L+gry,cols=co,gridExpand=FALSE,stack=TRUE) }
  oA(wb, nm, st_sep, rows=1:(r0+N-1L), cols=c(8,10,12), gridExpand=TRUE, stack=TRUE)   # separateurs groupes
  for (k in seq_along(rl$values)) oA(wb, nm, st_spB, rows=st[k]+rl$lengths[k]-1L, cols=1:13, gridExpand=TRUE, stack=TRUE)
  openxlsx::setColWidths(wb, nm, cols=1, widths=24); openxlsx::setColWidths(wb, nm, cols=2, widths=9)
  openxlsx::setColWidths(wb, nm, cols=3:7, widths=7); openxlsx::setColWidths(wb, nm, cols=8:13, widths=13)
  openxlsx::freezePane(wb, nm, firstActiveRow=r0, firstActiveCol=2)
}
if (requireNamespace("openxlsx", quietly = TRUE)) {
  wb <- openxlsx::createWorkbook()
  add_sheet(wb, "espece_x_base", wide)
  add_sheet(wb, "par_espece",    wide_esp)
  openxlsx::saveWorkbook(wb, f_xlsx, overwrite = TRUE)
  cat("XLSX (fusionne + colore) :", f_xlsx, "\n")
} else if (requireNamespace("writexl", quietly = TRUE)) {
  writexl::write_xlsx(list(espece_x_base = build_compact(wide, TRUE),
                           par_espece    = build_compact(wide_esp, TRUE)), f_xlsx)
  cat("XLSX (sans mise en forme) :", f_xlsx, "\n")
}

# ===================== TABLEAUX LaTeX =======================================
# Requiert dans le preambule : \usepackage{booktabs,multirow,amssymb,xcolor}
.tx <- function(x, d) if (is.na(x)) "--" else formatC(x, format = "f", digits = d)  # NA masque -> "--"
flh <- function(s) if (is.na(s) || s == "") "" else
  if (s == "+") "\\textcolor{red!75!black}{$\\blacktriangle$}" else
  "\\textcolor{green!45!black}{$\\blacktriangledown$}"
LEG <- "Sens de l'effet du \\emph{stress} : \\textcolor{red!75!black}{$\\blacktriangle$} = le stress augmente la mortalite, \\textcolor{green!45!black}{$\\blacktriangledown$} = la diminue. Pour TNn et SPEI6, le stress correspond a une \\emph{baisse} de l'indice (hiver plus froid, sol plus sec) ; pour TXx, HWN, CWN, WG10P a une \\emph{hausse}. Indice en gris = non retenu."
.abs7 <- setdiff(ORD_ESP, unique(as.character(wide$espece)))   # especes ecartees (effectif insuffisant)
if (length(.abs7))
  LEG <- paste0(LEG, " \\textbf{Especes non modelisees} (effectif insuffisant : $<$50 placettes ou $<$10 morts par base) : ",
                paste(.abs7, collapse = ", "), ".")
cell_tex <- function(nom, IR, sens) {
  if (is.na(IR) || is.na(nom) || nom == "") return("")
  if (IR == 0) return(sprintf("\\textcolor{gray}{%s}", nom))   # non retenu : grise
  sprintf("%s %.2f %s", nom, IR, flh(sens))
}
cells6 <- function(r) c(
  cell_tex(r$Froid_nom1,r$Froid_IR1,r$Froid_sens1), cell_tex(r$Froid_nom2,r$Froid_IR2,r$Froid_sens2),
  cell_tex(r$Chaud_nom1,r$Chaud_IR1,r$Chaud_sens1), cell_tex(r$Chaud_nom2,r$Chaud_IR2,r$Chaud_sens2),
  cell_tex(r$Sec_nom1,r$Sec_IR1,r$Sec_sens1),       cell_tex(r$Sec_nom2,r$Sec_IR2,r$Sec_sens2))
out_tex <- function(name, lines) for (dd in unique(c(DIRM_SY, DIRT))) writeLines(lines, file.path(dd, name))
band <- function(lead, lead_labels) c(                 # en-tete bande de groupes
  "\\toprule",
  paste0(strrep("& ", lead), "\\multicolumn{2}{c|}{Froid} & \\multicolumn{2}{c|}{Chaud} & \\multicolumn{2}{c}{Secheresse} \\\\"),
  sprintf("\\cmidrule(lr){%d-%d}\\cmidrule(lr){%d-%d}\\cmidrule(lr){%d-%d}",
          lead+1, lead+2, lead+3, lead+4, lead+5, lead+6),
  paste0(paste(lead_labels, collapse = " & "), " & (1) & (2) & (1) & (2) & (1) & (2) \\\\"),
  "\\midrule")

# 1) TABLEAU COMBINE : cellule espece fusionnee (structure de l'image cible) --
Lc <- c("% Genere par 7-Tableau_synthese_modele.R -- requiert booktabs, multirow, amssymb, xcolor.",
        "% Si le tableau deborde en largeur : \\usepackage{pdflscape} puis \\begin{landscape}...\\end{landscape}.", "",
        "\\begin{table}[ht]\\centering\\footnotesize",
        paste0("\\caption{Synthese du modele de mortalite par espece et base climatique. AUC et sensibilite (seuil de Youden) de validation ; pour chaque type de stress, les deux indices ECE par importance relative decroissante (IR, chute de deviance en \\%) et le sens de l'effet. ", LEG, "}"),
        "\\begin{tabular}{llrrrrr|ll|ll|ll}", band(7, c("Espece","Base","AUC","PRAUC","Sens.","Acc.","$\\sum$IR")))
for (e in ORD_ESP) {
  d <- wide[espece == e]; if (nrow(d) == 0L) next; n <- nrow(d)
  for (i in seq_len(n)) { r <- d[i]; cc <- cells6(r)
    lead1 <- if (i == 1L) sprintf("\\multirow{%d}{*}{\\textit{%s}}", n, e) else ""
    Lc <- c(Lc, sprintf("%s & %s & %s & %s & %s & %s & %s & %s & %s & %s & %s & %s & %s \\\\",
      lead1, as.character(r$base), .tx(r$AUC,3), .tx(r$PRAUC,3), .tx(r$Sensibilite,3), .tx(r$Accuracy,3), .tx(r$somme_IR_ECE,1), cc[1],cc[2],cc[3],cc[4],cc[5],cc[6])) }
  Lc <- c(Lc, "\\midrule")
}
Lc[length(Lc)] <- "\\bottomrule"
out_tex("Tableau_synthese_modele_combine.tex", c(Lc, "\\end{tabular}", "\\end{table}", ""))

# 2) PAR ESPECE (moyenne des 6 bases) : 1 tableau, 8 lignes -> corps d'article
Le <- c("% Genere par 7-Tableau_synthese_modele.R -- requiert booktabs, amssymb, xcolor.", "",
        "\\begin{table}[ht]\\centering\\small",
        paste0("\\caption{Synthese du modele de mortalite par espece (moyenne des 6 bases). ", LEG, "}"),
        "\\begin{tabular}{lrrrrr|ll|ll|ll}", band(6, c("Espece","AUC","PRAUC","Sens.","Acc.","$\\sum$IR")))
for (e in ORD_ESP) { d <- wide_esp[espece == e]; if (nrow(d) == 0L) next; r <- d[1]; cc <- cells6(r)
  Le <- c(Le, sprintf("\\textit{%s} & %s & %s & %s & %s & %s & %s & %s & %s & %s & %s & %s \\\\",
    e, .tx(r$AUC,3), .tx(r$PRAUC,3), .tx(r$Sensibilite,3), .tx(r$Accuracy,3), .tx(r$somme_IR_ECE,1), cc[1],cc[2],cc[3],cc[4],cc[5],cc[6])) }
out_tex("Tableau_synthese_modele_par_espece.tex", c(Le, "\\bottomrule", "\\end{tabular}", "\\end{table}", ""))

# 3) PAR BASE : un petit tableau par espece (6 bases) -> annexe / detail ------
Lb <- c("% Genere par 7-Tableau_synthese_modele.R -- requiert booktabs, amssymb, xcolor.", "")
for (e in ORD_ESP) {
  d <- wide[espece == e]; if (nrow(d) == 0L) next
  Lb <- c(Lb, "\\begin{table}[ht]\\centering\\small",
    sprintf("\\caption{\\textit{%s} : par base climatique. %s}", e, LEG),
    "\\begin{tabular}{lrrrrr|ll|ll|ll}", band(6, c("Base","AUC","PRAUC","Sens.","Acc.","$\\sum$IR")))
  for (i in seq_len(nrow(d))) { r <- d[i]; cc <- cells6(r)
    Lb <- c(Lb, sprintf("%s & %s & %s & %s & %s & %s & %s & %s & %s & %s & %s & %s \\\\",
      as.character(r$base), .tx(r$AUC,3), .tx(r$PRAUC,3), .tx(r$Sensibilite,3), .tx(r$Accuracy,3), .tx(r$somme_IR_ECE,1), cc[1],cc[2],cc[3],cc[4],cc[5],cc[6])) }
  Lb <- c(Lb, "\\bottomrule", "\\end{tabular}", "\\end{table}", "")
}
out_tex("Tableau_synthese_modele_par_base.tex", Lb)
cat(sprintf("TEX (combine + par_espece + par_base) -> %s\n    et -> %s\n", DIRM, DIRT))

# --- apercu console ----------------------------------------------------------
cat("\nApercu par espece (moyenne des bases) :\n")
print(build_compact(wide_esp, glyph = FALSE)[, .(Espece, AUC, Sens, Acc, Som_IR, Froid_1, Chaud_1, Sec_1)])
