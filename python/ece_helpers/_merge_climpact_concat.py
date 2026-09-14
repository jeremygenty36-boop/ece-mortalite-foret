# -*- coding: utf-8 -*-
# Concatene N fichiers Climpact (1 par periode) en 1 seul, en gerant le trim
# du warmup (1ere annee de chaque periode P2-P5).
# Plan B au cas ou terra::writeCDF avec compression bloque/sature en RAM.
#
# COMPAT : Python 2.7+ et 3.x
#
# USAGE (depuis R) :
#   system('"C:\\OSGeo4W64\\bin\\python.exe" '
#          '"S:\\Projets\\stage_JeremyG\\4-Travail\\2-ECE\\_merge_climpact_concat.py" '
#          '"S:/.../climpact_raw_1979-1987/tnn_MON_xxx.nc:1979" '   # tag:debut_effectif
#          '"S:/.../climpact_raw_1987-1996/tnn_MON_xxx.nc:1988" '
#          '...                                                   '
#          '"S:/.../climpact_raw/tnn_MON_xxx.nc"')                # OUT (dernier arg)
#
# Sortie compressee zlib niveau 1, chunks (1, ny, nx) = ~8 Mo / chunk.
# ============================================================================

from __future__ import print_function
import os, sys, time
import numpy as np
import netCDF4 as nc

if len(sys.argv) < 3:
    print("USAGE: python _merge_climpact_concat.py "
          "<in1.nc:debut_eff> <in2.nc:debut_eff> ... <out.nc>")
    sys.exit(2)

# Dernier arg = output
F_OUT = sys.argv[-1]
ENTRIES = sys.argv[1:-1]

print("[MERGE py] {0} fichiers d'entree, sortie : {1}".format(len(ENTRIES), F_OUT))
sys.stdout.flush()

# 1) Parser les entrees : "path.nc:debut_effectif"
inputs = []
for e in ENTRIES:
    if ':' in e and e.rfind(':') > 2:  # ":N" a la fin (eviter de splitter "C:/")
        path, an = e.rsplit(':', 1)
        try:
            an = int(an)
        except ValueError:
            path = e; an = None
    else:
        path = e; an = None
    if not os.path.exists(path):
        print("ERREUR : fichier absent : {0}".format(path))
        sys.exit(1)
    inputs.append({'path': path, 'debut_eff': an})
    print("  - {0}  (debut_effectif={1})".format(os.path.basename(path), an))
sys.stdout.flush()

# 2) Inspection du 1er fichier : grille + variable
ds0 = nc.Dataset(inputs[0]['path'], 'r')
try:
    if 'lon' in ds0.variables:
        lon_name, lat_name = 'lon', 'lat'
    elif 'longitude' in ds0.variables:
        lon_name, lat_name = 'longitude', 'latitude'
    else:
        cands = [v for v in ds0.variables if v.lower() in ('x','y')]
        lon_name, lat_name = cands[0], cands[1]
    lon_vals = ds0.variables[lon_name][:]
    lat_vals = ds0.variables[lat_name][:]
    nx = len(lon_vals); ny = len(lat_vals)
    excl = set([lon_name, lat_name, 'lon', 'lat', 'longitude', 'latitude',
                'time', 'time_bnds', 'crs', 'spatial_ref', 'x', 'y', 'bnds'])
    data_vars = [v for v in ds0.variables
                 if v not in excl and 'time' in ds0.variables[v].dimensions]
    if not data_vars:
        print("ERREUR : aucune variable de donnees dans {0}".format(inputs[0]['path']))
        sys.exit(1)
    var_name = data_vars[0]
    var_units = getattr(ds0.variables[var_name], 'units', '')
    var_dtype = ds0.variables[var_name].dtype
    print("[MERGE py] grille {0}x{1}, variable '{2}' ({3})".format(nx, ny, var_name, var_units))
finally:
    ds0.close()
sys.stdout.flush()

# 3) Lire dates de chaque fichier + filtrer selon debut_effectif
all_dates_jul = []  # numeriques (avec unite commune)
all_indices   = []  # indices a garder par fichier (apres trim)
t_units = None; t_calendar = 'standard'
for inp in inputs:
    ds = nc.Dataset(inp['path'], 'r')
    try:
        tv = ds.variables['time']
        t_raw = np.asarray(tv[:])
        if t_units is None:
            t_units = tv.units
            t_calendar = getattr(tv, 'calendar', 'standard')
        # Convert dates pour determiner annees
        try:
            dates_dt = nc.num2date(t_raw, units=tv.units,
                                   calendar=getattr(tv, 'calendar', 'standard'))
            years = np.array([d.year for d in dates_dt])
        except Exception:
            years = np.array([1970]*len(t_raw))
    finally:
        ds.close()
    if inp['debut_eff'] is not None:
        keep = np.where(years >= inp['debut_eff'])[0]
    else:
        keep = np.arange(len(t_raw))
    all_indices.append(keep)
    all_dates_jul.append(t_raw[keep])
    print("[MERGE py]   {0} : {1} couches, garde {2} (>= {3})".format(
        os.path.basename(inp['path']), len(t_raw), len(keep), inp['debut_eff']))
sys.stdout.flush()

times_concat = np.concatenate(all_dates_jul).astype(np.float64)
n_total = len(times_concat)
print("[MERGE py] total apres trim : {0} couches".format(n_total))
sys.stdout.flush()

# 4) Creer le fichier de sortie
if os.path.exists(F_OUT):
    os.remove(F_OUT)
print("[MERGE py] Creation {0}".format(F_OUT))
sys.stdout.flush()

out = nc.Dataset(F_OUT, 'w', format='NETCDF4')
try:
    out.createDimension('lon', nx)
    out.createDimension('lat', ny)
    out.createDimension('time', None)

    v_lon = out.createVariable('lon', 'f8', ('lon',))
    v_lon.units = 'degrees_east'; v_lon.standard_name = 'longitude'
    v_lon[:] = lon_vals

    v_lat = out.createVariable('lat', 'f8', ('lat',))
    v_lat.units = 'degrees_north'; v_lat.standard_name = 'latitude'
    v_lat[:] = lat_vals

    v_time = out.createVariable('time', 'f8', ('time',))
    v_time.units = t_units; v_time.calendar = t_calendar
    v_time.standard_name = 'time'
    v_time[:] = times_concat

    v_dat = out.createVariable(var_name, 'f4',
                               ('time', 'lat', 'lon'),
                               zlib=True, complevel=1, shuffle=True,
                               chunksizes=(1, ny, nx),
                               fill_value=-9999.0)
    if var_units:
        v_dat.units = var_units

    # 5) Boucle d'ecriture, par fichier d'entree (1 appel par periode)
    t_offset = 0
    t_start = time.time()
    for i, inp in enumerate(inputs):
        ds = nc.Dataset(inp['path'], 'r')
        try:
            data = ds.variables[var_name][:]   # shape varie : (n_t, ny, nx) ou (n_t, scale, ny, nx) pour SPEI
        finally:
            ds.close()
        if data.ndim == 4:
            # SPEI a une dim "scale" : on prend l'index 1 par defaut (SPEI-3 a SPEI-12 selon ordre)
            # Climpact : ordres = c(3, 6, 12) typiquement, on prend SPEI-6 = index 1
            scale_idx = 1 if data.shape[1] > 1 else 0
            data = data[:, scale_idx, :, :]
        # Trim selon debut_eff
        keep = all_indices[i]
        data = data[keep, :, :]
        n_t = data.shape[0]
        v_dat[t_offset:t_offset + n_t, :, :] = data
        t_offset += n_t
        elapsed = time.time() - t_start
        print("[MERGE py] {0}/{1} : +{2} couches (cumul {3}, +{4:.0f}s)".format(
            i + 1, len(inputs), n_t, t_offset, elapsed))
        sys.stdout.flush()
    out.sync()
finally:
    out.close()

sz = os.path.getsize(F_OUT) / 1e6
print("[MERGE py] OK : {0} ({1:.1f} Mo)".format(F_OUT, sz))
sys.exit(0)
