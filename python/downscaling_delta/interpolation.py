"""Interpolation source -> grille cible 1 km.

Deux methodes, comme dans les scripts R :

- IDW (Inverse Distance Weighting) pour SAFRAN, qui est fourni sous forme de
  POINTS 8 km (parametres du projet : puissance 0.5, rayon 50 km).
- Bilineaire pour E-OBS et CHELSA, fournis sous forme de GRILLES.

L'IDW est implemente en NumPy pur (chemin rapide optionnel via scipy.cKDTree si
installe). Le bilineaire s'appuie sur xarray.DataArray.interp (meme CRS / grille).
La reprojection reelle entre CRS (WGS84 -> L93) releve de rioxarray/rasterio :
voir io_raster.py (dependances optionnelles).
"""
from __future__ import annotations

import numpy as np

# Parametres IDW du projet (cf. IDW_POWER / IDW_RADIUS des scripts R SAFRAN).
IDW_POWER = 0.5
IDW_RADIUS = 50_000.0  # metres


def idw(
    points_xy: np.ndarray,
    valeurs: np.ndarray,
    grille_x: np.ndarray,
    grille_y: np.ndarray,
    power: float = IDW_POWER,
    radius: float = IDW_RADIUS,
) -> np.ndarray:
    """Interpole des points sur une grille reguliere par IDW a rayon limite.

    Parameters
    ----------
    points_xy : ndarray (n_points, 2)
        Coordonnees (x, y) des points source, dans le CRS de la grille cible (metres).
    valeurs : ndarray (n_points,)
        Valeur en chaque point (les NaN sont ignores).
    grille_x, grille_y : ndarray 1D
        Centres des colonnes (x) et des lignes (y) de la grille cible.
    power : float
        Puissance de la ponderation (poids = distance ** -power).
    radius : float
        Rayon de recherche (m). Au-dela, les points ne contribuent pas.

    Returns
    -------
    ndarray (ny, nx) : champ interpole (NaN la ou aucun point dans le rayon).
    """
    pts = np.asarray(points_xy, dtype=float)
    val = np.asarray(valeurs, dtype=float)
    ok = np.isfinite(val) & np.isfinite(pts).all(axis=1)
    pts, val = pts[ok], val[ok]
    if pts.shape[0] == 0:
        return np.full((grille_y.size, grille_x.size), np.nan)

    gx, gy = np.meshgrid(grille_x, grille_y)           # (ny, nx)
    cible = np.column_stack([gx.ravel(), gy.ravel()])  # (n_cible, 2)

    fast = _idw_scipy(pts, val, cible, power, radius)
    if fast is not None:
        return fast.reshape(gx.shape)

    # Chemin NumPy pur (par blocs de cellules cibles pour limiter la RAM).
    out = np.empty(cible.shape[0], dtype=float)
    bloc = 20_000
    r2 = radius * radius
    for i in range(0, cible.shape[0], bloc):
        c = cible[i : i + bloc]                                   # (b, 2)
        d2 = ((c[:, None, :] - pts[None, :, :]) ** 2).sum(axis=2)  # (b, n_pts)
        with np.errstate(divide="ignore"):
            w = np.where((d2 <= r2) & (d2 > 0), np.sqrt(d2) ** (-power), 0.0)
        # Point exactement sur une cellule : poids infini -> valeur exacte.
        exact = d2 == 0
        num = (w * val[None, :]).sum(axis=1)
        den = w.sum(axis=1)
        res = np.divide(num, den, out=np.full(c.shape[0], np.nan), where=den > 0)
        if exact.any():
            lignes = np.where(exact.any(axis=1))[0]
            for l in lignes:
                res[l] = val[np.argmax(exact[l])]
        out[i : i + bloc] = res
    return out.reshape(gx.shape)


def _idw_scipy(pts, val, cible, power, radius):
    """Chemin rapide via scipy.cKDTree si disponible, sinon None."""
    try:
        from scipy.spatial import cKDTree
    except ImportError:
        return None
    arbre = cKDTree(pts)
    voisins = arbre.query_ball_point(cible, r=radius)
    out = np.full(cible.shape[0], np.nan)
    for i, idx in enumerate(voisins):
        if not idx:
            continue
        d = np.sqrt(((cible[i] - pts[idx]) ** 2).sum(axis=1))
        if (d == 0).any():
            out[i] = val[idx][np.argmin(d)]
            continue
        w = d ** (-power)
        out[i] = (w * val[idx]).sum() / w.sum()
    return out


def bilineaire(source, grille_x: np.ndarray, grille_y: np.ndarray) -> np.ndarray:
    """Interpolation bilineaire d'une grille reguliere vers (grille_x, grille_y).

    Implementation NumPy pure (aucune dependance) pour une grille source
    REGULIERE, dans le MEME systeme de coordonnees que la grille cible. Pour
    changer de CRS (ex. WGS84 -> L93), reprojeter d'abord via io_raster.reprojeter.

    `source` peut etre :
      - un xarray.DataArray a coords x/y (ou lon/lat), ou
      - un tuple (champ2d, src_x, src_y) de tableaux NumPy.

    Retourne un ndarray (ny, nx) ; NaN hors de l'emprise source.
    """
    champ, sx, sy = _extraire_grille(source)
    return _bilineaire_reguliere(
        np.asarray(champ, float), np.asarray(sx, float), np.asarray(sy, float),
        np.asarray(grille_x, float), np.asarray(grille_y, float),
    )


def _extraire_grille(source):
    if isinstance(source, tuple):
        return source
    nom_x, nom_y = _noms_xy(source)  # xarray.DataArray
    return source.values, source[nom_x].values, source[nom_y].values


def _noms_xy(da):
    for cx, cy in (("x", "y"), ("lon", "lat"), ("longitude", "latitude")):
        if cx in da.coords and cy in da.coords:
            return cx, cy
    raise ValueError("Impossible de trouver les coordonnees x/y (ou lon/lat).")


def _bilineaire_reguliere(champ, sx, sy, dx, dy):
    """Bilineaire depuis une grille reguliere (sx, sy croissants) ; champ indexe [y, x]."""
    if champ.shape != (sy.size, sx.size):
        raise ValueError("champ doit avoir la forme (len(src_y), len(src_x))")
    ix = np.clip(np.searchsorted(sx, dx) - 1, 0, sx.size - 2)
    iy = np.clip(np.searchsorted(sy, dy) - 1, 0, sy.size - 2)
    tx = (dx - sx[ix]) / (sx[ix + 1] - sx[ix])   # (nx,)
    ty = (dy - sy[iy]) / (sy[iy + 1] - sy[iy])   # (ny,)
    IX, IY = np.meshgrid(ix, iy)                  # (ny, nx)
    TX, TY = np.meshgrid(tx, ty)
    v00, v01 = champ[IY, IX],     champ[IY, IX + 1]
    v10, v11 = champ[IY + 1, IX], champ[IY + 1, IX + 1]
    out = (v00 * (1 - TX) * (1 - TY) + v01 * TX * (1 - TY)
           + v10 * (1 - TX) * TY + v11 * TX * TY)
    hors = ((dy < sy[0]) | (dy > sy[-1]))[:, None] | ((dx < sx[0]) | (dx > sx[-1]))[None, :]
    out[hors] = np.nan
    return out
