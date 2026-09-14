"""Entrees/sorties raster pour les VRAIES donnees (dependances optionnelles).

Ce module n'est PAS necessaire a la demo synthetique ni aux tests : le coeur
(methode_delta) travaille sur des tableaux NumPy. Il sert a brancher les vraies
sources (SAFRAN / E-OBS / CHELSA / DIGITALIS) et exige alors :

    pip install rioxarray rasterio geopandas

Les imports sont donc *paresseux* : importer le package ne les requiert pas.
"""
from __future__ import annotations

import numpy as np

# CRS cible du projet (Lambert 93).
CRS_L93 = "EPSG:2154"


def _exiger(nom_module):
    try:
        return __import__(nom_module)
    except ImportError as e:  # pragma: no cover - depend de l'environnement
        raise ImportError(
            f"'{nom_module}' est requis pour l'I/O raster reel. "
            f"Installer : pip install rioxarray rasterio geopandas"
        ) from e


def lire_raster(chemin):
    """Lit un GeoTIFF/NetCDF en xarray.DataArray (rioxarray)."""
    rioxarray = _exiger("rioxarray")
    return rioxarray.open_rasterio(chemin, masked=True).squeeze()


def reprojeter(da, crs_cible=CRS_L93, resolution=None, methode="bilinear"):
    """Reprojette un DataArray vers `crs_cible` (rioxarray/rasterio).

    Reproduit l'etape [B] des scripts R (ex. CHELSA WGS84 -> L93 bilineaire).
    """
    _exiger("rioxarray")
    from rasterio.enums import Resampling

    res = {"bilinear": Resampling.bilinear, "nearest": Resampling.nearest}[methode]
    if resolution is not None:
        return da.rio.reproject(crs_cible, resolution=resolution, resampling=res)
    return da.rio.reproject(crs_cible, resampling=res)


def masque_france(da, chemin_shp):
    """Masque un DataArray a l'emprise de la France (geopandas + rioxarray)."""
    gpd = _exiger("geopandas")
    _exiger("rioxarray")
    france = gpd.read_file(chemin_shp).to_crs(da.rio.crs)
    return da.rio.clip(france.geometry, france.crs, drop=False)


def ecrire_geotiff(da, chemin, compression="LZW"):
    """Ecrit un DataArray en GeoTIFF (float32, compresse)."""
    _exiger("rioxarray")
    da.astype("float32").rio.to_raster(chemin, compress=compression)


def ecrire_netcdf(da, chemin, nom_var, unite="", longname=""):
    """Ecrit un DataArray journalier en NetCDF (comme les sorties E-OBS)."""
    da = da.rename(nom_var)
    da.attrs.update(units=unite, long_name=longname)
    da.astype("float32").to_netcdf(chemin)
