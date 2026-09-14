"""Tests du coeur methode Delta. Lancer : python -m pytest  (ou python tests/test_methode_delta.py)."""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from downscaling_delta import methode_delta as md  # noqa: E402


def test_stat_mensuelle_somme_et_moyenne():
    jours = np.array([[[1.0, 2.0]], [[3.0, 4.0]]])  # (2 jours, 1, 2)
    assert np.allclose(md.stat_mensuelle(jours, md.MULTIPLICATIF), [[4.0, 6.0]])
    assert np.allclose(md.stat_mensuelle(jours, md.ADDITIF), [[2.0, 3.0]])


def test_ratio_borne():
    src = np.array([[0.0, 100.0, 10.0]])          # 0 -> plancher, 100 -> ratio<min
    digi = np.array([[50.0, 0.05, 20.0]])
    r = md.facteur_mensuel(src, digi, md.MULTIPLICATIF)
    assert r.max() <= md.RATIO_MAX + 1e-12
    assert r.min() >= md.RATIO_MIN - 1e-12
    # cellule 3 : 20/10 = 2, dans les bornes
    assert np.isclose(r[0, 2], 2.0)


def test_delta_additif():
    src = np.array([[5.0, -3.0]])
    digi = np.array([[8.0, -1.0]])
    d = md.facteur_mensuel(src, digi, md.ADDITIF)
    assert np.allclose(d, [[3.0, 2.0]])


def test_appliquer_jour_precip_positive():
    jour = np.array([[2.0, 0.0]])
    fac = np.array([[3.0, 5.0]])
    out = md.appliquer_jour(jour, fac, md.MULTIPLICATIF)
    assert np.allclose(out, [[6.0, 0.0]])
    assert (out >= 0).all()


def test_conservation_somme_precip():
    rng = np.random.default_rng(0)
    jours = rng.gamma(0.5, 5.0, size=(31, 8, 6))
    src_m = md.stat_mensuelle(jours, md.MULTIPLICATIF)
    digi = src_m * rng.uniform(0.8, 1.3, src_m.shape)   # facteur dans les bornes
    corr = md.downscale_mois(jours, digi, md.MULTIPLICATIF)
    assert np.allclose(np.nansum(corr, axis=0), digi, rtol=1e-10)
    assert (corr >= 0).all()


def test_conservation_moyenne_temp():
    rng = np.random.default_rng(1)
    jours = rng.normal(10, 4, size=(28, 5, 7))
    src_m = md.stat_mensuelle(jours, md.ADDITIF)
    digi = src_m + rng.uniform(-2, 2, src_m.shape)
    corr = md.downscale_mois(jours, digi, md.ADDITIF)
    assert np.allclose(np.nanmean(corr, axis=0), digi, atol=1e-10)


def test_nan_reste_nan():
    jours = np.array([[[np.nan, 1.0]], [[np.nan, 2.0]]])
    digi = np.array([[1.0, 3.0]])
    corr = md.downscale_mois(jours, digi, md.ADDITIF)
    assert np.isnan(corr[:, 0, 0]).all()
    assert np.isfinite(corr[:, 0, 1]).all()


def test_methode_invalide():
    try:
        md.stat_mensuelle(np.zeros((1, 1, 1)), "bcsd")
    except ValueError:
        return
    raise AssertionError("une methode invalide doit lever ValueError")


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print(f"  OK  {fn.__name__}")
    print(f"\n{len(fns)} tests passes.")
