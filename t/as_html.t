use Test::More;

eval { require DBD::SQLite };
plan skip_all => "DBD::SQLite required to run test querylet" if $@;

plan tests => 1;

use Querylet;

database: dbi:SQLite:dbname=./t/wafers.db

query:
  SELECT wafer_id
  FROM   grown_wafers

output format: html

$q->output; # force execution of csv handler

no output

no Querylet;

ok(1, "made it here alive");
