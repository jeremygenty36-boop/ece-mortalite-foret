"""Orchestration : interpolation a 1 km puis methode Delta, pour un mois.

Deux entrees selon le type de source (comme les 3 scripts R) :

- `downscale_mois_points`  : source = POINTS (SAFRAN 8 km)  -> IDW
- `downscale_mois_grille`  : source = GRILLE (E-OBS/CHELSA) -> bilineaire

Les deux delegent le calcul du facteur et l'application journaliere au coeur
`methode_delta.downscale_mois`. Ce module ne fait AUCUNE I/O : il recoit des
tableaux/DataArray deja charges (via io_raster pour les vraies donnees, ou
generes pour la demo).
"""
from __future__ import annotations

import numpy as np

from . import interpolation as itp
from . import methode_delta as md


def downscale_mois_points(
    points_xy,
    valeurs_jours,
    digitalis_mensuel_1km,
    grille_x,
    grille_y,
    methode,
    power: float = itp.IDW_POWER,
    radius: float = itp.IDW_RADIUS,
    ratio_min: float = md.RATIO_MIN,
    ratio_max: float = md.RATIO_MAX,
) -> np.ndarray:
    """Source ponctuelle (SAFRAN) : IDW de chaque jour puis methode Delta.

    Parameters
    ----------
    points_xy : ndarray (n_points, 2)   coordonnees des points (CRS grille, m)
    valeurs_jours : ndarray (n_jours, n_points)   valeur par jour et par point
    digitalis_mensuel_1km : ndarray (ny, nx)
    grille_x, grille_y : ndarray 1D    grille cible 1 km
    methode : {"multiplicatif", "additif"}
    """
    jours_1km = np.stack(
        [itp.idw(points_xy, v, grille_x, grille_y, power, radius) for v in valeurs_jours],
        axis=0,
    )
    return md.downscale_mois(jours_1km, digitalis_mensuel_1km, methode, ratio_min, ratio_max)


def downscale_mois_grille(
    source_jours,
    digitalis_mensuel_1km,
    grille_x,
    grille_y,
    methode,
    ratio_min: float = md.RATIO_MIN,
    ratio_max: float = md.RATIO_MAX,
) -> np.ndarray:
    """Source en grille (E-OBS/CHELSA) : bilineaire de chaque jour puis methode Delta.

    `source_jours` est une liste/iterable de xarray.DataArray journaliers (memes
    coordonnees), ou un DataArray a dimension temps en premier axe.
    """
    jours_1km = np.stack(
        [np.asarray(itp.bilineaire(j, grille_x, grille_y)) for j in source_jours],
        axis=0,
    )
    return md.downscale_mois(jours_1km, np.asarray(digitalis_mensuel_1km),
                             methode, ratio_min, ratio_max)
