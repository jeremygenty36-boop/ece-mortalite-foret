# -*- coding: utf-8 -*-
"""Fig. 7 du rapport : R2 entre bases des six indices ECE aux placettes IFN,
avant (bases natives) et apres downscaling a 1 km.

Recreee le 14/09/2026 (script d'origine perdu). Valeurs verifiees : les 36 R2 affiches
dans le PDF du rapport sont retrouves a 0,01 pres sur les 31 600 placettes 2015-2023 hors Corse.
Usage : python3 python/figures/fig07_correlation_inter_bases.py
"""
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import FancyArrow
import _commun as c

PAIRES = [  # (libelle, couleur ligne, couleur texte, (natif a, natif b), (DS a, DS b))
    ("SAFRAN ~ E-OBS", "#1F6EB4", "#14538F", ("SAF8", "EOB10"), ("SAFDS", "EOBDS")),
    ("SAFRAN ~ CHELSA", "#C1274A", "#A01D3C", ("SAF8", "CHE1"), ("SAFDS", "CHE1")),
    ("E-OBS ~ CHELSA", "#E0902A", "#B9741D", ("EOB10", "CHE1"), ("EOBDS", "CHE1")),
]
EPAISSEUR = {"SAFRAN ~ CHELSA": 2.8}
DECALAGE = [0.27, 0.0, -0.27]


def main():
    bases = ["SAF8", "SAFDS", "EOB10", "EOBDS", "CHE1"]
    d = c.placettes_ifn([f"{i}_{b}" for i in c.INDICES_ECE for b in bases])
    print("placettes :", len(d))

    def r2(i, a, b):
        return d[[f"{i}_{a}", f"{i}_{b}"]].dropna().corr().iloc[0, 1] ** 2

    res = {i: [(r2(i, *nat), r2(i, *ds)) for _, _, _, nat, ds in PAIRES] for i in c.INDICES_ECE}
    # indices ordonnes par R2 moyen apres downscaling, decroissant
    ordre = sorted(c.INDICES_ECE, key=lambda i: -sum(v[1] for v in res[i]) / 3)

    fig, ax = plt.subplots(figsize=(10, 6.3))
    fig.subplots_adjust(left=0.2, right=0.98, top=0.97, bottom=0.25)
    for k, i in enumerate(ordre):
        y0 = -k
        if k % 2 == 0:
            ax.axhspan(y0 - 0.5, y0 + 0.5, color="#F0F0F0", zorder=0)
        for (lab, col, col_txt, _, _), dy, (v_nat, v_ds) in zip(PAIRES, DECALAGE, res[i]):
            y = y0 + dy
            ax.plot([v_nat, v_ds], [y, y], color=col, lw=EPAISSEUR.get(lab, 2.0), zorder=2, solid_capstyle="butt")
            ax.plot(v_nat, y, "o", ms=7.5, mfc="white", mec=col, mew=1.8, zorder=3)
            ax.plot(v_ds, y, "o", ms=7.5, mfc=col, mec=col, zorder=3)
            ax.text(v_nat - 0.015, y, c.virgule(v_nat), ha="right", va="center", fontsize=7, color="#8C8C8C")
            ax.text(v_ds + 0.015, y, c.virgule(v_ds), ha="left", va="center", fontsize=7.5,
                    color=col_txt, fontweight="bold")
    ax.set_yticks([-k for k in range(len(ordre))])
    ax.set_yticklabels([c.LIB_INDICE[i] for i in ordre], fontsize=10, fontweight="bold")
    ax.tick_params(axis="y", length=0, pad=10)
    ax.set_ylim(-len(ordre) + 0.5, 0.5)
    ax.set_xlim(-0.04, 1.06)
    ax.set_xticks([0, 0.2, 0.4, 0.6, 0.8, 1.0])
    ax.set_xticklabels([c.virgule(x, 1) for x in [0, 0.2, 0.4, 0.6, 0.8, 1.0]], fontsize=8)
    ax.grid(axis="x", color="#E2E2E2", lw=0.8, zorder=1)
    ax.set_axisbelow(True)
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.set_xlabel("R² entre deux bases (valeurs de l'indice extraites aux placettes)", fontsize=8.5)

    # fleche "correlation croissante"
    fig.add_artist(FancyArrow(0.1, 0.3, 0, 0.62, width=0.004, head_width=0.02, head_length=0.03,
                              length_includes_head=True, color="#4D4D4D", transform=fig.transFigure))
    fig.text(0.065, 0.61, "corrélation croissante", rotation=90, ha="center", va="center",
             fontsize=11, fontweight="bold", color="#4D4D4D")

    leg1 = [Line2D([0], [0], color=col, lw=EPAISSEUR.get(lab, 2.0), label=lab) for lab, col, _, _, _ in PAIRES]
    leg2 = [Line2D([0], [0], marker="o", ls="", ms=7, mfc="white", mec="#4D4D4D", mew=1.6,
                   label="bases natives (SAFRAN 8 km, E-OBS 10 km)"),
            Line2D([0], [0], marker="o", ls="", ms=7, mfc="#4D4D4D", mec="#4D4D4D",
                   label="après downscaling à 1 km (SAF-DS, EOBS-DS)")]
    fig.legend(handles=leg1, loc="lower left", bbox_to_anchor=(0.07, 0.0), frameon=False, fontsize=7.5)
    fig.legend(handles=leg2, loc="lower left", bbox_to_anchor=(0.43, 0.03), frameon=False, fontsize=7.5)

    c.enregistrer(fig, "Fig07_correlation_inter_bases_ECE")
    for i in ordre:
        print(i, " | ".join(f"{p[0]} {c.virgule(a)} -> {c.virgule(b)}" for p, (a, b) in zip(PAIRES, res[i])))


if __name__ == "__main__":
    main()
