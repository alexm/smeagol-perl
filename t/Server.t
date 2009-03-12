#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 46;
use LWP::UserAgent;
use HTTP::Request;
use XML::Simple;
use Carp;
use Data::Dumper;
use Data::Compare;

BEGIN {

    # Purge old test data before testing anything
    #use_ok("DataStore");
    #DataStore->clean();
    #
    # FIXME: Purge the hard way until DataStore does it better
    #
    unlink glob "/tmp/smeagol_datastore/*";

    use_ok($_) for qw(Server Resource Agenda Booking DateTime);
}

my $server_port = 8000;
my $server      = "http://localhost:$server_port";

my $pid = Server->new($server_port)->background();

# Auxiliary routine to encapsulate server requests
sub smeagol_request {
    my ( $method, $url, $xml ) = @_;

    my $req = HTTP::Request->new( $method => $url );

    $req->content_type('text/xml');
    $req->content($xml);

    my $ua  = LWP::UserAgent->new();
    my $res = $ua->request($req);

    return $res;
}

# Auxiliary routine to generate smeagol absolute URLs
sub smeagol_url {
    my $suffix = shift;
    return $server . $suffix;
}

# Auxiliary routine to remove xlink attributes
sub remove_xlink {
    my $xml = shift;

    $xml =~ s/ xmlns:xlink="[^"]*"//g;
    $xml =~ s/ xlink:href="[^"]*"//g;
    $xml =~ s/ xlink:type="[^"]*"//g;

    return $xml;
}

# Testing retrieve empty resource list
{
    my $res = smeagol_request( 'GET', "$server/resources" );
    ok( $res->is_success,
        'resource list retrieval status ' . Dumper( $res->code ) );

    ok(
        $res->content =~
m|<\?xml version="1.0" encoding="UTF-8"\?><\?xml-stylesheet type="application/xml" href="/xsl/resources.xsl"\?><resources xmlns:xlink="http://www.w3.org/1999/xlink" xlink:type="simple" xlink:href="/resources"></resources>|,
        "resource list content " . Dumper( $res->content )
    );
}

# Build a sample resource to be used in tests
my $b1 = Booking->new(
    DateTime->new(
        year   => 2008,
        month  => 4,
        day    => 14,
        hour   => 10,
        minute => 0,
        second => 0
    ),
    DateTime->new(
        year   => 2008,
        month  => 4,
        day    => 14,
        hour   => 10,
        minute => 59,
        second => 0
    )
);
my $b2 = Booking->new(
    DateTime->new(
        year   => 2008,
        month  => 4,
        day    => 14,
        hour   => 11,
        minute => 0,
        second => 0
    ),
    DateTime->new(
        year   => 2008,
        month  => 4,
        day    => 14,
        hour   => 11,
        minute => 59,
        second => 0
    )
);

my $ag = Agenda->new();
$ag->append($b1);
$ag->append($b2);
my $resource = Resource->new( 'desc 2 2', 'gra 2 2', $ag );
my $resource2 = Resource->new( 'desc 2 2', 'gra 2 2' );

# Testing resource creation via XML
{
    my $res =
      smeagol_request( 'POST', smeagol_url('/resource'), $resource->to_xml() );
    ok( $res->code == 201, "resource creation status " . Dumper( $res->code ) );

    my $xmltree = XMLin( $res->content );

    ok(
        $xmltree->{description}      eq $resource->description
          && $xmltree->{granularity} eq $resource->granularity,
        "resource creation content " . Dumper( $res->content )
    );

}

# Testing list_id with non-empty DataStore
{

    # Count number of resources before test
    my @ids             = DataStore->list_id;
    my $id_count_before = @ids;

    # Create several resources
    my $quants = 3;
    for ( my $i = 0 ; $i < $quants ; $i++ ) {
        my $res = smeagol_request( 'POST', smeagol_url('/resource'),
            $resource->to_xml() );
    }

    # Count number of  after test
    @ids = DataStore->list_id;
    my $id_count_after = @ids;

    ok( $id_count_after == $id_count_before + $quants,
        'list_id with non-empty datastore' );
}

# Testing resource retrieval and removal
{

    # first, we create a new resource
    my $res =
      smeagol_request( 'POST', smeagol_url('/resource'), $resource->to_xml() );
    my $xmltree = XMLin( $res->content );

    # retrieve the resource just created
    $res = smeagol_request( 'GET', smeagol_url( $xmltree->{'xlink:href'} ) );
    ok(
        $res->code == 200,
        "resource $xmltree->{'xlink:href'} retrieval, code "
          . Dumper( $res->code )
    );

    my $r = Resource->from_xml( $res->content, 1000 );
    ok( defined $r, "resource retrieval content " . Dumper( $res->content ) );

    # retrieve non-existent Resource
    $res = smeagol_request( 'GET', smeagol_url('/resource/666') );
    ok( $res->code == 404,
        "non-existent resource retrieval status " . Dumper( $res->code ) );

    # delete the resource just created
    $res = smeagol_request( 'DELETE', smeagol_url( $xmltree->{'xlink:href'} ) );
    ok( $res->code == 200, "resource removal $xmltree->{'xlink:href'}" );

    # try to retrieve the deleted resource
    $res = smeagol_request( 'GET', smeagol_url( $xmltree->{'xlink:href'} ) );
    ok(
        $res->code == 404,
        "retrieval of $xmltree->{'xlink:href'} deleted resource "
          . Dumper( $res->code )
    );
}

# Testing resource update
{

    # first, create a new resource
    my $res =
      smeagol_request( 'POST', smeagol_url('/resource'), $resource->to_xml() );

    ok( $res->code == '201',
        'resource creation status ' . Dumper( $res->code ) );
    my $xmltree = XMLin( $res->content );
    my $r = Resource->from_xml( $res->content, 1000 );

    # modify description
    my $nova_desc = 'He canviat la descripcio';
    $r->description($nova_desc);

    # update resource

    $res = smeagol_request( 'POST', smeagol_url( $xmltree->{'xlink:href'} ),
        $resource->to_xml );

    ok(
        $res->code == 200,
        "resource $xmltree->{'xlink:href'} update code: " . Dumper( $res->code )
    );

}

# Testing list bookings
{

    # first, create a new resource
    my $res =
      smeagol_request( 'POST', smeagol_url('/resource'), $resource->to_xml() );

    ok( $res->code == '201',
        'resource creation status ' . Dumper( $res->code ) );

    my $xmltree = XMLin( $res->content );

    print Dumper( $xmltree->{agenda}->{'xlink:href'} );

    $res =
      smeagol_request( 'GET',
        smeagol_url( $xmltree->{agenda}->{'xlink:href'} ) );

    ok(
        $res->code == 200,
        "list bookings "
          . $xmltree->{agenda}->{'xlink:href'}
          . " status "
          . Dumper( $res->code )
    );

    my $ag = Agenda->from_xml( remove_xlink( $res->content ) );

    ok( defined $ag, "list bookings content " . Dumper($ag) );
}

#Testing create booking
{

    # first, create a new resource without agenda, therefore neither bookings
    my $res =
      smeagol_request( 'POST', smeagol_url('/resource'), $resource2->to_xml() );

    ok( $res->code == '201',
        'resource creation status ' . Dumper( $res->code ) );

    my $r = Resource->from_xml( $res->content, 10 );

    $res = smeagol_request( 'POST', smeagol_url('/resource/10/booking'),
        $b1->to_xml() );
    ok(
        $res->code == '201'
          && Booking->from_xml( remove_xlink( $res->content ) ) == $b1,
        'created booking ' . $res->code
    );

    $res = smeagol_request( 'POST', smeagol_url('/resource/10/booking'),
        $b2->to_xml() );
    ok(
        $res->code == '201'
          && Booking->from_xml( remove_xlink( $res->content ) ) == $b2,
        'created booking ' . $res->code
    );

    $res = smeagol_request( 'POST', smeagol_url('/resource/10/booking'),
        $b2->to_xml() );
    ok( $res->code == '409',
        'booking not created because is contained ' . $res->code );
}

#Testing retrieve and remove bookings
{

    # first, create a new resource without bookings
    my $res =
      smeagol_request( 'POST', smeagol_url('/resource'), $resource2->to_xml() );

    ok( $res->code == '201',
        'resource creation status ' . Dumper( $res->code ) );

    my $xmltree      = XMLin( $res->content );
    my $resource_url = $xmltree->{'xlink:href'};

    #and try to retrieve non-existent booking
    $res =
      smeagol_request( 'GET', smeagol_url( $resource_url . '/booking/1' ) );
    ok( $res->code == '404',
        'not retrieved booking because there isn t agenda' );

    # second, add one booking
    $res = smeagol_request( 'POST', smeagol_url( $resource_url . '/booking' ),
        $b1->to_xml() );

    ok(
        $res->code == '201'
          && Booking->from_xml( remove_xlink( $res->content ), 1000 ) == $b1,
        'created booking status: ' . Dumper( $res->code )
    );

    $xmltree = XMLin( $res->content );
    my $booking_url = $xmltree->{'xlink:href'};

    #third, retrieve it, remove it, etc
    $res = smeagol_request( 'GET', smeagol_url($booking_url) );
    ok( Booking->from_xml( remove_xlink( $res->content ), 1000 ) == $b1,
        'retrieved booking' );

    $res =
      smeagol_request( 'GET', smeagol_url( $resource_url . '/booking/1000' ) );
    ok( $res->code == '404', 'not retrieved booking, booking not existent' );

    $res = smeagol_request( 'GET', smeagol_url('/resource/1000/booking/1') );
    ok( $res->code == '404', 'not retrieved booking, resource not existent' );

    $res = smeagol_request( 'POST', smeagol_url( $resource_url . '/booking' ),
        $b2->to_xml() );
    ok(
        $res->code == '201'
          && Booking->from_xml( remove_xlink( $res->content ), 1000 ) == $b2,
        'created booking ' . $res->code
    );

    $xmltree     = XMLin( $res->content );
    $booking_url = $xmltree->{'xlink:href'};

    $res = smeagol_request( 'GET', smeagol_url($booking_url) );
    ok( $res->code == 200, 'retrieve booking status ' . Dumper( $res->code ) );
    ok( Booking->from_xml( remove_xlink( $res->content ), 1000 ) == $b2,
        'retrieved booking content' );

    $res = smeagol_request( 'DELETE', smeagol_url('/resource/1000/booking/1') );
    ok( $res->code == '404',
        'not deleted booking, resource not existent ' . $res->code );

    $res = smeagol_request( 'DELETE', smeagol_url($booking_url) );
    ok( $res->code == '200', 'deleted booking ' . $res->code );

    $res = smeagol_request( 'GET', smeagol_url($booking_url) );
    ok( $res->code == '404',
        'not retrieved booking, booking not existent ' . $res->code );

    $res = smeagol_request( 'DELETE', smeagol_url($booking_url) );
    ok( $res->code == '404',
        'not deleted booking, booking not existent ' . $res->code );

}

# Testing update booking
{
    my $res = smeagol_request( 'POST', smeagol_url('/resource'),
        $resource->to_xml );

    ok( $res->code == 201,
        'created resource for booking_update tests: ' . Dumper( $res->code )
    );

    my $xmltree      = XMLin( $res->content );
    my $resource_url = $xmltree->{'xlink:href'};

    $res = smeagol_request( 'GET',
        smeagol_url( $resource_url . '/bookings' ) );

    ok( $res->code == 200,
        'retrieve bookings list: ' . Dumper( $res->code ) );

    my $ag = Agenda->from_xml( remove_xlink( $res->content ) );

    ok( $ag->size == 2, 'agenda size: ' . Dumper( $ag->size ) );

    my ( $booking1, $booking2 ) = $ag->elements;

    # update first booking with non-existent resource #1000
    $res
        = smeagol_request( 'POST',
        smeagol_url( '/resource/1000/booking/' . $booking1->id ),
        $booking1->to_xml );
    ok( $res->code == 404,
        'trying to update booking for non-existent resource: '
            . Dumper( $res->code )
    );

    # update with existent resource, non-existent booking #2222
    $res
        = smeagol_request( 'POST',
        smeagol_url( $resource_url . '/booking/2222' ),
        $booking1->to_xml );
    ok( $res->code == 404,
        'trying to update non-existent booking: ' . Dumper( $res->code ) );

    # existent resource, existent booking, non-valid new booking
    $res = smeagol_request(
        'POST',
        smeagol_url( $resource_url . '/booking/' . $booking1->id ),
        '<booking>I am not a valid booking :-P</booking>'
    );

    ok( $res->code == 400,
        'trying to update with invalid new booking: ' . Dumper( $res->code )
    );

    # new booking producing overlaps with both existent bookings:
    #    booking1: 10:00 - 10:59
    #    booking2: 11:00 - 11:59
    # new_booking: 10:30 - 11:30  (overlaps booking1, booking2)
    my $new_booking = Booking->new(
        DateTime->new(
            year   => 2008,
            month  => 4,
            day    => 14,
            hour   => 10,
            minute => 30,
            second => 0
        ),
        DateTime->new(
            year   => 2008,
            month  => 4,
            day    => 14,
            hour   => 11,
            minute => 30,
            second => 0
        )
    );

    $res
        = smeagol_request( 'POST',
        smeagol_url( $resource_url . '/booking/' . $booking1->id ),
        $new_booking->to_xml );

    ok( $res->code == 409,
        'producing overlappings when updating booking '
            . $resource_url
            . '/booking/'
            . $booking1->id . ': '
            . Dumper( $res->content )
    );

    # update booking, no overlapping
    my $new_booking2 = Booking->new(
        DateTime->new(
            year   => 2008,
            month  => 4,
            day    => 14,
            hour   => 12,
            minute => 0,
            second => 0
        ),
        DateTime->new(
            year   => 2008,
            month  => 4,
            day    => 14,
            hour   => 12,
            minute => 59,
            second => 0
        )
    );

    $res
        = smeagol_request( 'POST',
        smeagol_url( $resource_url . '/booking/' . $booking2->id ),
        $new_booking2->to_xml );

    ok( $res->code == 200,
        "update booking $resource_url/booking/"
            . $booking1->id
            . ' status: '
            . Dumper( $res->code )
    );

    my $result
        = Booking->from_xml( remove_xlink( $res->content ), $booking2->id );

    ok( $result == $new_booking2,
        'update booking content: ' . Dumper( $result->to_xml ) );
}

END {
    kill 3, $pid;
}
