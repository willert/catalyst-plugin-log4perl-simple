package TestApp;
use strict;
use warnings;

use Catalyst qw/Log4perl::Simple/;

__PACKAGE__->config( name => 'TestApp', log4perl => $ENV{TEST_LOG4PERL} );
__PACKAGE__->setup;

1;
