use Test::More tests => 3;

BEGIN {
  require_ok('Querylet');
      use_ok('Querylet::Query');
  require_ok('Querylet::Output');
}

diag( "Testing $Querylet::VERSION" );
