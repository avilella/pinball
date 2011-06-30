#!/usr/bin/perl
use strict;
use Getopt::Long;
use Bio::SeqIO;

my ($inputfile,$debug);

GetOptions(
	   'i|input|inputfile:s' => \$inputfile,
           'd|debug:s' => \$debug,
          );

open FILE,$inputfile or die $!;
while (<FILE>) {
  chomp $_;
  my ($cluster_id,$num,$seq_id,$seq) = split(" ",$_);
  print "\>$seq_id.$cluster_id\n$seq\n";
}

close FILE;
