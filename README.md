# postgres12-raster-benchmarks

Include all files and commands necessary to demonstrate non-parallel execution plans for typical raster operations, like raster_calculator for NDVI as well as summarystats, clip/union operations, etc. 

Scripts assume you're already running Postgres 12, and a unix-like terminal. 

Start here:
```
PG_BIN_PATH=/Applications/Postgres.app/Contents/Versions/12/bin/ PORT=5430 ./create-db-load-rasters.sh 
```

Any of the following settings are overrideable from the command line:
```
export PGHOST="${HOST:-localhost}"
export PGPORT="${PORT:-5432}"
export POSTGRES_USER="${POSTGRES_USER:-postgres}"
export PGUSER="$POSTGRES_USER"
export PG_BIN_PATH="${PG_BIN_PATH:-}"
```

The bash script will create a database and user:
```
export RASTER_USER="rasterbenchmark"
export RASTER_DB_NAME="raster_benchmark"
```

and install Postgis extensions, reproject the 2 sample rasters included in this repo, and import them into the db. It will then set the necessary parallel db settings for the current session and run through a series of queries that illustrate the non-parallel plan executions. The first batch calculate NDVI, which is a simple raster calculator equation, with different formulations of the same query (different tile sizes, recosting the function, etc). The second batch creates 1 million random points within the bounds of the raster, create buffers for those points, and calculates summary statistics for the piece of the raster it intersects with. 

I was unable to generate parallel execution plans for any of these queries, even though they follow all the Postgres12 rules (https://www.postgresql.org/docs/12/when-can-parallel-query-be-used.html), e.g., no CTEs, no update/inserts, only selects or create table as. Any help with this is greatly appreciated!
