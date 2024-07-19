///
/// # Test fixtures
///
/// Create objects for testing purpose
///
/// This is a very basic testing context !
///
/// For more sophisticated use cases, use the `pg_regress` functional test suite
/// See the `make installcheck` target for more details
///

use pgrx::prelude::*;

// dead_code warnings are disabled because this mod is loaded in lib.rs
// in order to make it available to all the others mod test section,
// but `cargo pgrx run` can't see where this function are used

#[allow(dead_code)]
pub fn create_masking_functions() -> pg_sys::Oid {
    Spi::run("
        CREATE SCHEMA outfit;
        CREATE FUNCTION outfit.mask(SMALLINT) RETURNS SMALLINT LANGUAGE SQL AS $$ SELECT 0::SMALLINT $$;
        CREATE FUNCTION outfit.mask(INT) RETURNS INT LANGUAGE SQL AS $$ SELECT 0 $$;
        CREATE FUNCTION outfit.mask(BIGINT) RETURNS BIGINT LANGUAGE SQL AS $$ SELECT 0::BIGINT $$;
        SECURITY LABEL FOR anon ON FUNCTION outfit.mask(SMALLINT) IS 'TRUSTED';
        SECURITY LABEL FOR anon ON FUNCTION outfit.mask(INT) IS 'TRUSTED';

        CREATE FUNCTION outfit.belt() RETURNS TEXT LANGUAGE SQL AS $$ SELECT 'x' $$;
        CREATE FUNCTION public.belt() RETURNS TEXT LANGUAGE SQL AS $$ SELECT 'x' $$;
        SECURITY LABEL FOR anon ON FUNCTION outfit.belt() IS 'UNTRUSTED';
        SECURITY LABEL FOR anon ON FUNCTION public.belt() IS 'TRUSTED';

        CREATE FUNCTION outfit.cape() RETURNS INT LANGUAGE SQL AS $$ SELECT 0 $$;
    ").unwrap();
    Spi::get_one::<pg_sys::Oid>("SELECT 'outfit'::REGNAMESPACE::OID;")
        .unwrap()
        .expect("should be an OID")
}

#[allow(dead_code)]
pub fn create_masked_role_in_policy(role: &str, policy: &str)
-> pg_sys::Oid
{
    Spi::run(format!("
        CREATE ROLE {role};
        SECURITY LABEL FOR {policy} ON ROLE {role} is 'MASKED';
    ").as_str()).unwrap();
    Spi::get_one::<pg_sys::Oid>(format!("
        SELECT '{role}'::REGROLE::OID;
    ").as_str()).unwrap().expect("should be an OID")
}

#[allow(dead_code)]
pub fn create_masked_role() -> pg_sys::Oid {
    Spi::run("
        CREATE ROLE batman;
        SECURITY LABEL FOR anon ON ROLE batman is 'MASKED';
    ").unwrap();
    Spi::get_one::<pg_sys::Oid>("SELECT 'batman'::REGROLE::OID;")
        .unwrap()
        .expect("should be an OID")
}

// an unmasked table
#[allow(dead_code)]
pub fn create_table_call() -> pg_sys::Oid {
    Spi::run("
         CREATE TABLE call AS
         SELECT  '410-719-9009'::TEXT        AS sender,
                 '410-258-4863'::TEXT        AS receiver,
                 '2004-07-08'::DATE          AS day
         ;
    ").unwrap();
    Spi::get_one::<pg_sys::Oid>("SELECT 'call'::REGCLASS::OID")
        .unwrap()
        .expect("should be an OID")
}

#[allow(dead_code)]
pub fn create_table_person() -> pg_sys::Oid {
    Spi::run("
         CREATE TABLE person AS
         SELECT  'Sarah'::VARCHAR(30)        AS firstname,
                 'Connor'::TEXT              AS lastname
         ;
         SECURITY LABEL FOR anon ON COLUMN person.lastname
           IS 'MASKED WITH VALUE NULL';
    ").unwrap();
    Spi::get_one::<pg_sys::Oid>("SELECT 'person'::REGCLASS::OID")
        .unwrap()
        .expect("should be an OID")
}

#[allow(dead_code)]
pub fn create_table_location() -> pg_sys::Oid {
    Spi::run("
         CREATE SCHEMA \"Postal_Info\";
         CREATE TABLE \"Postal_Info\".location AS
         SELECT  '53540'::VARCHAR(5)        AS zipcode,
                 'Gotham'::TEXT             AS city
         ;
    ").unwrap();
    Spi::get_one::<pg_sys::Oid>("SELECT '\"Postal_Info\".location'::REGCLASS::OID")
        .unwrap()
        .expect("should be an OID")
}

#[allow(dead_code)]
pub fn create_trusted_schema() -> pg_sys::Oid {
    Spi::run("
        CREATE SCHEMA gotham;
        SECURITY LABEL FOR anon ON SCHEMA gotham is 'TRUSTED';
    ").unwrap();
    Spi::get_one::<pg_sys::Oid>("SELECT 'gotham'::REGNAMESPACE::OID;")
        .unwrap()
        .expect("should be an OID")
}

#[allow(dead_code)]
pub fn create_unmasked_role() -> pg_sys::Oid {
    Spi::run("
        CREATE ROLE bruce;
    ").unwrap();
    Spi::get_one::<pg_sys::Oid>("SELECT 'bruce'::REGROLE::OID;")
        .unwrap()
        .expect("should be an OID")
}

#[allow(dead_code)]
pub fn create_untrusted_schema() -> pg_sys::Oid {
    Spi::run("
        CREATE SCHEMA arkham;
    ").unwrap();
    Spi::get_one::<pg_sys::Oid>("SELECT 'arkham'::REGNAMESPACE::OID;")
        .unwrap()
        .expect("should be an OID")
}

#[allow(dead_code)]
pub fn declare_masking_policies(){
    Spi::run("
        SET anon.masking_policies = 'devtests, analytics';
    ").unwrap();
}

#[allow(dead_code)]
pub fn trust_masking_functions_schema() {
    Spi::run("
        SECURITY LABEL FOR anon ON SCHEMA outfit IS 'TRUSTED';
    ").unwrap();
}
