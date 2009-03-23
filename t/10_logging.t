use strict;
use warnings;

use Test::More;

BEGIN {
  eval "use Test::Log4perl;";
  if ($@) {
    plan skip_all => 'Test::Log4perl required for testing logging'; } else {
    plan tests => 2;
  }
}

BEGIN {
  $ENV{TEST_LOG4PERL} = {
    root_logger => [qw/ DEBUG TestLogger /],
    options => { autoflush => 1 },
    appender => {
      TestLogger => {
        class  => 'Log::Log4perl::Appender::Screen',
        layout => {
          class => 'Log::Log4perl::Layout::PatternLayout',
          pattern => '[%p] %c %m%n',
        }
      }
    }
  };
}

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::WWW::Mechanize::Catalyst 'TestApp';

# suppress warnings from next that seem to occure between compile and run-time
BEGIN{ $SIG{__WARN__} = sub{} }; $SIG{__WARN__} = undef;


my $mech = Test::WWW::Mechanize::Catalyst->new();
my $tlogger = Test::Log4perl->get_logger("TestApp.Controller.Root");

# prefetching the logger seems to be needed to ensure that
# Test::Log4perl works correctly
Log::Log4perl->get_logger('TestApp.Controller.Root');

Test::Log4perl->start();
$tlogger->debug("Log message with level debug");
$tlogger->info ("Log message with level info");
$tlogger->warn ("Log message with level warn");
$tlogger->error("Log message with level error");
$tlogger->fatal("Log message with level fatal");
$mech->get_ok('http://localhost:3000/logging');
Test::Log4perl->end('Got all log messages');
