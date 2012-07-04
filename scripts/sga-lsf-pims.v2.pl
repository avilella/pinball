#! /usr/bin/perl
use strict;
use Carp;
use List::Util qw[min];
use Getopt::Long;
use Pod::Usage;
use threads;
use Thread::Queue qw( );
use Thread::Semaphore;
use File::Basename;
use threads::shared;

my $default_queue="research-rh6";
my $read_length = 100;
my $help = 0;
my $num_threads = 8;
my $output_prefix = "final";
my $job_base_name = $$ . "_";
my $bsubWrapper = "jsbsub";  #
my $SGA="sga_mh11";
my $no_reverse = 0;
my $no_index = 0;
my $no_merge = 0;
my $dry_run = 0;
my $disk = 1000000;

my $error :shared;
$error = 0;


GetOptions('threads=i'    => \$num_threads,
           'no-reverse'   => \$no_reverse,
           'no-index'   => \$no_index,
           'no-merge'   => \$no_merge,
           'dry-run'   => \$dry_run,
           'sga_exe:s'   => \$SGA,
           'bsub_exe:s'   => \$bsubWrapper,
           'default_queue:s'   => \$default_queue,
           'disk:s'   => \$disk,
	   'help|?' => \$help
) or pod2usage(2);

pod2usage(1) if $help;

=head1 NAME

  sga-lsf-pims.pl - LSF based parallel Indexing and Merging Script

=head1 SYNOPSIS

sga-lsf-pims.pl [options] [files ...]

=head1 OPTIONS

=over 8

=item B<--help>
Print a brief help message and exits.

=item B<--threads>
threads to use [default: 8] 

=item B<--dry-run>
don't execute commands - just print them

=item B<--no-reverse>
don't build reverse index_jobs

=item B<--no-index>
don't run indexing

=item B<--no-merge>
don't run index merge

=back

=cut

my @files = @ARGV;


my $fList = {};
my $sList = {};
my $jobTicker = 0;
$fList->{$_} = 0 for @files;

$sList->{$_} = -s $_ for @files;

while ( my ($key, $value) = each %{$sList}){
	print "$key => $value \n";
}

if(!$no_index){
  $fList = indexFiles($fList);
}

#while ( my ($key, $value) = each %{$fList}){
#	print "$key => $value \n";
#}


if(!$no_merge){
  my $lastFile = mergeFiles($fList);
}

print "Finished processing files !!! \n" ;

exit 0;

sub indexFiles
{
  my ($files) = @_;
  my $retFiles = {};
  if(scalar(@files) == 0){
    print STDERR "No files to merge !!!\n";
    exit 1;
  }
#	while ( ($key, $value) = each %hash )
	foreach my $f ( keys %{$files} ){
	    my @orientations = ("--no-reverse");
	    if(!$no_reverse){
		push(@orientations,"--no-forward");
	    }
	    my @jArr = ();
	    for my $o (@orientations){
		my $jobName = $job_base_name . $jobTicker++;
		my $mem = index_memory_usage($f);
		my @carr = ($bsubWrapper,"--cpu", $num_threads,"--mem",$mem."G","--prefix", "bsub.idx_$jobName","--name",$jobName);
#		push @carr, ("--queue","long");

#		my $cmd = "sga index -t $num_threads -a BCR -d 5000000 $no_reverse_opt $f";
#		my @carr = ($bsubWrapper);
		if($dry_run){
		    push @carr,("--dry-run");
		}else {
#		    push @carr,("--dry-run");
		}
#		push @carr, ("$SGA index $o -t $num_threads -a BCR -d 5000000 $f");
		push @carr, ("$SGA index $o -t $num_threads -d $disk $f");
#		push @carr,("--cpu", $num_threads,"--mem",$mem."G","--queue","long");
#		push @carr,("--prefix", "bsub.idx_$jobName","--name",$jobName, $cmd);

#		my $cmds = {
#		    'a' => "$SGA index --no-forward -t $num_threads -a BCR -d 5000000 $no_reverse_opt $f",
#		    'b' => "$SGA index --no-reverse -t $num_threads -a BCR -d 5000000 $no_reverse_opt $f"
#		};
		push @jArr,$jobName;
		runArr(@carr)
	    }
	    $retFiles->{$f}=\@jArr;
	}
  return $retFiles;
}

sub mergeFiles
{
  my ($files) = @_;

  my $file_count = scalar(keys %{$files});

  if($file_count == 0){
    print STDERR "No files to merge !!!\n";
    exit 1;
  } elsif($file_count ==1){
    print STDERR "Nothing to merge with one file ",@{[ %{$files} ]}[0],"!!!\n";
    return @{[ %{$files} ]}[0];
  }

	my $num_merged = 0;
	my @files_to_merge = keys %{$files};
	my $cnt = scalar(keys %{$files});
	while(scalar(@files_to_merge) > 1) {
		# Get two elements from the front of the the array, merge them
		# and push the result back on
		my $file1 =  shift @files_to_merge; 
		my $file2 =  shift @files_to_merge;

		# dependencies
		my @dependencies = ();
		my @a = @{delete $files->{$file1}};
		my @b = @{delete $files->{$file2}};
		my $depstr = buildDepStr('done',@a,@b);

		## PREFIX output name
		my $out = sprintf("%s.merged.%d.%d", $output_prefix, $$, $num_merged++);
		if(scalar(@files_to_merge) == 0) {
		    # Merge into final.fa
		    $out = $output_prefix;
		}
		my $f = "$out.fa";
		print "Merging $file1 $file2 into $out.fa\n";
		
		my $sCnt = 0; # suppression flag position
		my @sArr = ('--no-forward --no-reverse', # just sequence file
			    '--no-sequence --no-reverse'); # just forward file		     
		push @sArr,'--no-sequence --no-forward' if(!$no_reverse); # just reverse file
		my @jArr = (); #Job name Array
		my $queue = $default_queue; # Queue
		for my $s (@sArr){
		    # build unique job name
		    my $jobName = $job_base_name . $jobTicker++."_".$sCnt;
		    push @jArr,$jobName;

		    my $mem = merge_memory_usage($file1,$file2)+1;
		    my $cpu = $num_threads;
		    if($sCnt == 0){ # sequence file merge -> low memory, low CPU
			$mem = "1";
			$cpu = 1;
		    } # 1 or 2 -> fwd / rev index merge: as normal

		    my $cmd = "$SGA merge $s -t $cpu -p $out $file1 $file2";
###############
# QUEUE selection not needed for EBI
###############
#		    if ($mem > 29){
#			$queue = "hugemem";
#		    }elsif($mem > 15) {
#			$queue = "long";
#		    }
		    my @carr = ($bsubWrapper);
		    if(length($depstr) > 0){
			push @carr,("--depend-end",$depstr);
		    }
		    if($dry_run){
			push @carr,("--dry-run");
#		    }else {
#		    push @carr,("--dry-run");
		    }
		    push @carr,("--cpu", $cpu,"--prefix", "bsub.merge_$jobName","--mem",$mem."G","--queue",$queue,"--name",$jobName,$cmd);
		    runArr(@carr);
		    ++$sCnt;
		}
		$depstr = buildDepStr('done',@jArr);
		my $jobName = $job_base_name . $jobTicker++."_r";
		@jArr = ($jobName);

		## Final job for single dependency afterwards + to delete merged files
		my @carr = ($bsubWrapper);
		push @carr,("--dry-run") if ($dry_run);
		push @carr,("--depend-end",$depstr) if (length($depstr) > 0);
		push @carr,("--prefix", "bsub.merge_$jobName","--name",$jobName,"$SGA merge -r --no-sequence --no-forward --no-reverse -p $out $file1 $file2");
		runArr(@carr);

		## Register file + dependency
		$files->{$f}=\@jArr;
		$sList->{$f} = ($sList->{$file1})+($sList->{$file2});
		push @files_to_merge,$f;
	}
  
#  return $return_file;
}

## Build LSF Dependency string
sub buildDepStr
{
    my $dopt = shift(@_);
    my $str = "";
    my @d = ();
    foreach my $x (@_){
	if($x != 0){
	    push @d," $dopt($x) ";
	}
    }
    return join(" && ",@d);
}

sub index_memory_usage 
{
	my ($file_name) = @_;
	use integer;
	my $mem = gb(estimate_memory_usage(estimateReads($sList->{$file_name})))+1; # +1 -> leave extra space
	$mem = 5 if($mem <5);
	return $mem;
}

sub merge_memory_usage 
{
	my $total = 0;
	foreach my $file_name ( @_){
		my $b = $sList->{$file_name};
		my $g = gb(
		    estimate_memory_usage(
			estimateReads(
			    $sList->{$file_name})
		    ));
#		print "GB: ".$b." -> ".$g. " for ".$file_name."\n";
		$total += $g +1; # -> leave extra space 
	}
	if($no_reverse){
	    $total /= 2;
	}

	use integer;
	$total *= 1; # to get an integer
	return $total>1?$total:1; # always 1GB min
}

# Transform bytes into gigabytes
sub gb
{
    my($x) = @_;
#		use integer;
    return $x / (1000 * 1000 * 1000);
}

# 135,100,235,900
# Estimate the memory usage in bytes of indexing the reads using sga-bcr
sub estimate_memory_usage
{
	my ($reads) = @_;
	my $or=2;
	my $N = $reads * $read_length;
	return (8*$or) * $reads +         # for BCRVector data structure
					($N / 4)*$or +                        # for 2 working BWTs, each of size $N / 4 bytes
					($N / 8)*$or + ($reads * 4)*$or;  # for the table of reads
}

# e.g. 310730542696 bytes final.fa: estimated (1,351,002,359 reads), acctual ( )
# Estimate the amount of reads based on the file size
sub estimateReads
{
	my ($s) = @_;
	use integer;
	# more likely to be 2.3 to 2.5, but better to overestimate amount of reads
	return ($s/$read_length)/2.3;
}

sub do_shutdown
{
  my @threads = @_;
  my $hasError = 0;
  foreach my $t (@threads){
    my @t_ret = $t->join();
    # expect 0 as return value
    if($t_ret[0] ne 0){
      print STDERR "Thread ",$t->tid()," returned an unexpected value: ",join(",",@t_ret),"\n";
      $hasError = 1;
    }
  }
  # if any error reported or found
  if($hasError || $error){	
    print STDERR "Problem detected during execution -> Exit!!!\n";
    exit 1;
  }
}

# Run a command                                                                                                                                              
sub run
{
    my($cmd) = @_;
    print $cmd . "\n";
    sleep 0.5;
    if($dry_run){
	sleep 0.3;
    } else {
      my $returnValue = system($cmd);
      if($returnValue != 0){
	$error = 1;
        croak("Failed to execute >$cmd<: $!\n");	
      }
    }
}
sub runArr
{
    my @cmd = @_;
    print join(";",@cmd) , "\n";
    if($dry_run){
	sleep 0.3;
    } else {
	my $returnValue = system(@cmd);
	if($returnValue != 0){
	    $error = 1;
	    croak("Failed to execute >",join(";",@cmd),"<: $!\n");	
	}
    }
}



