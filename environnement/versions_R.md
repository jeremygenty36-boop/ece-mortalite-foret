# Versions de R et des paquets

La session R du serveur de calcul n'a pas été enregistrée pendant le stage (pas de `sessionInfo()`
ni de `renv.lock`), et ce serveur n'est plus accessible. Les versions ci-dessous ont été
**reconstituées le 14/09/2026** à partir des fichiers produits pendant le stage. Chaque ligne
indique son niveau de preuve.

## R

| Machine | Version | Preuve |
|---|---|---|
| Serveur de calcul (Windows, `x86_64-w64-mingw32`) | **R 4.3.1** | **certain** : en-tête (`infoRDS()$writer_version`) de tous les `.rds` écrits par les extractions sur NetCDF (`3-Donnees/6-IFN/_cache_moyennes_par_base/*.rds` du 17/07/2026, `_cache_Rx1day/*.rds` du 15/07/2026, `5-Resultats/1-Comparaison_BDD/7-Comparaison_variables/*.rds` des 10-11/06/2026) ; champ `Built: R 4.3.1; x86_64-w64-mingw32; windows` du paquet `climdex.pcic` compilé le 17/04/2026 |
| Poste Mac (figures, tests locaux) | **R 4.4.3** | **certain** : `.rds` du 10/06/2026 (`6-Comparaison_indices_ECE/valeurs_*_5km.rds`) et métadonnées `Producer: R 4.4.3` des PDF R produits sur le Mac |

## Paquets du calcul des indices (fournis avec Climpact)

| Paquet | Version | Preuve |
|---|---|---|
| climdex.pcic.ncdf | 0.5-4 (modifié, voir `third_party/climpact`) | **certain** : `DESCRIPTION` de la copie du projet |
| climdex.pcic | 1.2-0 (binaire Windows compilé le 17/04/2026 sous R 4.3.1) ou 1.1-11 (archive source) | **probable 1.2-0** : les deux sont présents dans `server/pcic_packages`, l'archive `climdex.pcic_1.1-11_win-binary.zip` contient en réalité la 1.2-0 compilée pour le serveur |
| PCICt | 0.5-4.4 | **certain** : archive fournie |
| ncdf4.helpers | 0.3-7 | **certain** : archive fournie |

## Autres paquets R sur le serveur de calcul

Sous Windows, `install.packages()` installe les binaires publiés par le CRAN pour la branche de R
utilisée. Pour R 4.3, ces binaires ne sont plus mis à jour depuis la sortie de R 4.5 : les versions
ci-dessous sont les dernières disponibles dans `https://cran.r-project.org/bin/windows/contrib/4.3/`
(consulté le 14/09/2026). Ce sont les versions **les plus probables** ; une installation depuis les
sources, ou antérieure au gel du dépôt, a pu donner une version plus ancienne.

| Paquet | Version probable | | Paquet | Version probable |
|---|---|---|---|---|
| terra | 1.8-29 | | ggplot2 | 3.5.1 |
| data.table | 1.17.0 | | patchwork | 1.3.0 |
| ncdf4 | 1.24 | | sf | 1.0-20 |
| SPEI | 1.8.1 | | dplyr | 1.1.4 |
| lubridate | 1.9.4 | | tidyr | 1.3.1 |
| matrixStats | 1.5.0 | | reshape2 | 1.4.4 |
| MLmetrics | 1.1.3 | | forcats | 1.0.0 |
| udunits2 | 0.13.2.1 | | ggtext | 0.1.2 |
| snow | 0.4-4 | | openxlsx | 4.2.8 |
| proj4 | 1.0-15 | | writexl | 1.5.3 |
| curl | 6.2.2 | | rnaturalearth | 1.0.1 |
| geodata | 0.6-2 | | rnaturalearthdata | 1.0.0 |

## Poste Mac (tests de la v1.1 et figures R)

Versions **certaines** (lues sur le poste le 14/09/2026) : R 4.4.3, terra 1.9.1, ncdf4 1.24,
data.table 1.17.0, ggplot2 4.0.2, patchwork 1.3.0, sf 1.1.0, MLmetrics 1.1.3 (installé pour les tests).
Python 3.14.6, numpy 2.4.1, pandas 2.3.3, matplotlib 3.10.8, xarray 2025.12.0, netCDF4 1.7.4.

## Reproduire l'environnement du serveur

Installer R 4.3.1, puis les versions ci-dessus, par exemple avec
`remotes::install_version("terra", version = "1.8-29")` pour chaque paquet, et Climpact selon
`third_party/climpact/README.md`. Cette procédure n'a pas été testée.
