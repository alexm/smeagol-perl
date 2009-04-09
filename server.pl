#!/usr/bin/perl

use strict;
use warnings;

my $VERSION = 0.2;

use Getopt::Euclid qw( :minimal_keys );

use Server;
use DataStore;

if ( $ARGV{verbose} ) {
    print "$0 version $VERSION entering verbose mode.\n";
    print "Binding to $ARGV{host} and listening on port $ARGV{port}.\n";
    print "DataStore in $ARGV{storage}.\n";
}

# initialize the datastore singleton
DataStore::init( $ARGV{storage} );

my $server = Server->new( $ARGV{port} );
$server->host( $ARGV{host} );

if ( $ARGV{background} ) {
    my $pid = $server->background();
    print "Going background (PID $pid).\n"
        if $ARGV{verbose};
}
else {
    print "Running...\n"
        if $ARGV{verbose};
    $server->run();
}

__END__

=head1 NAME

smeagol-server - Smeagol server

=head1 VERSION

This documentation refers to version 0.2

=head1 OPTIONS

=over

=item --port [=] <port>

Listen on port number

=for Euclid:
    port.type:    +integer
    port.default: 8000

=item --host [=] <host>

Address to bind to

=for Euclid:
    host.type:    str
    host.default: 'localhost'

=item --storage [=] <storage>

Directory where datastore resides

=for Euclid:
    storage.type:    string
    storage.default: '/tmp/smeagol_datastore'

=item --[no[-]]verbose

[Don't] show verbose messages

=for Euclid:
    false: --no[-]verbose

=item --[no[-]]background

[Don't] run in the background

=for Euclid:
    false: --no[-]background

=item --help

=item --version

=item --usage

=item --man

=back

=head1 AUTHORS

Angel Aguilera <angel.aguilera@upc.edu>
Eulalia Formenti <eulalia.formenti@upc.edu>
Francesc Guasch <frankie@etsetb.upc.edu>
Francisco Morillas <fmorillas@etsetb.upc.edu>
Alex Muntada <alexm@alexm.org>
Isabel Polo <ipolo@etsetb.upc.edu>
Sebastia Vila <sebas@lsi.upc.edu>

=head1 COPYRIGHT 

Copyright (C) 2008,2009  Universitat Politecnica de Catalunya

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

