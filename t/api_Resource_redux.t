#!perl

use strict;
use warnings;

BEGIN {
    require 't/TestingDB.pl';
}

use V2::Test::Resource;
use Test::More;
use utf8::all;

my $r = V2::Test::Resource->new( uri => '/resource' );

my @resources = $r->GET();

is_deeply( \@resources, [], 'get empty list of resources' );

my %res1 = (
    description => 'resource1',
    info        => 'info1',
);

my $id  = $r->POST([ %res1 ]);
my $out = $r->GET($id);

is_deeply( $out, { %res1, id => $id }, "create res1" );

@resources = $r->GET();

is_deeply( \@resources, [ $id ], 'list of 1 resource' );

$res1{'description'} = 'edited';
$r->PUT( $id, [ %res1 ] );

@resources = $r->GET();

is_deeply( \@resources, [ $id ], 'still list of 1 resource' );

$out = $r->GET($id);

is_deeply( $out, { %res1, id => $id }, "edit res1" );

$r->DELETE($id);

@resources = $r->GET();

is_deeply( \@resources, [], 'delete gets empty list back' );

done_testing();
