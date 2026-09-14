# -*- coding: utf-8 -*-
"""Elements communs aux figures Python du rapport (chemins, lecture, libelles, couleurs).

Variables d'environnement (toutes facultatives) :
  ECE_PROJET        dossier du projet (contient 3-Donnees/ et 5-Resultats/)
                    defaut : <ECE_NAS_ROOT>/Projets/stage_JeremyG, sinon S:/ ou /Volumes/_donnees
  ECE_F_IFN         chemin de IFN_placette.csv   (defaut : <ECE_PROJET>/3-Donnees/6-IFN/IFN_placette.csv)
  ECE_DIR_MODELES   dossier des runs              (defaut : <ECE_PROJET>/5-Resultats/5-Modeles/standard)
  ECE_RUN_ECE       run peuplement + ECE          (defaut : Mortalite_2015-2023_r070_n1000_binaire)
  ECE_FIGURES_OUT   dossier de sortie             (defaut : ./sorties_figures)
"""
import os
import numpy as np
import pandas as pd
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

plt.rcParams.update({"font.family": "DejaVu Sans", "pdf.fonttype": 3, "axes.unicode_minus": False})


def _projet():
    if os.environ.get("ECE_PROJET"):
        return os.environ["ECE_PROJET"]
    if os.environ.get("ECE_NAS_ROOT"):
        return os.path.join(os.environ["ECE_NAS_ROOT"], "Projets", "stage_JeremyG")
    for racine in ("S:/", "/Volumes/_donnees"):
        if os.path.isdir(os.path.join(racine, "Projets")):
            return os.path.join(racine, "Projets", "stage_JeremyG")
    raise SystemExit("Definir ECE_PROJET (dossier contenant 3-Donnees/ et 5-Resultats/)")


def chemin_ifn():
    return os.environ.get("ECE_F_IFN") or os.path.join(_projet(), "3-Donnees", "6-IFN", "IFN_placette.csv")


def chemin_run(fichier, run=None):
    base = os.environ.get("ECE_DIR_MODELES") or os.path.join(_projet(), "5-Resultats", "5-Modeles", "standard")
    run = run or os.environ.get("ECE_RUN_ECE", "Mortalite_2015-2023_r070_n1000_binaire")
    return os.path.join(base, run, "2-Syntheses", fichier)


def dossier_sortie():
    d = os.environ.get("ECE_FIGURES_OUT", "sorties_figures")
    os.makedirs(d, exist_ok=True)
    return d


def enregistrer(fig, nom):
    d = dossier_sortie()
    for ext in ("pdf", "png"):
        fig.savefig(os.path.join(d, f"{nom}.{ext}"), dpi=200, bbox_inches="tight")
    print("ecrit :", os.path.join(d, nom + ".pdf"))


def placettes_ifn(colonnes, camp_min=2015, camp_max=2023):
    """Une ligne par placette (dedoublonnage par idp), campagnes camp_min-camp_max, Corse exclue.
    C'est l'echantillon des Fig. 6 et 7 du rapport (31 600 placettes), et non les 34 255
    observations placette x essence du modele."""
    cols = ["idp", "campagne", "dep"] + [c for c in colonnes if c not in ("idp", "campagne", "dep")]
    d = pd.read_csv(chemin_ifn(), sep=";", usecols=cols, low_memory=False)
    d = d[(d.campagne >= camp_min) & (d.campagne <= camp_max) & (~d.dep.astype(str).isin(["2A", "2B"]))]
    return d.drop_duplicates("idp").reset_index(drop=True)


def virgule(x, nd=2):
    return f"{x:.{nd}f}".replace(".", ",")


INDICES_ECE = ["TXx", "TNn", "SPEI6", "WG10P", "HWN", "CWN"]
LIB_INDICE = {"TXx": "TXx", "TNn": "TNn", "SPEI6": "SPEI-6", "WG10P": "WG10P", "HWN": "HWN", "CWN": "CWN"}
BASES_5 = ["SAF8", "EOB10", "CHE1", "SAFDS", "EOBDS"]
LIB_BASE = {"SAF8": "SAF-8", "EOB10": "EOBS-10", "CHE1": "CHE-1", "SAFDS": "SAF-DS", "EOBDS": "EOBS-DS"}
ESP_NOMS = {"QURO": "Q. robur", "QUPE": "Q. petraea", "FASY": "F. sylvatica", "PISY": "P. sylvestris",
            "PINI": "P. nigra", "ABAL": "A. alba", "PIAB": "P. abies", "BEPE": "B. pendula"}
# couleurs par indice (palette ColorBrewer du rapport)
COUL_INDICE = {"TXx": "#E6550D", "HWN": "#FDAE6B", "TNn": "#3182BD", "CWN": "#9ECAE1",
               "SPEI6": "#31A354", "WG10P": "#A1D99B"}
VAR_FIXES = ["pH", "G_ha_tot", "Gini", "c13_moy_sp", "prop_G"]
