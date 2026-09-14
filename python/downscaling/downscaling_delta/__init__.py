"""Downscaling 1 km par methode Delta - implementation de reference (Python).

Portage lisible des scripts R de production (SAFRAN IDW, E-OBS / CHELSA bilineaire).
Cf. docs/methode_downscaling.md (racine du depot) pour la methode et README.md pour l'usage.
"""
from . import interpolation, methode_delta, pipeline  # noqa: F401
from .methode_delta import (  # noqa: F401
    ADDITIF,
    MULTIPLICATIF,
    RATIO_MAX,
    RATIO_MIN,
    appliquer_jour,
    downscale_mois,
    facteur_mensuel,
    stat_mensuelle,
)

__all__ = [
    "methode_delta", "interpolation", "pipeline",
    "MULTIPLICATIF", "ADDITIF", "RATIO_MIN", "RATIO_MAX",
    "stat_mensuelle", "facteur_mensuel", "appliquer_jour", "downscale_mois",
]
