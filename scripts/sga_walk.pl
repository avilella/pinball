#!/usr/local/bin/perl
use Getopt::Long;
use strict;
use File::Basename;

my $self = bless {};

my ($readsfile,$no_permute,$dust,$sample,$readsfile,$onlyindex,$minreadlen,$tag,
    $exhaustive_overlap,$overlap,$csize,$threads,$debug,$this_tmpdir);
my $disk = 1000000;
$threads = 1;
$overlap = 31;
# TODO: skip altogether if csize is below minimum
$csize = 50;
my $erate = 0;
$minreadlen = 30;

my $sga_executable      = "/homes/avilella/src/sga/latest/sga/src/sga";
GetOptions(
	   'i|r|reads|readsfile:s' => \$readsfile,
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
	   'no_permute' => \$no_permute,
           'd|debug:s' => \$debug,
           'onlyindex:s' => \$onlyindex,
	   'sga_exe:s' => \$sga_executable,
	   'this_tmpdir:s' => \$this_tmpdir,
          );

$self->{_tmp_dir} = $this_tmpdir if (defined $this_tmpdir);
$self->worker_process_temp_directory(1);
my ($infilebase,$path,$type) = fileparse($readsfile);
if (!defined $tag) {
  $tag = $infilebase . ".w";
};
my $exhaustive = '';
$exhaustive = '--exhaustive' if (1 == $exhaustive_overlap);

my $rerun_string = '';

my $cmd;
my $dust_threshold = '';
my $sample_threshold = '';
my $permute_ambiguous = '';
$dust_threshold = "--dust-threshold=" . $dust if (length $dust > 0);
$sample_threshold = "--sample=" . $sample if (length $sample > 0);
$permute_ambiguous = "--permute-ambiguous" unless ($no_permute);
# sga preprocess
# $cmd = "$sga_executable preprocess -p 0 $sample_threshold --min-length=$minreadlen $dust_threshold $permute_ambiguous $readsfile -o $tag.fq 2>$tag.preprocess.txt";
$cmd = "$sga_executable preprocess $sample_threshold --min-length=$minreadlen $dust_threshold $permute_ambiguous $readsfile -o $tag.fq 2>$tag.preprocess.txt";
print STDERR "$cmd\n" if ($debug);
$rerun_string .= "$cmd\n";
unless(system("$cmd") == 0) {    print("$cmd\n");    die("error running sga preprocess: $!\n");  }

# sga index
# this will take about 500MB of memory
$cmd = "$sga_executable index -t $threads --disk=$disk $tag.fq";
print STDERR "$cmd\n" if ($debug);
$rerun_string .= "$cmd\n";
unless(system("$cmd") == 0) {    print("$cmd\n");    die("error running sga index: $!\n");  }
exit 0 if ($onlyindex);

# sga rmdup
$cmd = "$sga_executable rmdup -e $erate -t $threads $tag.fq";
print STDERR "$cmd\n" if ($debug);
$rerun_string .= "$cmd\n";
unless(system("$cmd") == 0) {    print("$cmd\n");    die("error running sga rmdup: $!\n");  }

# sga overlap
$cmd = "$sga_executable overlap -m $overlap -t $threads $exhaustive -e $erate $tag.rmdup.fa -o $tag.asqg.gz";
print STDERR "$cmd\n" if ($debug);
$rerun_string .= "$cmd\n";
unless(system("$cmd") == 0) {    print("$cmd\n");    die("error running sga overlap: $!\n");  }

# sga walk
my $outdir = $path;
#$cmd = "$sga_executable walk --prefix=$tag --component-walks -o $outdir/$tag.walks --description-file=$outdir/$tag.wdesc $tag.asqg.gz";
$cmd = "$sga_executable walk --prefix=$tag --component-walks -o $outdir/$tag.walks --sam=$outdir/$tag.sam $tag.asqg.gz";
print STDERR "$cmd\n" if ($debug);
$rerun_string .= "$cmd\n";
unless(system("$cmd") == 0) {    print("$cmd\n");    die("error running sga walk: $!\n");  }

print STDERR "###\n" if ($debug);
print STDERR $rerun_string if ($debug);

sub DESTROY {
  print STDERR "###\n" if ($debug);
  print STDERR $rerun_string if ($debug);
}

$self->cleanup_worker_process_temp_directory(1) unless defined($this_tmpdir);

1;

########################################
#### METHODS
########################################

sub worker_process_temp_directory {
  my $self = shift;
  my $docwd = shift;

  unless(defined($self->{'_tmp_dir'}) and (-e $self->{'_tmp_dir'})) {
    #create temp directory to hold fasta databases
    $self->{'_tmp_dir'} = "/tmp/worker.$$/";
    mkdir($self->{'_tmp_dir'}, 0777);
    die("unable to create ".$self->{'_tmp_dir'}) unless(-e $self->{'_tmp_dir'});
  }
  if ($docwd) {
    use Cwd;
    $self->{oldwd} = getcwd;
    chdir($self->{'_tmp_dir'});
  }

  return $self->{'_tmp_dir'};
}


sub cleanup_worker_process_temp_directory {
  my $self = shift;
  my $docwd = shift;

  if ($docwd) {
    use Cwd;
    chdir($self->{'oldwd'});
  }

  if($self->{'_tmp_dir'}) {
    my $cmd = "rm -r ". $self->{'_tmp_dir'};
    system($cmd);
  }
}
