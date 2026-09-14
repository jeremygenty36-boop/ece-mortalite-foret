# Indices d'événements climatiques extrêmes (ECE)

Définitions **telles que codées en v1.1** dans `R/04_indices_ece/` (logique identique dans les
6 scripts). Références de ligne : `1-ECE_EOBS.R` de la v1.0 (tag `v1.0-rapport`). Écarts et
corrections : [`ERRATA.md`](../ERRATA.md).

## Bases

| Code | Base | Résolution | Production |
|---|---|---|---|
| EOB-10 (`EOBS`) | E-OBS v31.0e | ~11 km | native |
| SAF-8 (`SAFRAN`) | SAFRAN | 8 km | native |
| CHE-1 (`CHELSA`) | CHELSA V2.1 journalier (forçage ERA5) | 1 km | native |
| EOB-DS (`DIGI_EOBS`) | E-OBS × DIGITALIS | 1 km | méthode Delta, bilinéaire |
| SAF-DS (`DIGI_SAF`) | SAFRAN × DIGITALIS | 1 km | méthode Delta, IDW |
| CHE-C (`DIGI_CHEL`) | CHELSA × DIGITALIS | 1 km | méthode Delta ; **exclue des modèles et figures** |

Période calculée : 1979-2024. **Période de référence** (percentiles, Q10, SPEI) : **1979-1989**
(`BASE_START`, `BASE_END`, l. 63-64).

## Les 6 indices

| Indice | Stress | Calcul journalier ou mensuel | Saison | Valeur annuelle | Code |
|---|---|---|---|---|---|
| **TXx** | chaleur, intensité | max mensuel de Tmax (Climpact) | MAR-NOV | **max** des mois | l. 876 |
| **TNn** | froid, intensité | min mensuel de Tmin (Climpact) | SEP(an-1) à MAI(an) | **min** des mois | l. 442, 882 |
| **SPEI6** | sécheresse, intensité | SPEI à 6 mois (Climpact modifié : échelle 6 seule) | MAR-AOÛT | **min** des mois (v1.0 : moyenne, ERRATA 1) | l. 889 |
| **WG10P** | déficit hydrique, fréquence | % de jours où P − ETP < Q10 du même mois calendaire | MAR-AOÛT | **moyenne** des % mensuels | l. 503-530, 1086 |
| **HWN** | chaleur, fréquence | nombre de vagues : ≥ 3 jours consécutifs Tmax > q90 | MAI-SEP | **somme** des épisodes | l. 918-925 |
| **CWN** | froid, fréquence | nombre de vagues : ≥ 3 jours consécutifs Tmin < q10 | SEP(an-1) à MAI(an) | **somme** des épisodes | l. 918-925 |

### Détails

- **Hiver à cheval** (TNn, CWN) : l'année Y regroupe septembre-décembre de Y-1 et janvier-mai de Y.
- **Seuils HWN / CWN** : percentile 90 (Tmax) ou 10 (Tmin) par pixel et par jour de l'année, calculé
  sur 1979-1989 avec une fenêtre glissante de ± 7 jours. Un épisode est compté une fois, le jour où
  la série de jours consécutifs atteint 3 ; une rupture de dates remet le compteur à zéro.
  Indices repris de Carletti et al. (2026), qui utilisent la période de référence 1961-1990 et dont le
  tableau 1 définit les vagues comme « plus de 3 jours consécutifs » ; le code compte les épisodes
  d'**au moins 3 jours**.
- **WG10P** : Q10 de (P − ETP) par pixel et par mois calendaire sur 1979-1989 ; pourcentage calculé
  sur les jours valides ; NA (et non 0) si aucun jour valide.
- **ETP de Turc**, identique pour les 6 bases (l. 354-358) :
  `ETP = 0,013 × Tm / (Tm + 15) × (Rs + 50)` si Tm > 0, sinon 0 (mm/j) ;
  `Rs = 0,16 × √(Tmax − Tmin) × Ra × 23,884` (cal/cm²/j) ;
  Ra (rayonnement extraterrestre) calculé à la **latitude moyenne de la grille** (l. 340, ERRATA 2).
- **Variables compagnes Climpact** `day_of_*` exclues à la lecture (corrige un artefact en « peigne » sur TXx).
- **Traçabilité (v1.1)** : chaque indice agrégé porte l'attribut NetCDF global `agregation_annuelle`
  (`max`, `min`, ...). Un SPEI6 portant un autre opérateur, ou sans attribut, est recalculé.

## Post-traitement (`11-ECE_POSTTRAITEMENT.R`)

Valeurs hors bornes physiques mises à NA (décision du 28/05/2026) :

| TXx | TNn | SPEI6 | WG10P | HWN | CWN |
|---|---|---|---|---|---|
| [−10 ; 55] °C | [−60 ; 20] °C | [−5 ; 5] | [0 ; 100] % | [0 ; 366] | [0 ; 366] |

Puis masque France (GADM), masque Corse (lon > 8,5 et lat < 43,1) et réécriture de l'axe temps
(une couche par an, datée du 15 du dernier mois de la saison). NA reste NA : aucune valeur
aberrante n'est écrêtée, seules les valeurs physiquement impossibles sont retirées.

## Agrégation aux placettes (`R/05_extraction_ifn/3-Extraction_ECE_placettes.R`)

Fenêtre de **10 ans** se terminant l'année du relevé (`N_ANS`, l. 38). Si le relevé précède la
mi-saison de l'indice, la fenêtre est décalée d'un an vers le passé (toujours 10 ans, l. 167-168).

| TXx | TNn | SPEI6 | WG10P | HWN | CWN |
|---|---|---|---|---|---|
| max | min | min | moyenne | somme | somme |

L'extrême est calculé **par placette** sur sa fenêtre ; une fenêtre entièrement NA donne NA
(l. 176), une fenêtre partiellement NA est agrégée sur les années valides.
Colonnes produites : `<INDICE>_<BASE>` avec BASE ∈ {EOB10, SAF8, CHE1, EOBDS, SAFDS, CHEDS}.

## Référence

Carletti H., Caloin M., Joetzjer E., Marçais B., Gégout J.-C., Piedallu C. (2026). The long-term decrease in extreme cold events is a key actor in the increased mortality of Norway spruce and silver fir. *Agricultural and Forest Meteorology*, 111151. https://doi.org/10.1016/j.agrformet.2026.111151
