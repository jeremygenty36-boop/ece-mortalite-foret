# Environnement d'exécution

## R

Les calculs du rapport ont tourné sous **Windows, R 4.3.1**, sur le serveur de calcul du laboratoire ;
les figures R et les tests locaux sous **R 4.4.3 sur Mac**. La session n'avait
pas été enregistrée : versions reconstituées à partir des fichiers produits, avec leur niveau de preuve,
dans [`versions_R.md`](versions_R.md). Liste des paquets appelés : [`paquets_R.txt`](paquets_R.txt).
Climpact et ses paquets pcic : [`../third_party/climpact/README.md`](../third_party/climpact/README.md).

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
