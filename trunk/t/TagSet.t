#!/usr/bin/perl
use Test::More tests => 67;

use strict;
use warnings;

use XML::Simple;
use Data::Compare;

BEGIN {
    use_ok($_) for qw(
        Smeagol::Tag
        Smeagol::TagSet
        Smeagol::DataStore
    );

    Smeagol::DataStore::init();
}
use Data::Dumper;

my $tgS;
my ( $tg1, $tg2, $tg3, $tg4, $tg5, $tg11, $tg44 );
my ( $xmlTg1, $xmlTg5, $xmlTgS );

$tg1 = Smeagol::Tag->new("aula");
ok( defined $tg1, 'tag created' );
ok( $tg1->value eq "aula", 'tag checked' );

$tg2 = Smeagol::Tag->new("campus:nord");
ok( defined $tg2, 'tag created' );
ok( $tg2->value eq "campus:nord", 'tag checked' );

$tg3 = Smeagol::Tag->new("S-345");
ok( defined $tg3, 'tag created' );
ok( $tg3->value eq "S-345", 'tag checked' );

$tg4 = Smeagol::Tag->new("projeeector");
ok( defined $tg4, 'tag created' );
ok( $tg4->value eq "projeeector", 'tag checked' );

$tg5 = Smeagol::Tag->new("projector");
ok( defined $tg5, 'tag created' );
ok( $tg5->value eq "projector", 'tag checked' );

$tg11 = Smeagol::Tag->new("aula");
ok( defined $tg11, 'tag created' );
ok( $tg11->value eq "aula", 'tag checked' );

$tg44 = Smeagol::Tag->new("projeeector");
ok( defined $tg44, 'tag created' );
ok( $tg44->value eq "projeeector", 'tag checked' );

#create tagSet
{
    $tgS = Smeagol::TagSet->new();
    ok( defined $tgS, 'tagSet created' );
}

#appending and removing tags
{

    $tgS = Smeagol::TagSet->new();
    ok( defined $tgS, 'tagSet created' );

    ok( $tgS->size == 0, 'tgS contains 0 tags' );

    ok( !$tgS->contains($tg1), 'tg1 not in tgS' );
    $tgS->append($tg1);
    ok( $tgS->contains($tg1), 'tg1 in tgS' );

    ok( !$tgS->contains($tg2), 'tg2 not in tgS' );
    $tgS->append($tg2);
    ok( $tgS->contains($tg2), 'tg2 in tgS' );

    ok( $tgS->size == 2, 'tgS contains 2 tags' );

    ok( !$tgS->contains($tg3), 'tg3 not in tgS' );
    $tgS->append($tg3);
    ok( $tgS->contains($tg3), 'tg3 in tgS' );

    ok( !$tgS->contains($tg4), 'tg4 not in tgS' );
    $tgS->append($tg4);
    ok( $tgS->contains($tg4), 'tg4 in tgS' );

    ok( !$tgS->contains($tg5), 'tg5 not in tgS' );
    $tgS->append($tg5);
    ok( $tgS->contains($tg5), 'tg5 in tgS' );

    ok( $tgS->size == 5, 'tgS contains 5 tags' );

    $tgS->remove($tg4);
    ok( !$tgS->contains($tg4), 'tg4 not in tgS' );

    $tgS->remove($tg1);
    ok( !$tgS->contains($tg1), 'tg1 not in tgS' );
    ok( $tgS->size == 3,       'tgS contains 3 tags' );
}

#adding duplicated tags, not posible
{
    $tgS = Smeagol::TagSet->new();
    ok( defined $tgS, 'tagSet created' );

    ok( $tgS->size == 0, 'tgS contains 0 tags' );

    ok( !$tgS->contains($tg1), 'tg1 not in tgS' );
    $tgS->append($tg1);
    ok( $tgS->contains($tg1), 'tg1 in tgS' );

    ok( !$tgS->contains($tg11), 'tg11 not in tgS' );
    $tgS->append($tg11);
    ok( !$tgS->contains($tg11), 'tg11 not in tgS, tag duplicatted' );

    ok( !$tgS->contains($tg44), 'tg44 not in tgS' );
    $tgS->append($tg44);
    ok( $tgS->contains($tg44), 'tg44 in tgS' );

    ok( !$tgS->contains($tg4), 'tg4 not in tgS' );
    $tgS->append($tg4);
    ok( !$tgS->contains($tg4), 'tg4 not in tgS, tag duplicatted' );

}

#toXML
{
    $tgS = Smeagol::TagSet->new();
    ok( defined $tgS, 'tagSet created' );

    ok( $tgS->size == 0, 'tgS contains 0 tags' );

    ok( !$tgS->contains($tg1), 'tg1 not in tgS' );
    $tgS->append($tg1);
    ok( $tgS->contains($tg1), 'tg1 in tgS' );

    ok( $tgS->size == 1, 'tgS contains 1 tags' );

    $xmlTgS = $tgS->toString;
    ok( defined $xmlTgS, 'toXML ok' );
    ok( Compare( XMLin("<tags><tag>aula</tag></tags>"), XMLin($xmlTgS) ),
        'toXML checked' );

    ok( !$tgS->contains($tg5), 'tg5 not in tgS' );
    $tgS->append($tg5);
    ok( $tgS->contains($tg5), 'tg5 in tgS' );

    ok( $tgS->size == 2, 'tgS contains 2 tags' );

    $xmlTgS = $tgS->toXML();
    ok( defined $xmlTgS, 'toXML ok' );
    ok( $xmlTgS        =~ /<tag>aula<\/tag>/
            && $xmlTgS =~ /<tag>projector<\/tag>/
            && $xmlTgS =~ /<tags>/
            && $xmlTgS =~ /<\/tags>$/,
        'toXML checked'
    );

    $tgS->remove($tg1);
    ok( !$tgS->contains($tg1), 'tg1 not in tgS' );

    $xmlTgS = $tgS->toXML();
    ok( defined $xmlTgS, 'toXML ok' );
    is_deeply(
        XMLin($xmlTgS),
        XMLin('<tags><tag>projector</tag></tags>'),
        'toXML checked'
    );
}

#newFromXML
{
    my $ts = Smeagol::TagSet->new();
    $ts->append($tg1);

    my $got = Smeagol::TagSet->newFromXML( $ts->toXML );
    isa_ok( $got, 'Smeagol::TagSet' );
    ok( $got->size == 1, 'tgS contains 1 tag' );
    ok( $got->elements->value eq $tg1->value, 'tag checked' );

    $ts->append($tg5);

    $got = Smeagol::TagSet->newFromXML( $ts->toXML );
    isa_ok( $got, 'Smeagol::TagSet' );
    ok( $got->size == 2, 'tgS contains 2 tag' );

    my $xml = $got->toXML;
    ok( defined $xml, 'toXML ok' );
    ok( $xml        =~ /<tag>aula<\/tag>/
            && $xml =~ /<tag>projector<\/tag>/
            && $xml =~ /<tags>/
            && $xml =~ /<\/tags>$/,
        'toXML checked'
    );
}

END { Smeagol::DataStore->clean() }
