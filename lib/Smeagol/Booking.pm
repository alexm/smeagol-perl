package Smeagol::Booking;

use strict;
use warnings;

use DateTime::Span ();
use XML::Simple;
use XML::LibXML;
use Carp;
use Smeagol::XML;
use Smeagol::DataStore;
use base qw(DateTime::SpanSet);

use overload
    q{""} => \&toString,
    q{==} => \&isEqual,
    q{eq} => \&isEqual,
    q{!=} => \&isNotEqual,
    q{ne} => \&isNotEqual;

sub new {
    my $class = shift;
    my ( $description, $from, $to, $info ) = @_;

    return if ( !defined($description) || !defined($from) || !defined($to) );

    my $span = DateTime::Span->from_datetimes(
        start => $from,
        end   => $to,
    );
    my $obj = $class->SUPER::from_spans( spans => [$span], );

    $obj->{ __PACKAGE__ . "::description" } = $description;
    $obj->{ __PACKAGE__ . "::id" }
        = Smeagol::DataStore->getNextID(__PACKAGE__);
    $obj->{ __PACKAGE__ . "::info" } = defined($info) ? $info : '';

    bless $obj, $class;
    return $obj;
}

sub id {
    my $self = shift;

    my $field = __PACKAGE__ . "::id";
    if (@_) { $self->{$field} = shift; }

    return $self->{$field};
}

sub description {
    my $self = shift;

    my $field = __PACKAGE__ . "::description";
    if (@_) { $self->{$field} = shift; }

    return $self->{$field};
}

sub info {
    my $self = shift;

    my $field = __PACKAGE__ . "::info";
    if (@_) { $self->{$field} = shift; }

    return $self->{$field};
}

sub url {
    my $self = shift;

    return "/booking/" . $self->id;
}

sub isEqual {
    my $self = shift;
    my ($booking) = @_;

    croak "invalid reference"
        unless ref($booking) eq __PACKAGE__;

    return
           $self->description eq $booking->description
        && $self->contains($booking)
        && $booking->contains($self)
        && $self->info eq $booking->info;
}

sub isNotEqual {
    return !shift->isEqual(@_);
}

# Returns an XML::LibXML::Document representing the Booking
sub toDOM {
    my $self = shift;

    my $from = $self->span->start;
    my $to   = $self->span->end;

    # build XML document
    my $dom = XML::LibXML::Document->new('1.0','UTF-8');
    my $bookingNode = $dom->createElement('booking');
    $dom->setDocumentElement($bookingNode);

    # FIXME: refactor this into Smeagol::XML->dateTimeNode('from', $from);
    my $fromNode = $dom->createElement('from');
    $fromNode->appendTextChild('year', $from->year);
    $fromNode->appendTextChild('month', $from->month);
    $fromNode->appendTextChild('day', $from->day);
    $fromNode->appendTextChild('hour', $from->hour);
    $fromNode->appendTextChild('minute', $from->minute);
    $fromNode->appendTextChild('second', $from->second);

    # FIXME: refactor this into Smeagol::XML->dateTimeNode('to', $to);
    my $toNode = $dom->createElement('to');
    $toNode->appendTextChild('year', $to->year);
    $toNode->appendTextChild('month', $to->month);
    $toNode->appendTextChild('day', $to->day);
    $toNode->appendTextChild('hour', $to->hour);
    $toNode->appendTextChild('minute', $to->minute);
    $toNode->appendTextChild('second', $to->second);

    $bookingNode->appendTextChild('id', $self->id);
    $bookingNode->appendTextChild('description', $self->description);
    $bookingNode->appendChild($fromNode);
    $bookingNode->appendChild($toNode);
    $bookingNode->appendTextChild('info', $self->info);

    return $dom;
}

sub toString {
    my $self = shift;
    my ($url, $isRootNode) = @_;

    my $dom = $self->toDOM;

    return $dom->toString unless defined $url;

    my $xmlDoc = eval { Smeagol::XML->new($dom->toString) };
    croak $@ if $@;

    $xmlDoc->addXLink( "booking", $url . $self->url );

    if ($isRootNode) {
        $xmlDoc->addPreamble("booking");
        return "$xmlDoc";
    }
    else {
        # Take the first node and skip processing instructions
        my $node = $xmlDoc->doc->getElementsByTagName("booking")->[0];
        return $node->toString;
    }
}

# DEPRECATED
sub toXML {
    return shift->toString(@_);
}

sub newFromXML {
    my $class = shift;
    my ( $xml, $id ) = @_;

    # validate XML string against the DTD
    my $dtd = XML::LibXML::Dtd->new( "CPL UPC//Booking DTD v0.03",
        "dtd/booking.dtd" );

    my $doc = eval { XML::LibXML->new->parse_string($xml) };
    croak $@ if $@;

    if ( ( !defined $doc ) || !$doc->is_valid($dtd) ) {

        # Validation failed
        return;
    }

    # XML is valid. Build empty elements as ''
    my $xmlTree = XMLin( $xml, SuppressEmpty => '' );

    my $span = DateTime::Span->from_datetimes(
        start => DateTime->new(
            year   => $xmlTree->{from}->{year},
            month  => $xmlTree->{from}->{month},
            day    => $xmlTree->{from}->{day},
            hour   => $xmlTree->{from}->{hour},
            minute => $xmlTree->{from}->{minute},
            second => $xmlTree->{from}->{second}
        ),
        end => DateTime->new(
            year   => $xmlTree->{to}->{year},
            month  => $xmlTree->{to}->{month},
            day    => $xmlTree->{to}->{day},
            hour   => $xmlTree->{to}->{hour},
            minute => $xmlTree->{to}->{minute},
            second => $xmlTree->{to}->{second}
        )
    );

    my $obj = $class->SUPER::from_spans( spans => [$span], );

    $obj->{ __PACKAGE__ . "::id" }
        = ( defined $xmlTree->{id} ) ? $xmlTree->{id}
        : ( defined $id ) ? $id
        :                   Smeagol::DataStore->getNextID(__PACKAGE__);

    $obj->{ __PACKAGE__ . "::description" } = $xmlTree->{description};
    $obj->{ __PACKAGE__ . "::info" }
        = defined( $xmlTree->{info} ) ? $xmlTree->{info} : '';

    bless $obj, $class;
    return $obj;
}

sub ical {
    my $self = shift;

    my $class = __PACKAGE__ . "::ICal";

    eval "require $class";
    return bless $self, $class;
}

1;
