package Querylet::Query;

use strict;
use warnings;

=head1 NAME

Querylet::Query - renders and performs queries for Querylet

=head1 VERSION

version 0.22

 $Id: Query.pm,v 1.11 2004/09/20 18:46:35 rjbs Exp $

=cut

our $VERSION = '0.22';

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
     AND  ? IN (
            SELECT liquor FROM ingredients WHERE i i.drink_id = d.drink_id
          )
   ORDER BY d.name
 ");

 $q->set_query_vars({ min_abv => 25 });

 $q->bind("rum");

 $q->run;

 $q->output_type('html');

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

sub new {
	bless {
		bind_parameters => [],
		output_type     => 'csv',
		input_type => 'term'
	} => (shift);
}

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

=item C<< $q->bind(@parameters) >>

This method sets the bind parameters, overwriting any existing parameters.

=cut

sub bind {
	my ($self, @parameters) = @_;
	$self->{bind_parameters} = [ @parameters ];
}

=item C<< $q->bind_more(@parameters) >>

This method pushes the given parameters onto the list of bind parameters to use
when executing the query.

=cut

sub bind_more {
	my ($self, @parameters) = @_;
	$self->{bind_parameters} = [] unless $self->{bind_parameters};
	push @{$self->{bind_parameters}}, @parameters;
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
	   $sth->execute(@{$self->{bind_parameters}});
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

=item C<< $q->columns >>

This method returns the column names (as an arrayref) for the query's results.
The query will first be run (by calling C<run>) if needed.

=cut

sub columns {
	my $self = shift;
	return $self->{columns} if $self->{columns};
	$self->run;
	return $self->{columns};
}

=item C<< $q->set_columns( \@new_columns ) >>

This method replaces the list of column names for the current query result.  It
does not call the columns method, so if the query has not been run, it will not
be run by this method.

=cut

sub set_columns {
	my $self = shift;
	$self->{columns} = shift;
}

=item C<< $q->scratchpad >>

This method returns a reference to a hash for general-purpose note-taking.
I've put this here for really simple, mediocre communication between handlers.
I'm tempted to warn you that it might go away, but I think it's unlikely.  

=cut

sub scratchpad {
	my $self = shift;
	$self->{scratchpad} = {} unless $self->{scratchpad};
	return ($self->{scratchpad});
}

=item C<< $q->input_type($type) >>

This method sets or retrieves the input type, which is used to find the input
handler.

=cut

my %input_handler;

sub input_type {
	my $self = shift;
	return  $self->{input_type} unless @_;
	return ($self->{input_type} = undef) unless (my $type = shift);

	$self->{input_type} = $type;
}

=item C<< $q->input($parameter) >>

This method tells the Query to ask the current input handler to request that
the named parameter be received from input.

=cut

sub input {
	my ($self, $parameter) = @_;

	$self->{input} = {} unless $self->{input};
	return $self->{input}->{$parameter} if exists $self->{input}->{$parameter};

	unless ($input_handler{$self->input_type}) {
		warn "unknown input type: ", $self->input_type," \n";
		return;
	} else {
		$input_handler{$self->input_type}->($self, $parameter);
	}
}

=item C<< Querylet::Query->register_input_handler($type => \&handler) >>

This method registers an input handler routine for the given type.

If a type is registered that already has a handler, the old handler is quietly
replaced.  (This makes replacing the built-in, naive handlers quite painless.)

=cut

sub register_input_handler {
	shift;
	my ($type, $handler) = @_;
	$input_handler{$type} = $handler;
}

=item C<< $q->output_filename($filename) >>

This method sets a filename to which output should be directed.

If called with no arguments, it returns the name.  If called with C<undef>, it
unassigns the currently assigned filename.

=cut

sub output_filename {
	my $self = shift;
	return  $self->{output_filename} unless @_;
	return ($self->{output_filename} = undef) unless (my $filename = shift);

	$self->{output_filename} = $filename;
}

=item C<< $q->output_type($type) >>

This method sets or retrieves the format of the output to be generated.

=cut

my %output_handler;

sub output_type {
	my $self = shift;
	return  $self->{output_type} unless @_;
	return ($self->{output_type} = undef) unless (my $type = shift);

	$self->{output_type} = $type;
}

=item C<< $q->output >>

This method tells the Query to send the current results to the proper output
handler and return them.  If the outputs have already been generated, they are
not re-generated.

=cut

sub output {
	my $self = shift;

	return $self->{output} if exists $self->{output};

	unless ($output_handler{$self->output_type}) {
		warn "unknown output type: ", $self->output_type," \n";
		return;
	} else {
		$self->{output} = $output_handler{$self->output_type}->($self);
		unless ($self->{output}) {
			warn "no output received from output handler!\n";
			return;
		}
		return $self->{output};
	}
}

=item C<< $q->write_output >>

This method tells the Query to write the query output.  If no filename has been
set for output, the results are just printed.

If the result of the output method is a coderef, the coderef will be evaluated
and nothing will be printed.

=cut

sub write_output {
	my ($self) = @_;
	my $output = $self->output;

	if (ref $output eq 'CODE') {
		$output->();
	} else {
		if ($self->output_filename) {
			if (open(my $output_file, '>', $self->output_filename)) {
				print $output_file $self->output;
				close $output_file;
			} else {
				warn "can't open $self->{output_filename} for output";
				return;
			}
		} else {
			print $self->output || '';
		}
	}
	return $self->output;
}

=item C<< Querylet::Query->register_output_handler($type => \&handler) >>

This method registers an output handler routine for the given type.  (The
prototype sort of documents itself, doesn't it?)

It can be called on an instance, too.  It doesn't mind.

If a type is registered that already has a handler, the old handler is quietly
replaced.  (This makes replacing the built-in, naive handlers quite painless.)

=cut

sub register_output_handler {
	shift;
	my ($type, $handler) = @_;
	$output_handler{$type} = $handler;
}

=item C<< as_csv($q) >>

This is the default, built-in output handler.  It outputs the results of the
query as a CSV file.  That is, a series of comma-delimited fields, with each
record separated by a newline.

If a output filename was specified, the output is sent to that file (unless it
exists).  Otherwise, it's printed standard output.

=cut

__PACKAGE__->register_output_handler(csv   => \&as_csv);
sub as_csv {
	my $q = shift;
	my $csv;
	my $results = $q->results;
	my $columns = $q->columns;
	$csv = join(',', @$columns) . "\n";
	foreach my $row (@$results) {
		$csv .= join(',',(map { defined $_ ? $_ : '' } @$row{@$columns})) . "\n";
	}

	return $csv;
}

=item C<< as_html($q) >> 

This is a built-in output handler.  It outputs the results of the query as a
minimal HTML document.  The query results are put into an HTML table in a
document with no other contents.

If a output filename was specified, the output is sent to that file (unless it
exists).  Otherwise, it's printed standard output.

=cut

__PACKAGE__->register_output_handler(html  => \&as_html);
sub as_html {
	my $q = shift;
	my $results = $q->results;
	my $columns = $q->columns;

	my $html = "<html><head><title>results of query</title></head>";
	   $html .= "<body><table><tr>";
	   $html .= join('', map { "<th>$_</th>" } @$columns);
	   $html .= "</tr>\n";

		 $html .= "<tr>" . join('', map { "<td>$_</td>" } @$_{@$columns}). "</tr>\n"
	     foreach (@$results);

	   $html .= "</table></body></html>\n";

	return $html;
}

=item C<< from_term($q, $parameter) >>

This is a simple built-in input handler to prompt the user interactively for
parameter inputs.  It is the default input handler.

=cut

__PACKAGE__->register_input_handler(term => \&from_term);
sub from_term {
	my ($q, $parameter) = @_;

	print "enter $parameter: ";
	my $value = <STDIN>;
	chomp $value;
	$q->{input}->{$parameter} = $value;
}

=back

=head1 SEE ALSO

L<Querylet>, L<Querylet::Input>, L<Querylet::Output>

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
