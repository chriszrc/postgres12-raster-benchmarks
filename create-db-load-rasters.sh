export PGHOST="${HOST:-localhost}"
export PGPORT="${PORT:-5432}"
export POSTGRES_USER="${POSTGRES_USER:-postgres}"
export PGUSER="$POSTGRES_USER"
export PG_BIN_PATH="${PG_BIN_PATH:-}"
## TODO better than bin_path? 
#export PATH="$PATH:/etc"
export RASTER_USER="rasterbenchmark"
export RASTER_DB_NAME="raster_benchmark"


##create postgres user
${PG_BIN_PATH}createuser $RASTER_USER 

##create postgres db
${PG_BIN_PATH}createdb -e --owner=$RASTER_USER -U $PGUSER $RASTER_DB_NAME 

## add extensions to databases
${PG_BIN_PATH}psql -d $RASTER_DB_NAME -c "CREATE EXTENSION IF NOT EXISTS postgis;"
${PG_BIN_PATH}psql -d $RASTER_DB_NAME -c "CREATE EXTENSION IF NOT EXISTS postgis_raster;" 

## Reproject raster before importing
${PG_BIN_PATH}gdalwarp -s_srs EPSG:32616 -t_srs EPSG:5070 -r near -of GTiff ./data/LC08_L1TP_019036_20200709_20200721_01_T1_B4.TIF ./data/lc08_l1tp_019036_b4_albers.tif
${PG_BIN_PATH}gdalwarp -s_srs EPSG:32616 -t_srs EPSG:5070 -r near -of GTiff ./data/LC08_L1TP_019036_20200709_20200721_01_T1_B5.TIF ./data/lc08_l1tp_019036_b5_albers.tif

## Import both rasters 
## Ran into problems with adding automatic constraints with -C. Also with -N 0 for no data 
## Time ~14seconds
${PG_BIN_PATH}raster2pgsql -e -Y ./data/lc08_l1tp_019036_b4_albers.tif -t auto public.lc08_l1tp_019036_b4_albers | ${PG_BIN_PATH}psql -U $RASTER_USER -d $RASTER_DB_NAME
${PG_BIN_PATH}raster2pgsql -e -Y ./data/lc08_l1tp_019036_b5_albers.tif -t auto public.lc08_l1tp_019036_b5_albers | ${PG_BIN_PATH}psql -U $RASTER_USER -d $RASTER_DB_NAME

## Note that the tilesize = auto setting above results in tiles 291x161, which
## which seems pretty reasonable, with about 1000 records. 

## Also create a table with smaller tile sizes (more records, maybe more parallel friendly?)
${PG_BIN_PATH}raster2pgsql -e -Y ./data/lc08_l1tp_019036_b4_albers.tif -t 50x50 public.lc08_l1tp_019036_b4_albers_50x | ${PG_BIN_PATH}psql -U $RASTER_USER -d $RASTER_DB_NAME
${PG_BIN_PATH}raster2pgsql -e -Y ./data/lc08_l1tp_019036_b5_albers.tif -t 50x50 public.lc08_l1tp_019036_b5_albers_50x | ${PG_BIN_PATH}psql -U $RASTER_USER -d $RASTER_DB_NAME

## If you want to make db wide changes, you can run these performance enhancements for analytical queries
#${PG_BIN_PATH}psql -c "ALTER SYSTEM  SET shared_buffers = '4GB';"
#${PG_BIN_PATH}psql -c "ALTER SYSTEM  SET checkpoint_completion_target = '0.9';"
#${PG_BIN_PATH}psql -c "ALTER SYSTEM  SET wal_buffers = '16MB';"
#${PG_BIN_PATH}psql -c "ALTER SYSTEM  SET min_wal_size = '4GB';"
#${PG_BIN_PATH}psql -c "ALTER SYSTEM  SET max_wal_size = '8GB';"
#${PG_BIN_PATH}psql -c "ALTER SYSTEM  SET max_worker_processes = '8';"

## Run the benchmarks 
${PG_BIN_PATH}psql -U $RASTER_USER -d $RASTER_DB_NAME -f ./sql-benchmarks.sql

