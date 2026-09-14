# Climpact modifié pour le projet

Les scripts `R/04_indices_ece/1…6-ECE_*.R` chargent directement le code d'une copie locale
de Climpact (`modules/*.R` et `server/pcic_packages/climdex.pcic.ncdf/R/ncdf.R`) et l'appellent
avec `root.dir = CLIMPACT_DIR`. Cette copie a été **modifiée** pendant le stage.

## Version de base

Climpact **3.3.2** (entrée du `CHANGE_LOG` datée du 1er décembre 2025), dépôt officiel :
<https://github.com/ARCCSS-extremes/climpact>. Paquets pcic embarqués dans la copie :
`climdex.pcic` 1.1-11, `PCICt` 0.5-4.4, `ncdf4.helpers` 0.3-3 et 0.3-7.

## Fichiers modifiés (fournis dans `modifies/`)

| Fichier | Modification (20/05/2026) |
|---|---|
| `server/climpact.etsci-functions.r` | calcul de SPEI à l'échelle de 6 mois uniquement (commentaire `PATCH 2026-05-20`, l. 507) |
| `server/pcic_packages/climdex.pcic.ncdf/R/ncdf.R` | compteur de progression de la branche parallèle (l. 1941 et 1954) ; appel `base::t` explicite (l. 709) |

Seuls ces deux fichiers portent des marques de modification. La copie a été extraite le
23/03/2026 : une comparaison fichier par fichier avec la version officielle 3.3.2 reste à faire
pour exclure d'autres changements non commentés.

## Installation

1. Télécharger Climpact 3.3.2 et le décompresser dans `third_party/climpact/climpact-master/`
   (ou ailleurs, en définissant `ECE_CLIMPACT_DIR`).
2. Copier le contenu de `modifies/` par-dessus, en respectant l'arborescence.
3. Dans R, depuis la racine du dépôt : `source("R/04_indices_ece/0-Install_packages_ECE.R")`.

`third_party/climpact/climpact-master/` est ignoré par git.

## Licence

Climpact est distribué sous **GNU GPL v3**. Les fichiers de `modifies/` sont des versions
modifiées de fichiers de Climpact et restent sous GPL v3 ; les modifications sont décrites
ci-dessus, conformément à la licence. Texte de la licence :
<https://www.gnu.org/licenses/gpl-3.0.html>.
