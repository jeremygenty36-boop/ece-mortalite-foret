# Origine des données

Ce dépôt contient **le code**, pas les données (volumineuses et sous licences
propres). Voici comment obtenir chaque jeu et l'organiser pour `config_chemins`.

> **Le code ne redistribue aucune donnée.** Respecter les licences et les
> obligations de citation de chaque fournisseur.

## Vue d'ensemble

| Jeu | Rôle | Résolution | Couverture | Accès |
|-----|------|-----------|------------|-------|
| **DIGITALIS** | référence (cible) | 1 km, mensuel | France | non public — auteurs |
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

- Accès : ECA&D — page de téléchargement « E-OBS » (`ecad.eu`), ou Copernicus C3S.
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
- Citation : Karger et al. (2021), CHELSA v2.1.

## Organisation attendue (via `DIGI_ROOT`)

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
