package TestApp::Controller::Root;
use strict;
use warnings;

__PACKAGE__->config(namespace => q{});

use base 'Catalyst::Controller';

sub main :Path {
  my ( $self, $c ) = @_;
  $c->res->body('<h1>It works</h1>')
}

sub logging :Local {
  my ( $self, $c ) = @_;
  $c->log->debug("Log message with level debug");
  $c->log->info ("Log message with level info");
  $c->log->warn ("Log message with level warn");
  $c->log->error("Log message with level error");
  $c->log->fatal("Log message with level fatal");
  $c->res->body('<h1>It works</h1>')
}

1;
