#!/usr/bin/perl
use Getopt::Long;
use strict;
use File::Basename;
use Time::HiRes qw(time gettimeofday tv_interval);

my $self = bless {};
my ($inputfile,$debug,$maxsize,$minsize,$outdir);
my $debug = 0;
$self->{outdir} = ".";
$self->{sizedir} = 10;
my $tmpdir = '/tmp';
$maxsize = 100000;
$minsize = 5;
$self->{hashfile} = "hashlist";
GetOptions(
	   'i|input|inputfile:s' => \$inputfile,
           'tmpdir:s'  => \$tmpdir,
	   'maxsize:s' => \$maxsize,
	   'minsize:s' => \$minsize,
	   's|sizedir:s' => \$self->{sizedir},
           'd|debug:s' => \$debug,
	   'o|outdir:s' => \$self->{outdir},
	   'l|hashfile:s' => \$self->{hashfile},
          );
my $starttime = time();
print STDERR "[init] ",time()-$starttime," secs...\n" if ($debug); $starttime = time();

open FILE, $inputfile or die $!;
my $hf = $self->{hashfile};
open HASHFILE, ">$hf" or die $!;
my $last_cluster_id = 'none';
my @seq_list;

my $readsnum = 0;
$self->{filenum} = sprintf("%06d", 0);
while (<FILE>) {
  my $diff = time()-$starttime;
  chomp $_;
  my ($cluster_id,$cluster_size,$read_name,$read_sequence) = split("\t",$_);
  $cluster_id =~ s/\:/\./g;
  if ($cluster_id ne $last_cluster_id) {
    $last_cluster_id = $cluster_id;
    if (defined @seq_list) {
      if (scalar @seq_list < $maxsize && $minsize < scalar @seq_list) {
        $DB::single=$debug;1;
        my $outfile = $self->create_outdir($last_cluster_id);
        open OUT, ">$outfile" or die $!; print OUT join('',@seq_list); close OUT;
        print STDERR "[ $readsnum - $last_cluster_id - $outfile - $diff secs...]\n" if ($debug);
        print HASHFILE "$outfile\n";
      }
    }
    @seq_list = undef;
  }
  push @seq_list, ">$read_name\n$read_sequence\n";
  $readsnum++;
}
close FILE;
close HASHFILE;

print "Final dir:\n";
print $self->{final_dir}, "\n";


########################################
#### METHODS
########################################

sub create_outdir {
  my $self = shift;
  my $cluster_id = shift;

  my $outddir;
  if ($self->{this_sizedir} >= $self->{sizedir}) {
    $self->{this_sizedir} = 0;
    $self->{filenum}++;
  }
  $self->{filenum} = sprintf("%06d", $self->{filenum});
  $self->{filenum} =~ /(\d{2})(\d{2})(\d{2})/; #
  my $dir1 = $1; my $dir2 = $2; my $dir3 = $3;
  my $outdir = $self->{outdir} . "/$dir1/$dir2/$dir3";
  $self->{final_dir} = "$dir1:$dir2:$dir3";
  $outdir =~ s/\/\//\//g;
  unless (-d $outdir) {
    system("mkdir -p $outdir");
  }
  $self->{this_sizedir}++;
  my $outfile = $outdir . "/" . $cluster_id . ".fa";
  return $outfile;
}
