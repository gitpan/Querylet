use Test::More;

eval { require DBD::SQLite };
plan skip_all => "DBD::SQLite required to run test querylet" if $@;

plan tests => 2;

use Querylet;

sub null {}
Querylet::Query->register_handler(null => \&null);

database: dbi:SQLite:dbname=./t/wafers.db

query:
  SELECT material, COUNT(*) AS howmany, 1 AS one
  FROM   grown_wafers
  WHERE diameter = [% diameter %]
  GROUP BY material
  ORDER BY material, diameter

munge query:
	diameter => 4

munge query:
	diameter => 3

delete column one

munge rows:
	$row->{howmany} *= 2

output format: null

no output

no Querylet;

ok(1, "made it here alive");
is( $q->write_output, undef, "no output (null method)" );

