package Querylet::Query;

use strict;
use warnings;

=head1 NAME

Querylet::Query - renders and performs queries for Querylet

=head1 VERSION

version 0.12

 $Id: Query.pm,v 1.4 2004/09/17 13:04:09 rjbs Exp $

=cut

our $VERSION = '0.12';

=head1 SYNOPSIS

 use DBI;
 my $dbh = DBI->connect('dbi:Pg:dbname=drinks');
 
 use Querylet::Query;
 # Why am I using this package?  I'm a human, not Querylet!

 my $q = new Querylet::Query;

 $q->set_dbh($dbh);

 $q->set_query("
   SELECT *
   FROM   drinks d
   WHERE  abv > [% min_abv %]
     AND  '[% required_liquor %]' IN (
            SELECT liquor FROM ingredients WHERE i i.drink_id = d.drink_id
          )
   ORDER BY d.name
 ");

 $q->set_query_vars({ min_abv => 25, required_liquor => 'sour mash'});

 $q->run;

 $q->set_output_type('html');

 $q->output;

=head1 DESCRIPTION

Querylet::Query is used by Querylet-generated code to make that code go.  It
renders templatized queries, executes them, and hangs on to the results until
they're ready to go to output.

This module is probably not particularly useful outside of its use in code
written by Querylet, but there you have it.

=head1 METHODS

=over 4

=item C<< Querylet::Query->new >>

This creates and returns a new Querylet::Query.

=cut

sub new { bless {} => (shift); }

=item C<< $q->set_dbh($dbh) >>

This method sets the database handle to be used for running the query.

=cut

sub set_dbh {
	my $self = shift;
	my $dbh = shift;
	$self->{dbh} = $dbh;
}

=item C<< $q->set_query($query) >>

This method sets the query to run.  The query may be a plain SQL query or a
template to be rendered later.

=cut

sub set_query {
	my ($self, $sql) = @_;

	$self->{query} = $sql;
}

=item C<< $q->set_query_vars(\%variables) >>

This method sets the given variables, to be used when rendering the query.
It also indicates that the query that was given is a template, and should be
rendered.  (In other words, if this method is called at least once, even with
an empty hashref, the query will be considered a template, and rendered.)

=cut

sub set_query_vars {
	my ($self, $vars) = @_;

	$self->{query_vars} ||= {};
	$self->{query_vars} = { %{$self->{query_vars}}, %$vars };
}

=item C<< $q->render_query >>

This method renders the query using a templating engine (Template Toolkit, by
default) and returns the result.  This method is called internally by the run
method, if query variables have been set.

Normal Querylet code will not need to call this method.

=cut

sub render_query {
	my $self = shift;
	my $rendered_query;

	require Template;
	my $tt = new Template;
	$tt->process(\($self->{query}), $self->{query_vars}, \$rendered_query);

	return $rendered_query;
}

=item C<< $q->run >>

This method runs the query and sets up the results.  It is called internally by
the results method, if the query has not yet been run.

Normal Querylet code will not need to call this method.

=cut

sub run {
	my $self = shift;

	$self->{query} = $self->render_query if $self->{query_vars};

	my $sth = $self->{dbh}->prepare($self->{query});
	   $sth->execute;
	$self->{columns} = $sth->{NAME};
	$self->{results} = $sth->fetchall_arrayref({});
}

=item C<< $q->results >>

This method returns the results of the query, first running the query (by
calling C<run>) if needed.

The results are returned as a reference to an array of rows, each row a
reference to a hash.  These are not copies, and may be altered in place.

=cut

sub results {
	my $self = shift;
	return $self->{results} if $self->{results};
	$self->run;
}

=item C<< $q->set_results( \@new_results ) >>

This method replaces the result set with the provided results.  This method
does not call the results method, so if the query has not been run, it will not
be run by this method.

=cut

sub set_results {
	my $self = shift;
	$self->{results} = shift;
}

=item C<< $q->set_output_filename($filename) >>

This method sets a filename to which output should be directed.

If called with no arguments, it returns the name.  If called with C<undef>, it
unassigns the currently assigned filename.

=cut

sub set_output_filename {
	my $self = shift;
	return  $self->{output_filename} unless @_;
	return ($self->{output_filename} = undef) unless (my $filename = shift);

	if (-f $filename) {
		warn "filename already exists; aborting\n";
		exit;
	} else {
		$self->{output_filename} = $filename;
	}
}

=item C<< $q->set_output_type($type) >>

This method sets the format of the output to be generated.  If an unregistered
format is requested, the querylet will complain and abort execution.

=cut

my %output_handler;

sub set_output_type {
	my $self = shift;
	my $output_as = shift;
	unless ($output_handler{$output_as}) {
		warn "output type '$output_as' unknown; aborting\n";
		exit;
	} else {
		$self->{output_as} = $output_as;
	}
}

=item C<< $q->output >>

This method tells the Query to send the current results to the proper output
handler.

=cut

sub output {
	my $self = shift;
	   $self->{output_as} ||= 'csv';

	unless ($output_handler{$self->{output_as}}) {
		warn "unknown output type: $self->{output_as}\n";
		return;
	} else {
		$output_handler{$self->{output_as}}->($self);
	}
}

## BEGIN AWFUL OUTPUT STUFF

=item C<< Querylet::Query->register_handler($type => \&handler) >>

This method registers a handler routine for the given type.  (The prototype
sort of documents itself, doesn't it?)

It can be called on an instance, too.  It doesn't mind.

In a type is registered that already has a handler, the old handler is quietly
replaced.  (This makes replacing the built-in, naive handlers quite painless.)

=cut

sub register_handler {
	shift;
	my ($type, $handler) = @_;
	$output_handler{$type} = $handler;
}

=item C<< as_csv($q) >>

This is the default, built-in handler.  It outputs the results of the query as
a CSV file.  That is, a series of comma-delimited fields, with each record
separated by a newline.

If a output filename was specified, the output is sent to that file (unless it
exists).  Otherwise, it's printed standard output.

=cut

__PACKAGE__->register_handler(csv   => \&as_csv);
sub as_csv {
	my $query = shift;
	my $csv;
	my $results = $query->results;
	my $columns = $query->{columns};
	$csv = join(',', @$columns) . "\n";
	foreach my $row (@$results) {
		$csv .= join(',',(map { defined $_ ? $_ : '' } @$row{@$columns})) . "\n";
	}

	my $to;
	if ($query->{filename}) {
		open $to, '>', $query->{filename};
	} else {
		$to = \*STDOUT;
	}
	print $to $csv;
}

=item C<< as_html($q) >> 

This is a built-in handler.  It outputs the results of the query as a minimal
HTML document.  The query results are put into an HTML table in a document with
no other contents.

If a output filename was specified, the output is sent to that file (unless it
exists).  Otherwise, it's printed standard output.

=cut

__PACKAGE__->register_handler(html  => \&as_html);
sub as_html {
	my $query = shift;
	my $results = $query->results;
	my $columns = $query->{columns};

	my $html = "<html><head><title>results of query</title></head>";
	   $html .= "<body><table><tr>";
	   $html .= join('', map { "<th>$_</th>" } @$columns);
	   $html .= "</tr>\n";

		 $html .= "<tr>" . join('', map { "<td>$_</td>" } @$_{@$columns}). "</tr>\n"
	     foreach (@$results);

	   $html .= "</table></body></html>\n";

	my $to;
	if ($query->{filename}) {
		open $to, '>', $query->{filename};
	} else {
		$to = \*STDOUT;
	}
	print $to $html;
}

=back

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
