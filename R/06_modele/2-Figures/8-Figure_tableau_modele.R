# source("S:/Projets/stage_JeremyG/4-Travail_bis/4-Modeles/1-Mortalite/2-Figures/8-Figure_tableau_modele.R")
# ============================================================================
# FIGURE-TABLEAU du modele de mortalite (structure imbriquee facon Carletti) :
#   un tableau par espece ; pour chaque base climatique, AUC / Sensibilite /
#   somme des IR ECE sont fusionnees, et chaque groupe de stress (Froid, Chaud,
#   Secheresse) occupe 2 sous-lignes (les 2 indices) x 3 colonnes (Nom | IR | Sens).
#   Sens = effet du STRESS (cf script 7) : rouge triangle haut = le stress aggrave la
#   mortalite, vert triangle bas = il la diminue (TNn/SPEI6 : stress = baisse de l indice).
#   NE MODIFIE AUCUNE DONNEE : lit Tableau_synthese_modele.csv (script 7) et le met
#   en page. Sortie PDF multi-pages. Sorties dans 5-Resultats/5-Modeles/Figures/.
# ============================================================================
suppressPackageStartupMessages({ library(data.table); library(ggplot2) })
if (!exists(".PFX")) .PFX <- if (dir.exists("S:/Projets")) "S:" else "/Volumes/_donnees"
if (!exists("RUN_TAG")) RUN_TAG <- "Mortalite_2009-2023_r075"
.VARIANTE_DIR <- if (grepl("_dominants$", RUN_TAG)) "dominants" else if (grepl("_domines$", RUN_TAG)) "domines" else if (grepl("_pur080$", RUN_TAG)) "pur080" else "standard"  # niveau jeu de donnees (cf 6-Extraction_bases_variantes.R)
DIRM    <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/5-Modeles", .VARIANTE_DIR, RUN_TAG)
DIRM_SY <- file.path(DIRM, "2-Syntheses")
DIRF <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/5-Modeles", .VARIANTE_DIR, RUN_TAG, "Figures", "6-Tableaux_essences_x_bases")
dir.create(DIRF, showWarnings = FALSE, recursive = TRUE)
.run_suffix <- sub("^Mortalite_", "", RUN_TAG)

UP  <- intToUtf8(0x25B2); DN <- intToUtf8(0x25BC); SIG <- intToUtf8(0x2211)
ORD_ESP  <- c("Quercus robur","Quercus petraea","Fagus sylvatica","Pinus sylvestris",
              "Pinus nigra subsp. nigra","Abies alba","Picea abies","Betula pendula")
if (!exists("BASES_EXCLUES")) BASES_EXCLUES <- c("CHE-C")   # bases ecartees de l'analyse (CHE-C retiree, demande utilisateur)
ORD_BASE <- setdiff(c("EOB-10","SAF-8","CHE-1","EOB-DS","SAF-DS","CHE-C"), BASES_EXCLUES)
sel <- Sys.getenv("FIG_ESP", ""); if (nzchar(sel)) ORD_ESP <- strsplit(sel, ";")[[1]]

COL_MAX     <- "#C6EFC4"
COL_MIN     <- "#FFE0D0"
COL_BASE_SC <- c("EOB-10"="#5B9BD5","SAF-8"="#ED7D31","CHE-1"="#70AD47",
                 "EOB-DS"="#2E75B6","SAF-DS"="#C55A11","CHE-C"="#375623")

wide <- fread(file.path(DIRM_SY, "Tableau_synthese_modele.csv"))
wide <- wide[espece %in% ORD_ESP]
wide <- wide[!base %in% BASES_EXCLUES]          # retire les bases ecartees (ex. CHE-C)
if (!"Sensibilite" %in% names(wide) && "Sens_moy" %in% names(wide)) setnames(wide, "Sens_moy", "Sensibilite")
for (.col in c("AUC","PRAUC","Sensibilite","somme_IR_ECE"))
  if (!.col %in% names(wide)) wide[, (.col) := NA_real_]
if (!"n_morts" %in% names(wide)) wide[, n_morts := NA_integer_]   # effectif (justifie les "--")

# TSS, Kappa, Accuracy depuis Synthese_globale.csv (absent si ancien run)
{
  syn_glob <- fread(file.path(DIRM_SY, "Synthese_globale.csv"))
  for (.col in c("TSS_moy","Kappa_moy","Acc_moy","n_plac")) {
    if (.col %in% names(syn_glob)) {
      wide <- merge(wide, syn_glob[, c("espece","base",.col), with=FALSE],
                    by = c("espece","base"), all.x = TRUE)
    } else {
      wide[, (.col) := NA_real_]
    }
  }
  rm(syn_glob)
}

# ---- variables fixes : IR depuis RI_par_variable.csv -----------------------
VFIX_CK <- c(pH="pH", G_ha_tot="Gha", Gini="Gin", c13_moy_sp="c13", prop_G="pG")
ri_fix  <- fread(file.path(DIRM_SY, "RI_par_variable.csv"))
for (.v in names(VFIX_CK)) {
  .ck  <- VFIX_CK[[.v]]
  .sub <- ri_fix[variable == .v, .(espece, base, IR = RI)]
  setnames(.sub, "IR", paste0(.ck, "_IR"))
  wide <- merge(wide, .sub, by = c("espece","base"), all.x = TRUE)
}
rm(ri_fix)
wide[, espece := factor(espece, levels = ORD_ESP)]
wide[, base   := factor(base,   levels = ORD_BASE)]
setorder(wide, espece, base)

# Masque effectifs faibles (coherent avec script 7) : si n_morts < SEUIL_MORTS, on
# met TOUTE la ligne a NA. AUC/PRAUC/Sens/somme_IR sont deja masquees dans le CSV ;
# ici on masque AUSSI TSS/Kappa/Acc et les IR des variables fixes (tires de
# Synthese_globale / RI, non masques) pour ne pas laisser fuir des metriques d'un
# modele non fiable. Les cellules NA s'affichent "--".
if (!exists("SEUIL_MORTS")) SEUIL_MORTS <- 30L
if ("n_morts" %in% names(wide)) {
  .mq <- !is.na(wide$n_morts) & wide$n_morts < SEUIL_MORTS
  .mc <- intersect(c("TSS_moy","Kappa_moy","Acc_moy",
                     "pH_IR","Gha_IR","Gin_IR","c13_IR","pG_IR"), names(wide))
  if (any(.mq) && length(.mc)) wide[.mq, (.mc) := NA_real_]
}

# Especes cibles ECARTEES par le modele (absentes de la synthese : effectif insuffisant)
.abs8   <- setdiff(ORD_ESP, unique(as.character(wide$espece)))
.npres8 <- length(ORD_ESP) - length(.abs8)
.note8  <- if (length(.abs8)) paste0(" | absentes (effectif insuffisant) : ", paste(.abs8, collapse = ", ")) else ""

# ---- especes COMPARABLES entre montagne et plaine (page de classement) -------
# La moyenne inter-especes de la derniere page (render_scoring) ne doit porter
# que sur les essences modelisees AVEC un effectif suffisant DANS LES DEUX zones
# (montagne ET plaine), sinon les deux moyennes ne sont pas comparables. On
# ecarte donc, des deux cotes, toute essence absente ou sous le seuil dans l'une
# OU l'autre zone (ex. ABAL insuffisante en plaine, PINI insuffisante en montagne).
.zone <- if (grepl("Montagne", RUN_TAG)) "Montagne" else if (grepl("Plaine", RUN_TAG)) "Plaine" else "France"
.esp_suff <- function(syn) {   # especes presentes ET effectif suffisant (n_morts >= seuil)
  syn <- as.data.table(syn)
  if (!"n_morts" %in% names(syn)) return(unique(as.character(syn$espece)))
  syn[, .(nm = max(n_morts, na.rm = TRUE)), by = espece][nm >= SEUIL_MORTS, as.character(espece)]
}
.esp_score  <- intersect(ORD_ESP, unique(as.character(wide$espece)))   # defaut (France) : toutes les especes presentes
.note_score <- .note8
if (.zone %in% c("Montagne","Plaine")) {
  .sister     <- if (.zone == "Montagne") "Plaine" else "Montagne"
  .sister_tag <- sub(.zone, .sister, RUN_TAG)
  .sister_f   <- file.path(.PFX, "Projets/stage_JeremyG/5-Resultats/5-Modeles",
                           .VARIANTE_DIR, .sister_tag, "2-Syntheses", "Synthese_globale.csv")
  if (file.exists(.sister_f)) {
    .esp_here  <- .esp_suff(fread(file.path(DIRM_SY, "Synthese_globale.csv")))
    .esp_other <- .esp_suff(fread(.sister_f))
    .esp_score <- intersect(ORD_ESP, intersect(.esp_here, .esp_other))
    .excl      <- setdiff(intersect(ORD_ESP, union(.esp_here, .esp_other)), .esp_score)
    .note_score <- if (length(.excl))
      paste0(" | exclues (effectif insuffisant en montagne ou en plaine, non comparables) : ",
             paste(.excl, collapse = ", ")) else ""
    cat(sprintf("Page classement : moyenne sur %d especes comparables %s n %s ; exclues : %s\n",
                length(.esp_score), .zone, .sister,
                if (length(.excl)) paste(.excl, collapse = ", ") else "(aucune)"))
  } else {
    cat(sprintf("Zone soeur introuvable (%s) -- classement sur toutes les especes de la zone.\n", .sister_f))
  }
}

# ---- geometrie des colonnes (largeurs relatives) ---------------------------
COLS <- data.table(
  ck = c("Base","Acc","TSS","Kap","PRAUC","IR",
         "pH","Gha","Gin","c13","pG",
         "F_nom","F_IR","F_s","C_nom","C_IR","C_s","S_nom","S_IR","S_s"),
  w  = c( 2.4,  1.5,  1.4,  1.4,  1.4,   1.4,
          1.2,  1.2,  1.2,  1.2,  1.2,
          1.6,  0.85, 0.75,  1.6,  0.85, 0.75,  1.6,  0.85, 0.75))
COLS[, xr := cumsum(w)][, xl := xr - w]; WTOT <- COLS[.N, xr]
gx <- function(k, p = "c") { r <- COLS[ck == k]; if (p=="l") r$xl else if (p=="r") r$xr else (r$xl+r$xr)/2 }
SEP_X <- c(gx("Base","r"), gx("PRAUC","r"), gx("IR","r"),
           gx("pG","r"), gx("F_s","r"), gx("C_s","r"))
HB <- 1.35; HH <- 1.05; HS <- 1.0   # HB plus haut pour 2 lignes (espece + run)

f8   <- function(x, d) if (is.na(x)) "--" else formatC(x, format = "f", digits = d)  # NA masque -> "--"
icon <- function(s) fifelse(is.na(s) | s == "", "", fifelse(s == "+", UP, DN))
icol <- function(s) fifelse(is.na(s) | s == "", "grey55", fifelse(s == "+", "#C0392B", "#1E8449"))

# ---- rend un tableau pour un sous-ensemble d'especes -----------------------
render_table <- function(especes, outfile = NULL, scale = 0.46) {
  R <- list(); TT <- list(); S <- list(); SH <- list()
  aR <- function(x0,x1,y0,y1,fill) R[[length(R)+1]] <<- data.table(xmin=x0,xmax=x1,ymin=y0,ymax=y1,fill=fill)
  aT <- function(x,y,lab,col="black",face="plain",size=3.1,hj=0.5) TT[[length(TT)+1]] <<- data.table(x=x,y=y,label=lab,col=col,face=face,size=size,hjust=hj)
  aS <- function(x0,x1,y0,y1,lw,col="grey25") S[[length(S)+1]] <<- data.table(x=x0,xend=x1,y=y0,yend=y1,lw=lw,col=col)
  aSH <- function(x, y, sn, sz=2.2) {
    if (is.na(sn) || sn == "") return(invisible(NULL))
    SH[[length(SH)+1]] <<- data.table(x=x, y=y,
      sh  = if (sn=="+") 17L else 25L,
      col = if (sn=="+") "#C0392B" else "#1E8449", sz=sz)
  }

  d_all <- wide[espece %in% especes]
  if (nrow(d_all) == 0L) return(invisible(NULL))   # espece absente (effectif insuffisant) -> pas de page (cf. page classement)
  ny <- sum(vapply(especes, function(e) HB + HH + 2*HS*nrow(d_all[espece==e]), numeric(1)))
  ytop <- ny
  for (e in especes) {
    d <- d_all[espece == e]; nb <- nrow(d); if (nb == 0L) next
    y_blk_top <- ytop
    # bande espece : nom + run suffix + effectif total de placettes
    .npl     <- if ("n_plac" %in% names(d)) suppressWarnings(max(d$n_plac, na.rm = TRUE)) else NA_real_
    .npl_txt <- if (is.finite(.npl)) sprintf("   |   %s placettes", format(.npl, big.mark = " ")) else ""
    aR(0, WTOT, ytop-HB, ytop, "#9D9D9D")
    aT(WTOT/2, ytop-HB/2+0.17, as.character(e),  "black","bold.italic", 4.2)
    aT(WTOT/2, ytop-HB/2-0.25, paste0(.run_suffix, .npl_txt), "#F0F0F0","italic", 2.7)
    ytop <- ytop - HB; y_grid_top <- ytop
    # en-tete
    aR(0, WTOT, ytop-HH, ytop, "#F2F2F2")
    aT(gx("Base"),ytop-HH/2,"Base","black","bold",3.2)
    aT(gx("Acc"), ytop-HH/2,"Justesse",   "black","bold",3.0)
    aT(gx("TSS"), ytop-HH/2,"TSS",        "black","bold",3.0)
    aT(gx("Kap"), ytop-HH/2,"Kappa",      "black","bold",3.0)
    aT(gx("PRAUC"),ytop-HH/2,"prAUC",     "black","bold",3.0)
    aT(gx("IR"),  ytop-HH/2,paste0(SIG," IR ECE"),"black","bold",3.0)
    for (.fck in as.character(VFIX_CK))
      aT(gx(.fck), ytop-HH/2, .fck, "black","bold",3.0)
    aT(gx("F_nom","l")+0.1,ytop-HH/2,"Froid",     "black","bold",3.2,0)
    aT(gx("C_nom","l")+0.1,ytop-HH/2,"Chaud",     "black","bold",3.2,0)
    aT(gx("S_nom","l")+0.1,ytop-HH/2,"Secheresse","black","bold",3.2,0)
    ytop <- ytop - HH
    # indices des lignes max/min par colonne (gere les ex-aequo : toutes les lignes egales)
    .hl <- function(v) {
      mx <- max(v, na.rm=TRUE); mn <- min(v, na.rm=TRUE)
      if (!is.finite(mx) || mx == mn) return(list(hi=integer(0), lo=integer(0)))
      list(hi=which(!is.na(v) & v==mx), lo=which(!is.na(v) & v==mn))
    }
    mm_pra <- .hl(d$PRAUC)
    mm_tss <- .hl(d$TSS_moy); mm_kap <- .hl(d$Kappa_moy)
    mm_acc <- .hl(d$Acc_moy)
    mm_ir  <- .hl(d$somme_IR_ECE)
    mmfix  <- lapply(setNames(nm=as.character(VFIX_CK)), function(.fck) .hl(d[[paste0(.fck,"_IR")]]))
    mmece  <- local({
      out <- list()
      for (.g in list(c("F","Froid"),c("C","Chaud"),c("S","Sec")))
        for (.sub in 1:2) {
          .col <- paste0(switch(.g[1],F="Froid",C="Chaud",S="Sec"),"_IR",.sub)
          .v   <- if (.col %in% names(d)) d[[.col]] else numeric(0)
          .v[.v == 0] <- NA  # ne pas inclure les 0 dans min/max
          out[[paste0(.g[1],"_",.sub)]] <- .hl(.v)
        }
      out
    })
    for (i in seq_len(nb)) {
      r <- d[i]; yT <- ytop; yB <- ytop - 2*HS; yM <- ytop - HS
      flp <- if(i %in% mm_pra$hi) COL_MAX else if(i %in% mm_pra$lo) COL_MIN else "white"
      flt <- if(i %in% mm_tss$hi) COL_MAX else if(i %in% mm_tss$lo) COL_MIN else "white"
      flk <- if(i %in% mm_kap$hi) COL_MAX else if(i %in% mm_kap$lo) COL_MIN else "white"
      fac <- if(i %in% mm_acc$hi) COL_MAX else if(i %in% mm_acc$lo) COL_MIN else "white"
      fli <- if(i %in% mm_ir$hi)  COL_MAX else if(i %in% mm_ir$lo)  COL_MIN else "white"
      fm  <- function(f) if(f != "white") "bold" else "plain"
      aR(gx("Base","l"),gx("Base","r"),yB,yT,"#DDDDDD"); aT(gx("Base"),(yT+yB)/2,as.character(r$base),"black","bold",3.1)
      aR(gx("Acc","l"),  gx("Acc","r"),  yB,yT,fac);  aT(gx("Acc"),  (yT+yB)/2,f8(r$Acc_moy, 3),"black",fm(fac),3.1)
      aR(gx("TSS","l"),  gx("TSS","r"),  yB,yT,flt);  aT(gx("TSS"),  (yT+yB)/2,f8(r$TSS_moy, 3),"black",fm(flt),3.1)
      aR(gx("Kap","l"),  gx("Kap","r"),  yB,yT,flk);  aT(gx("Kap"),  (yT+yB)/2,f8(r$Kappa_moy, 3),"black",fm(flk),3.1)
      aR(gx("PRAUC","l"),gx("PRAUC","r"),yB,yT,flp);  aT(gx("PRAUC"),(yT+yB)/2,f8(r$PRAUC, 3),"black",fm(flp),3.1)
      aR(gx("IR","l"),   gx("IR","r"),   yB,yT,fli);  aT(gx("IR"),   (yT+yB)/2,f8(r$somme_IR_ECE, 1),"black",fm(fli),3.1)
      for (.fck in as.character(VFIX_CK)) {
        .ir  <- r[[paste0(.fck, "_IR")]]
        .clf <- if(i %in% mmfix[[.fck]]$hi) COL_MAX else if(i %in% mmfix[[.fck]]$lo) COL_MIN else "white"
        aR(gx(.fck,"l"), gx(.fck,"r"), yB, yT, .clf)
        if (!is.na(.ir)) aT(gx(.fck), (yT+yB)/2, formatC(.ir, format="f", digits=1), "black", if (.clf!="white")"bold" else "plain", 2.9)
      }
      grp <- list(c("F","Froid"), c("C","Chaud"), c("S","Sec"))
      for (g in grp) { p <- g[1]; gnm <- switch(p, F="Froid", C="Chaud", S="Sec")
        for (sub in 1:2) {
          yy     <- if (sub==1) yM + HS/2 else yB + HS/2
          yy_top <- if (sub==1) yT else yM
          yy_bot <- if (sub==1) yM else yB
          nom <- r[[paste0(gnm,"_nom",sub)]]
          IR  <- r[[paste0(gnm,"_IR",sub)]]
          sn  <- r[[paste0(gnm,"_sens",sub)]]
          gris <- is.na(IR) || IR == 0
          .mme <- mmece[[paste0(p,"_",sub)]]
          .cle <- if(!gris && i %in% .mme$hi) COL_MAX else if(!gris && i %in% .mme$lo) COL_MIN else "white"
          if (.cle != "white")
            aR(gx(paste0(p,"_IR"),"l"), gx(paste0(p,"_IR"),"r"), yy_bot, yy_top, .cle)
          aT(gx(paste0(p,"_nom"),"l")+0.1, yy, ifelse(is.na(nom),"",nom), if(gris)"grey55" else "black","plain",2.9,0)
          if (!gris) {
            aT(gx(paste0(p,"_IR")), yy, formatC(IR,format="f",digits=2),"black", if(.cle!="white")"bold" else "plain",2.9)
            aSH(gx(paste0(p,"_s")), yy, sn) }
        }
        aS(gx(paste0(p,"_nom"),"l"), gx(paste0(p,"_s"),"r"), yM, yM, 0.25,"grey80")
      }
      aS(0, WTOT, yB, yB, 0.8, "grey30")
      ytop <- yB
    }
    for (xb in COLS$xr) aS(xb, xb, ytop, y_grid_top, 0.25, "grey80")
    for (xb in SEP_X)   aS(xb, xb, ytop, y_grid_top, 0.8,  "grey30")
    aS(0,0, ytop, y_blk_top, 0.8,"grey30"); aS(WTOT,WTOT, ytop, y_blk_top, 0.8,"grey30")
    aS(0,WTOT, y_grid_top,y_grid_top, 0.8,"grey30")
  }
  yf <- -0.85
  aSH(0.15, yf, "+", 2.5); aT(0.65, yf, "= le stress aggrave la mortalite", "grey20","plain",3.0,0)
  aSH(WTOT*0.42, yf, "-", 2.5); aT(WTOT*0.42+0.55, yf, "= le stress la diminue","grey20","plain",3.0,0)
  aT(WTOT*0.74, yf, "indice grise = non retenu","grey45","italic",3.0,0)
  aT(WTOT*0.5, yf-0.6, "Stress = hausse de TXx/HWN/CWN/WG10P, baisse de TNn/SPEI6","grey45","italic",2.7,0)
  aT(WTOT*0.5, yf-1.2, sprintf("\"--\" = effectif insuffisant : moins de %d placettes avec mortalite, metrique non estimee", SEUIL_MORTS),"grey45","italic",2.7,0)
  Rd  <- rbindlist(R); Td <- rbindlist(TT); Sd <- rbindlist(S)
  Shd <- if (length(SH)>0L) rbindlist(SH) else
         data.table(x=numeric(0),y=numeric(0),sh=integer(0),col=character(0),sz=numeric(0))
  g <- ggplot() +
    geom_rect(data=Rd, aes(xmin=xmin,xmax=xmax,ymin=ymin,ymax=ymax,fill=fill), color="grey88", linewidth=0.15) +
    geom_segment(data=Sd, aes(x=x,xend=xend,y=y,yend=yend,linewidth=lw,color=col)) +
    geom_text(data=Td, aes(x=x,y=y,label=label,color=col,fontface=face,size=size,hjust=hjust),
              family="sans", lineheight=0.8) +
    geom_point(data=Shd, aes(x=x,y=y,shape=sh,color=col,fill=col,size=sz), stroke=0.3) +
    scale_fill_identity() + scale_color_identity() + scale_size_identity() +
    scale_linewidth_identity() + scale_shape_identity() +
    coord_equal(expand=FALSE, clip="off") + theme_void()
  if (!is.null(outfile)) {
    ggsave(outfile, g, width = WTOT*scale, height = (ny+2.2)*scale, dpi = 150,
           bg = "white", limitsize = FALSE)
    cat("Figure :", outfile, "\n")
  }
  invisible(list(g = g, ny = ny))
}

# ---- scoring : classement global des bases (moyenne inter-especes) ----------
# Pilote par une liste de metriques (mkeys). On ne garde que les "stats d'interet"
# (Justesse/TSS/Kappa/prAUC), eventuellement + Somme IR ECE. Deux pages produites
# a la fin : (1) stats + IR ECE, (2) stats seules.
SPEC_SC <- list(
  Acc   = list(lab="Justesse moy.", col="Acc_moy",      dig=3),
  TSS   = list(lab="TSS moy.",      col="TSS_moy",      dig=3),
  Kap   = list(lab="Kappa moy.",    col="Kappa_moy",    dig=3),
  PRAUC = list(lab="prAUC moy.",    col="PRAUC",        dig=3),
  IR    = list(lab="IR ECE moy.",   col="somme_IR_ECE", dig=1))

render_scoring <- function(data, ny_page, mkeys, page_title) {
  RANK_COLS <- c("#1E8449","#7FC97F","#C6EFC4","#FAD4CE","#E74C3C","#C0392B")
  mcols <- vapply(mkeys, function(k) SPEC_SC[[k]]$col, "")
  ag <- data[, lapply(.SD, mean, na.rm = TRUE), by = base, .SDcols = mcols]
  setnames(ag, mcols, paste0("m_", mkeys))
  for (k in mkeys) ag[, (paste0("rk_", k)) := rank(-get(paste0("m_", k)), ties.method = "min")]
  ag[, Score := rowSums(as.matrix(.SD)), .SDcols = paste0("rk_", mkeys)]
  setorder(ag, Score)

  SCOLS <- data.table(ck = c("Base", mkeys), w = c(5.5, rep(3.4, length(mkeys))))
  SCOLS[, xr := cumsum(w)][, xl := xr - w]; WTSC <- SCOLS[.N, xr]
  gxs  <- function(k, p="c") { r <- SCOLS[ck==k]; if(p=="l") r$xl else if(p=="r") r$xr else (r$xl+r$xr)/2 }
  rk_fill <- function(r) RANK_COLS[min(6L, max(1L, round(r)))]
  rk_fcol <- function(r) if (round(r) <= 2L) "white" else "black"

  HHs <- 1.1; HSs <- 1.0; nb <- nrow(ag); ny <- ny_page; ytop <- ny
  R <- list(); TT <- list(); S <- list()
  aR <- function(x0,x1,y0,y1,fill) R[[length(R)+1]] <<- data.table(xmin=x0,xmax=x1,ymin=y0,ymax=y1,fill=fill)
  aT <- function(x,y,lab,col="black",face="plain",sz=3.2,hj=0.5) TT[[length(TT)+1]] <<- data.table(x=x,y=y,label=lab,col=col,face=face,sz=sz,hjust=hj)
  aS <- function(x0,x1,y0,y1,lw=0.6,col="grey30") S[[length(S)+1]] <<- data.table(x=x0,xend=x1,y=y0,yend=y1,lw=lw,col=col)

  nsp_sc  <- length(unique(as.character(data$espece)))
  lab_sc  <- if (exists(".zone") && .zone %in% c("Montagne","Plaine"))
               "essences comparables (effectif suffisant en montagne ET en plaine)" else "especes modelisees"
  note_sc <- if (exists(".note_score")) .note_score else .note8
  note_sc <- sub("^ \\| ", "", note_sc)   # retire le separateur de tete -> ligne propre
  aT(WTSC/2, ytop-0.42, paste0(page_title, " : ", .run_suffix), "black","bold",3.5)
  aT(WTSC/2, ytop-0.92, paste0("Moyenne sur ", nsp_sc, " ", lab_sc, " ; couleur = rang (vert = meilleur)"), "grey40","italic",2.5)
  if (nzchar(note_sc)) aT(WTSC/2, ytop-1.30, note_sc, "#C0392B","italic",2.4)
  ytop <- ytop - 1.7

  aR(0, WTSC, ytop-HHs, ytop, "#3E3E3E")
  aT(gxs("Base"), ytop-HHs/2, "Base", "white","bold",3.4)
  for (k in mkeys) aT(gxs(k), ytop-HHs/2, SPEC_SC[[k]]$lab, "white","bold",3.1)
  ytop <- ytop - HHs; aS(0, WTSC, ytop, ytop, 1.0)

  for (i in seq_len(nb)) {
    r  <- ag[i]; yB <- ytop - HSs; yM <- (ytop + yB) / 2
    col_b <- COL_BASE_SC[as.character(r$base)]; if (is.na(col_b)) col_b <- "#888888"
    aR(gxs("Base","l"), gxs("Base","r"), yB, ytop, col_b)
    aT(gxs("Base"), yM, as.character(r$base), "white","bold",3.4)
    for (k in mkeys) {
      rk  <- r[[paste0("rk_", k)]]; val <- r[[paste0("m_", k)]]
      fmt <- formatC(val, format = "f", digits = SPEC_SC[[k]]$dig)
      aR(gxs(k,"l"), gxs(k,"r"), yB, ytop, rk_fill(rk))
      aT(gxs(k), yM, fmt, rk_fcol(rk),"bold",3.4)
    }
    aS(0, WTSC, yB, yB, 0.8, "grey30"); ytop <- yB
  }
  yB <- ytop - HSs; yM <- (ytop + yB) / 2
  aR(0, WTSC, yB, ytop, "#EBEBEB")
  aT(gxs("Base"), yM, "Ecart max-min", "grey25","bold.italic",3.0)
  for (k in mkeys) {
    v   <- ag[[paste0("m_", k)]]
    fmt <- formatC(max(v,na.rm=TRUE) - min(v,na.rm=TRUE), format = "f", digits = SPEC_SC[[k]]$dig)
    aT(gxs(k), yM, fmt, "grey25","bold.italic",3.2)
  }
  aS(0, WTSC, yB, yB, 0.8, "grey30"); ytop <- yB; y_bot <- ytop
  aS(0, WTSC, y_bot, y_bot, 0.8); aS(0,0,y_bot,ny-1.7,0.8); aS(WTSC,WTSC,y_bot,ny-1.7,0.8)
  for (xb in SCOLS$xr[-nrow(SCOLS)]) aS(xb, xb, y_bot, ny-1.7, 0.5, "grey55")
  aT(WTSC/2, y_bot-0.5,
     sprintf("Vert = meilleur, rouge = moins bon. Ordre des bases = somme des %d rangs sur moyennes inter-especes.", length(mkeys)),
     "grey45","italic",2.6)
  aT(WTSC/2, y_bot-1.1,
     "Justesse = exactitude globale. TSS = Sensib.+Spec.-1. Kappa = stat. de Cohen. prAUC = aire Precision-Rappel. IR ECE = somme IR des indices climatiques.",
     "grey45","italic",2.4)

  Rd <- rbindlist(R); Td <- rbindlist(TT); Sd <- rbindlist(S)
  ggplot() +
    geom_rect(data=Rd,aes(xmin=xmin,xmax=xmax,ymin=ymin,ymax=ymax,fill=fill),color="grey88",linewidth=0.15) +
    geom_segment(data=Sd,aes(x=x,xend=xend,y=y,yend=yend,linewidth=lw,color=col)) +
    geom_text(data=Td,aes(x=x,y=y,label=label,color=col,fontface=face,size=sz,hjust=hjust),
              family="sans",lineheight=0.8) +
    scale_fill_identity()+scale_color_identity()+scale_size_identity()+scale_linewidth_identity()+
    coord_equal(xlim=c(0,WTSC),ylim=c(0,ny),expand=FALSE,clip="off")+theme_void()
}

# ---- collecte + PDF multi-pages : 1 espece/page + scoring ------------------
g_list <- list()
for (e in ORD_ESP) {
  res <- render_table(e)
  g_list[[e]] <- res
}

if (length(g_list) > 0L) {
  f_pdf <- file.path(DIRF, sprintf("Tableaux_modele_par_espece_%s.pdf", .run_suffix))
  ny_one  <- HB + HH + 2 * HS * length(ORD_BASE)
  ny_page <- ny_one + 2.2
  pw <- WTOT * 0.46; ph <- ny_page * 0.46
  grDevices::pdf(file = f_pdf, width = pw, height = ph)
  suppressWarnings({
    for (e in ORD_ESP) {
      if (!is.null(g_list[[e]]))
        print(g_list[[e]]$g + ggplot2::theme(plot.margin = ggplot2::margin(0,0,0,0)))
    }
    # deux pages de synthese finale a la fin : (1) stats + IR ECE, (2) stats seules
    g_sc1 <- render_scoring(wide[espece %in% .esp_score], ny_page,
                            c("Acc","TSS","Kap","PRAUC","IR"), "Classement des bases (stats + IR ECE)")
    g_sc2 <- render_scoring(wide[espece %in% .esp_score], ny_page,
                            c("Acc","TSS","Kap","PRAUC"),      "Classement des bases (stats seules)")
    print(g_sc1 + ggplot2::theme(plot.margin = ggplot2::margin(0,0,0,0)))
    print(g_sc2 + ggplot2::theme(plot.margin = ggplot2::margin(0,0,0,0)))
  })
  dev.off()
  cat("PDF multi-pages :", f_pdf, "\n")
}
