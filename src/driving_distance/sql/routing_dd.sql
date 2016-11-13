--
-- Copyright (c) 2005 Sylvain Pasche,
--               2006-2007 Anton A. Patrushev, Orkney, Inc.
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
--

-----------------------------------------------------------------------
-- Core function for driving distance.
-- The sql should return edge and vertex ids.
-----------------------------------------------------------------------
/*
CREATE OR REPLACE FUNCTION pgr_drivingDistance(sql text, source_id integer, distance float8, directed boolean, has_reverse_cost boolean)
    RETURNS SETOF pgr_costResultBig
    AS '$libdir/librouting_dd', 'driving_distance' -- is a comment
    LANGUAGE c IMMUTABLE STRICT;
*/
CREATE OR REPLACE FUNCTION _pgr_drivingDistance(sql text, start_v bigint, distance float8, directed boolean, has_rcost boolean,
       OUT seq integer, OUT node bigint, OUT edge bigint, OUT cost float, OUT agg_cost float)
  RETURNS SETOF RECORD AS
     '$libdir/librouting-2.1', 'driving_distance'
 LANGUAGE c IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION _pgr_drivingDistance(sql text, start_v anyarray, distance float8, directed boolean, equicost boolean, has_rcost boolean,
       OUT seq integer, OUT start_v bigint, OUT node bigint, OUT edge bigint, OUT cost float, OUT agg_cost float)
  RETURNS SETOF RECORD AS
     '$libdir/librouting-2.1', 'driving_many_to_dist'
 LANGUAGE c IMMUTABLE STRICT;


-- OLD SIGNATURE
CREATE OR REPLACE FUNCTION pgr_drivingDistance(sql text, source bigint, distance float8, directed boolean, has_rcost boolean)
  RETURNS SETOF pgr_costresult AS
  $BODY$
  DECLARE
  has_reverse boolean;
  BEGIN
      -- old signature, things are int and float8 only
      has_reverse =_pgr_parameter_check('driving', sql, false);

      if (has_reverse != has_rcost) then
         if (has_reverse) then --raise NOTICE 'has_rcost set to false but reverse_cost column found, Ignoring';
         else raise EXCEPTION 'has_rcost set to true but reverse_cost not found';
         end if;
      end if;

      return query SELECT seq-1 as seq, node::integer as id1, edge::integer as id2, agg_cost as cost
                FROM _pgr_drivingDistance(sql, source, distance, directed, has_rcost);
  END
  $BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100
  ROWS 1000;


CREATE OR REPLACE FUNCTION pgr_drivingDistance(sql text, start_v bigint, distance float8,
       OUT seq integer, OUT node bigint, OUT edge bigint, OUT cost float, OUT agg_cost float)
  RETURNS SETOF RECORD AS
  $BODY$
  DECLARE
  has_rcost boolean;
  BEGIN
      has_rcost =_pgr_parameter_check('driving', sql, true);
      return query SELECT *
                FROM _pgr_drivingDistance(sql, start_v, distance, true, has_rcost);
  END
  $BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100
  ROWS 1000;


CREATE OR REPLACE FUNCTION pgr_drivingDistance(sql text, start_v bigint, distance float8, directed boolean,
       OUT seq integer, OUT node bigint, OUT edge bigint, OUT cost float, OUT agg_cost float)
  RETURNS SETOF RECORD AS
  $BODY$
  DECLARE
  has_rcost boolean;
  BEGIN
      has_rcost =_pgr_parameter_check('driving', sql, true);
      return query SELECT *
                FROM _pgr_drivingDistance(sql, start_v, distance, directed, has_rcost);
  END
  $BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100
  ROWS 1000;

CREATE OR REPLACE FUNCTION pgr_drivingDistance(sql text, start_v anyarray, distance float8, directed boolean default true, equicost boolean default false,
       OUT seq integer, OUT from_v bigint, OUT node bigint, OUT edge bigint, OUT cost float, OUT agg_cost float)
  RETURNS SETOF RECORD AS
  $BODY$
  DECLARE
  has_rcost boolean;
  BEGIN
      has_rcost =_pgr_parameter_check('driving', sql, true);
      return query SELECT *
                FROM _pgr_drivingDistance(sql, start_v, distance, directed, equicost, has_rcost);
  END
  $BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100
  ROWS 1000;




-----------------------------------------------------------------------
-- Core function for alpha shape computation.
-- The sql should return vertex ids and x,y values. Return ordered
-- vertex ids. 
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pgr_alphashape(sql text, alpha float8 DEFAULT 0, OUT x float8, OUT y float8)
    RETURNS SETOF record
    AS '$libdir/librouting-2.1', 'alphashape'
    LANGUAGE c IMMUTABLE STRICT;

----------------------------------------------------------
-- Draws an alpha shape around given set of points.
-- ** This should be rewritten as an aggregate. **
----------------------------------------------------------
CREATE OR REPLACE FUNCTION pgr_pointsAsPolygon(query varchar, alpha float8 DEFAULT 0)
	RETURNS geometry AS
	$$
	DECLARE
		r record;
		geoms geometry[];
		vertex_result record;
		i int;
		n int;
		spos int;
		q text;
		x float8[];
		y float8[];

	BEGIN
		geoms := array[]::geometry[];
		i := 1;

		FOR vertex_result IN EXECUTE 'SELECT x, y FROM pgr_alphashape('''|| query || ''', ' || alpha || ')' 
		LOOP
			x[i] = vertex_result.x;
			y[i] = vertex_result.y;
			i := i+1;
		END LOOP;

		n := i;
		IF n = 1 THEN
			RAISE NOTICE 'n = 1';
			RETURN NULL;
		END IF;

		spos := 1;
		q := 'SELECT ST_GeometryFromText(''POLYGON((';
		FOR i IN 1..n LOOP
			IF x[i] IS NULL AND y[i] IS NULL THEN
				q := q || ', ' || x[spos] || ' ' || y[spos] || '))'',0) AS geom;';
				EXECUTE q INTO r;
				geoms := geoms || array[r.geom];
				q := '';
			ELSE
				IF q = '' THEN
					spos := i;
					q := 'SELECT ST_GeometryFromText(''POLYGON((';
				END IF;
				IF i = spos THEN
					q := q || x[spos] || ' ' || y[spos];
				ELSE
					q := q || ', ' || x[i] || ' ' || y[i];
				END IF;
			END IF;
		END LOOP;

		RETURN ST_BuildArea(ST_Collect(geoms));
	END;
	$$
	LANGUAGE 'plpgsql' VOLATILE STRICT;

