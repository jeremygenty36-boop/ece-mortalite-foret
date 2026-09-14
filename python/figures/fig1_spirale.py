# -*- coding: utf-8 -*-
# Figure 1 : spirale du deperissement (adaptee de Manion 1981). Rendu vectoriel net.
import numpy as np, matplotlib.pyplot as plt
from matplotlib.patches import Circle
plt.rcParams['font.family'] = 'DejaVu Sans'

C_PRED, C_DECL, C_AGGR, C_MORT = "#215f9a", "#e08a2b", "#9e2a2b", "#111111"
CC = {'pred': C_PRED, 'decl': C_DECL, 'aggr': C_AGGR}

fig, ax = plt.subplots(figsize=(11.8, 8.4)); ax.set_aspect('equal'); ax.axis('off')

# --- spirale d'Archimede : ~3 tours (1 par famille), chaque bande couvre tous les azimuts ---
R_IN, R_OUT = 1.05, 3.50
th = np.linspace(2.0, 2.0 + 3.05*2*np.pi, 5000)
frac = (th - th[0]) / (th[-1] - th[0])
r = R_IN + (R_OUT - R_IN) * frac
phi = 5.368                                   # cale jonction O/R en haut-droite, entree en haut
x, y = r*np.cos(th + phi), r*np.sin(th + phi)
polar = np.arctan2(y, x)
n = len(th)
i1, i2 = int(n*0.328), int(n*0.656)           # rouge[0:i1] orange[i1:i2] bleu[i2:]
lw = 16
ax.plot(x[:i1],     y[:i1],     color=C_AGGR, lw=lw, solid_capstyle='round', zorder=3)
ax.plot(x[i1-1:i2], y[i1-1:i2], color=C_DECL, lw=lw, solid_capstyle='round', zorder=3)
ax.plot(x[i2-1:],   y[i2-1:],   color=C_PRED, lw=lw, solid_capstyle='round', zorder=3)

# --- centre MORT ---
ax.add_patch(Circle((0, 0), 0.74, color=C_MORT, zorder=5))
ax.text(0, 0.13, "MORT", color='white', ha='center', va='center', fontsize=15, fontweight='bold', zorder=6)
ax.text(0, -0.19, "de l'arbre", color='white', ha='center', va='center', fontsize=8.5, zorder=6)

# --- branchement : bord EXTERIEUR de la bande (rayon max a l'azimut de l'etiquette) ---
seg = {'pred': (i2, n), 'decl': (i1, i2), 'aggr': (0, i1)}
def attach(ang_deg, cat):
    a, b = seg[cat]; t = np.deg2rad(ang_deg)
    idx = np.arange(a, b)
    dif = np.abs(((polar[idx] - t + np.pi) % (2*np.pi)) - np.pi)
    near = idx[dif < np.deg2rad(5)]
    if len(near) == 0:
        near = idx[[int(np.argmin(dif))]]
    j = int(near[int(np.argmax(r[near]))])       # crossing le plus a l'exterieur
    return x[j], y[j]

# --- etiquettes : (azimut label, categorie, variable etudiee ?, texte, position imposee ou None) ---
labels = [
    (60,  'pred', True,  "Changement climatique", (2.35, 4.35)),   # jonction O/R ; aligne en haut
    (33,  'pred', True,  "Sol : pH, calcaire,\nréserve en eau", None),
    (6,   'pred', True,  "Structure du peuplement\n& sylviculture", None),
    (-22, 'pred', False, "Topographie", None),
    (-46, 'decl', True,  "Sécheresse", None),
    (-72, 'decl', True,  "Chaleur extrême,\nvagues de chaleur", None),
    (-105,'decl', True,  "Froid extrême,\nvagues de froid", None),
    (-143,'decl', False, "Tempête, blessure", None),
    (180, 'aggr', False, "Pathogènes\nsecondaires", None),
    (150, 'decl', False, "Pathogènes\nprimaires", None),
    (116, 'pred', False, "Âge, vitalité sociale", (-2.1, 4.35)),   # aligne en haut
]
Rlab = 4.5
for k, (ang, cat, tri, txt, pos) in enumerate(labels):
    a = np.deg2rad(ang)
    lx, ly = pos if pos is not None else (Rlab*np.cos(a), Rlab*np.sin(a))
    if k == 0:                                   # Changement climatique -> jonction orange/rouge
        tx, ty = x[i1], y[i1]
    else:
        tx, ty = attach(ang, cat)
    ax.plot([lx, tx], [ly, ty], color='0.6', lw=0.9, zorder=1)   # rejoint le bord de la case
    ha = 'left' if np.cos(a) > 0.25 else ('right' if np.cos(a) < -0.25 else 'center')
    ec = C_AGGR if k == 0 else CC[cat]           # Changement climatique en rouge
    s = ("▶ " if tri else "") + txt
    ax.text(lx, ly, s, ha=ha, va='center', fontsize=8.7, color='0.12',
            fontweight='bold' if tri else 'normal', zorder=4,
            bbox=dict(boxstyle='round,pad=0.32', fc='white', ec=ec, lw=1.7))

# --- legende ---
leg = [(C_PRED, "Facteurs prédisposants (fragilisent durablement)"),
       (C_DECL, "Facteurs déclenchants (rupture brutale de l'équilibre)"),
       (C_AGGR, "Facteurs aggravants (exploitent l'arbre affaibli)")]
y0 = -5.55
for k, (c, t) in enumerate(leg):
    yy = y0 - k*0.52
    ax.add_patch(plt.Rectangle((-6.7, yy-0.13), 0.34, 0.26, color=c, zorder=4))
    ax.text(-6.25, yy, t, va='center', ha='left', fontsize=9, color='0.12')
ax.text(0.5, y0, "▶", va='center', ha='center', fontsize=10, color='0.12')
ax.text(0.8, y0, "variable prise en compte dans cette étude (en gras)",
        va='center', ha='left', fontsize=9, color='0.12')

ax.set_xlim(-7.3, 7.7); ax.set_ylim(-6.6, 5.9)
out = "/Users/jeremygenty/Desktop/Figure1_spirale.png"
fig.savefig(out, dpi=300, bbox_inches='tight')
fig.savefig(out.replace('.png', '.pdf'), bbox_inches='tight')
print("OK ->", out)
