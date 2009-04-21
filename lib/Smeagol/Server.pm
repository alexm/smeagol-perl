package Smeagol::Server;

use strict;
use warnings;

use HTTP::Server::Simple::CGI;
use base qw(HTTP::Server::Simple::CGI);
use CGI qw();
use XML::LibXML;
use Carp;
use Data::Dumper;
use Smeagol::Tag;
use Smeagol::Booking;
use Smeagol::Agenda;
use Smeagol::Resource;
use Smeagol::Resource::List;

# Nota: hauria de funcionar amb "named groups" però només
# s'implementen a partir de perl 5.10. Quina misèria, no?
# A Python fa temps que funcionen...
#
# Dispatcher table. Associates a handler to an URL. Groups in
# the URL pattern are given as parameters to handler.
my %crud_for = (
    '/resources'      => { GET => \&_list_resources, },
    '/resource/(\d+)' => {
        GET    => \&_retrieve_resource,
        DELETE => \&_delete_resource,
        POST   => \&_update_resource,
    },
    '/resource'                     => { POST => \&_create_resource, },
    '/resource/(\d+)/bookings'      => { GET  => \&_list_bookings, },
    '/resource/(\d+)/bookings/ical' => { GET  => \&_list_bookings_ical, },
    '/resource/(\d+)/booking'       => { POST => \&_create_booking, },
    '/resource/(\d+)/tag'           => { POST => \&_create_tag, },
    '/resource/(\d+)/tags'          => { GET  => \&_list_tags, },
    '/resource/(\d+)/tag/([\w.:_\-]+)' => { DELETE => \&_delete_tag, },
    '/resource/(\d+)/booking/(\d+)'    => {
        GET    => \&_retrieve_booking,
        POST   => \&_update_booking,
        DELETE => \&_delete_booking,
    },
    '/resource/(\d+)/booking/(\d+)/ical' =>
        { GET => \&_retrieve_booking_ical },
    '/css/(\w+)\.css' => { GET => \&_send_css },
    '/dtd/(\w+)\.dtd' => { GET => \&_send_dtd },
    '/xsl/(\w+)\.xsl' => { GET => \&_send_xsl },
);

# Http request dispatcher. Sends every request to the corresponding
# handler according to hash %crud_for. The handler receives
# the CGI object and the list of parameters acording to the corresponding
# groups in the %crud_for regular expressions.
sub handle_request {
    my $self = shift;
    my $cgi  = shift;

    my $path_info = $cgi->path_info();
    my $method    = $cgi->request_method();

    # Find the corresponding action
    my $url_key = 'default_action';
    my @ids;

    foreach my $url_pattern ( keys(%crud_for) ) {

        # Anchor pattern and allow URLs ending in '/'
        my $pattern = '^' . $url_pattern . '/?$';
        if ( $path_info =~ m{$pattern} ) {
            @ids = ( $1, $2 );
            $url_key = $url_pattern;
            last;
        }
    }

    # Dispatch to the corresponding action.
    # Pass parameters obtained from the pattern to action
    if ( exists $crud_for{$url_key} ) {
        if ( exists $crud_for{$url_key}->{$method} ) {
            $crud_for{$url_key}->{$method}->( $cgi, $ids[0], $ids[1] );
        }
        else {

            # Requested HTTP method not available
            _status(405);
        }
    }
    else {

        # Requested URL not available
        _status(404);
    }
}

#############################################################
# Http tools
#############################################################

sub _reply {
    my ( $status, $type, @output ) = @_;

    $type = 'text/plain' unless defined $type and $type ne '';
    print "HTTP/1.0 $status\n", CGI->header($type), @output, "\n";
}

# Prints an Http response. Message is optional.
sub _status {
    my ( $code, $message ) = @_;

    my %codes = (
        200 => 'OK',
        201 => 'Created',
        400 => 'Bad Request',
        403 => 'Forbidden',
        404 => 'Not Found',
        405 => 'Method Not Allowed',
        409 => 'Conflict',
    );

    my $text = $codes{$code} or croak "Unknown HTTP code error";

    #
    # FIXME: Since we're returning XML most of the time,
    #        shouldn't we returning errors as XML too?
    #        (ticket:114)
    #
    _reply( "$code $codes{$code}", 'text/plain', $message || $text );
}

sub _send_xml {
    my ($xml) = @_;

    _reply( '200 OK', 'text/xml', $xml );
}

sub _send_ical {
    my ($ical) = @_;

    _reply( '200 OK', 'text/calendar', $ical );
}

##############################################################
# Handlers for resources
##############################################################

sub _list_resources {
    my $list = Smeagol::Resource::List->new();
    _send_xml( $list->to_xml( "/resources", 1 ) );
}

sub _create_resource {
    my ($cgi) = @_;

    my $r = Smeagol::Resource->from_xml( $cgi->param('POSTDATA') );

    if ( !defined $r ) {    # wrong XML argument
        _status(400);
    }
    else {
        $r->save();

        #
        # FIXME: We're returning XML as plaintext, wrong :/
        #        (ticket:90)
        #
        _status( 201, $r->to_xml( "", 1 ) );
    }
}

sub _retrieve_resource {
    my ( $cgi, $id ) = @_;

    if ( !defined $id ) {
        _status(400);
        return;
    }

    my $r = Smeagol::Resource->load($id);

    if ( !defined $r ) {
        _status(404);
    }
    else {
        _send_xml( $r->to_xml( "", 1 ) );
    }
}

sub _delete_resource {
    my ( $cgi, $id ) = @_;

    if ( !defined $id ) {
        _status(400);
        return;
    }

    my $r = Smeagol::Resource->load($id);

    if ( !defined $r ) {
        _status( 404, "Resource #$id does not exist" );
    }
    else {
        $r->remove();
        _status( 200, "Resource #$id deleted" );
    }
}

sub _update_resource {
    my ( $cgi, $id ) = @_;

    if ( !defined $id ) {
        _status(400);
        return;
    }

    my $updated_resource
        = Smeagol::Resource->from_xml( $cgi->param('POSTDATA'), $id );

    if ( !defined $updated_resource ) {
        _status(400);
    }
    elsif ( !defined Smeagol::Resource->load($id) ) {
        _status(404);
    }
    else {
        $updated_resource->save();
        _send_xml( $updated_resource->to_xml( "", 1 ) );
    }
}

##############################################################
# Handlers for DTD
##############################################################

sub _send_dtd {
    my ( $cgi, $id ) = @_;

    #
    # FIXME: make it work from anywhere, now it must run from
    #        the project base dir or won't find dtd dir
    #        (ticket:34)
    #
    if ( open my $dtd, "<", "dtd/$id.dtd" ) {

        # slurp dtd file
        local $/;
        _reply( '200 OK', 'text/sgml', <$dtd> );
    }
    else {
        _status(400);
    }
}

#
# FIXME: this call is made as _list_bookings($cgi, $1, $2, ...);
#        $2 is always undef since this regex captures 1 item only,
#        thus the undef on the args list below.
#        (ticket:115)
#
sub _list_bookings {
    my ( $cgi, $idResource, undef, $viewAs ) = @_;

    my $r = Smeagol::Resource->load($idResource);

    if ( !defined $r ) {
        _status(404);
        return;
    }

    if ( defined $viewAs && $viewAs eq 'ical' ) {
        my $ical = $r->agenda->ical;
        _send_ical("$ical");
    }
    else {
        my $xml = $r->agenda->to_xml( $r->url, 1 );
        _send_xml($xml);
    }
}

sub _list_bookings_ical {
    _list_bookings( @_, "ical" );
}

sub _create_booking {
    my ( $cgi, $idResource ) = @_;

    if ( !defined $idResource ) {
        _status(400);
        return;
    }

    my $r = Smeagol::Resource->load($idResource);
    if ( !defined $r ) {
        _status(404);
        return;
    }

    my $b = Smeagol::Booking->from_xml( $cgi->param('POSTDATA') );
    if ( !defined $b ) {
        _status(400);
        return;
    }

    my $ag = $r->agenda;

    if ( $ag->interlace($b) ) {
        my $overlapping_agenda = Smeagol::Agenda->new();
        my @overlapping = grep { $_->intersects($b) } $ag->elements;
        foreach my $aux (@overlapping) {
            $overlapping_agenda->append($aux);
        }

        #
        # FIXME: wrong again, returning XML as plaintext
        #        (ticket:90)
        #
        _status( 409, $overlapping_agenda->to_xml( $r->url, 1 ) );
        return;
    }

    $r->agenda->append($b);
    $r->save();
    _status( 201, $b->to_xml( $r->url, 1 ) );
}

sub _retrieve_booking {
    my ( $cgi, $idR, $idB, $viewAs ) = @_;

    if ( !defined $idR || !defined $idB ) {
        _status(400);
        return;
    }

    my $r = Smeagol::Resource->load($idR);
    if ( !defined $r ) {
        _status(404);
        return;
    }

    my $ag = $r->agenda;
    if ( !defined $ag ) {
        _status(404);
        return;
    }

    my $b = ( grep { $_->id eq $idB } $ag->elements )[0];
    if ( !defined $b ) {
        _status(404);
        return;
    }

    if ( defined $viewAs && $viewAs eq 'ical' ) {
        my $ics = $b->ical->calendar->as_string;
        _send_ical($ics);
    }
    else {
        _send_xml( $b->to_xml( $r->url, 1 ) );
    }
}

sub _retrieve_booking_ical {
    _retrieve_booking( @_, "ical" );
}

sub _delete_booking {
    my ( $cgi, $idR, $idB ) = @_;

    if ( !defined $idR || !defined $idB ) {
        _status(400);
        return;
    }

    my $r = Smeagol::Resource->load($idR);

    if ( !defined $r ) {
        _status(404);
        return;
    }

    my $ag = $r->agenda;
    if ( !defined $ag ) {
        _status(404);
        return;
    }

    my $b = ( grep { $_->id eq $idB } $ag->elements )[0];
    if ( !defined $b ) {
        _status(404);
        return;
    }

    $ag->remove($b);
    $r->save();
    _status( 200, "Booking #$idB deleted" );
}

# NOTE: No race conditions in _update_booking, because
#       we're using HTTP::Server::Simple which has no
#       concurrence management (requests are served
#       sequentially)
sub _update_booking {
    my ( $cgi, $idR, $idB ) = @_;

    if ( !defined $idR || !defined $idB ) {
        _status(400);
        return;
    }

    my $r = Smeagol::Resource->load($idR);
    if ( !defined $r ) {
        _status(404);
        return;
    }

    my $ag = $r->agenda;
    if ( !defined $ag ) {
        _status(404);
        return;
    }

    my $old_booking = ( grep { $_->id eq $idB } $ag->elements )[0];
    if ( !defined $old_booking ) {
        _status(404);
        return;
    }

    my $new_booking
        = Smeagol::Booking->from_xml( $cgi->param('POSTDATA'), $idB );

    if ( !defined $new_booking ) {
        _status(400);
        return;
    }

    #
    # Check wether updated booking would produce overlappings
    #
    $ag->remove($old_booking);

    if ( $ag->interlace($new_booking) ) {

        # if overlappings are produced, let's build a new agenda
        # containing affected bookings and return it to the client
        my @overlapping = grep { $_->intersects($new_booking) } $ag->elements;
        my $overlapping_agenda = Smeagol::Agenda->new();

        foreach my $aux (@overlapping) {
            $overlapping_agenda->append($aux);
        }
        $r->agenda($overlapping_agenda);

        #
        # FIXME: still wrong, returning XML as plaintext
        #        (ticket:90)
        #
        _status( 409, $overlapping_agenda->to_xml( $r->url, 1 ) );
        return;
    }

    $ag->append($new_booking);
    $r->agenda($ag);
    $r->save();

    _send_xml( $new_booking->to_xml( $r->url, 1 ) );
    return;
}

sub _create_tag {
    my ( $cgi, $idResource ) = @_;
    if ( !defined $idResource ) {
        _status(400);
        return;
    }

    my $r = Smeagol::Resource->load($idResource);
    if ( !defined $r ) {
        _status(404);
        return;
    }

    my $tg = Smeagol::Tag->from_xml( $cgi->param('POSTDATA') );
    if ( !defined $tg ) {
        _status(400);
        return;
    }

    $r->tags->append($tg);
    $r->save();
    _status( 201, $tg->toXML( $r->url, 1 ) );
}

sub _list_tags {
    my ( $cgi, $idResource ) = @_;
    my $r = Smeagol::Resource->load($idResource);

    if ( !defined $r ) {
        _status(404);
        return;
    }
    my $xml = $r->tags->to_xml( $r->url, 1 );
    _send_xml($xml);
}

sub _delete_tag {
    my ( $cgi, $idR, $idT ) = @_;

    if ( !defined $idR || !defined $idT ) {
        _status(400);
        return;
    }

    my $r = Smeagol::Resource->load($idR);

    if ( !defined $r ) {
        _status(404);
        return;
    }

    my $tgS = $r->tags;
    if ( !defined $tgS ) {
        _status(404);
        return;
    }

    my $tg = ( grep { $_->value eq $idT } $tgS->elements )[0];
    if ( !defined $tg ) {
        _status(404);
        return;
    }

    $tgS->remove($tg);
    $r->save();
    _status( 200, "Tag #$idT deleted" );
}
####################
# Handlers for CSS #
####################

# id should contain the CSS file name (without the ".css" extension)
sub _send_css {
    my ( $cgi, $id ) = @_;

    # FIXME: make it work from anywhere, now it must run from
    #        the project base dir or won't find dtd dir
    #        (ticket:116)
    if ( open my $css, "<", "css/$id.css" ) {

        # slurp css file
        local $/;
        _reply( '200 OK', 'text/css', <$css> );
    }
    else {
        _status(400);
    }
}

####################
# Handlers for XSL #
####################

# id should contain the XSL file name (without the ".xsl" extension)
sub _send_xsl {
    my ( $cgi, $id ) = @_;

    # FIXME: make it work from anywhere, now it must run from
    #        the project base dir or won't find dtd dir
    #        (ticket:116)
    if ( open my $xsl, "<", "xsl/$id.xsl" ) {

        # slurp css file
        local $/;
        _reply( '200 OK', 'application/xml', <$xsl> );
    }
    else {
        _status(400);
    }
}

1;
