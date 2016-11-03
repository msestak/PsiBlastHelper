#!/usr/bin/env perl
package PsiBlastHelper;
use 5.010;
use strict;
use warnings;
no warnings 'experimental::smartmatch';
use Exporter qw/import/;
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;
use File::Spec::Functions qw/:ALL/;
use Path::Tiny;
use Log::Log4perl;
use Config::Std { def_sep => '=' };   #MySQL uses =

our $VERSION = "0.01";

our @EXPORT_OK = qw{
  main
  init_logging
  get_parameters_from_cmd
  write_chunks
  sge_plus_combined
  condor_plus_combined
  condor_plus_combined_sh

};

# start of MODULINO - works with debugger too
run() if !caller() or (caller)[0] eq 'DB';

### INTERFACE SUB starting all others ###
# Usage      : main();
# Purpose    : it starts all other subs and entire modulino
# Returns    : nothing
# Parameters : none (argument handling by Getopt::Long)
# Throws     : lots of exceptions from logging
# Comments   : start of entire module
# See Also   : n/a
sub run {
    exit 'main() does not need parameters' unless @_ == 0;

    # first capture parameters to enable verbose flag for logging
    my ($param_href) = get_parameters_from_cmd();

    # preparation of parameters
    my $verbose = $param_href->{verbose};
    my $quiet   = $param_href->{quiet};

    # start logging for the rest of program (without capturing of parameters)
    init_logging( $verbose, $param_href->{argv} );
    ##########################
    # ... in some function ...
    ##########################
    my $log = Log::Log4perl::get_logger("main");

    # get dump of param_href if -v (verbose) flag is on (for debugging)
    my $param_print = sprintf( Data::Dumper->Dump( [$param_href], [qw(param_href)] ) ) if $verbose;
    $log->debug("$param_print") if $verbose;

    # split input fasta file to chunks
    my ( $num_large, $num_normal ) = write_chunks($param_href);
    $param_href = { num_l => $num_large, num_n => $num_normal, %{$param_href} };
    if ($verbose) { $log->debug( '$param_href after chunking', Dumper($param_href) ); }

    # call write modes (different subs that print different jobs)
    my %subs = (
        sge_plus_combined       => \&sge_plus_combined,
        condor_plus_combined    => \&condor_plus_combined,
        condor_plus_combined_sh => \&condor_plus_combined_sh,

    );
    foreach my $write_mode ( sort keys %subs ) {
        $log->info( "RUNNING ACTION for write_mode: ", $write_mode );
        $subs{$write_mode}->($param_href);
        $log->info("TIME when finished for: $write_mode");
    }

    return;
}

### INTERNAL UTILITY ###
# Usage      : my ($param_href) = get_parameters_from_cmd();
# Purpose    : processes parameters from command line
# Returns    : $param_href --> hash ref of all command line arguments and files
# Parameters : none -> works by argument handling by Getopt::Long
# Throws     : lots of exceptions from die
# Comments   : works without logger
# See Also   : run()
sub get_parameters_from_cmd {

    #no logger here
	# setup config file location
	my ($volume, $dir_out, $perl_script) = splitpath( $0 );
	$dir_out = rel2abs($dir_out);
    my ($app_name) = $perl_script =~ m{\A(.+)\.(?:.+)\z};
	$app_name = lc $app_name;
    my $config_file = catfile($volume, $dir_out, $app_name . '.cnf' );
	$config_file = canonpath($config_file);

	#read config to setup defaults
	read_config($config_file => my %config);
	#p(%config);
	my $config_ps_href = $config{PS};
	#p($config_ps_href);
	my $config_ti_href = $config{TI};
	#p($config_ti_href);
	my $config_psname_href = $config{PSNAME};

	#push all options into one hash no matter the section
	my %opts;
	foreach my $key (keys %config) {
		# don't expand PS, TI or PSNAME
		next if ( ($key eq 'PS') or ($key eq 'TI') or ($key eq 'PSNAME') );
		# expand all other options
		%opts = (%opts, %{ $config{$key} });
	}

	# put config location to %opts
	$opts{config} = $config_file;

	# put PS and TI section to %opts
	$opts{ps} = $config_ps_href;
	$opts{ti} = $config_ti_href;
	$opts{psname} = $config_psname_href;

	#cli part
	my @arg_copy = @ARGV;
	my (%cli, @mode);
	$cli{quiet} = 0;
	$cli{verbose} = 0;
	$cli{argv} = \@arg_copy;

	#mode, quiet and verbose can only be set on command line
    GetOptions(
        'help|h'        => \$cli{help},
        'man|m'         => \$cli{man},
        'config|cnf=s'  => \$cli{config},
        'in|i=s'        => \$cli{in},
        'infile|if=s'   => \$cli{infile},
        'out|o=s'       => \$cli{out},
        'outfile|of=s'  => \$cli{outfile},

        'chunk_num|n=i'     => \$cli{chunk_num},
        'chunk_name|name=s' => \$cli{chunk_name},
        'top|t=i'           => \$cli{top},
        'size|s=i'          => \$cli{size},
        'cpu|c=i'           => \$cli{cpu},
        'cpu_l|cl=i'        => \$cli{cpu_l},
        'db|d=s'            => \$cli{db},
        'db_name|dn=s'      => \$cli{db_name},
        'db_gz_name|dgn=s'  => \$cli{db_gz_name},
        'db_path|dp=s'      => \$cli{db_path},
        'app|ap=s'          => \$cli{app},

        'mode|mo=s{1,}' => \$cli{mode},       #accepts 1 or more arguments
        'append|a'      => \$cli{append},     #flag
        'quiet|q'       => \$cli{quiet},      #flag
        'verbose+'      => \$cli{verbose},    #flag
    ) or pod2usage( -verbose => 1 );

	# help and man
	pod2usage( -verbose => 1 ) if $cli{help};
	pod2usage( -verbose => 2 ) if $cli{man};

	#if not -q or --quiet print all this (else be quiet)
	if ($cli{quiet} == 0) {
		#print STDERR 'My @ARGV: {', join( "} {", @arg_copy ), '}', "\n";
		#no warnings 'uninitialized';
		#print STDERR "Extra options from config:", Dumper(\%opts);
	
		if ($cli{in}) {
			say 'My input path: ', canonpath($cli{in});
			$cli{in} = rel2abs($cli{in});
			$cli{in} = canonpath($cli{in});
			say "My absolute input path: $cli{in}";
		}
		if ($cli{infile}) {
			say 'My input file: ', canonpath($cli{infile});
			$cli{infile} = rel2abs($cli{infile});
			$cli{infile} = canonpath($cli{infile});
			say "My absolute input file: $cli{infile}";
		}
		if ($cli{out}) {
			say 'My output path: ', canonpath($cli{out});
			$cli{out} = rel2abs($cli{out});
			$cli{out} = canonpath($cli{out});
			say "My absolute output path: $cli{out}";
		}
		if ($cli{outfile}) {
			say 'My outfile: ', canonpath($cli{outfile});
			$cli{outfile} = rel2abs($cli{outfile});
			$cli{outfile} = canonpath($cli{outfile});
			say "My absolute outfile: $cli{outfile}";
		}
	}
	else {
		$cli{verbose} = -1;   #and logging is OFF

		if ($cli{in}) {
			$cli{in} = rel2abs($cli{in});
			$cli{in} = canonpath($cli{in});
		}
		if ($cli{infile}) {
			$cli{infile} = rel2abs($cli{infile});
			$cli{infile} = canonpath($cli{infile});
		}
		if ($cli{out}) {
			$cli{out} = rel2abs($cli{out});
			$cli{out} = canonpath($cli{out});
		}
		if ($cli{outfile}) {
			$cli{outfile} = rel2abs($cli{outfile});
			$cli{outfile} = canonpath($cli{outfile});
		}
	}

    #copy all config opts
	my %all_opts = %opts;
	#update with cli options
	foreach my $key (keys %cli) {
		if ( defined $cli{$key} ) {
			$all_opts{$key} = $cli{$key};
		}
	}

    return ( \%all_opts );
}

### INTERNAL UTILITY ###
# Usage      : init_logging();
# Purpose    : enables Log::Log4perl log() to Screen and File
# Returns    : nothing
# Parameters : verbose flag + copy of parameters from command line
# Throws     : croaks if it receives parameters
# Comments   : used to setup a logging framework
#            : logfile is in same directory and same name as script -pl +log
# See Also   : Log::Log4perl at https://metacpan.org/pod/Log::Log4perl
sub init_logging {
    exit 'init_logging() needs verbose parameter' unless @_ == 2;
    my ( $verbose, $argv_copy ) = @_;

    #create log file in same dir where script is running
	#removes perl script and takes absolute path from rest of path
	my ($volume,$dir_out,$perl_script) = splitpath( $0 );
	#say '$dir_out:', $dir_out;
	$dir_out = rel2abs($dir_out);
	#say '$dir_out:', $dir_out;

    my ($app_name) = $perl_script =~ m{\A(.+)\.(?:.+)\z};   #takes name of the script and removes .pl or .pm or .t
    #say '$app_name:', $app_name;
    my $logfile = catfile( $volume, $dir_out, $app_name . '.log' );    #combines all of above with .log
	#say '$logfile:', $logfile;
	$logfile = canonpath($logfile);
	#say '$logfile:', $logfile;

    #colored output on windows
    my $osname = $^O;
    if ( $osname eq 'MSWin32' ) {
        require Win32::Console::ANSI;                                 #require needs import
        Win32::Console::ANSI->import();
    }

    #enable different levels based on verbose flag
    my $log_level;
    if    ($verbose == 0)  { $log_level = 'INFO';  }
    elsif ($verbose == 1)  { $log_level = 'DEBUG'; }
    elsif ($verbose == 2)  { $log_level = 'TRACE'; }
    elsif ($verbose == -1) { $log_level = 'OFF';   }
	else                   { $log_level = 'INFO';  }

    #levels:
    #TRACE, DEBUG, INFO, WARN, ERROR, FATAL
    ###############################################################################
    #                              Log::Log4perl Conf                             #
    ###############################################################################
    # Configuration in a string ...
    my $conf = qq(
      log4perl.category.main                   = TRACE, Logfile, Screen

	  # Filter range from TRACE up
	  log4perl.filter.MatchTraceUp               = Log::Log4perl::Filter::LevelRange
      log4perl.filter.MatchTraceUp.LevelMin      = TRACE
      log4perl.filter.MatchTraceUp.LevelMax      = FATAL
      log4perl.filter.MatchTraceUp.AcceptOnMatch = true

      # Filter range from $log_level up
      log4perl.filter.MatchLevelUp               = Log::Log4perl::Filter::LevelRange
      log4perl.filter.MatchLevelUp.LevelMin      = $log_level
      log4perl.filter.MatchLevelUp.LevelMax      = FATAL
      log4perl.filter.MatchLevelUp.AcceptOnMatch = true
      
	  # setup of file log
      log4perl.appender.Logfile           = Log::Log4perl::Appender::File
      log4perl.appender.Logfile.filename  = $logfile
      log4perl.appender.Logfile.mode      = append
      log4perl.appender.Logfile.autoflush = 1
      log4perl.appender.Logfile.umask     = 0022
      log4perl.appender.Logfile.header_text = INVOCATION:$0 @$argv_copy
      log4perl.appender.Logfile.layout    = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Logfile.layout.ConversionPattern = [%d{yyyy/MM/dd HH:mm:ss,SSS}]%5p> %M line:%L==>%m%n
	  log4perl.appender.Logfile.Filter    = MatchTraceUp
      
	  # setup of screen log
      log4perl.appender.Screen            = Log::Log4perl::Appender::ScreenColoredLevels
      log4perl.appender.Screen.stderr     = 1
      log4perl.appender.Screen.layout     = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Screen.layout.ConversionPattern  = [%d{yyyy/MM/dd HH:mm:ss,SSS}]%5p> %M line:%L==>%m%n
	  log4perl.appender.Screen.Filter     = MatchLevelUp
    );

    # ... passed as a reference to init()
    Log::Log4perl::init( \$conf );

    return;
}


1;
__END__

=encoding utf-8

=head1 NAME

PsiBlastHelper - It's modulino that splits fasta input file into number of chunks for BLAST, PSI-BLAST and HMMER to run them on cluster or grid

=head1 SYNOPSIS

    use PsiBlastHelper;

=head1 DESCRIPTION

PsiBlastHelper is ...

=head1 LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

mocnii E<lt>msestak@irb.hrE<gt>

=cut

