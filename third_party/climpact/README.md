# Climpact modifié pour le projet

Les scripts `R/04_indices_ece/1…6-ECE_*.R` chargent directement le code d'une copie locale
de Climpact (tous les `modules/*.R` et `server/pcic_packages/climdex.pcic.ncdf/R/ncdf.R`) et
l'appellent avec `root.dir = CLIMPACT_DIR`. Cette copie a été **modifiée** pendant le stage.

## Version de base

Climpact **3.3.2** (1er décembre 2025), commit officiel
[`83b4721`](https://github.com/ARCCSS-extremes/climpact/commit/83b472172a45ac745fa5762b89b6d2755cdd6eb3)
du dépôt <https://github.com/ARCCSS-extremes/climpact>. La copie du projet a été comparée
fichier par fichier à ce commit le 14/09/2026 : 10 fichiers diffèrent, et la copie contient en
plus trois archives de paquets pcic (`PCICt_0.5-4.4.tar.gz`, `ncdf4.helpers_0.3-7.tar.gz`,
`climdex.pcic_1.1-11_win-binary.zip`).

## Modifications (dans `modifies/` et `climpact-3.3.2_modifications_projet.patch`)

| Fichier | Nature | Effet |
|---|---|---|
| `server/climpact.etsci-functions.r` | calcul | SPEI calculé à l'échelle de 6 mois uniquement (les échelles 3 et 12 restent NA), le pipeline n'utilisant que SPEI-6 |
| `server/pcic_packages/climdex.pcic.ncdf/R/ncdf.R` | calcul | voir le détail ci-dessous |
| `models/ncdfInputParams.R` | calcul | liste d'indices à calculer nettoyée des espaces (`trimws`) |
| `services/calculate_indices.R` | calcul | option `selected_indices` : ne calculer que les indices choisis |
| `modules/griddedStep1.R`, `modules/singleStationStep3.R` | interface | sélection des indices par cases à cocher |
| `modules/griddedStep1UI.R`, `modules/singleStationStep3UI.R` | interface | libellés et boutons de sélection (en français) |
| `app.R` | interface | choix de fichiers sans `tcltk` hors Windows |
| `climpact.Rproj` | environnement | fichier de projet RStudio simplifié |

### Détail de `ncdf.R`

1. **Axes temps** : les dates des fichiers d'entrée sont comparées en chaînes de caractères. Si
   les séries ont des longueurs différentes mais un début commun, elles sont **tronquées à la plus
   courte** avec un avertissement (la version officielle s'arrête sur une erreur).
2. **Unités** : précipitations en `mm` (et variantes) traitées comme `kg m-2 d-1` ; **températures
   forcées en `degrees_C` quelle que soit l'unité déclarée**, en supposant la conversion depuis les
   Kelvin déjà faite en amont (cas des NetCDF produits par `R/03_netcdf_annuels`).
3. **Projection** absente (fichiers écrits par terra) : grille traitée comme lat/lon.
4. **Conversion d'unités** : dimensions du tableau restaurées après `udunits2::ud.convert`.
5. **Parallélisme** : chargement explicite des paquets et de `root.dir` dans les workers,
   ouverture des NetCDF sans `readunlim = FALSE`, fermeture garantie des fichiers et du cluster,
   appel `base::t` explicite, compteurs de progression ; la branche séquentielle traite les tranches
   en ordre inverse (chaque tranche est écrite indépendamment).

Le calcul des indices eux-mêmes (fonctions `climdex.pcic`) n'est pas modifié. Les points 1 et 2
peuvent en revanche changer les données lues si les fichiers d'entrée ne sont pas conformes :
vérifier la longueur des séries (avertissement « Axes temporels tronqués ») et l'unité des
températures avant un calcul.

## Installation

1. Télécharger le commit 3.3.2 :
   <https://github.com/ARCCSS-extremes/climpact/archive/83b472172a45ac745fa5762b89b6d2755cdd6eb3.zip>
   et le décompresser en `third_party/climpact/climpact-master/` (ou ailleurs, en définissant
   `ECE_CLIMPACT_DIR`).
2. Appliquer les modifications, au choix :
   - `cd third_party/climpact/climpact-master && patch -p1 < ../climpact-3.3.2_modifications_projet.patch`
   - ou copier le contenu de `modifies/` par-dessus, en respectant l'arborescence.
3. Dans R, depuis la racine du dépôt : `source("R/04_indices_ece/0-Install_packages_ECE.R")`.

`third_party/climpact/climpact-master/` est ignoré par git.

## Licence

Climpact est distribué sous **GNU GPL v3**. Les fichiers de `modifies/` et le patch sont des
versions modifiées de fichiers de Climpact et restent sous GPL v3 ; les modifications sont
décrites ci-dessus, conformément à la licence. Texte de la licence :
<https://www.gnu.org/licenses/gpl-3.0.html>.
