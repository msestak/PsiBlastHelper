requires 'perl', '5.010';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

requires 'strict';
requires 'warnings';
requires 'Exporter';
requires 'Carp';
requires 'Data::Dumper';
requires 'Path::Tiny';
requires 'Getopt::Long';
requires 'Pod::Usage';
requires 'Log::Log4perl';
requires 'File::Spec::Functions';
requires 'Config::Std';

