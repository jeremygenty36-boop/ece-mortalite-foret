# -*- coding: utf-8 -*-
"""Fig. 9 du rapport : importance relative (IR) des six indices ECE par base et par essence
(barres empilees ; fond bleute = bases a 1 km).

Recreee le 14/09/2026 (script d'origine perdu), depuis RI_par_variable.csv du run
peuplement + ECE binaire (CHE-C exclue). Essences ordonnees par IR ECE moyen decroissant.
Usage : python3 python/figures/fig09_IR_essence_base.py
"""
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
import _commun as c

ORDRE_EMPIL = ["TXx", "HWN", "TNn", "CWN", "SPEI6", "WG10P"]
BASES_1KM = {"CHE1", "SAFDS", "EOBDS"}


def main():
    ri = pd.read_csv(c.chemin_run("RI_par_variable.csv"), sep=";")
    ece = ri[~ri.variable.isin(c.VAR_FIXES) & ri.base_code.isin(c.BASES_5)].copy()
    ece["indice"] = ece.variable.str.rsplit("_", n=1).str[0]
    tab = ece.pivot_table(index=["esp_code", "base_code"], columns="indice", values="RI", aggfunc="sum").fillna(0)
    ordre_esp = tab.sum(axis=1).groupby("esp_code").mean().sort_values(ascending=False).index.tolist()
    print("ordre des essences :", ordre_esp)

    fig, axes = plt.subplots(2, 4, figsize=(12.5, 6.6), sharey=True)
    fig.subplots_adjust(left=0.06, right=0.86, top=0.87, bottom=0.12, wspace=0.12, hspace=0.3)
    x = range(len(c.BASES_5))
    for ax, esp in zip(axes.flat, ordre_esp):
        ax.axvspan(1.5, 4.5, color="#EEF3F7", zorder=0)
        bas = [0.0] * len(c.BASES_5)
        for ind in ORDRE_EMPIL:
            h = [tab.loc[(esp, b), ind] if (esp, b) in tab.index and ind in tab.columns else 0.0 for b in c.BASES_5]
            ax.bar(x, h, bottom=bas, width=0.78, color=c.COUL_INDICE[ind], edgecolor="white", lw=0.8, zorder=3)
            bas = [a + b for a, b in zip(bas, h)]
        ax.set_title(c.ESP_NOMS[esp], fontsize=9, style="italic")
        ax.set_xlim(-0.5, 4.5)
        ax.set_ylim(0, 32)
        ax.set_xticks(list(x))
        ax.set_xticklabels([c.LIB_BASE[b] for b in c.BASES_5], rotation=90, fontsize=7)
        for lab, b in zip(ax.get_xticklabels(), c.BASES_5):
            lab.set_color("#111111" if b in BASES_1KM else "#999999")
            lab.set_fontweight("bold" if b in BASES_1KM else "normal")
        ax.grid(axis="y", color="#E6E6E6", lw=0.8, zorder=1)
        ax.tick_params(axis="y", labelsize=8)
        ax.tick_params(axis="x", length=0)
        for s in ("top", "right"):
            ax.spines[s].set_visible(False)
    for ax in axes[:, 0]:
        ax.set_ylabel("IR (% de déviance)", fontsize=8)
    fig.suptitle("Importance relative des indices d'ECE par essence et par base (fond bleuté : bases à 1 km)",
                 fontsize=11, fontweight="bold", y=0.97)
    fig.legend(handles=[Patch(color=c.COUL_INDICE[i], label=c.LIB_INDICE[i]) for i in ORDRE_EMPIL],
               loc="center left", bbox_to_anchor=(0.87, 0.5), frameon=False, fontsize=9, handlelength=1.2,
               labelspacing=1.1)
    c.enregistrer(fig, "Fig09_IR_essence_base_indice")


if __name__ == "__main__":
    main()
