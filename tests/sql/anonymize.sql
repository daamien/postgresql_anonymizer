BEGIN;

--
-- D A T A
--

CREATE TABLE stock (
  id INT,
  amount INT
);

INSERT INTO stock VALUES
(1,1000),
(2,400);

CREATE TABLE employee (
  id INT,
  firstname TEXT,
  lastname TEXT,
  phone TEXT UNIQUE,
  ssn TEXT UNIQUE,
  iban TEXT UNIQUE,
  linkedin_url TEXT
);

INSERT INTO employee
VALUES
(1,'Sarah','Connor','0609110911','153-473-999','FI9562411724264125',NULL),
(2,'Kyle', 'Reese', '0230366642','573-731-129','GB32BARC20039593595589',NULL)
;

CREATE TABLE call_history (
  id INT,
  fk_employee_phone TEXT REFERENCES employee(phone) DEFERRABLE,
  call_start TIMESTAMP,
  call_stop TIMESTAMP
);

INSERT INTO call_history
VALUES
(464,'0609110911','2020-05-24 08:11:30', '2020-05-24 08:11:43'),
(465,'0609110911','2020-05-25 15:58:23', '2020-05-24 16:01:11');


CREATE EXTENSION IF NOT EXISTS anon CASCADE;

--
-- R U L E S
--

SECURITY LABEL FOR anon ON COLUMN employee.firstname
IS 'MASKED WITH VALUE NULL';

SECURITY LABEL FOR anon ON COLUMN employee.lastname
IS 'MASKED WITH FUNCTION anon.fake_last_name()';

-- The FK must be masked with the same function on both ends
SECURITY LABEL FOR anon ON COLUMN employee.phone
IS 'MASKED WITH FUNCTION md5(phone)';

SECURITY LABEL FOR anon ON COLUMN call_history.fk_employee_phone
IS 'MASKED WITH FUNCTION md5(fk_employee_phone)';

-- This is designed to break the UNIQUE constraint
SECURITY LABEL FOR anon ON COLUMN employee.ssn
IS 'MASKED WITH FUNCTION anon.partial(ssn,0,$$XXX-XXX-XX$$,1)';

SECURITY LABEL FOR anon ON COLUMN employee.iban
IS 'MASKED WITH FUNCTION anon.random_string(18)';

-- Issue #181
SECURITY LABEL FOR anon ON COLUMN employee.linkedin_url
IS 'MASKED WITH VALUE ''https://example.com/path'' ';

--
-- T E S T S
--

-- Should return a NOTICE but anonymize data anyway
SELECT anon.anonymize_column('employee','lastname');
SELECT count(*)=0 FROM employee WHERE lastname= 'Connor';

SELECT anon.init();
SAVEPOINT after_init;

-- Anonymize all

-- This should fail because of the UNIQUE constraint on the ssn column
-- DISABLED because the error output differs between PG11- and PG12+
--SELECT anonymize_database();
--ROLLBACK TO after_init;

-- Remove uniquess and it should work
ALTER TABLE employee DROP CONSTRAINT employee_ssn_key;
SELECT anon.anonymize_database();

-- Issue #114 : Check if all columns are masked
SELECT phone != '0609110911' FROM employee WHERE id=1;

-- Issue #181
SELECT bool_and(linkedin_url IS NOT NULL) FROM employee;

-- Anonymize a masked table
SELECT anon.anonymize_table('employee');

-- Anonymize a table with no mask
-- returns NULL
SELECT anon.anonymize_table('stock') IS NULL;

-- Anonymize a table that does not exist
SELECT anon.anonymize_table('employee');

-- Anonymize a masked column
SELECT anon.anonymize_column('employee','phone');

-- Anonymize an unmasked column
-- returns FALSE and a WARNING
SELECT anon.anonymize_column('employee','firstname') IS FALSE;

-- Anonymize a column that does not exist
-- returns FALSE and a WARNING
SELECT anon.anonymize_column('employee','xxxxxxxxxxxxxxxx') IS FALSE;


ROLLBACK;
