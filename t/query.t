use Test::More tests => 11;
use strict;
use warnings;

BEGIN { use_ok("Querylet::Query"); }

my $q = new Querylet::Query;

is($q->output_filename,                undef, "no output filename defined");
is($q->output_filename('xyz.txt'), 'xyz.txt', "filename set properly");
is($q->output_filename,            'xyz.txt', "filename retrieved");
is($q->output_filename(undef),         undef, "filename unset");
is($q->output_filename,                undef, "no output filename defined");

is($q->output_type,                undef, "no output format defined");
is($q->output_type('xyz'),         'xyz', "format set properly");
is($q->output_type,                'xyz', "format retrieved");
is($q->output_type(undef),         undef, "format unset");
is($q->output_type,                undef, "no output format defined");
