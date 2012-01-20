#!/usr/local/bin/perl
use Getopt::Long;
use strict;
use File::Basename;

my ($readsfile,$phred64,$no_permute,$dust,$sample,$readsfile,$indexfilteronly,$onlyindex,$minreadlen,$tag,$exhaustive_overlap,$overlap,$csize,$threads,$debug,$paired);
my $disk = 1000000;
$threads = 1;
$overlap = 31;
$csize = 50;
my $erate = 0;
$minreadlen = 30;

my $sga_executable      = "/homes/avilella/src/sga/latest/sga/src/sga";
GetOptions(
	   'r|reads|readsfile:s' => \$readsfile,
	   't|tag:s' => \$tag,
	   'minreadlen:s' => \$minreadlen,
	   'threads:s' => \$threads,
	   'exhaustive:s' => \$exhaustive_overlap,
	   'overlap:s' => \$overlap,
	   'csize:s' => \$csize,
	   'erate:s' => \$erate,
	   'dust:s' => \$dust,
	   'disk:s' => \$disk,
	   'sample:s' => \$sample,
	   'phred64' => \$phred64,
	   'paired' => \$paired,
	   'no_permute' => \$no_permute,
           'd|debug:s' => \$debug,
           'onlyindex:s' => \$onlyindex,
           'indexfilteronly:s' => \$indexfilteronly,
	   'sga_exe:s' => \$sga_executable,
          );

my ($infilebase,$path,$type) = fileparse($readsfile);
if (!defined $tag) {
  $tag = $infilebase . ".clst";
};
my $exhaustive = '';
$exhaustive = '--exhaustive' if (1 == $exhaustive_overlap);
my $self = bless {};
#my $tmp_dir = $self->worker_process_temp_directory;

my $rerun_string = '';

my $cmd;
my $dust_threshold = '';
my $sample_threshold = '';
my $phred64_flag = '';
my $paired_flag = '';
my $permute_ambiguous = '';
$dust_threshold = "--dust-threshold=" . $dust if (length $dust > 0);
$sample_threshold = "--sample=" . $sample if (length $sample > 0);
$phred64_flag = "--phred64" if ($phred64);
$permute_ambiguous = "--permute-ambiguous" unless ($no_permute);
if ($paired) { $readsfile =~ s/\:/\ /; $paired_flag = '--pe-mode=1'};
# sga preprocess
$cmd = "$sga_executable preprocess $sample_threshold $paired_flag $phred64_flag --min-length=$minreadlen $dust_threshold $permute_ambiguous $readsfile -o $tag.fq 2>$tag.preprocess.txt";
print STDERR "$cmd\n" if ($debug);
$rerun_string .= "$cmd\n";
$DB::single=1;1;
unless(system("$cmd") == 0) {    print("$cmd\n");    throw("error running sga preprocess: $!\n");  }

# sga index
# this will take about 500MB of memory
$cmd = "$sga_executable index -t $threads --disk=$disk $tag.fq";
print STDERR "$cmd\n" if ($debug);
$rerun_string .= "$cmd\n";
unless(system("$cmd") == 0) {    print("$cmd\n");    throw("error running sga index: $!\n");  }

exit 0 if ($onlyindex);

# sga rmdup
#$cmd = "$sga_executable rmdup -e $erate -t $threads";
$cmd = "$sga_executable filter --no-kmer-check -t $threads $tag.fq";
print STDERR "$cmd\n" if ($debug);
$rerun_string .= "$cmd\n";
unless(system("$cmd") == 0) {    print("$cmd\n");    throw("error running sga filter: $!\n");  }

exit 0 if ($indexfilteronly);

# sga cluster
$cmd = "$sga_executable cluster -m $overlap -c $csize -e $erate -t $threads $tag.filter.pass.fa -o $tag.d$dust.$csize.$overlap.e$erate.clusters";
print STDERR "$cmd\n" if ($debug);
$rerun_string .= "$cmd\n";
unless(system("$cmd") == 0) {    print("$cmd\n");    throw("error running sga cluster: $!\n");  }

print STDERR "###\n" if ($debug);
print STDERR $rerun_string if ($debug);
$DB::single=1;1;#??

sub DESTROY {
  print STDERR "###\n" if ($debug);
  print STDERR $rerun_string if ($debug);
}

#$self->cleanup_worker_process_temp_directory;

########################################
#### METHODS
########################################

sub worker_process_temp_directory {
  my $self = shift;
  
  unless(defined($self->{'_tmp_dir'}) and (-e $self->{'_tmp_dir'})) {
    #create temp directory to hold fasta databases
    $self->{'_tmp_dir'} = "/tmp/worker.$$/";
    mkdir($self->{'_tmp_dir'}, 0777);
    throw("unable to create ".$self->{'_tmp_dir'}) unless(-e $self->{'_tmp_dir'});
  }
  return $self->{'_tmp_dir'};
}


sub cleanup_worker_process_temp_directory {
  my $self = shift;
  if($self->{'_tmp_dir'}) {
    my $cmd = "rm -r ". $self->{'_tmp_dir'};
    system($cmd);
  }
}
