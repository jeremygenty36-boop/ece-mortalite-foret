"""Demo de bout en bout sur donnees SYNTHETIQUES (aucune donnee reelle requise).

Montre les deux chemins de la methode Delta et verifie les proprietes de
conservation attendues :

  1. Precipitation (source ponctuelle -> IDW, multiplicatif)
       -> la SOMME mensuelle du resultat = DIGITALIS mensuel (ratio non borne)
  2. Temperature (source en grille -> bilineaire, additif)
       -> la MOYENNE mensuelle du resultat = DIGITALIS mensuel

Dependances : numpy, xarray, netCDF4 (pas de scipy/rasterio/geopandas).
Lancer :   python demo_synthetique.py
"""
from __future__ import annotations

import numpy as np
import xarray as xr

from downscaling_delta import interpolation as itp
from downscaling_delta import methode_delta as md
from downscaling_delta import pipeline as pl

RNG = np.random.default_rng(36)  # deterministe


def grille_cible():
    """Petite grille cible 1 km (coords en metres, style L93 reduit)."""
    x = np.arange(0, 40_000, 1_000, dtype=float)   # 40 colonnes
    y = np.arange(0, 30_000, 1_000, dtype=float)   # 30 lignes
    return x, y


# ======================================================================
# 1. PRECIPITATION : points 8 km -> IDW -> Delta multiplicatif
# ======================================================================
def demo_precip():
    print("\n=== 1. PRECIPITATION (points -> IDW, multiplicatif) ===")
    gx, gy = grille_cible()
    n_jours, n_pts = 30, 60

    # Points source disperses sur le domaine (coords m).
    pts = np.column_stack([RNG.uniform(0, 39_000, n_pts),
                           RNG.uniform(0, 29_000, n_pts)])
    # Precip journaliere par point (mm) : beaucoup de jours secs, quelques pluies.
    val_jours = RNG.gamma(shape=0.4, scale=6.0, size=(n_jours, n_pts))
    val_jours[RNG.random((n_jours, n_pts)) < 0.5] = 0.0  # jours secs

    # Interpolation IDW de chaque jour (parametres projet : p=0.5, r=50 km).
    jours_1km = np.stack([itp.idw(pts, v, gx, gy) for v in val_jours], axis=0)
    source_mensuel = md.stat_mensuelle(jours_1km, md.MULTIPLICATIF)

    # DIGITALIS "cible" construit dans les bornes du ratio (facteur 0.7-1.5).
    facteur_cible = RNG.uniform(0.7, 1.5, source_mensuel.shape)
    digi_mensuel = source_mensuel * facteur_cible

    corrige = md.downscale_mois(jours_1km, digi_mensuel, md.MULTIPLICATIF)

    # Verification via le wrapper pipeline (doit etre identique).
    corrige_pl = pl.downscale_mois_points(pts, val_jours, digi_mensuel, gx, gy,
                                          md.MULTIPLICATIF)

    somme = np.nansum(corrige, axis=0)
    fini = np.isfinite(digi_mensuel) & (digi_mensuel > 0)
    err = np.nanmax(np.abs(somme[fini] - digi_mensuel[fini]) / digi_mensuel[fini])
    print(f"  cellules valides            : {int(fini.sum())} / {fini.size}")
    print(f"  min corrige (>= 0 attendu)  : {np.nanmin(corrige):.4f}")
    print(f"  erreur rel. max somme/DIGI  : {err:.2e}   (conservation)")
    print(f"  identique au wrapper        : {np.allclose(corrige, corrige_pl, equal_nan=True)}")
    assert np.nanmin(corrige) >= -1e-9, "precip negative"
    assert err < 1e-10, "conservation de la somme mensuelle rompue"
    return corrige, gx, gy


# ======================================================================
# 2. TEMPERATURE : grille grossiere -> bilineaire -> Delta additif
# ======================================================================
def demo_temp():
    print("\n=== 2. TEMPERATURE (grille -> bilineaire, additif) ===")
    gx, gy = grille_cible()
    n_jours = 30

    # Grille source grossiere (~4 km) en xarray, gradient + bruit journalier.
    # Emprise legerement plus large que la cible pour la couvrir entierement.
    cx = np.arange(-4_000, 44_001, 4_000, dtype=float)
    cy = np.arange(-4_000, 34_001, 4_000, dtype=float)
    base = 8.0 + 0.0002 * cx[None, :] - 0.0003 * cy[:, None]
    jours_src = []
    for j in range(n_jours):
        champ = base + RNG.normal(0, 2.0) + RNG.normal(0, 0.3, base.shape)
        jours_src.append(xr.DataArray(champ, coords={"y": cy, "x": cx}, dims=("y", "x")))

    # Interpolation bilineaire de chaque jour vers 1 km.
    jours_1km = np.stack([np.asarray(itp.bilineaire(d, gx, gy)) for d in jours_src], axis=0)
    source_mensuel = md.stat_mensuelle(jours_1km, md.ADDITIF)   # moyenne

    # DIGITALIS "cible" = moyenne source + delta spatial modere.
    delta_cible = RNG.uniform(-1.5, 1.5, source_mensuel.shape)
    digi_mensuel = source_mensuel + delta_cible

    corrige = pl.downscale_mois_grille(jours_src, digi_mensuel, gx, gy, md.ADDITIF)

    moyenne = np.nanmean(corrige, axis=0)
    fini = np.isfinite(digi_mensuel)
    err = np.nanmax(np.abs(moyenne[fini] - digi_mensuel[fini]))
    print(f"  cellules valides            : {int(fini.sum())} / {fini.size}")
    print(f"  erreur abs. max moy./DIGI    : {err:.2e} degC   (conservation)")
    assert err < 1e-9, "conservation de la moyenne mensuelle rompue"
    return corrige, gx, gy


def ecrire_demo_netcdf(prec, temp, gx, gy, chemin="sortie_demo.nc"):
    """Ecrit les deux sorties journalieres en NetCDF (xarray, sans rioxarray)."""
    jours = np.arange(prec.shape[0])
    ds = xr.Dataset(
        {
            "prec": (("time", "y", "x"), prec.astype("float32")),
            "temp": (("time", "y", "x"), temp.astype("float32")),
        },
        coords={"time": jours, "y": gy, "x": gx},
    )
    ds.prec.attrs.update(units="mm", long_name="Precipitation downscalee 1km (demo, methode Delta)")
    ds.temp.attrs.update(units="degC", long_name="Temperature downscalee 1km (demo, methode Delta)")
    ds.to_netcdf(chemin)
    print(f"\n  NetCDF ecrit : {chemin}  ({ds.sizes['time']} jours, "
          f"{ds.sizes['y']}x{ds.sizes['x']} cellules)")


if __name__ == "__main__":
    print("DEMO methode Delta - donnees synthetiques (seed=36)")
    prec, gx, gy = demo_precip()
    temp, _, _ = demo_temp()
    ecrire_demo_netcdf(prec, temp, gx, gy)
    print("\nOK : les deux proprietes de conservation sont verifiees.")
