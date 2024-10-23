BEGIN;

CREATE EXTENSION anon;

CREATE TABLE employee (
  id  SERIAL,
  ssn TEXT
);

INSERT INTO employee
VALUES
  (102, '486-500-333'),
  (874, '486-500-457'),
  (3042, '486-500-268');

CREATE SCHEMA views;

CREATE VIEW views.early_employee AS
  SELECT *
  FROM employee
  WHERE id < 1000;

CREATE ROLE david LOGIN;

SECURITY LABEL FOR anon ON ROLE david IS 'MASKED';

GRANT USAGE ON SCHEMA views TO david;
GRANT SELECT ON views.early_employee TO david;


-- Rule on the table
SECURITY LABEL FOR anon ON COLUMN public.employee.ssn
IS 'MASKED WITH VALUE NULL';

-- Rule on the view
SECURITY LABEL FOR anon ON COLUMN views.early_employee.ssn
  IS 'MASKED WITH VALUE $$CONFIDENTIAL$$';

SET anon.transparent_dynamic_masking TO TRUE;

SET ROLE david;

SELECT ssn = 'CONFIDENTIAL' FROM views.early_employee LIMIT 1;

RESET ROLE;

-- DROP the rule on the view
SECURITY LABEL FOR anon ON COLUMN views.early_employee.ssn IS NULL;


SET ROLE david;

-- The rule on the table IS NOT applied !
SELECT ssn IS NOT NULL FROM views.early_employee LIMIT 1;


ROLLBACK;

