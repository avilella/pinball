#!/usr/bin/perl
use strict;
use Getopt::Long;
use Bio::SeqIO;

my ($inputfile,$debug,$cluster_id,$limit,$format);
$format = 'fasta';
$limit = 999999999999;
GetOptions(
	   'i|input|inputfile:s' => \$inputfile,
           'd|debug:s' => \$debug,
           'c|cluster_id:s' => \$cluster_id,
           'limit:s' => \$limit,
           'format:s' => \$format,
          );

my $io = Bio::SeqIO->new
(-file => $inputfile,
 -format => $format);
my $hash;
my $count = 0;
while (my $seq = $io->next_seq) {
  last if ($count++ >= $limit);
  my $display_id = $seq->display_id;
  my ($cluster,$cid,$walk,$wid) = split("-",$display_id);
  my $this_cluster_id;
  $DB::single=1;1;
  if (defined($cluster_id)) {
    $this_cluster_id = $cluster_id;
  } else {
    $this_cluster_id = "$cluster\-$cid";
  }
  my $sequence = $seq->seq;
  $hash->{$this_cluster_id}{$display_id} = $sequence;
}

foreach my $cluster_id (keys %$hash) {
  my @keys = keys %{$hash->{$cluster_id}};
  my $num = scalar @keys;
  foreach my $walk_id (@keys) {
    my $sequence = $hash->{$cluster_id}{$walk_id};
    print "$cluster_id\t$num\t$walk_id\t$sequence\n";
  }
}
