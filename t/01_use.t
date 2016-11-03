#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;

my $module = 'PsiBlastHelper';
my @subs = qw( 
  main
  init_logging
  get_parameters_from_cmd
  split_fasta
  sge_blast_combined
  condor_blast_combined
  condor_blast_combined_sh
);

use_ok( $module, @subs);

foreach my $sub (@subs) {
    can_ok( $module, $sub);
}

done_testing();
