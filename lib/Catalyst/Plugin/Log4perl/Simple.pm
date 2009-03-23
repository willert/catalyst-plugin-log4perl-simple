package Catalyst::Plugin::Log4perl::Simple;

=pod

=head1 NAME

Catalyst::Plugin::Log4perl::Simple - Logging and monitoring for Catalyst

=head1 SYNOPSIS

 package MyApp;

 # without any config, this will create a default
 # Catalyst::Log::Log4perl instance on setup
 use Catalyst (
   # your plug-ins here
   Log4perl::Extended
 );

 # you can just enable exception reporting like this:
 MyApp->config(
   log4perl => { error_logger => { recipient => 'me@example.com' }}
 );

 # ... or additionally chose another dispatcher
 MyApp->config(
   log4perl => {
     error_logger => {
       recipient => 'me@example.com',
       class     => 'Log::Dispatch::Email::MailSend',
     }
   }
 );


 # .. or use a full fledged Log4perl-style config:
 MyApp->config(
   log4perl => {
     root_logger => [qw/ INFO screen /],
     appender => {
       screen => {
         class  => 'Log::Log4perl::Appender::ScreenColoredLevels',
         layout => 'PatternLayout',
         'layout.ConversionPattern' =>  '[%p] %F:%L %n%m%n%n',
       }
     }
   }
 );


=head1 DESCRIPTION

B<Catalyst::Plugin::Log4perl::Simple> augments the standard
L<Catalyst::Log::Log4perl> logger with some useful functionality
that depends on mucking around with the dispatch cycle like redirecting
warning messages and flushing the logger when appropriate.

Additionally an error reporting facility is provided that is able
to provide a detailed contextual report (similar to the error page rendered
in debug mode) on errors via email or other logging facilities.

And as final sugarcoating, B<Catalyst::Plugin::Log4perl::Simple>
supports configuring Log4perl directly form your application config,
which also allows to e.g. better distinguish production and development
log settings.

=head1 METHODS

None, B<Catalyst::Plugin::Log4perl::Simple> does its job purely
with overriding Catalyst internals.

=cut

use strict;
use warnings;
use version;

use Carp;
use Scalar::Util qw/blessed/;
use Sub::Recursive;

use Data::Dumper;
use Encode;

use Data::Visitor::Callback;
use Catalyst::Log::Log4perl '1.0';
use MRO::Compat;

my %ignore_classes;
my @error_loggers;
my %email_appender;

=head1 CHANGES TO THE DISPATCH CYCLE

=head2 $self->setup

Builds a log4perl config hash out of your application config
initializes the logger and precomputes some internal data structures.

=cut

sub setup {
  my $self = shift;

  $self->next::method( @_ );

  my ( $error_logger, %log4perl_conf, %log4perl_args, %error_logger );

  my $conf = exists $self->config->{log4perl} ?
    $self->config->{log4perl} : undef;

  if ( ref $conf eq 'HASH' ) {
    $error_logger  =    delete $conf->{error_logger} || undef;
    %log4perl_args = %{ delete $conf->{options}      || {}    };
    my $visit = recursive {
      my ( $base, $path ) = @_;
      if ( ref $_[0] eq 'HASH' ) {
        for my $key ( keys %{ $_[0] } ) {
          $REC->( $_[0]->{ $key }, join( '.', $path, $key ) );
        }
      } elsif ( ref $_[0] eq 'ARRAY' ) {
        $REC->( join( ', ', @{ $_[0] } ), $path );
      } else {
        $path =~ s/appender\.(.+)\.class/appender.${1}/;
        $path =~ s/threshold$/Threshold/;
        $path =~ s/\.pattern$/.ConversionPattern/;
        $path =~ s/root_logger$/rootLogger/;
        $log4perl_conf{ $path } = $_[0];
      }
    };
    $visit->( $conf, 'log4perl' );
  }

  my $find_logger_conf = sub{
    my @default_paths = grep{ defined and not ref }
      ( $conf, qw/log4perl_local.conf log4perl.conf/ );
    my ( $conf ) = grep{ -r $self->path_to( $_ )->stringify } @default_paths;
    return $conf;
  };

  my %default_appender;
  my $default_log_level  = $self->debug ? 'DEBUG' : 'WARN';
  {
    my $class  = -t STDERR ? 'ScreenColoredLevels' : 'Screen';
    my $prefix = 'log4perl.appender';
    my $app    = \ %default_appender;
    $app->{"log4perl.rootLogger"} = "${default_log_level}, DefaultAppender";
    $app->{"${prefix}.DefaultAppender"} = 'Log::Log4perl::Appender::Screen';
    $app->{"${prefix}.DefaultAppender.layout"}= 'PatternLayout';
    $app->{"${prefix}.DefaultAppender.layout.ConversionPattern"} =
      '[%p] %c %d %F:%L %n%m%n';
  }

  %log4perl_conf = %default_appender
    unless %log4perl_conf or $find_logger_conf->();

  my @config_errors;

  if ( $error_logger ) {
    my $appender = ref $error_logger eq 'HASH' ?
      delete $error_logger->{appender} || 'auto' : $error_logger;

    if ( $appender eq 'off' ) {

      $self->log->info( "Turning off extended error logging" );

    } elsif ( $appender eq 'auto' ) {

      my $name = 'CatalystAutomaticErrorAppender';
      $log4perl_conf{"log4perl.appender.${name}"} =
        delete $error_logger->{class} || 'Log::Dispatch::Email::MailSend';
      $log4perl_conf{"log4perl.appender.${name}.to"} =
        delete $error_logger->{recipient}
          or die "Recipient needed for appender";
      $log4perl_conf{"log4perl.appender.${name}.Threshold"} =
        delete $error_logger->{threshold} || 'ERROR';
      $log4perl_conf{"log4perl.appender.${name}.subject"} =
        delete $error_logger->{subject} ||
          sprintf( '[%s] Internal server error', $self->config->{name} );
      $log4perl_conf{"log4perl.appender.${name}.layout"} =
        delete $error_logger->{layout} || 'PatternLayout';
      $log4perl_conf{"log4perl.appender.${name}.layout.ConversionPattern"} =
        delete $error_logger->{pattern} || '[%p] %F:%L %n%m%n%n';
      push @config_errors, "Unknown keys in error_logger configuration:" .
        join( ', ', keys %{ $error_logger } );

      # append the automatically configured append to the root logger
      $log4perl_conf{"log4perl.rootLogger"} = join(
        ', ', $log4perl_conf{"log4perl.rootLogger"} || 'ERROR', $name
      );
      @error_loggers = ( $name );
    } else {
      @error_loggers = ( split /,\s?/, $appender );
    }

    $self->log->warn(
      "Unknown/invalid error_logger keys:",
      Dumper( keys %{ $error_logger } )
    ) if ref $error_logger and %{ $error_logger };
  }

  my $catalyst_logger = do{
    if ( %log4perl_conf ) {
      Catalyst::Log::Log4perl->new( \%log4perl_conf, %log4perl_args );
    } else {
      my $config_path = $find_logger_conf->();
      $self->log->info( "Falling back to property file ${config_path}" );
      Catalyst::Log::Log4perl->new( $config_path, watch_delay => 30 );
    }
  };

  $self->log( $catalyst_logger );

  for my $logger ( @error_loggers ) {
    my $l4p_appender = Log::Log4perl->appenders->{ $logger };
    my $appender = eval{ $l4p_appender->{appender} }
      or die "Can't find $logger in ". Dumper( Log::Log4perl->appenders );
    next unless blessed $appender and $appender->isa('Log::Dispatch::Email');
    $email_appender{ $logger } = $appender;
  }

}


=head2 $self->dispatch

Redirects warnings to the current L<Catalyst::Log> instance
through a localized warning handler. If this fails, the warnings
are emitted normally.

=cut

sub dispatch {
  my $self = shift;

  local $SIG{__WARN__} = sub{
    local $@;
    eval{ $self->log->warn( @_ ) };
    warn $@ if $@;
  };

  $self->next::method( @_ );
}


=head2 $self->finalize

Flushes all appender instances that are L<Log::Dispatch::Email>
subclasses so we get one email per request (this can a a whole lot
so make sure your logging threshold is set high enough)

=cut

sub finalize {
  my $self = shift;

  #$self->log->warn('Flushing logger');
  $self->log->_flush unless $self->log->{abort};

  # propagate global flush to appenders that suppert this method (e.g. to send
  # a buffered log message collection as email) after everyone else finalized
  my $flush_loggers = !@error_loggers ? undef : Scope::Guard->new(
    sub{
      return if $self->debug;

      for my $logger ( values %email_appender ) {
        local $SIG{CHLD} = 'DEFAULT';
        $logger->flush;
      }
    }
  );
  $self->next::method( @_ );
}

sub finalize_error {
  my $self = shift;

  my $conf = $self->config;

  goto FINALIZE_OTHERS if $self->debug;

  if ( ref $conf->{debug} eq 'HASH' ) {
    $conf->{Log4perl}{ignore_classes} = $conf->{debug}{ignore_classes};
    $conf->{Log4perl}{scrubber_func}  = $conf->{debug}{scrubber_func};
  }

  $conf->{Log4perl}{ignore_classes} ||= [
    'DBIx::Class::ResultSource::Table',
    'DBIx::Class::ResultSourceHandle',
    'DateTime',
  ];

  $conf->{Log4perl}{scrubber_func} ||= sub{ $_ = "[stringified to: ${_}]" };

  if ( not keys %ignore_classes ) {
    # once
    foreach my $scrubbed_class (@{$conf->{Log4perl}{ignore_classes}}) {
      $ignore_classes{$scrubbed_class} = $conf->{Log4perl}{scrubber_func};
    }
  }

  my $scrubber = Data::Visitor::Callback->new(
    "ignore_return_values" => 1,
    "object"               => "visit_ref",
    plain_value            => sub{ eval{ $_ = encode( 'iso-8859-1', $_ ) }},
    %ignore_classes,
  );

  my $build_headline =  sub{ sprintf(
    "%s\n%s\n%s\n\n", '-' x length($_[0]), $_[0], '-' x length($_[0])
  )};

  my $dump = $build_headline->(
    'Dumping relevant request context and environment variables'
  );

  for my $info ( $self->dump_these ) {
    my $name  = $info->[0];
    my %values = %{ $info->[1] || {} };
    next unless %values;

    # Don't show context, body parser, response header in the dump
    delete @values{qw/ _context _body _finalized_headers/};

    # scrub long (and uniformative) values
    $scrubber->visit( \%values );

    {
      local $Data::Dumper::Indent   = 1;
      local $Data::Dumper::Purity   = 0;
      local $Data::Dumper::Useqq    = 1;
      local $Data::Dumper::Terse    = 1;
      local $Data::Dumper::Sortkeys = 1;
      $dump .= sprintf( "Catalyst %s: %s", lc($name), Dumper( \%values ));
    }
  }


  my $send_report_message = sub{
    for my $logger ( @error_loggers ) {
      if ( exists $email_appender{ $logger } ) {
        $email_appender{ $logger }->log_message( message => $_[0] );
      } else {
        eval{
          Log::Log4perl->appender_by_name( $logger )->log(
            message     => $_[0],
            log4p_level => 'ERROR',
          )};
        if ( my $err = $@ ) {
          $self->log->error( "Failed create error report: $@" );
        }
      }
    }
  };

  $send_report_message->( $build_headline->(
    'An error occured while processing: '. $self->action->reverse
  ));

  $self->log->_flush unless $self->log->{abort};

  $send_report_message->( $dump );

 FINALIZE_OTHERS:
  $self->next::method( @_ );
}


1;

__END__

=head1 CONFIGURATION FORMAT

B<Catalyst::Plugin::Log4perl::Simple> tries to emulate the property format
of L<Log::Log4perl> as close as possible while using config hashes.
Basically, B<Catalyst::Plugin::Log4perl::Simple> just joins the path
to a hash value while leaving out keys named C<'class'> in the appender
section. This means you could either write:

  $config->{log4perl}{appender}{example} = {
    class  => 'Log::Log4perl::Appender::Screen',
    layout => 'Log::Log4perl::Layout::SimpleLayout',
  };

or:

  $config->{log4perl}{appender} = {
    'example'        => 'Log::Log4perl::Appender::Screen',
    'example.layout' => 'Log::Log4perl::Layout::SimpleLayout',
  };

to build this L<Log::Log4perl::Config> file:

 log4perl.appender.example=Log::Log4perl::Appender::Screen
 log4perl.appender.example.layout=Log::Log4perl::Layout::SimpleLayout


Additionally, every key-value-pair under the root key C<options>
will be passed on to L<Catalyst::Log::Log4perl>'s C<new()> method
and everything under C<error_logger> is used to configure the
error reporting facility (see below).

=head1 CONFIGURING THE ERROR REPORTER

When C<$c->config->{log4perl}{error_logger}> is set to some other
value then C<'off'>, B<Catalyst::Plugin::Log4perl::Simple> assumes
it should created detailed error reports.

When C<error_logger> is a string, B<Catalyst::Plugin::Log4perl::Simple>
tries to log directly to the appender with this name. When C<error_logger>
evaluates to a hash reference, a default L<Log::Dispatch::Email::MailSend>
appender is created.

When using the second approach, you need to at least set C<recipient>
in C<error_logger> to specify where the error report should be send.
Further options are: C<subject>, C<class>, C<threshold>, C<layout>,
C<pattern> where class specifies an alternative default appender
and pattern an L<Log::Log4perl::Layout::PatternLayout> spec.

=head1 BUGS

Plenty, I guess. This is a pre-release version of
B<Catalyst::Plugin::Log4perl::Simple> and hasn't seen wide-spread
testing.

=head1 SOURCE AVAILABILITY

This code is in Github:

 git://github.com/willert/catalyst-plugin-log4perl-simple.git

=head1 SEE ALSO

L<http://github.com/willert/catalyst-plugin-log4perl-simple/>,
L<Catalyst::Log>, L<Catalyst::Log::Log4perl>, L<Log::Log4perl>,
L<Log::Dispatch::Email>, L<Log::Dispatch::Email::MailSend>,

=head1 AUTHOR

Sebastian Willert, C<willert@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright 2009 by Sebastian Willert E<lt>willert@cpan.orgE<gt>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
