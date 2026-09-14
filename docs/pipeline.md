# Pipeline : ordre d'exécution, entrées, sorties

Les chemins sont donnés relativement aux racines de [`config/chemins.R`](../config/chemins.R) :
`PROJET` (dossier du projet sur le stockage partagé), `LOCAL_ROOT` (disque local rapide
de la machine de calcul), `.PFX` (racine qui contient aussi `BD_SIG/`).

Tous les scripts se lancent **depuis la racine du dépôt** (`setwd()` ou `ECE_DEPOT`).

```
sources brutes ──► 02 downscaling 1 km ──► 03 NetCDF annuels ──► 04 indices ECE ──► post-traitement
                                                                                        │
                                   07 figures ◄── 06 modèles ◄── 05 extraction IFN ◄────┘
```

## 01 · Sources

| Script | Rôle | Sortie |
|---|---|---|
| `0-Telecharger_limites_France.R` | limites France (GADM niveau 0) | `MASQUE_FRANCE_GPKG` |
| `1-Download_CHELSA_daily_1960_1981.R`, `1.2-…manquants.R`, `1.4-…jours_manquants.R` | CHELSA V2.1 journalier (pr, tasmin, tasmax) | `PROJET/3-Donnees/2-CHELSA/...` (emplacement historique) |
| `1.1-Verification_CHELSA.R`, `1.3-Diagnostic_TIF_CHELSA_corrompus.R` | contrôle des TIF CHELSA (audit) | `PROJET/5-Resultats/0-Diagnostics_sources` |
| `3.1-Verification_EOBS.R`, `3.2-Diagnostic_NA_EOBS.R` | contrôle E-OBS (audit) | rapports texte |
| `2-Calcul_SAFRAN_ForcPRCP_horaire_vers_journalier.R` | test d'agrégation horaire → journalier SAFRAN, **septembre 2014 seulement** | `PROJET/3-Donnees/1-SAFRAN/1-2014_SAFRAN` |

E-OBS v31.0e et SAFRAN SIM2 se téléchargent à la main (voir [`sources_donnees.md`](sources_donnees.md)).

## 02 · Downscaling 1 km (méthode Delta)

Configuration propre : [`R/02_downscaling/config_chemins.R`](../R/02_downscaling/config_chemins.R) (`DIGI_ROOT`).
Lanceur : `lanceur_downscaling.R` (depuis `R/02_downscaling/`), qui enchaîne :

| Script | Base produite | Interpolation |
|---|---|---|
| `production_SAFRAN_IDW.R` | SAF-DS | IDW, puissance 0,5, rayon 50 km |
| `production_CHELSA_bilineaire.R` | CHE-C | bilinéaire (reprojection WGS84 → L93) |
| `production_EOBS_bilineaire.R` | EOB-DS | bilinéaire |

Sur le projet d'origine, les sorties sont sous `PROJET/3-Donnees/5-DIGITALIS/` :
`4-DIGITALIS_daily_DS_SAFRAN_IDW`, `3-DIGITALIS_daily_DS_CHELSA`,
`5-DIGITALIS_daily_DS_EOBS_BCSD_bilinear` (nom historique : c'est la méthode Delta, pas du BCSD).
Méthode : [`methode_downscaling.md`](methode_downscaling.md).

## 03 · NetCDF annuels (WGS84)

Sorties dans `LOCAL_ROOT/ECE_data/<n-base>/<BASE>_<var>_<année>.nc`, lues en priorité par le module 04.

| Ordre | Script | Entrée | Sortie `ECE_data/` |
|---|---|---|---|
| 1 | `8a-EOBS_vers_NetCDF.R` | `PROJET/3-Donnees/3-E_OBS/2-1950_2024_EOBS_FR` | `1-EOBS_11km` |
| 2 | *(manquant, cf. ERRATA 16)* puis `8b-SAFRAN_reprojection_WGS84.R` | NetCDF SAFRAN journaliers déjà dans `2-SAFRAN_8km` | `2-SAFRAN_8km` (reprojeté sur place) |
| 3 | `8c-CHELSA_vers_NetCDF.R` | `PROJET/3-Donnees/2-CHELSA/2-1960_2026_CHELSA_FR/{pr,tasmax,tasmin}` | `3-CHELSA_1km` |
| 4 | `8d0-DIGI_EOBS_vers_NetCDF.R` puis `8d-DIGI_EOBS_reprojection_WGS84.R` | `PROJET/3-Donnees/5-DIGITALIS/5-DIGITALIS_daily_DS_EOBS_BCSD_bilinear` | `4-DIGI_EOBS_1km` |
| 5 | `8d-DIGI_SAF_vers_NetCDF.R` | `PROJET/3-Donnees/5-DIGITALIS/4-DIGITALIS_daily_DS_SAFRAN_IDW` | `5-DIGI_SAF_1km` |
| 6 | `8d-Conversion_DIGI_CHEL.R` | `PROJET/3-Donnees/5-DIGITALIS/3-DIGITALIS_daily_DS_CHELSA` | `6-DIGI_CHEL_1km` |

Garde-fous intégrés : masquage des jours aberrants CHELSA (fill 0 K, dépassement int16) dans `8c` ;
refus d'une année entièrement NaN dans les `8d` ; normalisation de l'axe temps.

## 04 · Indices ECE

1. `0-Install_packages_ECE.R` : une fois, installe les paquets pcic depuis `CLIMPACT_RACINE`.
2. Un script par base : `1-ECE_EOBS.R`, `2-ECE_SAFRAN.R`, `3-ECE_CHELSA.R`, `4-ECE_DIGI_EOBS.R`,
   `5-ECE_DIGI_CHELSA.R`, `6-ECE_DIGI_SAFRAN.R`. Chaque script enchaîne : fusion des NetCDF
   annuels, ETP de Turc, Climpact (TXx, TNn, SPEI mensuels), WG10P, HWN et CWN, agrégation saisonnière.
   - En une fois : `source("R/04_indices_ece/1-ECE_EOBS.R")`.
   - Par périodes parallèles (1979-1987, 1987-1996, 1996-2005, 2005-2014, 2014-2024) :
     `Rscript R/04_indices_ece/1-ECE_EOBS.R <période 1 à 5> <nb de périodes simultanées>`,
     puis `7-Merge_periodes_climpact.R` (poser `BASE_CODE`) et une dernière exécution complète
     qui agrège depuis `climpact_raw/`.
3. `11-ECE_POSTTRAITEMENT.R` : poser `BASE` (et au besoin `INDICES_PT`) avant `source()`.
   Bornes physiques (hors plage → NA), masque France, masque Corse, axe temps. Originaux
   copiés dans `_avant_posttraitement/`.

Sorties : `PROJET/5-Resultats/3-ECE/1-ECE_1979-2024/<n-base>/ECE_<BASE>_<INDICE>_<SAISON>.nc`,
46 couches annuelles (1979-2024). Définitions : [`indices_ece.md`](indices_ece.md).

Drapeaux utiles avant `source()` : `N_PARALLEL_ECE`, `FORCE_CLIMPACT`, `RECOMPUTE_PREC_ONLY`,
`SANDBOX_ANNEES` / `SANDBOX_OUT` / `SANDBOX_CROP_EXT` (test sur une période et une emprise réduites).

## 05 · Extraction IFN

| Ordre | Script | Rôle | Sortie |
|---|---|---|---|
| 1 | `1-Preparation_IFN.R` | 1re visite, tous arbres, format long placette × 8 essences, peuplement, pH | `PROJET/3-Donnees/6-IFN/IFN_placette.csv` |
| 2 | `3-Extraction_ECE_placettes.R` | 36 colonnes `<INDICE>_<BASE>` agrégées sur 10 ans | même fichier, colonnes ajoutées |
| 3 | `3c-Extraction_Moyennes_par_base.R` | 6 moyennes saisonnières par base (run ECE vs climat moyen) | même fichier |
| 4 | `3b-Extraction_Classique_SAFDS.R` | variables climatiques DIGITALIS « classiques » (run 0K) | même fichier |

Entrées : `dfCCRNv2` (arbres et placettes, dérivé des données brutes IGN), `BD_SIG/nutrition/France/2014/ph_ess2_L93.tif`,
indices post-traités. Détail : [`modele_mortalite.md`](modele_mortalite.md).

## 06 · Modèles

Le moteur `1-Modele_mortalite_optimise.R` ne se lance pas seul : une **session** pose les
drapeaux puis le source. Sessions des résultats du rapport :

| Session | Runs produits (`PROJET/5-Resultats/5-Modeles/standard/<RUN_TAG>`) |
|---|---|
| `0N2-Session_France_binaire_complet.R` | `Mortalite_2015-2023_Peuplement_n1000_binaire`, `Mortalite_2015-2023_r070_n1000_binaire` |
| `0M-Session_ECE_plus_Moyen_5bases_2015-2023_binaire.R` | `ECE_Moyen_5bases_2015-2023_binaire` |
| `0K-Session_Comparaison_Classique_DIGI_2015-2023_binaire.R` | `Comparaison_Classique_DIGI_2015-2023_binaire` (usage dans le rapport à confirmer) |

`0N2` source ensuite `3-Tableaux/7-…`, `2-Figures/8-…`, `20-…`, `22-…`, `9-…` et `3-Tableaux/19-…`.
Les trois sessions excluent CHE-C et partagent le même échantillon de placettes (v1.1).
Le moteur et les scripts de figures écrivent et lisent `standard/<RUN_TAG>` ; le mode de réponse
est porté par le suffixe `_binaire` (sur le projet d'origine, les runs avaient été rangés à la main
dans `standard/Binaire/` et `standard/Binomiale/`).

## 07 · Figures et tableaux

- R : `R/07_figures/` (Fig. 2, 8a, A1, A.2 ; `tableaux_performances.R` pour les Tableaux I et A.III).
- Python : `python/figures/` (Fig. 1, 6, 7, 8b, 9), variables d'environnement décrites dans `_commun.py`.

Détail : [`figures_rapport.md`](figures_rapport.md).

## Arborescence attendue des données

Les scripts reproduisent l'arborescence du projet **au moment des calculs**. Depuis, une partie
des sources a été rangée sous `3-Donnees/0-Brut/` : adapter le chemin ou créer un lien si besoin.

```
<ECE_NAS_ROOT>/
├── BD_SIG/
│   ├── climat/france/DIGITALIS_v3/{tmin,tmax}/          DIGITALIS v3 (module 02)
│   ├── climat/france/SAFRAN/journalier_1960_2024/       SIM2 quotidien (module 02)
│   ├── climat/france/SAFRAN/0_donnees_brutes/           forçages horaires (module 01)
│   └── nutrition/France/2014/ph_ess2_L93.tif            pH (module 05)
└── Projets/stage_JeremyG/                                = PROJET
    ├── 3-Donnees/
    │   ├── 2-CHELSA/2-1960_2026_CHELSA_FR/              aujourd'hui 0-Brut/2-CHELSA/
    │   ├── 3-E_OBS/2-1950_2024_EOBS_FR/                 aujourd'hui 0-Brut/3-E_OBS/
    │   ├── 5-DIGITALIS/                                 DIGITALIS v4 prec + sorties du module 02
    │   └── 6-IFN/{dfCCRNv2/, IFN_placette.csv}
    └── 5-Resultats/{3-ECE/, 5-Modeles/}
<ECE_LOCAL_ROOT>/                                         = LOCAL_ROOT
├── ECE_data/<n-base>/                                    module 03
└── ECE_merge/                                            fusions temporaires du module 04
```
