# Origine des données

Ce dépôt contient **le code**, pas les données (volumineuses et sous licences
propres). Voici comment obtenir chaque jeu. Le module 02 (downscaling) lit ses chemins dans
`R/02_downscaling/config_chemins.R` ; les autres modules dans `config/chemins.R`
(arborescence décrite dans [`pipeline.md`](pipeline.md)).

> **Le code ne redistribue aucune donnée.** Respecter les licences et les
> obligations de citation de chaque fournisseur.

## Vue d'ensemble

| Jeu | Rôle | Résolution | Couverture | Accès |
|-----|------|-----------|------------|-------|
| **DIGITALIS** | référence (cible) | 1 km, mensuel | France | non public, contacter les auteurs |
| **SAFRAN / SIM2** | source | 8 km, journalier | France | Météo-France (ouvert) |
| **E-OBS** | source | 0,1°, journalier | Europe | ECA&D / Copernicus |
| **CHELSA v2.1** | source | 1 km, journalier | global | chelsa-climate.org |

## DIGITALIS (référence)

Climatologie mensuelle 1 km de la France (précipitation, tmin, tmax), **œuvre de
Christian Piedallu (INRAE)**. Utilisée ici comme **référence** vers laquelle la
méthode Delta recale les moyennes mensuelles. **Non librement redistribuable** :
contacter les auteurs pour les conditions d'usage.

- Précipitation : encodée en **0,1 mm** (les scripts divisent par 10).
- tmin / tmax : encodées en **0,1 °C** (division par 10).
- Fichiers attendus : `{prec,tmin,tmax}_ANNEE_MOIS.tif` (grille 1 km L93).

## SAFRAN / SIM2 (Météo-France)

Réanalyse journalière à 8 km sur la France, distribuée en CSV décennaux SIM2.

- Accès : portail données ouvertes de Météo-France (`meteo.data.gouv.fr`), jeu
  « SIM2 » quotidien.
- Fichiers attendus : `QUOT_SIM2_YYYY-YYYY.csv[.gz]`.
- Colonnes utilisées : `LAMBX`, `LAMBY` (Lambert II, × 100), `PRELIQ_Q`, `PRENEI_Q`
  (précip = somme), `TINF_H_Q` (tmin), `TSUP_H_Q` (tmax).

## E-OBS (ECA&D / Copernicus)

Grille journalière européenne à 0,1° (~11 km), issue de l'interpolation de stations.

- Accès : ECA&D, page de téléchargement « E-OBS » (`ecad.eu`), ou Copernicus C3S.
- Version employée : **v31.0e**. Fichiers NetCDF WGS84.
- Fichiers attendus : `rr_ens_mean_0.1deg_reg_v31.0e.nc` (précip), `tn_…` (tmin),
  `tx_…` (tmax).
- Citation : Cornes et al. (2018), *An Ensemble Version of the E-OBS Temperature and
  Precipitation Data Sets*, JGR Atmospheres.

## CHELSA v2.1 (Karger et al.)

Climatologie/serie journalière haute résolution (~1 km), globale.

- Accès : `chelsa-climate.org` (v2.1, produits journaliers).
- Variables : `pr` (mm/jour), `tasmin`, `tasmax` (**Kelvin** → °C par −273,15).
- Fichiers attendus : `CHELSA_<var>_DD_MM_YYYY_V.2.1.tif` (WGS84).
- Citation : Karger et al. (2017) et Karger et al. (2021) pour CHELSA V2.1 journalier. Ne pas citer CHELSA-W5E5 ni CHELSA-TraCE21k, qui sont d'autres produits.

## Organisation attendue par le module 02 (via `DIGI_ROOT`)

Avec `DIGI_ROOT` pointant sur votre racine de données, l'arborescence par défaut
de `config_chemins` est :

```
$DIGI_ROOT/
├── DIGITALIS/{prec,tmin,tmax}/       # {prec,tmin,tmax}_ANNEE_MOIS.tif  (1 km L93)
├── SAFRAN/                            # QUOT_SIM2_YYYY-YYYY.csv[.gz]
├── E-OBS/                             # rr/tn/tx_ens_mean_0.1deg_reg_v31.0e.nc
├── CHELSA/{pr,tasmin,tasmax}/         # CHELSA_<var>_DD_MM_YYYY_V.2.1.tif
├── masque/FRANCE.shp                  # masque France métropolitaine (L93)
└── gabarit_1km/                       # >= 1 TIF 1 km L93 (grille cible de référence)
```

Adapter les sous-chemins dans `config_chemins.R` / `config_chemins.py` si votre
organisation diffère. Les liens et intitulés d'accès ci-dessus sont indicatifs :
vérifier la page officielle de chaque fournisseur (URLs et versions évoluent).

## Autres données du pipeline complet

### Inventaire forestier (IGN)

- Données brutes de l'inventaire forestier national de l'IGN :
  <https://inventaire-forestier.ign.fr/dataifn/> (données brutes, téléchargées le 12/02/2025).
- Le projet part de `dfArbresCCRN.csv` et `dfPlacettesCCRN.csv` (dossier `dfCCRNv2`), versions
  filtrées et enrichies des données brutes (campagnes 2009-2023, visites 1 et 2, essence,
  GRECO, statut dominant ou dominé, surface terrière, pureté du peuplement), préparées en amont
  du stage. Leur `LISEZ_MOI.txt` détaille chaque transformation.
- Dates de relevé : `Synthese_placettes_all_GMN.csv`.
- Le jeu d'analyse `IFN_placette.csv` (545 Mo) n'est pas versionné.

### pH du sol

Raster `ph_ess2_L93.tif` (France, 1 km, Lambert-93, 2014), `BD_SIG/nutrition/France/2014/`
sur le stockage du laboratoire. Accès à demander aux encadrants.

### Limites administratives (GADM)

`France_GADM_L0.gpkg`, niveau 0, téléchargé par `R/01_sources/0-Telecharger_limites_France.R`
(paquet `geodata`). Licence GADM : usage académique libre, redistribution interdite ; le fichier
n'est donc pas versionné.

### Climpact

Voir [`../third_party/climpact/README.md`](../third_party/climpact/README.md).
