# downscaling-digitalis

Descente d'échelle **8–11 km → 1 km** de trois bases climatiques journalières
(**SAFRAN**, **E-OBS**, **CHELSA**) par la **méthode Delta**, calée sur la
climatologie mensuelle 1 km **DIGITALIS**. Produit, pour chaque base, des champs
journaliers de précipitation, tmin et tmax à 1 km cohérents avec la moyenne
mensuelle DIGITALIS.

Deux implémentations :
- **`r/`** — les scripts de production R **tels qu'exécutés** (parallélisés) pour l'étude.
- **`python/`** — une **implémentation de référence** lisible, testée et exécutable
  sur un petit échantillon (sans donnée réelle).

---

## Méthode en bref

Pour chaque (mois, variable), un facteur de correction mensuel calé sur DIGITALIS
est appliqué à chaque jour interpolé à 1 km :

| Variable | Interpolation source → 1 km | Facteur mensuel | Application jour |
|----------|------------------------------|-----------------|------------------|
| Précipitation | IDW (SAFRAN) ou bilinéaire (E-OBS/CHELSA) | `ratio = clamp(DIGI / max(src_m, 0,001), 0,001, 5)` | `jour × ratio` (≥ 0) |
| Température (tmin/tmax) | idem | `delta = DIGI − src_m` | `jour + delta` |

La **somme** mensuelle (précip) ou la **moyenne** mensuelle (temp) du résultat
égale DIGITALIS. Détails complets : [`docs/methode.md`](docs/methode.md).

## Structure

```
downscaling-digitalis/
├── r/          scripts R de production (SAFRAN IDW, E-OBS / CHELSA bilinéaire) + config + lanceur
├── python/     implémentation de référence (package downscaling_delta) + démo + tests
├── docs/       méthode détaillée + origine des données
├── LICENSE     CC-BY 4.0
└── CITATION.cff
```

## Démarrage rapide (Python, sans données réelles)

```bash
cd python
python3 -m pip install -r requirements.txt      # numpy, xarray, netCDF4
python3 demo_synthetique.py                      # pipeline complet sur données jouet
python3 tests/test_methode_delta.py              # tests unitaires
```

La démo génère des données synthétiques, applique les deux variantes de la méthode
(IDW + bilinéaire) et vérifie les propriétés de conservation. Aucune donnée réelle
requise ; `scipy`/`rasterio` sont optionnels.

## Reproduire sur les vraies données

1. **Obtenir les données** (SAFRAN, E-OBS, CHELSA, DIGITALIS) — voir
   [`docs/sources_donnees.md`](docs/sources_donnees.md).
2. **Adapter les chemins** : définir la variable d'environnement `DIGI_ROOT`
   (racine des données) ou éditer `r/config_chemins.R` (et `python/config_chemins.py`).
3. **Lancer** (R, sur une machine adaptée — production lourde) :
   ```r
   setwd("r")
   source("lanceur_downscaling.R")     # enchaîne les 3 bases
   # ou une base : source("production_CHELSA_bilineaire.R")
   ```

> Les scripts R détectent automatiquement le nombre de workers selon la charge
> CPU/RAM et reprennent sans recalculer les sorties déjà valides.

## Données et attribution

- **DIGITALIS** — climatologie mensuelle 1 km de la France, **œuvre de Christian
  Piedallu** (INRAE) ; utilisée ici comme **référence** de la correction. Elle
  n'est **pas** produite par ce dépôt et n'est pas librement redistribuable :
  contacter les auteurs.
- **SAFRAN / SIM2** — Météo-France · **E-OBS** — ECA&D / Copernicus ·
  **CHELSA v2.1** — Karger et al. Conditions d'accès et citations dans
  [`docs/sources_donnees.md`](docs/sources_donnees.md).

Développé par **Jeremy Genty** (stage M2), dans le cadre d'un projet encadré par
**Christian Piedallu** et **Violette Gautier** (INRAE). Voir [`CITATION.cff`](CITATION.cff).

## Licence

Code et documentation sous **[CC-BY 4.0](LICENSE)** : réutilisation libre avec
attribution. Les **données** (DIGITALIS, SAFRAN, E-OBS, CHELSA) relèvent de leurs
licences propres et ne sont pas couvertes par la présente.
