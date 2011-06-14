
=pod 

=head1 NAME

Pinball::Walk

=head1 SYNOPSIS

Walk reconstructs the possible walks in a cluster graph and lists the read order for each walk.

=head1 DESCRIPTION

'Pinball::Walk' is the second step of the Pinball pipeline.

=cut

package Pinball::Walk;

use strict;
use File::Basename;
use Cwd;
use Time::HiRes qw(time gettimeofday tv_interval);

use base ('Bio::EnsEMBL::Hive::Process');

=head2 fetch_input

    Description : Implements fetch_input()

=cut

sub fetch_input {
    my $self = shift @_;

    $self->{starttime} = time();
    print STDERR "[init] ",time()-$self->{starttime}," secs...\n" if ($self->debug);

    my $clstreadsfile   = $self->param('clstreadsfile') || 
      die "'clstreadsfile' is an obligatory parameter, please set it in the input_id hashref";
    my $work_dir   = $self->param('work_dir') || 
      die "'work_dir' is an obligatory parameter, please set it in the input_id hashref";
#    $self->{param1} = $self->param('param1')  || die "'param1' is an obligatory parameter";

}

=head2 run

    Description : Implements run().

=cut

sub run {
    my $self = shift @_;

    my $worker_temp_directory = $self->worker_temp_directory;
    print STDERR "# $worker_temp_directory\n" if ($self->debug);
    chdir($worker_temp_directory);

    my $tag            = $self->param('tag');
    my $dust           = $self->param('dust');
    my $phred64        = $self->param('phred64');
    my $no_permute     = $self->param('no_permute');
    my $disk           = $self->param('disk');

    my $overlap        = $self->param('overlap');
    my $csize          = $self->param('csize');
    my $erate          = $self->param('erate');
    my $minreadlen     = $self->param('minreadlen');
    my $sga_executable = $self->param('sga_executable');
    my $sample         = $self->param('sample');
    my $work_dir       = $self->param('work_dir');

    my $clstreadsfile   = $self->param('clstreadsfile') || 
      die "'clstreadsfile' is an obligatory parameter, please set it in the input_id hashref";
    my $readsfile = $clstreadsfile; # for convenience
    my ($infilebase,$path,$type) = fileparse($clstreadsfile);
    my $cluster_id; $infilebase =~ /(cluster\-\d+)/; $cluster_id = $1;
    $tag = join("\.", $tag, $cluster_id, "w");

    my $cmd;
    my $dust_threshold    = '';
    my $sample_threshold  = '';
    my $phred64_flag      = '';
    my $permute_ambiguous = '';
    $dust_threshold       = "--dust-threshold=" . $dust if (length $dust > 0);
    $sample_threshold     = "--sample=" . $sample if (length $sample > 0);
    $phred64_flag         = "--phred64" if ($phred64);
    $permute_ambiguous    = "--permute-ambiguous" unless ($no_permute);

    # sga preprocess
    my $preprocess_log = "$tag.sga.preprocess.log";
    $cmd = "$sga_executable preprocess $sample_threshold $phred64_flag --min-length=$minreadlen $dust_threshold $permute_ambiguous $readsfile -o $tag.fq 2>$preprocess_log";
    print STDERR "$cmd\n" if ($self->debug);

    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga preprocess $!\n");  }

    # sga index
    # this will take about 500MB of memory
    my $disk_option = ''; $disk_option = "--disk=$disk" if (length($disk)>0);
    $cmd = "$sga_executable index -t 1 $disk_option $tag.fq";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga index $!\n");  }

    # sga rmdup
    $cmd = "$sga_executable rmdup -e $erate -t 1 $tag.fq";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga rmdup: $!\n");  }

    # sga overlap
    $cmd = "$sga_executable overlap -m $overlap -t 1 --exhaustive -e $erate $tag.rmdup.fa -o $tag.asqg.gz";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga overlap $!\n");  }

    $DB::single=1;1;
    # sga walk
    my $outdir = $path;
    my $walksfile = $outdir . "$cluster_id.walks";
    my $wdescfile = $outdir . "$cluster_id.wdesc";
    $cmd = "$sga_executable walk --prefix=$cluster_id --component-walks -o $walksfile --description-file=$wdescfile $tag.asqg.gz";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga walk $!\n");  }

    if (-e $walksfile && !-z $walksfile) {
      print STDERR "$walksfile\n" if ($self->debug);
      $self->param('walksfile', $walksfile);
    } else {
      $self->throw("error running sga walk\n $cmd\n #$walksfile\n $!\n");
    }

    if (-e $wdescfile && !-z $wdescfile) {
      print STDERR "$wdescfile\n" if ($self->debug);
      $self->param('wdescfile', $wdescfile);
    } else {
      $self->warn("error running sga walk\n $cmd\n #$wdescfile\n $!\n");
    }
}

=head2 write_output

    Description : Implements write_output()

=cut

sub write_output {  # nothing to write out, but some dataflow to perform:
    my $self = shift @_;

    my $work_dir = $self->param('work_dir');

    my $walksfile = $self->param('walksfile');
    my $wdescfile = $self->param('wdescfile');
    my @output_ids;
    push @output_ids, {'walksfile'=> $walksfile, 'wdescfile' => $wdescfile};
    print "Created jobs ", scalar @output_ids, "\n" if ($self->debug);
    $self->param('output_ids', \@output_ids);
    my $output_ids = $self->param('output_ids');
    $self->dataflow_output_id($output_ids, 1);

    $self->warning(scalar(@$output_ids).' jobs have been created');     # warning messages get recorded into 'job_message' table

    ## then flow into the branch#1 funnel; input_id would flow into branch#1 by default anyway, but we request it here explicitly:
    # $self->dataflow_output_id($self->input_id, 1);
}

1;

