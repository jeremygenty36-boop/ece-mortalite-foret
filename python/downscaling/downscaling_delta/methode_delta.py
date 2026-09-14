"""Coeur de la methode Delta (portage fidele des scripts R de production).

La descente d'echelle applique, pour chaque (mois, variable), un *facteur de
correction mensuel* cale sur la climatologie DIGITALIS 1 km, a chaque jour du
mois interpole a 1 km :

    Precipitation (multiplicatif) :
        ratio_m   = clamp( DIGI_mensuel / max(source_mensuel_1km, eps),  min, max )
        jour_corr = max( source_jour_1km * ratio_m, 0 )
        => la somme mensuelle est recalee sur DIGITALIS, les jours secs preserves.

    Temperature (additif) :
        delta_m   = DIGI_mensuel - source_mensuel_1km
        jour_corr = source_jour_1km + delta_m
        => la moyenne mensuelle est calee sur DIGITALIS, la variabilite journaliere
           preservee.

Ce module ne manipule que des tableaux NumPy (aucune dependance geospatiale) :
il est donc directement testable et executable. La lecture/ecriture raster et la
reprojection reelle sont dans `io_raster.py` (dependances optionnelles).

Convention : les valeurs manquantes sont des NaN et le restent (jamais 0).
"""
from __future__ import annotations

import warnings

import numpy as np

# Bornes du ratio (identiques aux scripts R : RATIO_MIN / RATIO_MAX).
RATIO_MIN = 0.001
RATIO_MAX = 5.0

MULTIPLICATIF = "multiplicatif"  # precipitation
ADDITIF = "additif"              # temperature (tmin / tmax)


def stat_mensuelle(jours_1km: np.ndarray, methode: str) -> np.ndarray:
    """Statistique mensuelle de la source (deja interpolee a 1 km).

    Parameters
    ----------
    jours_1km : ndarray, forme (n_jours, ny, nx)
        Champs journaliers de la source, interpoles sur la grille cible 1 km.
    methode : {"multiplicatif", "additif"}
        multiplicatif -> somme mensuelle (precipitation) ;
        additif       -> moyenne mensuelle (temperature).

    Returns
    -------
    ndarray, forme (ny, nx)
    """
    _valider_methode(methode)
    if jours_1km.ndim != 3:
        raise ValueError("jours_1km doit avoir la forme (n_jours, ny, nx)")
    if methode == MULTIPLICATIF:
        return np.nansum(jours_1km, axis=0)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)  # cellule tout-NaN -> NaN (voulu)
        return np.nanmean(jours_1km, axis=0)


def facteur_mensuel(
    source_mensuel_1km: np.ndarray,
    digitalis_mensuel_1km: np.ndarray,
    methode: str,
    ratio_min: float = RATIO_MIN,
    ratio_max: float = RATIO_MAX,
) -> np.ndarray:
    """Facteur de correction mensuel (ratio pour precip, delta pour temperature).

    Parameters
    ----------
    source_mensuel_1km : ndarray (ny, nx)
        Statistique mensuelle de la source a 1 km (somme ou moyenne).
    digitalis_mensuel_1km : ndarray (ny, nx)
        Climatologie mensuelle DIGITALIS a 1 km (deja a l'unite finale : mm ou degC).
    methode : {"multiplicatif", "additif"}
    ratio_min, ratio_max : float
        Bornes du ratio (multiplicatif uniquement).

    Returns
    -------
    ndarray (ny, nx)
        ratio (multiplicatif) borne a [ratio_min, ratio_max], ou delta (additif).
    """
    _valider_methode(methode)
    if methode == ADDITIF:
        return digitalis_mensuel_1km - source_mensuel_1km
    # Multiplicatif : eviter la division par ~0 (denominateur plancher a ratio_min),
    # puis borner le ratio comme dans les scripts R.
    denom = np.where(source_mensuel_1km < ratio_min, ratio_min, source_mensuel_1km)
    ratio = digitalis_mensuel_1km / denom
    return np.clip(ratio, ratio_min, ratio_max)


def appliquer_jour(source_jour_1km: np.ndarray, facteur: np.ndarray, methode: str) -> np.ndarray:
    """Applique le facteur mensuel a un champ journalier (1 km)."""
    _valider_methode(methode)
    if methode == ADDITIF:
        return source_jour_1km + facteur
    # Precipitation : produit borne a 0 (pas de precip negative).
    return np.maximum(source_jour_1km * facteur, 0.0)


def downscale_mois(
    source_jours_1km: np.ndarray,
    digitalis_mensuel_1km: np.ndarray,
    methode: str,
    ratio_min: float = RATIO_MIN,
    ratio_max: float = RATIO_MAX,
) -> np.ndarray:
    """Descente d'echelle d'un mois complet (enchaine stat -> facteur -> application).

    C'est l'equivalent, en une fonction, de la boucle mensuelle des scripts R.
    La statistique mensuelle est calculee sur les MEMES champs journaliers 1 km que
    ceux corriges ensuite : la conservation (somme/moyenne mensuelle = DIGITALIS) est
    donc exacte tant que le ratio n'est pas borne.

    Parameters
    ----------
    source_jours_1km : ndarray (n_jours, ny, nx)
        Source journaliere deja interpolee a 1 km (cf. interpolation.py).
    digitalis_mensuel_1km : ndarray (ny, nx)
    methode : {"multiplicatif", "additif"}

    Returns
    -------
    ndarray (n_jours, ny, nx) : champs journaliers corriges.
    """
    _valider_methode(methode)
    src_m = stat_mensuelle(source_jours_1km, methode)
    fac = facteur_mensuel(src_m, digitalis_mensuel_1km, methode, ratio_min, ratio_max)
    return np.stack([appliquer_jour(j, fac, methode) for j in source_jours_1km], axis=0)


def _valider_methode(methode: str) -> None:
    if methode not in (MULTIPLICATIF, ADDITIF):
        raise ValueError(
            f"methode inconnue : {methode!r} (attendu {MULTIPLICATIF!r} ou {ADDITIF!r})"
        )
