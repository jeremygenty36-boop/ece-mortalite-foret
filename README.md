# ece-mortalite-foret

Chaîne de traitement complète du stage de Master 2 de Jérémy Genty (UMR Silva,
2025-2026) : **les événements climatiques extrêmes (ECE), calculés à 1 km,
expliquent-ils la mortalité des arbres mieux que le climat moyen ?**

La chaîne descend trois bases climatiques journalières à 1 km (méthode Delta),
en dérive six indices d'extrêmes, les extrait aux placettes de l'Inventaire
forestier national, puis modélise la mortalité par essence et par base.

> **Version v1.1.** Corrige les écarts relevés à la relecture du code du rapport
> ([`ERRATA.md`](ERRATA.md), [`CHANGELOG.md`](CHANGELOG.md)) : SPEI6 annuel en minimum, même
> échantillon de placettes et mêmes partitions pour toutes les bases, tableaux calculés, figures
> perdues recréées. **Ce code n'a pas été réexécuté sur les données complètes** ; les résultats
> du rapport de stage (juillet 2026) ont été produits par la version taguée `v1.0-rapport`,
> identique au code exécuté à l'époque (seuls les chemins y sont configurables).

## La chaîne en 7 modules

| Module | Rôle | Machine |
|---|---|---|
| [`R/01_sources`](R/01_sources) | téléchargement et contrôle des sources (CHELSA, E-OBS, SAFRAN, limites France) | calcul |
| [`R/02_downscaling`](R/02_downscaling) | descente d'échelle à 1 km par méthode Delta (SAFRAN IDW, E-OBS et CHELSA bilinéaire) | calcul |
| [`R/03_netcdf_annuels`](R/03_netcdf_annuels) | mise en forme en NetCDF annuels WGS84 | calcul |
| [`R/04_indices_ece`](R/04_indices_ece) | 6 indices (TXx, TNn, SPEI6, WG10P, HWN, CWN) × 6 bases, puis post-traitement | calcul |
| [`R/05_extraction_ifn`](R/05_extraction_ifn) | jeu d'analyse aux placettes IFN (fenêtre de 10 ans) | calcul |
| [`R/06_modele`](R/06_modele) | GLM cloglog par essence × base, 1 000 partitions 70/30 | calcul |
| [`R/07_figures`](R/07_figures), [`python/figures`](python/figures) | figures du rapport | calcul ou poste |

Détail des entrées, sorties et de l'ordre d'exécution : [`docs/pipeline.md`](docs/pipeline.md).

## Documentation

- [`docs/pipeline.md`](docs/pipeline.md) : ordre d'exécution, entrées, sorties, arborescence attendue
- [`docs/methode_downscaling.md`](docs/methode_downscaling.md) : méthode Delta
- [`docs/indices_ece.md`](docs/indices_ece.md) : définition des 6 indices, telle que codée
- [`docs/modele_mortalite.md`](docs/modele_mortalite.md) : jeu d'analyse et modèle
- [`docs/figures_rapport.md`](docs/figures_rapport.md) : chaque figure du rapport et son script
- [`docs/sources_donnees.md`](docs/sources_donnees.md) : origine et accès aux données
- [`ERRATA.md`](ERRATA.md) : écarts relevés et leur statut en v1.1
- [`CHANGELOG.md`](CHANGELOG.md) : différences entre v1.0 et v1.1
- [`tests/`](tests) : tests locaux des corrections

## Lancer un script

Les scripts R ont été exécutés sous Windows (serveur de calcul, 36 cœurs, 384 Go),
données sur un stockage réseau. Depuis la **racine du dépôt**, dans une console R :

```r
setwd("C:/chemin/vers/ece-mortalite-foret")
Sys.setenv(ECE_NAS_ROOT = "S:", ECE_LOCAL_ROOT = "D:/Stage_JeremyG")   # adapter
source("R/04_indices_ece/1-ECE_EOBS.R")
```

Chaque script charge [`config/chemins.R`](config/chemins.R), qui définit les racines
(`PROJET`, `LOCAL_ROOT`, `CLIMPACT_RACINE`, `MASQUE_FRANCE_GPKG`, `PYTHON_EXE`).
Le module 02 garde sa propre configuration ([`R/02_downscaling/config_chemins.R`](R/02_downscaling/config_chemins.R),
variable `DIGI_ROOT`).

Les modules 01 à 04 manipulent des dizaines de Go et tournent plusieurs jours.
Machine partagée : plafonner les workers (`N_PARALLEL_ECE`, `N_PARALLEL`) avant `source()`.

## Ce que le dépôt ne contient pas

- **Aucune donnée** : climat brut ou downscalé, indices, `IFN_placette.csv`, résultats de modèles.
  DIGITALIS (C. Piedallu, INRAE) n'est pas redistribuable ; les autres jeux relèvent de leurs licences.
- **Climpact** : à télécharger (v3.3.2), puis appliquer les modifications du projet
  ([`third_party/climpact`](third_party/climpact)).
- Le masque GADM `France_GADM_L0.gpkg` (licence GADM) : produit par `R/01_sources/0-Telecharger_limites_France.R`.
- Les scripts exploratoires, diagnostics ponctuels et correctifs historiques, restés dans l'arborescence du projet.

## Attribution

Développé par **Jérémy Genty** (stage M2), encadré par **Christian Piedallu** et
**Violette Gautier**. La climatologie DIGITALIS, référence de la correction, est
l'œuvre de Christian Piedallu. Voir [`CITATION.cff`](CITATION.cff).

## Licence

Voir [`LICENSE`](LICENSE). Le choix de licence et la diffusion publique restent à
valider avec les encadrants avant toute mise en ligne. Les fichiers de
`third_party/climpact` sont sous GPL-3 (licence de Climpact).
