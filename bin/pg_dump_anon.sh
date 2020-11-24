#!/bin/bash
#    pg_dump_anon
#    A basic wrapper to export anonymized data with pg_dump and psql

usage()
{
cat << END
Usage: $(basename "$0") [OPTION]... [DBNAME]

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

## Return the masking schema
get_mask_schema() {
psql "${psql_opts[@]}" << EOSQL
  SELECT anon.mask_schema();
EOSQL
}

## Return the masking filters based on the table name
get_mask_filters() {
psql "${psql_opts[@]}" << EOSQL
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

################################################################################
## 0. Parsing the command line arguments
##
## pg_dump_anon supports a subset of pg_dump options
##
## some arguments will be pushed to `pg_dump` and/or `psql` while others need
## specific treatment ( especially the `--file` option)
################################################################################

output=/dev/stdout      # by default, use standard ouput
pg_dump_opts=()         # export options
psql_opts=(
  "--quiet"
  "--tuples-only"
  "--no-align"
  "--no-psqlrc"
)                       # connections options
exclude_table_data=()   # dump the ddl, but ignore the data

while [ $# -gt 0 ]; do
    case "$1" in
    # options pushed to pg_dump and psql
    -d|--dbname|-h|--host|-p|--port|-U|--username)
        pg_dump_opts+=("$1" "$2")
        psql_opts+=("$1" "$2")
        shift
        ;;
    --dbname=*|--host=*|--port=*|--username=*|-w|--no-password|-W|--password)
        pg_dump_opts+=("$1")
        psql_opts+=("$1")
        ;;
    # output options
    # `pg_dump_anon -f foo.sql` becomes `pg_dump [...] > foo.sql`
    -f|--file)
        shift # skip the `-f` tag
        output="$1"
        ;;
    --file=*)
        output="${1#--file=}"
        ;;
    # options pushed only to pg_dump
    -n|--schema|-N|--exclude-schema|-t|--table|-T|--exclude-table)
        pg_dump_opts+=("$1" "$2")
        shift
        ;;
    --schema=*|--exclude-schema=*|--table=*|--exclude-table=*)
        pg_dump_opts+=("$1")
        ;;
    # special case for `--exclude-table-data`
    --exclude-table-data=*)
        pg_dump_opts+=("$1")
        exclude_table_data+=("$1")
        ;;
    # general options and fallback
    --help)
        usage
        exit 0
        ;;
    -*|--*)
        echo "$0: Invalid option -- $1"
        echo Try "$0 --help" for more information.
        exit 1
        ;;
    *)
        # this is DBNAME
        pg_dump_opts+=("$1")
        psql_opts+=("$1")
        ;;
    esac
    shift
done

# Stop if the extension is not installed in the database
version=$( psql "${psql_opts[@]}" -c 'SELECT anon.version();' )
if [ -z "$version" ]
then
  echo 'ERROR: Anon extension is not installed in this database.' >&2
  exit 1
fi

# Header
cat > "$output" <<EOF
--
-- Dump generated by PostgreSQL Anonymizer $version
--
EOF

################################################################################
## 1. Dump the DDL (pre-data section)
################################################################################

# gather all options needed to dump the DDL
ddl_dump_opt=(
  "${pg_dump_opts[@]}"     # options from the command line
  "--section=pre-data"         # data will be dumped later
  "--no-security-labels"  # masking rules are confidential
  "--exclude-schema=anon" # do not dump the extension schema
  "--exclude-schema=$(get_mask_schema)" # idem
)

# we need to remove some `CREATE EXTENSION` commands
pg_dump "${ddl_dump_opt[@]}" \
| filter_out_extension anon  \
| filter_out_extension pgcrypto  \
| filter_out_extension tsm_system_rows \
>> "$output"

################################################################################
## 2. Dump the tables data
##
## We need to know which table data must be dumped.
## So We're launching the pg_dump again to get the list of the tables that were
## dumped previously.
################################################################################

# Only this time, we exclude the tables listed in `--exclude-table-data`
tables_dump_opt=(
  "${ddl_dump_opt[@]}"  # same as previously
  ${exclude_table_data//--exclude-table-data=/--exclude-table=}
)

# List the tables whose data must be dumped
dumped_tables=$(
  pg_dump "${tables_dump_opt[@]}" \
  | awk '/^CREATE TABLE /{ print $3 }'
)

# For each dumped table, we export the data by applying the masking rules
for t in $dumped_tables
do
  # get the masking filters of this table (if any)
  filters=$(get_mask_filters "$t")
  # generate the "COPY ... FROM STDIN" statement for a given table
  echo "COPY $t FROM STDIN WITH CSV;" >> "$output"
  # export the data
  psql "${psql_opts[@]}" \
    -c "\\copy (SELECT $filters FROM $t) TO STDOUT WITH CSV" \
    >> "$output" || echo "Error during export of $t" >&2
  # close the stdin stream
  echo \\.  >> "$output"
  echo >> "$output"
done

################################################################################
## 3. Dump the sequences data
################################################################################

# The trick here is to use `--exclude-table-data=*` instead of `--schema-only`
seq_data_dump_opt=(
  "${pg_dump_opts[@]}"      # options from the commande line
  "--exclude-schema=anon"  # do not dump the anon sequences
  "--exclude-table-data=*" # get the sequences data without the tables data
)

pg_dump "${seq_data_dump_opt[@]}"   \
| grep '^SELECT pg_catalog.setval'  \
>> "$output"


################################################################################
## 4. Dump the DDL (post-data section)
################################################################################

# gather all options needed to dump the DDL
ddl_dump_opt=(
  "${pg_dump_opts[@]}"    # options from the command line
  "--section=post-data"
  "--no-security-labels"  # masking rules are confidential
  "--exclude-schema=anon" # do not dump the extension schema
  "--exclude-schema=$(get_mask_schema)" # idem
)

# we need to remove some `CREATE EXTENSION` commands
pg_dump "${ddl_dump_opt[@]}" >> "$output"

exit 0
