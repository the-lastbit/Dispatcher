--
-- PostgreSQL database dump
--

-- Dumped from database version 14.1 (Debian 14.1-1.pgdg110+1)
-- Dumped by pg_dump version 14.1 (Debian 14.1-1.pgdg110+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: api; Type: SCHEMA; Schema: -; Owner: admin
--

CREATE SCHEMA api;


ALTER SCHEMA api OWNER TO admin;

--
-- Name: db; Type: SCHEMA; Schema: -; Owner: admin
--

CREATE SCHEMA db;


ALTER SCHEMA db OWNER TO admin;

--
-- Name: news; Type: SCHEMA; Schema: -; Owner: admin
--

CREATE SCHEMA news;


ALTER SCHEMA news OWNER TO admin;

--
-- Name: access(); Type: FUNCTION; Schema: api; Owner: admin
--

CREATE FUNCTION api.access() RETURNS boolean
    LANGUAGE sql
    RETURN true;


ALTER FUNCTION api.access() OWNER TO admin;

--
-- Name: market_sentiment_daily(); Type: FUNCTION; Schema: api; Owner: admin
--

CREATE FUNCTION api.market_sentiment_daily() RETURNS TABLE(id_instrument character varying, sum_analysis integer, count_analysis integer, calculation double precision, last_update timestamp without time zone, symbol character varying, description character varying, name character varying)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
	RETURN QUERY EXECUTE FORMAT(E'SELECT * FROM db.tops');
END  
$$;


ALTER FUNCTION api.market_sentiment_daily() OWNER TO admin;

--
-- Name: market_sentiment_monthly(); Type: FUNCTION; Schema: api; Owner: admin
--

CREATE FUNCTION api.market_sentiment_monthly() RETURNS TABLE(id_instrument character varying, sum_analysis integer, count_analysis integer, calculation double precision, last_update timestamp with time zone, symbol character varying, description character varying, name character varying)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
	RETURN QUERY EXECUTE FORMAT(E'SELECT * FROM db.heatmap');
END  
$$;


ALTER FUNCTION api.market_sentiment_monthly() OWNER TO admin;

--
-- Name: obtain_analysis(timestamp with time zone, character varying); Type: FUNCTION; Schema: api; Owner: admin
--

CREATE FUNCTION api.obtain_analysis(date_ timestamp with time zone, symbol character varying) RETURNS TABLE(download_time timestamp with time zone, analysis smallint)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    text_in_date TEXT;
    perm_view_name TEXT;
    child_table_name TEXT;
    table_ INTEGER;
BEGIN
    text_in_date := to_char(date_, 'YYYY_MM');
    child_table_name := symbol || '_news_from_' || text_in_date;
    perm_view_name := 'view_' || symbol || '_' || text_in_date;
    table_ := (SELECT 1 FROM information_schema.tables WHERE table_name = perm_view_name);
      
IF table_ = 1
THEN
    RETURN QUERY EXECUTE FORMAT(E'SELECT * FROM api.%I', perm_view_name);
ELSE
    RETURN QUERY EXECUTE FORMAT(E'SELECT download_time, analysis FROM news.%I', child_table_name);
END IF;
END  
$$;


ALTER FUNCTION api.obtain_analysis(date_ timestamp with time zone, symbol character varying) OWNER TO admin;

--
-- Name: check_register_symbol(character varying); Type: FUNCTION; Schema: db; Owner: admin
--

CREATE FUNCTION db.check_register_symbol(symbol_ character varying) RETURNS void
    LANGUAGE plpgsql
    AS $_$#variable_conflict use_column
DECLARE
	partition_name TEXT;
BEGIN    
 	partition_name := symbol_ || '_partition';
IF NOT EXISTS
	(SELECT 1
   	 FROM   information_schema.tables
   	 WHERE  table_name = partition_name) 
THEN
    EXECUTE 'CREATE TABLE db.'
            || quote_ident(partition_name)
            || ' PARTITION OF db.scraped_news_reference FOR VALUES IN ('
            || quote_literal(symbol_)
            || ')';
	--EXECUTE FORMAT(E'CREATE TABLE db.%I PARTITION OF db.scraped_news_reference FOR VALUES IN($1)', partition_name) USING check_register_symbol.symbol_;
END IF;
END$_$;


ALTER FUNCTION db.check_register_symbol(symbol_ character varying) OWNER TO admin;

--
-- Name: heatmap_data(); Type: FUNCTION; Schema: db; Owner: admin
--

CREATE FUNCTION db.heatmap_data() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$DECLARE
    current_month TIMESTAMP;
    date_ TIMESTAMP;
    record_month TIMESTAMP;
    current_count_analysis INTEGER;
    value_ INTEGER;
    sum_analysis_ INTEGER;
    count_analysis_ INTEGER;
    calculation_ FLOAT; 
BEGIN
    current_month := (SELECT DATE_TRUNC('month', now()));
    date_ := (SELECT last_update FROM db.heatmap h WHERE h.id_instrument = NEW.id_instrument);
    record_month := (SELECT DATE_TRUNC('month', date_));
    current_count_analysis := (SELECT count_analysis FROM db.heatmap WHERE id_instrument = NEW.id_instrument);
    value_ := (SELECT CASE WHEN NEW.analysis > 0 THEN 1 ELSE -1 END);
    sum_analysis_ := (SELECT sum_analysis FROM db.heatmap WHERE id_instrument = NEW.id_instrument) + (value_);
    count_analysis_ := (current_count_analysis + 1);
    calculation_ = (select sum_analysis_::float/count_analysis_);
IF current_count_analysis = 0 
THEN
	EXECUTE format(E'UPDATE db.heatmap h SET(sum_analysis, count_analysis, calculation, last_update) = ($1, 1, $2, $3) WHERE h.id_instrument = $4') USING NEW.analysis, NEW.analysis, NEW.download_time, NEW.id_instrument;
ELSIF current_month > record_month
THEN
	EXECUTE format(E'UPDATE db.heatmap h SET(sum_analysis, count_analysis, calculation, last_update) = ($1, 1, $2, $3) WHERE h.id_instrument = $4') USING NEW.analysis, NEW.analysis, NEW.download_time, NEW.id_instrument;
ELSE
    EXECUTE format(E'UPDATE db.heatmap h SET(sum_analysis, count_analysis, calculation, last_update) = (%L, %L, %L, $1) WHERE h.id_instrument = $2', sum_analysis_, count_analysis_, calculation_) USING NEW.download_time, NEW.id_instrument;
END IF;
RETURN NULL;
END$_$;


ALTER FUNCTION db.heatmap_data() OWNER TO admin;

--
-- Name: montly_news(); Type: FUNCTION; Schema: db; Owner: admin
--

CREATE FUNCTION db.montly_news() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$DECLARE
	partition_date TEXT;
	partition_name TEXT;
    instrument TEXT;
	start_of_month TEXT;
	end_of_next_month TEXT;
BEGIN
    instrument := (SELECT symbol FROM db.instruments as instrument WHERE instrument.cusip = NEW.id_instrument);
	partition_date := to_char(NEW.download_time,'YYYY_MM');
 	partition_name := instrument || '_news_from_' || partition_date;
IF NOT EXISTS
	(SELECT 1
   	 FROM   information_schema.tables 
   	 WHERE  table_name = partition_name) 
THEN
    -- Creation of valid dates
	start_of_month := to_char((NEW.download_time),'YYYY-MM') || '-01';
	end_of_next_month := to_char((NEW.download_time + interval '1 month'),'YYYY-MM') || '-01';
	EXECUTE format(E'CREATE TABLE news.%I (CHECK ( date_trunc(\'day\', download_time) >= ''%s'' AND date_trunc(\'day\', download_time) < ''%s'')) INHERITS (news.news)', partition_name, start_of_month,end_of_next_month);
END IF;
  EXECUTE format(E'INSERT INTO news.%I (title, description, pubdate, download_time, id_instrument, analysis) VALUES($1,$2,$3,$4,$5,$6)', partition_name) using NEW.title, NEW.description, NEW.pubdate, NEW.download_time, NEW.id_instrument, NEW.analysis;
RETURN NEW;
END$_$;


ALTER FUNCTION db.montly_news() OWNER TO admin;

--
-- Name: tops_data(); Type: FUNCTION; Schema: db; Owner: admin
--

CREATE FUNCTION db.tops_data() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$DECLARE
    current_day_ TIMESTAMP;
    date__ TIMESTAMP;
    record_day_ TIMESTAMP;
    current_count_analysis_ INTEGER;
    sum_analysis__ INTEGER;
    value_ INTEGER;
    count_analysis__ INTEGER;
    calculation__ FLOAT; 
BEGIN
    current_day_ := (SELECT DATE_TRUNC('day', now()));
    date__ := (SELECT last_update FROM db.tops h WHERE h.id_instrument = NEW.id_instrument);
    record_day_ := (SELECT DATE_TRUNC('day', date__));
    current_count_analysis_ := (SELECT count_analysis FROM db.tops WHERE id_instrument = NEW.id_instrument);
    value_ := (SELECT CASE WHEN NEW.analysis > 0 THEN 1 ELSE -1 END);
    sum_analysis__ :=(SELECT (SELECT sum_analysis FROM db.tops WHERE id_instrument = NEW.id_instrument) + (value_));
    count_analysis__ := (current_count_analysis_ + 1);
    calculation__ = (select sum_analysis__::float/count_analysis__);
IF current_count_analysis_ = 0
THEN
	EXECUTE format(E'UPDATE db.tops t SET(sum_analysis, count_analysis, calculation, last_update) = ($1, 1, $2, $3) WHERE t.id_instrument = $4') USING NEW.analysis, NEW.analysis, NEW.download_time, NEW.id_instrument;
ELSIF current_day_ > record_day_
THEN
	EXECUTE format(E'UPDATE db.tops t SET(sum_analysis, count_analysis, calculation, last_update) = ($1, 1, $2, $3) WHERE t.id_instrument = $4') USING NEW.analysis, NEW.analysis, NEW.download_time, NEW.id_instrument;
ELSE
    EXECUTE format(E'UPDATE db.tops t SET(sum_analysis, count_analysis, calculation, last_update) = (%L, %L, %L, $1) WHERE t.id_instrument = $2', sum_analysis__, count_analysis__, calculation__) USING NEW.download_time, NEW.id_instrument;
END IF;
RETURN NULL;
END$_$;


ALTER FUNCTION db.tops_data() OWNER TO admin;

SET default_tablespace = '';

--
-- Name: scraped_news_reference; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.scraped_news_reference (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
)
PARTITION BY LIST (symbol);


ALTER TABLE db.scraped_news_reference OWNER TO admin;

SET default_table_access_method = heap;

--
-- Name: a_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.a_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.a_partition OWNER TO admin;

--
-- Name: aal_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.aal_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.aal_partition OWNER TO admin;

--
-- Name: aap_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.aap_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.aap_partition OWNER TO admin;

--
-- Name: aapl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.aapl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.aapl_partition OWNER TO admin;

--
-- Name: abbv_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.abbv_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.abbv_partition OWNER TO admin;

--
-- Name: abc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.abc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.abc_partition OWNER TO admin;

--
-- Name: abmd_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.abmd_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.abmd_partition OWNER TO admin;

--
-- Name: abt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.abt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.abt_partition OWNER TO admin;

--
-- Name: acn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.acn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.acn_partition OWNER TO admin;

--
-- Name: adbe_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.adbe_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.adbe_partition OWNER TO admin;

--
-- Name: adi_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.adi_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.adi_partition OWNER TO admin;

--
-- Name: adm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.adm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.adm_partition OWNER TO admin;

--
-- Name: adp_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.adp_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.adp_partition OWNER TO admin;

--
-- Name: adsk_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.adsk_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.adsk_partition OWNER TO admin;

--
-- Name: aee_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.aee_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.aee_partition OWNER TO admin;

--
-- Name: aep_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.aep_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.aep_partition OWNER TO admin;

--
-- Name: aes_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.aes_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.aes_partition OWNER TO admin;

--
-- Name: afl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.afl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.afl_partition OWNER TO admin;

--
-- Name: aig_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.aig_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.aig_partition OWNER TO admin;

--
-- Name: aiz_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.aiz_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.aiz_partition OWNER TO admin;

--
-- Name: ajg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ajg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ajg_partition OWNER TO admin;

--
-- Name: akam_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.akam_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.akam_partition OWNER TO admin;

--
-- Name: alb_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.alb_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.alb_partition OWNER TO admin;

--
-- Name: algn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.algn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.algn_partition OWNER TO admin;

--
-- Name: alk_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.alk_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.alk_partition OWNER TO admin;

--
-- Name: all_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.all_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.all_partition OWNER TO admin;

--
-- Name: alle_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.alle_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.alle_partition OWNER TO admin;

--
-- Name: amat_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.amat_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.amat_partition OWNER TO admin;

--
-- Name: amcr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.amcr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.amcr_partition OWNER TO admin;

--
-- Name: amd_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.amd_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.amd_partition OWNER TO admin;

--
-- Name: ame_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ame_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ame_partition OWNER TO admin;

--
-- Name: amgn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.amgn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.amgn_partition OWNER TO admin;

--
-- Name: amp_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.amp_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.amp_partition OWNER TO admin;

--
-- Name: amt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.amt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.amt_partition OWNER TO admin;

--
-- Name: amzn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.amzn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.amzn_partition OWNER TO admin;

--
-- Name: anet_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.anet_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.anet_partition OWNER TO admin;

--
-- Name: anss_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.anss_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.anss_partition OWNER TO admin;

--
-- Name: antm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.antm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.antm_partition OWNER TO admin;

--
-- Name: aon_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.aon_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.aon_partition OWNER TO admin;

--
-- Name: aos_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.aos_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.aos_partition OWNER TO admin;

--
-- Name: apa_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.apa_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.apa_partition OWNER TO admin;

--
-- Name: apd_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.apd_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.apd_partition OWNER TO admin;

--
-- Name: aph_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.aph_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.aph_partition OWNER TO admin;

--
-- Name: aptv_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.aptv_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.aptv_partition OWNER TO admin;

--
-- Name: are_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.are_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.are_partition OWNER TO admin;

--
-- Name: ato_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ato_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ato_partition OWNER TO admin;

--
-- Name: atvi_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.atvi_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.atvi_partition OWNER TO admin;

--
-- Name: avb_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.avb_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.avb_partition OWNER TO admin;

--
-- Name: avgo_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.avgo_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.avgo_partition OWNER TO admin;

--
-- Name: avy_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.avy_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.avy_partition OWNER TO admin;

--
-- Name: awk_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.awk_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.awk_partition OWNER TO admin;

--
-- Name: axp_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.axp_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.axp_partition OWNER TO admin;

--
-- Name: azo_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.azo_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.azo_partition OWNER TO admin;

--
-- Name: ba_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ba_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ba_partition OWNER TO admin;

--
-- Name: bac_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.bac_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.bac_partition OWNER TO admin;

--
-- Name: bax_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.bax_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.bax_partition OWNER TO admin;

--
-- Name: bbwi_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.bbwi_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.bbwi_partition OWNER TO admin;

--
-- Name: bby_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.bby_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.bby_partition OWNER TO admin;

--
-- Name: bdx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.bdx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.bdx_partition OWNER TO admin;

--
-- Name: ben_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ben_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ben_partition OWNER TO admin;

--
-- Name: bf.b_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db."bf.b_partition" (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db."bf.b_partition" OWNER TO admin;

--
-- Name: biib_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.biib_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.biib_partition OWNER TO admin;

--
-- Name: bio_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.bio_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.bio_partition OWNER TO admin;

--
-- Name: bk_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.bk_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.bk_partition OWNER TO admin;

--
-- Name: bkng_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.bkng_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.bkng_partition OWNER TO admin;

--
-- Name: bkr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.bkr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.bkr_partition OWNER TO admin;

--
-- Name: blk_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.blk_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.blk_partition OWNER TO admin;

--
-- Name: bll_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.bll_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.bll_partition OWNER TO admin;

--
-- Name: bmy_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.bmy_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.bmy_partition OWNER TO admin;

--
-- Name: br_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.br_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.br_partition OWNER TO admin;

--
-- Name: brk.b_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db."brk.b_partition" (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db."brk.b_partition" OWNER TO admin;

--
-- Name: bro_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.bro_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.bro_partition OWNER TO admin;

--
-- Name: bsx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.bsx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.bsx_partition OWNER TO admin;

--
-- Name: bwa_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.bwa_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.bwa_partition OWNER TO admin;

--
-- Name: bxp_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.bxp_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.bxp_partition OWNER TO admin;

--
-- Name: c_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.c_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.c_partition OWNER TO admin;

--
-- Name: cag_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cag_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cag_partition OWNER TO admin;

--
-- Name: cah_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cah_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cah_partition OWNER TO admin;

--
-- Name: carr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.carr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.carr_partition OWNER TO admin;

--
-- Name: cat_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cat_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cat_partition OWNER TO admin;

--
-- Name: cb_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cb_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cb_partition OWNER TO admin;

--
-- Name: cboe_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cboe_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cboe_partition OWNER TO admin;

--
-- Name: cbre_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cbre_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cbre_partition OWNER TO admin;

--
-- Name: cci_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cci_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cci_partition OWNER TO admin;

--
-- Name: ccl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ccl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ccl_partition OWNER TO admin;

--
-- Name: cday_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cday_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cday_partition OWNER TO admin;

--
-- Name: cdns_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cdns_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cdns_partition OWNER TO admin;

--
-- Name: cdw_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cdw_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cdw_partition OWNER TO admin;

--
-- Name: ce_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ce_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ce_partition OWNER TO admin;

--
-- Name: ceg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ceg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ceg_partition OWNER TO admin;

--
-- Name: cern_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cern_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cern_partition OWNER TO admin;

--
-- Name: cf_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cf_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cf_partition OWNER TO admin;

--
-- Name: cfg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cfg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cfg_partition OWNER TO admin;

--
-- Name: chd_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.chd_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.chd_partition OWNER TO admin;

--
-- Name: chrw_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.chrw_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.chrw_partition OWNER TO admin;

--
-- Name: chtr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.chtr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.chtr_partition OWNER TO admin;

--
-- Name: ci_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ci_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ci_partition OWNER TO admin;

--
-- Name: cinf_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cinf_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cinf_partition OWNER TO admin;

--
-- Name: cl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cl_partition OWNER TO admin;

--
-- Name: clx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.clx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.clx_partition OWNER TO admin;

--
-- Name: cma_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cma_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cma_partition OWNER TO admin;

--
-- Name: cmcsa_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cmcsa_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cmcsa_partition OWNER TO admin;

--
-- Name: cme_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cme_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cme_partition OWNER TO admin;

--
-- Name: cmg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cmg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cmg_partition OWNER TO admin;

--
-- Name: cmi_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cmi_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cmi_partition OWNER TO admin;

--
-- Name: cms_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cms_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cms_partition OWNER TO admin;

--
-- Name: cnc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cnc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cnc_partition OWNER TO admin;

--
-- Name: cnp_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cnp_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cnp_partition OWNER TO admin;

--
-- Name: cof_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cof_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cof_partition OWNER TO admin;

--
-- Name: coo_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.coo_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.coo_partition OWNER TO admin;

--
-- Name: cop_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cop_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cop_partition OWNER TO admin;

--
-- Name: cost_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cost_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cost_partition OWNER TO admin;

--
-- Name: cpb_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cpb_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cpb_partition OWNER TO admin;

--
-- Name: cprt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cprt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cprt_partition OWNER TO admin;

--
-- Name: crl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.crl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.crl_partition OWNER TO admin;

--
-- Name: crm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.crm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.crm_partition OWNER TO admin;

--
-- Name: csco_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.csco_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.csco_partition OWNER TO admin;

--
-- Name: csx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.csx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.csx_partition OWNER TO admin;

--
-- Name: ctas_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ctas_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ctas_partition OWNER TO admin;

--
-- Name: ctlt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ctlt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ctlt_partition OWNER TO admin;

--
-- Name: ctra_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ctra_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ctra_partition OWNER TO admin;

--
-- Name: ctsh_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ctsh_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ctsh_partition OWNER TO admin;

--
-- Name: ctva_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ctva_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ctva_partition OWNER TO admin;

--
-- Name: ctxs_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ctxs_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ctxs_partition OWNER TO admin;

--
-- Name: cvs_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cvs_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cvs_partition OWNER TO admin;

--
-- Name: cvx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.cvx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.cvx_partition OWNER TO admin;

--
-- Name: czr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.czr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.czr_partition OWNER TO admin;

--
-- Name: d_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.d_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.d_partition OWNER TO admin;

--
-- Name: dal_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dal_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dal_partition OWNER TO admin;

--
-- Name: dd_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dd_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dd_partition OWNER TO admin;

--
-- Name: de_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.de_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.de_partition OWNER TO admin;

--
-- Name: dfs_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dfs_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dfs_partition OWNER TO admin;

--
-- Name: dg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dg_partition OWNER TO admin;

--
-- Name: dgx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dgx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dgx_partition OWNER TO admin;

--
-- Name: dhi_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dhi_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dhi_partition OWNER TO admin;

--
-- Name: dhr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dhr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dhr_partition OWNER TO admin;

--
-- Name: dis_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dis_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dis_partition OWNER TO admin;

--
-- Name: disca_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.disca_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.disca_partition OWNER TO admin;

--
-- Name: disck_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.disck_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.disck_partition OWNER TO admin;

--
-- Name: dish_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dish_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dish_partition OWNER TO admin;

--
-- Name: dlr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dlr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dlr_partition OWNER TO admin;

--
-- Name: dltr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dltr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dltr_partition OWNER TO admin;

--
-- Name: dov_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dov_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dov_partition OWNER TO admin;

--
-- Name: dow_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dow_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dow_partition OWNER TO admin;

--
-- Name: dpz_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dpz_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dpz_partition OWNER TO admin;

--
-- Name: dre_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dre_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dre_partition OWNER TO admin;

--
-- Name: dri_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dri_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dri_partition OWNER TO admin;

--
-- Name: dte_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dte_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dte_partition OWNER TO admin;

--
-- Name: duk_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.duk_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.duk_partition OWNER TO admin;

--
-- Name: dva_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dva_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dva_partition OWNER TO admin;

--
-- Name: dvn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dvn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dvn_partition OWNER TO admin;

--
-- Name: dxc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dxc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dxc_partition OWNER TO admin;

--
-- Name: dxcm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.dxcm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.dxcm_partition OWNER TO admin;

--
-- Name: ea_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ea_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ea_partition OWNER TO admin;

--
-- Name: ebay_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ebay_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ebay_partition OWNER TO admin;

--
-- Name: ecl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ecl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ecl_partition OWNER TO admin;

--
-- Name: ed_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ed_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ed_partition OWNER TO admin;

--
-- Name: efx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.efx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.efx_partition OWNER TO admin;

--
-- Name: eix_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.eix_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.eix_partition OWNER TO admin;

--
-- Name: el_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.el_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.el_partition OWNER TO admin;

--
-- Name: emn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.emn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.emn_partition OWNER TO admin;

--
-- Name: emr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.emr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.emr_partition OWNER TO admin;

--
-- Name: enph_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.enph_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.enph_partition OWNER TO admin;

--
-- Name: eog_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.eog_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.eog_partition OWNER TO admin;

--
-- Name: epam_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.epam_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.epam_partition OWNER TO admin;

--
-- Name: eqix_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.eqix_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.eqix_partition OWNER TO admin;

--
-- Name: eqr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.eqr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.eqr_partition OWNER TO admin;

--
-- Name: es_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.es_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.es_partition OWNER TO admin;

--
-- Name: ess_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ess_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ess_partition OWNER TO admin;

--
-- Name: etn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.etn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.etn_partition OWNER TO admin;

--
-- Name: etr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.etr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.etr_partition OWNER TO admin;

--
-- Name: etsy_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.etsy_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.etsy_partition OWNER TO admin;

--
-- Name: evrg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.evrg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.evrg_partition OWNER TO admin;

--
-- Name: ew_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ew_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ew_partition OWNER TO admin;

--
-- Name: exc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.exc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.exc_partition OWNER TO admin;

--
-- Name: expd_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.expd_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.expd_partition OWNER TO admin;

--
-- Name: expe_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.expe_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.expe_partition OWNER TO admin;

--
-- Name: exr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.exr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.exr_partition OWNER TO admin;

--
-- Name: f_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.f_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.f_partition OWNER TO admin;

--
-- Name: fang_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.fang_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.fang_partition OWNER TO admin;

--
-- Name: fast_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.fast_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.fast_partition OWNER TO admin;

--
-- Name: fb_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.fb_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.fb_partition OWNER TO admin;

--
-- Name: fbhs_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.fbhs_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.fbhs_partition OWNER TO admin;

--
-- Name: fcx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.fcx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.fcx_partition OWNER TO admin;

--
-- Name: fds_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.fds_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.fds_partition OWNER TO admin;

--
-- Name: fdx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.fdx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.fdx_partition OWNER TO admin;

--
-- Name: fe_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.fe_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.fe_partition OWNER TO admin;

--
-- Name: ffiv_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ffiv_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ffiv_partition OWNER TO admin;

--
-- Name: fis_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.fis_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.fis_partition OWNER TO admin;

--
-- Name: fisv_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.fisv_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.fisv_partition OWNER TO admin;

--
-- Name: fitb_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.fitb_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.fitb_partition OWNER TO admin;

--
-- Name: flt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.flt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.flt_partition OWNER TO admin;

--
-- Name: fmc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.fmc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.fmc_partition OWNER TO admin;

--
-- Name: fox_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.fox_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.fox_partition OWNER TO admin;

--
-- Name: foxa_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.foxa_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.foxa_partition OWNER TO admin;

--
-- Name: frc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.frc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.frc_partition OWNER TO admin;

--
-- Name: frt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.frt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.frt_partition OWNER TO admin;

--
-- Name: ftnt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ftnt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ftnt_partition OWNER TO admin;

--
-- Name: ftv_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ftv_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ftv_partition OWNER TO admin;

--
-- Name: gd_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.gd_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.gd_partition OWNER TO admin;

--
-- Name: ge_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ge_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ge_partition OWNER TO admin;

--
-- Name: gild_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.gild_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.gild_partition OWNER TO admin;

--
-- Name: gis_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.gis_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.gis_partition OWNER TO admin;

--
-- Name: gl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.gl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.gl_partition OWNER TO admin;

--
-- Name: glw_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.glw_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.glw_partition OWNER TO admin;

--
-- Name: gm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.gm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.gm_partition OWNER TO admin;

--
-- Name: gnrc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.gnrc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.gnrc_partition OWNER TO admin;

--
-- Name: goog_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.goog_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.goog_partition OWNER TO admin;

--
-- Name: googl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.googl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.googl_partition OWNER TO admin;

--
-- Name: gpc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.gpc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.gpc_partition OWNER TO admin;

--
-- Name: gpn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.gpn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.gpn_partition OWNER TO admin;

--
-- Name: grmn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.grmn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.grmn_partition OWNER TO admin;

--
-- Name: gs_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.gs_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.gs_partition OWNER TO admin;

--
-- Name: gww_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.gww_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.gww_partition OWNER TO admin;

--
-- Name: hal_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hal_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hal_partition OWNER TO admin;

--
-- Name: has_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.has_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.has_partition OWNER TO admin;

--
-- Name: hban_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hban_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hban_partition OWNER TO admin;

--
-- Name: hca_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hca_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hca_partition OWNER TO admin;

--
-- Name: hd_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hd_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hd_partition OWNER TO admin;

--
-- Name: heatmap; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.heatmap (
    id_instrument character varying(12) NOT NULL,
    sum_analysis integer DEFAULT 0 NOT NULL,
    count_analysis integer DEFAULT 0 NOT NULL,
    calculation double precision DEFAULT 0.0 NOT NULL,
    last_update timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    symbol character varying NOT NULL,
    description character varying NOT NULL,
    name character varying NOT NULL
);


ALTER TABLE db.heatmap OWNER TO admin;

--
-- Name: hes_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hes_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hes_partition OWNER TO admin;

--
-- Name: hig_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hig_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hig_partition OWNER TO admin;

--
-- Name: hii_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hii_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hii_partition OWNER TO admin;

--
-- Name: hlt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hlt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hlt_partition OWNER TO admin;

--
-- Name: holx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.holx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.holx_partition OWNER TO admin;

--
-- Name: hon_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hon_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hon_partition OWNER TO admin;

--
-- Name: hpe_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hpe_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hpe_partition OWNER TO admin;

--
-- Name: hpq_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hpq_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hpq_partition OWNER TO admin;

--
-- Name: hrl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hrl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hrl_partition OWNER TO admin;

--
-- Name: hsic_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hsic_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hsic_partition OWNER TO admin;

--
-- Name: hst_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hst_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hst_partition OWNER TO admin;

--
-- Name: hsy_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hsy_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hsy_partition OWNER TO admin;

--
-- Name: hum_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hum_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hum_partition OWNER TO admin;

--
-- Name: hwm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.hwm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.hwm_partition OWNER TO admin;

--
-- Name: ibm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ibm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ibm_partition OWNER TO admin;

--
-- Name: ice_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ice_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ice_partition OWNER TO admin;

--
-- Name: idxx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.idxx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.idxx_partition OWNER TO admin;

--
-- Name: iex_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.iex_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.iex_partition OWNER TO admin;

--
-- Name: iff_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.iff_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.iff_partition OWNER TO admin;

--
-- Name: ilmn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ilmn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ilmn_partition OWNER TO admin;

--
-- Name: incy_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.incy_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.incy_partition OWNER TO admin;

--
-- Name: info_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.info_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.info_partition OWNER TO admin;

--
-- Name: instruments; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.instruments (
    cusip character varying NOT NULL,
    symbol character varying NOT NULL,
    description character varying NOT NULL,
    exchange character varying NOT NULL,
    assettype character varying NOT NULL
);


ALTER TABLE db.instruments OWNER TO admin;

--
-- Name: intc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.intc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.intc_partition OWNER TO admin;

--
-- Name: intu_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.intu_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.intu_partition OWNER TO admin;

--
-- Name: ip_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ip_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ip_partition OWNER TO admin;

--
-- Name: ipg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ipg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ipg_partition OWNER TO admin;

--
-- Name: ipgp_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ipgp_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ipgp_partition OWNER TO admin;

--
-- Name: iqv_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.iqv_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.iqv_partition OWNER TO admin;

--
-- Name: ir_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ir_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ir_partition OWNER TO admin;

--
-- Name: irm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.irm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.irm_partition OWNER TO admin;

--
-- Name: isrg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.isrg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.isrg_partition OWNER TO admin;

--
-- Name: it_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.it_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.it_partition OWNER TO admin;

--
-- Name: itw_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.itw_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.itw_partition OWNER TO admin;

--
-- Name: ivz_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ivz_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ivz_partition OWNER TO admin;

--
-- Name: j_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.j_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.j_partition OWNER TO admin;

--
-- Name: jbht_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.jbht_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.jbht_partition OWNER TO admin;

--
-- Name: jci_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.jci_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.jci_partition OWNER TO admin;

--
-- Name: jkhy_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.jkhy_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.jkhy_partition OWNER TO admin;

--
-- Name: jnj_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.jnj_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.jnj_partition OWNER TO admin;

--
-- Name: jnpr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.jnpr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.jnpr_partition OWNER TO admin;

--
-- Name: jpm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.jpm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.jpm_partition OWNER TO admin;

--
-- Name: k_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.k_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.k_partition OWNER TO admin;

--
-- Name: key_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.key_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.key_partition OWNER TO admin;

--
-- Name: keys_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.keys_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.keys_partition OWNER TO admin;

--
-- Name: khc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.khc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.khc_partition OWNER TO admin;

--
-- Name: kim_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.kim_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.kim_partition OWNER TO admin;

--
-- Name: klac_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.klac_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.klac_partition OWNER TO admin;

--
-- Name: kmb_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.kmb_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.kmb_partition OWNER TO admin;

--
-- Name: kmi_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.kmi_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.kmi_partition OWNER TO admin;

--
-- Name: kmx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.kmx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.kmx_partition OWNER TO admin;

--
-- Name: ko_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ko_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ko_partition OWNER TO admin;

--
-- Name: kr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.kr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.kr_partition OWNER TO admin;

--
-- Name: l_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.l_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.l_partition OWNER TO admin;

--
-- Name: ldos_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ldos_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ldos_partition OWNER TO admin;

--
-- Name: len_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.len_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.len_partition OWNER TO admin;

--
-- Name: lh_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.lh_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.lh_partition OWNER TO admin;

--
-- Name: lhx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.lhx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.lhx_partition OWNER TO admin;

--
-- Name: lin_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.lin_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.lin_partition OWNER TO admin;

--
-- Name: lkq_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.lkq_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.lkq_partition OWNER TO admin;

--
-- Name: lly_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.lly_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.lly_partition OWNER TO admin;

--
-- Name: lmt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.lmt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.lmt_partition OWNER TO admin;

--
-- Name: lnc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.lnc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.lnc_partition OWNER TO admin;

--
-- Name: lnt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.lnt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.lnt_partition OWNER TO admin;

--
-- Name: low_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.low_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.low_partition OWNER TO admin;

--
-- Name: lrcx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.lrcx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.lrcx_partition OWNER TO admin;

--
-- Name: lumn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.lumn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.lumn_partition OWNER TO admin;

--
-- Name: luv_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.luv_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.luv_partition OWNER TO admin;

--
-- Name: lvs_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.lvs_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.lvs_partition OWNER TO admin;

--
-- Name: lw_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.lw_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.lw_partition OWNER TO admin;

--
-- Name: lyb_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.lyb_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.lyb_partition OWNER TO admin;

--
-- Name: lyv_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.lyv_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.lyv_partition OWNER TO admin;

--
-- Name: ma_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ma_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ma_partition OWNER TO admin;

--
-- Name: maa_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.maa_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.maa_partition OWNER TO admin;

--
-- Name: mar_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mar_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mar_partition OWNER TO admin;

--
-- Name: mas_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mas_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mas_partition OWNER TO admin;

--
-- Name: mcd_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mcd_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mcd_partition OWNER TO admin;

--
-- Name: mchp_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mchp_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mchp_partition OWNER TO admin;

--
-- Name: mck_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mck_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mck_partition OWNER TO admin;

--
-- Name: mco_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mco_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mco_partition OWNER TO admin;

--
-- Name: mdlz_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mdlz_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mdlz_partition OWNER TO admin;

--
-- Name: mdt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mdt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mdt_partition OWNER TO admin;

--
-- Name: met_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.met_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.met_partition OWNER TO admin;

--
-- Name: mgm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mgm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mgm_partition OWNER TO admin;

--
-- Name: mhk_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mhk_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mhk_partition OWNER TO admin;

--
-- Name: mkc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mkc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mkc_partition OWNER TO admin;

--
-- Name: mktx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mktx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mktx_partition OWNER TO admin;

--
-- Name: mlm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mlm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mlm_partition OWNER TO admin;

--
-- Name: mmc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mmc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mmc_partition OWNER TO admin;

--
-- Name: mmm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mmm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mmm_partition OWNER TO admin;

--
-- Name: mnst_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mnst_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mnst_partition OWNER TO admin;

--
-- Name: mo_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mo_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mo_partition OWNER TO admin;

--
-- Name: mos_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mos_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mos_partition OWNER TO admin;

--
-- Name: mpc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mpc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mpc_partition OWNER TO admin;

--
-- Name: mpwr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mpwr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mpwr_partition OWNER TO admin;

--
-- Name: mrk_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mrk_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mrk_partition OWNER TO admin;

--
-- Name: mrna_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mrna_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mrna_partition OWNER TO admin;

--
-- Name: mro_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mro_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mro_partition OWNER TO admin;

--
-- Name: ms_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ms_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ms_partition OWNER TO admin;

--
-- Name: msci_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.msci_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.msci_partition OWNER TO admin;

--
-- Name: msft_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.msft_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.msft_partition OWNER TO admin;

--
-- Name: msi_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.msi_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.msi_partition OWNER TO admin;

--
-- Name: mtb_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mtb_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mtb_partition OWNER TO admin;

--
-- Name: mtch_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mtch_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mtch_partition OWNER TO admin;

--
-- Name: mtd_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mtd_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mtd_partition OWNER TO admin;

--
-- Name: mu_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.mu_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.mu_partition OWNER TO admin;

--
-- Name: nclh_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nclh_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nclh_partition OWNER TO admin;

--
-- Name: ndaq_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ndaq_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ndaq_partition OWNER TO admin;

--
-- Name: nee_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nee_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nee_partition OWNER TO admin;

--
-- Name: nem_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nem_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nem_partition OWNER TO admin;

--
-- Name: nflx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nflx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nflx_partition OWNER TO admin;

--
-- Name: ni_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ni_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ni_partition OWNER TO admin;

--
-- Name: nke_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nke_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nke_partition OWNER TO admin;

--
-- Name: nlok_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nlok_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nlok_partition OWNER TO admin;

--
-- Name: nlsn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nlsn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nlsn_partition OWNER TO admin;

--
-- Name: noc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.noc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.noc_partition OWNER TO admin;

--
-- Name: now_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.now_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.now_partition OWNER TO admin;

--
-- Name: nrg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nrg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nrg_partition OWNER TO admin;

--
-- Name: nsc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nsc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nsc_partition OWNER TO admin;

--
-- Name: ntap_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ntap_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ntap_partition OWNER TO admin;

--
-- Name: ntrs_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ntrs_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ntrs_partition OWNER TO admin;

--
-- Name: nue_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nue_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nue_partition OWNER TO admin;

--
-- Name: nvda_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nvda_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nvda_partition OWNER TO admin;

--
-- Name: nvr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nvr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nvr_partition OWNER TO admin;

--
-- Name: nwl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nwl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nwl_partition OWNER TO admin;

--
-- Name: nws_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nws_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nws_partition OWNER TO admin;

--
-- Name: nwsa_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nwsa_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nwsa_partition OWNER TO admin;

--
-- Name: nxpi_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.nxpi_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.nxpi_partition OWNER TO admin;

--
-- Name: o_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.o_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.o_partition OWNER TO admin;

--
-- Name: odfl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.odfl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.odfl_partition OWNER TO admin;

--
-- Name: ogn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ogn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ogn_partition OWNER TO admin;

--
-- Name: oke_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.oke_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.oke_partition OWNER TO admin;

--
-- Name: omc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.omc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.omc_partition OWNER TO admin;

--
-- Name: orcl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.orcl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.orcl_partition OWNER TO admin;

--
-- Name: orly_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.orly_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.orly_partition OWNER TO admin;

--
-- Name: otis_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.otis_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.otis_partition OWNER TO admin;

--
-- Name: oxy_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.oxy_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.oxy_partition OWNER TO admin;

--
-- Name: payc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.payc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.payc_partition OWNER TO admin;

--
-- Name: payx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.payx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.payx_partition OWNER TO admin;

--
-- Name: pbct_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pbct_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pbct_partition OWNER TO admin;

--
-- Name: pcar_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pcar_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pcar_partition OWNER TO admin;

--
-- Name: peak_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.peak_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.peak_partition OWNER TO admin;

--
-- Name: peg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.peg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.peg_partition OWNER TO admin;

--
-- Name: penn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.penn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.penn_partition OWNER TO admin;

--
-- Name: pep_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pep_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pep_partition OWNER TO admin;

--
-- Name: pfe_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pfe_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pfe_partition OWNER TO admin;

--
-- Name: pfg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pfg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pfg_partition OWNER TO admin;

--
-- Name: pg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pg_partition OWNER TO admin;

--
-- Name: pgr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pgr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pgr_partition OWNER TO admin;

--
-- Name: ph_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ph_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ph_partition OWNER TO admin;

--
-- Name: phm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.phm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.phm_partition OWNER TO admin;

--
-- Name: pkg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pkg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pkg_partition OWNER TO admin;

--
-- Name: pki_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pki_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pki_partition OWNER TO admin;

--
-- Name: pld_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pld_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pld_partition OWNER TO admin;

--
-- Name: pm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pm_partition OWNER TO admin;

--
-- Name: pnc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pnc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pnc_partition OWNER TO admin;

--
-- Name: pnr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pnr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pnr_partition OWNER TO admin;

--
-- Name: pnw_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pnw_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pnw_partition OWNER TO admin;

--
-- Name: pool_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pool_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pool_partition OWNER TO admin;

--
-- Name: ppg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ppg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ppg_partition OWNER TO admin;

--
-- Name: ppl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ppl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ppl_partition OWNER TO admin;

--
-- Name: pru_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pru_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pru_partition OWNER TO admin;

--
-- Name: psa_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.psa_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.psa_partition OWNER TO admin;

--
-- Name: psx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.psx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.psx_partition OWNER TO admin;

--
-- Name: ptc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ptc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ptc_partition OWNER TO admin;

--
-- Name: pvh_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pvh_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pvh_partition OWNER TO admin;

--
-- Name: pwr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pwr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pwr_partition OWNER TO admin;

--
-- Name: pxd_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pxd_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pxd_partition OWNER TO admin;

--
-- Name: pypl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.pypl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.pypl_partition OWNER TO admin;

--
-- Name: qcom_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.qcom_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.qcom_partition OWNER TO admin;

--
-- Name: qrvo_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.qrvo_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.qrvo_partition OWNER TO admin;

--
-- Name: rcl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.rcl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.rcl_partition OWNER TO admin;

--
-- Name: re_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.re_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.re_partition OWNER TO admin;

--
-- Name: reg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.reg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.reg_partition OWNER TO admin;

--
-- Name: regn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.regn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.regn_partition OWNER TO admin;

--
-- Name: rf_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.rf_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.rf_partition OWNER TO admin;

--
-- Name: rhi_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.rhi_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.rhi_partition OWNER TO admin;

--
-- Name: rjf_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.rjf_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.rjf_partition OWNER TO admin;

--
-- Name: rl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.rl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.rl_partition OWNER TO admin;

--
-- Name: rmd_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.rmd_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.rmd_partition OWNER TO admin;

--
-- Name: rok_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.rok_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.rok_partition OWNER TO admin;

--
-- Name: rol_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.rol_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.rol_partition OWNER TO admin;

--
-- Name: rop_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.rop_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.rop_partition OWNER TO admin;

--
-- Name: rost_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.rost_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.rost_partition OWNER TO admin;

--
-- Name: rsg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.rsg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.rsg_partition OWNER TO admin;

--
-- Name: rtx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.rtx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.rtx_partition OWNER TO admin;

--
-- Name: sbac_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.sbac_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.sbac_partition OWNER TO admin;

--
-- Name: sbny_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.sbny_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.sbny_partition OWNER TO admin;

--
-- Name: sbux_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.sbux_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.sbux_partition OWNER TO admin;

--
-- Name: schw_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.schw_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.schw_partition OWNER TO admin;

--
-- Name: sedg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.sedg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.sedg_partition OWNER TO admin;

--
-- Name: see_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.see_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.see_partition OWNER TO admin;

--
-- Name: shw_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.shw_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.shw_partition OWNER TO admin;

--
-- Name: sivb_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.sivb_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.sivb_partition OWNER TO admin;

--
-- Name: sjm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.sjm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.sjm_partition OWNER TO admin;

--
-- Name: slb_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.slb_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.slb_partition OWNER TO admin;

--
-- Name: sna_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.sna_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.sna_partition OWNER TO admin;

--
-- Name: snps_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.snps_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.snps_partition OWNER TO admin;

--
-- Name: so_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.so_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.so_partition OWNER TO admin;

--
-- Name: spg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.spg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.spg_partition OWNER TO admin;

--
-- Name: spgi_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.spgi_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.spgi_partition OWNER TO admin;

--
-- Name: sre_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.sre_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.sre_partition OWNER TO admin;

--
-- Name: ste_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ste_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ste_partition OWNER TO admin;

--
-- Name: stt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.stt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.stt_partition OWNER TO admin;

--
-- Name: stx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.stx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.stx_partition OWNER TO admin;

--
-- Name: stz_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.stz_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.stz_partition OWNER TO admin;

--
-- Name: swk_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.swk_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.swk_partition OWNER TO admin;

--
-- Name: swks_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.swks_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.swks_partition OWNER TO admin;

--
-- Name: syf_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.syf_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.syf_partition OWNER TO admin;

--
-- Name: syk_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.syk_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.syk_partition OWNER TO admin;

--
-- Name: syy_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.syy_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.syy_partition OWNER TO admin;

--
-- Name: t_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.t_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.t_partition OWNER TO admin;

--
-- Name: tap_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tap_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tap_partition OWNER TO admin;

--
-- Name: tdg_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tdg_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tdg_partition OWNER TO admin;

--
-- Name: tdy_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tdy_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tdy_partition OWNER TO admin;

--
-- Name: tech_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tech_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tech_partition OWNER TO admin;

--
-- Name: tel_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tel_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tel_partition OWNER TO admin;

--
-- Name: ter_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ter_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ter_partition OWNER TO admin;

--
-- Name: tfc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tfc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tfc_partition OWNER TO admin;

--
-- Name: tfx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tfx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tfx_partition OWNER TO admin;

--
-- Name: tgt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tgt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tgt_partition OWNER TO admin;

--
-- Name: tjx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tjx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tjx_partition OWNER TO admin;

--
-- Name: tmo_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tmo_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tmo_partition OWNER TO admin;

--
-- Name: tmus_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tmus_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tmus_partition OWNER TO admin;

--
-- Name: tops; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tops (
    id_instrument character varying NOT NULL,
    sum_analysis integer DEFAULT 0 NOT NULL,
    count_analysis integer DEFAULT 0 NOT NULL,
    calculation double precision DEFAULT 0.0 NOT NULL,
    last_update timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    symbol character varying NOT NULL,
    description character varying NOT NULL,
    name character varying NOT NULL
);


ALTER TABLE db.tops OWNER TO admin;

--
-- Name: tpr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tpr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tpr_partition OWNER TO admin;

--
-- Name: trmb_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.trmb_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.trmb_partition OWNER TO admin;

--
-- Name: trow_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.trow_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.trow_partition OWNER TO admin;

--
-- Name: trv_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.trv_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.trv_partition OWNER TO admin;

--
-- Name: tsco_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tsco_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tsco_partition OWNER TO admin;

--
-- Name: tsla_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tsla_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tsla_partition OWNER TO admin;

--
-- Name: tsn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tsn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tsn_partition OWNER TO admin;

--
-- Name: tt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tt_partition OWNER TO admin;

--
-- Name: ttwo_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ttwo_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ttwo_partition OWNER TO admin;

--
-- Name: twtr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.twtr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.twtr_partition OWNER TO admin;

--
-- Name: txn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.txn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.txn_partition OWNER TO admin;

--
-- Name: txt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.txt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.txt_partition OWNER TO admin;

--
-- Name: tyl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.tyl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.tyl_partition OWNER TO admin;

--
-- Name: ua_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ua_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ua_partition OWNER TO admin;

--
-- Name: uaa_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.uaa_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.uaa_partition OWNER TO admin;

--
-- Name: ual_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ual_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ual_partition OWNER TO admin;

--
-- Name: udr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.udr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.udr_partition OWNER TO admin;

--
-- Name: uhs_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.uhs_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.uhs_partition OWNER TO admin;

--
-- Name: ulta_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ulta_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ulta_partition OWNER TO admin;

--
-- Name: unh_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.unh_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.unh_partition OWNER TO admin;

--
-- Name: unp_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.unp_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.unp_partition OWNER TO admin;

--
-- Name: ups_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.ups_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.ups_partition OWNER TO admin;

--
-- Name: uri_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.uri_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.uri_partition OWNER TO admin;

--
-- Name: usb_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.usb_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.usb_partition OWNER TO admin;

--
-- Name: v_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.v_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.v_partition OWNER TO admin;

--
-- Name: vfc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.vfc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.vfc_partition OWNER TO admin;

--
-- Name: viac_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.viac_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.viac_partition OWNER TO admin;

--
-- Name: vlo_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.vlo_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.vlo_partition OWNER TO admin;

--
-- Name: vmc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.vmc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.vmc_partition OWNER TO admin;

--
-- Name: vno_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.vno_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.vno_partition OWNER TO admin;

--
-- Name: vrsk_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.vrsk_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.vrsk_partition OWNER TO admin;

--
-- Name: vrsn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.vrsn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.vrsn_partition OWNER TO admin;

--
-- Name: vrtx_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.vrtx_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.vrtx_partition OWNER TO admin;

--
-- Name: vtr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.vtr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.vtr_partition OWNER TO admin;

--
-- Name: vtrs_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.vtrs_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.vtrs_partition OWNER TO admin;

--
-- Name: vz_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.vz_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.vz_partition OWNER TO admin;

--
-- Name: wab_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.wab_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.wab_partition OWNER TO admin;

--
-- Name: wat_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.wat_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.wat_partition OWNER TO admin;

--
-- Name: wba_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.wba_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.wba_partition OWNER TO admin;

--
-- Name: wdc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.wdc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.wdc_partition OWNER TO admin;

--
-- Name: wec_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.wec_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.wec_partition OWNER TO admin;

--
-- Name: well_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.well_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.well_partition OWNER TO admin;

--
-- Name: wfc_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.wfc_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.wfc_partition OWNER TO admin;

--
-- Name: whr_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.whr_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.whr_partition OWNER TO admin;

--
-- Name: wm_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.wm_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.wm_partition OWNER TO admin;

--
-- Name: wmb_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.wmb_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.wmb_partition OWNER TO admin;

--
-- Name: wmt_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.wmt_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.wmt_partition OWNER TO admin;

--
-- Name: wrb_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.wrb_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.wrb_partition OWNER TO admin;

--
-- Name: wrk_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.wrk_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.wrk_partition OWNER TO admin;

--
-- Name: wst_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.wst_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.wst_partition OWNER TO admin;

--
-- Name: wtw_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.wtw_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.wtw_partition OWNER TO admin;

--
-- Name: wy_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.wy_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.wy_partition OWNER TO admin;

--
-- Name: wynn_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.wynn_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.wynn_partition OWNER TO admin;

--
-- Name: xel_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.xel_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.xel_partition OWNER TO admin;

--
-- Name: xom_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.xom_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.xom_partition OWNER TO admin;

--
-- Name: xray_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.xray_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.xray_partition OWNER TO admin;

--
-- Name: xyl_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.xyl_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.xyl_partition OWNER TO admin;

--
-- Name: yum_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.yum_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.yum_partition OWNER TO admin;

--
-- Name: zbh_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.zbh_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.zbh_partition OWNER TO admin;

--
-- Name: zbra_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.zbra_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.zbra_partition OWNER TO admin;

--
-- Name: zion_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.zion_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.zion_partition OWNER TO admin;

--
-- Name: zts_partition; Type: TABLE; Schema: db; Owner: admin
--

CREATE TABLE db.zts_partition (
    id_reference character varying NOT NULL,
    symbol character varying NOT NULL,
    date timestamp with time zone NOT NULL
);


ALTER TABLE db.zts_partition OWNER TO admin;

--
-- Name: news; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news.news (
    id bigint NOT NULL,
    title character varying NOT NULL,
    description character varying NOT NULL,
    pubdate timestamp with time zone NOT NULL,
    download_time timestamp with time zone NOT NULL,
    id_instrument character varying NOT NULL,
    analysis smallint NOT NULL
);


ALTER TABLE news.news OWNER TO admin;

--
-- Name: AAL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AAL_news_from_2022_03" (
    CONSTRAINT "AAL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AAL_news_from_2022_03" OWNER TO admin;

--
-- Name: AAPL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AAPL_news_from_2022_03" (
    CONSTRAINT "AAPL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AAPL_news_from_2022_03" OWNER TO admin;

--
-- Name: AAP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AAP_news_from_2022_03" (
    CONSTRAINT "AAP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AAP_news_from_2022_03" OWNER TO admin;

--
-- Name: ABBV_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ABBV_news_from_2022_03" (
    CONSTRAINT "ABBV_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ABBV_news_from_2022_03" OWNER TO admin;

--
-- Name: ABC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ABC_news_from_2022_03" (
    CONSTRAINT "ABC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ABC_news_from_2022_03" OWNER TO admin;

--
-- Name: ABMD_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ABMD_news_from_2022_03" (
    CONSTRAINT "ABMD_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ABMD_news_from_2022_03" OWNER TO admin;

--
-- Name: ABT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ABT_news_from_2022_03" (
    CONSTRAINT "ABT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ABT_news_from_2022_03" OWNER TO admin;

--
-- Name: ACN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ACN_news_from_2022_03" (
    CONSTRAINT "ACN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ACN_news_from_2022_03" OWNER TO admin;

--
-- Name: ADBE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ADBE_news_from_2022_03" (
    CONSTRAINT "ADBE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ADBE_news_from_2022_03" OWNER TO admin;

--
-- Name: ADI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ADI_news_from_2022_03" (
    CONSTRAINT "ADI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ADI_news_from_2022_03" OWNER TO admin;

--
-- Name: ADM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ADM_news_from_2022_03" (
    CONSTRAINT "ADM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ADM_news_from_2022_03" OWNER TO admin;

--
-- Name: ADP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ADP_news_from_2022_03" (
    CONSTRAINT "ADP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ADP_news_from_2022_03" OWNER TO admin;

--
-- Name: ADSK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ADSK_news_from_2022_03" (
    CONSTRAINT "ADSK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ADSK_news_from_2022_03" OWNER TO admin;

--
-- Name: AEE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AEE_news_from_2022_03" (
    CONSTRAINT "AEE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AEE_news_from_2022_03" OWNER TO admin;

--
-- Name: AEP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AEP_news_from_2022_03" (
    CONSTRAINT "AEP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AEP_news_from_2022_03" OWNER TO admin;

--
-- Name: AES_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AES_news_from_2022_03" (
    CONSTRAINT "AES_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AES_news_from_2022_03" OWNER TO admin;

--
-- Name: AFL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AFL_news_from_2022_03" (
    CONSTRAINT "AFL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AFL_news_from_2022_03" OWNER TO admin;

--
-- Name: AIG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AIG_news_from_2022_03" (
    CONSTRAINT "AIG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AIG_news_from_2022_03" OWNER TO admin;

--
-- Name: AIZ_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AIZ_news_from_2022_03" (
    CONSTRAINT "AIZ_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AIZ_news_from_2022_03" OWNER TO admin;

--
-- Name: AJG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AJG_news_from_2022_03" (
    CONSTRAINT "AJG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AJG_news_from_2022_03" OWNER TO admin;

--
-- Name: AKAM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AKAM_news_from_2022_03" (
    CONSTRAINT "AKAM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AKAM_news_from_2022_03" OWNER TO admin;

--
-- Name: ALB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ALB_news_from_2022_03" (
    CONSTRAINT "ALB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ALB_news_from_2022_03" OWNER TO admin;

--
-- Name: ALGN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ALGN_news_from_2022_03" (
    CONSTRAINT "ALGN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ALGN_news_from_2022_03" OWNER TO admin;

--
-- Name: ALK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ALK_news_from_2022_03" (
    CONSTRAINT "ALK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ALK_news_from_2022_03" OWNER TO admin;

--
-- Name: ALLE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ALLE_news_from_2022_03" (
    CONSTRAINT "ALLE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ALLE_news_from_2022_03" OWNER TO admin;

--
-- Name: ALL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ALL_news_from_2022_03" (
    CONSTRAINT "ALL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ALL_news_from_2022_03" OWNER TO admin;

--
-- Name: AMAT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AMAT_news_from_2022_03" (
    CONSTRAINT "AMAT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AMAT_news_from_2022_03" OWNER TO admin;

--
-- Name: AMCR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AMCR_news_from_2022_03" (
    CONSTRAINT "AMCR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AMCR_news_from_2022_03" OWNER TO admin;

--
-- Name: AMD_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AMD_news_from_2022_03" (
    CONSTRAINT "AMD_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AMD_news_from_2022_03" OWNER TO admin;

--
-- Name: AME_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AME_news_from_2022_03" (
    CONSTRAINT "AME_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AME_news_from_2022_03" OWNER TO admin;

--
-- Name: AMGN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AMGN_news_from_2022_03" (
    CONSTRAINT "AMGN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AMGN_news_from_2022_03" OWNER TO admin;

--
-- Name: AMP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AMP_news_from_2022_03" (
    CONSTRAINT "AMP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AMP_news_from_2022_03" OWNER TO admin;

--
-- Name: AMT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AMT_news_from_2022_03" (
    CONSTRAINT "AMT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AMT_news_from_2022_03" OWNER TO admin;

--
-- Name: AMZN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AMZN_news_from_2022_03" (
    CONSTRAINT "AMZN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AMZN_news_from_2022_03" OWNER TO admin;

--
-- Name: ANET_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ANET_news_from_2022_03" (
    CONSTRAINT "ANET_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ANET_news_from_2022_03" OWNER TO admin;

--
-- Name: ANSS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ANSS_news_from_2022_03" (
    CONSTRAINT "ANSS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ANSS_news_from_2022_03" OWNER TO admin;

--
-- Name: ANTM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ANTM_news_from_2022_03" (
    CONSTRAINT "ANTM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ANTM_news_from_2022_03" OWNER TO admin;

--
-- Name: AON_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AON_news_from_2022_03" (
    CONSTRAINT "AON_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AON_news_from_2022_03" OWNER TO admin;

--
-- Name: AOS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AOS_news_from_2022_03" (
    CONSTRAINT "AOS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AOS_news_from_2022_03" OWNER TO admin;

--
-- Name: APA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."APA_news_from_2022_03" (
    CONSTRAINT "APA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."APA_news_from_2022_03" OWNER TO admin;

--
-- Name: APD_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."APD_news_from_2022_03" (
    CONSTRAINT "APD_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."APD_news_from_2022_03" OWNER TO admin;

--
-- Name: APH_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."APH_news_from_2022_03" (
    CONSTRAINT "APH_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."APH_news_from_2022_03" OWNER TO admin;

--
-- Name: APTV_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."APTV_news_from_2022_03" (
    CONSTRAINT "APTV_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."APTV_news_from_2022_03" OWNER TO admin;

--
-- Name: ARE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ARE_news_from_2022_03" (
    CONSTRAINT "ARE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ARE_news_from_2022_03" OWNER TO admin;

--
-- Name: ATO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ATO_news_from_2022_03" (
    CONSTRAINT "ATO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ATO_news_from_2022_03" OWNER TO admin;

--
-- Name: ATVI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ATVI_news_from_2022_03" (
    CONSTRAINT "ATVI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ATVI_news_from_2022_03" OWNER TO admin;

--
-- Name: AVB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AVB_news_from_2022_03" (
    CONSTRAINT "AVB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AVB_news_from_2022_03" OWNER TO admin;

--
-- Name: AVGO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AVGO_news_from_2022_03" (
    CONSTRAINT "AVGO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AVGO_news_from_2022_03" OWNER TO admin;

--
-- Name: AVY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AVY_news_from_2022_03" (
    CONSTRAINT "AVY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AVY_news_from_2022_03" OWNER TO admin;

--
-- Name: AWK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AWK_news_from_2022_03" (
    CONSTRAINT "AWK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AWK_news_from_2022_03" OWNER TO admin;

--
-- Name: AXP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AXP_news_from_2022_03" (
    CONSTRAINT "AXP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AXP_news_from_2022_03" OWNER TO admin;

--
-- Name: AZO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."AZO_news_from_2022_03" (
    CONSTRAINT "AZO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."AZO_news_from_2022_03" OWNER TO admin;

--
-- Name: A_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."A_news_from_2022_03" (
    CONSTRAINT "A_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."A_news_from_2022_03" OWNER TO admin;

--
-- Name: BAC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BAC_news_from_2022_03" (
    CONSTRAINT "BAC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BAC_news_from_2022_03" OWNER TO admin;

--
-- Name: BAX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BAX_news_from_2022_03" (
    CONSTRAINT "BAX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BAX_news_from_2022_03" OWNER TO admin;

--
-- Name: BA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BA_news_from_2022_03" (
    CONSTRAINT "BA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BA_news_from_2022_03" OWNER TO admin;

--
-- Name: BBWI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BBWI_news_from_2022_03" (
    CONSTRAINT "BBWI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BBWI_news_from_2022_03" OWNER TO admin;

--
-- Name: BBY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BBY_news_from_2022_03" (
    CONSTRAINT "BBY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BBY_news_from_2022_03" OWNER TO admin;

--
-- Name: BDX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BDX_news_from_2022_03" (
    CONSTRAINT "BDX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BDX_news_from_2022_03" OWNER TO admin;

--
-- Name: BEN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BEN_news_from_2022_03" (
    CONSTRAINT "BEN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BEN_news_from_2022_03" OWNER TO admin;

--
-- Name: BF.B_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BF.B_news_from_2022_03" (
    CONSTRAINT "BF.B_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BF.B_news_from_2022_03" OWNER TO admin;

--
-- Name: BIIB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BIIB_news_from_2022_03" (
    CONSTRAINT "BIIB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BIIB_news_from_2022_03" OWNER TO admin;

--
-- Name: BIO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BIO_news_from_2022_03" (
    CONSTRAINT "BIO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BIO_news_from_2022_03" OWNER TO admin;

--
-- Name: BKNG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BKNG_news_from_2022_03" (
    CONSTRAINT "BKNG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BKNG_news_from_2022_03" OWNER TO admin;

--
-- Name: BKR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BKR_news_from_2022_03" (
    CONSTRAINT "BKR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BKR_news_from_2022_03" OWNER TO admin;

--
-- Name: BK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BK_news_from_2022_03" (
    CONSTRAINT "BK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BK_news_from_2022_03" OWNER TO admin;

--
-- Name: BLK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BLK_news_from_2022_03" (
    CONSTRAINT "BLK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BLK_news_from_2022_03" OWNER TO admin;

--
-- Name: BLL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BLL_news_from_2022_03" (
    CONSTRAINT "BLL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BLL_news_from_2022_03" OWNER TO admin;

--
-- Name: BMY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BMY_news_from_2022_03" (
    CONSTRAINT "BMY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BMY_news_from_2022_03" OWNER TO admin;

--
-- Name: BRK.B_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BRK.B_news_from_2022_03" (
    CONSTRAINT "BRK.B_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BRK.B_news_from_2022_03" OWNER TO admin;

--
-- Name: BRO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BRO_news_from_2022_03" (
    CONSTRAINT "BRO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BRO_news_from_2022_03" OWNER TO admin;

--
-- Name: BR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BR_news_from_2022_03" (
    CONSTRAINT "BR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BR_news_from_2022_03" OWNER TO admin;

--
-- Name: BSX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BSX_news_from_2022_03" (
    CONSTRAINT "BSX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BSX_news_from_2022_03" OWNER TO admin;

--
-- Name: BWA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BWA_news_from_2022_03" (
    CONSTRAINT "BWA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BWA_news_from_2022_03" OWNER TO admin;

--
-- Name: BXP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."BXP_news_from_2022_03" (
    CONSTRAINT "BXP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."BXP_news_from_2022_03" OWNER TO admin;

--
-- Name: CAG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CAG_news_from_2022_03" (
    CONSTRAINT "CAG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CAG_news_from_2022_03" OWNER TO admin;

--
-- Name: CAH_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CAH_news_from_2022_03" (
    CONSTRAINT "CAH_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CAH_news_from_2022_03" OWNER TO admin;

--
-- Name: CARR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CARR_news_from_2022_03" (
    CONSTRAINT "CARR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CARR_news_from_2022_03" OWNER TO admin;

--
-- Name: CAT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CAT_news_from_2022_03" (
    CONSTRAINT "CAT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CAT_news_from_2022_03" OWNER TO admin;

--
-- Name: CBOE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CBOE_news_from_2022_03" (
    CONSTRAINT "CBOE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CBOE_news_from_2022_03" OWNER TO admin;

--
-- Name: CBRE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CBRE_news_from_2022_03" (
    CONSTRAINT "CBRE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CBRE_news_from_2022_03" OWNER TO admin;

--
-- Name: CB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CB_news_from_2022_03" (
    CONSTRAINT "CB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CB_news_from_2022_03" OWNER TO admin;

--
-- Name: CCI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CCI_news_from_2022_03" (
    CONSTRAINT "CCI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CCI_news_from_2022_03" OWNER TO admin;

--
-- Name: CCL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CCL_news_from_2022_03" (
    CONSTRAINT "CCL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CCL_news_from_2022_03" OWNER TO admin;

--
-- Name: CDAY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CDAY_news_from_2022_03" (
    CONSTRAINT "CDAY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CDAY_news_from_2022_03" OWNER TO admin;

--
-- Name: CDNS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CDNS_news_from_2022_03" (
    CONSTRAINT "CDNS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CDNS_news_from_2022_03" OWNER TO admin;

--
-- Name: CDW_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CDW_news_from_2022_03" (
    CONSTRAINT "CDW_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CDW_news_from_2022_03" OWNER TO admin;

--
-- Name: CEG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CEG_news_from_2022_03" (
    CONSTRAINT "CEG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CEG_news_from_2022_03" OWNER TO admin;

--
-- Name: CERN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CERN_news_from_2022_03" (
    CONSTRAINT "CERN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CERN_news_from_2022_03" OWNER TO admin;

--
-- Name: CE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CE_news_from_2022_03" (
    CONSTRAINT "CE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CE_news_from_2022_03" OWNER TO admin;

--
-- Name: CFG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CFG_news_from_2022_03" (
    CONSTRAINT "CFG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CFG_news_from_2022_03" OWNER TO admin;

--
-- Name: CF_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CF_news_from_2022_03" (
    CONSTRAINT "CF_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CF_news_from_2022_03" OWNER TO admin;

--
-- Name: CHD_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CHD_news_from_2022_03" (
    CONSTRAINT "CHD_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CHD_news_from_2022_03" OWNER TO admin;

--
-- Name: CHRW_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CHRW_news_from_2022_03" (
    CONSTRAINT "CHRW_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CHRW_news_from_2022_03" OWNER TO admin;

--
-- Name: CHTR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CHTR_news_from_2022_03" (
    CONSTRAINT "CHTR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CHTR_news_from_2022_03" OWNER TO admin;

--
-- Name: CINF_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CINF_news_from_2022_03" (
    CONSTRAINT "CINF_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CINF_news_from_2022_03" OWNER TO admin;

--
-- Name: CI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CI_news_from_2022_03" (
    CONSTRAINT "CI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CI_news_from_2022_03" OWNER TO admin;

--
-- Name: CLX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CLX_news_from_2022_03" (
    CONSTRAINT "CLX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CLX_news_from_2022_03" OWNER TO admin;

--
-- Name: CL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CL_news_from_2022_03" (
    CONSTRAINT "CL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CL_news_from_2022_03" OWNER TO admin;

--
-- Name: CMA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CMA_news_from_2022_03" (
    CONSTRAINT "CMA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CMA_news_from_2022_03" OWNER TO admin;

--
-- Name: CMCSA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CMCSA_news_from_2022_03" (
    CONSTRAINT "CMCSA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CMCSA_news_from_2022_03" OWNER TO admin;

--
-- Name: CME_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CME_news_from_2022_03" (
    CONSTRAINT "CME_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CME_news_from_2022_03" OWNER TO admin;

--
-- Name: CMG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CMG_news_from_2022_03" (
    CONSTRAINT "CMG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CMG_news_from_2022_03" OWNER TO admin;

--
-- Name: CMI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CMI_news_from_2022_03" (
    CONSTRAINT "CMI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CMI_news_from_2022_03" OWNER TO admin;

--
-- Name: CMS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CMS_news_from_2022_03" (
    CONSTRAINT "CMS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CMS_news_from_2022_03" OWNER TO admin;

--
-- Name: CNC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CNC_news_from_2022_03" (
    CONSTRAINT "CNC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CNC_news_from_2022_03" OWNER TO admin;

--
-- Name: CNP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CNP_news_from_2022_03" (
    CONSTRAINT "CNP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CNP_news_from_2022_03" OWNER TO admin;

--
-- Name: COF_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."COF_news_from_2022_03" (
    CONSTRAINT "COF_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."COF_news_from_2022_03" OWNER TO admin;

--
-- Name: COO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."COO_news_from_2022_03" (
    CONSTRAINT "COO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."COO_news_from_2022_03" OWNER TO admin;

--
-- Name: COP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."COP_news_from_2022_03" (
    CONSTRAINT "COP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."COP_news_from_2022_03" OWNER TO admin;

--
-- Name: COST_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."COST_news_from_2022_03" (
    CONSTRAINT "COST_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."COST_news_from_2022_03" OWNER TO admin;

--
-- Name: CPB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CPB_news_from_2022_03" (
    CONSTRAINT "CPB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CPB_news_from_2022_03" OWNER TO admin;

--
-- Name: CPRT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CPRT_news_from_2022_03" (
    CONSTRAINT "CPRT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CPRT_news_from_2022_03" OWNER TO admin;

--
-- Name: CRL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CRL_news_from_2022_03" (
    CONSTRAINT "CRL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CRL_news_from_2022_03" OWNER TO admin;

--
-- Name: CRM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CRM_news_from_2022_03" (
    CONSTRAINT "CRM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CRM_news_from_2022_03" OWNER TO admin;

--
-- Name: CSCO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CSCO_news_from_2022_03" (
    CONSTRAINT "CSCO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CSCO_news_from_2022_03" OWNER TO admin;

--
-- Name: CSX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CSX_news_from_2022_03" (
    CONSTRAINT "CSX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CSX_news_from_2022_03" OWNER TO admin;

--
-- Name: CTAS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CTAS_news_from_2022_03" (
    CONSTRAINT "CTAS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CTAS_news_from_2022_03" OWNER TO admin;

--
-- Name: CTLT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CTLT_news_from_2022_03" (
    CONSTRAINT "CTLT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CTLT_news_from_2022_03" OWNER TO admin;

--
-- Name: CTRA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CTRA_news_from_2022_03" (
    CONSTRAINT "CTRA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CTRA_news_from_2022_03" OWNER TO admin;

--
-- Name: CTSH_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CTSH_news_from_2022_03" (
    CONSTRAINT "CTSH_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CTSH_news_from_2022_03" OWNER TO admin;

--
-- Name: CTVA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CTVA_news_from_2022_03" (
    CONSTRAINT "CTVA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CTVA_news_from_2022_03" OWNER TO admin;

--
-- Name: CTXS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CTXS_news_from_2022_03" (
    CONSTRAINT "CTXS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CTXS_news_from_2022_03" OWNER TO admin;

--
-- Name: CVS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CVS_news_from_2022_03" (
    CONSTRAINT "CVS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CVS_news_from_2022_03" OWNER TO admin;

--
-- Name: CVX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CVX_news_from_2022_03" (
    CONSTRAINT "CVX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CVX_news_from_2022_03" OWNER TO admin;

--
-- Name: CZR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."CZR_news_from_2022_03" (
    CONSTRAINT "CZR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."CZR_news_from_2022_03" OWNER TO admin;

--
-- Name: C_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."C_news_from_2022_03" (
    CONSTRAINT "C_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."C_news_from_2022_03" OWNER TO admin;

--
-- Name: DAL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DAL_news_from_2022_03" (
    CONSTRAINT "DAL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DAL_news_from_2022_03" OWNER TO admin;

--
-- Name: DD_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DD_news_from_2022_03" (
    CONSTRAINT "DD_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DD_news_from_2022_03" OWNER TO admin;

--
-- Name: DE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DE_news_from_2022_03" (
    CONSTRAINT "DE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DE_news_from_2022_03" OWNER TO admin;

--
-- Name: DFS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DFS_news_from_2022_03" (
    CONSTRAINT "DFS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DFS_news_from_2022_03" OWNER TO admin;

--
-- Name: DGX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DGX_news_from_2022_03" (
    CONSTRAINT "DGX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DGX_news_from_2022_03" OWNER TO admin;

--
-- Name: DG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DG_news_from_2022_03" (
    CONSTRAINT "DG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DG_news_from_2022_03" OWNER TO admin;

--
-- Name: DHI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DHI_news_from_2022_03" (
    CONSTRAINT "DHI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DHI_news_from_2022_03" OWNER TO admin;

--
-- Name: DHR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DHR_news_from_2022_03" (
    CONSTRAINT "DHR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DHR_news_from_2022_03" OWNER TO admin;

--
-- Name: DISCA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DISCA_news_from_2022_03" (
    CONSTRAINT "DISCA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DISCA_news_from_2022_03" OWNER TO admin;

--
-- Name: DISCK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DISCK_news_from_2022_03" (
    CONSTRAINT "DISCK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DISCK_news_from_2022_03" OWNER TO admin;

--
-- Name: DISH_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DISH_news_from_2022_03" (
    CONSTRAINT "DISH_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DISH_news_from_2022_03" OWNER TO admin;

--
-- Name: DIS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DIS_news_from_2022_03" (
    CONSTRAINT "DIS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DIS_news_from_2022_03" OWNER TO admin;

--
-- Name: DLR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DLR_news_from_2022_03" (
    CONSTRAINT "DLR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DLR_news_from_2022_03" OWNER TO admin;

--
-- Name: DLTR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DLTR_news_from_2022_03" (
    CONSTRAINT "DLTR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DLTR_news_from_2022_03" OWNER TO admin;

--
-- Name: DOV_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DOV_news_from_2022_03" (
    CONSTRAINT "DOV_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DOV_news_from_2022_03" OWNER TO admin;

--
-- Name: DOW_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DOW_news_from_2022_03" (
    CONSTRAINT "DOW_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DOW_news_from_2022_03" OWNER TO admin;

--
-- Name: DPZ_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DPZ_news_from_2022_03" (
    CONSTRAINT "DPZ_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DPZ_news_from_2022_03" OWNER TO admin;

--
-- Name: DRE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DRE_news_from_2022_03" (
    CONSTRAINT "DRE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DRE_news_from_2022_03" OWNER TO admin;

--
-- Name: DRI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DRI_news_from_2022_03" (
    CONSTRAINT "DRI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DRI_news_from_2022_03" OWNER TO admin;

--
-- Name: DTE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DTE_news_from_2022_03" (
    CONSTRAINT "DTE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DTE_news_from_2022_03" OWNER TO admin;

--
-- Name: DUK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DUK_news_from_2022_03" (
    CONSTRAINT "DUK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DUK_news_from_2022_03" OWNER TO admin;

--
-- Name: DVA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DVA_news_from_2022_03" (
    CONSTRAINT "DVA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DVA_news_from_2022_03" OWNER TO admin;

--
-- Name: DVN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DVN_news_from_2022_03" (
    CONSTRAINT "DVN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DVN_news_from_2022_03" OWNER TO admin;

--
-- Name: DXCM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DXCM_news_from_2022_03" (
    CONSTRAINT "DXCM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DXCM_news_from_2022_03" OWNER TO admin;

--
-- Name: DXC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."DXC_news_from_2022_03" (
    CONSTRAINT "DXC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."DXC_news_from_2022_03" OWNER TO admin;

--
-- Name: D_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."D_news_from_2022_03" (
    CONSTRAINT "D_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."D_news_from_2022_03" OWNER TO admin;

--
-- Name: EA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EA_news_from_2022_03" (
    CONSTRAINT "EA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EA_news_from_2022_03" OWNER TO admin;

--
-- Name: EBAY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EBAY_news_from_2022_03" (
    CONSTRAINT "EBAY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EBAY_news_from_2022_03" OWNER TO admin;

--
-- Name: ECL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ECL_news_from_2022_03" (
    CONSTRAINT "ECL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ECL_news_from_2022_03" OWNER TO admin;

--
-- Name: ED_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ED_news_from_2022_03" (
    CONSTRAINT "ED_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ED_news_from_2022_03" OWNER TO admin;

--
-- Name: EFX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EFX_news_from_2022_03" (
    CONSTRAINT "EFX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EFX_news_from_2022_03" OWNER TO admin;

--
-- Name: EIX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EIX_news_from_2022_03" (
    CONSTRAINT "EIX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EIX_news_from_2022_03" OWNER TO admin;

--
-- Name: EL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EL_news_from_2022_03" (
    CONSTRAINT "EL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EL_news_from_2022_03" OWNER TO admin;

--
-- Name: EMN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EMN_news_from_2022_03" (
    CONSTRAINT "EMN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EMN_news_from_2022_03" OWNER TO admin;

--
-- Name: EMR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EMR_news_from_2022_03" (
    CONSTRAINT "EMR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EMR_news_from_2022_03" OWNER TO admin;

--
-- Name: ENPH_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ENPH_news_from_2022_03" (
    CONSTRAINT "ENPH_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ENPH_news_from_2022_03" OWNER TO admin;

--
-- Name: EOG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EOG_news_from_2022_03" (
    CONSTRAINT "EOG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EOG_news_from_2022_03" OWNER TO admin;

--
-- Name: EPAM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EPAM_news_from_2022_03" (
    CONSTRAINT "EPAM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EPAM_news_from_2022_03" OWNER TO admin;

--
-- Name: EQIX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EQIX_news_from_2022_03" (
    CONSTRAINT "EQIX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EQIX_news_from_2022_03" OWNER TO admin;

--
-- Name: EQR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EQR_news_from_2022_03" (
    CONSTRAINT "EQR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EQR_news_from_2022_03" OWNER TO admin;

--
-- Name: ESS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ESS_news_from_2022_03" (
    CONSTRAINT "ESS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ESS_news_from_2022_03" OWNER TO admin;

--
-- Name: ES_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ES_news_from_2022_03" (
    CONSTRAINT "ES_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ES_news_from_2022_03" OWNER TO admin;

--
-- Name: ETN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ETN_news_from_2022_03" (
    CONSTRAINT "ETN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ETN_news_from_2022_03" OWNER TO admin;

--
-- Name: ETR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ETR_news_from_2022_03" (
    CONSTRAINT "ETR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ETR_news_from_2022_03" OWNER TO admin;

--
-- Name: ETSY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ETSY_news_from_2022_03" (
    CONSTRAINT "ETSY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ETSY_news_from_2022_03" OWNER TO admin;

--
-- Name: EVRG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EVRG_news_from_2022_03" (
    CONSTRAINT "EVRG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EVRG_news_from_2022_03" OWNER TO admin;

--
-- Name: EW_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EW_news_from_2022_03" (
    CONSTRAINT "EW_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EW_news_from_2022_03" OWNER TO admin;

--
-- Name: EXC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EXC_news_from_2022_03" (
    CONSTRAINT "EXC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EXC_news_from_2022_03" OWNER TO admin;

--
-- Name: EXPD_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EXPD_news_from_2022_03" (
    CONSTRAINT "EXPD_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EXPD_news_from_2022_03" OWNER TO admin;

--
-- Name: EXPE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EXPE_news_from_2022_03" (
    CONSTRAINT "EXPE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EXPE_news_from_2022_03" OWNER TO admin;

--
-- Name: EXR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."EXR_news_from_2022_03" (
    CONSTRAINT "EXR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."EXR_news_from_2022_03" OWNER TO admin;

--
-- Name: FANG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FANG_news_from_2022_03" (
    CONSTRAINT "FANG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FANG_news_from_2022_03" OWNER TO admin;

--
-- Name: FAST_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FAST_news_from_2022_03" (
    CONSTRAINT "FAST_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FAST_news_from_2022_03" OWNER TO admin;

--
-- Name: FBHS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FBHS_news_from_2022_03" (
    CONSTRAINT "FBHS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FBHS_news_from_2022_03" OWNER TO admin;

--
-- Name: FB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FB_news_from_2022_03" (
    CONSTRAINT "FB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FB_news_from_2022_03" OWNER TO admin;

--
-- Name: FCX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FCX_news_from_2022_03" (
    CONSTRAINT "FCX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FCX_news_from_2022_03" OWNER TO admin;

--
-- Name: FDS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FDS_news_from_2022_03" (
    CONSTRAINT "FDS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FDS_news_from_2022_03" OWNER TO admin;

--
-- Name: FDX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FDX_news_from_2022_03" (
    CONSTRAINT "FDX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FDX_news_from_2022_03" OWNER TO admin;

--
-- Name: FE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FE_news_from_2022_03" (
    CONSTRAINT "FE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FE_news_from_2022_03" OWNER TO admin;

--
-- Name: FFIV_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FFIV_news_from_2022_03" (
    CONSTRAINT "FFIV_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FFIV_news_from_2022_03" OWNER TO admin;

--
-- Name: FISV_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FISV_news_from_2022_03" (
    CONSTRAINT "FISV_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FISV_news_from_2022_03" OWNER TO admin;

--
-- Name: FIS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FIS_news_from_2022_03" (
    CONSTRAINT "FIS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FIS_news_from_2022_03" OWNER TO admin;

--
-- Name: FITB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FITB_news_from_2022_03" (
    CONSTRAINT "FITB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FITB_news_from_2022_03" OWNER TO admin;

--
-- Name: FLT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FLT_news_from_2022_03" (
    CONSTRAINT "FLT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FLT_news_from_2022_03" OWNER TO admin;

--
-- Name: FMC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FMC_news_from_2022_03" (
    CONSTRAINT "FMC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FMC_news_from_2022_03" OWNER TO admin;

--
-- Name: FOXA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FOXA_news_from_2022_03" (
    CONSTRAINT "FOXA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FOXA_news_from_2022_03" OWNER TO admin;

--
-- Name: FOX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FOX_news_from_2022_03" (
    CONSTRAINT "FOX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FOX_news_from_2022_03" OWNER TO admin;

--
-- Name: FRC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FRC_news_from_2022_03" (
    CONSTRAINT "FRC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FRC_news_from_2022_03" OWNER TO admin;

--
-- Name: FRT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FRT_news_from_2022_03" (
    CONSTRAINT "FRT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FRT_news_from_2022_03" OWNER TO admin;

--
-- Name: FTNT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FTNT_news_from_2022_03" (
    CONSTRAINT "FTNT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FTNT_news_from_2022_03" OWNER TO admin;

--
-- Name: FTV_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."FTV_news_from_2022_03" (
    CONSTRAINT "FTV_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."FTV_news_from_2022_03" OWNER TO admin;

--
-- Name: F_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."F_news_from_2022_03" (
    CONSTRAINT "F_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."F_news_from_2022_03" OWNER TO admin;

--
-- Name: GD_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."GD_news_from_2022_03" (
    CONSTRAINT "GD_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."GD_news_from_2022_03" OWNER TO admin;

--
-- Name: GE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."GE_news_from_2022_03" (
    CONSTRAINT "GE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."GE_news_from_2022_03" OWNER TO admin;

--
-- Name: GILD_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."GILD_news_from_2022_03" (
    CONSTRAINT "GILD_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."GILD_news_from_2022_03" OWNER TO admin;

--
-- Name: GIS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."GIS_news_from_2022_03" (
    CONSTRAINT "GIS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."GIS_news_from_2022_03" OWNER TO admin;

--
-- Name: GLW_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."GLW_news_from_2022_03" (
    CONSTRAINT "GLW_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."GLW_news_from_2022_03" OWNER TO admin;

--
-- Name: GL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."GL_news_from_2022_03" (
    CONSTRAINT "GL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."GL_news_from_2022_03" OWNER TO admin;

--
-- Name: GM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."GM_news_from_2022_03" (
    CONSTRAINT "GM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."GM_news_from_2022_03" OWNER TO admin;

--
-- Name: GNRC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."GNRC_news_from_2022_03" (
    CONSTRAINT "GNRC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."GNRC_news_from_2022_03" OWNER TO admin;

--
-- Name: GOOGL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."GOOGL_news_from_2022_03" (
    CONSTRAINT "GOOGL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."GOOGL_news_from_2022_03" OWNER TO admin;

--
-- Name: GOOG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."GOOG_news_from_2022_03" (
    CONSTRAINT "GOOG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."GOOG_news_from_2022_03" OWNER TO admin;

--
-- Name: GPC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."GPC_news_from_2022_03" (
    CONSTRAINT "GPC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."GPC_news_from_2022_03" OWNER TO admin;

--
-- Name: GPN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."GPN_news_from_2022_03" (
    CONSTRAINT "GPN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."GPN_news_from_2022_03" OWNER TO admin;

--
-- Name: GRMN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."GRMN_news_from_2022_03" (
    CONSTRAINT "GRMN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."GRMN_news_from_2022_03" OWNER TO admin;

--
-- Name: GS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."GS_news_from_2022_03" (
    CONSTRAINT "GS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."GS_news_from_2022_03" OWNER TO admin;

--
-- Name: GWW_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."GWW_news_from_2022_03" (
    CONSTRAINT "GWW_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."GWW_news_from_2022_03" OWNER TO admin;

--
-- Name: HAL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HAL_news_from_2022_03" (
    CONSTRAINT "HAL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HAL_news_from_2022_03" OWNER TO admin;

--
-- Name: HAS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HAS_news_from_2022_03" (
    CONSTRAINT "HAS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HAS_news_from_2022_03" OWNER TO admin;

--
-- Name: HBAN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HBAN_news_from_2022_03" (
    CONSTRAINT "HBAN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HBAN_news_from_2022_03" OWNER TO admin;

--
-- Name: HCA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HCA_news_from_2022_03" (
    CONSTRAINT "HCA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HCA_news_from_2022_03" OWNER TO admin;

--
-- Name: HD_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HD_news_from_2022_03" (
    CONSTRAINT "HD_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HD_news_from_2022_03" OWNER TO admin;

--
-- Name: HES_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HES_news_from_2022_03" (
    CONSTRAINT "HES_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HES_news_from_2022_03" OWNER TO admin;

--
-- Name: HIG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HIG_news_from_2022_03" (
    CONSTRAINT "HIG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HIG_news_from_2022_03" OWNER TO admin;

--
-- Name: HII_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HII_news_from_2022_03" (
    CONSTRAINT "HII_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HII_news_from_2022_03" OWNER TO admin;

--
-- Name: HLT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HLT_news_from_2022_03" (
    CONSTRAINT "HLT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HLT_news_from_2022_03" OWNER TO admin;

--
-- Name: HOLX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HOLX_news_from_2022_03" (
    CONSTRAINT "HOLX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HOLX_news_from_2022_03" OWNER TO admin;

--
-- Name: HON_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HON_news_from_2022_03" (
    CONSTRAINT "HON_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HON_news_from_2022_03" OWNER TO admin;

--
-- Name: HPE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HPE_news_from_2022_03" (
    CONSTRAINT "HPE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HPE_news_from_2022_03" OWNER TO admin;

--
-- Name: HPQ_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HPQ_news_from_2022_03" (
    CONSTRAINT "HPQ_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HPQ_news_from_2022_03" OWNER TO admin;

--
-- Name: HRL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HRL_news_from_2022_03" (
    CONSTRAINT "HRL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HRL_news_from_2022_03" OWNER TO admin;

--
-- Name: HSIC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HSIC_news_from_2022_03" (
    CONSTRAINT "HSIC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HSIC_news_from_2022_03" OWNER TO admin;

--
-- Name: HST_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HST_news_from_2022_03" (
    CONSTRAINT "HST_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HST_news_from_2022_03" OWNER TO admin;

--
-- Name: HSY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HSY_news_from_2022_03" (
    CONSTRAINT "HSY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HSY_news_from_2022_03" OWNER TO admin;

--
-- Name: HUM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HUM_news_from_2022_03" (
    CONSTRAINT "HUM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HUM_news_from_2022_03" OWNER TO admin;

--
-- Name: HWM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."HWM_news_from_2022_03" (
    CONSTRAINT "HWM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."HWM_news_from_2022_03" OWNER TO admin;

--
-- Name: IBM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."IBM_news_from_2022_03" (
    CONSTRAINT "IBM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."IBM_news_from_2022_03" OWNER TO admin;

--
-- Name: ICE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ICE_news_from_2022_03" (
    CONSTRAINT "ICE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ICE_news_from_2022_03" OWNER TO admin;

--
-- Name: IDXX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."IDXX_news_from_2022_03" (
    CONSTRAINT "IDXX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."IDXX_news_from_2022_03" OWNER TO admin;

--
-- Name: IEX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."IEX_news_from_2022_03" (
    CONSTRAINT "IEX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."IEX_news_from_2022_03" OWNER TO admin;

--
-- Name: IFF_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."IFF_news_from_2022_03" (
    CONSTRAINT "IFF_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."IFF_news_from_2022_03" OWNER TO admin;

--
-- Name: ILMN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ILMN_news_from_2022_03" (
    CONSTRAINT "ILMN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ILMN_news_from_2022_03" OWNER TO admin;

--
-- Name: INCY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."INCY_news_from_2022_03" (
    CONSTRAINT "INCY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."INCY_news_from_2022_03" OWNER TO admin;

--
-- Name: INFO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."INFO_news_from_2022_03" (
    CONSTRAINT "INFO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."INFO_news_from_2022_03" OWNER TO admin;

--
-- Name: INTC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."INTC_news_from_2022_03" (
    CONSTRAINT "INTC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."INTC_news_from_2022_03" OWNER TO admin;

--
-- Name: INTU_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."INTU_news_from_2022_03" (
    CONSTRAINT "INTU_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."INTU_news_from_2022_03" OWNER TO admin;

--
-- Name: IPGP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."IPGP_news_from_2022_03" (
    CONSTRAINT "IPGP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."IPGP_news_from_2022_03" OWNER TO admin;

--
-- Name: IPG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."IPG_news_from_2022_03" (
    CONSTRAINT "IPG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."IPG_news_from_2022_03" OWNER TO admin;

--
-- Name: IP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."IP_news_from_2022_03" (
    CONSTRAINT "IP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."IP_news_from_2022_03" OWNER TO admin;

--
-- Name: IQV_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."IQV_news_from_2022_03" (
    CONSTRAINT "IQV_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."IQV_news_from_2022_03" OWNER TO admin;

--
-- Name: IRM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."IRM_news_from_2022_03" (
    CONSTRAINT "IRM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."IRM_news_from_2022_03" OWNER TO admin;

--
-- Name: IR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."IR_news_from_2022_03" (
    CONSTRAINT "IR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."IR_news_from_2022_03" OWNER TO admin;

--
-- Name: ISRG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ISRG_news_from_2022_03" (
    CONSTRAINT "ISRG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ISRG_news_from_2022_03" OWNER TO admin;

--
-- Name: ITW_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ITW_news_from_2022_03" (
    CONSTRAINT "ITW_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ITW_news_from_2022_03" OWNER TO admin;

--
-- Name: IT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."IT_news_from_2022_03" (
    CONSTRAINT "IT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."IT_news_from_2022_03" OWNER TO admin;

--
-- Name: IVZ_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."IVZ_news_from_2022_03" (
    CONSTRAINT "IVZ_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."IVZ_news_from_2022_03" OWNER TO admin;

--
-- Name: JBHT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."JBHT_news_from_2022_03" (
    CONSTRAINT "JBHT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."JBHT_news_from_2022_03" OWNER TO admin;

--
-- Name: JCI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."JCI_news_from_2022_03" (
    CONSTRAINT "JCI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."JCI_news_from_2022_03" OWNER TO admin;

--
-- Name: JKHY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."JKHY_news_from_2022_03" (
    CONSTRAINT "JKHY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."JKHY_news_from_2022_03" OWNER TO admin;

--
-- Name: JNJ_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."JNJ_news_from_2022_03" (
    CONSTRAINT "JNJ_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."JNJ_news_from_2022_03" OWNER TO admin;

--
-- Name: JNPR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."JNPR_news_from_2022_03" (
    CONSTRAINT "JNPR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."JNPR_news_from_2022_03" OWNER TO admin;

--
-- Name: JPM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."JPM_news_from_2022_03" (
    CONSTRAINT "JPM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."JPM_news_from_2022_03" OWNER TO admin;

--
-- Name: J_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."J_news_from_2022_03" (
    CONSTRAINT "J_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."J_news_from_2022_03" OWNER TO admin;

--
-- Name: KEYS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."KEYS_news_from_2022_03" (
    CONSTRAINT "KEYS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."KEYS_news_from_2022_03" OWNER TO admin;

--
-- Name: KEY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."KEY_news_from_2022_03" (
    CONSTRAINT "KEY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."KEY_news_from_2022_03" OWNER TO admin;

--
-- Name: KHC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."KHC_news_from_2022_03" (
    CONSTRAINT "KHC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."KHC_news_from_2022_03" OWNER TO admin;

--
-- Name: KIM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."KIM_news_from_2022_03" (
    CONSTRAINT "KIM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."KIM_news_from_2022_03" OWNER TO admin;

--
-- Name: KLAC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."KLAC_news_from_2022_03" (
    CONSTRAINT "KLAC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."KLAC_news_from_2022_03" OWNER TO admin;

--
-- Name: KMB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."KMB_news_from_2022_03" (
    CONSTRAINT "KMB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."KMB_news_from_2022_03" OWNER TO admin;

--
-- Name: KMI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."KMI_news_from_2022_03" (
    CONSTRAINT "KMI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."KMI_news_from_2022_03" OWNER TO admin;

--
-- Name: KMX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."KMX_news_from_2022_03" (
    CONSTRAINT "KMX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."KMX_news_from_2022_03" OWNER TO admin;

--
-- Name: KO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."KO_news_from_2022_03" (
    CONSTRAINT "KO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."KO_news_from_2022_03" OWNER TO admin;

--
-- Name: KR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."KR_news_from_2022_03" (
    CONSTRAINT "KR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."KR_news_from_2022_03" OWNER TO admin;

--
-- Name: K_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."K_news_from_2022_03" (
    CONSTRAINT "K_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."K_news_from_2022_03" OWNER TO admin;

--
-- Name: LDOS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LDOS_news_from_2022_03" (
    CONSTRAINT "LDOS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LDOS_news_from_2022_03" OWNER TO admin;

--
-- Name: LEN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LEN_news_from_2022_03" (
    CONSTRAINT "LEN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LEN_news_from_2022_03" OWNER TO admin;

--
-- Name: LHX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LHX_news_from_2022_03" (
    CONSTRAINT "LHX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LHX_news_from_2022_03" OWNER TO admin;

--
-- Name: LH_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LH_news_from_2022_03" (
    CONSTRAINT "LH_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LH_news_from_2022_03" OWNER TO admin;

--
-- Name: LIN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LIN_news_from_2022_03" (
    CONSTRAINT "LIN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LIN_news_from_2022_03" OWNER TO admin;

--
-- Name: LKQ_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LKQ_news_from_2022_03" (
    CONSTRAINT "LKQ_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LKQ_news_from_2022_03" OWNER TO admin;

--
-- Name: LLY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LLY_news_from_2022_03" (
    CONSTRAINT "LLY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LLY_news_from_2022_03" OWNER TO admin;

--
-- Name: LMT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LMT_news_from_2022_03" (
    CONSTRAINT "LMT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LMT_news_from_2022_03" OWNER TO admin;

--
-- Name: LNC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LNC_news_from_2022_03" (
    CONSTRAINT "LNC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LNC_news_from_2022_03" OWNER TO admin;

--
-- Name: LNT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LNT_news_from_2022_03" (
    CONSTRAINT "LNT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LNT_news_from_2022_03" OWNER TO admin;

--
-- Name: LOW_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LOW_news_from_2022_03" (
    CONSTRAINT "LOW_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LOW_news_from_2022_03" OWNER TO admin;

--
-- Name: LRCX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LRCX_news_from_2022_03" (
    CONSTRAINT "LRCX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LRCX_news_from_2022_03" OWNER TO admin;

--
-- Name: LUMN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LUMN_news_from_2022_03" (
    CONSTRAINT "LUMN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LUMN_news_from_2022_03" OWNER TO admin;

--
-- Name: LUV_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LUV_news_from_2022_03" (
    CONSTRAINT "LUV_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LUV_news_from_2022_03" OWNER TO admin;

--
-- Name: LVS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LVS_news_from_2022_03" (
    CONSTRAINT "LVS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LVS_news_from_2022_03" OWNER TO admin;

--
-- Name: LW_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LW_news_from_2022_03" (
    CONSTRAINT "LW_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LW_news_from_2022_03" OWNER TO admin;

--
-- Name: LYB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LYB_news_from_2022_03" (
    CONSTRAINT "LYB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LYB_news_from_2022_03" OWNER TO admin;

--
-- Name: LYV_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."LYV_news_from_2022_03" (
    CONSTRAINT "LYV_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."LYV_news_from_2022_03" OWNER TO admin;

--
-- Name: L_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."L_news_from_2022_03" (
    CONSTRAINT "L_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."L_news_from_2022_03" OWNER TO admin;

--
-- Name: MAA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MAA_news_from_2022_03" (
    CONSTRAINT "MAA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MAA_news_from_2022_03" OWNER TO admin;

--
-- Name: MAR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MAR_news_from_2022_03" (
    CONSTRAINT "MAR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MAR_news_from_2022_03" OWNER TO admin;

--
-- Name: MAS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MAS_news_from_2022_03" (
    CONSTRAINT "MAS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MAS_news_from_2022_03" OWNER TO admin;

--
-- Name: MA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MA_news_from_2022_03" (
    CONSTRAINT "MA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MA_news_from_2022_03" OWNER TO admin;

--
-- Name: MCD_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MCD_news_from_2022_03" (
    CONSTRAINT "MCD_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MCD_news_from_2022_03" OWNER TO admin;

--
-- Name: MCHP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MCHP_news_from_2022_03" (
    CONSTRAINT "MCHP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MCHP_news_from_2022_03" OWNER TO admin;

--
-- Name: MCK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MCK_news_from_2022_03" (
    CONSTRAINT "MCK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MCK_news_from_2022_03" OWNER TO admin;

--
-- Name: MCO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MCO_news_from_2022_03" (
    CONSTRAINT "MCO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MCO_news_from_2022_03" OWNER TO admin;

--
-- Name: MDLZ_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MDLZ_news_from_2022_03" (
    CONSTRAINT "MDLZ_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MDLZ_news_from_2022_03" OWNER TO admin;

--
-- Name: MDT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MDT_news_from_2022_03" (
    CONSTRAINT "MDT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MDT_news_from_2022_03" OWNER TO admin;

--
-- Name: MET_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MET_news_from_2022_03" (
    CONSTRAINT "MET_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MET_news_from_2022_03" OWNER TO admin;

--
-- Name: MGM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MGM_news_from_2022_03" (
    CONSTRAINT "MGM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MGM_news_from_2022_03" OWNER TO admin;

--
-- Name: MHK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MHK_news_from_2022_03" (
    CONSTRAINT "MHK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MHK_news_from_2022_03" OWNER TO admin;

--
-- Name: MKC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MKC_news_from_2022_03" (
    CONSTRAINT "MKC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MKC_news_from_2022_03" OWNER TO admin;

--
-- Name: MKTX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MKTX_news_from_2022_03" (
    CONSTRAINT "MKTX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MKTX_news_from_2022_03" OWNER TO admin;

--
-- Name: MLM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MLM_news_from_2022_03" (
    CONSTRAINT "MLM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MLM_news_from_2022_03" OWNER TO admin;

--
-- Name: MMC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MMC_news_from_2022_03" (
    CONSTRAINT "MMC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MMC_news_from_2022_03" OWNER TO admin;

--
-- Name: MMM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MMM_news_from_2022_03" (
    CONSTRAINT "MMM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MMM_news_from_2022_03" OWNER TO admin;

--
-- Name: MNST_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MNST_news_from_2022_03" (
    CONSTRAINT "MNST_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MNST_news_from_2022_03" OWNER TO admin;

--
-- Name: MOS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MOS_news_from_2022_03" (
    CONSTRAINT "MOS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MOS_news_from_2022_03" OWNER TO admin;

--
-- Name: MO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MO_news_from_2022_03" (
    CONSTRAINT "MO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MO_news_from_2022_03" OWNER TO admin;

--
-- Name: MPC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MPC_news_from_2022_03" (
    CONSTRAINT "MPC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MPC_news_from_2022_03" OWNER TO admin;

--
-- Name: MPWR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MPWR_news_from_2022_03" (
    CONSTRAINT "MPWR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MPWR_news_from_2022_03" OWNER TO admin;

--
-- Name: MRK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MRK_news_from_2022_03" (
    CONSTRAINT "MRK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MRK_news_from_2022_03" OWNER TO admin;

--
-- Name: MRNA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MRNA_news_from_2022_03" (
    CONSTRAINT "MRNA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MRNA_news_from_2022_03" OWNER TO admin;

--
-- Name: MRO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MRO_news_from_2022_03" (
    CONSTRAINT "MRO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MRO_news_from_2022_03" OWNER TO admin;

--
-- Name: MSCI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MSCI_news_from_2022_03" (
    CONSTRAINT "MSCI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MSCI_news_from_2022_03" OWNER TO admin;

--
-- Name: MSFT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MSFT_news_from_2022_03" (
    CONSTRAINT "MSFT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MSFT_news_from_2022_03" OWNER TO admin;

--
-- Name: MSI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MSI_news_from_2022_03" (
    CONSTRAINT "MSI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MSI_news_from_2022_03" OWNER TO admin;

--
-- Name: MS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MS_news_from_2022_03" (
    CONSTRAINT "MS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MS_news_from_2022_03" OWNER TO admin;

--
-- Name: MTB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MTB_news_from_2022_03" (
    CONSTRAINT "MTB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MTB_news_from_2022_03" OWNER TO admin;

--
-- Name: MTCH_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MTCH_news_from_2022_03" (
    CONSTRAINT "MTCH_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MTCH_news_from_2022_03" OWNER TO admin;

--
-- Name: MTD_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MTD_news_from_2022_03" (
    CONSTRAINT "MTD_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MTD_news_from_2022_03" OWNER TO admin;

--
-- Name: MU_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."MU_news_from_2022_03" (
    CONSTRAINT "MU_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."MU_news_from_2022_03" OWNER TO admin;

--
-- Name: NCLH_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NCLH_news_from_2022_03" (
    CONSTRAINT "NCLH_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NCLH_news_from_2022_03" OWNER TO admin;

--
-- Name: NDAQ_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NDAQ_news_from_2022_03" (
    CONSTRAINT "NDAQ_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NDAQ_news_from_2022_03" OWNER TO admin;

--
-- Name: NEE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NEE_news_from_2022_03" (
    CONSTRAINT "NEE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NEE_news_from_2022_03" OWNER TO admin;

--
-- Name: NEM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NEM_news_from_2022_03" (
    CONSTRAINT "NEM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NEM_news_from_2022_03" OWNER TO admin;

--
-- Name: NFLX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NFLX_news_from_2022_03" (
    CONSTRAINT "NFLX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NFLX_news_from_2022_03" OWNER TO admin;

--
-- Name: NI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NI_news_from_2022_03" (
    CONSTRAINT "NI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NI_news_from_2022_03" OWNER TO admin;

--
-- Name: NKE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NKE_news_from_2022_03" (
    CONSTRAINT "NKE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NKE_news_from_2022_03" OWNER TO admin;

--
-- Name: NLOK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NLOK_news_from_2022_03" (
    CONSTRAINT "NLOK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NLOK_news_from_2022_03" OWNER TO admin;

--
-- Name: NLSN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NLSN_news_from_2022_03" (
    CONSTRAINT "NLSN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NLSN_news_from_2022_03" OWNER TO admin;

--
-- Name: NOC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NOC_news_from_2022_03" (
    CONSTRAINT "NOC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NOC_news_from_2022_03" OWNER TO admin;

--
-- Name: NOW_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NOW_news_from_2022_03" (
    CONSTRAINT "NOW_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NOW_news_from_2022_03" OWNER TO admin;

--
-- Name: NRG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NRG_news_from_2022_03" (
    CONSTRAINT "NRG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NRG_news_from_2022_03" OWNER TO admin;

--
-- Name: NSC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NSC_news_from_2022_03" (
    CONSTRAINT "NSC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NSC_news_from_2022_03" OWNER TO admin;

--
-- Name: NTAP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NTAP_news_from_2022_03" (
    CONSTRAINT "NTAP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NTAP_news_from_2022_03" OWNER TO admin;

--
-- Name: NTRS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NTRS_news_from_2022_03" (
    CONSTRAINT "NTRS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NTRS_news_from_2022_03" OWNER TO admin;

--
-- Name: NUE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NUE_news_from_2022_03" (
    CONSTRAINT "NUE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NUE_news_from_2022_03" OWNER TO admin;

--
-- Name: NVDA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NVDA_news_from_2022_03" (
    CONSTRAINT "NVDA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NVDA_news_from_2022_03" OWNER TO admin;

--
-- Name: NVR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NVR_news_from_2022_03" (
    CONSTRAINT "NVR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NVR_news_from_2022_03" OWNER TO admin;

--
-- Name: NWL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NWL_news_from_2022_03" (
    CONSTRAINT "NWL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NWL_news_from_2022_03" OWNER TO admin;

--
-- Name: NWSA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NWSA_news_from_2022_03" (
    CONSTRAINT "NWSA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NWSA_news_from_2022_03" OWNER TO admin;

--
-- Name: NWS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NWS_news_from_2022_03" (
    CONSTRAINT "NWS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NWS_news_from_2022_03" OWNER TO admin;

--
-- Name: NXPI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."NXPI_news_from_2022_03" (
    CONSTRAINT "NXPI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."NXPI_news_from_2022_03" OWNER TO admin;

--
-- Name: ODFL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ODFL_news_from_2022_03" (
    CONSTRAINT "ODFL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ODFL_news_from_2022_03" OWNER TO admin;

--
-- Name: OGN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."OGN_news_from_2022_03" (
    CONSTRAINT "OGN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."OGN_news_from_2022_03" OWNER TO admin;

--
-- Name: OKE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."OKE_news_from_2022_03" (
    CONSTRAINT "OKE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."OKE_news_from_2022_03" OWNER TO admin;

--
-- Name: OMC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."OMC_news_from_2022_03" (
    CONSTRAINT "OMC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."OMC_news_from_2022_03" OWNER TO admin;

--
-- Name: ORCL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ORCL_news_from_2022_03" (
    CONSTRAINT "ORCL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ORCL_news_from_2022_03" OWNER TO admin;

--
-- Name: ORLY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ORLY_news_from_2022_03" (
    CONSTRAINT "ORLY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ORLY_news_from_2022_03" OWNER TO admin;

--
-- Name: OTIS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."OTIS_news_from_2022_03" (
    CONSTRAINT "OTIS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."OTIS_news_from_2022_03" OWNER TO admin;

--
-- Name: OXY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."OXY_news_from_2022_03" (
    CONSTRAINT "OXY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."OXY_news_from_2022_03" OWNER TO admin;

--
-- Name: O_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."O_news_from_2022_03" (
    CONSTRAINT "O_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."O_news_from_2022_03" OWNER TO admin;

--
-- Name: PAYC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PAYC_news_from_2022_03" (
    CONSTRAINT "PAYC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PAYC_news_from_2022_03" OWNER TO admin;

--
-- Name: PAYX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PAYX_news_from_2022_03" (
    CONSTRAINT "PAYX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PAYX_news_from_2022_03" OWNER TO admin;

--
-- Name: PBCT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PBCT_news_from_2022_03" (
    CONSTRAINT "PBCT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PBCT_news_from_2022_03" OWNER TO admin;

--
-- Name: PCAR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PCAR_news_from_2022_03" (
    CONSTRAINT "PCAR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PCAR_news_from_2022_03" OWNER TO admin;

--
-- Name: PEAK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PEAK_news_from_2022_03" (
    CONSTRAINT "PEAK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PEAK_news_from_2022_03" OWNER TO admin;

--
-- Name: PEG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PEG_news_from_2022_03" (
    CONSTRAINT "PEG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PEG_news_from_2022_03" OWNER TO admin;

--
-- Name: PENN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PENN_news_from_2022_03" (
    CONSTRAINT "PENN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PENN_news_from_2022_03" OWNER TO admin;

--
-- Name: PEP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PEP_news_from_2022_03" (
    CONSTRAINT "PEP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PEP_news_from_2022_03" OWNER TO admin;

--
-- Name: PFE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PFE_news_from_2022_03" (
    CONSTRAINT "PFE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PFE_news_from_2022_03" OWNER TO admin;

--
-- Name: PFG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PFG_news_from_2022_03" (
    CONSTRAINT "PFG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PFG_news_from_2022_03" OWNER TO admin;

--
-- Name: PGR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PGR_news_from_2022_03" (
    CONSTRAINT "PGR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PGR_news_from_2022_03" OWNER TO admin;

--
-- Name: PG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PG_news_from_2022_03" (
    CONSTRAINT "PG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PG_news_from_2022_03" OWNER TO admin;

--
-- Name: PHM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PHM_news_from_2022_03" (
    CONSTRAINT "PHM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PHM_news_from_2022_03" OWNER TO admin;

--
-- Name: PH_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PH_news_from_2022_03" (
    CONSTRAINT "PH_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PH_news_from_2022_03" OWNER TO admin;

--
-- Name: PKG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PKG_news_from_2022_03" (
    CONSTRAINT "PKG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PKG_news_from_2022_03" OWNER TO admin;

--
-- Name: PKI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PKI_news_from_2022_03" (
    CONSTRAINT "PKI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PKI_news_from_2022_03" OWNER TO admin;

--
-- Name: PLD_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PLD_news_from_2022_03" (
    CONSTRAINT "PLD_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PLD_news_from_2022_03" OWNER TO admin;

--
-- Name: PM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PM_news_from_2022_03" (
    CONSTRAINT "PM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PM_news_from_2022_03" OWNER TO admin;

--
-- Name: PNC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PNC_news_from_2022_03" (
    CONSTRAINT "PNC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PNC_news_from_2022_03" OWNER TO admin;

--
-- Name: PNR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PNR_news_from_2022_03" (
    CONSTRAINT "PNR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PNR_news_from_2022_03" OWNER TO admin;

--
-- Name: PNW_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PNW_news_from_2022_03" (
    CONSTRAINT "PNW_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PNW_news_from_2022_03" OWNER TO admin;

--
-- Name: POOL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."POOL_news_from_2022_03" (
    CONSTRAINT "POOL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."POOL_news_from_2022_03" OWNER TO admin;

--
-- Name: PPG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PPG_news_from_2022_03" (
    CONSTRAINT "PPG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PPG_news_from_2022_03" OWNER TO admin;

--
-- Name: PPL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PPL_news_from_2022_03" (
    CONSTRAINT "PPL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PPL_news_from_2022_03" OWNER TO admin;

--
-- Name: PRU_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PRU_news_from_2022_03" (
    CONSTRAINT "PRU_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PRU_news_from_2022_03" OWNER TO admin;

--
-- Name: PSA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PSA_news_from_2022_03" (
    CONSTRAINT "PSA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PSA_news_from_2022_03" OWNER TO admin;

--
-- Name: PSX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PSX_news_from_2022_03" (
    CONSTRAINT "PSX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PSX_news_from_2022_03" OWNER TO admin;

--
-- Name: PTC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PTC_news_from_2022_03" (
    CONSTRAINT "PTC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PTC_news_from_2022_03" OWNER TO admin;

--
-- Name: PVH_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PVH_news_from_2022_03" (
    CONSTRAINT "PVH_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PVH_news_from_2022_03" OWNER TO admin;

--
-- Name: PWR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PWR_news_from_2022_03" (
    CONSTRAINT "PWR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PWR_news_from_2022_03" OWNER TO admin;

--
-- Name: PXD_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PXD_news_from_2022_03" (
    CONSTRAINT "PXD_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PXD_news_from_2022_03" OWNER TO admin;

--
-- Name: PYPL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."PYPL_news_from_2022_03" (
    CONSTRAINT "PYPL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."PYPL_news_from_2022_03" OWNER TO admin;

--
-- Name: QCOM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."QCOM_news_from_2022_03" (
    CONSTRAINT "QCOM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."QCOM_news_from_2022_03" OWNER TO admin;

--
-- Name: QRVO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."QRVO_news_from_2022_03" (
    CONSTRAINT "QRVO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."QRVO_news_from_2022_03" OWNER TO admin;

--
-- Name: RCL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."RCL_news_from_2022_03" (
    CONSTRAINT "RCL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."RCL_news_from_2022_03" OWNER TO admin;

--
-- Name: REGN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."REGN_news_from_2022_03" (
    CONSTRAINT "REGN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."REGN_news_from_2022_03" OWNER TO admin;

--
-- Name: REG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."REG_news_from_2022_03" (
    CONSTRAINT "REG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."REG_news_from_2022_03" OWNER TO admin;

--
-- Name: RE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."RE_news_from_2022_03" (
    CONSTRAINT "RE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."RE_news_from_2022_03" OWNER TO admin;

--
-- Name: RF_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."RF_news_from_2022_03" (
    CONSTRAINT "RF_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."RF_news_from_2022_03" OWNER TO admin;

--
-- Name: RHI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."RHI_news_from_2022_03" (
    CONSTRAINT "RHI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."RHI_news_from_2022_03" OWNER TO admin;

--
-- Name: RJF_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."RJF_news_from_2022_03" (
    CONSTRAINT "RJF_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."RJF_news_from_2022_03" OWNER TO admin;

--
-- Name: RL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."RL_news_from_2022_03" (
    CONSTRAINT "RL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."RL_news_from_2022_03" OWNER TO admin;

--
-- Name: RMD_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."RMD_news_from_2022_03" (
    CONSTRAINT "RMD_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."RMD_news_from_2022_03" OWNER TO admin;

--
-- Name: ROK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ROK_news_from_2022_03" (
    CONSTRAINT "ROK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ROK_news_from_2022_03" OWNER TO admin;

--
-- Name: ROL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ROL_news_from_2022_03" (
    CONSTRAINT "ROL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ROL_news_from_2022_03" OWNER TO admin;

--
-- Name: ROP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ROP_news_from_2022_03" (
    CONSTRAINT "ROP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ROP_news_from_2022_03" OWNER TO admin;

--
-- Name: ROST_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ROST_news_from_2022_03" (
    CONSTRAINT "ROST_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ROST_news_from_2022_03" OWNER TO admin;

--
-- Name: RSG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."RSG_news_from_2022_03" (
    CONSTRAINT "RSG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."RSG_news_from_2022_03" OWNER TO admin;

--
-- Name: RTX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."RTX_news_from_2022_03" (
    CONSTRAINT "RTX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."RTX_news_from_2022_03" OWNER TO admin;

--
-- Name: SBAC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SBAC_news_from_2022_03" (
    CONSTRAINT "SBAC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SBAC_news_from_2022_03" OWNER TO admin;

--
-- Name: SBNY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SBNY_news_from_2022_03" (
    CONSTRAINT "SBNY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SBNY_news_from_2022_03" OWNER TO admin;

--
-- Name: SBUX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SBUX_news_from_2022_03" (
    CONSTRAINT "SBUX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SBUX_news_from_2022_03" OWNER TO admin;

--
-- Name: SCHW_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SCHW_news_from_2022_03" (
    CONSTRAINT "SCHW_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SCHW_news_from_2022_03" OWNER TO admin;

--
-- Name: SEDG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SEDG_news_from_2022_03" (
    CONSTRAINT "SEDG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SEDG_news_from_2022_03" OWNER TO admin;

--
-- Name: SEE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SEE_news_from_2022_03" (
    CONSTRAINT "SEE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SEE_news_from_2022_03" OWNER TO admin;

--
-- Name: SHW_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SHW_news_from_2022_03" (
    CONSTRAINT "SHW_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SHW_news_from_2022_03" OWNER TO admin;

--
-- Name: SIVB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SIVB_news_from_2022_03" (
    CONSTRAINT "SIVB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SIVB_news_from_2022_03" OWNER TO admin;

--
-- Name: SJM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SJM_news_from_2022_03" (
    CONSTRAINT "SJM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SJM_news_from_2022_03" OWNER TO admin;

--
-- Name: SLB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SLB_news_from_2022_03" (
    CONSTRAINT "SLB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SLB_news_from_2022_03" OWNER TO admin;

--
-- Name: SNA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SNA_news_from_2022_03" (
    CONSTRAINT "SNA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SNA_news_from_2022_03" OWNER TO admin;

--
-- Name: SNPS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SNPS_news_from_2022_03" (
    CONSTRAINT "SNPS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SNPS_news_from_2022_03" OWNER TO admin;

--
-- Name: SO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SO_news_from_2022_03" (
    CONSTRAINT "SO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SO_news_from_2022_03" OWNER TO admin;

--
-- Name: SPGI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SPGI_news_from_2022_03" (
    CONSTRAINT "SPGI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SPGI_news_from_2022_03" OWNER TO admin;

--
-- Name: SPG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SPG_news_from_2022_03" (
    CONSTRAINT "SPG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SPG_news_from_2022_03" OWNER TO admin;

--
-- Name: SRE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SRE_news_from_2022_03" (
    CONSTRAINT "SRE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SRE_news_from_2022_03" OWNER TO admin;

--
-- Name: STE_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."STE_news_from_2022_03" (
    CONSTRAINT "STE_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."STE_news_from_2022_03" OWNER TO admin;

--
-- Name: STT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."STT_news_from_2022_03" (
    CONSTRAINT "STT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."STT_news_from_2022_03" OWNER TO admin;

--
-- Name: STX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."STX_news_from_2022_03" (
    CONSTRAINT "STX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."STX_news_from_2022_03" OWNER TO admin;

--
-- Name: STZ_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."STZ_news_from_2022_03" (
    CONSTRAINT "STZ_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."STZ_news_from_2022_03" OWNER TO admin;

--
-- Name: SWKS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SWKS_news_from_2022_03" (
    CONSTRAINT "SWKS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SWKS_news_from_2022_03" OWNER TO admin;

--
-- Name: SWK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SWK_news_from_2022_03" (
    CONSTRAINT "SWK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SWK_news_from_2022_03" OWNER TO admin;

--
-- Name: SYF_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SYF_news_from_2022_03" (
    CONSTRAINT "SYF_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SYF_news_from_2022_03" OWNER TO admin;

--
-- Name: SYK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SYK_news_from_2022_03" (
    CONSTRAINT "SYK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SYK_news_from_2022_03" OWNER TO admin;

--
-- Name: SYY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."SYY_news_from_2022_03" (
    CONSTRAINT "SYY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."SYY_news_from_2022_03" OWNER TO admin;

--
-- Name: TAP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TAP_news_from_2022_03" (
    CONSTRAINT "TAP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TAP_news_from_2022_03" OWNER TO admin;

--
-- Name: TDG_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TDG_news_from_2022_03" (
    CONSTRAINT "TDG_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TDG_news_from_2022_03" OWNER TO admin;

--
-- Name: TDY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TDY_news_from_2022_03" (
    CONSTRAINT "TDY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TDY_news_from_2022_03" OWNER TO admin;

--
-- Name: TECH_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TECH_news_from_2022_03" (
    CONSTRAINT "TECH_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TECH_news_from_2022_03" OWNER TO admin;

--
-- Name: TEL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TEL_news_from_2022_03" (
    CONSTRAINT "TEL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TEL_news_from_2022_03" OWNER TO admin;

--
-- Name: TER_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TER_news_from_2022_03" (
    CONSTRAINT "TER_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TER_news_from_2022_03" OWNER TO admin;

--
-- Name: TFC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TFC_news_from_2022_03" (
    CONSTRAINT "TFC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TFC_news_from_2022_03" OWNER TO admin;

--
-- Name: TFX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TFX_news_from_2022_03" (
    CONSTRAINT "TFX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TFX_news_from_2022_03" OWNER TO admin;

--
-- Name: TGT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TGT_news_from_2022_03" (
    CONSTRAINT "TGT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TGT_news_from_2022_03" OWNER TO admin;

--
-- Name: TJX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TJX_news_from_2022_03" (
    CONSTRAINT "TJX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TJX_news_from_2022_03" OWNER TO admin;

--
-- Name: TMO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TMO_news_from_2022_03" (
    CONSTRAINT "TMO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TMO_news_from_2022_03" OWNER TO admin;

--
-- Name: TMUS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TMUS_news_from_2022_03" (
    CONSTRAINT "TMUS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TMUS_news_from_2022_03" OWNER TO admin;

--
-- Name: TPR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TPR_news_from_2022_03" (
    CONSTRAINT "TPR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TPR_news_from_2022_03" OWNER TO admin;

--
-- Name: TRMB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TRMB_news_from_2022_03" (
    CONSTRAINT "TRMB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TRMB_news_from_2022_03" OWNER TO admin;

--
-- Name: TROW_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TROW_news_from_2022_03" (
    CONSTRAINT "TROW_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TROW_news_from_2022_03" OWNER TO admin;

--
-- Name: TRV_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TRV_news_from_2022_03" (
    CONSTRAINT "TRV_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TRV_news_from_2022_03" OWNER TO admin;

--
-- Name: TSCO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TSCO_news_from_2022_03" (
    CONSTRAINT "TSCO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TSCO_news_from_2022_03" OWNER TO admin;

--
-- Name: TSLA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TSLA_news_from_2022_03" (
    CONSTRAINT "TSLA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TSLA_news_from_2022_03" OWNER TO admin;

--
-- Name: TSN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TSN_news_from_2022_03" (
    CONSTRAINT "TSN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TSN_news_from_2022_03" OWNER TO admin;

--
-- Name: TTWO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TTWO_news_from_2022_03" (
    CONSTRAINT "TTWO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TTWO_news_from_2022_03" OWNER TO admin;

--
-- Name: TT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TT_news_from_2022_03" (
    CONSTRAINT "TT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TT_news_from_2022_03" OWNER TO admin;

--
-- Name: TWTR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TWTR_news_from_2022_03" (
    CONSTRAINT "TWTR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TWTR_news_from_2022_03" OWNER TO admin;

--
-- Name: TXN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TXN_news_from_2022_03" (
    CONSTRAINT "TXN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TXN_news_from_2022_03" OWNER TO admin;

--
-- Name: TXT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TXT_news_from_2022_03" (
    CONSTRAINT "TXT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TXT_news_from_2022_03" OWNER TO admin;

--
-- Name: TYL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."TYL_news_from_2022_03" (
    CONSTRAINT "TYL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."TYL_news_from_2022_03" OWNER TO admin;

--
-- Name: T_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."T_news_from_2022_03" (
    CONSTRAINT "T_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."T_news_from_2022_03" OWNER TO admin;

--
-- Name: UAA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."UAA_news_from_2022_03" (
    CONSTRAINT "UAA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."UAA_news_from_2022_03" OWNER TO admin;

--
-- Name: UAL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."UAL_news_from_2022_03" (
    CONSTRAINT "UAL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."UAL_news_from_2022_03" OWNER TO admin;

--
-- Name: UA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."UA_news_from_2022_03" (
    CONSTRAINT "UA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."UA_news_from_2022_03" OWNER TO admin;

--
-- Name: UDR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."UDR_news_from_2022_03" (
    CONSTRAINT "UDR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."UDR_news_from_2022_03" OWNER TO admin;

--
-- Name: UHS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."UHS_news_from_2022_03" (
    CONSTRAINT "UHS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."UHS_news_from_2022_03" OWNER TO admin;

--
-- Name: ULTA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ULTA_news_from_2022_03" (
    CONSTRAINT "ULTA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ULTA_news_from_2022_03" OWNER TO admin;

--
-- Name: UNH_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."UNH_news_from_2022_03" (
    CONSTRAINT "UNH_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."UNH_news_from_2022_03" OWNER TO admin;

--
-- Name: UNP_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."UNP_news_from_2022_03" (
    CONSTRAINT "UNP_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."UNP_news_from_2022_03" OWNER TO admin;

--
-- Name: UPS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."UPS_news_from_2022_03" (
    CONSTRAINT "UPS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."UPS_news_from_2022_03" OWNER TO admin;

--
-- Name: URI_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."URI_news_from_2022_03" (
    CONSTRAINT "URI_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."URI_news_from_2022_03" OWNER TO admin;

--
-- Name: USB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."USB_news_from_2022_03" (
    CONSTRAINT "USB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."USB_news_from_2022_03" OWNER TO admin;

--
-- Name: VFC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."VFC_news_from_2022_03" (
    CONSTRAINT "VFC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."VFC_news_from_2022_03" OWNER TO admin;

--
-- Name: VIAC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."VIAC_news_from_2022_03" (
    CONSTRAINT "VIAC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."VIAC_news_from_2022_03" OWNER TO admin;

--
-- Name: VLO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."VLO_news_from_2022_03" (
    CONSTRAINT "VLO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."VLO_news_from_2022_03" OWNER TO admin;

--
-- Name: VMC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."VMC_news_from_2022_03" (
    CONSTRAINT "VMC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."VMC_news_from_2022_03" OWNER TO admin;

--
-- Name: VNO_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."VNO_news_from_2022_03" (
    CONSTRAINT "VNO_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."VNO_news_from_2022_03" OWNER TO admin;

--
-- Name: VRSK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."VRSK_news_from_2022_03" (
    CONSTRAINT "VRSK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."VRSK_news_from_2022_03" OWNER TO admin;

--
-- Name: VRSN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."VRSN_news_from_2022_03" (
    CONSTRAINT "VRSN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."VRSN_news_from_2022_03" OWNER TO admin;

--
-- Name: VRTX_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."VRTX_news_from_2022_03" (
    CONSTRAINT "VRTX_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."VRTX_news_from_2022_03" OWNER TO admin;

--
-- Name: VTRS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."VTRS_news_from_2022_03" (
    CONSTRAINT "VTRS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."VTRS_news_from_2022_03" OWNER TO admin;

--
-- Name: VTR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."VTR_news_from_2022_03" (
    CONSTRAINT "VTR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."VTR_news_from_2022_03" OWNER TO admin;

--
-- Name: VZ_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."VZ_news_from_2022_03" (
    CONSTRAINT "VZ_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."VZ_news_from_2022_03" OWNER TO admin;

--
-- Name: V_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."V_news_from_2022_03" (
    CONSTRAINT "V_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."V_news_from_2022_03" OWNER TO admin;

--
-- Name: WAB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WAB_news_from_2022_03" (
    CONSTRAINT "WAB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WAB_news_from_2022_03" OWNER TO admin;

--
-- Name: WAT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WAT_news_from_2022_03" (
    CONSTRAINT "WAT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WAT_news_from_2022_03" OWNER TO admin;

--
-- Name: WBA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WBA_news_from_2022_03" (
    CONSTRAINT "WBA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WBA_news_from_2022_03" OWNER TO admin;

--
-- Name: WDC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WDC_news_from_2022_03" (
    CONSTRAINT "WDC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WDC_news_from_2022_03" OWNER TO admin;

--
-- Name: WEC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WEC_news_from_2022_03" (
    CONSTRAINT "WEC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WEC_news_from_2022_03" OWNER TO admin;

--
-- Name: WELL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WELL_news_from_2022_03" (
    CONSTRAINT "WELL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WELL_news_from_2022_03" OWNER TO admin;

--
-- Name: WFC_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WFC_news_from_2022_03" (
    CONSTRAINT "WFC_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WFC_news_from_2022_03" OWNER TO admin;

--
-- Name: WHR_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WHR_news_from_2022_03" (
    CONSTRAINT "WHR_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WHR_news_from_2022_03" OWNER TO admin;

--
-- Name: WMB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WMB_news_from_2022_03" (
    CONSTRAINT "WMB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WMB_news_from_2022_03" OWNER TO admin;

--
-- Name: WMT_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WMT_news_from_2022_03" (
    CONSTRAINT "WMT_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WMT_news_from_2022_03" OWNER TO admin;

--
-- Name: WM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WM_news_from_2022_03" (
    CONSTRAINT "WM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WM_news_from_2022_03" OWNER TO admin;

--
-- Name: WRB_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WRB_news_from_2022_03" (
    CONSTRAINT "WRB_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WRB_news_from_2022_03" OWNER TO admin;

--
-- Name: WRK_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WRK_news_from_2022_03" (
    CONSTRAINT "WRK_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WRK_news_from_2022_03" OWNER TO admin;

--
-- Name: WST_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WST_news_from_2022_03" (
    CONSTRAINT "WST_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WST_news_from_2022_03" OWNER TO admin;

--
-- Name: WTW_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WTW_news_from_2022_03" (
    CONSTRAINT "WTW_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WTW_news_from_2022_03" OWNER TO admin;

--
-- Name: WYNN_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WYNN_news_from_2022_03" (
    CONSTRAINT "WYNN_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WYNN_news_from_2022_03" OWNER TO admin;

--
-- Name: WY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."WY_news_from_2022_03" (
    CONSTRAINT "WY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."WY_news_from_2022_03" OWNER TO admin;

--
-- Name: XEL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."XEL_news_from_2022_03" (
    CONSTRAINT "XEL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."XEL_news_from_2022_03" OWNER TO admin;

--
-- Name: XOM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."XOM_news_from_2022_03" (
    CONSTRAINT "XOM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."XOM_news_from_2022_03" OWNER TO admin;

--
-- Name: XRAY_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."XRAY_news_from_2022_03" (
    CONSTRAINT "XRAY_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."XRAY_news_from_2022_03" OWNER TO admin;

--
-- Name: XYL_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."XYL_news_from_2022_03" (
    CONSTRAINT "XYL_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."XYL_news_from_2022_03" OWNER TO admin;

--
-- Name: YUM_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."YUM_news_from_2022_03" (
    CONSTRAINT "YUM_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."YUM_news_from_2022_03" OWNER TO admin;

--
-- Name: ZBH_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ZBH_news_from_2022_03" (
    CONSTRAINT "ZBH_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ZBH_news_from_2022_03" OWNER TO admin;

--
-- Name: ZBRA_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ZBRA_news_from_2022_03" (
    CONSTRAINT "ZBRA_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ZBRA_news_from_2022_03" OWNER TO admin;

--
-- Name: ZION_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ZION_news_from_2022_03" (
    CONSTRAINT "ZION_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ZION_news_from_2022_03" OWNER TO admin;

--
-- Name: ZTS_news_from_2022_03; Type: TABLE; Schema: news; Owner: admin
--

CREATE TABLE news."ZTS_news_from_2022_03" (
    CONSTRAINT "ZTS_news_from_2022_03_download_time_check" CHECK (((date_trunc('day'::text, download_time) >= '2022-03-01 00:00:00+00'::timestamp with time zone) AND (date_trunc('day'::text, download_time) < '2022-04-01 00:00:00+00'::timestamp with time zone)))
)
INHERITS (news.news);


ALTER TABLE news."ZTS_news_from_2022_03" OWNER TO admin;

--
-- Name: news_id_seq; Type: SEQUENCE; Schema: news; Owner: admin
--

CREATE SEQUENCE news.news_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE news.news_id_seq OWNER TO admin;

--
-- Name: news_id_seq; Type: SEQUENCE OWNED BY; Schema: news; Owner: admin
--

ALTER SEQUENCE news.news_id_seq OWNED BY news.news.id;


--
-- Name: a_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.a_partition FOR VALUES IN ('a');


--
-- Name: aal_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.aal_partition FOR VALUES IN ('aal');


--
-- Name: aap_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.aap_partition FOR VALUES IN ('aap');


--
-- Name: aapl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.aapl_partition FOR VALUES IN ('aapl');


--
-- Name: abbv_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.abbv_partition FOR VALUES IN ('abbv');


--
-- Name: abc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.abc_partition FOR VALUES IN ('abc');


--
-- Name: abmd_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.abmd_partition FOR VALUES IN ('abmd');


--
-- Name: abt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.abt_partition FOR VALUES IN ('abt');


--
-- Name: acn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.acn_partition FOR VALUES IN ('acn');


--
-- Name: adbe_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.adbe_partition FOR VALUES IN ('adbe');


--
-- Name: adi_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.adi_partition FOR VALUES IN ('adi');


--
-- Name: adm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.adm_partition FOR VALUES IN ('adm');


--
-- Name: adp_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.adp_partition FOR VALUES IN ('adp');


--
-- Name: adsk_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.adsk_partition FOR VALUES IN ('adsk');


--
-- Name: aee_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.aee_partition FOR VALUES IN ('aee');


--
-- Name: aep_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.aep_partition FOR VALUES IN ('aep');


--
-- Name: aes_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.aes_partition FOR VALUES IN ('aes');


--
-- Name: afl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.afl_partition FOR VALUES IN ('afl');


--
-- Name: aig_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.aig_partition FOR VALUES IN ('aig');


--
-- Name: aiz_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.aiz_partition FOR VALUES IN ('aiz');


--
-- Name: ajg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ajg_partition FOR VALUES IN ('ajg');


--
-- Name: akam_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.akam_partition FOR VALUES IN ('akam');


--
-- Name: alb_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.alb_partition FOR VALUES IN ('alb');


--
-- Name: algn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.algn_partition FOR VALUES IN ('algn');


--
-- Name: alk_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.alk_partition FOR VALUES IN ('alk');


--
-- Name: all_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.all_partition FOR VALUES IN ('all');


--
-- Name: alle_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.alle_partition FOR VALUES IN ('alle');


--
-- Name: amat_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.amat_partition FOR VALUES IN ('amat');


--
-- Name: amcr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.amcr_partition FOR VALUES IN ('amcr');


--
-- Name: amd_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.amd_partition FOR VALUES IN ('amd');


--
-- Name: ame_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ame_partition FOR VALUES IN ('ame');


--
-- Name: amgn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.amgn_partition FOR VALUES IN ('amgn');


--
-- Name: amp_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.amp_partition FOR VALUES IN ('amp');


--
-- Name: amt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.amt_partition FOR VALUES IN ('amt');


--
-- Name: amzn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.amzn_partition FOR VALUES IN ('amzn');


--
-- Name: anet_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.anet_partition FOR VALUES IN ('anet');


--
-- Name: anss_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.anss_partition FOR VALUES IN ('anss');


--
-- Name: antm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.antm_partition FOR VALUES IN ('antm');


--
-- Name: aon_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.aon_partition FOR VALUES IN ('aon');


--
-- Name: aos_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.aos_partition FOR VALUES IN ('aos');


--
-- Name: apa_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.apa_partition FOR VALUES IN ('apa');


--
-- Name: apd_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.apd_partition FOR VALUES IN ('apd');


--
-- Name: aph_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.aph_partition FOR VALUES IN ('aph');


--
-- Name: aptv_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.aptv_partition FOR VALUES IN ('aptv');


--
-- Name: are_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.are_partition FOR VALUES IN ('are');


--
-- Name: ato_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ato_partition FOR VALUES IN ('ato');


--
-- Name: atvi_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.atvi_partition FOR VALUES IN ('atvi');


--
-- Name: avb_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.avb_partition FOR VALUES IN ('avb');


--
-- Name: avgo_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.avgo_partition FOR VALUES IN ('avgo');


--
-- Name: avy_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.avy_partition FOR VALUES IN ('avy');


--
-- Name: awk_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.awk_partition FOR VALUES IN ('awk');


--
-- Name: axp_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.axp_partition FOR VALUES IN ('axp');


--
-- Name: azo_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.azo_partition FOR VALUES IN ('azo');


--
-- Name: ba_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ba_partition FOR VALUES IN ('ba');


--
-- Name: bac_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.bac_partition FOR VALUES IN ('bac');


--
-- Name: bax_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.bax_partition FOR VALUES IN ('bax');


--
-- Name: bbwi_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.bbwi_partition FOR VALUES IN ('bbwi');


--
-- Name: bby_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.bby_partition FOR VALUES IN ('bby');


--
-- Name: bdx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.bdx_partition FOR VALUES IN ('bdx');


--
-- Name: ben_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ben_partition FOR VALUES IN ('ben');


--
-- Name: bf.b_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db."bf.b_partition" FOR VALUES IN ('bf.b');


--
-- Name: biib_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.biib_partition FOR VALUES IN ('biib');


--
-- Name: bio_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.bio_partition FOR VALUES IN ('bio');


--
-- Name: bk_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.bk_partition FOR VALUES IN ('bk');


--
-- Name: bkng_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.bkng_partition FOR VALUES IN ('bkng');


--
-- Name: bkr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.bkr_partition FOR VALUES IN ('bkr');


--
-- Name: blk_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.blk_partition FOR VALUES IN ('blk');


--
-- Name: bll_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.bll_partition FOR VALUES IN ('bll');


--
-- Name: bmy_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.bmy_partition FOR VALUES IN ('bmy');


--
-- Name: br_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.br_partition FOR VALUES IN ('br');


--
-- Name: brk.b_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db."brk.b_partition" FOR VALUES IN ('brk.b');


--
-- Name: bro_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.bro_partition FOR VALUES IN ('bro');


--
-- Name: bsx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.bsx_partition FOR VALUES IN ('bsx');


--
-- Name: bwa_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.bwa_partition FOR VALUES IN ('bwa');


--
-- Name: bxp_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.bxp_partition FOR VALUES IN ('bxp');


--
-- Name: c_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.c_partition FOR VALUES IN ('c');


--
-- Name: cag_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cag_partition FOR VALUES IN ('cag');


--
-- Name: cah_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cah_partition FOR VALUES IN ('cah');


--
-- Name: carr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.carr_partition FOR VALUES IN ('carr');


--
-- Name: cat_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cat_partition FOR VALUES IN ('cat');


--
-- Name: cb_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cb_partition FOR VALUES IN ('cb');


--
-- Name: cboe_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cboe_partition FOR VALUES IN ('cboe');


--
-- Name: cbre_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cbre_partition FOR VALUES IN ('cbre');


--
-- Name: cci_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cci_partition FOR VALUES IN ('cci');


--
-- Name: ccl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ccl_partition FOR VALUES IN ('ccl');


--
-- Name: cday_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cday_partition FOR VALUES IN ('cday');


--
-- Name: cdns_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cdns_partition FOR VALUES IN ('cdns');


--
-- Name: cdw_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cdw_partition FOR VALUES IN ('cdw');


--
-- Name: ce_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ce_partition FOR VALUES IN ('ce');


--
-- Name: ceg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ceg_partition FOR VALUES IN ('ceg');


--
-- Name: cern_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cern_partition FOR VALUES IN ('cern');


--
-- Name: cf_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cf_partition FOR VALUES IN ('cf');


--
-- Name: cfg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cfg_partition FOR VALUES IN ('cfg');


--
-- Name: chd_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.chd_partition FOR VALUES IN ('chd');


--
-- Name: chrw_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.chrw_partition FOR VALUES IN ('chrw');


--
-- Name: chtr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.chtr_partition FOR VALUES IN ('chtr');


--
-- Name: ci_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ci_partition FOR VALUES IN ('ci');


--
-- Name: cinf_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cinf_partition FOR VALUES IN ('cinf');


--
-- Name: cl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cl_partition FOR VALUES IN ('cl');


--
-- Name: clx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.clx_partition FOR VALUES IN ('clx');


--
-- Name: cma_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cma_partition FOR VALUES IN ('cma');


--
-- Name: cmcsa_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cmcsa_partition FOR VALUES IN ('cmcsa');


--
-- Name: cme_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cme_partition FOR VALUES IN ('cme');


--
-- Name: cmg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cmg_partition FOR VALUES IN ('cmg');


--
-- Name: cmi_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cmi_partition FOR VALUES IN ('cmi');


--
-- Name: cms_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cms_partition FOR VALUES IN ('cms');


--
-- Name: cnc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cnc_partition FOR VALUES IN ('cnc');


--
-- Name: cnp_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cnp_partition FOR VALUES IN ('cnp');


--
-- Name: cof_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cof_partition FOR VALUES IN ('cof');


--
-- Name: coo_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.coo_partition FOR VALUES IN ('coo');


--
-- Name: cop_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cop_partition FOR VALUES IN ('cop');


--
-- Name: cost_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cost_partition FOR VALUES IN ('cost');


--
-- Name: cpb_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cpb_partition FOR VALUES IN ('cpb');


--
-- Name: cprt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cprt_partition FOR VALUES IN ('cprt');


--
-- Name: crl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.crl_partition FOR VALUES IN ('crl');


--
-- Name: crm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.crm_partition FOR VALUES IN ('crm');


--
-- Name: csco_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.csco_partition FOR VALUES IN ('csco');


--
-- Name: csx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.csx_partition FOR VALUES IN ('csx');


--
-- Name: ctas_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ctas_partition FOR VALUES IN ('ctas');


--
-- Name: ctlt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ctlt_partition FOR VALUES IN ('ctlt');


--
-- Name: ctra_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ctra_partition FOR VALUES IN ('ctra');


--
-- Name: ctsh_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ctsh_partition FOR VALUES IN ('ctsh');


--
-- Name: ctva_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ctva_partition FOR VALUES IN ('ctva');


--
-- Name: ctxs_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ctxs_partition FOR VALUES IN ('ctxs');


--
-- Name: cvs_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cvs_partition FOR VALUES IN ('cvs');


--
-- Name: cvx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.cvx_partition FOR VALUES IN ('cvx');


--
-- Name: czr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.czr_partition FOR VALUES IN ('czr');


--
-- Name: d_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.d_partition FOR VALUES IN ('d');


--
-- Name: dal_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dal_partition FOR VALUES IN ('dal');


--
-- Name: dd_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dd_partition FOR VALUES IN ('dd');


--
-- Name: de_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.de_partition FOR VALUES IN ('de');


--
-- Name: dfs_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dfs_partition FOR VALUES IN ('dfs');


--
-- Name: dg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dg_partition FOR VALUES IN ('dg');


--
-- Name: dgx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dgx_partition FOR VALUES IN ('dgx');


--
-- Name: dhi_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dhi_partition FOR VALUES IN ('dhi');


--
-- Name: dhr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dhr_partition FOR VALUES IN ('dhr');


--
-- Name: dis_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dis_partition FOR VALUES IN ('dis');


--
-- Name: disca_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.disca_partition FOR VALUES IN ('disca');


--
-- Name: disck_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.disck_partition FOR VALUES IN ('disck');


--
-- Name: dish_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dish_partition FOR VALUES IN ('dish');


--
-- Name: dlr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dlr_partition FOR VALUES IN ('dlr');


--
-- Name: dltr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dltr_partition FOR VALUES IN ('dltr');


--
-- Name: dov_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dov_partition FOR VALUES IN ('dov');


--
-- Name: dow_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dow_partition FOR VALUES IN ('dow');


--
-- Name: dpz_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dpz_partition FOR VALUES IN ('dpz');


--
-- Name: dre_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dre_partition FOR VALUES IN ('dre');


--
-- Name: dri_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dri_partition FOR VALUES IN ('dri');


--
-- Name: dte_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dte_partition FOR VALUES IN ('dte');


--
-- Name: duk_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.duk_partition FOR VALUES IN ('duk');


--
-- Name: dva_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dva_partition FOR VALUES IN ('dva');


--
-- Name: dvn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dvn_partition FOR VALUES IN ('dvn');


--
-- Name: dxc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dxc_partition FOR VALUES IN ('dxc');


--
-- Name: dxcm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.dxcm_partition FOR VALUES IN ('dxcm');


--
-- Name: ea_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ea_partition FOR VALUES IN ('ea');


--
-- Name: ebay_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ebay_partition FOR VALUES IN ('ebay');


--
-- Name: ecl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ecl_partition FOR VALUES IN ('ecl');


--
-- Name: ed_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ed_partition FOR VALUES IN ('ed');


--
-- Name: efx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.efx_partition FOR VALUES IN ('efx');


--
-- Name: eix_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.eix_partition FOR VALUES IN ('eix');


--
-- Name: el_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.el_partition FOR VALUES IN ('el');


--
-- Name: emn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.emn_partition FOR VALUES IN ('emn');


--
-- Name: emr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.emr_partition FOR VALUES IN ('emr');


--
-- Name: enph_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.enph_partition FOR VALUES IN ('enph');


--
-- Name: eog_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.eog_partition FOR VALUES IN ('eog');


--
-- Name: epam_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.epam_partition FOR VALUES IN ('epam');


--
-- Name: eqix_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.eqix_partition FOR VALUES IN ('eqix');


--
-- Name: eqr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.eqr_partition FOR VALUES IN ('eqr');


--
-- Name: es_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.es_partition FOR VALUES IN ('es');


--
-- Name: ess_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ess_partition FOR VALUES IN ('ess');


--
-- Name: etn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.etn_partition FOR VALUES IN ('etn');


--
-- Name: etr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.etr_partition FOR VALUES IN ('etr');


--
-- Name: etsy_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.etsy_partition FOR VALUES IN ('etsy');


--
-- Name: evrg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.evrg_partition FOR VALUES IN ('evrg');


--
-- Name: ew_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ew_partition FOR VALUES IN ('ew');


--
-- Name: exc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.exc_partition FOR VALUES IN ('exc');


--
-- Name: expd_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.expd_partition FOR VALUES IN ('expd');


--
-- Name: expe_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.expe_partition FOR VALUES IN ('expe');


--
-- Name: exr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.exr_partition FOR VALUES IN ('exr');


--
-- Name: f_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.f_partition FOR VALUES IN ('f');


--
-- Name: fang_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.fang_partition FOR VALUES IN ('fang');


--
-- Name: fast_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.fast_partition FOR VALUES IN ('fast');


--
-- Name: fb_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.fb_partition FOR VALUES IN ('fb');


--
-- Name: fbhs_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.fbhs_partition FOR VALUES IN ('fbhs');


--
-- Name: fcx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.fcx_partition FOR VALUES IN ('fcx');


--
-- Name: fds_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.fds_partition FOR VALUES IN ('fds');


--
-- Name: fdx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.fdx_partition FOR VALUES IN ('fdx');


--
-- Name: fe_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.fe_partition FOR VALUES IN ('fe');


--
-- Name: ffiv_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ffiv_partition FOR VALUES IN ('ffiv');


--
-- Name: fis_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.fis_partition FOR VALUES IN ('fis');


--
-- Name: fisv_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.fisv_partition FOR VALUES IN ('fisv');


--
-- Name: fitb_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.fitb_partition FOR VALUES IN ('fitb');


--
-- Name: flt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.flt_partition FOR VALUES IN ('flt');


--
-- Name: fmc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.fmc_partition FOR VALUES IN ('fmc');


--
-- Name: fox_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.fox_partition FOR VALUES IN ('fox');


--
-- Name: foxa_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.foxa_partition FOR VALUES IN ('foxa');


--
-- Name: frc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.frc_partition FOR VALUES IN ('frc');


--
-- Name: frt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.frt_partition FOR VALUES IN ('frt');


--
-- Name: ftnt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ftnt_partition FOR VALUES IN ('ftnt');


--
-- Name: ftv_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ftv_partition FOR VALUES IN ('ftv');


--
-- Name: gd_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.gd_partition FOR VALUES IN ('gd');


--
-- Name: ge_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ge_partition FOR VALUES IN ('ge');


--
-- Name: gild_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.gild_partition FOR VALUES IN ('gild');


--
-- Name: gis_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.gis_partition FOR VALUES IN ('gis');


--
-- Name: gl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.gl_partition FOR VALUES IN ('gl');


--
-- Name: glw_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.glw_partition FOR VALUES IN ('glw');


--
-- Name: gm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.gm_partition FOR VALUES IN ('gm');


--
-- Name: gnrc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.gnrc_partition FOR VALUES IN ('gnrc');


--
-- Name: goog_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.goog_partition FOR VALUES IN ('goog');


--
-- Name: googl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.googl_partition FOR VALUES IN ('googl');


--
-- Name: gpc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.gpc_partition FOR VALUES IN ('gpc');


--
-- Name: gpn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.gpn_partition FOR VALUES IN ('gpn');


--
-- Name: grmn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.grmn_partition FOR VALUES IN ('grmn');


--
-- Name: gs_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.gs_partition FOR VALUES IN ('gs');


--
-- Name: gww_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.gww_partition FOR VALUES IN ('gww');


--
-- Name: hal_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hal_partition FOR VALUES IN ('hal');


--
-- Name: has_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.has_partition FOR VALUES IN ('has');


--
-- Name: hban_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hban_partition FOR VALUES IN ('hban');


--
-- Name: hca_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hca_partition FOR VALUES IN ('hca');


--
-- Name: hd_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hd_partition FOR VALUES IN ('hd');


--
-- Name: hes_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hes_partition FOR VALUES IN ('hes');


--
-- Name: hig_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hig_partition FOR VALUES IN ('hig');


--
-- Name: hii_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hii_partition FOR VALUES IN ('hii');


--
-- Name: hlt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hlt_partition FOR VALUES IN ('hlt');


--
-- Name: holx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.holx_partition FOR VALUES IN ('holx');


--
-- Name: hon_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hon_partition FOR VALUES IN ('hon');


--
-- Name: hpe_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hpe_partition FOR VALUES IN ('hpe');


--
-- Name: hpq_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hpq_partition FOR VALUES IN ('hpq');


--
-- Name: hrl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hrl_partition FOR VALUES IN ('hrl');


--
-- Name: hsic_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hsic_partition FOR VALUES IN ('hsic');


--
-- Name: hst_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hst_partition FOR VALUES IN ('hst');


--
-- Name: hsy_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hsy_partition FOR VALUES IN ('hsy');


--
-- Name: hum_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hum_partition FOR VALUES IN ('hum');


--
-- Name: hwm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.hwm_partition FOR VALUES IN ('hwm');


--
-- Name: ibm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ibm_partition FOR VALUES IN ('ibm');


--
-- Name: ice_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ice_partition FOR VALUES IN ('ice');


--
-- Name: idxx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.idxx_partition FOR VALUES IN ('idxx');


--
-- Name: iex_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.iex_partition FOR VALUES IN ('iex');


--
-- Name: iff_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.iff_partition FOR VALUES IN ('iff');


--
-- Name: ilmn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ilmn_partition FOR VALUES IN ('ilmn');


--
-- Name: incy_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.incy_partition FOR VALUES IN ('incy');


--
-- Name: info_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.info_partition FOR VALUES IN ('info');


--
-- Name: intc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.intc_partition FOR VALUES IN ('intc');


--
-- Name: intu_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.intu_partition FOR VALUES IN ('intu');


--
-- Name: ip_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ip_partition FOR VALUES IN ('ip');


--
-- Name: ipg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ipg_partition FOR VALUES IN ('ipg');


--
-- Name: ipgp_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ipgp_partition FOR VALUES IN ('ipgp');


--
-- Name: iqv_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.iqv_partition FOR VALUES IN ('iqv');


--
-- Name: ir_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ir_partition FOR VALUES IN ('ir');


--
-- Name: irm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.irm_partition FOR VALUES IN ('irm');


--
-- Name: isrg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.isrg_partition FOR VALUES IN ('isrg');


--
-- Name: it_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.it_partition FOR VALUES IN ('it');


--
-- Name: itw_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.itw_partition FOR VALUES IN ('itw');


--
-- Name: ivz_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ivz_partition FOR VALUES IN ('ivz');


--
-- Name: j_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.j_partition FOR VALUES IN ('j');


--
-- Name: jbht_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.jbht_partition FOR VALUES IN ('jbht');


--
-- Name: jci_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.jci_partition FOR VALUES IN ('jci');


--
-- Name: jkhy_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.jkhy_partition FOR VALUES IN ('jkhy');


--
-- Name: jnj_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.jnj_partition FOR VALUES IN ('jnj');


--
-- Name: jnpr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.jnpr_partition FOR VALUES IN ('jnpr');


--
-- Name: jpm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.jpm_partition FOR VALUES IN ('jpm');


--
-- Name: k_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.k_partition FOR VALUES IN ('k');


--
-- Name: key_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.key_partition FOR VALUES IN ('key');


--
-- Name: keys_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.keys_partition FOR VALUES IN ('keys');


--
-- Name: khc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.khc_partition FOR VALUES IN ('khc');


--
-- Name: kim_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.kim_partition FOR VALUES IN ('kim');


--
-- Name: klac_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.klac_partition FOR VALUES IN ('klac');


--
-- Name: kmb_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.kmb_partition FOR VALUES IN ('kmb');


--
-- Name: kmi_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.kmi_partition FOR VALUES IN ('kmi');


--
-- Name: kmx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.kmx_partition FOR VALUES IN ('kmx');


--
-- Name: ko_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ko_partition FOR VALUES IN ('ko');


--
-- Name: kr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.kr_partition FOR VALUES IN ('kr');


--
-- Name: l_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.l_partition FOR VALUES IN ('l');


--
-- Name: ldos_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ldos_partition FOR VALUES IN ('ldos');


--
-- Name: len_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.len_partition FOR VALUES IN ('len');


--
-- Name: lh_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.lh_partition FOR VALUES IN ('lh');


--
-- Name: lhx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.lhx_partition FOR VALUES IN ('lhx');


--
-- Name: lin_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.lin_partition FOR VALUES IN ('lin');


--
-- Name: lkq_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.lkq_partition FOR VALUES IN ('lkq');


--
-- Name: lly_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.lly_partition FOR VALUES IN ('lly');


--
-- Name: lmt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.lmt_partition FOR VALUES IN ('lmt');


--
-- Name: lnc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.lnc_partition FOR VALUES IN ('lnc');


--
-- Name: lnt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.lnt_partition FOR VALUES IN ('lnt');


--
-- Name: low_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.low_partition FOR VALUES IN ('low');


--
-- Name: lrcx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.lrcx_partition FOR VALUES IN ('lrcx');


--
-- Name: lumn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.lumn_partition FOR VALUES IN ('lumn');


--
-- Name: luv_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.luv_partition FOR VALUES IN ('luv');


--
-- Name: lvs_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.lvs_partition FOR VALUES IN ('lvs');


--
-- Name: lw_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.lw_partition FOR VALUES IN ('lw');


--
-- Name: lyb_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.lyb_partition FOR VALUES IN ('lyb');


--
-- Name: lyv_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.lyv_partition FOR VALUES IN ('lyv');


--
-- Name: ma_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ma_partition FOR VALUES IN ('ma');


--
-- Name: maa_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.maa_partition FOR VALUES IN ('maa');


--
-- Name: mar_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mar_partition FOR VALUES IN ('mar');


--
-- Name: mas_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mas_partition FOR VALUES IN ('mas');


--
-- Name: mcd_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mcd_partition FOR VALUES IN ('mcd');


--
-- Name: mchp_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mchp_partition FOR VALUES IN ('mchp');


--
-- Name: mck_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mck_partition FOR VALUES IN ('mck');


--
-- Name: mco_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mco_partition FOR VALUES IN ('mco');


--
-- Name: mdlz_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mdlz_partition FOR VALUES IN ('mdlz');


--
-- Name: mdt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mdt_partition FOR VALUES IN ('mdt');


--
-- Name: met_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.met_partition FOR VALUES IN ('met');


--
-- Name: mgm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mgm_partition FOR VALUES IN ('mgm');


--
-- Name: mhk_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mhk_partition FOR VALUES IN ('mhk');


--
-- Name: mkc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mkc_partition FOR VALUES IN ('mkc');


--
-- Name: mktx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mktx_partition FOR VALUES IN ('mktx');


--
-- Name: mlm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mlm_partition FOR VALUES IN ('mlm');


--
-- Name: mmc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mmc_partition FOR VALUES IN ('mmc');


--
-- Name: mmm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mmm_partition FOR VALUES IN ('mmm');


--
-- Name: mnst_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mnst_partition FOR VALUES IN ('mnst');


--
-- Name: mo_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mo_partition FOR VALUES IN ('mo');


--
-- Name: mos_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mos_partition FOR VALUES IN ('mos');


--
-- Name: mpc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mpc_partition FOR VALUES IN ('mpc');


--
-- Name: mpwr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mpwr_partition FOR VALUES IN ('mpwr');


--
-- Name: mrk_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mrk_partition FOR VALUES IN ('mrk');


--
-- Name: mrna_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mrna_partition FOR VALUES IN ('mrna');


--
-- Name: mro_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mro_partition FOR VALUES IN ('mro');


--
-- Name: ms_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ms_partition FOR VALUES IN ('ms');


--
-- Name: msci_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.msci_partition FOR VALUES IN ('msci');


--
-- Name: msft_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.msft_partition FOR VALUES IN ('msft');


--
-- Name: msi_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.msi_partition FOR VALUES IN ('msi');


--
-- Name: mtb_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mtb_partition FOR VALUES IN ('mtb');


--
-- Name: mtch_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mtch_partition FOR VALUES IN ('mtch');


--
-- Name: mtd_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mtd_partition FOR VALUES IN ('mtd');


--
-- Name: mu_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.mu_partition FOR VALUES IN ('mu');


--
-- Name: nclh_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nclh_partition FOR VALUES IN ('nclh');


--
-- Name: ndaq_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ndaq_partition FOR VALUES IN ('ndaq');


--
-- Name: nee_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nee_partition FOR VALUES IN ('nee');


--
-- Name: nem_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nem_partition FOR VALUES IN ('nem');


--
-- Name: nflx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nflx_partition FOR VALUES IN ('nflx');


--
-- Name: ni_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ni_partition FOR VALUES IN ('ni');


--
-- Name: nke_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nke_partition FOR VALUES IN ('nke');


--
-- Name: nlok_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nlok_partition FOR VALUES IN ('nlok');


--
-- Name: nlsn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nlsn_partition FOR VALUES IN ('nlsn');


--
-- Name: noc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.noc_partition FOR VALUES IN ('noc');


--
-- Name: now_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.now_partition FOR VALUES IN ('now');


--
-- Name: nrg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nrg_partition FOR VALUES IN ('nrg');


--
-- Name: nsc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nsc_partition FOR VALUES IN ('nsc');


--
-- Name: ntap_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ntap_partition FOR VALUES IN ('ntap');


--
-- Name: ntrs_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ntrs_partition FOR VALUES IN ('ntrs');


--
-- Name: nue_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nue_partition FOR VALUES IN ('nue');


--
-- Name: nvda_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nvda_partition FOR VALUES IN ('nvda');


--
-- Name: nvr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nvr_partition FOR VALUES IN ('nvr');


--
-- Name: nwl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nwl_partition FOR VALUES IN ('nwl');


--
-- Name: nws_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nws_partition FOR VALUES IN ('nws');


--
-- Name: nwsa_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nwsa_partition FOR VALUES IN ('nwsa');


--
-- Name: nxpi_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.nxpi_partition FOR VALUES IN ('nxpi');


--
-- Name: o_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.o_partition FOR VALUES IN ('o');


--
-- Name: odfl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.odfl_partition FOR VALUES IN ('odfl');


--
-- Name: ogn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ogn_partition FOR VALUES IN ('ogn');


--
-- Name: oke_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.oke_partition FOR VALUES IN ('oke');


--
-- Name: omc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.omc_partition FOR VALUES IN ('omc');


--
-- Name: orcl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.orcl_partition FOR VALUES IN ('orcl');


--
-- Name: orly_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.orly_partition FOR VALUES IN ('orly');


--
-- Name: otis_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.otis_partition FOR VALUES IN ('otis');


--
-- Name: oxy_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.oxy_partition FOR VALUES IN ('oxy');


--
-- Name: payc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.payc_partition FOR VALUES IN ('payc');


--
-- Name: payx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.payx_partition FOR VALUES IN ('payx');


--
-- Name: pbct_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pbct_partition FOR VALUES IN ('pbct');


--
-- Name: pcar_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pcar_partition FOR VALUES IN ('pcar');


--
-- Name: peak_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.peak_partition FOR VALUES IN ('peak');


--
-- Name: peg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.peg_partition FOR VALUES IN ('peg');


--
-- Name: penn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.penn_partition FOR VALUES IN ('penn');


--
-- Name: pep_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pep_partition FOR VALUES IN ('pep');


--
-- Name: pfe_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pfe_partition FOR VALUES IN ('pfe');


--
-- Name: pfg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pfg_partition FOR VALUES IN ('pfg');


--
-- Name: pg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pg_partition FOR VALUES IN ('pg');


--
-- Name: pgr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pgr_partition FOR VALUES IN ('pgr');


--
-- Name: ph_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ph_partition FOR VALUES IN ('ph');


--
-- Name: phm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.phm_partition FOR VALUES IN ('phm');


--
-- Name: pkg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pkg_partition FOR VALUES IN ('pkg');


--
-- Name: pki_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pki_partition FOR VALUES IN ('pki');


--
-- Name: pld_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pld_partition FOR VALUES IN ('pld');


--
-- Name: pm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pm_partition FOR VALUES IN ('pm');


--
-- Name: pnc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pnc_partition FOR VALUES IN ('pnc');


--
-- Name: pnr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pnr_partition FOR VALUES IN ('pnr');


--
-- Name: pnw_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pnw_partition FOR VALUES IN ('pnw');


--
-- Name: pool_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pool_partition FOR VALUES IN ('pool');


--
-- Name: ppg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ppg_partition FOR VALUES IN ('ppg');


--
-- Name: ppl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ppl_partition FOR VALUES IN ('ppl');


--
-- Name: pru_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pru_partition FOR VALUES IN ('pru');


--
-- Name: psa_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.psa_partition FOR VALUES IN ('psa');


--
-- Name: psx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.psx_partition FOR VALUES IN ('psx');


--
-- Name: ptc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ptc_partition FOR VALUES IN ('ptc');


--
-- Name: pvh_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pvh_partition FOR VALUES IN ('pvh');


--
-- Name: pwr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pwr_partition FOR VALUES IN ('pwr');


--
-- Name: pxd_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pxd_partition FOR VALUES IN ('pxd');


--
-- Name: pypl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.pypl_partition FOR VALUES IN ('pypl');


--
-- Name: qcom_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.qcom_partition FOR VALUES IN ('qcom');


--
-- Name: qrvo_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.qrvo_partition FOR VALUES IN ('qrvo');


--
-- Name: rcl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.rcl_partition FOR VALUES IN ('rcl');


--
-- Name: re_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.re_partition FOR VALUES IN ('re');


--
-- Name: reg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.reg_partition FOR VALUES IN ('reg');


--
-- Name: regn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.regn_partition FOR VALUES IN ('regn');


--
-- Name: rf_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.rf_partition FOR VALUES IN ('rf');


--
-- Name: rhi_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.rhi_partition FOR VALUES IN ('rhi');


--
-- Name: rjf_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.rjf_partition FOR VALUES IN ('rjf');


--
-- Name: rl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.rl_partition FOR VALUES IN ('rl');


--
-- Name: rmd_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.rmd_partition FOR VALUES IN ('rmd');


--
-- Name: rok_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.rok_partition FOR VALUES IN ('rok');


--
-- Name: rol_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.rol_partition FOR VALUES IN ('rol');


--
-- Name: rop_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.rop_partition FOR VALUES IN ('rop');


--
-- Name: rost_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.rost_partition FOR VALUES IN ('rost');


--
-- Name: rsg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.rsg_partition FOR VALUES IN ('rsg');


--
-- Name: rtx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.rtx_partition FOR VALUES IN ('rtx');


--
-- Name: sbac_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.sbac_partition FOR VALUES IN ('sbac');


--
-- Name: sbny_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.sbny_partition FOR VALUES IN ('sbny');


--
-- Name: sbux_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.sbux_partition FOR VALUES IN ('sbux');


--
-- Name: schw_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.schw_partition FOR VALUES IN ('schw');


--
-- Name: sedg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.sedg_partition FOR VALUES IN ('sedg');


--
-- Name: see_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.see_partition FOR VALUES IN ('see');


--
-- Name: shw_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.shw_partition FOR VALUES IN ('shw');


--
-- Name: sivb_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.sivb_partition FOR VALUES IN ('sivb');


--
-- Name: sjm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.sjm_partition FOR VALUES IN ('sjm');


--
-- Name: slb_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.slb_partition FOR VALUES IN ('slb');


--
-- Name: sna_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.sna_partition FOR VALUES IN ('sna');


--
-- Name: snps_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.snps_partition FOR VALUES IN ('snps');


--
-- Name: so_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.so_partition FOR VALUES IN ('so');


--
-- Name: spg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.spg_partition FOR VALUES IN ('spg');


--
-- Name: spgi_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.spgi_partition FOR VALUES IN ('spgi');


--
-- Name: sre_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.sre_partition FOR VALUES IN ('sre');


--
-- Name: ste_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ste_partition FOR VALUES IN ('ste');


--
-- Name: stt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.stt_partition FOR VALUES IN ('stt');


--
-- Name: stx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.stx_partition FOR VALUES IN ('stx');


--
-- Name: stz_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.stz_partition FOR VALUES IN ('stz');


--
-- Name: swk_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.swk_partition FOR VALUES IN ('swk');


--
-- Name: swks_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.swks_partition FOR VALUES IN ('swks');


--
-- Name: syf_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.syf_partition FOR VALUES IN ('syf');


--
-- Name: syk_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.syk_partition FOR VALUES IN ('syk');


--
-- Name: syy_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.syy_partition FOR VALUES IN ('syy');


--
-- Name: t_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.t_partition FOR VALUES IN ('t');


--
-- Name: tap_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tap_partition FOR VALUES IN ('tap');


--
-- Name: tdg_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tdg_partition FOR VALUES IN ('tdg');


--
-- Name: tdy_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tdy_partition FOR VALUES IN ('tdy');


--
-- Name: tech_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tech_partition FOR VALUES IN ('tech');


--
-- Name: tel_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tel_partition FOR VALUES IN ('tel');


--
-- Name: ter_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ter_partition FOR VALUES IN ('ter');


--
-- Name: tfc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tfc_partition FOR VALUES IN ('tfc');


--
-- Name: tfx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tfx_partition FOR VALUES IN ('tfx');


--
-- Name: tgt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tgt_partition FOR VALUES IN ('tgt');


--
-- Name: tjx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tjx_partition FOR VALUES IN ('tjx');


--
-- Name: tmo_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tmo_partition FOR VALUES IN ('tmo');


--
-- Name: tmus_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tmus_partition FOR VALUES IN ('tmus');


--
-- Name: tpr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tpr_partition FOR VALUES IN ('tpr');


--
-- Name: trmb_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.trmb_partition FOR VALUES IN ('trmb');


--
-- Name: trow_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.trow_partition FOR VALUES IN ('trow');


--
-- Name: trv_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.trv_partition FOR VALUES IN ('trv');


--
-- Name: tsco_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tsco_partition FOR VALUES IN ('tsco');


--
-- Name: tsla_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tsla_partition FOR VALUES IN ('tsla');


--
-- Name: tsn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tsn_partition FOR VALUES IN ('tsn');


--
-- Name: tt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tt_partition FOR VALUES IN ('tt');


--
-- Name: ttwo_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ttwo_partition FOR VALUES IN ('ttwo');


--
-- Name: twtr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.twtr_partition FOR VALUES IN ('twtr');


--
-- Name: txn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.txn_partition FOR VALUES IN ('txn');


--
-- Name: txt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.txt_partition FOR VALUES IN ('txt');


--
-- Name: tyl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.tyl_partition FOR VALUES IN ('tyl');


--
-- Name: ua_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ua_partition FOR VALUES IN ('ua');


--
-- Name: uaa_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.uaa_partition FOR VALUES IN ('uaa');


--
-- Name: ual_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ual_partition FOR VALUES IN ('ual');


--
-- Name: udr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.udr_partition FOR VALUES IN ('udr');


--
-- Name: uhs_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.uhs_partition FOR VALUES IN ('uhs');


--
-- Name: ulta_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ulta_partition FOR VALUES IN ('ulta');


--
-- Name: unh_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.unh_partition FOR VALUES IN ('unh');


--
-- Name: unp_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.unp_partition FOR VALUES IN ('unp');


--
-- Name: ups_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.ups_partition FOR VALUES IN ('ups');


--
-- Name: uri_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.uri_partition FOR VALUES IN ('uri');


--
-- Name: usb_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.usb_partition FOR VALUES IN ('usb');


--
-- Name: v_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.v_partition FOR VALUES IN ('v');


--
-- Name: vfc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.vfc_partition FOR VALUES IN ('vfc');


--
-- Name: viac_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.viac_partition FOR VALUES IN ('viac');


--
-- Name: vlo_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.vlo_partition FOR VALUES IN ('vlo');


--
-- Name: vmc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.vmc_partition FOR VALUES IN ('vmc');


--
-- Name: vno_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.vno_partition FOR VALUES IN ('vno');


--
-- Name: vrsk_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.vrsk_partition FOR VALUES IN ('vrsk');


--
-- Name: vrsn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.vrsn_partition FOR VALUES IN ('vrsn');


--
-- Name: vrtx_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.vrtx_partition FOR VALUES IN ('vrtx');


--
-- Name: vtr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.vtr_partition FOR VALUES IN ('vtr');


--
-- Name: vtrs_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.vtrs_partition FOR VALUES IN ('vtrs');


--
-- Name: vz_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.vz_partition FOR VALUES IN ('vz');


--
-- Name: wab_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.wab_partition FOR VALUES IN ('wab');


--
-- Name: wat_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.wat_partition FOR VALUES IN ('wat');


--
-- Name: wba_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.wba_partition FOR VALUES IN ('wba');


--
-- Name: wdc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.wdc_partition FOR VALUES IN ('wdc');


--
-- Name: wec_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.wec_partition FOR VALUES IN ('wec');


--
-- Name: well_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.well_partition FOR VALUES IN ('well');


--
-- Name: wfc_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.wfc_partition FOR VALUES IN ('wfc');


--
-- Name: whr_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.whr_partition FOR VALUES IN ('whr');


--
-- Name: wm_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.wm_partition FOR VALUES IN ('wm');


--
-- Name: wmb_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.wmb_partition FOR VALUES IN ('wmb');


--
-- Name: wmt_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.wmt_partition FOR VALUES IN ('wmt');


--
-- Name: wrb_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.wrb_partition FOR VALUES IN ('wrb');


--
-- Name: wrk_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.wrk_partition FOR VALUES IN ('wrk');


--
-- Name: wst_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.wst_partition FOR VALUES IN ('wst');


--
-- Name: wtw_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.wtw_partition FOR VALUES IN ('wtw');


--
-- Name: wy_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.wy_partition FOR VALUES IN ('wy');


--
-- Name: wynn_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.wynn_partition FOR VALUES IN ('wynn');


--
-- Name: xel_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.xel_partition FOR VALUES IN ('xel');


--
-- Name: xom_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.xom_partition FOR VALUES IN ('xom');


--
-- Name: xray_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.xray_partition FOR VALUES IN ('xray');


--
-- Name: xyl_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.xyl_partition FOR VALUES IN ('xyl');


--
-- Name: yum_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.yum_partition FOR VALUES IN ('yum');


--
-- Name: zbh_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.zbh_partition FOR VALUES IN ('zbh');


--
-- Name: zbra_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.zbra_partition FOR VALUES IN ('zbra');


--
-- Name: zion_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.zion_partition FOR VALUES IN ('zion');


--
-- Name: zts_partition; Type: TABLE ATTACH; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.scraped_news_reference ATTACH PARTITION db.zts_partition FOR VALUES IN ('zts');


--
-- Name: AAL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AAL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AAPL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AAPL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AAP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AAP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ABBV_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ABBV_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ABC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ABC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ABMD_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ABMD_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ABT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ABT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ACN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ACN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ADBE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ADBE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ADI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ADI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ADM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ADM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ADP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ADP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ADSK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ADSK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AEE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AEE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AEP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AEP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AES_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AES_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AFL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AFL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AIG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AIG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AIZ_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AIZ_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AJG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AJG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AKAM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AKAM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ALB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ALB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ALGN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ALGN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ALK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ALK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ALLE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ALLE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ALL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ALL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AMAT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AMAT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AMCR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AMCR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AMD_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AMD_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AME_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AME_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AMGN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AMGN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AMP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AMP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AMT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AMT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AMZN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AMZN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ANET_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ANET_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ANSS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ANSS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ANTM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ANTM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AON_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AON_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AOS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AOS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: APA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."APA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: APD_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."APD_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: APH_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."APH_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: APTV_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."APTV_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ARE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ARE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ATO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ATO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ATVI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ATVI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AVB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AVB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AVGO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AVGO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AVY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AVY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AWK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AWK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AXP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AXP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: AZO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."AZO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: A_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."A_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BAC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BAC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BAX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BAX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BBWI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BBWI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BBY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BBY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BDX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BDX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BEN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BEN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BF.B_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BF.B_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BIIB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BIIB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BIO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BIO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BKNG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BKNG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BKR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BKR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BLK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BLK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BLL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BLL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BMY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BMY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BRK.B_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BRK.B_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BRO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BRO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BSX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BSX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BWA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BWA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: BXP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."BXP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CAG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CAG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CAH_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CAH_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CARR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CARR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CAT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CAT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CBOE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CBOE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CBRE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CBRE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CCI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CCI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CCL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CCL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CDAY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CDAY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CDNS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CDNS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CDW_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CDW_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CEG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CEG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CERN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CERN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CFG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CFG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CF_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CF_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CHD_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CHD_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CHRW_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CHRW_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CHTR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CHTR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CINF_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CINF_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CLX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CLX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CMA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CMA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CMCSA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CMCSA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CME_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CME_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CMG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CMG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CMI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CMI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CMS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CMS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CNC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CNC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CNP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CNP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: COF_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."COF_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: COO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."COO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: COP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."COP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: COST_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."COST_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CPB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CPB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CPRT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CPRT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CRL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CRL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CRM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CRM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CSCO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CSCO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CSX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CSX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CTAS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CTAS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CTLT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CTLT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CTRA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CTRA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CTSH_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CTSH_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CTVA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CTVA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CTXS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CTXS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CVS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CVS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CVX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CVX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: CZR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."CZR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: C_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."C_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DAL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DAL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DD_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DD_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DFS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DFS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DGX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DGX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DHI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DHI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DHR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DHR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DISCA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DISCA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DISCK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DISCK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DISH_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DISH_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DIS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DIS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DLR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DLR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DLTR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DLTR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DOV_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DOV_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DOW_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DOW_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DPZ_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DPZ_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DRE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DRE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DRI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DRI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DTE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DTE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DUK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DUK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DVA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DVA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DVN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DVN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DXCM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DXCM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: DXC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."DXC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: D_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."D_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EBAY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EBAY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ECL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ECL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ED_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ED_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EFX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EFX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EIX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EIX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EMN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EMN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EMR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EMR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ENPH_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ENPH_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EOG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EOG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EPAM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EPAM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EQIX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EQIX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EQR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EQR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ESS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ESS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ES_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ES_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ETN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ETN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ETR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ETR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ETSY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ETSY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EVRG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EVRG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EW_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EW_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EXC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EXC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EXPD_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EXPD_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EXPE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EXPE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: EXR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."EXR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FANG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FANG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FAST_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FAST_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FBHS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FBHS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FCX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FCX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FDS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FDS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FDX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FDX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FFIV_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FFIV_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FISV_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FISV_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FIS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FIS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FITB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FITB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FLT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FLT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FMC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FMC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FOXA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FOXA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FOX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FOX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FRC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FRC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FRT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FRT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FTNT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FTNT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: FTV_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."FTV_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: F_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."F_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: GD_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."GD_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: GE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."GE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: GILD_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."GILD_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: GIS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."GIS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: GLW_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."GLW_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: GL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."GL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: GM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."GM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: GNRC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."GNRC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: GOOGL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."GOOGL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: GOOG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."GOOG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: GPC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."GPC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: GPN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."GPN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: GRMN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."GRMN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: GS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."GS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: GWW_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."GWW_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HAL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HAL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HAS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HAS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HBAN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HBAN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HCA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HCA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HD_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HD_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HES_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HES_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HIG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HIG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HII_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HII_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HLT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HLT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HOLX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HOLX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HON_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HON_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HPE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HPE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HPQ_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HPQ_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HRL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HRL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HSIC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HSIC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HST_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HST_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HSY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HSY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HUM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HUM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: HWM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."HWM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: IBM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."IBM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ICE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ICE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: IDXX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."IDXX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: IEX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."IEX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: IFF_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."IFF_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ILMN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ILMN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: INCY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."INCY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: INFO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."INFO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: INTC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."INTC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: INTU_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."INTU_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: IPGP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."IPGP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: IPG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."IPG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: IP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."IP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: IQV_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."IQV_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: IRM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."IRM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: IR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."IR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ISRG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ISRG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ITW_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ITW_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: IT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."IT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: IVZ_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."IVZ_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: JBHT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."JBHT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: JCI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."JCI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: JKHY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."JKHY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: JNJ_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."JNJ_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: JNPR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."JNPR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: JPM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."JPM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: J_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."J_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: KEYS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."KEYS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: KEY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."KEY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: KHC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."KHC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: KIM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."KIM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: KLAC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."KLAC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: KMB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."KMB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: KMI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."KMI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: KMX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."KMX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: KO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."KO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: KR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."KR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: K_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."K_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LDOS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LDOS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LEN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LEN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LHX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LHX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LH_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LH_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LIN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LIN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LKQ_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LKQ_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LLY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LLY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LMT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LMT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LNC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LNC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LNT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LNT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LOW_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LOW_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LRCX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LRCX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LUMN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LUMN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LUV_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LUV_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LVS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LVS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LW_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LW_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LYB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LYB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: LYV_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."LYV_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: L_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."L_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MAA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MAA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MAR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MAR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MAS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MAS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MCD_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MCD_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MCHP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MCHP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MCK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MCK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MCO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MCO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MDLZ_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MDLZ_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MDT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MDT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MET_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MET_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MGM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MGM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MHK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MHK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MKC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MKC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MKTX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MKTX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MLM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MLM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MMC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MMC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MMM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MMM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MNST_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MNST_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MOS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MOS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MPC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MPC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MPWR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MPWR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MRK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MRK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MRNA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MRNA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MRO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MRO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MSCI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MSCI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MSFT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MSFT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MSI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MSI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MTB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MTB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MTCH_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MTCH_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MTD_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MTD_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: MU_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."MU_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NCLH_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NCLH_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NDAQ_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NDAQ_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NEE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NEE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NEM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NEM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NFLX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NFLX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NKE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NKE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NLOK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NLOK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NLSN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NLSN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NOC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NOC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NOW_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NOW_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NRG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NRG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NSC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NSC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NTAP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NTAP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NTRS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NTRS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NUE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NUE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NVDA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NVDA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NVR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NVR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NWL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NWL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NWSA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NWSA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NWS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NWS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: NXPI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."NXPI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ODFL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ODFL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: OGN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."OGN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: OKE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."OKE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: OMC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."OMC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ORCL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ORCL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ORLY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ORLY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: OTIS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."OTIS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: OXY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."OXY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: O_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."O_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PAYC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PAYC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PAYX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PAYX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PBCT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PBCT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PCAR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PCAR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PEAK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PEAK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PEG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PEG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PENN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PENN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PEP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PEP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PFE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PFE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PFG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PFG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PGR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PGR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PHM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PHM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PH_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PH_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PKG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PKG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PKI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PKI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PLD_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PLD_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PNC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PNC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PNR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PNR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PNW_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PNW_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: POOL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."POOL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PPG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PPG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PPL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PPL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PRU_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PRU_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PSA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PSA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PSX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PSX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PTC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PTC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PVH_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PVH_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PWR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PWR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PXD_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PXD_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: PYPL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."PYPL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: QCOM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."QCOM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: QRVO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."QRVO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: RCL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."RCL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: REGN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."REGN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: REG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."REG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: RE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."RE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: RF_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."RF_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: RHI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."RHI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: RJF_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."RJF_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: RL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."RL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: RMD_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."RMD_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ROK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ROK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ROL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ROL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ROP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ROP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ROST_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ROST_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: RSG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."RSG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: RTX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."RTX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SBAC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SBAC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SBNY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SBNY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SBUX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SBUX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SCHW_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SCHW_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SEDG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SEDG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SEE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SEE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SHW_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SHW_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SIVB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SIVB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SJM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SJM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SLB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SLB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SNA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SNA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SNPS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SNPS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SPGI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SPGI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SPG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SPG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SRE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SRE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: STE_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."STE_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: STT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."STT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: STX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."STX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: STZ_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."STZ_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SWKS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SWKS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SWK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SWK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SYF_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SYF_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SYK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SYK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: SYY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."SYY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TAP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TAP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TDG_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TDG_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TDY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TDY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TECH_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TECH_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TEL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TEL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TER_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TER_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TFC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TFC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TFX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TFX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TGT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TGT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TJX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TJX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TMO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TMO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TMUS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TMUS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TPR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TPR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TRMB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TRMB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TROW_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TROW_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TRV_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TRV_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TSCO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TSCO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TSLA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TSLA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TSN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TSN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TTWO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TTWO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TWTR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TWTR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TXN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TXN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TXT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TXT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: TYL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."TYL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: T_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."T_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: UAA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."UAA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: UAL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."UAL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: UA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."UA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: UDR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."UDR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: UHS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."UHS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ULTA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ULTA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: UNH_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."UNH_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: UNP_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."UNP_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: UPS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."UPS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: URI_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."URI_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: USB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."USB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: VFC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."VFC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: VIAC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."VIAC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: VLO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."VLO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: VMC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."VMC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: VNO_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."VNO_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: VRSK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."VRSK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: VRSN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."VRSN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: VRTX_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."VRTX_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: VTRS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."VTRS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: VTR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."VTR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: VZ_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."VZ_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: V_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."V_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WAB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WAB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WAT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WAT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WBA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WBA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WDC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WDC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WEC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WEC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WELL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WELL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WFC_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WFC_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WHR_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WHR_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WMB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WMB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WMT_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WMT_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WRB_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WRB_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WRK_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WRK_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WST_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WST_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WTW_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WTW_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WYNN_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WYNN_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: WY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."WY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: XEL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."XEL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: XOM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."XOM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: XRAY_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."XRAY_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: XYL_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."XYL_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: YUM_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."YUM_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ZBH_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ZBH_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ZBRA_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ZBRA_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ZION_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ZION_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: ZTS_news_from_2022_03 id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news."ZTS_news_from_2022_03" ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: news id; Type: DEFAULT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news.news ALTER COLUMN id SET DEFAULT nextval('news.news_id_seq'::regclass);


--
-- Name: heatmap heatmap_pkey; Type: CONSTRAINT; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.heatmap
    ADD CONSTRAINT heatmap_pkey PRIMARY KEY (id_instrument);


--
-- Name: instruments instruments_cusip_key; Type: CONSTRAINT; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.instruments
    ADD CONSTRAINT instruments_cusip_key UNIQUE (cusip);


--
-- Name: instruments instruments_pkey; Type: CONSTRAINT; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.instruments
    ADD CONSTRAINT instruments_pkey PRIMARY KEY (cusip);


--
-- Name: tops tops_pkey; Type: CONSTRAINT; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.tops
    ADD CONSTRAINT tops_pkey PRIMARY KEY (id_instrument);


--
-- Name: news news_pkey; Type: CONSTRAINT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news.news
    ADD CONSTRAINT news_pkey PRIMARY KEY (id);


--
-- Name: id_instrument; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX id_instrument ON ONLY db.scraped_news_reference USING btree (symbol);


--
-- Name: a_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX a_partition_symbol_idx ON db.a_partition USING btree (symbol);


--
-- Name: aal_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX aal_partition_symbol_idx ON db.aal_partition USING btree (symbol);


--
-- Name: aap_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX aap_partition_symbol_idx ON db.aap_partition USING btree (symbol);


--
-- Name: aapl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX aapl_partition_symbol_idx ON db.aapl_partition USING btree (symbol);


--
-- Name: abbv_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX abbv_partition_symbol_idx ON db.abbv_partition USING btree (symbol);


--
-- Name: abc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX abc_partition_symbol_idx ON db.abc_partition USING btree (symbol);


--
-- Name: abmd_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX abmd_partition_symbol_idx ON db.abmd_partition USING btree (symbol);


--
-- Name: abt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX abt_partition_symbol_idx ON db.abt_partition USING btree (symbol);


--
-- Name: acn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX acn_partition_symbol_idx ON db.acn_partition USING btree (symbol);


--
-- Name: adbe_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX adbe_partition_symbol_idx ON db.adbe_partition USING btree (symbol);


--
-- Name: adi_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX adi_partition_symbol_idx ON db.adi_partition USING btree (symbol);


--
-- Name: adm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX adm_partition_symbol_idx ON db.adm_partition USING btree (symbol);


--
-- Name: adp_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX adp_partition_symbol_idx ON db.adp_partition USING btree (symbol);


--
-- Name: adsk_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX adsk_partition_symbol_idx ON db.adsk_partition USING btree (symbol);


--
-- Name: aee_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX aee_partition_symbol_idx ON db.aee_partition USING btree (symbol);


--
-- Name: aep_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX aep_partition_symbol_idx ON db.aep_partition USING btree (symbol);


--
-- Name: aes_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX aes_partition_symbol_idx ON db.aes_partition USING btree (symbol);


--
-- Name: afl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX afl_partition_symbol_idx ON db.afl_partition USING btree (symbol);


--
-- Name: aig_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX aig_partition_symbol_idx ON db.aig_partition USING btree (symbol);


--
-- Name: aiz_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX aiz_partition_symbol_idx ON db.aiz_partition USING btree (symbol);


--
-- Name: ajg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ajg_partition_symbol_idx ON db.ajg_partition USING btree (symbol);


--
-- Name: akam_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX akam_partition_symbol_idx ON db.akam_partition USING btree (symbol);


--
-- Name: alb_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX alb_partition_symbol_idx ON db.alb_partition USING btree (symbol);


--
-- Name: algn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX algn_partition_symbol_idx ON db.algn_partition USING btree (symbol);


--
-- Name: alk_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX alk_partition_symbol_idx ON db.alk_partition USING btree (symbol);


--
-- Name: all_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX all_partition_symbol_idx ON db.all_partition USING btree (symbol);


--
-- Name: alle_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX alle_partition_symbol_idx ON db.alle_partition USING btree (symbol);


--
-- Name: amat_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX amat_partition_symbol_idx ON db.amat_partition USING btree (symbol);


--
-- Name: amcr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX amcr_partition_symbol_idx ON db.amcr_partition USING btree (symbol);


--
-- Name: amd_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX amd_partition_symbol_idx ON db.amd_partition USING btree (symbol);


--
-- Name: ame_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ame_partition_symbol_idx ON db.ame_partition USING btree (symbol);


--
-- Name: amgn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX amgn_partition_symbol_idx ON db.amgn_partition USING btree (symbol);


--
-- Name: amp_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX amp_partition_symbol_idx ON db.amp_partition USING btree (symbol);


--
-- Name: amt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX amt_partition_symbol_idx ON db.amt_partition USING btree (symbol);


--
-- Name: amzn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX amzn_partition_symbol_idx ON db.amzn_partition USING btree (symbol);


--
-- Name: anet_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX anet_partition_symbol_idx ON db.anet_partition USING btree (symbol);


--
-- Name: anss_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX anss_partition_symbol_idx ON db.anss_partition USING btree (symbol);


--
-- Name: antm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX antm_partition_symbol_idx ON db.antm_partition USING btree (symbol);


--
-- Name: aon_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX aon_partition_symbol_idx ON db.aon_partition USING btree (symbol);


--
-- Name: aos_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX aos_partition_symbol_idx ON db.aos_partition USING btree (symbol);


--
-- Name: apa_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX apa_partition_symbol_idx ON db.apa_partition USING btree (symbol);


--
-- Name: apd_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX apd_partition_symbol_idx ON db.apd_partition USING btree (symbol);


--
-- Name: aph_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX aph_partition_symbol_idx ON db.aph_partition USING btree (symbol);


--
-- Name: aptv_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX aptv_partition_symbol_idx ON db.aptv_partition USING btree (symbol);


--
-- Name: are_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX are_partition_symbol_idx ON db.are_partition USING btree (symbol);


--
-- Name: ato_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ato_partition_symbol_idx ON db.ato_partition USING btree (symbol);


--
-- Name: atvi_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX atvi_partition_symbol_idx ON db.atvi_partition USING btree (symbol);


--
-- Name: avb_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX avb_partition_symbol_idx ON db.avb_partition USING btree (symbol);


--
-- Name: avgo_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX avgo_partition_symbol_idx ON db.avgo_partition USING btree (symbol);


--
-- Name: avy_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX avy_partition_symbol_idx ON db.avy_partition USING btree (symbol);


--
-- Name: awk_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX awk_partition_symbol_idx ON db.awk_partition USING btree (symbol);


--
-- Name: axp_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX axp_partition_symbol_idx ON db.axp_partition USING btree (symbol);


--
-- Name: azo_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX azo_partition_symbol_idx ON db.azo_partition USING btree (symbol);


--
-- Name: ba_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ba_partition_symbol_idx ON db.ba_partition USING btree (symbol);


--
-- Name: bac_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX bac_partition_symbol_idx ON db.bac_partition USING btree (symbol);


--
-- Name: bax_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX bax_partition_symbol_idx ON db.bax_partition USING btree (symbol);


--
-- Name: bbwi_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX bbwi_partition_symbol_idx ON db.bbwi_partition USING btree (symbol);


--
-- Name: bby_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX bby_partition_symbol_idx ON db.bby_partition USING btree (symbol);


--
-- Name: bdx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX bdx_partition_symbol_idx ON db.bdx_partition USING btree (symbol);


--
-- Name: ben_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ben_partition_symbol_idx ON db.ben_partition USING btree (symbol);


--
-- Name: bf.b_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX "bf.b_partition_symbol_idx" ON db."bf.b_partition" USING btree (symbol);


--
-- Name: biib_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX biib_partition_symbol_idx ON db.biib_partition USING btree (symbol);


--
-- Name: bio_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX bio_partition_symbol_idx ON db.bio_partition USING btree (symbol);


--
-- Name: bk_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX bk_partition_symbol_idx ON db.bk_partition USING btree (symbol);


--
-- Name: bkng_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX bkng_partition_symbol_idx ON db.bkng_partition USING btree (symbol);


--
-- Name: bkr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX bkr_partition_symbol_idx ON db.bkr_partition USING btree (symbol);


--
-- Name: blk_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX blk_partition_symbol_idx ON db.blk_partition USING btree (symbol);


--
-- Name: bll_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX bll_partition_symbol_idx ON db.bll_partition USING btree (symbol);


--
-- Name: bmy_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX bmy_partition_symbol_idx ON db.bmy_partition USING btree (symbol);


--
-- Name: br_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX br_partition_symbol_idx ON db.br_partition USING btree (symbol);


--
-- Name: brk.b_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX "brk.b_partition_symbol_idx" ON db."brk.b_partition" USING btree (symbol);


--
-- Name: bro_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX bro_partition_symbol_idx ON db.bro_partition USING btree (symbol);


--
-- Name: bsx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX bsx_partition_symbol_idx ON db.bsx_partition USING btree (symbol);


--
-- Name: bwa_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX bwa_partition_symbol_idx ON db.bwa_partition USING btree (symbol);


--
-- Name: bxp_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX bxp_partition_symbol_idx ON db.bxp_partition USING btree (symbol);


--
-- Name: c_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX c_partition_symbol_idx ON db.c_partition USING btree (symbol);


--
-- Name: cag_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cag_partition_symbol_idx ON db.cag_partition USING btree (symbol);


--
-- Name: cah_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cah_partition_symbol_idx ON db.cah_partition USING btree (symbol);


--
-- Name: carr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX carr_partition_symbol_idx ON db.carr_partition USING btree (symbol);


--
-- Name: cat_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cat_partition_symbol_idx ON db.cat_partition USING btree (symbol);


--
-- Name: cb_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cb_partition_symbol_idx ON db.cb_partition USING btree (symbol);


--
-- Name: cboe_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cboe_partition_symbol_idx ON db.cboe_partition USING btree (symbol);


--
-- Name: cbre_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cbre_partition_symbol_idx ON db.cbre_partition USING btree (symbol);


--
-- Name: cci_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cci_partition_symbol_idx ON db.cci_partition USING btree (symbol);


--
-- Name: ccl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ccl_partition_symbol_idx ON db.ccl_partition USING btree (symbol);


--
-- Name: cday_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cday_partition_symbol_idx ON db.cday_partition USING btree (symbol);


--
-- Name: cdns_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cdns_partition_symbol_idx ON db.cdns_partition USING btree (symbol);


--
-- Name: cdw_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cdw_partition_symbol_idx ON db.cdw_partition USING btree (symbol);


--
-- Name: ce_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ce_partition_symbol_idx ON db.ce_partition USING btree (symbol);


--
-- Name: ceg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ceg_partition_symbol_idx ON db.ceg_partition USING btree (symbol);


--
-- Name: cern_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cern_partition_symbol_idx ON db.cern_partition USING btree (symbol);


--
-- Name: cf_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cf_partition_symbol_idx ON db.cf_partition USING btree (symbol);


--
-- Name: cfg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cfg_partition_symbol_idx ON db.cfg_partition USING btree (symbol);


--
-- Name: chd_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX chd_partition_symbol_idx ON db.chd_partition USING btree (symbol);


--
-- Name: chrw_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX chrw_partition_symbol_idx ON db.chrw_partition USING btree (symbol);


--
-- Name: chtr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX chtr_partition_symbol_idx ON db.chtr_partition USING btree (symbol);


--
-- Name: ci_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ci_partition_symbol_idx ON db.ci_partition USING btree (symbol);


--
-- Name: cinf_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cinf_partition_symbol_idx ON db.cinf_partition USING btree (symbol);


--
-- Name: cl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cl_partition_symbol_idx ON db.cl_partition USING btree (symbol);


--
-- Name: clx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX clx_partition_symbol_idx ON db.clx_partition USING btree (symbol);


--
-- Name: cma_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cma_partition_symbol_idx ON db.cma_partition USING btree (symbol);


--
-- Name: cmcsa_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cmcsa_partition_symbol_idx ON db.cmcsa_partition USING btree (symbol);


--
-- Name: cme_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cme_partition_symbol_idx ON db.cme_partition USING btree (symbol);


--
-- Name: cmg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cmg_partition_symbol_idx ON db.cmg_partition USING btree (symbol);


--
-- Name: cmi_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cmi_partition_symbol_idx ON db.cmi_partition USING btree (symbol);


--
-- Name: cms_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cms_partition_symbol_idx ON db.cms_partition USING btree (symbol);


--
-- Name: cnc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cnc_partition_symbol_idx ON db.cnc_partition USING btree (symbol);


--
-- Name: cnp_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cnp_partition_symbol_idx ON db.cnp_partition USING btree (symbol);


--
-- Name: cof_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cof_partition_symbol_idx ON db.cof_partition USING btree (symbol);


--
-- Name: coo_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX coo_partition_symbol_idx ON db.coo_partition USING btree (symbol);


--
-- Name: cop_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cop_partition_symbol_idx ON db.cop_partition USING btree (symbol);


--
-- Name: cost_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cost_partition_symbol_idx ON db.cost_partition USING btree (symbol);


--
-- Name: cpb_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cpb_partition_symbol_idx ON db.cpb_partition USING btree (symbol);


--
-- Name: cprt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cprt_partition_symbol_idx ON db.cprt_partition USING btree (symbol);


--
-- Name: crl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX crl_partition_symbol_idx ON db.crl_partition USING btree (symbol);


--
-- Name: crm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX crm_partition_symbol_idx ON db.crm_partition USING btree (symbol);


--
-- Name: csco_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX csco_partition_symbol_idx ON db.csco_partition USING btree (symbol);


--
-- Name: csx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX csx_partition_symbol_idx ON db.csx_partition USING btree (symbol);


--
-- Name: ctas_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ctas_partition_symbol_idx ON db.ctas_partition USING btree (symbol);


--
-- Name: ctlt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ctlt_partition_symbol_idx ON db.ctlt_partition USING btree (symbol);


--
-- Name: ctra_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ctra_partition_symbol_idx ON db.ctra_partition USING btree (symbol);


--
-- Name: ctsh_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ctsh_partition_symbol_idx ON db.ctsh_partition USING btree (symbol);


--
-- Name: ctva_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ctva_partition_symbol_idx ON db.ctva_partition USING btree (symbol);


--
-- Name: ctxs_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ctxs_partition_symbol_idx ON db.ctxs_partition USING btree (symbol);


--
-- Name: cusip; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cusip ON db.heatmap USING btree (id_instrument);


--
-- Name: cvs_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cvs_partition_symbol_idx ON db.cvs_partition USING btree (symbol);


--
-- Name: cvx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX cvx_partition_symbol_idx ON db.cvx_partition USING btree (symbol);


--
-- Name: czr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX czr_partition_symbol_idx ON db.czr_partition USING btree (symbol);


--
-- Name: d_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX d_partition_symbol_idx ON db.d_partition USING btree (symbol);


--
-- Name: dal_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dal_partition_symbol_idx ON db.dal_partition USING btree (symbol);


--
-- Name: dd_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dd_partition_symbol_idx ON db.dd_partition USING btree (symbol);


--
-- Name: de_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX de_partition_symbol_idx ON db.de_partition USING btree (symbol);


--
-- Name: dfs_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dfs_partition_symbol_idx ON db.dfs_partition USING btree (symbol);


--
-- Name: dg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dg_partition_symbol_idx ON db.dg_partition USING btree (symbol);


--
-- Name: dgx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dgx_partition_symbol_idx ON db.dgx_partition USING btree (symbol);


--
-- Name: dhi_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dhi_partition_symbol_idx ON db.dhi_partition USING btree (symbol);


--
-- Name: dhr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dhr_partition_symbol_idx ON db.dhr_partition USING btree (symbol);


--
-- Name: dis_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dis_partition_symbol_idx ON db.dis_partition USING btree (symbol);


--
-- Name: disca_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX disca_partition_symbol_idx ON db.disca_partition USING btree (symbol);


--
-- Name: disck_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX disck_partition_symbol_idx ON db.disck_partition USING btree (symbol);


--
-- Name: dish_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dish_partition_symbol_idx ON db.dish_partition USING btree (symbol);


--
-- Name: dlr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dlr_partition_symbol_idx ON db.dlr_partition USING btree (symbol);


--
-- Name: dltr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dltr_partition_symbol_idx ON db.dltr_partition USING btree (symbol);


--
-- Name: dov_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dov_partition_symbol_idx ON db.dov_partition USING btree (symbol);


--
-- Name: dow_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dow_partition_symbol_idx ON db.dow_partition USING btree (symbol);


--
-- Name: dpz_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dpz_partition_symbol_idx ON db.dpz_partition USING btree (symbol);


--
-- Name: dre_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dre_partition_symbol_idx ON db.dre_partition USING btree (symbol);


--
-- Name: dri_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dri_partition_symbol_idx ON db.dri_partition USING btree (symbol);


--
-- Name: dte_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dte_partition_symbol_idx ON db.dte_partition USING btree (symbol);


--
-- Name: duk_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX duk_partition_symbol_idx ON db.duk_partition USING btree (symbol);


--
-- Name: dva_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dva_partition_symbol_idx ON db.dva_partition USING btree (symbol);


--
-- Name: dvn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dvn_partition_symbol_idx ON db.dvn_partition USING btree (symbol);


--
-- Name: dxc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dxc_partition_symbol_idx ON db.dxc_partition USING btree (symbol);


--
-- Name: dxcm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX dxcm_partition_symbol_idx ON db.dxcm_partition USING btree (symbol);


--
-- Name: ea_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ea_partition_symbol_idx ON db.ea_partition USING btree (symbol);


--
-- Name: ebay_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ebay_partition_symbol_idx ON db.ebay_partition USING btree (symbol);


--
-- Name: ecl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ecl_partition_symbol_idx ON db.ecl_partition USING btree (symbol);


--
-- Name: ed_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ed_partition_symbol_idx ON db.ed_partition USING btree (symbol);


--
-- Name: efx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX efx_partition_symbol_idx ON db.efx_partition USING btree (symbol);


--
-- Name: eix_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX eix_partition_symbol_idx ON db.eix_partition USING btree (symbol);


--
-- Name: el_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX el_partition_symbol_idx ON db.el_partition USING btree (symbol);


--
-- Name: emn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX emn_partition_symbol_idx ON db.emn_partition USING btree (symbol);


--
-- Name: emr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX emr_partition_symbol_idx ON db.emr_partition USING btree (symbol);


--
-- Name: enph_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX enph_partition_symbol_idx ON db.enph_partition USING btree (symbol);


--
-- Name: eog_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX eog_partition_symbol_idx ON db.eog_partition USING btree (symbol);


--
-- Name: epam_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX epam_partition_symbol_idx ON db.epam_partition USING btree (symbol);


--
-- Name: eqix_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX eqix_partition_symbol_idx ON db.eqix_partition USING btree (symbol);


--
-- Name: eqr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX eqr_partition_symbol_idx ON db.eqr_partition USING btree (symbol);


--
-- Name: es_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX es_partition_symbol_idx ON db.es_partition USING btree (symbol);


--
-- Name: ess_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ess_partition_symbol_idx ON db.ess_partition USING btree (symbol);


--
-- Name: etn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX etn_partition_symbol_idx ON db.etn_partition USING btree (symbol);


--
-- Name: etr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX etr_partition_symbol_idx ON db.etr_partition USING btree (symbol);


--
-- Name: etsy_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX etsy_partition_symbol_idx ON db.etsy_partition USING btree (symbol);


--
-- Name: evrg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX evrg_partition_symbol_idx ON db.evrg_partition USING btree (symbol);


--
-- Name: ew_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ew_partition_symbol_idx ON db.ew_partition USING btree (symbol);


--
-- Name: exc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX exc_partition_symbol_idx ON db.exc_partition USING btree (symbol);


--
-- Name: expd_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX expd_partition_symbol_idx ON db.expd_partition USING btree (symbol);


--
-- Name: expe_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX expe_partition_symbol_idx ON db.expe_partition USING btree (symbol);


--
-- Name: exr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX exr_partition_symbol_idx ON db.exr_partition USING btree (symbol);


--
-- Name: f_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX f_partition_symbol_idx ON db.f_partition USING btree (symbol);


--
-- Name: fang_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX fang_partition_symbol_idx ON db.fang_partition USING btree (symbol);


--
-- Name: fast_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX fast_partition_symbol_idx ON db.fast_partition USING btree (symbol);


--
-- Name: fb_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX fb_partition_symbol_idx ON db.fb_partition USING btree (symbol);


--
-- Name: fbhs_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX fbhs_partition_symbol_idx ON db.fbhs_partition USING btree (symbol);


--
-- Name: fcx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX fcx_partition_symbol_idx ON db.fcx_partition USING btree (symbol);


--
-- Name: fds_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX fds_partition_symbol_idx ON db.fds_partition USING btree (symbol);


--
-- Name: fdx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX fdx_partition_symbol_idx ON db.fdx_partition USING btree (symbol);


--
-- Name: fe_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX fe_partition_symbol_idx ON db.fe_partition USING btree (symbol);


--
-- Name: ffiv_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ffiv_partition_symbol_idx ON db.ffiv_partition USING btree (symbol);


--
-- Name: fis_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX fis_partition_symbol_idx ON db.fis_partition USING btree (symbol);


--
-- Name: fisv_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX fisv_partition_symbol_idx ON db.fisv_partition USING btree (symbol);


--
-- Name: fitb_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX fitb_partition_symbol_idx ON db.fitb_partition USING btree (symbol);


--
-- Name: flt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX flt_partition_symbol_idx ON db.flt_partition USING btree (symbol);


--
-- Name: fmc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX fmc_partition_symbol_idx ON db.fmc_partition USING btree (symbol);


--
-- Name: fox_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX fox_partition_symbol_idx ON db.fox_partition USING btree (symbol);


--
-- Name: foxa_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX foxa_partition_symbol_idx ON db.foxa_partition USING btree (symbol);


--
-- Name: frc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX frc_partition_symbol_idx ON db.frc_partition USING btree (symbol);


--
-- Name: frt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX frt_partition_symbol_idx ON db.frt_partition USING btree (symbol);


--
-- Name: ftnt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ftnt_partition_symbol_idx ON db.ftnt_partition USING btree (symbol);


--
-- Name: ftv_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ftv_partition_symbol_idx ON db.ftv_partition USING btree (symbol);


--
-- Name: gd_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX gd_partition_symbol_idx ON db.gd_partition USING btree (symbol);


--
-- Name: ge_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ge_partition_symbol_idx ON db.ge_partition USING btree (symbol);


--
-- Name: gild_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX gild_partition_symbol_idx ON db.gild_partition USING btree (symbol);


--
-- Name: gis_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX gis_partition_symbol_idx ON db.gis_partition USING btree (symbol);


--
-- Name: gl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX gl_partition_symbol_idx ON db.gl_partition USING btree (symbol);


--
-- Name: glw_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX glw_partition_symbol_idx ON db.glw_partition USING btree (symbol);


--
-- Name: gm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX gm_partition_symbol_idx ON db.gm_partition USING btree (symbol);


--
-- Name: gnrc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX gnrc_partition_symbol_idx ON db.gnrc_partition USING btree (symbol);


--
-- Name: goog_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX goog_partition_symbol_idx ON db.goog_partition USING btree (symbol);


--
-- Name: googl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX googl_partition_symbol_idx ON db.googl_partition USING btree (symbol);


--
-- Name: gpc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX gpc_partition_symbol_idx ON db.gpc_partition USING btree (symbol);


--
-- Name: gpn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX gpn_partition_symbol_idx ON db.gpn_partition USING btree (symbol);


--
-- Name: grmn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX grmn_partition_symbol_idx ON db.grmn_partition USING btree (symbol);


--
-- Name: gs_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX gs_partition_symbol_idx ON db.gs_partition USING btree (symbol);


--
-- Name: gww_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX gww_partition_symbol_idx ON db.gww_partition USING btree (symbol);


--
-- Name: hal_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hal_partition_symbol_idx ON db.hal_partition USING btree (symbol);


--
-- Name: has_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX has_partition_symbol_idx ON db.has_partition USING btree (symbol);


--
-- Name: hban_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hban_partition_symbol_idx ON db.hban_partition USING btree (symbol);


--
-- Name: hca_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hca_partition_symbol_idx ON db.hca_partition USING btree (symbol);


--
-- Name: hd_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hd_partition_symbol_idx ON db.hd_partition USING btree (symbol);


--
-- Name: hes_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hes_partition_symbol_idx ON db.hes_partition USING btree (symbol);


--
-- Name: hig_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hig_partition_symbol_idx ON db.hig_partition USING btree (symbol);


--
-- Name: hii_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hii_partition_symbol_idx ON db.hii_partition USING btree (symbol);


--
-- Name: hlt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hlt_partition_symbol_idx ON db.hlt_partition USING btree (symbol);


--
-- Name: holx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX holx_partition_symbol_idx ON db.holx_partition USING btree (symbol);


--
-- Name: hon_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hon_partition_symbol_idx ON db.hon_partition USING btree (symbol);


--
-- Name: hpe_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hpe_partition_symbol_idx ON db.hpe_partition USING btree (symbol);


--
-- Name: hpq_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hpq_partition_symbol_idx ON db.hpq_partition USING btree (symbol);


--
-- Name: hrl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hrl_partition_symbol_idx ON db.hrl_partition USING btree (symbol);


--
-- Name: hsic_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hsic_partition_symbol_idx ON db.hsic_partition USING btree (symbol);


--
-- Name: hst_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hst_partition_symbol_idx ON db.hst_partition USING btree (symbol);


--
-- Name: hsy_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hsy_partition_symbol_idx ON db.hsy_partition USING btree (symbol);


--
-- Name: hum_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hum_partition_symbol_idx ON db.hum_partition USING btree (symbol);


--
-- Name: hwm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX hwm_partition_symbol_idx ON db.hwm_partition USING btree (symbol);


--
-- Name: ibm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ibm_partition_symbol_idx ON db.ibm_partition USING btree (symbol);


--
-- Name: ice_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ice_partition_symbol_idx ON db.ice_partition USING btree (symbol);


--
-- Name: idxx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX idxx_partition_symbol_idx ON db.idxx_partition USING btree (symbol);


--
-- Name: iex_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX iex_partition_symbol_idx ON db.iex_partition USING btree (symbol);


--
-- Name: iff_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX iff_partition_symbol_idx ON db.iff_partition USING btree (symbol);


--
-- Name: ilmn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ilmn_partition_symbol_idx ON db.ilmn_partition USING btree (symbol);


--
-- Name: incy_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX incy_partition_symbol_idx ON db.incy_partition USING btree (symbol);


--
-- Name: info_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX info_partition_symbol_idx ON db.info_partition USING btree (symbol);


--
-- Name: intc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX intc_partition_symbol_idx ON db.intc_partition USING btree (symbol);


--
-- Name: intu_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX intu_partition_symbol_idx ON db.intu_partition USING btree (symbol);


--
-- Name: ip_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ip_partition_symbol_idx ON db.ip_partition USING btree (symbol);


--
-- Name: ipg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ipg_partition_symbol_idx ON db.ipg_partition USING btree (symbol);


--
-- Name: ipgp_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ipgp_partition_symbol_idx ON db.ipgp_partition USING btree (symbol);


--
-- Name: iqv_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX iqv_partition_symbol_idx ON db.iqv_partition USING btree (symbol);


--
-- Name: ir_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ir_partition_symbol_idx ON db.ir_partition USING btree (symbol);


--
-- Name: irm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX irm_partition_symbol_idx ON db.irm_partition USING btree (symbol);


--
-- Name: isrg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX isrg_partition_symbol_idx ON db.isrg_partition USING btree (symbol);


--
-- Name: it_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX it_partition_symbol_idx ON db.it_partition USING btree (symbol);


--
-- Name: itw_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX itw_partition_symbol_idx ON db.itw_partition USING btree (symbol);


--
-- Name: ivz_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ivz_partition_symbol_idx ON db.ivz_partition USING btree (symbol);


--
-- Name: j_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX j_partition_symbol_idx ON db.j_partition USING btree (symbol);


--
-- Name: jbht_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX jbht_partition_symbol_idx ON db.jbht_partition USING btree (symbol);


--
-- Name: jci_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX jci_partition_symbol_idx ON db.jci_partition USING btree (symbol);


--
-- Name: jkhy_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX jkhy_partition_symbol_idx ON db.jkhy_partition USING btree (symbol);


--
-- Name: jnj_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX jnj_partition_symbol_idx ON db.jnj_partition USING btree (symbol);


--
-- Name: jnpr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX jnpr_partition_symbol_idx ON db.jnpr_partition USING btree (symbol);


--
-- Name: jpm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX jpm_partition_symbol_idx ON db.jpm_partition USING btree (symbol);


--
-- Name: k_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX k_partition_symbol_idx ON db.k_partition USING btree (symbol);


--
-- Name: key_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX key_partition_symbol_idx ON db.key_partition USING btree (symbol);


--
-- Name: keys_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX keys_partition_symbol_idx ON db.keys_partition USING btree (symbol);


--
-- Name: khc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX khc_partition_symbol_idx ON db.khc_partition USING btree (symbol);


--
-- Name: kim_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX kim_partition_symbol_idx ON db.kim_partition USING btree (symbol);


--
-- Name: klac_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX klac_partition_symbol_idx ON db.klac_partition USING btree (symbol);


--
-- Name: kmb_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX kmb_partition_symbol_idx ON db.kmb_partition USING btree (symbol);


--
-- Name: kmi_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX kmi_partition_symbol_idx ON db.kmi_partition USING btree (symbol);


--
-- Name: kmx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX kmx_partition_symbol_idx ON db.kmx_partition USING btree (symbol);


--
-- Name: ko_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ko_partition_symbol_idx ON db.ko_partition USING btree (symbol);


--
-- Name: kr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX kr_partition_symbol_idx ON db.kr_partition USING btree (symbol);


--
-- Name: l_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX l_partition_symbol_idx ON db.l_partition USING btree (symbol);


--
-- Name: ldos_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ldos_partition_symbol_idx ON db.ldos_partition USING btree (symbol);


--
-- Name: len_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX len_partition_symbol_idx ON db.len_partition USING btree (symbol);


--
-- Name: lh_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX lh_partition_symbol_idx ON db.lh_partition USING btree (symbol);


--
-- Name: lhx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX lhx_partition_symbol_idx ON db.lhx_partition USING btree (symbol);


--
-- Name: lin_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX lin_partition_symbol_idx ON db.lin_partition USING btree (symbol);


--
-- Name: lkq_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX lkq_partition_symbol_idx ON db.lkq_partition USING btree (symbol);


--
-- Name: lly_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX lly_partition_symbol_idx ON db.lly_partition USING btree (symbol);


--
-- Name: lmt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX lmt_partition_symbol_idx ON db.lmt_partition USING btree (symbol);


--
-- Name: lnc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX lnc_partition_symbol_idx ON db.lnc_partition USING btree (symbol);


--
-- Name: lnt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX lnt_partition_symbol_idx ON db.lnt_partition USING btree (symbol);


--
-- Name: low_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX low_partition_symbol_idx ON db.low_partition USING btree (symbol);


--
-- Name: lrcx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX lrcx_partition_symbol_idx ON db.lrcx_partition USING btree (symbol);


--
-- Name: lumn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX lumn_partition_symbol_idx ON db.lumn_partition USING btree (symbol);


--
-- Name: luv_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX luv_partition_symbol_idx ON db.luv_partition USING btree (symbol);


--
-- Name: lvs_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX lvs_partition_symbol_idx ON db.lvs_partition USING btree (symbol);


--
-- Name: lw_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX lw_partition_symbol_idx ON db.lw_partition USING btree (symbol);


--
-- Name: lyb_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX lyb_partition_symbol_idx ON db.lyb_partition USING btree (symbol);


--
-- Name: lyv_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX lyv_partition_symbol_idx ON db.lyv_partition USING btree (symbol);


--
-- Name: ma_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ma_partition_symbol_idx ON db.ma_partition USING btree (symbol);


--
-- Name: maa_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX maa_partition_symbol_idx ON db.maa_partition USING btree (symbol);


--
-- Name: mar_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mar_partition_symbol_idx ON db.mar_partition USING btree (symbol);


--
-- Name: mas_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mas_partition_symbol_idx ON db.mas_partition USING btree (symbol);


--
-- Name: mcd_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mcd_partition_symbol_idx ON db.mcd_partition USING btree (symbol);


--
-- Name: mchp_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mchp_partition_symbol_idx ON db.mchp_partition USING btree (symbol);


--
-- Name: mck_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mck_partition_symbol_idx ON db.mck_partition USING btree (symbol);


--
-- Name: mco_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mco_partition_symbol_idx ON db.mco_partition USING btree (symbol);


--
-- Name: mdlz_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mdlz_partition_symbol_idx ON db.mdlz_partition USING btree (symbol);


--
-- Name: mdt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mdt_partition_symbol_idx ON db.mdt_partition USING btree (symbol);


--
-- Name: met_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX met_partition_symbol_idx ON db.met_partition USING btree (symbol);


--
-- Name: mgm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mgm_partition_symbol_idx ON db.mgm_partition USING btree (symbol);


--
-- Name: mhk_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mhk_partition_symbol_idx ON db.mhk_partition USING btree (symbol);


--
-- Name: mkc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mkc_partition_symbol_idx ON db.mkc_partition USING btree (symbol);


--
-- Name: mktx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mktx_partition_symbol_idx ON db.mktx_partition USING btree (symbol);


--
-- Name: mlm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mlm_partition_symbol_idx ON db.mlm_partition USING btree (symbol);


--
-- Name: mmc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mmc_partition_symbol_idx ON db.mmc_partition USING btree (symbol);


--
-- Name: mmm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mmm_partition_symbol_idx ON db.mmm_partition USING btree (symbol);


--
-- Name: mnst_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mnst_partition_symbol_idx ON db.mnst_partition USING btree (symbol);


--
-- Name: mo_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mo_partition_symbol_idx ON db.mo_partition USING btree (symbol);


--
-- Name: mos_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mos_partition_symbol_idx ON db.mos_partition USING btree (symbol);


--
-- Name: mpc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mpc_partition_symbol_idx ON db.mpc_partition USING btree (symbol);


--
-- Name: mpwr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mpwr_partition_symbol_idx ON db.mpwr_partition USING btree (symbol);


--
-- Name: mrk_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mrk_partition_symbol_idx ON db.mrk_partition USING btree (symbol);


--
-- Name: mrna_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mrna_partition_symbol_idx ON db.mrna_partition USING btree (symbol);


--
-- Name: mro_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mro_partition_symbol_idx ON db.mro_partition USING btree (symbol);


--
-- Name: ms_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ms_partition_symbol_idx ON db.ms_partition USING btree (symbol);


--
-- Name: msci_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX msci_partition_symbol_idx ON db.msci_partition USING btree (symbol);


--
-- Name: msft_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX msft_partition_symbol_idx ON db.msft_partition USING btree (symbol);


--
-- Name: msi_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX msi_partition_symbol_idx ON db.msi_partition USING btree (symbol);


--
-- Name: mtb_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mtb_partition_symbol_idx ON db.mtb_partition USING btree (symbol);


--
-- Name: mtch_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mtch_partition_symbol_idx ON db.mtch_partition USING btree (symbol);


--
-- Name: mtd_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mtd_partition_symbol_idx ON db.mtd_partition USING btree (symbol);


--
-- Name: mu_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX mu_partition_symbol_idx ON db.mu_partition USING btree (symbol);


--
-- Name: nclh_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nclh_partition_symbol_idx ON db.nclh_partition USING btree (symbol);


--
-- Name: ndaq_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ndaq_partition_symbol_idx ON db.ndaq_partition USING btree (symbol);


--
-- Name: nee_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nee_partition_symbol_idx ON db.nee_partition USING btree (symbol);


--
-- Name: nem_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nem_partition_symbol_idx ON db.nem_partition USING btree (symbol);


--
-- Name: nflx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nflx_partition_symbol_idx ON db.nflx_partition USING btree (symbol);


--
-- Name: ni_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ni_partition_symbol_idx ON db.ni_partition USING btree (symbol);


--
-- Name: nke_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nke_partition_symbol_idx ON db.nke_partition USING btree (symbol);


--
-- Name: nlok_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nlok_partition_symbol_idx ON db.nlok_partition USING btree (symbol);


--
-- Name: nlsn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nlsn_partition_symbol_idx ON db.nlsn_partition USING btree (symbol);


--
-- Name: noc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX noc_partition_symbol_idx ON db.noc_partition USING btree (symbol);


--
-- Name: now_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX now_partition_symbol_idx ON db.now_partition USING btree (symbol);


--
-- Name: nrg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nrg_partition_symbol_idx ON db.nrg_partition USING btree (symbol);


--
-- Name: nsc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nsc_partition_symbol_idx ON db.nsc_partition USING btree (symbol);


--
-- Name: ntap_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ntap_partition_symbol_idx ON db.ntap_partition USING btree (symbol);


--
-- Name: ntrs_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ntrs_partition_symbol_idx ON db.ntrs_partition USING btree (symbol);


--
-- Name: nue_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nue_partition_symbol_idx ON db.nue_partition USING btree (symbol);


--
-- Name: nvda_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nvda_partition_symbol_idx ON db.nvda_partition USING btree (symbol);


--
-- Name: nvr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nvr_partition_symbol_idx ON db.nvr_partition USING btree (symbol);


--
-- Name: nwl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nwl_partition_symbol_idx ON db.nwl_partition USING btree (symbol);


--
-- Name: nws_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nws_partition_symbol_idx ON db.nws_partition USING btree (symbol);


--
-- Name: nwsa_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nwsa_partition_symbol_idx ON db.nwsa_partition USING btree (symbol);


--
-- Name: nxpi_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX nxpi_partition_symbol_idx ON db.nxpi_partition USING btree (symbol);


--
-- Name: o_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX o_partition_symbol_idx ON db.o_partition USING btree (symbol);


--
-- Name: odfl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX odfl_partition_symbol_idx ON db.odfl_partition USING btree (symbol);


--
-- Name: ogn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ogn_partition_symbol_idx ON db.ogn_partition USING btree (symbol);


--
-- Name: oke_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX oke_partition_symbol_idx ON db.oke_partition USING btree (symbol);


--
-- Name: omc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX omc_partition_symbol_idx ON db.omc_partition USING btree (symbol);


--
-- Name: orcl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX orcl_partition_symbol_idx ON db.orcl_partition USING btree (symbol);


--
-- Name: orly_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX orly_partition_symbol_idx ON db.orly_partition USING btree (symbol);


--
-- Name: otis_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX otis_partition_symbol_idx ON db.otis_partition USING btree (symbol);


--
-- Name: oxy_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX oxy_partition_symbol_idx ON db.oxy_partition USING btree (symbol);


--
-- Name: payc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX payc_partition_symbol_idx ON db.payc_partition USING btree (symbol);


--
-- Name: payx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX payx_partition_symbol_idx ON db.payx_partition USING btree (symbol);


--
-- Name: pbct_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pbct_partition_symbol_idx ON db.pbct_partition USING btree (symbol);


--
-- Name: pcar_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pcar_partition_symbol_idx ON db.pcar_partition USING btree (symbol);


--
-- Name: peak_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX peak_partition_symbol_idx ON db.peak_partition USING btree (symbol);


--
-- Name: peg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX peg_partition_symbol_idx ON db.peg_partition USING btree (symbol);


--
-- Name: penn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX penn_partition_symbol_idx ON db.penn_partition USING btree (symbol);


--
-- Name: pep_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pep_partition_symbol_idx ON db.pep_partition USING btree (symbol);


--
-- Name: pfe_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pfe_partition_symbol_idx ON db.pfe_partition USING btree (symbol);


--
-- Name: pfg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pfg_partition_symbol_idx ON db.pfg_partition USING btree (symbol);


--
-- Name: pg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pg_partition_symbol_idx ON db.pg_partition USING btree (symbol);


--
-- Name: pgr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pgr_partition_symbol_idx ON db.pgr_partition USING btree (symbol);


--
-- Name: ph_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ph_partition_symbol_idx ON db.ph_partition USING btree (symbol);


--
-- Name: phm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX phm_partition_symbol_idx ON db.phm_partition USING btree (symbol);


--
-- Name: pkg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pkg_partition_symbol_idx ON db.pkg_partition USING btree (symbol);


--
-- Name: pki_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pki_partition_symbol_idx ON db.pki_partition USING btree (symbol);


--
-- Name: pld_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pld_partition_symbol_idx ON db.pld_partition USING btree (symbol);


--
-- Name: pm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pm_partition_symbol_idx ON db.pm_partition USING btree (symbol);


--
-- Name: pnc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pnc_partition_symbol_idx ON db.pnc_partition USING btree (symbol);


--
-- Name: pnr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pnr_partition_symbol_idx ON db.pnr_partition USING btree (symbol);


--
-- Name: pnw_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pnw_partition_symbol_idx ON db.pnw_partition USING btree (symbol);


--
-- Name: pool_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pool_partition_symbol_idx ON db.pool_partition USING btree (symbol);


--
-- Name: ppg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ppg_partition_symbol_idx ON db.ppg_partition USING btree (symbol);


--
-- Name: ppl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ppl_partition_symbol_idx ON db.ppl_partition USING btree (symbol);


--
-- Name: pru_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pru_partition_symbol_idx ON db.pru_partition USING btree (symbol);


--
-- Name: psa_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX psa_partition_symbol_idx ON db.psa_partition USING btree (symbol);


--
-- Name: psx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX psx_partition_symbol_idx ON db.psx_partition USING btree (symbol);


--
-- Name: ptc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ptc_partition_symbol_idx ON db.ptc_partition USING btree (symbol);


--
-- Name: pvh_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pvh_partition_symbol_idx ON db.pvh_partition USING btree (symbol);


--
-- Name: pwr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pwr_partition_symbol_idx ON db.pwr_partition USING btree (symbol);


--
-- Name: pxd_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pxd_partition_symbol_idx ON db.pxd_partition USING btree (symbol);


--
-- Name: pypl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX pypl_partition_symbol_idx ON db.pypl_partition USING btree (symbol);


--
-- Name: qcom_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX qcom_partition_symbol_idx ON db.qcom_partition USING btree (symbol);


--
-- Name: qrvo_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX qrvo_partition_symbol_idx ON db.qrvo_partition USING btree (symbol);


--
-- Name: rcl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX rcl_partition_symbol_idx ON db.rcl_partition USING btree (symbol);


--
-- Name: re_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX re_partition_symbol_idx ON db.re_partition USING btree (symbol);


--
-- Name: reg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX reg_partition_symbol_idx ON db.reg_partition USING btree (symbol);


--
-- Name: regn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX regn_partition_symbol_idx ON db.regn_partition USING btree (symbol);


--
-- Name: rf_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX rf_partition_symbol_idx ON db.rf_partition USING btree (symbol);


--
-- Name: rhi_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX rhi_partition_symbol_idx ON db.rhi_partition USING btree (symbol);


--
-- Name: rjf_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX rjf_partition_symbol_idx ON db.rjf_partition USING btree (symbol);


--
-- Name: rl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX rl_partition_symbol_idx ON db.rl_partition USING btree (symbol);


--
-- Name: rmd_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX rmd_partition_symbol_idx ON db.rmd_partition USING btree (symbol);


--
-- Name: rok_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX rok_partition_symbol_idx ON db.rok_partition USING btree (symbol);


--
-- Name: rol_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX rol_partition_symbol_idx ON db.rol_partition USING btree (symbol);


--
-- Name: rop_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX rop_partition_symbol_idx ON db.rop_partition USING btree (symbol);


--
-- Name: rost_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX rost_partition_symbol_idx ON db.rost_partition USING btree (symbol);


--
-- Name: rsg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX rsg_partition_symbol_idx ON db.rsg_partition USING btree (symbol);


--
-- Name: rtx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX rtx_partition_symbol_idx ON db.rtx_partition USING btree (symbol);


--
-- Name: sbac_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX sbac_partition_symbol_idx ON db.sbac_partition USING btree (symbol);


--
-- Name: sbny_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX sbny_partition_symbol_idx ON db.sbny_partition USING btree (symbol);


--
-- Name: sbux_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX sbux_partition_symbol_idx ON db.sbux_partition USING btree (symbol);


--
-- Name: schw_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX schw_partition_symbol_idx ON db.schw_partition USING btree (symbol);


--
-- Name: sedg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX sedg_partition_symbol_idx ON db.sedg_partition USING btree (symbol);


--
-- Name: see_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX see_partition_symbol_idx ON db.see_partition USING btree (symbol);


--
-- Name: shw_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX shw_partition_symbol_idx ON db.shw_partition USING btree (symbol);


--
-- Name: sivb_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX sivb_partition_symbol_idx ON db.sivb_partition USING btree (symbol);


--
-- Name: sjm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX sjm_partition_symbol_idx ON db.sjm_partition USING btree (symbol);


--
-- Name: slb_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX slb_partition_symbol_idx ON db.slb_partition USING btree (symbol);


--
-- Name: sna_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX sna_partition_symbol_idx ON db.sna_partition USING btree (symbol);


--
-- Name: snps_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX snps_partition_symbol_idx ON db.snps_partition USING btree (symbol);


--
-- Name: so_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX so_partition_symbol_idx ON db.so_partition USING btree (symbol);


--
-- Name: spg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX spg_partition_symbol_idx ON db.spg_partition USING btree (symbol);


--
-- Name: spgi_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX spgi_partition_symbol_idx ON db.spgi_partition USING btree (symbol);


--
-- Name: sre_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX sre_partition_symbol_idx ON db.sre_partition USING btree (symbol);


--
-- Name: ste_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ste_partition_symbol_idx ON db.ste_partition USING btree (symbol);


--
-- Name: stt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX stt_partition_symbol_idx ON db.stt_partition USING btree (symbol);


--
-- Name: stx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX stx_partition_symbol_idx ON db.stx_partition USING btree (symbol);


--
-- Name: stz_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX stz_partition_symbol_idx ON db.stz_partition USING btree (symbol);


--
-- Name: swk_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX swk_partition_symbol_idx ON db.swk_partition USING btree (symbol);


--
-- Name: swks_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX swks_partition_symbol_idx ON db.swks_partition USING btree (symbol);


--
-- Name: syf_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX syf_partition_symbol_idx ON db.syf_partition USING btree (symbol);


--
-- Name: syk_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX syk_partition_symbol_idx ON db.syk_partition USING btree (symbol);


--
-- Name: syy_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX syy_partition_symbol_idx ON db.syy_partition USING btree (symbol);


--
-- Name: t_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX t_partition_symbol_idx ON db.t_partition USING btree (symbol);


--
-- Name: tap_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tap_partition_symbol_idx ON db.tap_partition USING btree (symbol);


--
-- Name: tdg_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tdg_partition_symbol_idx ON db.tdg_partition USING btree (symbol);


--
-- Name: tdy_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tdy_partition_symbol_idx ON db.tdy_partition USING btree (symbol);


--
-- Name: tech_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tech_partition_symbol_idx ON db.tech_partition USING btree (symbol);


--
-- Name: tel_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tel_partition_symbol_idx ON db.tel_partition USING btree (symbol);


--
-- Name: ter_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ter_partition_symbol_idx ON db.ter_partition USING btree (symbol);


--
-- Name: tfc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tfc_partition_symbol_idx ON db.tfc_partition USING btree (symbol);


--
-- Name: tfx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tfx_partition_symbol_idx ON db.tfx_partition USING btree (symbol);


--
-- Name: tgt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tgt_partition_symbol_idx ON db.tgt_partition USING btree (symbol);


--
-- Name: tjx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tjx_partition_symbol_idx ON db.tjx_partition USING btree (symbol);


--
-- Name: tmo_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tmo_partition_symbol_idx ON db.tmo_partition USING btree (symbol);


--
-- Name: tmus_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tmus_partition_symbol_idx ON db.tmus_partition USING btree (symbol);


--
-- Name: tpr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tpr_partition_symbol_idx ON db.tpr_partition USING btree (symbol);


--
-- Name: trmb_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX trmb_partition_symbol_idx ON db.trmb_partition USING btree (symbol);


--
-- Name: trow_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX trow_partition_symbol_idx ON db.trow_partition USING btree (symbol);


--
-- Name: trv_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX trv_partition_symbol_idx ON db.trv_partition USING btree (symbol);


--
-- Name: tsco_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tsco_partition_symbol_idx ON db.tsco_partition USING btree (symbol);


--
-- Name: tsla_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tsla_partition_symbol_idx ON db.tsla_partition USING btree (symbol);


--
-- Name: tsn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tsn_partition_symbol_idx ON db.tsn_partition USING btree (symbol);


--
-- Name: tt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tt_partition_symbol_idx ON db.tt_partition USING btree (symbol);


--
-- Name: ttwo_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ttwo_partition_symbol_idx ON db.ttwo_partition USING btree (symbol);


--
-- Name: twtr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX twtr_partition_symbol_idx ON db.twtr_partition USING btree (symbol);


--
-- Name: txn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX txn_partition_symbol_idx ON db.txn_partition USING btree (symbol);


--
-- Name: txt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX txt_partition_symbol_idx ON db.txt_partition USING btree (symbol);


--
-- Name: tyl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX tyl_partition_symbol_idx ON db.tyl_partition USING btree (symbol);


--
-- Name: ua_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ua_partition_symbol_idx ON db.ua_partition USING btree (symbol);


--
-- Name: uaa_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX uaa_partition_symbol_idx ON db.uaa_partition USING btree (symbol);


--
-- Name: ual_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ual_partition_symbol_idx ON db.ual_partition USING btree (symbol);


--
-- Name: udr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX udr_partition_symbol_idx ON db.udr_partition USING btree (symbol);


--
-- Name: uhs_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX uhs_partition_symbol_idx ON db.uhs_partition USING btree (symbol);


--
-- Name: ulta_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ulta_partition_symbol_idx ON db.ulta_partition USING btree (symbol);


--
-- Name: unh_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX unh_partition_symbol_idx ON db.unh_partition USING btree (symbol);


--
-- Name: unp_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX unp_partition_symbol_idx ON db.unp_partition USING btree (symbol);


--
-- Name: ups_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX ups_partition_symbol_idx ON db.ups_partition USING btree (symbol);


--
-- Name: uri_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX uri_partition_symbol_idx ON db.uri_partition USING btree (symbol);


--
-- Name: usb_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX usb_partition_symbol_idx ON db.usb_partition USING btree (symbol);


--
-- Name: v_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX v_partition_symbol_idx ON db.v_partition USING btree (symbol);


--
-- Name: vfc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX vfc_partition_symbol_idx ON db.vfc_partition USING btree (symbol);


--
-- Name: viac_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX viac_partition_symbol_idx ON db.viac_partition USING btree (symbol);


--
-- Name: vlo_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX vlo_partition_symbol_idx ON db.vlo_partition USING btree (symbol);


--
-- Name: vmc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX vmc_partition_symbol_idx ON db.vmc_partition USING btree (symbol);


--
-- Name: vno_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX vno_partition_symbol_idx ON db.vno_partition USING btree (symbol);


--
-- Name: vrsk_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX vrsk_partition_symbol_idx ON db.vrsk_partition USING btree (symbol);


--
-- Name: vrsn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX vrsn_partition_symbol_idx ON db.vrsn_partition USING btree (symbol);


--
-- Name: vrtx_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX vrtx_partition_symbol_idx ON db.vrtx_partition USING btree (symbol);


--
-- Name: vtr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX vtr_partition_symbol_idx ON db.vtr_partition USING btree (symbol);


--
-- Name: vtrs_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX vtrs_partition_symbol_idx ON db.vtrs_partition USING btree (symbol);


--
-- Name: vz_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX vz_partition_symbol_idx ON db.vz_partition USING btree (symbol);


--
-- Name: wab_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX wab_partition_symbol_idx ON db.wab_partition USING btree (symbol);


--
-- Name: wat_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX wat_partition_symbol_idx ON db.wat_partition USING btree (symbol);


--
-- Name: wba_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX wba_partition_symbol_idx ON db.wba_partition USING btree (symbol);


--
-- Name: wdc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX wdc_partition_symbol_idx ON db.wdc_partition USING btree (symbol);


--
-- Name: wec_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX wec_partition_symbol_idx ON db.wec_partition USING btree (symbol);


--
-- Name: well_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX well_partition_symbol_idx ON db.well_partition USING btree (symbol);


--
-- Name: wfc_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX wfc_partition_symbol_idx ON db.wfc_partition USING btree (symbol);


--
-- Name: whr_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX whr_partition_symbol_idx ON db.whr_partition USING btree (symbol);


--
-- Name: wm_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX wm_partition_symbol_idx ON db.wm_partition USING btree (symbol);


--
-- Name: wmb_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX wmb_partition_symbol_idx ON db.wmb_partition USING btree (symbol);


--
-- Name: wmt_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX wmt_partition_symbol_idx ON db.wmt_partition USING btree (symbol);


--
-- Name: wrb_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX wrb_partition_symbol_idx ON db.wrb_partition USING btree (symbol);


--
-- Name: wrk_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX wrk_partition_symbol_idx ON db.wrk_partition USING btree (symbol);


--
-- Name: wst_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX wst_partition_symbol_idx ON db.wst_partition USING btree (symbol);


--
-- Name: wtw_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX wtw_partition_symbol_idx ON db.wtw_partition USING btree (symbol);


--
-- Name: wy_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX wy_partition_symbol_idx ON db.wy_partition USING btree (symbol);


--
-- Name: wynn_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX wynn_partition_symbol_idx ON db.wynn_partition USING btree (symbol);


--
-- Name: xel_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX xel_partition_symbol_idx ON db.xel_partition USING btree (symbol);


--
-- Name: xom_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX xom_partition_symbol_idx ON db.xom_partition USING btree (symbol);


--
-- Name: xray_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX xray_partition_symbol_idx ON db.xray_partition USING btree (symbol);


--
-- Name: xyl_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX xyl_partition_symbol_idx ON db.xyl_partition USING btree (symbol);


--
-- Name: yum_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX yum_partition_symbol_idx ON db.yum_partition USING btree (symbol);


--
-- Name: zbh_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX zbh_partition_symbol_idx ON db.zbh_partition USING btree (symbol);


--
-- Name: zbra_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX zbra_partition_symbol_idx ON db.zbra_partition USING btree (symbol);


--
-- Name: zion_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX zion_partition_symbol_idx ON db.zion_partition USING btree (symbol);


--
-- Name: zts_partition_symbol_idx; Type: INDEX; Schema: db; Owner: admin
--

CREATE INDEX zts_partition_symbol_idx ON db.zts_partition USING btree (symbol);


--
-- Name: download_time; Type: INDEX; Schema: news; Owner: admin
--

CREATE INDEX download_time ON news.news USING btree (download_time);


--
-- Name: a_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.a_partition_symbol_idx;


--
-- Name: aal_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.aal_partition_symbol_idx;


--
-- Name: aap_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.aap_partition_symbol_idx;


--
-- Name: aapl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.aapl_partition_symbol_idx;


--
-- Name: abbv_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.abbv_partition_symbol_idx;


--
-- Name: abc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.abc_partition_symbol_idx;


--
-- Name: abmd_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.abmd_partition_symbol_idx;


--
-- Name: abt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.abt_partition_symbol_idx;


--
-- Name: acn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.acn_partition_symbol_idx;


--
-- Name: adbe_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.adbe_partition_symbol_idx;


--
-- Name: adi_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.adi_partition_symbol_idx;


--
-- Name: adm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.adm_partition_symbol_idx;


--
-- Name: adp_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.adp_partition_symbol_idx;


--
-- Name: adsk_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.adsk_partition_symbol_idx;


--
-- Name: aee_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.aee_partition_symbol_idx;


--
-- Name: aep_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.aep_partition_symbol_idx;


--
-- Name: aes_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.aes_partition_symbol_idx;


--
-- Name: afl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.afl_partition_symbol_idx;


--
-- Name: aig_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.aig_partition_symbol_idx;


--
-- Name: aiz_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.aiz_partition_symbol_idx;


--
-- Name: ajg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ajg_partition_symbol_idx;


--
-- Name: akam_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.akam_partition_symbol_idx;


--
-- Name: alb_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.alb_partition_symbol_idx;


--
-- Name: algn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.algn_partition_symbol_idx;


--
-- Name: alk_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.alk_partition_symbol_idx;


--
-- Name: all_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.all_partition_symbol_idx;


--
-- Name: alle_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.alle_partition_symbol_idx;


--
-- Name: amat_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.amat_partition_symbol_idx;


--
-- Name: amcr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.amcr_partition_symbol_idx;


--
-- Name: amd_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.amd_partition_symbol_idx;


--
-- Name: ame_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ame_partition_symbol_idx;


--
-- Name: amgn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.amgn_partition_symbol_idx;


--
-- Name: amp_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.amp_partition_symbol_idx;


--
-- Name: amt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.amt_partition_symbol_idx;


--
-- Name: amzn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.amzn_partition_symbol_idx;


--
-- Name: anet_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.anet_partition_symbol_idx;


--
-- Name: anss_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.anss_partition_symbol_idx;


--
-- Name: antm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.antm_partition_symbol_idx;


--
-- Name: aon_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.aon_partition_symbol_idx;


--
-- Name: aos_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.aos_partition_symbol_idx;


--
-- Name: apa_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.apa_partition_symbol_idx;


--
-- Name: apd_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.apd_partition_symbol_idx;


--
-- Name: aph_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.aph_partition_symbol_idx;


--
-- Name: aptv_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.aptv_partition_symbol_idx;


--
-- Name: are_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.are_partition_symbol_idx;


--
-- Name: ato_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ato_partition_symbol_idx;


--
-- Name: atvi_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.atvi_partition_symbol_idx;


--
-- Name: avb_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.avb_partition_symbol_idx;


--
-- Name: avgo_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.avgo_partition_symbol_idx;


--
-- Name: avy_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.avy_partition_symbol_idx;


--
-- Name: awk_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.awk_partition_symbol_idx;


--
-- Name: axp_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.axp_partition_symbol_idx;


--
-- Name: azo_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.azo_partition_symbol_idx;


--
-- Name: ba_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ba_partition_symbol_idx;


--
-- Name: bac_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.bac_partition_symbol_idx;


--
-- Name: bax_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.bax_partition_symbol_idx;


--
-- Name: bbwi_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.bbwi_partition_symbol_idx;


--
-- Name: bby_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.bby_partition_symbol_idx;


--
-- Name: bdx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.bdx_partition_symbol_idx;


--
-- Name: ben_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ben_partition_symbol_idx;


--
-- Name: bf.b_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db."bf.b_partition_symbol_idx";


--
-- Name: biib_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.biib_partition_symbol_idx;


--
-- Name: bio_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.bio_partition_symbol_idx;


--
-- Name: bk_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.bk_partition_symbol_idx;


--
-- Name: bkng_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.bkng_partition_symbol_idx;


--
-- Name: bkr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.bkr_partition_symbol_idx;


--
-- Name: blk_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.blk_partition_symbol_idx;


--
-- Name: bll_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.bll_partition_symbol_idx;


--
-- Name: bmy_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.bmy_partition_symbol_idx;


--
-- Name: br_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.br_partition_symbol_idx;


--
-- Name: brk.b_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db."brk.b_partition_symbol_idx";


--
-- Name: bro_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.bro_partition_symbol_idx;


--
-- Name: bsx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.bsx_partition_symbol_idx;


--
-- Name: bwa_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.bwa_partition_symbol_idx;


--
-- Name: bxp_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.bxp_partition_symbol_idx;


--
-- Name: c_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.c_partition_symbol_idx;


--
-- Name: cag_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cag_partition_symbol_idx;


--
-- Name: cah_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cah_partition_symbol_idx;


--
-- Name: carr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.carr_partition_symbol_idx;


--
-- Name: cat_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cat_partition_symbol_idx;


--
-- Name: cb_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cb_partition_symbol_idx;


--
-- Name: cboe_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cboe_partition_symbol_idx;


--
-- Name: cbre_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cbre_partition_symbol_idx;


--
-- Name: cci_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cci_partition_symbol_idx;


--
-- Name: ccl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ccl_partition_symbol_idx;


--
-- Name: cday_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cday_partition_symbol_idx;


--
-- Name: cdns_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cdns_partition_symbol_idx;


--
-- Name: cdw_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cdw_partition_symbol_idx;


--
-- Name: ce_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ce_partition_symbol_idx;


--
-- Name: ceg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ceg_partition_symbol_idx;


--
-- Name: cern_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cern_partition_symbol_idx;


--
-- Name: cf_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cf_partition_symbol_idx;


--
-- Name: cfg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cfg_partition_symbol_idx;


--
-- Name: chd_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.chd_partition_symbol_idx;


--
-- Name: chrw_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.chrw_partition_symbol_idx;


--
-- Name: chtr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.chtr_partition_symbol_idx;


--
-- Name: ci_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ci_partition_symbol_idx;


--
-- Name: cinf_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cinf_partition_symbol_idx;


--
-- Name: cl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cl_partition_symbol_idx;


--
-- Name: clx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.clx_partition_symbol_idx;


--
-- Name: cma_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cma_partition_symbol_idx;


--
-- Name: cmcsa_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cmcsa_partition_symbol_idx;


--
-- Name: cme_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cme_partition_symbol_idx;


--
-- Name: cmg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cmg_partition_symbol_idx;


--
-- Name: cmi_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cmi_partition_symbol_idx;


--
-- Name: cms_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cms_partition_symbol_idx;


--
-- Name: cnc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cnc_partition_symbol_idx;


--
-- Name: cnp_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cnp_partition_symbol_idx;


--
-- Name: cof_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cof_partition_symbol_idx;


--
-- Name: coo_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.coo_partition_symbol_idx;


--
-- Name: cop_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cop_partition_symbol_idx;


--
-- Name: cost_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cost_partition_symbol_idx;


--
-- Name: cpb_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cpb_partition_symbol_idx;


--
-- Name: cprt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cprt_partition_symbol_idx;


--
-- Name: crl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.crl_partition_symbol_idx;


--
-- Name: crm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.crm_partition_symbol_idx;


--
-- Name: csco_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.csco_partition_symbol_idx;


--
-- Name: csx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.csx_partition_symbol_idx;


--
-- Name: ctas_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ctas_partition_symbol_idx;


--
-- Name: ctlt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ctlt_partition_symbol_idx;


--
-- Name: ctra_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ctra_partition_symbol_idx;


--
-- Name: ctsh_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ctsh_partition_symbol_idx;


--
-- Name: ctva_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ctva_partition_symbol_idx;


--
-- Name: ctxs_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ctxs_partition_symbol_idx;


--
-- Name: cvs_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cvs_partition_symbol_idx;


--
-- Name: cvx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.cvx_partition_symbol_idx;


--
-- Name: czr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.czr_partition_symbol_idx;


--
-- Name: d_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.d_partition_symbol_idx;


--
-- Name: dal_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dal_partition_symbol_idx;


--
-- Name: dd_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dd_partition_symbol_idx;


--
-- Name: de_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.de_partition_symbol_idx;


--
-- Name: dfs_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dfs_partition_symbol_idx;


--
-- Name: dg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dg_partition_symbol_idx;


--
-- Name: dgx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dgx_partition_symbol_idx;


--
-- Name: dhi_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dhi_partition_symbol_idx;


--
-- Name: dhr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dhr_partition_symbol_idx;


--
-- Name: dis_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dis_partition_symbol_idx;


--
-- Name: disca_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.disca_partition_symbol_idx;


--
-- Name: disck_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.disck_partition_symbol_idx;


--
-- Name: dish_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dish_partition_symbol_idx;


--
-- Name: dlr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dlr_partition_symbol_idx;


--
-- Name: dltr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dltr_partition_symbol_idx;


--
-- Name: dov_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dov_partition_symbol_idx;


--
-- Name: dow_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dow_partition_symbol_idx;


--
-- Name: dpz_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dpz_partition_symbol_idx;


--
-- Name: dre_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dre_partition_symbol_idx;


--
-- Name: dri_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dri_partition_symbol_idx;


--
-- Name: dte_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dte_partition_symbol_idx;


--
-- Name: duk_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.duk_partition_symbol_idx;


--
-- Name: dva_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dva_partition_symbol_idx;


--
-- Name: dvn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dvn_partition_symbol_idx;


--
-- Name: dxc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dxc_partition_symbol_idx;


--
-- Name: dxcm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.dxcm_partition_symbol_idx;


--
-- Name: ea_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ea_partition_symbol_idx;


--
-- Name: ebay_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ebay_partition_symbol_idx;


--
-- Name: ecl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ecl_partition_symbol_idx;


--
-- Name: ed_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ed_partition_symbol_idx;


--
-- Name: efx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.efx_partition_symbol_idx;


--
-- Name: eix_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.eix_partition_symbol_idx;


--
-- Name: el_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.el_partition_symbol_idx;


--
-- Name: emn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.emn_partition_symbol_idx;


--
-- Name: emr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.emr_partition_symbol_idx;


--
-- Name: enph_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.enph_partition_symbol_idx;


--
-- Name: eog_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.eog_partition_symbol_idx;


--
-- Name: epam_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.epam_partition_symbol_idx;


--
-- Name: eqix_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.eqix_partition_symbol_idx;


--
-- Name: eqr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.eqr_partition_symbol_idx;


--
-- Name: es_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.es_partition_symbol_idx;


--
-- Name: ess_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ess_partition_symbol_idx;


--
-- Name: etn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.etn_partition_symbol_idx;


--
-- Name: etr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.etr_partition_symbol_idx;


--
-- Name: etsy_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.etsy_partition_symbol_idx;


--
-- Name: evrg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.evrg_partition_symbol_idx;


--
-- Name: ew_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ew_partition_symbol_idx;


--
-- Name: exc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.exc_partition_symbol_idx;


--
-- Name: expd_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.expd_partition_symbol_idx;


--
-- Name: expe_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.expe_partition_symbol_idx;


--
-- Name: exr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.exr_partition_symbol_idx;


--
-- Name: f_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.f_partition_symbol_idx;


--
-- Name: fang_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.fang_partition_symbol_idx;


--
-- Name: fast_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.fast_partition_symbol_idx;


--
-- Name: fb_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.fb_partition_symbol_idx;


--
-- Name: fbhs_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.fbhs_partition_symbol_idx;


--
-- Name: fcx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.fcx_partition_symbol_idx;


--
-- Name: fds_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.fds_partition_symbol_idx;


--
-- Name: fdx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.fdx_partition_symbol_idx;


--
-- Name: fe_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.fe_partition_symbol_idx;


--
-- Name: ffiv_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ffiv_partition_symbol_idx;


--
-- Name: fis_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.fis_partition_symbol_idx;


--
-- Name: fisv_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.fisv_partition_symbol_idx;


--
-- Name: fitb_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.fitb_partition_symbol_idx;


--
-- Name: flt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.flt_partition_symbol_idx;


--
-- Name: fmc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.fmc_partition_symbol_idx;


--
-- Name: fox_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.fox_partition_symbol_idx;


--
-- Name: foxa_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.foxa_partition_symbol_idx;


--
-- Name: frc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.frc_partition_symbol_idx;


--
-- Name: frt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.frt_partition_symbol_idx;


--
-- Name: ftnt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ftnt_partition_symbol_idx;


--
-- Name: ftv_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ftv_partition_symbol_idx;


--
-- Name: gd_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.gd_partition_symbol_idx;


--
-- Name: ge_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ge_partition_symbol_idx;


--
-- Name: gild_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.gild_partition_symbol_idx;


--
-- Name: gis_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.gis_partition_symbol_idx;


--
-- Name: gl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.gl_partition_symbol_idx;


--
-- Name: glw_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.glw_partition_symbol_idx;


--
-- Name: gm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.gm_partition_symbol_idx;


--
-- Name: gnrc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.gnrc_partition_symbol_idx;


--
-- Name: goog_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.goog_partition_symbol_idx;


--
-- Name: googl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.googl_partition_symbol_idx;


--
-- Name: gpc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.gpc_partition_symbol_idx;


--
-- Name: gpn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.gpn_partition_symbol_idx;


--
-- Name: grmn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.grmn_partition_symbol_idx;


--
-- Name: gs_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.gs_partition_symbol_idx;


--
-- Name: gww_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.gww_partition_symbol_idx;


--
-- Name: hal_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hal_partition_symbol_idx;


--
-- Name: has_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.has_partition_symbol_idx;


--
-- Name: hban_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hban_partition_symbol_idx;


--
-- Name: hca_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hca_partition_symbol_idx;


--
-- Name: hd_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hd_partition_symbol_idx;


--
-- Name: hes_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hes_partition_symbol_idx;


--
-- Name: hig_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hig_partition_symbol_idx;


--
-- Name: hii_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hii_partition_symbol_idx;


--
-- Name: hlt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hlt_partition_symbol_idx;


--
-- Name: holx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.holx_partition_symbol_idx;


--
-- Name: hon_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hon_partition_symbol_idx;


--
-- Name: hpe_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hpe_partition_symbol_idx;


--
-- Name: hpq_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hpq_partition_symbol_idx;


--
-- Name: hrl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hrl_partition_symbol_idx;


--
-- Name: hsic_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hsic_partition_symbol_idx;


--
-- Name: hst_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hst_partition_symbol_idx;


--
-- Name: hsy_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hsy_partition_symbol_idx;


--
-- Name: hum_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hum_partition_symbol_idx;


--
-- Name: hwm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.hwm_partition_symbol_idx;


--
-- Name: ibm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ibm_partition_symbol_idx;


--
-- Name: ice_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ice_partition_symbol_idx;


--
-- Name: idxx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.idxx_partition_symbol_idx;


--
-- Name: iex_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.iex_partition_symbol_idx;


--
-- Name: iff_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.iff_partition_symbol_idx;


--
-- Name: ilmn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ilmn_partition_symbol_idx;


--
-- Name: incy_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.incy_partition_symbol_idx;


--
-- Name: info_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.info_partition_symbol_idx;


--
-- Name: intc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.intc_partition_symbol_idx;


--
-- Name: intu_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.intu_partition_symbol_idx;


--
-- Name: ip_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ip_partition_symbol_idx;


--
-- Name: ipg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ipg_partition_symbol_idx;


--
-- Name: ipgp_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ipgp_partition_symbol_idx;


--
-- Name: iqv_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.iqv_partition_symbol_idx;


--
-- Name: ir_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ir_partition_symbol_idx;


--
-- Name: irm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.irm_partition_symbol_idx;


--
-- Name: isrg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.isrg_partition_symbol_idx;


--
-- Name: it_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.it_partition_symbol_idx;


--
-- Name: itw_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.itw_partition_symbol_idx;


--
-- Name: ivz_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ivz_partition_symbol_idx;


--
-- Name: j_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.j_partition_symbol_idx;


--
-- Name: jbht_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.jbht_partition_symbol_idx;


--
-- Name: jci_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.jci_partition_symbol_idx;


--
-- Name: jkhy_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.jkhy_partition_symbol_idx;


--
-- Name: jnj_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.jnj_partition_symbol_idx;


--
-- Name: jnpr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.jnpr_partition_symbol_idx;


--
-- Name: jpm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.jpm_partition_symbol_idx;


--
-- Name: k_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.k_partition_symbol_idx;


--
-- Name: key_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.key_partition_symbol_idx;


--
-- Name: keys_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.keys_partition_symbol_idx;


--
-- Name: khc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.khc_partition_symbol_idx;


--
-- Name: kim_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.kim_partition_symbol_idx;


--
-- Name: klac_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.klac_partition_symbol_idx;


--
-- Name: kmb_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.kmb_partition_symbol_idx;


--
-- Name: kmi_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.kmi_partition_symbol_idx;


--
-- Name: kmx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.kmx_partition_symbol_idx;


--
-- Name: ko_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ko_partition_symbol_idx;


--
-- Name: kr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.kr_partition_symbol_idx;


--
-- Name: l_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.l_partition_symbol_idx;


--
-- Name: ldos_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ldos_partition_symbol_idx;


--
-- Name: len_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.len_partition_symbol_idx;


--
-- Name: lh_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.lh_partition_symbol_idx;


--
-- Name: lhx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.lhx_partition_symbol_idx;


--
-- Name: lin_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.lin_partition_symbol_idx;


--
-- Name: lkq_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.lkq_partition_symbol_idx;


--
-- Name: lly_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.lly_partition_symbol_idx;


--
-- Name: lmt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.lmt_partition_symbol_idx;


--
-- Name: lnc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.lnc_partition_symbol_idx;


--
-- Name: lnt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.lnt_partition_symbol_idx;


--
-- Name: low_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.low_partition_symbol_idx;


--
-- Name: lrcx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.lrcx_partition_symbol_idx;


--
-- Name: lumn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.lumn_partition_symbol_idx;


--
-- Name: luv_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.luv_partition_symbol_idx;


--
-- Name: lvs_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.lvs_partition_symbol_idx;


--
-- Name: lw_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.lw_partition_symbol_idx;


--
-- Name: lyb_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.lyb_partition_symbol_idx;


--
-- Name: lyv_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.lyv_partition_symbol_idx;


--
-- Name: ma_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ma_partition_symbol_idx;


--
-- Name: maa_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.maa_partition_symbol_idx;


--
-- Name: mar_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mar_partition_symbol_idx;


--
-- Name: mas_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mas_partition_symbol_idx;


--
-- Name: mcd_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mcd_partition_symbol_idx;


--
-- Name: mchp_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mchp_partition_symbol_idx;


--
-- Name: mck_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mck_partition_symbol_idx;


--
-- Name: mco_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mco_partition_symbol_idx;


--
-- Name: mdlz_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mdlz_partition_symbol_idx;


--
-- Name: mdt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mdt_partition_symbol_idx;


--
-- Name: met_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.met_partition_symbol_idx;


--
-- Name: mgm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mgm_partition_symbol_idx;


--
-- Name: mhk_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mhk_partition_symbol_idx;


--
-- Name: mkc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mkc_partition_symbol_idx;


--
-- Name: mktx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mktx_partition_symbol_idx;


--
-- Name: mlm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mlm_partition_symbol_idx;


--
-- Name: mmc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mmc_partition_symbol_idx;


--
-- Name: mmm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mmm_partition_symbol_idx;


--
-- Name: mnst_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mnst_partition_symbol_idx;


--
-- Name: mo_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mo_partition_symbol_idx;


--
-- Name: mos_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mos_partition_symbol_idx;


--
-- Name: mpc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mpc_partition_symbol_idx;


--
-- Name: mpwr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mpwr_partition_symbol_idx;


--
-- Name: mrk_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mrk_partition_symbol_idx;


--
-- Name: mrna_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mrna_partition_symbol_idx;


--
-- Name: mro_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mro_partition_symbol_idx;


--
-- Name: ms_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ms_partition_symbol_idx;


--
-- Name: msci_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.msci_partition_symbol_idx;


--
-- Name: msft_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.msft_partition_symbol_idx;


--
-- Name: msi_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.msi_partition_symbol_idx;


--
-- Name: mtb_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mtb_partition_symbol_idx;


--
-- Name: mtch_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mtch_partition_symbol_idx;


--
-- Name: mtd_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mtd_partition_symbol_idx;


--
-- Name: mu_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.mu_partition_symbol_idx;


--
-- Name: nclh_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nclh_partition_symbol_idx;


--
-- Name: ndaq_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ndaq_partition_symbol_idx;


--
-- Name: nee_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nee_partition_symbol_idx;


--
-- Name: nem_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nem_partition_symbol_idx;


--
-- Name: nflx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nflx_partition_symbol_idx;


--
-- Name: ni_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ni_partition_symbol_idx;


--
-- Name: nke_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nke_partition_symbol_idx;


--
-- Name: nlok_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nlok_partition_symbol_idx;


--
-- Name: nlsn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nlsn_partition_symbol_idx;


--
-- Name: noc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.noc_partition_symbol_idx;


--
-- Name: now_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.now_partition_symbol_idx;


--
-- Name: nrg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nrg_partition_symbol_idx;


--
-- Name: nsc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nsc_partition_symbol_idx;


--
-- Name: ntap_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ntap_partition_symbol_idx;


--
-- Name: ntrs_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ntrs_partition_symbol_idx;


--
-- Name: nue_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nue_partition_symbol_idx;


--
-- Name: nvda_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nvda_partition_symbol_idx;


--
-- Name: nvr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nvr_partition_symbol_idx;


--
-- Name: nwl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nwl_partition_symbol_idx;


--
-- Name: nws_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nws_partition_symbol_idx;


--
-- Name: nwsa_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nwsa_partition_symbol_idx;


--
-- Name: nxpi_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.nxpi_partition_symbol_idx;


--
-- Name: o_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.o_partition_symbol_idx;


--
-- Name: odfl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.odfl_partition_symbol_idx;


--
-- Name: ogn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ogn_partition_symbol_idx;


--
-- Name: oke_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.oke_partition_symbol_idx;


--
-- Name: omc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.omc_partition_symbol_idx;


--
-- Name: orcl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.orcl_partition_symbol_idx;


--
-- Name: orly_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.orly_partition_symbol_idx;


--
-- Name: otis_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.otis_partition_symbol_idx;


--
-- Name: oxy_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.oxy_partition_symbol_idx;


--
-- Name: payc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.payc_partition_symbol_idx;


--
-- Name: payx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.payx_partition_symbol_idx;


--
-- Name: pbct_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pbct_partition_symbol_idx;


--
-- Name: pcar_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pcar_partition_symbol_idx;


--
-- Name: peak_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.peak_partition_symbol_idx;


--
-- Name: peg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.peg_partition_symbol_idx;


--
-- Name: penn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.penn_partition_symbol_idx;


--
-- Name: pep_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pep_partition_symbol_idx;


--
-- Name: pfe_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pfe_partition_symbol_idx;


--
-- Name: pfg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pfg_partition_symbol_idx;


--
-- Name: pg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pg_partition_symbol_idx;


--
-- Name: pgr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pgr_partition_symbol_idx;


--
-- Name: ph_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ph_partition_symbol_idx;


--
-- Name: phm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.phm_partition_symbol_idx;


--
-- Name: pkg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pkg_partition_symbol_idx;


--
-- Name: pki_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pki_partition_symbol_idx;


--
-- Name: pld_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pld_partition_symbol_idx;


--
-- Name: pm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pm_partition_symbol_idx;


--
-- Name: pnc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pnc_partition_symbol_idx;


--
-- Name: pnr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pnr_partition_symbol_idx;


--
-- Name: pnw_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pnw_partition_symbol_idx;


--
-- Name: pool_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pool_partition_symbol_idx;


--
-- Name: ppg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ppg_partition_symbol_idx;


--
-- Name: ppl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ppl_partition_symbol_idx;


--
-- Name: pru_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pru_partition_symbol_idx;


--
-- Name: psa_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.psa_partition_symbol_idx;


--
-- Name: psx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.psx_partition_symbol_idx;


--
-- Name: ptc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ptc_partition_symbol_idx;


--
-- Name: pvh_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pvh_partition_symbol_idx;


--
-- Name: pwr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pwr_partition_symbol_idx;


--
-- Name: pxd_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pxd_partition_symbol_idx;


--
-- Name: pypl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.pypl_partition_symbol_idx;


--
-- Name: qcom_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.qcom_partition_symbol_idx;


--
-- Name: qrvo_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.qrvo_partition_symbol_idx;


--
-- Name: rcl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.rcl_partition_symbol_idx;


--
-- Name: re_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.re_partition_symbol_idx;


--
-- Name: reg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.reg_partition_symbol_idx;


--
-- Name: regn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.regn_partition_symbol_idx;


--
-- Name: rf_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.rf_partition_symbol_idx;


--
-- Name: rhi_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.rhi_partition_symbol_idx;


--
-- Name: rjf_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.rjf_partition_symbol_idx;


--
-- Name: rl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.rl_partition_symbol_idx;


--
-- Name: rmd_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.rmd_partition_symbol_idx;


--
-- Name: rok_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.rok_partition_symbol_idx;


--
-- Name: rol_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.rol_partition_symbol_idx;


--
-- Name: rop_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.rop_partition_symbol_idx;


--
-- Name: rost_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.rost_partition_symbol_idx;


--
-- Name: rsg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.rsg_partition_symbol_idx;


--
-- Name: rtx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.rtx_partition_symbol_idx;


--
-- Name: sbac_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.sbac_partition_symbol_idx;


--
-- Name: sbny_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.sbny_partition_symbol_idx;


--
-- Name: sbux_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.sbux_partition_symbol_idx;


--
-- Name: schw_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.schw_partition_symbol_idx;


--
-- Name: sedg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.sedg_partition_symbol_idx;


--
-- Name: see_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.see_partition_symbol_idx;


--
-- Name: shw_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.shw_partition_symbol_idx;


--
-- Name: sivb_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.sivb_partition_symbol_idx;


--
-- Name: sjm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.sjm_partition_symbol_idx;


--
-- Name: slb_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.slb_partition_symbol_idx;


--
-- Name: sna_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.sna_partition_symbol_idx;


--
-- Name: snps_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.snps_partition_symbol_idx;


--
-- Name: so_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.so_partition_symbol_idx;


--
-- Name: spg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.spg_partition_symbol_idx;


--
-- Name: spgi_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.spgi_partition_symbol_idx;


--
-- Name: sre_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.sre_partition_symbol_idx;


--
-- Name: ste_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ste_partition_symbol_idx;


--
-- Name: stt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.stt_partition_symbol_idx;


--
-- Name: stx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.stx_partition_symbol_idx;


--
-- Name: stz_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.stz_partition_symbol_idx;


--
-- Name: swk_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.swk_partition_symbol_idx;


--
-- Name: swks_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.swks_partition_symbol_idx;


--
-- Name: syf_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.syf_partition_symbol_idx;


--
-- Name: syk_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.syk_partition_symbol_idx;


--
-- Name: syy_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.syy_partition_symbol_idx;


--
-- Name: t_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.t_partition_symbol_idx;


--
-- Name: tap_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tap_partition_symbol_idx;


--
-- Name: tdg_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tdg_partition_symbol_idx;


--
-- Name: tdy_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tdy_partition_symbol_idx;


--
-- Name: tech_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tech_partition_symbol_idx;


--
-- Name: tel_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tel_partition_symbol_idx;


--
-- Name: ter_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ter_partition_symbol_idx;


--
-- Name: tfc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tfc_partition_symbol_idx;


--
-- Name: tfx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tfx_partition_symbol_idx;


--
-- Name: tgt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tgt_partition_symbol_idx;


--
-- Name: tjx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tjx_partition_symbol_idx;


--
-- Name: tmo_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tmo_partition_symbol_idx;


--
-- Name: tmus_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tmus_partition_symbol_idx;


--
-- Name: tpr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tpr_partition_symbol_idx;


--
-- Name: trmb_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.trmb_partition_symbol_idx;


--
-- Name: trow_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.trow_partition_symbol_idx;


--
-- Name: trv_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.trv_partition_symbol_idx;


--
-- Name: tsco_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tsco_partition_symbol_idx;


--
-- Name: tsla_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tsla_partition_symbol_idx;


--
-- Name: tsn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tsn_partition_symbol_idx;


--
-- Name: tt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tt_partition_symbol_idx;


--
-- Name: ttwo_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ttwo_partition_symbol_idx;


--
-- Name: twtr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.twtr_partition_symbol_idx;


--
-- Name: txn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.txn_partition_symbol_idx;


--
-- Name: txt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.txt_partition_symbol_idx;


--
-- Name: tyl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.tyl_partition_symbol_idx;


--
-- Name: ua_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ua_partition_symbol_idx;


--
-- Name: uaa_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.uaa_partition_symbol_idx;


--
-- Name: ual_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ual_partition_symbol_idx;


--
-- Name: udr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.udr_partition_symbol_idx;


--
-- Name: uhs_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.uhs_partition_symbol_idx;


--
-- Name: ulta_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ulta_partition_symbol_idx;


--
-- Name: unh_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.unh_partition_symbol_idx;


--
-- Name: unp_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.unp_partition_symbol_idx;


--
-- Name: ups_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.ups_partition_symbol_idx;


--
-- Name: uri_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.uri_partition_symbol_idx;


--
-- Name: usb_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.usb_partition_symbol_idx;


--
-- Name: v_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.v_partition_symbol_idx;


--
-- Name: vfc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.vfc_partition_symbol_idx;


--
-- Name: viac_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.viac_partition_symbol_idx;


--
-- Name: vlo_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.vlo_partition_symbol_idx;


--
-- Name: vmc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.vmc_partition_symbol_idx;


--
-- Name: vno_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.vno_partition_symbol_idx;


--
-- Name: vrsk_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.vrsk_partition_symbol_idx;


--
-- Name: vrsn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.vrsn_partition_symbol_idx;


--
-- Name: vrtx_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.vrtx_partition_symbol_idx;


--
-- Name: vtr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.vtr_partition_symbol_idx;


--
-- Name: vtrs_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.vtrs_partition_symbol_idx;


--
-- Name: vz_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.vz_partition_symbol_idx;


--
-- Name: wab_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.wab_partition_symbol_idx;


--
-- Name: wat_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.wat_partition_symbol_idx;


--
-- Name: wba_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.wba_partition_symbol_idx;


--
-- Name: wdc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.wdc_partition_symbol_idx;


--
-- Name: wec_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.wec_partition_symbol_idx;


--
-- Name: well_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.well_partition_symbol_idx;


--
-- Name: wfc_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.wfc_partition_symbol_idx;


--
-- Name: whr_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.whr_partition_symbol_idx;


--
-- Name: wm_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.wm_partition_symbol_idx;


--
-- Name: wmb_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.wmb_partition_symbol_idx;


--
-- Name: wmt_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.wmt_partition_symbol_idx;


--
-- Name: wrb_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.wrb_partition_symbol_idx;


--
-- Name: wrk_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.wrk_partition_symbol_idx;


--
-- Name: wst_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.wst_partition_symbol_idx;


--
-- Name: wtw_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.wtw_partition_symbol_idx;


--
-- Name: wy_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.wy_partition_symbol_idx;


--
-- Name: wynn_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.wynn_partition_symbol_idx;


--
-- Name: xel_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.xel_partition_symbol_idx;


--
-- Name: xom_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.xom_partition_symbol_idx;


--
-- Name: xray_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.xray_partition_symbol_idx;


--
-- Name: xyl_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.xyl_partition_symbol_idx;


--
-- Name: yum_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.yum_partition_symbol_idx;


--
-- Name: zbh_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.zbh_partition_symbol_idx;


--
-- Name: zbra_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.zbra_partition_symbol_idx;


--
-- Name: zion_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.zion_partition_symbol_idx;


--
-- Name: zts_partition_symbol_idx; Type: INDEX ATTACH; Schema: db; Owner: admin
--

ALTER INDEX db.id_instrument ATTACH PARTITION db.zts_partition_symbol_idx;


--
-- Name: news dinamic_patition_of_identifiers; Type: TRIGGER; Schema: news; Owner: admin
--

CREATE TRIGGER dinamic_patition_of_identifiers BEFORE INSERT ON news.news FOR EACH ROW EXECUTE FUNCTION db.montly_news();


--
-- Name: news heatmap_data_population; Type: TRIGGER; Schema: news; Owner: admin
--

CREATE TRIGGER heatmap_data_population AFTER INSERT ON news.news FOR EACH ROW EXECUTE FUNCTION db.heatmap_data();


--
-- Name: news tops_data_population; Type: TRIGGER; Schema: news; Owner: admin
--

CREATE TRIGGER tops_data_population AFTER INSERT ON news.news FOR EACH ROW EXECUTE FUNCTION db.tops_data();


--
-- Name: heatmap heatmap_id_instrument_fkey; Type: FK CONSTRAINT; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.heatmap
    ADD CONSTRAINT heatmap_id_instrument_fkey FOREIGN KEY (id_instrument) REFERENCES db.instruments(cusip) NOT VALID;


--
-- Name: tops tops_id_instrument_fkey; Type: FK CONSTRAINT; Schema: db; Owner: admin
--

ALTER TABLE ONLY db.tops
    ADD CONSTRAINT tops_id_instrument_fkey FOREIGN KEY (id_instrument) REFERENCES db.instruments(cusip) NOT VALID;


--
-- Name: news news_id_instrument_fkey; Type: FK CONSTRAINT; Schema: news; Owner: admin
--

ALTER TABLE ONLY news.news
    ADD CONSTRAINT news_id_instrument_fkey FOREIGN KEY (id_instrument) REFERENCES db.instruments(cusip);


--
-- Name: SCHEMA api; Type: ACL; Schema: -; Owner: admin
--

GRANT USAGE ON SCHEMA api TO client;


--
-- Name: FUNCTION access(); Type: ACL; Schema: api; Owner: admin
--

GRANT ALL ON FUNCTION api.access() TO client;


--
-- Name: FUNCTION market_sentiment_daily(); Type: ACL; Schema: api; Owner: admin
--

GRANT ALL ON FUNCTION api.market_sentiment_daily() TO client;


--
-- Name: FUNCTION market_sentiment_monthly(); Type: ACL; Schema: api; Owner: admin
--

GRANT ALL ON FUNCTION api.market_sentiment_monthly() TO client;


--
-- Name: FUNCTION obtain_analysis(date_ timestamp with time zone, symbol character varying); Type: ACL; Schema: api; Owner: admin
--

GRANT ALL ON FUNCTION api.obtain_analysis(date_ timestamp with time zone, symbol character varying) TO client;


--
-- PostgreSQL database dump complete
--

