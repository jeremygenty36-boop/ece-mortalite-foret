# Environnement d'exécution

## R

Les calculs du rapport ont tourné sous **Windows**, dans R, sur le serveur de calcul du
laboratoire. La version exacte de R et des paquets **n'a pas été enregistrée** au moment des
calculs. Pour la figer, lancer une fois, sur la machine de calcul, dans la console R :

```r
writeLines(capture.output(sessionInfo()), "environnement/sessionInfo_calcul.txt")
```

puis versionner le fichier produit. Paquets utilisés par les scripts du dépôt : voir
[`paquets_R.txt`](paquets_R.txt). Climpact et ses paquets pcic : voir
[`../third_party/climpact/README.md`](../third_party/climpact/README.md).

Certains scripts sont encodés en Latin-1 avec fins de ligne Windows (CRLF) ; ils se lisent
correctement sous Windows mais peuvent afficher des accents erronés ailleurs.

## Python

- Helpers de fusion NetCDF (`python/ece_helpers/`) : Python avec `numpy` et `netCDF4`
  (OSGeo4W sur la machine d'origine ; interpréteur configurable via `ECE_PYTHON`).
- Figures (`python/figures/`) : `numpy`, `pandas`, `matplotlib` (les PDF du rapport indiquent Matplotlib 3.10.8 ;
  figures recréées testées avec Python 3.14, numpy 2.4, pandas 2.3, matplotlib 3.10.8).
- Version de référence du downscaling (`python/downscaling/`) : voir son `requirements.txt`.

```bash
python3 -m pip install -r environnement/requirements.txt
```
