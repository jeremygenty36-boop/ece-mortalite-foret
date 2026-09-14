# Figures Python du rapport

| Script | Figure du rapport | Statut |
|---|---|---|
| `fig1_spirale.py` | Fig. 1, spirale du dépérissement | retrouvé |
| `fig06_distributions_downscaling.py` | Fig. 6, distributions avant et après downscaling | recréé, 12 écarts-types identiques |
| `fig07_correlation_inter_bases.py` | Fig. 7, R² entre bases | recréé, 36 R² identiques |
| `fig08b_reponse_majoritaire.py` | Fig. 8b, indice dominant et sens de l'effet | recréé, 40 cellules identiques |
| `fig09_IR_essence_base.py` | Fig. 9, IR par base et par essence | recréé |

« Identiques » : valeurs affichées égales à celles du PDF du rapport, en lisant les sorties v1.0.
Les Fig. 4, 5, A.3 et A.4 (NetCDF) restent à recréer.

```bash
cd python/figures
export ECE_PROJET=/chemin/vers/Projets/stage_JeremyG   # ou ECE_F_IFN, ECE_DIR_MODELES, ECE_RUN_ECE
export ECE_FIGURES_OUT=/chemin/de/sortie
python3 fig07_correlation_inter_bases.py
```

Variables reconnues : voir `_commun.py`. `fig1_spirale.py` écrit dans `ECE_FIGURES_OUT` (défaut : `~/Desktop`).
