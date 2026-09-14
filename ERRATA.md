# Errata

Écarts relevés le 14/09/2026 entre l'intention méthodologique et le code **tel qu'exécuté pour le
rapport de stage** (tag `v1.0-rapport`), et leur traitement dans la v1.1. Les résultats du rapport
correspondent à la v1.0 ; la v1.1 n'a pas été réexécutée sur les données complètes.

Statut : **corrigé** (code modifié en v1.1) · **documenté** (pas de changement de code) ·
**ouvert** (non résolu). Type : **[calcul]** change des valeurs · **[doc]** formulation ·
**[chaîne]** maillon manquant ou fragile.

| N° | Type | Écart | Statut v1.1 |
|---|---|---|---|
| 1 | calcul | SPEI6 annuel = moyenne des mois MAR-AOÛT | **corrigé** |
| 2 | doc | Ra de l'ETP à latitude unique | documenté |
| 3 | chaîne | `0-Recombiner_saisons_ECE.R` : TNn en année civile | documenté (script non publié) ; vérification des sorties v1.0 impossible |
| 4 | chaîne | Climpact modifié localement | **corrigé** : 10 fichiers et patch dans `third_party/climpact` |
| 5 | doc | drapeau `RENORM_MENS_PREC` sans effet | documenté (absent du dépôt) |
| 6 | doc | « 34 255 placettes » dans les légendes des Fig. 6 et 7 | documenté |
| 7 | doc | deux critères d'exclusion de la Corse | documenté (même sélection) |
| 8 | calcul | effectifs différents entre bases | **corrigé** : échantillon commun |
| 9 | calcul | graine différente d'une base à l'autre | **corrigé** : graine par essence |
| 10 | doc | « 1 000 bootstraps » | documenté |
| 11 | doc | runs nommés « 2015-2024 » | **corrigé** : runs 2015-2023 |
| 12 | doc | Tableau A.III (a) mal étiqueté | **corrigé** : tableaux calculés |
| 13 | doc | Tableau I, ligne « Différence max » | **corrigé** : tableaux calculés |
| 14 | doc | citation CHELSA « Karger et al. 2023 » | documenté |
| 15 | chaîne | scripts de figures perdus | **corrigé** pour Fig. 6, 7, 8b, 9 ; **ouvert** pour Fig. 3, 4, 5, A.3, A.4 (données plus accessibles) |
| 16 | chaîne | production des NetCDF journaliers SAF-8 absente | **ouvert** |
| 17 | chaîne | sous-chemins de données historiques | documenté |

## Détail

### Indices ECE

1. **SPEI6 annuel = moyenne, et non minimum.** v1.0 : moyenne des 6 SPEI-6 mensuels de mars à
   août (`agreger(f_spei, "SPEI6", 3:8, "mean", ...)`, identique dans les 6 scripts), puis minimum
   de ces moyennes sur 10 ans à la placette. Non voulu.
   **v1.1** : minimum mensuel. L'opérateur est écrit dans l'attribut NetCDF `agregation_annuelle` ;
   un SPEI6 existant agrégé autrement part à la corbeille puis est recalculé, et le post-traitement
   n'écrase plus le nouveau calcul avec une ancienne sauvegarde (`tests/test_posttraitement_spei6.R`).
   Relance nécessaire : indices SPEI6, extraction, modèles, figures et tableaux.

2. **Rayonnement extraterrestre à latitude unique.** Dans l'ETP de Turc, Ra est calculé avec la
   latitude moyenne de la grille pour toute la France (`R/04_indices_ece/1-ECE_EOBS.R`, fonction
   `calc_etp`). Simplification conservée ; l'indice WG10P étant relatif à un Q10 par pixel, l'effet
   porte surtout sur les valeurs absolues d'ETP. À mentionner dans la méthode.

3. **`0-Recombiner_saisons_ECE.R` calcule TNn en année civile** (mois 1-5 et 9-12 d'une même année),
   alors qu'`agreger()` utilise l'hiver à cheval SEP(an-1) à MAI(an). Ce lanceur n'est appelé par
   aucun script et n'est pas publié. La vérification que les fichiers TNn et CWN de la v1.0 ont bien
   été produits par `agreger()` (46 couches, date postérieure au passage à l'hiver à cheval) n'a pas
   pu être faite, faute d'accès au serveur de calcul. La v1.1 utilise `agreger()`.

4. **Climpact modifié localement.** Comparaison avec le commit officiel 3.3.2 : 10 fichiers
   modifiés, dont deux changements de `ncdf.R` qui peuvent modifier les données lues (troncature des
   séries à la plus courte, températures forcées en °C). Détail et patch : `third_party/climpact/`.

### Downscaling

5. **Drapeau `RENORM_MENS_PREC` sans effet.** Le script SAFRAN du projet déclarait une « passe 3 »
   de renormalisation mensuelle des pluies, exportée aux workers mais jamais lue : SAF-DS est la
   méthode Delta seule. Erreur de production involontaire ; le drapeau n'a jamais figuré dans ce dépôt.

### Extraction et effectifs

6. **Effectifs des Fig. 6 et 7.** Les légendes écrivent « 34 255 placettes ». Les écarts-types et R²
   affichés sont en réalité calculés sur **31 600 placettes** (toutes les placettes 2015-2023 hors
   Corse, une valeur par placette). 34 255 est le nombre d'observations placette × essence du
   modèle (21 989 placettes distinctes, dont 9 392 portent au moins deux des 8 essences).

7. **Deux critères d'exclusion de la Corse** (boîte lon > 8,5 et lat < 43,1 ; départements 2A/2B).
   Ils sélectionnent exactement les mêmes placettes en 2015-2023. La Corse est exclue partout
   (valeurs aberrantes de DIGITALIS).

### Modèle

8. **Effectifs différents entre bases.** v1.0 : `na.omit()` base par base ; placettes hors de la
   grille terrestre de certaines bases (littoral, frontière nord-est pour EOB-DS) : 0 pour CHE-1,
   6 SAF-8, 11 SAF-DS, 28 EOB-10, 82 EOB-DS sur 34 255.
   **v1.1** : `ECHANTILLON_COMMUN = TRUE`, mêmes placettes pour toutes les bases (34 159 lignes,
   au plus 0,49 % retirées par essence), y compris pour le run peuplement.

9. **Graine différente d'une base à l'autre.** v1.0 : `42 + 100 × rang essence + rang base`,
   rangs calculés après filtrage.
   **v1.1** : `42 + 100 × rang de l'essence dans la liste complète` ; avec l'échantillon commun, les
   partitions 70/30 sont identiques pour toutes les bases et entre un run complet et un run filtré
   (`tests/test_moteur_echantillon.R`).

10. **« 1 000 bootstraps ».** Le code tire 1 000 partitions aléatoires 70/30 sans remise :
    validation croisée répétée, pas bootstrap.

11. **Runs nommés « 2015-2024 »** alors que les données s'arrêtent en 2023.
    **v1.1** : sessions en `2015-2023`, `CAMPAGNE_MAX = 2023`.

### Tableaux et figures du rapport

12. **Tableau A.III (a)** : valeurs du modèle **avec ECE** (AUC 0,761) présentées comme celles du
    modèle peuplement (AUC 0,753) ; le texte y renvoie sous le nom « Tableau A.II ».
    **v1.1** : `R/07_figures/tableaux_performances.R` produit les deux tableaux, correctement
    étiquetés.

13. **Tableau I, ligne « Différence max entre modèle Peupl. - ECE »** : ce sont les écarts **moyens**
    (+0,008 pour l'AUC ; l'écart maximal par base est +0,011). **v1.1** : les deux lignes sont produites.

14. **Tableau A.II : CHELSA cité « Karger et al. 2023 »** (CHELSA-TraCE21k, paléoclimat). La base
    utilisée est CHELSA V2.1 : Karger et al. 2017 et 2021.

15. **Scripts de figures perdus.** Recréés et validés sur les données v1.0 : Fig. 6, 7, 8b, 9.
    Restent à recréer : Fig. 3 (schéma), Fig. 4 et 5 (NetCDF 2014), Fig. A.3 et A.4 (NetCDF des
    indices) ; ces données sont sur le stockage du laboratoire, qui n'est plus accessible. La Fig. 8a (heatmap des IR) a les mêmes valeurs que la sortie de
    `R/07_figures/figures_H1_binaire.R`, avec une mise en forme différente. Voir `docs/figures_rapport.md`.

### Chaîne de production

16. **NetCDF journaliers SAF-8 (1979-2024).** Aucun script du projet ne les produit :
    `2-Calcul_SAFRAN_ForcPRCP_horaire_vers_journalier.R` ne traite que septembre 2014 (test) et
    `8b-SAFRAN_reprojection_WGS84.R` reprojette des fichiers déjà présents. D'après le Lisez-moi
    de `3-Donnees/2-SAFRAN_8Km_nc`, SAF-8 dérive des forçages SAFRAN horaires, alors que SAF-DS part
    des fichiers SIM2 quotidiens : à confirmer.

17. **Sous-chemins historiques.** Les scripts des modules 01 et 03 lisent d'anciens emplacements
    (`3-Donnees/2-CHELSA/...`, `3-Donnees/3-E_OBS/...`), déplacés depuis sous `3-Donnees/0-Brut/`
    (voir `docs/pipeline.md`).
