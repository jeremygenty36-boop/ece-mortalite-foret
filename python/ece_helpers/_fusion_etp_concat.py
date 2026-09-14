# -*- coding: utf-8 -*-
# Concatene les 46 tmp ETP annuels de CHELSA en un seul NetCDF.
# Contourne le bug R "long vectors not yet supported" (Rinlinedfuns.h:537) qui
# plante terra::writeCDF quand le raster total > 2^31 elements.
# Python n'a pas cette limite. netCDF4 ecrit chunk-par-chunk via HDF5 sans
# bufferiser tout en RAM. Estimation : ~5-15 min pour 46 ans / 1km France.
#
# USAGE (depuis R sur CALCULUS) :
#   system('"C:\\OSGeo4W64\\bin\\python.exe" '
#          '"S:\\Projets\\stage_JeremyG\\4-Travail\\2-ECE\\_fusion_etp_concat.py" '
#          '"D:/Stage_JeremyG/ECE_merge/CHELSA" '
#          '"CHELSA_etp_turc_1979-2024.nc"')
#
# COMPAT : Python 2.7+ et 3.x (utilise .format() au lieu de f-strings)
# ============================================================================

from __future__ import print_function
import os
import sys
import glob
import re
import time
import numpy as np
import netCDF4 as nc

if len(sys.argv) < 3:
    print("USAGE: python _fusion_etp_concat.py <MERGE_DIR> <OUT_FILENAME>")
    sys.exit(2)

MERGE_DIR = sys.argv[1]
OUT_NAME  = sys.argv[2]
F_OUT     = os.path.join(MERGE_DIR, OUT_NAME)

print("[FUSION ETP py] Python    = {0}".format(sys.version.split()[0]))
print("[FUSION ETP py] MERGE_DIR = {0}".format(MERGE_DIR))
print("[FUSION ETP py] OUT       = {0}".format(F_OUT))
print("[FUSION ETP py] netCDF4   = {0}, numpy = {1}".format(nc.__version__, np.__version__))
sys.stdout.flush()

# 1) Detecter les tmp files annuels
pat = os.path.join(MERGE_DIR, "*_etpturc_tmp_????.nc")
tmp_files = sorted(glob.glob(pat))
if not tmp_files:
    print("ERREUR : aucun tmp file trouve avec pattern {0}".format(pat))
    sys.exit(1)

# Tri par annee
def get_year(f):
    m = re.search(r"_etpturc_tmp_(\d{4})\.nc$", os.path.basename(f))
    return int(m.group(1)) if m else -1
tmp_files.sort(key=get_year)
print("[FUSION ETP py] {0} tmp files trouves ({1}-{2})".format(
    len(tmp_files), get_year(tmp_files[0]), get_year(tmp_files[-1])))
sys.stdout.flush()

# 2) Inspecter le 1er fichier : grille + variable
ds0 = nc.Dataset(tmp_files[0], 'r')
try:
    if 'lon' in ds0.variables:
        lon_name, lat_name = 'lon', 'lat'
    elif 'longitude' in ds0.variables:
        lon_name, lat_name = 'longitude', 'latitude'
    else:
        coords = [v for v in ds0.variables if v.lower() in ('x', 'y')]
        lon_name, lat_name = coords[0], coords[1]
    lon_vals = ds0.variables[lon_name][:]
    lat_vals = ds0.variables[lat_name][:]
    nx = len(lon_vals); ny = len(lat_vals)
    excl = set([lon_name, lat_name, 'lon', 'lat', 'longitude', 'latitude',
                'time', 'time_bnds', 'crs', 'spatial_ref', 'x', 'y'])
    data_vars = [v for v in ds0.variables
                 if v not in excl and 'time' in ds0.variables[v].dimensions]
    if not data_vars:
        print("ERREUR : aucune variable de donnees dans {0}".format(tmp_files[0]))
        sys.exit(1)
    var_name = data_vars[0]
    var_units = getattr(ds0.variables[var_name], 'units', 'mm')
    print("[FUSION ETP py] grille : {0} lon x {1} lat".format(nx, ny))
    print("[FUSION ETP py] variable : '{0}' ({1})".format(var_name, var_units))
finally:
    ds0.close()
sys.stdout.flush()

# 3) Collecter toutes les dates
print("[FUSION ETP py] Collecte des dates depuis {0} tmp...".format(len(tmp_files)))
sys.stdout.flush()
all_t = []
t_units = None
t_calendar = 'standard'
for f in tmp_files:
    ds = nc.Dataset(f, 'r')
    try:
        tv = ds.variables['time']
        all_t.append(np.asarray(tv[:]))
        if t_units is None:
            t_units = tv.units
            t_calendar = getattr(tv, 'calendar', 'standard')
    finally:
        ds.close()
times_concat = np.concatenate(all_t).astype(np.float64)
n_total = len(times_concat)
print("[FUSION ETP py] total time steps : {0} (attendu ~16802 pour 46 ans)".format(n_total))
print("[FUSION ETP py] time units : '{0}', calendar : '{1}'".format(t_units, t_calendar))
sys.stdout.flush()

# 4) Creer le fichier de sortie (NETCDF4 compresse, chunks=(1, ny, nx))
if os.path.exists(F_OUT):
    os.remove(F_OUT)
    print("[FUSION ETP py] suppression ancien {0}".format(F_OUT))

print("[FUSION ETP py] Creation {0} ...".format(F_OUT))
sys.stdout.flush()
out = nc.Dataset(F_OUT, 'w', format='NETCDF4')
try:
    out.createDimension('lon',  nx)
    out.createDimension('lat',  ny)
    out.createDimension('time', None)  # unlimited

    v_lon = out.createVariable('lon', 'f8', ('lon',))
    v_lon.units = 'degrees_east'
    v_lon.standard_name = 'longitude'
    v_lon[:] = lon_vals

    v_lat = out.createVariable('lat', 'f8', ('lat',))
    v_lat.units = 'degrees_north'
    v_lat.standard_name = 'latitude'
    v_lat[:] = lat_vals

    v_time = out.createVariable('time', 'f8', ('time',))
    v_time.units = t_units
    v_time.calendar = t_calendar
    v_time.standard_name = 'time'
    v_time[:] = times_concat

    # Variable principale : (time, lat, lon) chunks (1, ny, nx) = ~8-9 Mo / chunk
    v_dat = out.createVariable(var_name, 'f4',
                               ('time', 'lat', 'lon'),
                               zlib=True, complevel=1, shuffle=True,
                               chunksizes=(1, ny, nx),
                               fill_value=-9999.0)
    v_dat.units = var_units

    # 5) Boucle d'ecriture, 1 annee par appel (~365 chunks compresses sequentiels)
    t_offset = 0
    t_start = time.time()
    for i, f in enumerate(tmp_files):
        an = get_year(f)
        ds = nc.Dataset(f, 'r')
        try:
            data = ds.variables[var_name][:]   # shape (n_t, ny, nx)
        finally:
            ds.close()
        if data.ndim == 4:
            data = data[:, 0, :, :]
        n_t = data.shape[0]
        v_dat[t_offset:t_offset + n_t, :, :] = data
        t_offset += n_t
        elapsed = time.time() - t_start
        print("[FUSION ETP py] {0:2d}/{1} ({2}) : {3} couches (cumul {4}, +{5:.0f}s)".format(
            i + 1, len(tmp_files), an, n_t, t_offset, elapsed))
        sys.stdout.flush()
    out.sync()
finally:
    out.close()

sz_gb = os.path.getsize(F_OUT) / 1e9
print("[FUSION ETP py] OK : {0} ({1:.2f} GB)".format(F_OUT, sz_gb))
sys.exit(0)
