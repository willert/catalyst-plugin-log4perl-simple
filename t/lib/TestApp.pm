package TestApp;
use strict;
use warnings;

use Catalyst qw/Log4perl::Simple/;

sub import {
  my $into = shift;
  __PACKAGE__->config( @_ );
  __PACKAGE__->setup;
};

1;
