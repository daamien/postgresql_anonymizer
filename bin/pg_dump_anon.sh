#!/bin/bash
#
#    pg_dump_anon
#    A basic wrapper to export anonymized data with pg_dump and psql
#
#    This is work in progress. Use with care.
#
#

usage()
{
cat << END
Usage: $(basename $0) [OPTION]... [DBNAME]

General options:
  -f, --file=FILENAME           output file
  --help                        display this message

Options controlling the output content:
  -n, --schema=PATTERN          dump the specified schema(s) only
  -N, --exclude-schema=PATTERN  do NOT dump the specified schema(s)
  -t, --table=PATTERN           dump the specified table(s) only
  -T, --exclude-table=PATTERN   do NOT dump the specified table(s)
  --exclude-table-data=PATTERN  do NOT dump data for the specified table(s)

Connection options:
  -d, --dbname=DBNAME           database to dump
  -h, --host=HOSTNAME           database server host or socket directory
  -p, --port=PORT               database server port number
  -U, --username=NAME           connect as specified database user
  -w, --no-password             never prompt for password
  -W, --password                force password prompt (should happen automatically)

If no database name is supplied, then the PGDATABASE environment
variable value is used.

END
}

does_anon_version_exists() {
$PSQL << EOSQL
  SELECT EXISTS(SELECT NULL FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid 
        WHERE proname = 'version' AND nspname='anon');
EOSQL
}

## Return the version of the anon extension
get_anon_version() {
FCT_EXISTS=$(does_anon_version_exists)
echo $FCT_EXISTS
if [ $FCT_EXISTS == "t" ]
then
$PSQL << EOSQL
  SELECT anon.version();
EOSQL
fi
}

## Return the masking schema
get_mask_schema() {
$PSQL << EOSQL
  SELECT anon.mask_schema();
EOSQL
}

## Return the masking filters based on the table name
get_mask_filters() {
$PSQL << EOSQL
  SELECT anon.mask_filters('$1'::REGCLASS);
EOSQL
}

## There's no clean way to exclude an extension from a dump
## This is a pragmatic approach
filter_out_extension(){
grep -v -E "^-- Name: $1;" |
grep -v -E "^CREATE EXTENSION IF NOT EXISTS $1" |
grep -v -E "^-- Name: EXTENSION $1" |
grep -v -E "^COMMENT ON EXTENSION $1"
}

##
## M A I N
##

##
## pg_dump and psql have a lot of common parameters ( -h, -d, etc.) but they
## also have similar parameters with different names (e.g. `pg_dump -f` and
## `psql -o` ). This wrapper script allows a subset of pg_dump's parameters
## and when needed, we transform the pg_dump options into the matching psql
## options
##
pg_dump_opt=$@        # backup args before parsing
psql_connect_opt=     # connections options
psql_output_opt=      # print options (currently only -f is supported)
exclude_table_data=   # dump the ddl, but ignore the data

while [ $# -gt 0 ]; do
    case "$1" in
    -d|--dbname)
        psql_connect_op+=" $1"
        shift
        psql_connect_opt+=" $1"
        ;;
    --dbname=*)
        psql_connect_opt+=" $1"
        ;;
    -f|--file)  # `pg_dump -f foo.sql` becomes `psql -o foo.sql`
        psql_output_opt+=" -o"
        shift
        psql_output_opt+=" $1"
        ;;
    --file=*) # `pg_dump -file=foo.sql` becomes `psql --output=foo.sql`
        psql_output_opt+=" $(echo $1| sed s/--file=/--output=/)"
        ;;
    -h|--host)
        psql_connect_opt+=" $1"
        shift
        psql_connect_opt+=" $1"
        ;;
    --host=*)
        psql_connect_opt+=" $1"
        shift
        psql_connect_opt+=" $1"
        ;;
    -p|--port)
        psql_connect_opt+=" $1"
        ;;
    --port=*)
        psql_connect_opt+=" $1"
        ;;
    -U|--username)
        psql_connect_opt+=" $1"
        shift
        psql_connect_opt+=" $1"
        ;;
    --username=*)
        psql_connect_opt+=" $1"
        ;;
    -w|--no-password)
        psql_connect_opt+=" $1"
        ;;
    -W|--password)
        psql_connect_opt+=" $1"
        ;;
    -n|--schema)
        # ignore the option for psql
        shift
        ;;
    --schema=*)
        # ignore the option for psql
        ;;
    -N|--exclude-schema)
        # ignore the option for psql
        shift
        ;;
    --exclude-schema=*)
        # ignore the option for psql
        ;;
    -t)
        # ignore the option for psql
        shift
        ;;
    --table=*)
        # ignore the option for psql
        ;;
    -T|--exclude-table)
        # ignore the option for psql
        shift
        ;;
    --exclude-table=*)
        # ignore the option for psql
        ;;
    --exclude-table-data=*)
        exclude_table_data+=" $1"
        ;;
    --help)
        usage
        exit 0
        ;;
    -*|--*)
        echo $0: Invalid option -- $1
        echo Try "$0 --help" for more information.
        exit 1
        ;;
    *)
        # this is DBNAME
        psql_connect_opt+=" $1"
        ;;
    esac
    shift
done

PSQL="psql $psql_connect_opt --quiet --tuples-only --no-align"
PSQL_PRINT="$PSQL $psql_output_opt"

## Stop if the extension is not installed in the database
version=$(get_anon_version)
if [ -z "$version" ]
then
  echo 'ERROR: Anon extension is not installed in this database.'
  exit 1
fi

## Header
echo "--"
echo "-- Dump generated by PostgreSQL Anonymizer $version."
echo "--"
echo


##
## Dump the DDL
##
## We need to remove
##  - Security Labels (masking rules are confidential)
##  - The schemas installed by the anon extension
##  - the anon extension and its dependencies
##
##
exclude_anon_schemas="--exclude-schema=anon --exclude-schema=$(get_mask_schema)"
DUMP="pg_dump --schema-only --no-security-labels $exclude_anon_schemas $pg_dump_opt"

$DUMP | filter_out_extension ddlx | filter_out_extension anon | filter_out_extension tsm_system_rows

##
## We're launching the pg_dump again to get the list of the tables that were
## dumped. Only this time we add extra parameters like --exclude-table-data
##
exclude_table=$(echo $exclude_table_data | sed s/--exclude-table-data=/--exclude-table=/)
dumped_tables=`$DUMP $exclude_table |awk '/^CREATE TABLE /{ print $3 }'`

##
## For each dumped table, we export the data form the Masking View
## instead of the real data
##
for t in $dumped_tables
do
  filters=$(get_mask_filters $t)
  ## generate the "COPY ... FROM STDIN" statement for a given table
  echo COPY $t FROM STDIN WITH CSV';'
  $PSQL_PRINT -c "\copy (SELECT $filters FROM $t) TO STDOUT WITH CSV"
  echo \\.
  echo
done

