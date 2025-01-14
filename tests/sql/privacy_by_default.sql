BEGIN;

CREATE EXTENSION IF NOT EXISTS anon CASCADE;

SET anon.privacy_by_default = True;

CREATE TABLE public.access_logs (
  date_open TIMESTAMP,
  session_id TEXT,
  ip_addr INET,
  url TEXT,
  browser TEXT DEFAULT 'unkown',
  operating_system TEXT DEFAULT NULL,
  locale TEXT
);

INSERT INTO public.access_logs VALUES
('2020-10-08', '1234','10.0.0.78', '/home.html', 'Mozilla/5.0','Windows','en_US'),
('2015-07-22', '999', '192.168.42.2', '/index.html', 'Chrome/97','Linux','fr_FR')
;

SECURITY LABEL FOR anon ON COLUMN public.access_logs.operating_system
IS 'NOT MASKED';


SAVEPOINT initial_state;

-- 1: Before Anonymization
SELECT count(*)=7 AS test1 FROM anon.pg_masking_rules;

-- 2: Authentic data is replaced by NULL or default value
SELECT anon.anonymize_table('public.access_logs');
SELECT bool_and(date_open IS NULL) AS test2a FROM public.access_logs;
SELECT bool_and(browser = 'unkown') AS test2b FROM public.access_logs;

-- 3: NOT MASKED
SELECT bool_or(operating_system = 'Linux') AS test3 FROM public.access_logs;

ROLLBACK TO initial_state;

-- 4: not_null_violation

ALTER TABLE public.access_logs
  ALTER COLUMN date_open
  SET NOT NULL;

DO $$
BEGIN
  SELECT anon.anonymize_table('public.access_logs') as test4;
EXCEPTION
  WHEN not_null_violation THEN
    RAISE NOTICE 'OK : not_null_violation error catched';
  WHEN others THEN
    RAISE NOTICE 'KO : unkown error catched';
    RAISE NOTICE '% %', SQLERRM, SQLSTATE;
END; $$
LANGUAGE 'plpgsql';

ROLLBACK TO initial_state;

-- 5: foreign_key_violation

CREATE TABLE public.os (name TEXT UNIQUE NOT NULL);
INSERT INTO public.os VALUES ('Windows'),('Linux');

ALTER TABLE public.access_logs
  ADD CONSTRAINT osfk
  FOREIGN KEY (operating_system) REFERENCES os (name) MATCH FULL;

SELECT anon.anonymize_table('public.access_logs') as test5;

ROLLBACK TO initial_state;

-- 6: unique_violation

ALTER TABLE public.access_logs
  ADD CONSTRAINT session_id_unique
  UNIQUE (session_id);

SELECT anon.anonymize_table('public.access_logs') as test6;

ROLLBACK TO initial_state;

-- 7: check_violation
ALTER TABLE public.access_logs
  ADD CONSTRAINT date_check
  CHECK (date_open >= '2000-01-01');

SELECT anon.anonymize_table('public.access_logs') as test7;

ROLLBACK TO initial_state;

-- 10: security
CREATE ROLE ursula;
SET ROLE ursula;

DO $$
BEGIN
  SET anon.privacy_by_default = off;
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK : insufficient_privilege error catched';
  WHEN others THEN
    RAISE NOTICE 'KO : unkown error catched';
    RAISE NOTICE '% %', SQLERRM, SQLSTATE;
END; $$
LANGUAGE 'plpgsql';

ROLLBACK TO initial_state;

-- 11: anonymous dumps
-- see https://gitlab.com/dalibo/postgresql_anonymizer/-/issues/479

SET anon.transparent_dynamic_masking = True;
SELECT anon.init();

CREATE ROLE dump_anon;

SECURITY LABEL FOR anon ON ROLE dump_anon IS 'MASKED';

GRANT USAGE ON SCHEMA anon TO dump_anon;
GRANT SELECT ON ALL TABLES IN SCHEMA anon TO dump_anon;


SET ROLE dump_anon;

SELECT TRUE AS catalog_relations_are_not_masked
FROM (SELECT tableoid FROM pg_extension) AS x
LIMIT 1;

SELECT TRUE AS anon_relations_are_not_masked
FROM (SELECT val FROM anon.last_name ) AS x
LIMIT 1;

ROLLBACK TO initial_state;



-- Clean up

DROP TABLE public.access_logs;
DROP EXTENSION anon;

ROLLBACK;
