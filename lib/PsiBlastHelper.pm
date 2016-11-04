#!/usr/bin/env perl
package PsiBlastHelper;
use 5.010;
use strict;
use warnings;
no warnings 'experimental::smartmatch';
use Exporter qw/import/;
use Carp;
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
  split_fasta
  sge_blast_combined
  condor_blast_combined
  condor_blast_combined_sh
  sge_psiblast_combined
  condor_psiblast_combined
  condor_psiblast_combined_sh
  sge_hmmer

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
    my ( $num_large, $num_normal ) = split_fasta($param_href);
    $param_href = { num_l => $num_large, num_n => $num_normal, %{$param_href} };
    if ($verbose) { $log->debug( '$param_href after chunking', Dumper($param_href) ); }

    # call write modes (different subs that print different jobs)
    my %subs = (
        sge_blast_combined       => \&sge_blast_combined,
        condor_blast_combined    => \&condor_blast_combined,
        condor_blast_combined_sh => \&condor_blast_combined_sh,
        sge_psiblast_combined       => \&sge_psiblast_combined,
        condor_psiblast_combined    => \&condor_psiblast_combined,
        condor_psiblast_combined_sh => \&condor_psiblast_combined_sh,
        sge_hmmer     => \&sge_hmmer,

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

        'chunk_size|n=i'     => \$cli{chunk_size},
        'chunk_name|name=s' => \$cli{chunk_name},
        'top|t=i'           => \$cli{top},
        'fasta_size|s=i'    => \$cli{fasta_size},
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


### WORKING SUB ###
# Usage      : split_fasta(  );
# Purpose    : splits fasta file into chunks
# Returns    : nothing
# Parameters : ( all from command line )
# Throws     : croaks if wrong number of arguments
# Comments   : splits fasta, writes chunks, longest sequences
# See Also   :
sub split_fasta {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('split_fasta() needs a hash_ref') unless @_ == 1;
    my ($param_href) = @_;

    my $infile     = $param_href->{infile}     or $log->logcroak('no $infile specified on command line!');
    my $out        = $param_href->{out}        or $log->logcroak('no $out specified on command line!');
    my $chunk_size = $param_href->{chunk_size} or $log->logcroak('no $chunk_size specified on command line!');
    my $chunk_name = $param_href->{chunk_name} or $log->logcroak('no $chunk_name specified on command line!');
    my $top        = $param_href->{top};
    my $fasta_size = $param_href->{fasta_size};
    my $append     = $param_href->{append};

    #clean $out directory before use
    if ( -d $out ) {
        path($out)->remove_tree and $log->warn(qq|Action: dir $out removed and cleaned|);
    }
    path($out)->mkpath and $log->trace(qq|Action: dir $out created empty|);

    # load fasta sequences into hash
    # FORMAT:header => [length, fasta_seq]
    my $fasta_href = _load_fasta($param_href);

    # find and print the longest sequences
    my ( $only_normal_href, $longest_cnt ) = _print_longest_seq( { fasta => $fasta_href, %{$param_href} } );

    # print out all normal sequences
    my $chunk_cnt = _print_normal_seq( { normal_seq => $only_normal_href, %{$param_href} } );

    $log->info( 'Returning num of longest: ', $longest_cnt, ' and num of chunks: ', $chunk_cnt );
    return ( $longest_cnt, $chunk_cnt );

}


### INTERNAL UTILITY ###
# Usage      : my $fasta_href = _load_fasta($param_href);
# Purpose    : read and push fasta sequences into hash to use later to split them based on length
# Returns    : $hash_ref of fasta sequences
# Parameters : $param_href
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : split_fasta() calls it
sub _load_fasta {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_load_fasta() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    # load fasta sequences into hash
    # FORMAT:header => [length, fasta_seq]
    open( my $fh_instream, "<", $param_href->{infile} )
      or $log->logdie("error opening input file $param_href->{infile}:$!");
    my $countseq = 0;
    my %fasta;

    # start fasta reading
    local $/ = '>';

    # calculate number of fasta sequences and their length
    while ( my $line = <$fh_instream> ) {
        chomp $line;

        if ($line =~ m{\A([^\s+]+)\s+    #header of seq till first space
                (.+)\z                   #fasta_seq
                }xms
          )
        {
            $countseq++;
            my $header = $1;
            my $fasta_seq = $2;
            $fasta_seq =~ s/\R//g;
            $fasta_seq = uc $fasta_seq;
            $fasta_seq =~ tr/A-Z*//dc;
            my $fasta_len = length $fasta_seq;

            # add to complex hash
            $fasta{$header} = [ $fasta_len, $fasta_seq ];
        }
    }
    close $fh_instream;

    # report summary statistics of fasta sequences
    $log->info( 'Num of seq: ',    $countseq );
    $log->info( 'Num of seq in chunk: ', $param_href->{chunk_size} );
    my $num_of_chunks = int( $countseq / $param_href->{chunk_size} );
    $log->info( 'Num of chunks: ', $num_of_chunks );
    my $remainder = $countseq % $param_href->{chunk_size};
    $log->info( 'Num of seq left without chunk: ', $remainder );

    return \%fasta;
}


### CLASS METHOD/INSTANCE METHOD/INTERFACE SUB/INTERNAL UTILITY ###
# Usage      : my ($only_normal_href, $longest_cnt) = _print_longest_seq( { fasta => $fasta_href, %{$param_href} } );
# Purpose    : prints longest sequences separately 
# Returns    : 
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : split_fasta() calls it
sub _print_longest_seq {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_print_longest_seq() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;
    my %fasta = %{$param_href->{fasta}};

    # find the longest sequences
    # get the values out from aref [seq_len, fasta], pull first value from array_ref with map, sort numerically descending
    # print Dumper(\%fasta);
    my @all = sort { $b <=> $a } map { $_->[0] } values %fasta;

    #print all only for small inputs
    say "All seq lengths: @all" if scalar @all < 10;

    #longest seqs depends on top or size
    my @longest;
    if ( $param_href->{top} and $param_href->{fasta_size} ) {
        $log->logdie("Error: choose either -t or -s option, not both");
    }
    elsif ($param_href->{top}) {
        @longest = @all[ 0 .. $param_href->{top} - 1 ];    #sorted from longest so this works
        $log->warn("Top $param_href->{top}:@longest");
    }
    elsif ($param_href->{fasta_size}) {
        @longest = grep { $_ > $param_href->{fasta_size} } @all;
        $log->warn( "Larger than $param_href->{fasta_size} {", scalar @longest, " seq}: @longest" );
    }
    else {
        $log->logdie("Error: choose either -t or -s option");
    }

    # extract longest sequences
    my %only_large;
    my %only_normal;
    while ( my ( $gene_name, $aref ) = each %fasta ) {
        foreach my $num (@longest) {
            if ( $num == $fasta{$gene_name}[0] ) {
                $only_large{$gene_name} = $fasta{$gene_name};
            }
        }
        $only_normal{$gene_name} = $fasta{$gene_name}[1];    #here are all sequences not only normal
    }

    #delete longest sequences from normal sequences
    delete @only_normal{ keys %only_large };    #hash slice
                                                #print Dumper(\%only_normal);

    #print out large sequences one by one
    my $index = 1;
    foreach my $gene ( keys %only_large ) {
        my $largeseq = path( $param_href->{out}, $param_href->{chunk_name} . '_large' . $index )->canonpath;
        open( my $fh_large, ">", $largeseq ) or $log->logdie("Error: can't open large output file:$largeseq:$!");

        say {$fh_large} ">$gene\n$only_large{$gene}[1]";
        $log->debug( "File_large: ", path($largeseq)->basename );
        $index++;
        close $fh_large;
    }

    return \%only_normal, scalar @longest;
}


### INTERNAL UTILITY ###
# Usage      : my $chunk_cnt =_print_normal_seq( { normal_seq => $only_normal_href,  %{$param_href} } );
# Purpose    : prints normal sized sequences in chunks
# Returns    : num of chunks printed
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub _print_normal_seq {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_print_normal_seq() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;
    my %only_normal = %{ $param_href->{normal_seq} };

    # print out all normal sequences
    my $counter_normal = 0;    #counter for each sequence
    my @bucket;                #array holding seqs for print
    my $chunk = 0;             #counter for each chunk

    # loop for all sequences
    while ( my ( $name, $seq ) = each %only_normal ) {
        $counter_normal++;     #say $counter_normal;

        # push already formated sequences
        push @bucket, ">$name\n$seq\n";

        # for each full container equal to chunk_size
        if ( $counter_normal % $param_href->{chunk_size} == 0) {

            $chunk++;          #increment before so you don't need to change last append name

            my $normal_seq = path( $param_href->{out}, $param_href->{chunk_name} . $chunk )->canonpath;
            open( my $fh_normal, ">", $normal_seq ) or $log->logdie("Can't open normal output file $normal_seq:$!");
            print {$fh_normal} @bucket;
            $log->debug( "File: ", path($normal_seq)->basename, " printed with $param_href->{chunk_size} sequences");
            @bucket = ();      #empty each bucket for new chunk
            close $fh_normal;
        }

    }

    # for remainder of sequences create new file (default) or append to last chunk
    if ( scalar @bucket > 0 ) {

        # different behaviour depending on append option
        if ( $param_href->{append} ) {    #append to previous file
            my $normal_seq = path( $param_href->{out}, $param_href->{chunk_name} . $chunk )->canonpath;
            open( my $fh_normal, ">>", $normal_seq ) or die "Can't open apppended output file $normal_seq:$!\n";
            print {$fh_normal} @bucket;
            my $append_cnt = @bucket;
            $log->debug( "File ", path($normal_seq)->basename, " appended $append_cnt sequences" );
            @bucket = ();
            close $fh_normal;
        }

        # default is to create new file and put sequences there
        else {
            $chunk++;
            my $normal_seq = path( $param_href->{out}, $param_href->{chunk_name} . $chunk )->canonpath;
            open( my $fh_normal, ">", $normal_seq ) or die "Can't open remainder output file $normal_seq:$!\n";
            print {$fh_normal} @bucket;
            my $remainder_cnt = @bucket;
            $log->debug( 'File ', path($normal_seq)->basename, " printed with $remainder_cnt sequences" );
            @bucket = ();
            close $fh_normal;
        }
    }

    return $chunk;
}


### WORKING SUB ###
# Usage      : sge_blast_combined();
# Purpose    : writes SGE SCRIPTS for BLAST+ files split_fasta() generated
# Returns    : nothing
# Parameters : ($param_href)
# Throws     : croaks if wrong number of arguments
# Comments   : writes SGE scripts to run BLAST+ on isabella
# See Also   : split_fasta()
sub sge_blast_combined {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak( 'sge_blast_combined() needs a hash_ref' ) unless @_ == 1;
    my ( $param_href ) = @_;

    my $out        = $param_href->{out}        or $log->logcroak('no out specified on command line!');
    my $chunk_name = $param_href->{chunk_name} or $log->logcroak('no chunk_name specified on command line!');
    my $cpu        = $param_href->{cpu}        or $log->logcroak('no cpu specified on command line!');
    my $cpu_l      = $param_href->{cpu_l}      or $log->logcroak('no cpu_l specified on command line!');
	my $num_l      = $param_href->{num_l}      // $log->logcroak('no num_l sent to sub!');   #can be 0 so checks for defindness
	my $num_n      = $param_href->{num_n}      // $log->logcroak('no num_n sent to sub!');
    my $db_path    = $param_href->{db_path}    or $log->logcroak('no db_path specified on command line!');
    my $db_name    = $param_href->{db_name}    or $log->logcroak('no db_name specified on command line!');
    my $app        = defined $param_href->{app} ? $param_href->{app} : 'blastp';

	#build a queue for large seq
	my @large = 1 ..$num_l;
	my $script_num = 0;
	while (my @next_large = splice @large, 0, $cpu_l) {
		#say "@next_large";
		$script_num++;
		my $real_cpu = @next_large;   #calculate real cpu usage

		# generate input files
		my $input_files_large;
		foreach my $i (@next_large) {
			$input_files_large .= "$ENV{HOME}/in/${chunk_name}_large$i ";
		}

        #construct script for SGE large sequences
		my $sge_large = <<"SGE_LARGE";
#!/bin/sh

#\$ -N bl_${chunk_name}_lp$script_num
#\$ -cwd
#\$ -m abe
#\$ -M msestak\@irb.hr
#\$ -pe mpisingle $real_cpu
#\$ -R y
#\$ -l exclusive=1

mkdir -p \$TMPDIR/db
mkdir -p \$TMPDIR/out
mkdir -p \$TMPDIR/in
cp -uvR $db_path/* \$TMPDIR/db/
cp -uvR $input_files_large \$TMPDIR/in
SGE_LARGE

		my $sge_large_script = path( $out, $chunk_name . "_sge_large_plus_combined$script_num.submit" )->canonpath;
    	open( my $sge_large_fh, ">", $sge_large_script ) or die "Can't open large output file $sge_large_script:$!\n";
    	say {$sge_large_fh} $sge_large;

		#print for all jobs
		foreach my $i (@next_large) {
			my $blast_cmd = qq{$app -db \$TMPDIR/db/$db_name -query \$TMPDIR/in/${chunk_name}_large$i -out \$TMPDIR/out/${chunk_name}_largeoutplus$i -evalue 1e-3 -outfmt 6 -seg yes -max_target_seqs 100000000 &};
			say {$sge_large_fh} $blast_cmd;
		}

		#print bash wait to wait on all background processes
		say {$sge_large_fh} "\nwait\n";

		#copy all back
		foreach my $i (@next_large) {
			my $cp_cmd = qq{cp --preserve=timestamps \$TMPDIR/out/${chunk_name}_largeoutplus$i $ENV{HOME}/out/};
			say {$sge_large_fh} $cp_cmd;
		}
		
		$log->info( "SGE large BLAST+ combined (jobs @next_large) script: $sge_large_script" );
	}   #end while


	#SECOND PART
	#build a queue for large seq
	my @normal = 1 ..$num_n;
	my $script_num_n = 0;
	while (my @next_normal = splice @normal, 0, $cpu) {
		#say "@next_normal";
		$script_num_n++;
		my $real_cpu = @next_normal;

		# generate input files
		my $input_files_normal;
		foreach my $i (@next_normal) {
			$input_files_normal .= "$ENV{HOME}/in/${chunk_name}$i ";
		}

		#construct script for SGE normal sequences
		my $sge_normal = <<"SGE_NORMAL";
#!/bin/sh

#\$ -N bl_${chunk_name}_p$script_num_n
#\$ -cwd
#\$ -m abe
#\$ -M msestak\@irb.hr
#\$ -pe mpisingle $real_cpu
#\$ -R y
#\$ -l exclusive=1

mkdir -p \$TMPDIR/db
mkdir -p \$TMPDIR/out
mkdir -p \$TMPDIR/in
cp -uvR $db_path/* \$TMPDIR/db/
cp -uvR $input_files_normal \$TMPDIR/in
SGE_NORMAL

		my $sge_normal_script = path( $out, $chunk_name . "_sge_normal_plus_combined$script_num_n.submit" )->canonpath;
		open( my $sge_normal_fh, ">", $sge_normal_script ) or die "Can't open normal output file $sge_normal_script:$!\n";
		say {$sge_normal_fh} $sge_normal;

		#print all blastall processes as background
		foreach my $i (@next_normal) {
			my $blast_cmd = qq{$app -db \$TMPDIR/db/$db_name -query \$TMPDIR/in/${chunk_name}$i -out \$TMPDIR/out/${chunk_name}_outplus$i -evalue 1e-3 -outfmt 6 -seg yes -max_target_seqs 100000000 &};
			say {$sge_normal_fh} $blast_cmd;
		}

		#print bash wait to wait on all background processes
		say {$sge_normal_fh} "\nwait\n";

		#copy all back
		foreach my $i (@next_normal) {
			my $cp_cmd = qq{cp --preserve=timestamps \$TMPDIR/out/${chunk_name}_outplus$i $ENV{HOME}/out/};
			say {$sge_normal_fh} $cp_cmd;
		}

		$log->info( "SGE normal BLAST+ combined (jobs @next_normal) script: $sge_normal_script" );

	}   #end while

    return;
}


### CLASS METHOD/INSTANCE METHOD/INTERFACE SUB/INTERNAL UTILITY ###
# Usage      : condor_blast_combined( $param_href )
# Purpose    : creates HTCondor submit scripts
# Returns    : nothing
# Parameters : $param_href
# Throws     : croaks if wrong number of parameters
# Comments   : creates 2 scripts that starts HTCondor
# See Also   : condor_blast_combined_sh() which creates run scripts
sub condor_blast_combined {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('condor_blast_combined() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $out        = $param_href->{out}        or $log->logcroak('no out specified on command line!');
    my $chunk_name = $param_href->{chunk_name} or $log->logcroak('no chunk_name specified on command line!');
    my $cpu        = $param_href->{cpu}        or $log->logcroak('no cpu specified on command line!');
    my $cpu_l      = $param_href->{cpu_l}      or $log->logcroak('no cpu_l specified on command line!');
	my $num_l      = $param_href->{num_l}      // $log->logcroak('no num_l sent to sub!');   #can be 0 so checks for defindness
	my $num_n      = $param_href->{num_n}      // $log->logcroak('no num_n sent to sub!');
    my $app        = defined $param_href->{app} ? $param_href->{app} : 'blastp';

	#build a queue for large seq
	my @large = 1 ..$num_l;
	my $script_num = 0;
	while (my @next_large = splice @large, 0, $cpu_l) {
		#say "@next_large";
		$script_num++;
		my $real_cpu = @next_large;   #calculate real cpu usage

        #construct script for HTCondor large sequences
		my $condor_large = <<"HTCondor_LARGE";
Executable=bl_${chunk_name}_lp$script_num.sh
#Arguments=
TransferExecutable = True
Notification       = Complete
notify_user        = msestak\@irb.hr
universe           = grid
grid_resource      = gt2 ce.srce.cro-ngi.hr/jobmanager-sge

GlobusRSL   = (jobType=single)(count=$real_cpu)(exclusive=1)
Environment = "PE_MODE=single"

should_transfer_files = yes
WhenToTransferOutput  = ON_EXIT
transfer_input_files  = in.tgz, $app
HTCondor_LARGE

		my $condor_large_script = path( $out, $chunk_name . "_condor_large_plus_combined$script_num.submit" )->canonpath;
    	open( my $condor_large_fh, ">", $condor_large_script ) or die "Can't open large output file $condor_large_script:$!\n";
    	say {$condor_large_fh} $condor_large;

		#print for all jobs
		my @returning_output;
		foreach my $i (@next_large) {
			my $blast_output = "${chunk_name}_largeoutplus$i";
			push @returning_output, $blast_output;
		}
		say {$condor_large_fh} "transfer_output_files = ", join ", ", @returning_output;


		my $condor_large2 = <<"HTCondor_LARGE2";

Log    = log/bl_${chunk_name}_lp$script_num.\$(cluster).log
Output = log/bl_${chunk_name}_lp$script_num.\$(cluster).out
Error  = log/bl_${chunk_name}_lp$script_num.\$(cluster).err

queue

HTCondor_LARGE2

		say {$condor_large_fh} $condor_large2;
		
		$log->info( "HTCondor large BLAST+ combined (jobs @next_large) script: $condor_large_script" );
	}   #end while for each script


	#SECOND PART
	#build a queue for normal seq
	my @normal = 1 ..$num_n;
	my $script_num_n = 0;
	while (my @next_normal = splice @normal, 0, $cpu) {
		#say "@next_normal";
		$script_num_n++;
		my $real_cpu = @next_normal;

		#construct script for HTCondor normal sequences
		my $condor_normal = <<"HTCondor_NORMAL";
Executable=bl_${chunk_name}_p$script_num_n.sh
#Arguments=
TransferExecutable = True
Notification       = Complete
notify_user        = msestak\@irb.hr
universe           = grid
grid_resource      = gt2 ce.srce.cro-ngi.hr/jobmanager-sge

GlobusRSL   = (jobType=single)(count=$real_cpu)(exclusive=1)
Environment = "PE_MODE=single"

should_transfer_files = yes
WhenToTransferOutput  = ON_EXIT
transfer_input_files  = in.tgz, $app
HTCondor_NORMAL

		my $condor_normal_script = path( $out, $chunk_name . "_condor_normal_plus_combined$script_num_n.submit" )->canonpath;
		open( my $condor_normal_fh, ">", $condor_normal_script ) or die "Can't open normal output file $condor_normal_script:$!\n";
		say {$condor_normal_fh} $condor_normal;

		#print for all jobs
		my @returning_output_n;
		foreach my $i (@next_normal) {
			my $blast_output = "${chunk_name}_outplus$i";
			push @returning_output_n, $blast_output;
		}
		say {$condor_normal_fh} "transfer_output_files = ", join ", ", @returning_output_n;


		my $condor_normal2 = <<"HTCondor_NORMAL2";

Log    = log/bl_${chunk_name}_p$script_num.\$(cluster).log
Output = log/bl_${chunk_name}_p$script_num.\$(cluster).out
Error  = log/bl_${chunk_name}_p$script_num.\$(cluster).err

queue

HTCondor_NORMAL2

		say {$condor_normal_fh} $condor_normal2;
		
		$log->info( "HTCondor normal BLAST+ combined (jobs @next_normal) script: $condor_normal_script" );
	}   #end while for each script

    return;
}


### CLASS METHOD/INSTANCE METHOD/INTERFACE SUB/INTERNAL UTILITY ###
# Usage      : condor_blast_combined_sh( $param_href )
# Purpose    : creates HTCondor bash run scripts
# Returns    : nothing
# Parameters : $param_href
# Throws     : croaks if wrong number of parameters
# Comments   : creates 2 scripts for each job with 4 BLAST jobs inside
#            : uberftp ce.srce.cro-ngi.hr to transfer db.tgz into $HOME/newdata/
# See Also   : condor_blast_combined() which creates submit scripts
sub condor_blast_combined_sh {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('condor_blast_combined_sh() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $out        = $param_href->{out}        or $log->logcroak('no out specified on command line!');
    my $chunk_name = $param_href->{chunk_name} or $log->logcroak('no chunk_name specified on command line!');
    my $cpu        = $param_href->{cpu}        or $log->logcroak('no cpu specified on command line!');
    my $cpu_l      = $param_href->{cpu_l}      or $log->logcroak('no cpu_l specified on command line!');
	my $num_l      = $param_href->{num_l}      // $log->logcroak('no num_l sent to sub!');   #can be 0 so checks for defindness
	my $num_n      = $param_href->{num_n}      // $log->logcroak('no num_n sent to sub!');
    my $db_name    = $param_href->{db_name}    or $log->logcroak('no db_name specified on command line!');
    my $db_gz_name = $param_href->{db_gz_name} or $log->logcroak('no db_gz_name specified on command line!');
    my $app        = defined $param_href->{app} ? $param_href->{app} : 'blastp';

	#build a queue for large seq
	my @large = 1 ..$num_l;
	my $script_num = 0;
	while (my @next_large = splice @large, 0, $cpu_l) {
		#say "@next_large";
		$script_num++;
		my $real_cpu = @next_large;   #calculate real cpu usage

        #construct script for HTCondor large sequences
		my $condor_large = <<"HTCondor_LARGE";
#!/bin/bash

WORKDIR=\$PWD
echo "SCRATCH_DIRECTORY (workdir) is:\$WORKDIR"
HTCondor_LARGE

		#name of the script here
		my $condor_large_script = path( $out, "bl_${chunk_name}_lp$script_num.sh" )->canonpath;
    	open( my $condor_large_fh, ">", $condor_large_script ) or die "Can't open large output file $condor_large_script:$!\n";
    	say {$condor_large_fh} $condor_large;

		# generate touch (output files)
		my @returning_output;
		foreach my $i (@next_large) {
			my $blast_output = "${chunk_name}_largeoutplus$i";
			push @returning_output, $blast_output;
		}
		say {$condor_large_fh} "touch @returning_output";

		#second part of script
		my $condor_large2 = <<"HTCondor_LARGE2";
chmod +x blastp

sleep 1
echo "{\$(pwd)" && echo "\$(ls -lha)}"

cd \$TMPDIR
echo "TMPDIR is:\$TMPDIR"
cp \$WORKDIR/* \$TMPDIR
tar -zxf in.tgz
tar -zxf \$HOME/newdata/$db_gz_name
HTCondor_LARGE2

		say {$condor_large_fh} $condor_large2;

		# print BLAST+ command for all jobs
		foreach my $i (@next_large) {
			my $blast_cmd = qq{\$TMPDIR/blastp -db \$TMPDIR/$db_name -query \$TMPDIR/${chunk_name}_large$i -out \$TMPDIR/${chunk_name}_largeoutplus$i -evalue 1e-3 -outfmt 6 -seg yes -max_target_seqs 100000000 &};
			say {$condor_large_fh} $blast_cmd;
		}

		#third part of script
		my $condor_large3 = <<"HTCondor_LARGE3";

sleep 1
echo "\$(pgrep -fl blastp)"
echo "{\$(pwd)" && echo "\$(ls -lha)}"

#echo "\$(env)"

wait
HTCondor_LARGE3

		say {$condor_large_fh} $condor_large3;

		# copy to workdir (so HTCondor can return them back)
		say {$condor_large_fh} "cp @returning_output \$WORKDIR";
		
		$log->info( "HTCondor large BLAST+ shell script: $condor_large_script" );
	}   #end while for each script


	#SECOND PART
	#build a queue for normal seq
	my @normal = 1 ..$num_n;
	my $script_num_n = 0;
	while (my @next_normal = splice @normal, 0, $cpu) {
		#say "@next_normal";
		$script_num_n++;
		my $real_cpu = @next_normal;

		#construct script for HTCondor normal sequences
		my $condor_normal = <<"HTCondor_NORMAL";
#!/bin/bash

WORKDIR=\$PWD
echo "SCRATCH_DIRECTORY (workdir) is:\$WORKDIR"
HTCondor_NORMAL

		# name of the script here
		my $condor_normal_script = path( $out, "bl_${chunk_name}_p$script_num_n.sh" )->canonpath;
    	open( my $condor_normal_fh, ">", $condor_normal_script ) or die "Can't open normal output file $condor_normal_script:$!\n";
    	say {$condor_normal_fh} $condor_normal;

		# print touch for all output files (just in case there is error)
		my @returning_output_n;
		foreach my $i (@next_normal) {
			my $blast_output = "${chunk_name}_outplus$i";
			push @returning_output_n, $blast_output;
		}
		say {$condor_normal_fh} "touch @returning_output_n";

		# second part of script
		my $condor_normal2 = <<"HTCondor_NORMAL2";
chmod +x blastp

sleep 1
echo "{\$(pwd)" && echo "\$(ls -lha)}"

cd \$TMPDIR
echo "TMPDIR is:\$TMPDIR"
cp \$WORKDIR/* \$TMPDIR
tar -zxf in.tgz
tar -zxf \$HOME/newdata/$db_gz_name
HTCondor_NORMAL2

		say {$condor_normal_fh} $condor_normal2;

		# print BLAST+ jobs
		foreach my $i (@next_normal) {
			my $blast_cmd = qq{\$TMPDIR/blastp -db \$TMPDIR/$db_name -query \$TMPDIR/${chunk_name}$i -out \$TMPDIR/${chunk_name}_outplus$i -evalue 1e-3 -outfmt 6 -seg yes -max_target_seqs 100000000 &};
			say {$condor_normal_fh} $blast_cmd;
		}

		# third part of script
		my $condor_normal3 = <<"HTCondor_NORMAL3";

sleep 1
echo "\$(pgrep -fl blastp)"
echo "{\$(pwd)" && echo "\$(ls -lha)}"

#echo "\$(env)"

wait
HTCondor_NORMAL3

		say {$condor_normal_fh} $condor_normal3;

		# copy output files back to workdir for HTCondor to return them back
		say {$condor_normal_fh} "cp @returning_output_n \$WORKDIR";
		
		$log->info( "HTCondor normal BLAST+ shell script: $condor_normal_script" );
	}   #end while for each script

    return;
}


### WORKING SUB ###
# Usage      : sge_psiblast_combined();
# Purpose    : writes SGE SCRIPTS for PSI-BLAST+ files split_fasta() generated
# Returns    : nothing
# Parameters : ($param_href)
# Throws     : croaks if wrong number of arguments
# Comments   : writes SGE scripts to run PSI-BLAST+ on isabella
# See Also   : split_fasta()
sub sge_psiblast_combined {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak( 'sge_psiblast_combined() needs a hash_ref' ) unless @_ == 1;
    my ( $param_href ) = @_;

    my $out        = $param_href->{out}        or $log->logcroak('no out specified on command line!');
    my $chunk_name = $param_href->{chunk_name} or $log->logcroak('no chunk_name specified on command line!');
    my $cpu        = $param_href->{cpu}        or $log->logcroak('no cpu specified on command line!');
    my $cpu_l      = $param_href->{cpu_l}      or $log->logcroak('no cpu_l specified on command line!');
	my $num_l      = $param_href->{num_l}      // $log->logcroak('no num_l sent to sub!');   #can be 0 so checks for defindness
	my $num_n      = $param_href->{num_n}      // $log->logcroak('no num_n sent to sub!');
    my $db_path    = $param_href->{db_path}    or $log->logcroak('no db_path specified on command line!');
    my $db_name    = $param_href->{db_name}    or $log->logcroak('no db_name specified on command line!');
    my $app        = defined $param_href->{app} ? $param_href->{app} : 'psiblast';

	#build a queue for large seq
	my @large = 1 ..$num_l;
	my $script_num = 0;
	while (my @next_large = splice @large, 0, $cpu_l) {
		#say "@next_large";
		$script_num++;
		my $real_cpu = @next_large;   #calculate real cpu usage

		# generate input files
		my $input_files_large;
		foreach my $i (@next_large) {
			$input_files_large .= "$ENV{HOME}/in/${chunk_name}_large$i ";
		}

        #construct script for SGE large sequences
		my $sge_large = <<"SGE_LARGE";
#!/bin/sh

#\$ -N psibl_${chunk_name}_lp$script_num
#\$ -cwd
#\$ -m abe
#\$ -M msestak\@irb.hr
#\$ -pe mpisingle $real_cpu
#\$ -R y
#\$ -l exclusive=1

mkdir -p \$TMPDIR/db
mkdir -p \$TMPDIR/out
mkdir -p \$TMPDIR/in
cp -uvR $db_path/* \$TMPDIR/db/
cp -uvR $input_files_large \$TMPDIR/in
SGE_LARGE

		my $sge_large_script = path( $out, $chunk_name . "_sge_psiblast_large_plus_combined$script_num.submit" )->canonpath;
    	open( my $sge_large_fh, ">", $sge_large_script ) or die "Can't open large output file $sge_large_script:$!\n";
    	say {$sge_large_fh} $sge_large;

		#print for all jobs
		foreach my $i (@next_large) {
			my $blast_cmd = qq{$app -db \$TMPDIR/db/$db_name -query \$TMPDIR/in/${chunk_name}_large$i -out \$TMPDIR/out/${chunk_name}_largepsiout$i -evalue 1e-3 -outfmt 6 -seg yes -max_target_seqs 100000000 -num_iterations=4 -inclusion_ethresh=1e-3 &};
			say {$sge_large_fh} $blast_cmd;
		}

		#print bash wait to wait on all background processes
		say {$sge_large_fh} "\nwait\n";

		#copy all back
		foreach my $i (@next_large) {
			my $cp_cmd = qq{cp --preserve=timestamps \$TMPDIR/out/${chunk_name}_largepsiout$i $ENV{HOME}/out/};
			say {$sge_large_fh} $cp_cmd;
		}
		
		$log->info( "SGE large PSI-BLAST+ combined (jobs @next_large) script: $sge_large_script" );
	}   #end while


	#SECOND PART
	#build a queue for large seq
	my @normal = 1 ..$num_n;
	my $script_num_n = 0;
	while (my @next_normal = splice @normal, 0, $cpu) {
		#say "@next_normal";
		$script_num_n++;
		my $real_cpu = @next_normal;

		# generate input files
		my $input_files_normal;
		foreach my $i (@next_normal) {
			$input_files_normal .= "$ENV{HOME}/in/${chunk_name}$i ";
		}

		#construct script for SGE normal sequences
		my $sge_normal = <<"SGE_NORMAL";
#!/bin/sh

#\$ -N bl_${chunk_name}_p$script_num_n
#\$ -cwd
#\$ -m abe
#\$ -M msestak\@irb.hr
#\$ -pe mpisingle $real_cpu
#\$ -R y
#\$ -l exclusive=1

mkdir -p \$TMPDIR/db
mkdir -p \$TMPDIR/out
mkdir -p \$TMPDIR/in
cp -uvR $db_path/* \$TMPDIR/db/
cp -uvR $input_files_normal \$TMPDIR/in
SGE_NORMAL

		my $sge_normal_script = path( $out, $chunk_name . "_sge_psiblast_normal_plus_combined$script_num_n.submit" )->canonpath;
		open( my $sge_normal_fh, ">", $sge_normal_script ) or die "Can't open normal output file $sge_normal_script:$!\n";
		say {$sge_normal_fh} $sge_normal;

		#print all blastall processes as background
		foreach my $i (@next_normal) {
			my $blast_cmd = qq{$app -db \$TMPDIR/db/$db_name -query \$TMPDIR/in/${chunk_name}$i -out \$TMPDIR/out/${chunk_name}_psiout$i -evalue 1e-3 -outfmt 6 -seg yes -max_target_seqs 100000000 -num_iterations=4 -inclusion_ethresh=1e-3 &};
			say {$sge_normal_fh} $blast_cmd;
		}

		#print bash wait to wait on all background processes
		say {$sge_normal_fh} "\nwait\n";

		#copy all back
		foreach my $i (@next_normal) {
			my $cp_cmd = qq{cp --preserve=timestamps \$TMPDIR/out/${chunk_name}_psiout$i $ENV{HOME}/out/};
			say {$sge_normal_fh} $cp_cmd;
		}

		$log->info( "SGE normal PSI-BLAST+ combined (jobs @next_normal) script: $sge_normal_script" );

	}   #end while

    return;
}


### CLASS METHOD/INSTANCE METHOD/INTERFACE SUB/INTERNAL UTILITY ###
# Usage      : condor_psiblast_combined( $param_href )
# Purpose    : creates HTCondor PSI_BLAST+ submit scripts
# Returns    : nothing
# Parameters : $param_href
# Throws     : croaks if wrong number of parameters
# Comments   : creates 2 scripts that starts HTCondor
# See Also   : condor_psiblast_combined_sh() which creates run scripts
sub condor_psiblast_combined {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('condor_psiblast_combined() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $out        = $param_href->{out}        or $log->logcroak('no out specified on command line!');
    my $chunk_name = $param_href->{chunk_name} or $log->logcroak('no chunk_name specified on command line!');
    my $cpu        = $param_href->{cpu}        or $log->logcroak('no cpu specified on command line!');
    my $cpu_l      = $param_href->{cpu_l}      or $log->logcroak('no cpu_l specified on command line!');
    my $num_l = $param_href->{num_l} // $log->logcroak('no num_l sent to sub!');    #can be 0 so checks for defindness
    my $num_n = $param_href->{num_n} // $log->logcroak('no num_n sent to sub!');
    my $app = defined $param_href->{app} ? $param_href->{app} : 'psiblast';

    #build a queue for large seq
    my @large      = 1 .. $num_l;
    my $script_num = 0;
    while ( my @next_large = splice @large, 0, $cpu_l ) {

        #say "@next_large";
        $script_num++;
        my $real_cpu = @next_large;                                                 #calculate real cpu usage

        #construct script for HTCondor large sequences
        my $condor_large = <<"HTCondor_LARGE";
Executable=psibl_${chunk_name}_lp$script_num.sh
#Arguments=
TransferExecutable = True
Notification       = Complete
notify_user        = msestak\@irb.hr
universe           = grid
grid_resource      = gt2 ce.srce.cro-ngi.hr/jobmanager-sge

GlobusRSL   = (jobType=single)(count=$real_cpu)(exclusive=1)
Environment = "PE_MODE=single"

should_transfer_files = yes
WhenToTransferOutput  = ON_EXIT
transfer_input_files  = in.tgz, $app
HTCondor_LARGE

        my $condor_large_script
          = path( $out, $chunk_name . "_condor_psiblast_large_plus_combined$script_num.submit" )->canonpath;
        open( my $condor_large_fh, ">", $condor_large_script )
          or die "Can't open large output file $condor_large_script:$!\n";
        say {$condor_large_fh} $condor_large;

        #print for all jobs
        my @returning_output;
        foreach my $i (@next_large) {
            my $blast_output = "${chunk_name}_largepsiout$i";
            push @returning_output, $blast_output;
        }
        say {$condor_large_fh} "transfer_output_files = ", join ", ", @returning_output;

        my $condor_large2 = <<"HTCondor_LARGE2";

Log    = log/bl_${chunk_name}_lp$script_num.\$(cluster).log
Output = log/bl_${chunk_name}_lp$script_num.\$(cluster).out
Error  = log/bl_${chunk_name}_lp$script_num.\$(cluster).err

queue

HTCondor_LARGE2

        say {$condor_large_fh} $condor_large2;

        $log->info("HTCondor large PSI-BLAST+ combined (jobs @next_large) script: $condor_large_script");
    }    #end while for each script

    #SECOND PART
    #build a queue for normal seq
    my @normal       = 1 .. $num_n;
    my $script_num_n = 0;
    while ( my @next_normal = splice @normal, 0, $cpu ) {

        #say "@next_normal";
        $script_num_n++;
        my $real_cpu = @next_normal;

        #construct script for HTCondor normal sequences
        my $condor_normal = <<"HTCondor_NORMAL";
Executable=psibl_${chunk_name}_p$script_num_n.sh
#Arguments=
TransferExecutable = True
Notification       = Complete
notify_user        = msestak\@irb.hr
universe           = grid
grid_resource      = gt2 ce.srce.cro-ngi.hr/jobmanager-sge

GlobusRSL   = (jobType=single)(count=$real_cpu)(exclusive=1)
Environment = "PE_MODE=single"

should_transfer_files = yes
WhenToTransferOutput  = ON_EXIT
transfer_input_files  = in.tgz, $app
HTCondor_NORMAL

        my $condor_normal_script
          = path( $out, $chunk_name . "_condor_psiblast_normal_plus_combined$script_num_n.submit" )->canonpath;
        open( my $condor_normal_fh, ">", $condor_normal_script )
          or die "Can't open normal output file $condor_normal_script:$!\n";
        say {$condor_normal_fh} $condor_normal;

        #print for all jobs
        my @returning_output_n;
        foreach my $i (@next_normal) {
            my $blast_output = "${chunk_name}_psiout$i";
            push @returning_output_n, $blast_output;
        }
        say {$condor_normal_fh} "transfer_output_files = ", join ", ", @returning_output_n;

        my $condor_normal2 = <<"HTCondor_NORMAL2";

Log    = log/bl_${chunk_name}_p$script_num.\$(cluster).log
Output = log/bl_${chunk_name}_p$script_num.\$(cluster).out
Error  = log/bl_${chunk_name}_p$script_num.\$(cluster).err

queue

HTCondor_NORMAL2

        say {$condor_normal_fh} $condor_normal2;

        $log->info("HTCondor normal PSI-BLAST+ combined (jobs @next_normal) script: $condor_normal_script");
    }    #end while for each script

    return;
}


### CLASS METHOD/INSTANCE METHOD/INTERFACE SUB/INTERNAL UTILITY ###
# Usage      : condor_psiblast_combined_sh( $param_href )
# Purpose    : creates HTCondor bash run scripts
# Returns    : nothing
# Parameters : $param_href
# Throws     : croaks if wrong number of parameters
# Comments   : creates 2 scripts for each job with 4 BLAST jobs inside
#            : uberftp ce.srce.cro-ngi.hr to transfer db.tgz into $HOME/newdata/
# See Also   : condor_psiblast_combined() which creates submit scripts
sub condor_psiblast_combined_sh {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('condor_psiblast_combined_sh() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $out        = $param_href->{out}        or $log->logcroak('no out specified on command line!');
    my $chunk_name = $param_href->{chunk_name} or $log->logcroak('no chunk_name specified on command line!');
    my $cpu        = $param_href->{cpu}        or $log->logcroak('no cpu specified on command line!');
    my $cpu_l      = $param_href->{cpu_l}      or $log->logcroak('no cpu_l specified on command line!');
    my $num_l = $param_href->{num_l} // $log->logcroak('no num_l sent to sub!');    #can be 0 so checks for defindness
    my $num_n = $param_href->{num_n} // $log->logcroak('no num_n sent to sub!');
    my $db_name    = $param_href->{db_name}    or $log->logcroak('no db_name specified on command line!');
    my $db_gz_name = $param_href->{db_gz_name} or $log->logcroak('no db_gz_name specified on command line!');
    my $app = defined $param_href->{app} ? $param_href->{app} : 'psiblast';

    #build a queue for large seq
    my @large      = 1 .. $num_l;
    my $script_num = 0;
    while ( my @next_large = splice @large, 0, $cpu_l ) {

        #say "@next_large";
        $script_num++;
        my $real_cpu = @next_large;    #calculate real cpu usage

        #construct script for HTCondor large sequences
        my $condor_large = <<"HTCondor_LARGE";
#!/bin/bash

WORKDIR=\$PWD
echo "SCRATCH_DIRECTORY (workdir) is:\$WORKDIR"
HTCondor_LARGE

        #name of the script here
        my $condor_large_script = path( $out, "psibl_${chunk_name}_lp$script_num.sh" )->canonpath;
        open( my $condor_large_fh, ">", $condor_large_script )
          or die "Can't open large output file $condor_large_script:$!\n";
        say {$condor_large_fh} $condor_large;

        # generate touch (output files)
        my @returning_output;
        foreach my $i (@next_large) {
            my $blast_output = "${chunk_name}_largepsiout$i";
            push @returning_output, $blast_output;
        }
        say {$condor_large_fh} "touch @returning_output";

        #second part of script
        my $condor_large2 = <<"HTCondor_LARGE2";
chmod +x psiblast

sleep 1
echo "{\$(pwd)" && echo "\$(ls -lha)}"

cd \$TMPDIR
echo "TMPDIR is:\$TMPDIR"
cp \$WORKDIR/* \$TMPDIR
tar -zxf in.tgz
tar -zxf \$HOME/newdata/$db_gz_name
HTCondor_LARGE2

        say {$condor_large_fh} $condor_large2;

        # print PSI-BLAST+ command for all jobs
        foreach my $i (@next_large) {
            my $blast_cmd
              = qq{\$TMPDIR/$app -db \$TMPDIR/$db_name -query \$TMPDIR/${chunk_name}_large$i -out \$TMPDIR/${chunk_name}_largepsiout$i -evalue 1e-3 -outfmt 6 -seg yes -max_target_seqs 100000000 -num_iterations=4 -inclusion_ethresh=1e-3 &};
            say {$condor_large_fh} $blast_cmd;
        }

        #third part of script
        my $condor_large3 = <<"HTCondor_LARGE3";

sleep 1
echo "\$(pgrep -fl psiblast)"
echo "{\$(pwd)" && echo "\$(ls -lha)}"

#echo "\$(env)"

wait
HTCondor_LARGE3

        say {$condor_large_fh} $condor_large3;

        # copy to workdir (so HTCondor can return them back)
        say {$condor_large_fh} "cp @returning_output \$WORKDIR";

        $log->info("HTCondor large PSI-BLAST+ shell script: $condor_large_script");
    }    #end while for each script

    #SECOND PART
    #build a queue for normal seq
    my @normal       = 1 .. $num_n;
    my $script_num_n = 0;
    while ( my @next_normal = splice @normal, 0, $cpu ) {

        #say "@next_normal";
        $script_num_n++;
        my $real_cpu = @next_normal;

        #construct script for HTCondor normal sequences
        my $condor_normal = <<"HTCondor_NORMAL";
#!/bin/bash

WORKDIR=\$PWD
echo "SCRATCH_DIRECTORY (workdir) is:\$WORKDIR"
HTCondor_NORMAL

        # name of the script here
        my $condor_normal_script = path( $out, "psibl_${chunk_name}_p$script_num_n.sh" )->canonpath;
        open( my $condor_normal_fh, ">", $condor_normal_script )
          or die "Can't open normal output file $condor_normal_script:$!\n";
        say {$condor_normal_fh} $condor_normal;

        # print touch for all output files (just in case there is error)
        my @returning_output_n;
        foreach my $i (@next_normal) {
            my $blast_output = "${chunk_name}_psiout$i";
            push @returning_output_n, $blast_output;
        }
        say {$condor_normal_fh} "touch @returning_output_n";

        # second part of script
        my $condor_normal2 = <<"HTCondor_NORMAL2";
chmod +x psiblast

sleep 1
echo "{\$(pwd)" && echo "\$(ls -lha)}"

cd \$TMPDIR
echo "TMPDIR is:\$TMPDIR"
cp \$WORKDIR/* \$TMPDIR
tar -zxf in.tgz
tar -zxf \$HOME/newdata/$db_gz_name
HTCondor_NORMAL2

        say {$condor_normal_fh} $condor_normal2;

        # print PSI-BLAST+ jobs
        foreach my $i (@next_normal) {
            my $blast_cmd
              = qq{\$TMPDIR/psiblast -db \$TMPDIR/$db_name -query \$TMPDIR/${chunk_name}$i -out \$TMPDIR/${chunk_name}_psiout$i -evalue 1e-3 -outfmt 6 -seg yes -max_target_seqs 100000000 -num_iterations=4 -inclusion_ethresh=1e-3 &};
            say {$condor_normal_fh} $blast_cmd;
        }

        # third part of script
        my $condor_normal3 = <<"HTCondor_NORMAL3";

sleep 1
echo "\$(pgrep -fl psiblast)"
echo "{\$(pwd)" && echo "\$(ls -lha)}"

#echo "\$(env)"

wait
HTCondor_NORMAL3

        say {$condor_normal_fh} $condor_normal3;

        # copy output files back to workdir for HTCondor to return them back
        say {$condor_normal_fh} "cp @returning_output_n \$WORKDIR";

        $log->info("HTCondor normal PSI-BLAST+ shell script: $condor_normal_script");
    }    #end while for each script

    return;
}


### WORKING SUB ###
# Usage      : sge_hmmer();
# Purpose    : writes SGE SCRIPTS for HMMER files split_fasta() generated
# Returns    : nothing
# Parameters : ($param_href)
# Throws     : croaks if wrong number of arguments
# Comments   : writes SGE scripts to run HMMER on isabella
# See Also   : split_fasta()
sub sge_hmmer {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak( 'sge_hmmer() needs a hash_ref' ) unless @_ == 1;
    my ( $param_href ) = @_;

    my $out        = $param_href->{out}        or $log->logcroak('no out specified on command line!');
    my $chunk_name = $param_href->{chunk_name} or $log->logcroak('no chunk_name specified on command line!');
    my $cpu        = $param_href->{cpu}        or $log->logcroak('no cpu specified on command line!');
    my $cpu_l      = $param_href->{cpu_l}      or $log->logcroak('no cpu_l specified on command line!');
	my $num_l      = $param_href->{num_l}      // $log->logcroak('no num_l sent to sub!');   #can be 0 so checks for defindness
	my $num_n      = $param_href->{num_n}      // $log->logcroak('no num_n sent to sub!');
    my $db_path    = $param_href->{db_path}    or $log->logcroak('no db_path specified on command line!');
    my $db_name    = $param_href->{db_name}    or $log->logcroak('no db_name specified on command line!');
    my $app        = defined $param_href->{app} ? $param_href->{app} : 'phmmer';

	#build a queue for large seq
	my @large = 1 ..$num_l;
	my $script_num = 0;
	while (my @next_large = splice @large, 0, 1) {
		#say "@next_large";
		$script_num++;

		# generate input files
		my $input_files_large;
		foreach my $i (@next_large) {
			$input_files_large .= "$ENV{HOME}/in/${chunk_name}_large$i ";
		}

        #construct script for SGE large sequences
		my $sge_large = <<"SGE_LARGE";
#!/bin/sh

#\$ -N hmmer_${chunk_name}_lp$script_num
#\$ -cwd
#\$ -m abe
#\$ -M msestak\@irb.hr
#\$ -pe mpisingle $cpu_l
#\$ -R y
#\$ -l exclusive=1

mkdir -p \$TMPDIR/db
mkdir -p \$TMPDIR/out
mkdir -p \$TMPDIR/in
cp -uvR $db_path \$TMPDIR/db/
cp -uvR $input_files_large \$TMPDIR/in
SGE_LARGE

		my $sge_large_script = path( $out, $chunk_name . "_sge_hmmer_large$script_num.submit" )->canonpath;
    	open( my $sge_large_fh, ">", $sge_large_script ) or die "Can't open large output file $sge_large_script:$!\n";
    	say {$sge_large_fh} $sge_large;

		#print for all jobs
		foreach my $i (@next_large) {
			my $hmmer_cmd = qq{$app -o /dev/null --tblout \$TMPDIR/out/${chunk_name}_largehmmerout$i -E 0.001 --incE 0.001 --qformat fasta --tformat fasta --cpu $cpu_l \$TMPDIR/in/${chunk_name}_large$i \$TMPDIR/db/$db_name &};
			say {$sge_large_fh} $hmmer_cmd;
		}

		#print bash wait to wait on all background processes
		say {$sge_large_fh} "\nwait\n";

		#copy all back
		foreach my $i (@next_large) {
			my $cp_cmd = qq{cp --preserve=timestamps \$TMPDIR/out/${chunk_name}_largehmmerout$i $ENV{HOME}/out/};
			say {$sge_large_fh} $cp_cmd;
		}
		
		$log->info( "SGE large HMMER (jobs @next_large) script: $sge_large_script" );
	}   #end while


	#SECOND PART
	#build a queue for normal seq
	my @normal = 1 ..$num_n;
	my $script_num_n = 0;
	while (my @next_normal = splice @normal, 0, 1) {
		$script_num_n++;

		# generate input files
		my $input_files_normal;
		foreach my $i (@next_normal) {
			$input_files_normal .= "$ENV{HOME}/in/${chunk_name}$i ";
		}

		#construct script for SGE normal sequences
		my $sge_normal = <<"SGE_NORMAL";
#!/bin/sh

#\$ -N bl_${chunk_name}_p$script_num_n
#\$ -cwd
#\$ -m abe
#\$ -M msestak\@irb.hr
#\$ -pe mpisingle $cpu
#\$ -R y
#\$ -l exclusive=1

mkdir -p \$TMPDIR/db
mkdir -p \$TMPDIR/out
mkdir -p \$TMPDIR/in
cp -uvR $db_path \$TMPDIR/db/
cp -uvR $input_files_normal \$TMPDIR/in
SGE_NORMAL

		my $sge_normal_script = path( $out, $chunk_name . "_sge_hmmer_normal$script_num_n.submit" )->canonpath;
		open( my $sge_normal_fh, ">", $sge_normal_script ) or die "Can't open normal output file $sge_normal_script:$!\n";
		say {$sge_normal_fh} $sge_normal;

		#print all hmmer processes as background
		foreach my $i (@next_normal) {
			my $hmmer_cmd = qq{$app -o /dev/null --tblout \$TMPDIR/out/${chunk_name}_hmmerout$i -E 0.001 --incE 0.001 --qformat fasta --tformat fasta --cpu $cpu \$TMPDIR/in/${chunk_name}$i \$TMPDIR/db/$db_name &};
			say {$sge_normal_fh} $hmmer_cmd;
		}

		#print bash wait to wait on all background processes
		say {$sge_normal_fh} "\nwait\n";

		#copy all back
		foreach my $i (@next_normal) {
			my $cp_cmd = qq{cp --preserve=timestamps \$TMPDIR/out/${chunk_name}_hmmerout$i $ENV{HOME}/out/};
			say {$sge_normal_fh} $cp_cmd;
		}

		$log->info( "SGE normal HMMER (jobs @next_normal) script: $sge_normal_script" );

	}   #end while

    return;
}


1;
__END__

=encoding utf-8

=head1 NAME

PsiBlastHelper - It's modulino that splits fasta input file into number of chunks for BLAST, PSI-BLAST and HMMER to run them on cluster or grid

=head1 SYNOPSIS

    # test example for BLAST and PSI-BLAST
    lib/PsiBlastHelper.pm --infile=t/data/dm_splicvar --out=t/data/dm_chunks/ --chunk_name=dm --chunk_size=1000 --fasta_size 10000 --cpu 5 --cpu_l 5 --db_name=dbfull --db_path=/shared/msestak/db_full_plus --db_gz_name=dbfull_plus_format_new.tar.gz

    # test example for HMMER
    lib/PsiBlastHelper.pm --infile=t/data/dm_splicvar --out=t/data/dm_chunks/ --chunk_name=dm --chunk_size=1000 --fasta_size 10000 --cpu 5 --cpu_l 5 --db_name=dbfull --db_path=/shared/msestak/dbfull --db_gz_name=dbfull.gz

    # possible options for BLAST database
    --db_name=dbfull  --db_path=/shared/msestak/db_full_plus --db_gz_name=dbfull_plus_format_new.tar.gz
    --db_name=db90    --db_path=/shared/msestak/db90_plus    --db_gz_name=db90_plus_format_new.tar.gz
    --db_name=db90old --db_path=/shared/msestak/db90old      --db_gz_name=db90old_format.tar.gz

    # options for HMMER database
    --db_name=dbfull  --db_path=/shared/msestak/dbfull --db_gz_name=dbfull.gz

=head1 DESCRIPTION

PsiBlastHelper is modulino that splits fasta file (input) into a number of chunks for parallel BLAST++, PSI-BLAST or HMMER (default is all of them).
Chunks get short name + different number for each chunk (+ sufix '_large' if larger than -s or in top N sequences by size).
You need to provide input file, size of the chunk, chunk name and either top n or length of sequences to run separately. 
You also meed provide --cpu or --cpu_l to split manual SGE or HTCondor on this number of jobs. The idea here is to reduce a number of BLAST database copies (e.g., for every job),
which can lead to failed jobs if out of disk space on specific node.
You can also use -a (--append) to append remainder of sequences to last file or to create new file with this remainder, which is default.
After splitting sequences it also prints SGE and HTCondor jobs bash scripts.
All paths are hardcoded to ISABELLA cluster at tannat.srce.hr and CRO-NGI grid.

For help write:

    perl FastaSplit.pm -h
    perl FastaSplit.pm -m

=head1 LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

mocnii E<lt>msestak@irb.hrE<gt>

=cut

