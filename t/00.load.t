use Test::More tests => 2;

BEGIN {
  require_ok('Querylet');
      use_ok('Querylet::Query');
}

diag( "Testing $Querylet::VERSION" );
