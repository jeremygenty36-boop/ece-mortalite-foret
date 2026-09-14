# Figures et tableaux du rapport

Numérotation du **PDF rendu** (« Rapport de stage M2 BICG-Genty Jeremy.pdf », 25/07/2026).
Le dossier de travail `Figures_rapport/` utilisait une numérotation antérieure, indiquée
entre parenthèses.

Statut : **retrouvé** (script identifié et importé) · **à confirmer** (script probable) ·
**à recréer** (aucun script trouvé, PDF seul) · **saisi** (tableau rempli à la main).

## Corps du rapport

| N° | Contenu | Fichier livré | Script | Données | Statut |
|---|---|---|---|---|---|
| Fig. 1 | Spirale du dépérissement (d'après Manion 1981) | `Figure1_spirale.pdf` | [`python/figures/fig1_spirale.py`](../python/figures/fig1_spirale.py) | aucune | retrouvé |
| Fig. 2 | Placettes IFN retenues par essence et part avec mortalité, 2015-2023 | `IFN_figure_combinee_carte_barplot.png` | [`R/07_figures/4-Carte_combinee_barplot_Focus.R`](../R/07_figures/4-Carte_combinee_barplot_Focus.R) | `IFN_placette.csv`, masque GADM | retrouvé |
| Fig. 3 | Schéma du downscaling (interpolation puis méthode Delta) | inclus au rapport | aucun | aucune | à préciser (dessin ?) |
| Fig. 4 | Cumul de précipitations 2014, 4 bases à résolution native | `Figure_04_precipitations_2014.pdf` (22/07) | aucun ; variante d'un script de cartes 2014 à 6 bases (mars, non importé) | SAFRAN, E-OBS, CHELSA, DIGITALIS 2014 | à recréer |
| Fig. 5 | Descente d'échelle de Tmin 2014, Alpes du Nord (SAF-8, SAF-DS, EOB-10, EOB-DS) | `Figure_06_descente_echelle_Alpes_TNn.pdf` (PNG converti) | aucun | NetCDF journaliers 2014 | à recréer |
| Fig. 6 | Effet du downscaling sur la distribution des ECE aux placettes, CHE-1 superposée (version 6 indices en annexe de travail) | `Figure_07_distributions_ECE_avec_CHELSA.pdf`, `Figure_annexe_distributions_6indices_avec_CHELSA.pdf` (Matplotlib, 23/07) | aucun | `IFN_placette.csv` | à recréer |
| Fig. 7 | R² entre bases des 6 indices aux placettes, avant et après downscaling | `Figure_05_correlation_inter_bases_ECE.pdf` (Matplotlib, 23/07) | aucun | `IFN_placette.csv` | à recréer |
| Tab. I | Performances par base, modèle peuplement et peuplement + ECE | `Tableau_performances_entre_bases_peupl_et_ECE.docx` | aucun | `Synthese_globale.csv` des runs binaires peuplement et r070 | saisi ; valeurs vérifiées (± 0,001) |
| Fig. 8a | IR des indices ECE par essence, moyenne des 5 bases | `Figure_10_IR_par_essence__A_CONFIRMER.pdf` (R, 21/07) | [`R/07_figures/figures_H1_binaire.R`](../R/07_figures/figures_H1_binaire.R) (figure 3, heatmap) | `RI_par_variable.csv`, run r070 binaire | à confirmer |
| Fig. 8b | Sens de l'effet des ECE selon la base | `Figure_reponse_majoritaire_ECE_par_base.pdf` (Matplotlib, 24/07) | aucun | `RI_par_variable.csv`, run r070 binaire | à recréer |
| Fig. 9 | IR des 6 ECE par base et par essence | `Figure_11_IR_essence_base_indice_2D.pdf` (Matplotlib, 24/07) | aucun | `RI_par_variable.csv`, run r070 binaire | à recréer |

## Annexes

| N° | Contenu | Fichier livré | Script | Données | Statut |
|---|---|---|---|---|---|
| Tab. A.I | Les 6 indices ECE | `1.1-Tableau_A1.pdf` | source LaTeX `1.1-Tableau_A1.tex` (projet, non importée) | aucune | saisi |
| Tab. A.II | Inventaire des bases climatiques | `1.2-Tableau_A2.pdf` | source LaTeX `1.2-Tableau_A2.tex` (projet, non importée) | aucune | saisi ; citation CHELSA à corriger (ERRATA 14) |
| Tab. A.III | (a) performances moyennes, (b) IR des variables de peuplement | inclus au rapport | aucun | runs r070 binaire | saisi ; (a) mal étiqueté (ERRATA 12) |
| Fig. A1 | Matrices de corrélation des 6 indices, une par base | `Fig_correlation_indices_ECE_par_base.png` | [`R/07_figures/71-Fig_correlation_indices_ECE_MM.R`](../R/07_figures/71-Fig_correlation_indices_ECE_MM.R) | `IFN_placette.csv` | retrouvé |
| Fig. A.2 | Modèles binaires ECE contre moyennes saisonnières | `Fig_comparaison_ECE_vs_moyen_7metriques__*.pdf` | [`R/07_figures/81-Fig_comparaison_ECE_vs_moyen_7metriques_binaire.R`](../R/07_figures/81-Fig_comparaison_ECE_vs_moyen_7metriques_binaire.R) | runs r070 binaire et `ECE_Moyen_5bases_2015-2023_binaire` | retrouvé |
| Fig. A.3 | Évolution des 6 indices en France, 5 bases, 1979-2024 | `Figure_tendance_ECE_toutes_bases_TENDANCES_1979-2024.pdf` (Matplotlib, 24/07) | aucun | NetCDF des indices post-traités | à recréer |
| Fig. A.4 | Cartes des 6 indices, CHE-1, moyenne 1979-2024 | `Figure_cartes_ECE_CHELSA.pdf` (Matplotlib, 24/07) | aucun | NetCDF CHE-1 post-traités | à recréer |

## Figures produites automatiquement par les sessions

`R/06_modele/0N2-Session_France_binaire_complet.R` enchaîne après chaque modèle :
`3-Tableaux/7-Tableau_synthese_modele.R`, `2-Figures/8-Figure_tableau_modele.R`,
`2-Figures/20-Fig_RI_par_variable.R`, `2-Figures/22-Fig_synthese_IR_modele.R`,
`2-Figures/9-Courbes_reponse.R` et `3-Tableaux/19-Tableau_effectifs_mortalite.R`.
Ces sorties servent au contrôle des runs ; elles ne figurent pas telles quelles dans le rapport.

## Recréer une figure perdue

Les PDF livrés servent de référence. Pour chaque figure à recréer : écrire le script dans
`python/figures/` (ou `R/07_figures/`), lire les mêmes données, puis comparer visuellement la
sortie au PDF du rapport (structure, échelles, valeurs affichées) avant de changer le statut ici.
