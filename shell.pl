#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;

use Carp;
use Smeagol::Shell;


my $shell = Smeagol::Shell->new;
$shell->cmdloop;

