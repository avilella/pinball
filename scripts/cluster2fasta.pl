#!/usr/bin/perl
use strict;
use Getopt::Long;
use Bio::SeqIO;

my ($inputfile,$debug,$minsize,$maxsize);

GetOptions(
	   'i|input|inputfile:s' => \$inputfile,
	   'min_csize:s' => \$minsize,
	   'max_csize:s' => \$maxsize,
           'd|debug:s' => \$debug,
          );

open FILE,$inputfile or die $!;
while (<FILE>) {
  chomp $_;
  my ($cluster_id,$num,$seq_id,$seq) = split(" ",$_);
  if (defined $minsize) {
    next if ($num < $minsize);
  }
  if (defined $maxsize) {
    next if ($num > $maxsize);
  }
  print "\>$seq_id.$cluster_id\n$seq\n";
}

close FILE;
