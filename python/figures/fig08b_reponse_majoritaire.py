# -*- coding: utf-8 -*-
"""Fig. 8b du rapport : indice ECE d'IR maximale par essence et par base, avec son IR et le
sens de son effet sur la mortalite.

Recreee le 14/09/2026 (script d'origine perdu), depuis RI_par_variable.csv du run
peuplement + ECE binaire (CHE-C exclue).
- Cellule : indice ECE d'IR la plus forte ; couleur = type de stress, foncee si IR >= 4 %.
- Triangle : colonne "sens" du moteur (difference de probabilite predite entre les quantiles
  10 et 90 de l'indice) ; rouge vers le bas = l'augmentation de l'indice augmente la mortalite,
  vert vers le haut = elle la diminue.
- Ordre des lignes : celui de la figure du rapport.
Usage : python3 python/figures/fig08b_reponse_majoritaire.py
"""
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import Patch, Rectangle
import _commun as c

ORDRE_LIGNES = ["PINI", "QUPE", "FASY", "QURO", "ABAL", "PIAB", "PISY", "BEPE"]
STRESS = {"TXx": "chaud", "HWN": "chaud", "TNn": "froid", "CWN": "froid", "SPEI6": "hydrique", "WG10P": "hydrique"}
COUL = {"chaud": ("#E6550D", "#FDD0A2"), "froid": ("#3182BD", "#C6DBEF"), "hydrique": ("#31A354", "#C7E9C0")}
SEUIL_FONCE = 4.0
ROUGE_TRI, VERT_TRI = "#B2182B", "#1A7A34"


def main():
    ri = pd.read_csv(c.chemin_run("RI_par_variable.csv"), sep=";")
    ece = ri[~ri.variable.isin(c.VAR_FIXES) & ri.base_code.isin(c.BASES_5)].copy()
    ece["indice"] = ece.variable.str.rsplit("_", n=1).str[0]
    dom = (ece.sort_values("RI", ascending=False, kind="stable")
              .groupby(["esp_code", "base_code"], as_index=False).first().set_index(["esp_code", "base_code"]))

    fig, ax = plt.subplots(figsize=(7.2, 5.2))
    fig.subplots_adjust(left=0.15, right=0.98, top=0.88, bottom=0.14)
    for i, esp in enumerate(ORDRE_LIGNES):
        for j, b in enumerate(c.BASES_5):
            y = len(ORDRE_LIGNES) - 1 - i
            r = dom.loc[(esp, b)]
            fonce, clair = COUL[STRESS[r.indice]]
            est_fonce = r.RI >= SEUIL_FONCE
            ax.add_patch(Rectangle((j, y), 1, 1, facecolor=fonce if est_fonce else clair, edgecolor="white", lw=1.5))
            txt = "white" if est_fonce else "#1A1A1A"
            ax.text(j + 0.5, y + 0.72, c.LIB_INDICE[r.indice], ha="center", va="center", fontsize=6.5,
                    fontweight="bold", color=txt)
            ax.text(j + 0.5, y + 0.48, f"{c.virgule(r.RI, 1)} %", ha="center", va="center", fontsize=5.5, color=txt)
            if r.sens in ("+", "-"):
                ax.plot(j + 0.5, y + 0.22, marker="v" if r.sens == "+" else "^", ms=6.5,
                        color=ROUGE_TRI if r.sens == "+" else VERT_TRI, mec="white", mew=0.6)
    ax.set_xlim(0, len(c.BASES_5))
    ax.set_ylim(0, len(ORDRE_LIGNES))
    ax.set_xticks([j + 0.5 for j in range(len(c.BASES_5))])
    ax.set_xticklabels([c.LIB_BASE[b] for b in c.BASES_5], fontsize=7.5, fontweight="bold")
    ax.xaxis.tick_top()
    ax.set_yticks([len(ORDRE_LIGNES) - 1 - i + 0.5 for i in range(len(ORDRE_LIGNES))])
    ax.set_yticklabels([c.ESP_NOMS[e] for e in ORDRE_LIGNES], fontsize=7.5, style="italic")
    ax.tick_params(length=0)
    for s in ax.spines.values():
        s.set_visible(False)
    fig.suptitle("Réponse majoritaire des indices d'ECE par essence et par base climatique",
                 fontsize=10.5, fontweight="bold", y=0.975)
    poignees = [Patch(color=COUL["chaud"][0], label="chaud (TXx, HWN)"),
                Patch(color=COUL["froid"][0], label="froid (TNn, CWN)"),
                Patch(color=COUL["hydrique"][0], label="hydrique (SPEI-6, WG10P)"),
                Patch(color="#DDDDDD", label="IR < 4 % (clair)"),
                Patch(color="#A5A5A5", label="IR ≥ 4 % (foncé)"),
                Line2D([0], [0], marker="^", ls="", color=VERT_TRI, ms=6, label="diminue la mortalité"),
                Line2D([0], [0], marker="v", ls="", color=ROUGE_TRI, ms=6, label="augmente la mortalité")]
    fig.legend(handles=poignees, loc="lower center", ncol=4, frameon=False, fontsize=6, handlelength=1.2,
               bbox_to_anchor=(0.55, 0.0), columnspacing=1.2)
    c.enregistrer(fig, "Fig08b_reponse_majoritaire_ECE_par_base")


if __name__ == "__main__":
    main()
