use inc::Module::Install;

name 'Catalyst-Plugin-Log4perl-Simple';
all_from 'lib/Catalyst/Plugin/Log4perl/Simple.pm';

requires 'Catalyst::Runtime';
requires 'Catalyst::Log::Log4perl';
requires 'Scope::Guard';

build_requires 'Test::WWW::Mechanize::Catalyst';
build_requires 'Test::More';
build_requires 'Test::Log4perl';

build_requires 'ok';

WriteAll();
