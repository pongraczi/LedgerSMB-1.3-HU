=head1 NAME

LedgerSMB::DBObject_Moose - LedgerSMB class for building objects from db 
relations, now with Moose!

=head1 SYOPSIS

This module creates object instances based on LedgerSMB's in-database ORM, using Moose.

=cut

package LedgerSMB::DBObject_Moose;
use Moose::Role;
use LedgerSMB::DBObject;
use LedgerSMB;
use Scalar::Util;
use Log::Log4perl;
use LedgerSMB::DBObject;
use Moose::Util::TypeConstraints;
use LedgerSMB::MooseTypes

=head1 METHODS

=over

=item new ($class, base => $LedgerSMB::hash)

This is the base constructor for all child classes.  It must be used with base
argument because this is necessary for database connectivity and the like.

Of course the base object can be any object that inherits LedgerSMB, so you can
use any subclass of that.  The per-session dbh is passed between the objects 
this way as is any information that is needed.

=item exec_method 

($self, procname => $function_name, [args => \@args, schema => $schema,
continue_on_error=>$continue_on_error])

Provides the basic mapping of parameters to the SQL stored procedure function 
arguments.

If \@args is not defined, args are mapped from the object's properties, 
stripping them of their in_ prefix.  If schema is provided, that is used 
instead of PostgreSQL's search path.  If continue_on_error is provided and true,
the operation will not raise an exception in the event of a database error, and 
it will be up to the application to handle any exceptions.

=item _db_array_scalars(@elements) creates a db array from scalars.

=item _db_array_literal(@elements) creates a multiple dimension db array from 
	preparsed db arrays or other data which does not need to be escaped.

=cut

my $logger = Log::Log4perl->get_logger('LedgerSMB::DBObject');

sub prepare_dbhash {
    my $self = shift;
    my $target = shift;
    $target->{dbh} = $LedgerSMB::App_State::DBH;
}

# _to_dbobject 
#Private method used to convert to db object for purposes of function wrapping
#
sub _to_dbobject {
     my $self   = shift @_;
    return LedgerSMB::DBObject->new({base => $self});
}

=item set_ordering

Sets the ordering used by default for specific functions called by exec_method

=cut

sub exec_method {
    my $self   = shift @_;
    my $dbo = $self->_to_dbobject;
    return $dbo->exec_method(@_);
}

=item run_custom_queries

Backward-compatible with 1.2 custom query system for moving forward.

=cut

sub run_custom_queries {
    my $self   = shift @_;
    my $dbo = $self->_to_dbobject;
    return $dbo->run_custom_queries(@_);
}

sub call_procedure {
    my $self   = shift @_; 
    return LedgerSMB->call_procedure(@_);
}

# Keeping this here due to common requirements
sub is_allowed_role {
    my $self   = shift @_;
    my $dbo = $self->_to_dbobject;
    return $dbo->is_allowed_role(@_);
}

sub get_interval_dates {
    my ($self, $year, $month, $type) = @_;
    my $start = "$year-$month-01"; 
    return {start => undef, end => LedgerSMB::PGDate->from_db($start, 'date')}
      if $type eq 'none';
    my $dbh = $LedgerSMB::App_State::DBH;
    my $intervals = {
          year => '1 year',
          month => '1 month',
          quarter => '3 months'
    };

    my $sth = $dbh->prepare(
           "SELECT (?::date + ?::interval - '1 day'::interval)::date"
    );

    $sth->execute($start, $intervals->{$type});
    my ($end) = $sth->fetchrow_array();
    return { start => LedgerSMB::PGDate->from_db($start, 'date'), 
               end => LedgerSMB::PGDate->from_db($end, 'date') };   
}

=back

=head1 Copyright (C) 2007, The LedgerSMB core team.

This file is licensed under the Gnu General Public License version 2, or at your
option any later version.  A copy of the license should have been included with
your software.

=cut

1;
