# Resource class definition
package Smeagol::Resource;

use strict;
use warnings;

use XML::LibXML;
use Smeagol::DataStore;
use Carp;
use Smeagol::XML;
use Data::Dumper;

use overload q{""} => \&__str__;

# Create a new resource
sub new {
    my $class = shift;
    my ( $description, $agenda, $info, $tags ) = @_;

    # $agenda and $info arguments are not mandatory
    return if !defined $description;

    my $obj;

    # Load on runtime to get rid of cross-dependency between
    # both Resource and Agenda
    require Smeagol::Agenda;
    require Smeagol::TagSet;

    $obj = {
        id          => _next_id(),
        description => $description,
        agenda      => ( defined $agenda ) ? $agenda : Smeagol::Agenda->new(),
        info        => ( defined $info ) ? $info : "",
        tags        => ( defined $tags ) ? $tags : Smeagol::TagSet->new(),
        _persistent => 0,
    };

    bless $obj, $class;
    return $obj;
}

# Setters and getters
sub id {
    my $self = shift;

    if (@_) { $self->{id} = shift; }

    return $self->{id};
}

sub description {
    my $self = shift;

    if (@_) { $self->{description} = shift; }

    return $self->{description};
}

sub agenda {
    my $self = shift;

    if (@_) { $self->{agenda} = shift; }

    return $self->{agenda};
}

sub info {
    my $self = shift;

    if (@_) { $self->{info} = shift; }

    return $self->{info};
}

sub url {
    my $self = shift;

    return "/resource/" . $self->id;
}

sub tags {
    my $self = shift;
    if (@_) { $self->{tags} = shift; }

    return $self->{tags};
}

# Constructor that fetchs a resource from datastore
# or fail if it cannot be found
sub load {
    my $class = shift;
    my ($id) = @_;

    return if ( !defined($id) );

    my $data = Smeagol::DataStore->load($id);

    return if ( !defined($data) );

    my $resource = Smeagol::Resource->from_xml( $data, $id );

    return $resource;
}

# from_xml: creates a Resource via an XML string
# If $id is defined, it will be used as the Resource ID.
# Otherwise, a new ID will be generated by DataStore
sub from_xml {
    my $class = shift;
    my ( $xml, $id ) = @_;

    my $obj = {};

    # Load on runtime to get rid of cross-dependency between
    # both Resource and Agenda
    require Smeagol::Agenda;
    require Smeagol::TagSet;

    # validate XML string against the DTD
    my $dtd = XML::LibXML::Dtd->new( "CPL UPC//Resource DTD v0.03",
        "dtd/resource.dtd" );

    my $dom = eval { XML::LibXML->new->parse_string($xml) };

    if ( ( !defined $dom ) || !$dom->is_valid($dtd) ) {

        # validation failed
        return;
    }

    $obj = {
        id => ( ( defined $id ) ? $id : _next_id() ),
        description =>
            $dom->getElementsByTagName('description')->string_value,
        agenda      => Smeagol::Agenda->new(),
        info        => "",
        tags        => Smeagol::TagSet->new(),
        _persistent => 0,
    };

    if ( $dom->getElementsByTagName('agenda')->get_node(1) ) {
        $obj->{agenda} = Smeagol::Agenda->from_xml(
            $dom->getElementsByTagName('agenda')->get_node(1)->toString );
    }

    my $info = $dom->findnodes('//resource/info')->get_node(1)->string_value;

    #
    # FIXME: what if $info == 0 ?
    #        (un)definition should be checked using '(defined $info)'
    #        (ticket:113)
    #
    $obj->{info} = ($info) ? $info : "";

    if ( $dom->getElementsByTagName('tags')->get_node(1) ) {
        $obj->{tags} = Smeagol::TagSet->from_xml(
            $dom->getElementsByTagName('tags')->get_node(1)->toString );
    }

    bless $obj, $class;
    return $obj;
}

sub __str__ {
    my $self = shift;
    my ( $url, $isRootNode ) = @_;

    $url .= $self->url
        if defined $url;

    my $xmlText = "<resource>";
    $xmlText .= "<description>" . $self->{description} . "</description>";

    $xmlText .= $self->{agenda}->to_xml($url)
        if ( ( defined $self->{agenda} )
        && defined( $self->{agenda}->elements ) );

    $xmlText .= "<info>" . $self->{info} . "</info>";
    $xmlText .= $self->{tags}->to_xml($url)
        if ( ( defined $self->{tags} )
        && defined( $self->{tags}->elements ) );

    $xmlText .= "</resource>";

    return $xmlText
        unless defined $url && $url ne '';

    my $xmlDoc = eval { Smeagol::XML->new($xmlText) };
    croak $@ if $@;

    $xmlDoc->addXLink( "resource", $url );
    if ($isRootNode) {
        $xmlDoc->addPreamble("resource");
        return "$xmlDoc";
    }
    else {

        # Take the first node and skip processing instructions
        my $node = $xmlDoc->doc->getElementsByTagName("resource")->[0];
        return $node->toString;
    }
}

# DEPRECATED
sub to_xml {
    return shift->__str__(@_);
}

sub remove {
    my $self = shift;

    Smeagol::DataStore->remove( $self->{id} );
    $self->{_persistent} = 0;
}

# Save Resource in DataStore
sub save {
    my $self = shift;

    $self->{_persistent} = 1;
    Smeagol::DataStore->save( $self->{id}, $self->to_xml() );
}

sub DESTROY {
    my $self = shift;

    $self->save if ( $self->{_persistent} );
}

sub _next_id {
    return Smeagol::DataStore->next_id(__PACKAGE__);
}

1;
