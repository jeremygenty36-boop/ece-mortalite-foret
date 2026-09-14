# Méthode de downscaling (méthode Delta)

Descente d'échelle statistique de bases climatiques journalières vers une grille
1 km Lambert 93, calée sur la climatologie mensuelle **DIGITALIS** (1 km).

> **Terminologie.** La correction employée est la **méthode Delta** (ratio pour la
> précipitation, delta additif pour la température). Certains noms de dossiers et
> de fichiers de sortie historiques portent la mention « BCSD » : c'est le **même**
> traitement : il n'y a **pas** de quantile mapping. Ces noms sont conservés tels
> quels pour compatibilité avec la chaîne de traitement aval.

## 1. Principe commun

Pour chaque **(année, mois, variable)** :

```
                 SOURCE brute (8-11 km)          DIGITALIS (1 km, mensuel)
                        │                                   │
             [A] statistique mensuelle                      │
          précip = somme · temp = moyenne                   │
                        │                                   │
             [B] passage à 1 km L93                          │
        IDW (SAFRAN) │ bilinéaire (E-OBS/CHELSA)             │
                        │                                   │
                        └──────────► [C] facteur mensuel ◄──┘
                                     précip : ratio  = DIGI / max(src_1km, 0,001)   → clamp [0,001 ; 5]
                                     temp   : delta  = DIGI − src_1km
                                              │
             SOURCE brute jour j (1 km) ─────►[D] application jour par jour
                                     précip : jour_j × ratio_m      (clamp ≥ 0)
                                     temp   : jour_j + delta_m
                                              │
                                     [E] masque France → écriture (TIF / NetCDF)
```

### Formules

Soit, pour un mois donné et une cellule 1 km, `src_1km(j)` la source interpolée à
1 km le jour `j`, et `DIGI` la valeur mensuelle DIGITALIS.

**Précipitation (multiplicatif)**, avec `src_m = Σ_j src_1km(j)` :

```
ratio   = clamp( DIGI / max(src_m, ε),  ε,  5 )        ε = 0,001
p(j)    = max( src_1km(j) × ratio,  0 )
```

La somme mensuelle est recalée sur DIGITALIS (`Σ_j p(j) = DIGI` tant que le ratio
n'est pas borné) et les jours secs sont préservés.

**Température tmin/tmax (additif)**, avec `src_m = moyenne_j src_1km(j)` :

```
delta   = DIGI − src_m
t(j)    = src_1km(j) + delta
```

La moyenne mensuelle est calée sur DIGITALIS (`moyenne_j t(j) = DIGI`) et la
variabilité journalière est préservée.

Le clamp `[0,001 ; 5]` évite les ratios explosifs là où la source est ~0. Aucune renormalisation
n'est appliquée ensuite : dans les mailles bornées, le cumul mensuel n'est pas exactement celui de
DIGITALIS (pluie sous-estimée si DIGITALIS dépasse 5 fois la source, ou si la source est sèche).
Diagnostic sur SAFRAN 2015-2017 : 0,08 % des mailles par mois en moyenne, au plus 1,5 % (octobre
2017), dans le quart sud-est et les Pyrénées-Atlantiques. Non diagnostiqué pour E-OBS et CHELSA.
Les valeurs manquantes restent manquantes (NaN, jamais 0).

## 2. Les trois bases

| Base | Source | Résolution / CRS natif | Interpolation → 1 km | Sortie |
|------|--------|------------------------|----------------------|--------|
| **SAFRAN** | SIM2 (points 8 km) | 8 km, Lambert II (EPSG:27572) | **IDW** p = 0,5 · r = 50 km | TIF journaliers |
| **E-OBS** | v31.0e (grille) | 0,1° (~11 km), WGS84 | **bilinéaire** | NetCDF annuel |
| **CHELSA** | v2.1 (grille) | 1 km, WGS84 | **bilinéaire** (reproj. WGS84 → L93) | TIF journaliers |

- **SAFRAN** : précip = `PRELIQ_Q + PRENEI_Q` ; températures `TINF_H_Q` / `TSUP_H_Q`.
  Les points SIM2 (coordonnées `LAMBX/LAMBY` × 100, Lambert II) sont interpolés par
  IDW sur la grille 1 km. Paramètres IDW : puissance 0,5, rayon 50 km (optimisés par
  validation croisée leave-one-out sur septembre 2014).
- **E-OBS** : variables `rr` / `tn` / `tx`, bilinéaire de 0,1° WGS84 vers 1 km L93.
  Écriture NetCDF **atomique** (`.tmp.nc` → renommage) : un crash ne laisse pas de
  fichier corrompu.
- **CHELSA** : déjà à 1 km mais en WGS84 : reprojection L93 puis rééchantillonnage.
  Conversion Kelvin → °C pour la température. Les **jours aberrants** (remplissage
  0 K, dépassement int16 > 1000 K) sont traités comme manquants et exclus de la
  correction mensuelle (sinon le delta amplifierait l'aberration).

## 3. Sources et cible

| Rôle | Jeu | Résolution | Unité brute | Chemin (config) |
|------|-----|-----------|-------------|-----------------|
| Cible (réf.) | DIGITALIS prec | 1 km L93 | 0,1 mm (× 0,1) | `DIGI_PREC` |
| Cible (réf.) | DIGITALIS tmin/tmax | 1 km L93 | 0,1 °C (× 0,1) | `DIGI_TMIN` / `DIGI_TMAX` |
| Source | SAFRAN SIM2 | 8 km | mm, °C | `SAFRAN_CSV_DIR` |
| Source | E-OBS v31.0e | 0,1° | mm, °C | `EOBS_DIR` |
| Source | CHELSA v2.1 | 1 km | mm, K | `CHELSA_PR/TASMIN/TASMAX` |

DIGITALIS sert de **référence** « vérité terrain » à la correction ; elle n'est pas
produite ici (cf. [sources_donnees.md](sources_donnees.md) et le README).

## 4. Correspondance R ↔ Python

| Étape | R (`r/`) | Python (`python/`) |
|-------|----------|--------------------|
| Chemins | `config_chemins.R` | `config_chemins.py` |
| SAFRAN (IDW) | `production_SAFRAN_IDW.R` | `pipeline.downscale_mois_points` + `interpolation.idw` |
| E-OBS / CHELSA (bilinéaire) | `production_EOBS_bilineaire.R`, `production_CHELSA_bilineaire.R` | `pipeline.downscale_mois_grille` + `interpolation.bilineaire` |
| Cœur (ratio/delta, clamp) | intégré aux scripts | `methode_delta.py` |

La version Python vérifie la conservation (somme/moyenne mensuelle = DIGITALIS) par
des tests unitaires (`python/downscaling/tests/`).
