# Journal des versions

## Depuis v1.1 (documentation)

- `ERRATA.md` : section « Portée sur les conclusions du rapport » (fréquence de sélection du SPEI6,
  origine des produits SAFRAN, portée du test entre bases, écarts sans effet attendu).
- `docs/methode_downscaling.md` : absence de renormalisation et diagnostic des bornes du facteur de pluie.

## v1.1 (version publiée)

Corrections des écarts relevés dans [`ERRATA.md`](ERRATA.md). **Le code v1.1 n'a pas été
réexécuté sur les données complètes** (serveur de calcul plus accessible) : les résultats du
rapport de stage correspondent à la v1.0. Chaque correction a été testée localement sur des
données synthétiques ou sur un extrait des données réelles (voir `tests/`).

### Changements qui modifient les résultats (relance nécessaire)

- **SPEI6** : valeur annuelle = **minimum** des SPEI-6 mensuels de mars à août (v1.0 : moyenne).
  L'opérateur est écrit dans l'attribut NetCDF `agregation_annuelle` ; un SPEI6 existant agrégé
  autrement est mis à la corbeille puis recalculé, et le post-traitement ne restaure plus une
  sauvegarde agrégée avec un autre opérateur (en v1.0 il aurait réécrit l'ancienne moyenne par-dessus).
  Scripts : `R/04_indices_ece/1…6-ECE_*.R`, `11-ECE_POSTTRAITEMENT.R`.
- **Échantillon commun** (`ECHANTILLON_COMMUN = TRUE`) : pour une essence, toutes les bases sont
  modélisées sur les mêmes placettes (lignes complètes sur les ECE des 5 bases). Sur les données
  du rapport : 34 159 lignes au lieu de 34 255 à 34 173 selon la base.
- **Graine par essence** : `42 + 100 × rang de l'essence`, identique pour toutes les bases et
  indépendante des filtres. Avec l'échantillon commun, les 1 000 partitions 70/30 sont les mêmes
  pour les 5 bases (comparaison appariée).
- **Sessions** : runs nommés `2015-2023` (`CAMPAGNE_MAX = 2023`), CHE-C exclue explicitement,
  même échantillon pour les runs peuplement, ECE, ECE + moyennes et climat DIGITALIS.

### Ajouts

- `R/07_figures/tableaux_performances.R` : Tableau I et Tableau A.III calculés depuis les
  synthèses des runs (étiquettes corrigées). Validé : redonne les valeurs du rapport à partir des
  sorties v1.0.
- `python/figures/` : Fig. 6, 7, 8b et 9 recréées (scripts d'origine perdus). Validées sur les
  données v1.0 : écarts-types, R², IR et cellules affichés identiques aux PDF du rapport.
- `tests/test_posttraitement_spei6.R`, `tests/test_moteur_echantillon.R`.

### Publication

- Licences : code sous MIT (`LICENSE`), documentation sous CC-BY 4.0 (`LICENSE-docs`), fichiers
  Climpact modifiés sous GPL-3 (`third_party/climpact/LICENSE`).
- Commentaires internes retirés (identifiants d'utilisateurs du serveur de calcul, chemins personnels).
- `.gitattributes` : fins de ligne et encodages des scripts conservés tels quels.

### Non modifié

- Méthode Delta, interpolations, définitions de TXx, TNn, WG10P, HWN et CWN, ETP de Turc
  (latitude unique documentée), extraction aux placettes, sélection de variables et calcul des IR.

## v1.0-rapport

Code tel qu'exécuté pour le rapport de stage (juillet 2026), importé à l'identique depuis
l'arborescence du projet ; seules les racines des chemins ont été rendues configurables
(`config/chemins.R`). Tag git `v1.0-rapport`.
