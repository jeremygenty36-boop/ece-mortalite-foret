# Jeu d'analyse et modèle de mortalité

Références de ligne : `R/05_extraction_ifn/1-Preparation_IFN.R` et
`R/06_modele/1-Modele_mortalite_optimise.R`. Écarts connus : [`ERRATA.md`](../ERRATA.md).

## Jeu d'analyse `IFN_placette.csv`

- **Source** : `dfArbresCCRN.csv` et `dfPlacettesCCRN.csv` (dossier `dfCCRNv2`), dérivés des
  données brutes de l'inventaire forestier de l'IGN (campagnes 2009-2023) ; dates de relevé
  depuis `Synthese_placettes_all_GMN.csv`.
- **1re visite seulement**, dominants et dominés (`1-Preparation_IFN.R:77`). Arbre mort :
  `veget_gen` = 5 (mort sur pied au relevé, l. 92).
- **Format long** : une ligne par placette × essence focus (8 lignes par placette), `presence` = 1
  si l'essence a au moins un arbre. Placettes à surface terrière nulle exclues.
- **8 essences** : QURO (*Quercus robur*), QUPE (*Q. petraea*), FASY (*Fagus sylvatica*),
  PISY (*Pinus sylvestris*), PINI (*P. nigra* subsp. *nigra*), ABAL (*Abies alba*),
  PIAB (*Picea abies*), BEPE (*Betula pendula*).
- **Variables** : peuplement (`G_ha_tot`, `Gini`, `c13_moy_sp`, `prop_G`), pH du sol
  (`ph_ess2_L93.tif`), 36 colonnes ECE, moyennes saisonnières par base, `mort_bin`.
  `prop_G` et `c13_moy_sp` portent sur l'essence, `Gini` sur le peuplement entier.

### Effectifs (2015-2023, hors Corse)

| | Valeur |
|---|---|
| Placettes | 31 600 |
| Placettes portant au moins une essence focus | 21 989 (dont 9 392 avec au moins deux) |
| **Observations placette × essence** (lignes `presence = 1`) | **34 255** |
| QURO / QUPE / FASY / PISY / BEPE / ABAL / PIAB / PINI | 9 091 / 6 848 / 6 446 / 3 861 / 2 923 / 2 265 / 2 173 / 648 |

Recalculés sur `IFN_placette.csv` et identiques à la somme de `n_plac` du run peuplement.

## Modèle

Un modèle par **essence × base** (8 × 5 dans le rapport). Réponse selon `MODE_REPONSE` :

| Mode | Réponse | Mesure | Utilisé dans le rapport |
|---|---|---|---|
| `binaire` | `mort_bin` : au moins un arbre de l'essence mort | occurrence | **oui** |
| `binomial` (défaut du moteur) | `cbind(n_mort_sp, n_tiges − n_mort_sp)` | intensité | non |

Étapes, pour chaque essence × base :

1. **Filtres** : Corse exclue par département 2A/2B (l. 156), campagnes `CAMPAGNE_MIN`-`CAMPAGNE_MAX`,
   `presence == 1`, lignes complètes sur les variables de la base (`na.omit`, l. 483, ERRATA 8),
   au moins 50 placettes et 10 événements.
2. **1 000 itérations** (`N_ITER`). À chaque itération, tirage **sans remise** de 70 % des
   placettes pour la calibration, 30 % pour la validation (l. 58, 332). Graine : l. 316 (ERRATA 9).
3. **Modèle de départ** : GLM binomial, **lien cloglog**, avec les 5 variables fixes et leur terme
   quadratique (`v + I(v²)`, l. 117). Les variables fixes restent toujours dans le modèle.
4. **Sélection ascendante des ECE** : à chaque pas, le candidat (avec son terme quadratique) de BIC
   le plus bas est ajouté s'il est significatif (test du χ², **p ≤ 0,01**) et **si le BIC diminue**
   (l. 352-356). Après chaque ajout, les candidats corrélés à **|r| > 0,70** (Pearson) sont écartés (l. 227).
5. **Évaluation sur la validation** : AUC (trapèzes), prAUC, sensibilité, spécificité, TSS, kappa et
   succès au seuil de Youden. En binomial, la probabilité d'au moins un mort est
   `1 − (1 − p)^n_tiges` (l. 374).
6. **Importance relative (IR)** d'une variable : perte de déviance quand on la retire du modèle final,
   × 100 / déviance nulle (l. 259) ; moyenne sur les itérations (0 si non sélectionnée), puis
   **normalisée à 100 %** par essence × base (l. 609).
7. **Sens et forme de l'effet** : différence de probabilité prédite entre les quantiles 10 et 90
   (autres variables à leur moyenne) ; forme `+`, `-`, `U` ou `n` sur une grille de percentiles.

## Sorties d'un run

`PROJET/5-Resultats/5-Modeles/standard/<RUN_TAG>/`

| Dossier | Contenu |
|---|---|
| `1-Iterations/Resultats_<ESP>_<BASE>.csv` | 1 ligne par itération : variables retenues, BIC, D², 7 indicateurs |
| `2-Syntheses/Synthese_globale.csv` | moyennes et écarts-types par essence × base, `n_plac`, `n_morts` |
| `2-Syntheses/RI_par_variable.csv` | IR normalisée, IR brute, sens, forme par variable |
| `3-Predictions/` | prédictions de la dernière itération |

## Runs cités dans le rapport

| Run | Contenu |
|---|---|
| `Mortalite_2015-2024_Peuplement_n1000_binaire` | peuplement et sol seuls (AUC moyenne 0,753) |
| `Mortalite_2015-2024_r070_n1000_binaire` | peuplement + 6 ECE, 5 bases (AUC moyenne 0,761) |
| `ECE_Moyen_5bases_2015-2023_binaire` | 6 ECE + 6 moyennes saisonnières par base (Fig. A.2) |
