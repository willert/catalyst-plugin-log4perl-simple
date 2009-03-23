use inc::Module::Install;

name 'Catalyst-Plugin-Log4perl-Simple';
all_from 'lib/Catalyst/Plugin/Log4perl/Simple.pm';

build_requires 'Catalyst::Runtime';
build_requires 'Test::WWW::Mechanize::Catalyst';
build_requires 'Test::More';
build_requires 'ok';

WriteAll();
