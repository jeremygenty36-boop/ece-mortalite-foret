# Version Python — downscaling 1 km par méthode Delta

Implémentation de **référence** (lisible, testée, exécutable) de la méthode Delta
utilisée par les scripts R de production du dossier `3-Downscaling`. Objectif :
**comprendre et reproduire** la méthode, pas produire les 65 ans × 3 bases en
parallèle (ça reste le rôle des scripts R sur CALCULUS).

> Portage fidèle mais **indépendant** des scripts R : mêmes formules, mêmes
> paramètres (IDW p=0,5 r=50 km ; ratio borné [0,001 ; 5]), vérifié par des tests
> de conservation. La machinerie serveur (parallélisme PSOCK, détection CPU
> PowerShell, throttle OMP, priorité process) n'est **pas** reprise.

## Méthode (rappel)

Pour chaque (mois, variable), un facteur de correction mensuel calé sur DIGITALIS
est appliqué à chaque jour interpolé à 1 km :

| Variable | Interpolation source→1 km | Facteur mensuel | Application jour |
|----------|---------------------------|-----------------|------------------|
| Précipitation | IDW (points) ou bilinéaire (grille) | `ratio = clamp(DIGI / max(src_m, 0.001), 0.001, 5)` | `jour × ratio` (≥ 0) |
| Température (tmin/tmax) | idem | `delta = DIGI − src_m` | `jour + delta` |

Conservation : la **somme** mensuelle (précip) ou la **moyenne** mensuelle (temp)
du résultat égale DIGITALIS. Cf. `../docs/methode.md` pour le contexte complet.

## Structure

```
python/
├── downscaling_delta/
│   ├── methode_delta.py   # coeur NumPy : stat mensuelle, facteur, application, downscale_mois
│   ├── interpolation.py   # IDW (NumPy, scipy optionnel) + bilinéaire (NumPy pur)
│   ├── io_raster.py        # I/O des VRAIES données (rioxarray/rasterio/geopandas — optionnels)
│   └── pipeline.py         # orchestration : points→IDW ou grille→bilinéaire, puis méthode Delta
├── config_chemins.py       # equivalent de r/config_chemins.R (racine DIGI_ROOT)
├── demo_synthetique.py     # démo bout-en-bout sur données jouet (aucune donnée réelle)
├── tests/test_methode_delta.py
└── requirements.txt
```

## Installation

```bash
python3 -m pip install -r requirements.txt   # numpy, xarray, netCDF4
```

`scipy` (IDW rapide) et `rioxarray/rasterio/geopandas` (données réelles) sont
**optionnels** : le cœur, la démo et les tests tournent sans eux.

## Utilisation

```bash
# Démo complète (précip via IDW + température via bilinéaire) + vérif conservation
python3 demo_synthetique.py

# Tests unitaires
python3 tests/test_methode_delta.py          # ou : python3 -m pytest

# Vérifier la résolution des chemins vers les vraies données
python3 config_chemins.py
```

### Sur les vraies données

```python
from downscaling_delta import pipeline as pl, methode_delta as md
from downscaling_delta import io_raster as io   # nécessite rioxarray/rasterio

# Exemple grille (E-OBS / CHELSA) : bilinéaire + delta additif pour la température
jours_1km = pl.downscale_mois_grille(jours_src, digi_mensuel, gx, gy, md.ADDITIF)
```

Pour SAFRAN (points 8 km) : `pl.downscale_mois_points(points_xy, valeurs_jours, ...)`.
La reprojection WGS84→L93 (CHELSA/E-OBS) et le masque France passent par
`io_raster.reprojeter` / `io_raster.masque_france`.

## Correspondance avec les scripts R

| Script R | Équivalent Python |
|----------|-------------------|
| `r/production_SAFRAN_IDW.R` | `pipeline.downscale_mois_points` + `interpolation.idw` |
| `r/production_EOBS_bilineaire.R` | `pipeline.downscale_mois_grille` + `interpolation.bilineaire` |
| `r/production_CHELSA_bilineaire.R` | idem (bilinéaire + reprojection L93) |
| `r/config_chemins.R` | `config_chemins.py` |
| cœur méthode (ratio/delta, clamp) | `methode_delta.py` |
