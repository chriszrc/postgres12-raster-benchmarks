--Add configuration for parallel queries from a single user
SET effective_cache_size = '12GB';


SET maintenance_work_mem = '1792MB';


SET work_mem = '12000kB';


SET max_parallel_workers_per_gather = '4';


SET max_parallel_workers = '8' ;

;

-- sanity check
show parallel_setup_cost;

show max_parallel_workers;

show max_parallel_workers_per_gather;

\echo 'Remove raster tiles with no data';


update lc08_l1tp_019036_b4_albers
set rast = ST_SetBandNoDataValue(rast, 1, 0);


update lc08_l1tp_019036_b5_albers
set rast = ST_SetBandNoDataValue(rast, 1, 0);


delete
from lc08_l1tp_019036_b4_albers
where rid in
    (select rid
     from
       (select rid,
               ST_BandIsNoData(rast, 1, true) as isEmpty
        from lc08_l1tp_019036_b4_albers)a
     where isEmpty = true );

;


delete
from lc08_l1tp_019036_b5_albers
where rid in
    (select rid
     from
       (select rid,
               ST_BandIsNoData(rast, 1, true) as isEmpty
        from lc08_l1tp_019036_b5_albers)a
     where isEmpty = true );

;

\echo 'Run NDVI with built in st_MapAlgebra on subset of records';


drop table ndvi_test_100_records;

EXPLAIN ANALYSE
CREATE TABLE ndvi_test_100_records as
SELECT ST_MapAlgebra(rast1.rast,
                     1,
                     rast2.rast,
                     1,
                     '([rast1] - [rast2]) / ([rast1] + [rast2])::float',
                     '16BUI')
FROM lc08_l1tp_019036_b5_albers rast1
join lc08_l1tp_019036_b4_albers rast2 ON rast1.rid = rast2.rid
where rast1.rid < 270 -- about 100 rows of the ~1000 in the table

  and rast2.rid < 270;

;

/**
Gather  (cost=10.55..152.36 rows=10 width=32) (actual time=98.152..21140.218 rows=99 loops=1)
   Workers Planned: 1
   Workers Launched: 1
   Single Copy: true
   ->  Merge Join  (cost=0.55..141.36 rows=10 width=32) (actual time=28.281..21215.240 rows=99 loops=1)
         Merge Cond: (rast1.rid = rast2.rid)
         ->  Index Scan using lc08_l1tp_019036_b5_albers_pkey on lc08_l1tp_019036_b5_albers rast1  (cost=0.28..65.89 rows=99 width=31) (actual time=0.036..0.883 rows=99 loops=1)
               Index Cond: (rid < 270)
         ->  Index Scan using lc08_l1tp_019036_b4_albers_pkey on lc08_l1tp_019036_b4_albers rast2  (cost=0.28..74.85 rows=99 width=31) (actual time=0.034..0.343 rows=99 loops=1)
               Index Cond: (rid < 270)
 Planning Time: 1.636 ms
 Execution Time: 21371.077 ms
 **/ ;

;

\echo 'Run NDVI with built in st_MapAlgebra on all records';


drop table ndvi_test_all_records;

EXPLAIN ANALYSE
CREATE TABLE ndvi_test_all_records as
SELECT ST_MapAlgebra(rast1.rast,
                     1,
                     rast2.rast,
                     1,
                     '([rast1] - [rast2]) / ([rast1] + [rast2])::float',
                     '16BUI')
FROM lc08_l1tp_019036_b5_albers rast1
join lc08_l1tp_019036_b4_albers rast2 ON rast1.rid = rast2.rid ;

/**
TODO add execution plan output
  --257698.645 ms
**/;

-- NOTES: time seems linear, seems like a good operation for parallelization
;

-- try recosting the ST_MapAlgebra

CREATE OR REPLACE FUNCTION raster_mapalgebra_test(rast1 raster, nband1 integer, rast2 raster, nband2 integer) RETURNS raster AS $$
	DECLARE
	BEGIN
		return ST_MapAlgebra(rast1, 1, rast2, 1, '([rast1] - [rast2]) / ([rast1] + [rast2])::float', '32BF');
	END;
	$$ LANGUAGE 'plpgsql' PARALLEL SAFE IMMUTABLE COST 1000000;

;

;

\echo 'Run NDVI with costed st_mapAlgebra on all records';


drop table ndvi_test_all_records_costed;

EXPLAIN ANALYSE
CREATE TABLE ndvi_test_all_records_costed as
SELECT raster_mapalgebra_test(rast1.rast,
                              1,
                              rast2.rast,
                              1)
FROM lc08_l1tp_019036_b5_albers rast1
join lc08_l1tp_019036_b4_albers rast2 ON rast1.rid = rast2.rid ;

;

/**
Gather  (cost=198.38..2375494.38 rows=950 width=32) (actual time=487.541..241466.276 rows=950 loops=1)
   Workers Planned: 1
   Workers Launched: 1
   Single Copy: true
   ->  Hash Join  (cost=188.38..2375389.38 rows=950 width=32) (actual time=478.030..251484.445 rows=950 loops=1)
         Hash Cond: (rast2.rid = rast1.rid)
         ->  Seq Scan on lc08_l1tp_019036_b4_albers rast2  (cost=0.00..198.50 rows=950 width=31) (actual time=0.063..15.876 rows=950 loops=1)
         ->  Hash  (cost=176.50..176.50 rows=950 width=31) (actual time=105.675..105.684 rows=950 loops=1)
               Buckets: 1024  Batches: 1  Memory Usage: 69kB
               ->  Seq Scan on lc08_l1tp_019036_b5_albers rast1  (cost=0.00..176.50 rows=950 width=31) (actual time=0.631..105.061 rows=950 loops=1)
 Planning Time: 8.859 ms
 Execution Time: 253594.990 ms
**/ ;

--
\echo 'Try multiband for st_MapAlgebra';


create table lc08_l1tp_019036_b4_b5_albers as
SELECT rast1.rid,
       ST_AddBand(rast1.rast, rast2.rast) as newrast
FROM lc08_l1tp_019036_b5_albers rast1
join lc08_l1tp_019036_b4_albers rast2 ON rast1.rid = rast2.rid ;

-- TODO adding timing

drop table ndvi_test_all_records_multi;

EXPLAIN ANALYSE
CREATE TABLE ndvi_test_all_records_multi as
SELECT raster_mapalgebra_test(rast1.rast,
                              1,
                              rast1.rast,
                              2)
FROM lc08_l1tp_019036_b5_albers rast1;

--Execution Time: 292825.020 ms
 --try ndvi with smaller tile sizes
 --Remove the empty tiles

update lc08_l1tp_019036_b4_albers_50x
set rast = ST_SetBandNoDataValue(rast, 1, 0);


update lc08_l1tp_019036_b5_albers_50x
set rast = ST_SetBandNoDataValue(rast, 1, 0);


delete
from lc08_l1tp_019036_b4_albers_50x
where rid in
    (select rid
     from
       (select rid,
               ST_BandIsNoData(rast, 1, true) as isEmpty
        from lc08_l1tp_019036_b4_albers_50x)a
     where isEmpty = true );

;


delete
from lc08_l1tp_019036_b5_albers_50x
where rid in
    (select rid
     from
       (select rid,
               ST_BandIsNoData(rast, 1, true) as isEmpty
        from lc08_l1tp_019036_b5_albers_50x)a
     where isEmpty = true );

;

\echo 'Run NDVI with built in st_MapAlgebra on all records with tilesize 50x50';


drop table ndvi_test_all_records_50x;

EXPLAIN ANALYSE
CREATE TABLE ndvi_test_all_records_50x as
SELECT ST_MapAlgebra(rast1.rast,
                     1,
                     rast2.rast,
                     1,
                     '([rast1] - [rast2]) / ([rast1] + [rast2])::float',
                     '16BUI')
FROM lc08_l1tp_019036_b5_albers_50x rast1
join lc08_l1tp_019036_b4_albers_50x rast2 ON rast1.rid = rast2.rid ;

/**
Gather  (cost=1118.64..3790.17 rows=16873 width=32) (actual time=165.595..242860.226 rows=16873 loops=1)
  Workers Planned: 1
  Workers Launched: 1
  Single Copy: true
  ->  Hash Join  (cost=1108.64..2092.87 rows=16873 width=32) (actual time=33.151..245872.878 rows=16873 loops=1)
        Hash Cond: (rast2.rid = rast1.rid)
        ->  Seq Scan on lc08_l1tp_019036_b4_albers_50x rast2  (cost=0.00..897.74 rows=16874 width=33) (actual time=0.473..86.727 rows=16874 loops=1)
        ->  Hash  (cost=897.73..897.73 rows=16873 width=33) (actual time=17.503..17.510 rows=16873 loops=1)
              Buckets: 32768  Batches: 1  Memory Usage: 1364kB
              ->  Seq Scan on lc08_l1tp_019036_b5_albers_50x rast1  (cost=0.00..897.73 rows=16873 width=33) (actual time=0.456..10.167 rows=16873 loops=1)
Planning Time: 23.587 ms
Execution Time: 269383.031 ms
**/;

--
-- run summary stats for buffers around points
--
 \echo 'Run generate points within the bounding box of raster';


drop table raster_point_buffer_data;


create table raster_point_buffer_data(id bigint PRIMARY KEY GENERATED BY DEFAULT AS IDENTITY, geom geometry(POINT,5070), geom_buff geometry(Polygon,5070));

;

EXPLAIN analyse
create table raster_point_buffer_data(id, geom, geom_buff) as
select row_number() OVER () as id,
                         geom,
                         ST_Buffer(geom,50, 'quad_segs=1')
from
  (SELECT (ST_Dump(ST_GeneratePoints(geomBox, 1000000))).geom
   FROM
     (select 1 as id,
             ST_SetSRID(st_extent(a.geom),5070) as geomBox
      from
        (SELECT ST_Collect(ARRAY
                             (SELECT ST_Envelope(rast) as rastEnv
                              FROM lc08_l1tp_019036_b4_albers)) as geom) a) AS s) as b;

;

/**
-- NOTE I really expected this to at least kick in with some parallel plans?
WindowAgg  (cost=201.14..52766.67 rows=1000 width=72) (actual time=1899.585..97363.138 rows=1000000 loops=1)
  ->  Result  (cost=201.14..27744.17 rows=1000 width=32) (actual time=1897.740..10338.328 rows=1000000 loops=1)
        ->  ProjectSet  (cost=201.14..234.16 rows=1000 width=32) (actual time=1897.733..9449.816 rows=1000000 loops=1)
              ->  Aggregate  (cost=201.14..201.65 rows=1 width=36) (actual time=148.443..148.445 rows=1 loops=1)
                    InitPlan 1 (returns $0)
                      ->  Seq Scan on lc08_l1tp_019036_b4_albers  (cost=0.00..200.88 rows=950 width=32) (actual time=3.265..147.076 rows=950 loops=1)
                    ->  Result  (cost=0.00..0.01 rows=1 width=0) (actual time=0.002..0.002 rows=1 loops=1)
Planning Time: 0.239 ms
Execution Time: 105531.531 ms
**/ ;

--add indexes

create index raster_point_geom_idx on raster_point_buffer_data using GIST (geom);


create index raster_point_geom_buff_idx on raster_point_buffer_data using GIST (geom_buff);

/**
 * Add spatial index on raster
 */
CREATE INDEX lc08_l1tp_019036_b4_albers_rast_idx ON lc08_l1tp_019036_b4_albers USING gist(ST_ConvexHull(rast));

;


create table raster_buffer_statistic(id, buffer, rcount, rsum, rmean, rmin, rmax, stddev) as
SELECT id,
       50, (stats).count, (stats).sum, (stats).mean, (stats).min, (stats).max, (stats).stddev
from
  (select id,
          ST_SummaryStats(ST_Union(rast)) As stats
   from
     (SELECT id,
             ST_Clip(rast,geom_buff) as rast
      FROM lc08_l1tp_019036_b4_albers
      join raster_point_buffer_data feat ON ST_Intersects(feat.geom_buff,rast))a
   group by id)b ;

;

/**
Gather  (cost=310738.36..510238.57 rows=316667 width=60) (actual time=37974.630..449158.930 rows=864290 loops=1)
  Workers Planned: 1
  Workers Launched: 1
  Single Copy: true
  ->  Subquery Scan on b  (cost=310728.36..478561.87 rows=316667 width=60) (actual time=37814.805..449117.040 rows=864290 loops=1)
        ->  GroupAggregate  (cost=310728.36..475395.20 rows=316667 width=40) (actual time=37814.792..447231.203 rows=864290 loops=1)
              Group Key: feat.id
              ->  Sort  (cost=310728.36..311520.03 rows=316667 width=155) (actual time=37796.138..40286.450 rows=891227 loops=1)
                    Sort Key: feat.id
                    Worker 0:  Sort Method: external merge  Disk: 141616kB
                    ->  Nested Loop  (cost=1.04..267215.05 rows=316667 width=155) (actual time=11.761..35739.970 rows=891227 loops=1)
                          ->  Seq Scan on lc08_l1tp_019036_b4_albers  (cost=0.00..198.50 rows=950 width=27) (actual time=0.123..3.283 rows=950 loops=1)
                          ->  Index Scan using raster_point_geom_buff_idx on raster_point_buffer_data feat  (cost=1.04..280.74 rows=33 width=128) (actual time=0.179..37.142 rows=938 loops=950)
                                Index Cond: (geom_buff && (lc08_l1tp_019036_b4_albers.rast)::geometry)
                                Filter: _st_intersects(geom_buff, lc08_l1tp_019036_b4_albers.rast, NULL::integer)
                                Rows Removed by Filter: 0
Planning Time: 2.812 ms
Execution Time: 457200.663 ms ~ 7.5 minutes
**/ ;

--TODO try buffer overlap with smaller tile size