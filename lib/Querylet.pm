package Querylet;
use Filter::Simple;

use warnings;
use strict;

=head1 NAME

Querylet - simplified queries for the non-programmer

=head1 VERSION

version 0.32

 $Id: Querylet.pm,v 1.20 2005/02/04 18:26:51 rjbs Exp $

=cut

our $VERSION = '0.32';

=head1 SYNOPSIS

 use Querylet;

 database: dbi:SQLite:dbname=wafers.db

 query:
   SELECT wafer_id, material, diameter, failurecode
   FROM   grown_wafers
   WHERE  reactor_id = 105
     AND  product_type <> 'Calibration'

 add column surface_area:
   $value = $row->{diameter} * 3.14;

 add column cost:
   $value = $row->{surface_area} * 100 if $row->{material} eq 'GaAs';
   $value = $row->{surface_area} * 200 if $row->{material} eq 'InP';
 
 munge column failurecode:
   $value = 10 if $value == 3; # 3's have been reclassified
 
 munge all values:
   $value = '(null)' unless defined $value;
 
 output format: html

=head1 DESCRIPTION

Querylet provides a simple syntax for writing Perl-enhanced SQL queries with
multiple output methods.  It processes and renders a template SQL query, then
processes the query results before returning them to the user.

The results can be returned in various formats.

=cut

=head1 SYNTAX

The intent of Querylet is to provide a simple syntax for writing queries.
Querylet will rewrite querylets from their simple form into complete Perl
programs.  The syntax described here is the "intended" and basic syntax, but
savvy Perl hackers will realize that horrible things can be done by
interspersing "real" Perl with querylet directives.

I am afraid I really cannot suggest that course of action, sir.

=head2 DIRECTIVES

In the directives below, a BLOCK begins after the colon preceding it and ends
at the next line with something unindented.

=over 4

=item C<database: VALUE>

This directive provides information about the database to which to connect.
Its syntax is likely to be better defined by the specific Querylet subclass
you're using.

=item C<output format: VALUE>

This directive names a format to be used by the output renderer.  The default
value is "csv".

=item C<output file: VALUE>

This directive names a file to which the rendered output should be written.  If
not given, renderers will present output to the terminal, or otherwise
interactively.  If this doesn't make sense, an error should be thrown.

=item C<query: BLOCK>

 query:
   SELECT customer.customerid, lastname, firstname, COUNT(*)
   FROM   customers
   JOIN   orders ON customer.customerid = orders.customerid
   GROUP BY customer.customerid, lastname, firstname

This directive provides the query to be run by Querylet.  The query can
actually be a template, and will be rendered before running if (and only if)
the C<munge query> directive occurs in the querylet.  The query can include
bind parameters -- that is, you can put a ? in place of a value, and later use
C<query parameter> to replace the value.  (See below.)

It is important that every selected column have a name or alias.

=item C<query parameter: BLOCK>

This directive sets the value for the next bind parameter.  You should have one
(and only one) C<query parameter> directive for each "?" in your query.

=item C<munge query: BLOCK>

The directive informs Querylet that the given query is a template and must be
rendered.  The BLOCK must return a list of parameter names and values, which
will be passed to the template toolkit to render the query.

=item C<set option NAME: BLOCK>

This sets the name option to the given value, and is used to set up options for
plugins and I/O handlers.  Leading and trailing space is stripped from the
block.

=item C<munge rows: BLOCK>

This directive causes the given block of code to be run on every row.  The row
is made available to the block as C<$row>, a hashref.

=item C<delete rows where: BLOCK>

This directive will cause any row to be deleted where the given condition
evaluates true.  In that evaluation, C<$row> is available.

=item C<munge all values: BLOCK>

This directive causes the given block of code to be run on every value of every
row.  The row is made available to the block as C<$row>, a hashref.  The value
is available as C<$value>.

=item C<munge column NAME: BLOCK>

This directive causes the given block of code to be run on the named column in
every row.  The row is made available to the block as C<$row>, a hashref.  The
column value is available as C<$value>.

=item C<add column NAME: BLOCK>

This directive adds a column to the result set, evaluating the given block for
each row.  The row is made available as to the block as C<$row>, and the new
column value is available as C<$value>.

=item C<delete column NAME>

This directive deletes the named column from the result set.

=item C<delete columns where: BLOCK>

This directive will cause any column to be deleted where the given condition
evaluates true.  In that evaluation, C<$column> is available, containing the
column name; C<@values> contains all the values for that column.

=item C<no output>

This directive instructs the Querylet not to output its results.

=back

=head1 IMPLEMENTATION

Querylet is a source filter, implemented as a class suitable for subclassing.
It rewrites the querylet to use the Querylet::Query class to perform its work.

=cut

=head2 METHODS

=over 4

=item C<< Querylet->init >>

The C<init> method is called to generate a header for the querylet, importing
needed modules and creating the Query object.  By default, the Query object is
assigned to C<$q>.

=cut

sub init { <<''
use strict;
use warnings;
use Querylet::Query;
my $q ||= new Querylet::Query;

}

=item C<< Querylet->set_dbh($text) >>

This method returns Perl code to set the database handle to be used by the
Query object.  The default implementation will attempt to use $text as a DBI
connect string to create a dbh.

=cut

sub set_dbh    { shift; <<""
use DBI;
my \$dbh = DBI->connect(q|$_[0]|);
\$q->set_dbh(\$dbh);

}

=item C<< Querylet->set_query($sql_template) >>

This method returns Perl code to set the Query object's SQL query to the passed
value.

=cut

sub set_query  { shift; "\$q->set_query(q{$_[0]});\n"; }

=item C<< Querylet->bind_next_param($text) >>

This method produces Perl code to push the given parameters onto the list of
bind parameters for the query.  (The text should evaluate to a list of
parameters to push.)

=cut

sub bind_next_param { shift; <<""
{
	my \$input = \$q->{input};
	\$q->bind_more($_[0]);
}

}

=item C<< Querylet->set_query_vars(%values) >>

This method returns Perl code to set the template variables to be used to
render the SQL query template.

=cut

sub set_query_vars { shift; <<""
{
	my \$input = \$q->{input};
	\$q->set_query_vars({$_[0]});
}

}

=item C<< Querylet->set_option($option, $value) >>

This method returns Perl code to set the named query option to the given value.
At present, this works by using the Querylet::Query scratchpad, but a more
sophisticated method will probably be implemented.  Someday.

=cut

sub set_option  { shift;
	my ($option, $value) = @_;
	$value =~ s/(^\s+|\s+$)//g;
	"\$q->option(q{$option}, q{$value});\n"
}

=item C<< Querylet->input($parameter) >>

This method returns code to instruct the Query object to get an input parameter
with the given name.

=cut

sub input { shift; "\$q->input(q{$_[0]});\n"; }

=item C<< Querylet->set_input_type($type) >>

This method returns Perl code to set the input format.

=cut

sub set_input_type { shift; "\$q->input_type(q{$_[0]});\n"; }

=item C<< Querylet->set_output_filename($filename) >>

This method returns Perl code to set the output filename.

=cut

sub set_output_filename { shift; "\$q->output_filename(q{$_[0]});\n"; }

=item C<< Querylet->set_output_method($type) >>

This method returns Perl code to set the output method.

=cut

sub set_output_method { shift; "\$q->write_type(q{$_[0]});\n"; }

=item C<< Querylet->set_output_type($type) >>

This method returns Perl code to set the output format.

=cut

sub set_output_type { shift; "\$q->output_type(q{$_[0]});\n"; }

=item C<< Querylet->munge_rows($text) >>

This method returns Perl code to execute the Perl given in C<$text> for every
row in the result set, aliasing C<$row> to the row on each iteration.

=cut

sub munge_rows { shift; <<"";
foreach my \$row (\@{\$q->results}) {
	$_[0]
}

}

=item C<< Querylet->delete_rows($text) >>

This method returns Perl code to delete from the result set any row for which
C<$text> evaluates true.  The code iterates over every row in the result set,
aliasing C<$row> to the row.

=cut

sub delete_rows { shift; <<"";
my \@new_results;
for my \$row (\@{\$q->results}) {
	push \@new_results, \$row unless ($_[0]);
}
\$q->set_results([\@new_results]);

}

=item C<< Querylet->munge_col($column, $text) >>

This method returns Perl code to evaluate the Perl code given in C<$text> for
each row, with the variables C<$row> and C<$value> aliased to the row and it's
C<$column> value respectively.

=cut

sub munge_col  { shift; <<"";
foreach my \$row (\@{\$q->results}) {
	foreach my \$value (\$row->{$_[0]}) {
		$_[1]
	}
}

}

=item C<< Querylet->add_col($column, $text) >>

This method returns Perl code, adding a column with the given name.  The Perl
given in C<$text> is evaluated for each row, with the variables C<$row> and
C<$value> aliased to the row and row column respectively.

If a column with the given name already exists, a warning issue and the
directive is ignored.

=cut

sub add_col  { shift; <<"";
if (exists \$q->results->[0]->{$_[0]}) {
	warn "column $_[0] already exists; ignoring directive\n";
} else { 
	push \@{\$q->columns}, '$_[0]';
	foreach my \$row (\@{\$q->results}) {
		for my \$value (\$row->{$_[0]}) {
			$_[1]
		}
	}
}

}

=item C<< Querylet->delete_col($column) >>

This method returns Perl code, deleting the named column from the result set.

=cut

sub delete_col  { shift; <<"";
\$q->set_columns( [ grep { \$_ ne "$_[0]" } \@{\$q->columns} ] );
foreach my \$row (\@{\$q->results}) {
	delete \$row->{$_[0]};
}

}

=item C<< Querylet->delete_cols($text) >>

This method returns Perl code to delete from the result set any row for which
C<$text> evaluates true.  The code iterates over every column in the result
set, creating C<@values>, which contains a copy of all the values in that
columns, and C<$column>, which contains the name of the current column.

=cut

sub delete_cols { my $class = shift; qq|
for my \$column (\@{\$q->columns}) {
	my \@values;
	push \@values, \$_->{\$column} for \@{\$q->results};
	if ($_[0]) {
| .	 $class->delete_col('$column') . qq|
	}
}
|

}

=item C<< Querylet->column_headers($text) >>

This method returns Perl code to set up column headers.  The C<$text> should be
Perl code describing a hash of column-header pairs.

=cut

sub column_headers { my $class = shift; "\$q->set_headers({ $_[0] });" }

=item C<< Querylet->munge_values($text) >>

This method returns Perl code to perform the code in C<$text> on every value in
every row in the result set.

=cut

sub munge_values { shift; <<"";
foreach my \$row (\@{\$q->results}) {
	foreach my \$value (values \%\$row) {
		$_[0]
	}
}

}

=item C<< Querylet->output >>

This returns the Perl instructing the Query to output its results in the
requested format, to the requested destination.

=cut

sub output { shift; <<''
$q->write_output;

}

=back

=head2 FUNCTIONS

=over 4

=item C<< once($id, $text) >>

This is a little utility function, used to ensure that a bit of text is only
included once.  If it has been called before with the given C<$id>, an empty
string is returned.  Otherwise, C<$text> is returned.

=cut

my %ran;

sub once {
	my ($id, $text) = @_;
	return '' if $ran{$id}++;
	return $text || '';
}

my $to_next = qr/(?=^\S|\Z)/;

FILTER {
	my ($class) = @_;

	s/\r//g;
  s/\A/once('init',init)/egms;

	s/^ database:\s*([^\n]+)
	 /  $class->set_dbh($1)
	 /egmsx;

	s/^ query:\s*(.+?)
	    $to_next
	 /  $class->set_query($1)
	 /egmsx;
	
	s/^ query\s+parameter:\s*(.+?)
	    $to_next
	 /  $class->bind_next_param($1);
	 /egmsx;

	s/^ munge\s+query:\s*(.+?)
	    $to_next
	 /  $class->set_query_vars($1);
	 /egmsx;

	s/^ set\s+option\s+([\/A-Za-z0-9_]+):\s*(.+?)
			$to_next
	 /  $class->set_option($1,$2);
	 /egmsx;

	s/^ input:\s*([^\n]+)
	 /  $class->input($1)
	 /egmsx;

	s/^ input\s+type:\s+(\w+)$
	 /  $class->set_input_type($1);
	 /egmsx;

	s/^ munge\s+rows:\s*(.+?)
	    $to_next
	 /  $class->munge_rows($1);
	 /egmsx;

	s/^ delete\s+rows\s+where:\s*(.+?)
	    $to_next
	 /  $class->delete_rows($1);
	 /egmsx;

	s/^ munge\s+all\s+values:\s*(.+?)
	    $to_next
	 /  $class->munge_values($1);
	 /egmsx;

	s/^ munge\s+column\s+(\w+):\s*(.+?)
	    $to_next
	 /  $class->munge_col($1, $2);
	 /egmsx;

	s/^ add\s+column\s+(\w+):\s*(.+?)
	    $to_next
	 /  $class->add_col($1, $2);
	 /egmsx;

	s/^ delete\s+column\s+(\w+)$
	 /  $class->delete_col($1);
	 /egmsx;

	s/^ delete\s+columns\s+where:\s*(.+?)
	    $to_next
	 /  $class->delete_cols($1);
	 /egmsx;

	s/^ column\s+headers?:\s*(.+?)
	    $to_next
	 /  $class->column_headers($1);
	 /egmsx;

	s/^ output\s+format:\s+(\w+)$
	 /  $class->set_output_type($1);
	 /egmsx;

	s/^ output\s+method:\s+(\w+)$
	 /  $class->set_output_method($1);
	 /egmsx;

	s/^ output\s+file:\s+([_.A-Za-z0-9]+)$
	 /  $class->set_output_filename($1);
	 /egmsx;

	s/^ no\s+output$
	 /  once('output', '')
	 /egmsx;

	s/\Z
	 /once('output',output)
	 /egmsx;
}

=back

=head1 SEE ALSO

L<Querylet::Query>

=head1 AUTHOR

Ricardo SIGNES, C<< <rjbs@cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-querylet@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.  I will be notified, and then you'll automatically be
notified of progress on your bug as I make changes.

=head1 COPYRIGHT

Copyright 2004 Ricardo SIGNES, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

"I do endeavor to give satisfaction, sir.";
