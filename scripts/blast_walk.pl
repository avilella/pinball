#!/usr/bin/perl
use Getopt::Long;
use strict;
use File::Basename;
use Time::HiRes qw(time gettimeofday tv_interval);
use Bio::SeqIO;

my $self = bless {};
my $tmpdir = "/tmp";
my ($inputfile,$debug,$blast_exe,$reference,$tag);
$blast_exe = "/homes/avilella/src/ncbi-blast-2.2.23+/bin/blastn";
GetOptions(
	   'q|query|i|input|inputfile:s' => \$inputfile,
           'db|r|reference:s' => \$reference,
           'd|debug:s' => \$debug,
           'blast_exe:s' => \$blast_exe,
           'tag:s' => \$tag,
          );

my ($infilebase,$path,$type) = fileparse($inputfile,qr/\.[^.]*/);
my ($refinfilebase,$refpath,$reftype) = fileparse($reference,qr/\.[^.]*/);
$tag = $refinfilebase if (!defined $tag);
$infilebase =~ /(cluster\-\d+)/;
my $cluster_id = $1;

my $starttime = time();
print STDERR "[init] ",time()-$starttime," secs...\n" if ($debug); $starttime = time();

my $walkin = Bio::SeqIO->new
  (-file => $inputfile,
   -format => 'fasta');

my $tempdir = $self->worker_process_temp_directory;
my $tempfile = $tempdir . "$cluster_id.walk.fa";
my $walkout = Bio::SeqIO->new
  (-file => ">$tempfile",
   -format => 'fasta');

while (my $walk = $walkin->next_seq) {
  my $id = $walk->display_id;
  $id = $cluster_id . "." . $id;
  print STDERR $walk->display_id , "\n" if ($debug);
  $walk->display_id($id);
  $walkout->write_seq($walk);
}
$walkout->close;

my $cmd;
# blastn
$cmd = "$blast_exe -query $tempfile -db $reference -outfmt 7 | grep -v '^#' > $inputfile.$tag.blastn";
print STDERR "$cmd\n" if ($debug);
unless(system("$cmd") == 0) {    print("$cmd\n");    die("error running blastn $!\n");  }

$DB::single=1;1;

########################################
#### METHODS
########################################

sub DESTROY {
  my $self = shift;
  $self->cleanup_worker_process_temp_directory;
}

sub worker_process_temp_directory {
  my $self = shift;
  
  unless(defined($self->{'_tmp_dir'}) and (-e $self->{'_tmp_dir'})) {
    #create temp directory to hold fasta databases
    $self->{'_tmp_dir'} = $tmpdir . "/worker.$$/";
    mkdir($self->{'_tmp_dir'}, 0777);
    throw("unable to create ".$self->{'_tmp_dir'}) unless(-e $self->{'_tmp_dir'});
  }
  return $self->{'_tmp_dir'};
}


sub cleanup_worker_process_temp_directory {
  my $self = shift;
  if($self->{'_tmp_dir'}) {
    my $cmd = "rm -r ". $self->{'_tmp_dir'};
    system($cmd) if (-e $self->{'_tmp_dir'});
  }
}
