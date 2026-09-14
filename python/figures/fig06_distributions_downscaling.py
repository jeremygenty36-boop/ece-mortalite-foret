# -*- coding: utf-8 -*-
"""Fig. 6 du rapport : effet du downscaling sur la distribution des indices ECE entre
placettes IFN (base native en trait plein, downscalee en tirets, CHELSA native en rouge).

Recreee le 14/09/2026 (script d'origine perdu). Valeurs verifiees : les ecarts-types
affiches dans le PDF du rapport sont retrouves a 0,01 pres sur les 31 600 placettes
2015-2023 hors Corse (ecart-type de population). Les densites sont des estimations
par noyau gaussien (regle de Scott) : la forme exacte des courbes d'origine peut
differer legerement.

Usage : python3 python/figures/fig06_distributions_downscaling.py
        ECE_INDICES=TXx,HWN,TNn,CWN,SPEI6,WG10P  -> version a 6 indices
"""
import os
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import Patch
from matplotlib.ticker import MaxNLocator
import _commun as c

TITRE_INDICE = {"TNn": ("TNn (min. des T min, °C)", "TNn (°C)"), "TXx": ("TXx (max. des T max, °C)", "TXx (°C)"),
                "WG10P": ("WG10P (jours de déficit, %)", "WG10P (%)"), "HWN": ("HWN (vagues de chaleur, nb)", "HWN (nb)"),
                "CWN": ("CWN (vagues de froid, nb)", "CWN (nb)"), "SPEI6": ("SPEI-6 (sécheresse)", "SPEI-6")}
LIGNES = [("SAFRAN", "SAF8", "SAFDS"), ("E-OBS", "EOB10", "EOBDS")]
ROUGE, VERT, SAUMON = "#CB181D", "#C0E4C1", "#FDBBAD"


def kde(x, grille):
    """Densite par noyau gaussien, largeur de bande de Scott (n^-1/5 x ecart-type)."""
    x = x[np.isfinite(x)]
    h = x.std() * len(x) ** (-1 / 5)
    pas = grille[1] - grille[0]
    bords = np.append(grille - pas / 2, grille[-1] + pas / 2)
    hist, _ = np.histogram(x, bins=bords)
    noyau_x = np.arange(-int(4 * h / pas) - 1, int(4 * h / pas) + 2) * pas
    noyau = np.exp(-0.5 * (noyau_x / h) ** 2)
    dens = np.convolve(hist, noyau / noyau.sum(), mode="same")
    return dens / (len(x) * pas)


def main():
    indices = os.environ.get("ECE_INDICES", "TNn,TXx,WG10P").split(",")
    d = c.placettes_ifn([f"{i}_{b}" for i in indices for b in ("SAF8", "SAFDS", "EOB10", "EOBDS", "CHE1")])
    print("placettes :", len(d))
    fig, axes = plt.subplots(2, len(indices), figsize=(4.3 * len(indices), 6.8), squeeze=False)
    fig.subplots_adjust(left=0.1, right=0.98, top=0.86, bottom=0.17, wspace=0.18, hspace=0.12)
    for j, ind in enumerate(indices):
        valeurs = np.concatenate([d[f"{ind}_{b}"].dropna().values for b in ("SAF8", "SAFDS", "EOB10", "EOBDS", "CHE1")])
        lo, hi = np.quantile(valeurs, [0.002, 0.998])
        pad = 0.05 * (hi - lo)
        grille = np.linspace(lo - pad, hi + pad, 1200)
        y_che = kde(d[f"{ind}_CHE1"].values, grille)
        s_che = d[f"{ind}_CHE1"].std(ddof=0)
        for i, (lab, nat, ds) in enumerate(LIGNES):
            ax = axes[i, j]
            y_nat, y_ds = kde(d[f"{ind}_{nat}"].values, grille), kde(d[f"{ind}_{ds}"].values, grille)
            ax.fill_between(grille, y_nat, y_ds, where=y_ds >= y_nat, color=VERT, lw=0, interpolate=True)
            ax.fill_between(grille, y_nat, y_ds, where=y_ds < y_nat, color=SAUMON, lw=0, interpolate=True)
            ax.plot(grille, y_nat, color="#222222", lw=2.0)
            ax.plot(grille, y_ds, color="#000000", lw=1.3, ls=(0, (4, 2.5)))
            ax.plot(grille, y_che, color=ROUGE, lw=2.6)
            s_nat, s_ds = d[f"{ind}_{nat}"].std(ddof=0), d[f"{ind}_{ds}"].std(ddof=0)
            evol = 100 * (s_ds / s_nat - 1)
            ax.text(0.03, 0.965, f"{c.LIB_BASE[nat]} → {c.LIB_BASE[ds]} : σ {c.virgule(s_nat)} → {c.virgule(s_ds)} ({evol:+.0f} %)".replace("+-", "-"),
                    transform=ax.transAxes, ha="left", va="top", fontsize=7,
                    bbox=dict(boxstyle="round,pad=0.25", fc="white", ec="#BBBBBB", lw=0.8))
            ax.text(0.04, 0.845, f"CHE-1 : σ {c.virgule(s_che)}", transform=ax.transAxes, ha="left", va="top",
                    fontsize=7.5, color=ROUGE, fontweight="bold")
            ax.set_xlim(grille[0], grille[-1])
            ax.set_ylim(0, 1.4 * max(y_nat.max(), y_ds.max(), y_che.max()))
            ax.yaxis.set_major_locator(MaxNLocator(nbins=3))
            ax.xaxis.set_major_locator(MaxNLocator(nbins=5, steps=[1, 2, 5, 10]))
            ax.tick_params(labelsize=7.5, colors="#333333")
            ax.grid(axis="x", color="#DDDDDD", lw=0.8)
            ax.set_axisbelow(True)
            for s in ("top", "right"):
                ax.spines[s].set_visible(False)
            if i == 0:
                ax.set_title(TITRE_INDICE[ind][0], fontsize=10)
                ax.tick_params(labelbottom=False)
            else:
                ax.set_xlabel(TITRE_INDICE[ind][1], fontsize=8.5)
            if j == 0:
                ax.set_ylabel("Densité", fontsize=8.5, color="#555555")
                pos = ax.get_position()
                fig.text(0.035, (pos.y0 + pos.y1) / 2, lab, rotation=90, ha="center", va="center",
                         fontsize=11, fontweight="bold")
    fig.suptitle("Distribution des indices d'extrêmes entre placettes IFN : effet du downscaling et comparaison "
                 "à CHELSA native (2015-2023, hors Corse)", fontsize=11, fontweight="bold", y=0.975)
    fig.text(0.5, 0.925, "Base native (plein) vs downscalée à 1 km (tirets) ; CHELSA native superposée en rouge  |  "
             "σ = écart-type spatial entre placettes", ha="center", fontsize=8, color="#555555")
    poignees = [Line2D([0], [0], color="#222222", lw=2, label="base native (trait plein)"),
                Line2D([0], [0], color="#000000", lw=1.3, ls=(0, (4, 2.5)), label="base downscalée à 1 km (tirets)"),
                Line2D([0], [0], color=ROUGE, lw=2.6, label="CHELSA native (CHE-1)"),
                Patch(color=VERT, label="densité de placettes en hausse après downscaling"),
                Patch(color=SAUMON, label="densité de placettes en baisse après downscaling")]
    fig.legend(handles=poignees, loc="lower center", ncol=3, frameon=False, fontsize=8, bbox_to_anchor=(0.5, 0.0))
    nom = "Fig06_distributions_ECE_avec_CHELSA" if len(indices) == 3 else f"Fig06_annexe_distributions_{len(indices)}indices"
    c.enregistrer(fig, nom)


if __name__ == "__main__":
    main()
