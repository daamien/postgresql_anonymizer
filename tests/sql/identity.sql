BEGIN;

CREATE EXTENSION anon;

CREATE SCHEMA nba;

CREATE TABLE nba.player (
  id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  name TEXT,
  height_cm SMALLINT,
  height_in NUMERIC GENERATED ALWAYS AS (height_cm / 2.54) STORED
);

INSERT INTO nba.player (name,height_cm)
VALUES
  ('Muggsy Bogues',160),
  ('Manute Bol', 231),
  ('Michael Jordan', 198);

SAVEPOINT init;

CREATE SEQUENCE nba.anon_player_id_seq START 24632563;

SECURITY LABEL FOR anon ON FUNCTION pg_catalog.nextval(REGCLASS)
  IS 'TRUSTED';

SECURITY LABEL FOR anon ON COLUMN nba.player.id
  IS  'MASKED WITH FUNCTION pg_catalog.nextval( $$ nba.anon_player_id_seq $$ )';

SAVEPOINT before_failure;

SELECT anon.anonymize_table('nba.player');

ROLLBACK TO before_failure;

ALTER TABLE nba.player
 ALTER COLUMN id SET GENERATED BY DEFAULT;

SELECT anon.anonymize_table('nba.player');

ROLLBACK;
