# Errata de la v1.0

Écarts relevés lors de la relecture du 14/09/2026 entre l'intention méthodologique
et le code **tel qu'exécuté pour le rapport**. Ils sont conservés dans la v1.0 pour
que le dépôt reproduise les résultats rendus. Les corrections prévues vont dans la
v1.1 ; les résultats du rapport ne les intègrent pas.

Légende : **[calcul]** change des valeurs si corrigé · **[doc]** formulation ou
documentation · **[chaîne]** maillon manquant ou mal rangé.

## Indices ECE

1. **[calcul] SPEI6 annuel = moyenne, et non minimum.** La valeur annuelle est la
   moyenne des 6 SPEI-6 mensuels de mars à août
   (`agreger(f_spei, "SPEI6", 3:8, "mean", ...)`, par exemple
   `R/04_indices_ece/1-ECE_EOBS.R:889`, identique dans les 6 scripts). À la
   placette, on prend ensuite le minimum de ces moyennes sur 10 ans. Non voulu.
   Correction v1.1 : minimum mensuel, puis recalcul de SPEI6, de l'extraction et des modèles.

2. **[doc] Rayonnement extraterrestre à latitude unique.** Dans l'ETP de Turc,
   Ra est calculé avec la latitude moyenne de la grille pour toute la France
   (`1-ECE_EOBS.R:340`). Simplification à mentionner dans la méthode.

3. **[chaîne] `0-Recombiner_saisons_ECE.R` (non publié) calcule TNn en année
   civile.** Ce lanceur prend les mois 1-5 et 9-12 d'une même année, alors
   qu'`agreger()` utilise l'hiver à cheval SEP(an-1) à MAI(an). Il n'est appelé
   par aucun script. À vérifier sur la machine de calcul : les fichiers
   `ECE_*_TNn_SEP-MAY.nc` et `ECE_*_CWN_SEP-MAY.nc` finaux ont 46 couches et une
   date de modification postérieure au passage à l'hiver à cheval.

4. **[chaîne] Climpact modifié localement.** SPEI-6 seul
   (`server/climpact.etsci-functions.r`) et compteur de progression + appel
   `base::t` explicite (`climdex.pcic.ncdf/R/ncdf.R`), le 20/05/2026. Voir
   `third_party/climpact/README.md`. Une comparaison complète avec la version
   officielle 3.3.2 reste à faire.

## Downscaling

5. **[doc] Drapeau `RENORM_MENS_PREC` sans effet.** Le script SAFRAN du projet
   déclarait une « passe 3 » de renormalisation mensuelle des pluies
   (`RENORM_MENS_PREC <- TRUE`), exportée aux workers mais jamais lue : SAF-DS
   est la méthode Delta seule. Ce drapeau n'a jamais figuré dans le module 02
   de ce dépôt. Erreur de production, involontaire.

## Extraction IFN

6. **[doc] 34 255 observations, pas 34 255 placettes.** 34 255 est le nombre de
   couples placette × essence (2015-2023, hors Corse). Ils proviennent de
   21 989 placettes, dont 9 392 portent au moins deux des 8 essences. Les légendes
   des Fig. 6 et 7 du rapport écrivent « 34 255 placettes ».

7. **[doc] Deux critères d'exclusion de la Corse** (boîte lon > 8,5 et lat < 43,1
   pour les grilles et l'extraction, départements 2A/2B pour le modèle et les
   figures). Ils sélectionnent exactement les mêmes placettes en 2015-2023 ;
   la Corse est exclue partout (valeurs aberrantes de DIGITALIS).

## Modèle

8. **[calcul] Effectifs différents entre bases.** `na.omit()` est appliqué base
   par base (`R/06_modele/1-Modele_mortalite_optimise.R:483`). Les NA viennent
   des placettes hors de la grille terrestre de certaines bases (littoral, et
   frontière nord-est pour EOB-DS) : 0 pour CHE-1, 6 SAF-8, 11 SAF-DS, 28 EOB-10,
   82 EOB-DS, sur 34 255. Correction v1.1 : placettes communes aux 5 bases
   (34 159 lignes, 96 retirées, au plus 0,49 % par essence).

9. **[calcul] Graine aléatoire différente d'une base à l'autre.** La graine vaut
   `42 + 100 × rang essence + rang base` (`...optimise.R:316`), rangs calculés
   après filtrage : les partitions 70/30 diffèrent entre bases et entre un run
   complet et un run filtré. Correction v1.1 : même graine par essence pour toutes
   les bases, sur les mêmes placettes (comparaison appariée).

10. **[doc] « 1 000 bootstraps ».** Le code tire 1 000 partitions aléatoires
    70/30 **sans remise** : validation croisée répétée, pas bootstrap.

11. **[doc] Runs nommés « 2015-2024 ».** Les données s'arrêtent en 2023 ;
    `CAMPAGNE_MAX = 2024` n'a pas d'effet. Les runs `..._2015-2024_...` et
    `..._2015-2023_...` portent sur le même jeu.

## Tableaux et figures du rapport

12. **[doc] Tableau A.III (a)** : les valeurs sont celles du modèle **avec ECE**
    (AUC 0,761), alors que la légende et le texte le présentent comme le modèle
    peuplement (AUC 0,753). Le texte y renvoie sous le nom « Tableau A.II ».

13. **[doc] Tableau I, ligne « Différence max entre modèle Peupl. - ECE »** :
    les valeurs sont les écarts **moyens** (AUC +0,008). Les autres valeurs du
    Tableau I concordent avec les sorties à 0,001 près.

14. **[doc] Tableau A.II : CHELSA cité « Karger et al. 2023 »** (CHELSA-TraCE21k,
    paléoclimat). La base utilisée est CHELSA V2.1 : Karger et al. 2017 et 2021.

15. **[chaîne] Scripts introuvables** pour les Fig. 3, 4, 5, 6, 7, 8b, 9, A.3 et
    A.4 (voir `docs/figures_rapport.md`). À recréer et comparer aux PDF du rapport.

## Chaîne de production

16. **[chaîne] NetCDF journaliers SAF-8 (1979-2024).** Aucun script actif ne les
    produit : `2-Calcul_SAFRAN_ForcPRCP_horaire_vers_journalier.R` ne traite que
    septembre 2014 (test) et `8b-SAFRAN_reprojection_WGS84.R` reprojette des
    fichiers déjà présents. Script à retrouver dans les archives du projet.
    À confirmer : d'après le Lisez-moi de `3-Donnees/2-SAFRAN_8Km_nc`, SAF-8
    dérive des forçages SAFRAN horaires (ForcT, ForcPRCP), alors que SAF-DS part
    des fichiers SIM2 quotidiens.

17. **[chaîne] Sous-chemins historiques.** Les scripts des modules 01 et 03
    lisent d'anciens emplacements (`3-Donnees/2-CHELSA/...`,
    `3-Donnees/3-E_OBS/...`), déplacés depuis sous `3-Donnees/0-Brut/`
    (voir `docs/pipeline.md`).
