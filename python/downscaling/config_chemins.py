"""Chemins du pipeline (equivalent Python de r/config_chemins.R) - a ADAPTER.

Source de verite des chemins pour l'I/O des VRAIES donnees. La demo synthetique
et les tests n'en ont pas besoin. Adapter via la variable d'environnement
DIGI_ROOT (racine des donnees) ou en editant RACINE ci-dessous. Voir
docs/sources_donnees.md pour l'origine et le format des donnees.
"""
from __future__ import annotations

import os
from pathlib import Path

# Racine des donnees : variable d'environnement DIGI_ROOT, ou editer ci-dessous.
_env = os.environ.get("DIGI_ROOT", "")
RACINE = Path(_env) if _env else None
if RACINE is None:
    # A defaut de DIGI_ROOT, decommenter et editer :
    # RACINE = Path("/data/downscaling")
    raise SystemExit("Definir DIGI_ROOT (racine des donnees) ou editer RACINE.")

SORTIE = Path(os.environ.get("DIGI_OUT", str(RACINE / "sorties_downscaling")))

# --- DIGITALIS (cible 1 km L93) : {prec,tmin,tmax}_ANNEE_MOIS.tif ---
DIGI_PREC = RACINE / "DIGITALIS" / "prec"
DIGI_TMIN = RACINE / "DIGITALIS" / "tmin"
DIGI_TMAX = RACINE / "DIGITALIS" / "tmax"

# --- Sources brutes ---
SAFRAN_CSV_DIR = RACINE / "SAFRAN"          # QUOT_SIM2_*.csv[.gz]
EOBS_DIR = RACINE / "E-OBS"                  # rr/tn/tx_ens_mean_0.1deg_*.nc
CHELSA_PR = RACINE / "CHELSA" / "pr"         # CHELSA_pr_DD_MM_YYYY_V.2.1.tif
CHELSA_TASMIN = RACINE / "CHELSA" / "tasmin"
CHELSA_TASMAX = RACINE / "CHELSA" / "tasmax"

# --- Masque / gabarit ---
FRANCE_SHP = RACINE / "masque" / "FRANCE.shp"
GABARIT_1KM_DIR = RACINE / "gabarit_1km"     # >= 1 TIF 1 km L93 de reference

# --- Sorties ---
OUT_SAFRAN = SORTIE / "SAFRAN_DS"
OUT_CHELSA = SORTIE / "CHELSA_DS"
OUT_EOBS = SORTIE / "EOBS_DS"
CACHE_SAFRAN = SORTIE / "cache_SAFRAN"


if __name__ == "__main__":
    print(f"[config] RACINE = {RACINE} | SORTIE = {SORTIE}")
    for nom in ("DIGI_PREC", "SAFRAN_CSV_DIR", "EOBS_DIR", "CHELSA_PR",
                "FRANCE_SHP", "OUT_SAFRAN", "OUT_CHELSA", "OUT_EOBS"):
        p = globals()[nom]
        print(f"  [{'OK ' if p.exists() else 'MANQ'}] {nom:16s} {p}")
