package Server;

use strict;
use warnings;

use HTTP::Server::Simple::CGI;
use base qw(HTTP::Server::Simple::CGI);
use CGI qw();
use XML::LibXML;
use Carp;
use Data::Dumper;
use Resource;

my $XML_HEADER = '<?xml version="1.0" encoding="UTF-8"?>';

sub _xml_preamble {
    my $type = shift;    # resources, resource, agenda or booking
    return
          $XML_HEADER
        . '<?xml-stylesheet type="application/xml" href="/xsl/'
        . $type
        . '.xsl"?>';
}

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
    '/resource/(\d+)/booking'       => { POST => \&_create_booking, },
    '/resource/(\d+)/booking/(\d+)' => {
        GET    => \&_retrieve_booking,
        POST   => \&_update_booking,
        DELETE => \&_delete_booking,
    },
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

############################
# REST management routines #
############################

# Returns the REST URL which identifies a given resource
sub _rest_get_resource_url {
    my ($resource) = shift;

    return "/resource/" . $resource->id;
}

# Extracts the Resource ID from a given Resource REST URL
sub _rest_parse_resource_url {
    my ($url) = shift;

    if ( $url =~ /\/resource\/(\w+)/ ) {
        return $1;
    }
    else {
        return undef;
    }
}

# Returns the REST URL which identifies the agenda of a given resource
sub _rest_get_agenda_url {
    my ($resource) = shift;
    return _rest_get_resource_url($resource) . "/bookings";
}

# Returns the REST URL which identifies a booking of a given resource
sub _rest_get_booking_url {
    my $booking_id  = shift;
    my $resource_id = shift;

    return '/resource/' . $resource_id . '/booking/' . $booking_id;
}

# Returns XML representation of a given resource, including
# all REST decoration stuff (xlink resource locator)
sub _rest_resource_to_xml {
    my $resource     = shift;
    my $is_root_node = shift;

    $is_root_node = ( defined $is_root_node ) ? $is_root_node : 0;

    my $agenda_url = _rest_get_agenda_url($resource);

    my $parser = XML::LibXML->new();
    my $doc    = $parser->parse_string( $resource->to_xml() );

    # Add xlink decorations to <resource>, <agenda> and <booking> elements
    my @nodes = $doc->getElementsByTagName('resource');
    if ($is_root_node) {
        $nodes[0]->setNamespace( "http://www.w3.org/1999/xlink", "xlink", 0 );
    }
    $nodes[0]->setAttribute( "xlink:type", "simple" );
    $nodes[0]
        ->setAttribute( "xlink:href", _rest_get_resource_url($resource) );

    #
    # FIXME: The following loop should be rewritten using _rest_agenda_to_xml
    #
    for my $agenda_node ( $doc->getElementsByTagName('agenda') ) {
        $agenda_node->setAttribute( "xlink:type", 'simple' );
        $agenda_node->setAttribute( "xlink:href",
            _rest_get_agenda_url($resource) );
    }

    #
    # FIXME: The following loop should be rewritten using _rest_booking_to_xml
    #
    for my $booking_node ( $doc->getElementsByTagName('booking') ) {
        my $booking = Booking->from_xml(
            _rest_remove_xlink_attrs( $booking_node->toString() ) );
        $booking_node->setAttribute( "xlink:type", 'simple' );
        $booking_node->setAttribute( "xlink:href",
            _rest_get_booking_url( $booking->id, $resource->id ) );
    }

    my $xml = $doc->toString();

    # toString adds an XML preamble, not needed if
    # this is not a root node, so we remove it
    $xml =~ s/<\?xml version="1.0"\?>//;

    if ($is_root_node) {
        $xml = _xml_preamble('resource') . $xml;
    }
    return $xml;

}

sub _rest_remove_xlink_attrs {
    my $xml = shift;

    my $parser = XML::LibXML->new();
    my $doc    = $parser->parse_string($xml)
        or die "_rest_remove_xlink_attrs() received an invalid XML argument";

    my @tags = ( 'booking', 'agenda', 'resource' );

    for my $tag (@tags) {
        for my $node ( $doc->getElementsByTagName($tag) ) {
            $node->removeAttribute("xlink:href");
            $node->removeAttribute("xlink:type");
            $node->removeAttribute("xmlns:xlink");
        }
    }

    my $result = $doc->toString(0);

# removeAttribute() cannot remove namespace declarations (WTF!!!)
# ... and, if you are asking: *no*, removeAttributeNS() does not work, either!),
# so let's be expeditive:
    $result =~ s/ xmlns:xlink="[^"]*"//g;

    return $result;
}

sub _rest_agenda_to_xml {
    my $resource     = shift;
    my $is_root_node = shift;

    $is_root_node = ( defined $is_root_node ) ? $is_root_node : 0;

    my $parser = XML::LibXML->new();
    my $doc    = $parser->parse_string( $resource->agenda->to_xml() );
    my @nodes  = $doc->getElementsByTagName('agenda');
    if ($is_root_node) {
        $nodes[0]->setNamespace( "http://www.w3.org/1999/xlink", "xlink", 0 );
    }
    $nodes[0]->setAttribute( "xlink:type", 'simple' );
    $nodes[0]->setAttribute( "xlink:href", _rest_get_agenda_url($resource) );

    #
    # FIXME: The following loop should be rewritten using _rest_booking_to_xml
    #
    for my $booking_node ( $doc->getElementsByTagName('booking') ) {
        my $booking = Booking->from_xml(
            _rest_remove_xlink_attrs( $booking_node->toString() ) );
        $booking_node->setAttribute( "xlink:type", 'simple' );
        $booking_node->setAttribute( "xlink:href",
            _rest_get_booking_url( $booking->id, $resource->id ) );
    }

    my $xml = $doc->toString();

    # toString adds an XML preamble, not needed if
    # this is not a root node, so we remove it
    $xml =~ s/<\?xml version="1.0"\?>//;

    if ($is_root_node) {
        $xml = _xml_preamble('agenda') . $xml;
    }
    return $xml;
}

sub _rest_booking_to_xml {
    my ( $booking, $resource_id, $is_root_node ) = @_;

    $is_root_node = ( defined $is_root_node ) ? $is_root_node : 0;

    my $parser = XML::LibXML->new();
    my $doc    = $parser->parse_string( $booking->to_xml() );

    my @nodes = $doc->getElementsByTagName('booking');

    # Add XLink attributes
    if ($is_root_node) {
        $nodes[0]->setNamespace( "http://www.w3.org/1999/xlink", "xlink", 0 );
    }
    $nodes[0]->setAttribute( "xlink:type", 'simple' );
    $nodes[0]->setAttribute( "xlink:href",
        _rest_get_booking_url( $booking->id, $resource_id ) );

    my $xml = $doc->toString();

    # toString adds an XML preamble, not needed if
    # this is not a root node, so we remove it
    $xml =~ s/<\?xml version="1.0"\?>//;

    if ($is_root_node) {
        $xml = _xml_preamble('booking') . $xml;
    }
    return $xml;
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

    my $text = $codes{$code} || die "Unknown HTTP code error";
    _reply( "$code $codes{$code}", 'text/plain', $message || $text );
}

sub _send_xml {
    my $xml = shift;

    _reply( '200 OK', 'text/xml', $xml );
}

##############################################################
# Handlers for resources
##############################################################

sub _list_resources {
    my $xml = _xml_preamble('resources')
        . '<resources xmlns:xlink="http://www.w3.org/1999/xlink" xlink:type="simple" xlink:href="/resources">';
    foreach my $id ( Resource->list_id ) {
        my $r = Resource->load($id);
        if ( defined $r ) {
            $xml .= _rest_resource_to_xml( $r, 0 );
        }
    }
    $xml .= "</resources>";
    _send_xml($xml);
}

sub _create_resource {
    my $cgi = shift;

    my $r = Resource->from_xml(
        _rest_remove_xlink_attrs( $cgi->param('POSTDATA') ) );

    if ( !defined $r ) {    # wrong XML argument
        _status(400);
    }
    else {
        $r->save();
        _status( 201, _rest_resource_to_xml( $r, 1 ) );
    }
}

sub _retrieve_resource {
    my $cgi = shift;
    my $id  = shift;

    if ( !defined $id ) {
        _status(400);
        return;
    }

    my $r = Resource->load($id);

    if ( !defined $r ) {
        _status(404);
    }
    else {
        _send_xml( _rest_resource_to_xml( $r, 1 ) );
    }
}

sub _delete_resource {
    my $cgi = shift;
    my $id  = shift;

    if ( !defined $id ) {
        _status(400);
        return;
    }

    my $r = Resource->load($id);

    if ( !defined $r ) {
        _status( 404, "Resource #$id does not exist" );
    }
    else {
        $r->remove();
        _status( 200, "Resource #$id deleted" );
    }
}

sub _update_resource {
    my $cgi = shift;
    my $id  = shift;

    if ( !defined $id ) {
        _status(400);
        return;
    }

    my $updated_resource = Resource->from_xml(
        _rest_remove_xlink_attrs( $cgi->param('POSTDATA') ), $id );

    if ( !defined $updated_resource ) {
        _status(400);
    }
    elsif ( !defined Resource->load($id) ) {
        _status(404);
    }
    else {
        $updated_resource->save();
        _send_xml( _rest_resource_to_xml($updated_resource) );
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

sub _list_bookings {
    my $cgi = shift;
    my $id  = shift;    # Resource ID

    my $r = Resource->load($id);

    if ( !defined $r ) {
        _status(404);
        return;
    }

    my $xml = _rest_agenda_to_xml( $r, 1 );
    _send_xml($xml);

}

sub _create_booking {
    my $cgi = shift;
    my $id  = shift;

    if ( !defined $id ) {
        _status(400);
        return;
    }

    my $r = Resource->load($id);
    if ( !defined $r ) {
        _status(404);
        return;
    }

    my $b = Booking->from_xml(
        _rest_remove_xlink_attrs( $cgi->param('POSTDATA') ) );
    if ( !defined $b ) {
        _status(400);
        return;
    }

    if ( $r->agenda->interlace($b) ) {
        _status(409);
        return;
    }

    $r->agenda->append($b);
    $r->save();
    _status( 201, _rest_booking_to_xml( $b, $id, 1 ) );
}

sub _retrieve_booking {
    my $cgi = shift;
    my $idR = shift;
    my $idB = shift;

    if ( !defined $idR || !defined $idB ) {
        _status(400);
        return;
    }

    my $r = Resource->load($idR);
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

    _send_xml( _rest_booking_to_xml( $b, $idR, 1 ) );
}

sub _delete_booking {
    my $cgi = shift;
    my $idR = shift;
    my $idB = shift;

    if ( !defined $idR || !defined $idB ) {
        _status(400);
        return;
    }

    my $r = Resource->load($idR);

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

#
# NOTE: No race conditions in _update_bookings, because we're using HTTP::Server::Simple
#       which has no concurrence (requests are served sequentially)
#
sub _update_booking {
    my ( $cgi, $idR, $idB ) = @_;

    if ( !defined $idR || !defined $idB ) {
        _status(400);
        return;
    }

    my $r = Resource->load($idR);
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

    my $new_booking = Booking->from_xml(
        _rest_remove_xlink_attrs( $cgi->param('POSTDATA') ), $idB );

    if ( !defined $new_booking ) {
        _status(400);
        return;
    }

    #
    # Search if updated booking would overlap
    #
    $ag->remove($old_booking);

    my @overlapping = grep { $_->intersects($new_booking) } $ag->elements;
    if ( $#overlapping > 0 ) {

        my $overlapping_agenda = Agenda->new();
        for (@overlapping) {
            $overlapping_agenda->append($_);
        }

    # FIXME: _rest_agenda_to_xml should accept an 
    # agenda and a resource_id as parameters
    # so we should not need to perform the following hack
    #
    # REALLY UGLY HACK: create a dummy resource to build the agenda XML
        my $dummy_resource
            = Resource->new( 'dummy', 'dummy', $overlapping_agenda );
        $dummy_resource->id($idR);
        _status( 409, _rest_agenda_to_xml( $dummy_resource, 1 ) );
        return;
    }

    $ag->append($new_booking);
    $r->agenda($ag);

    $r->save();
    _send_xml( _rest_booking_to_xml( $new_booking, $idR, 1 ) );
    return;
}


####################
# Handlers for CSS #
####################

sub _send_css {
    my ( $cgi, $id )
        = @_
        ;  #id should contain the CSS file name (without the ".css" extension)

    #
    # FIXME: make it work from anywhere, now it must run from
    #        the project base dir or won't find dtd dir

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

sub _send_xsl {
    my ( $cgi, $id )
        = @_
        ;  #id should contain the XSL file name (without the ".xsl" extension)

    #
    # FIXME: make it work from anywhere, now it must run from
    #        the project base dir or won't find dtd dir

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
