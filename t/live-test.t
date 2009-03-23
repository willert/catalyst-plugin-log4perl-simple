#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 3;

# setup library path
use FindBin;
use lib "$FindBin::Bin/lib";

# make sure testapp works
use ok 'TestApp';

# a live test against TestApp, the test application
use Test::WWW::Mechanize::Catalyst 'TestApp';

# suppress warnings from next that seem to occure between compile and run-time
BEGIN{ $SIG{__WARN__} = sub{} }; $SIG{__WARN__} = undef;

my $mech = Test::WWW::Mechanize::Catalyst->new;
$mech->get_ok('http://localhost/', 'get main page');
$mech->content_like(qr/it works/i, 'see if it has our text');

