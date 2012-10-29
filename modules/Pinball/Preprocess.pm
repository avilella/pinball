
=pod 

=head1 NAME

Pinball::Preprocess

=head1 SYNOPSIS

Preprocess reads in fastq/fasta file by overlap

=head1 DESCRIPTION

'Pinball::Preprocess' is the first step of the Pinball pipeline.

=cut

package Pinball::Preprocess;

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

    $self->{start_dir} = getcwd;
    my $seq = $self->param('seq')  || die "'seq' is an obligatory parameter";

}

=head2 run

    Description : Implements run().

=cut


sub run {
    my $self = shift @_;

    print STDERR "[run init] ",time()-$self->{starttime}," secs...\n" if ($self->debug);

    my $seq            = $self->param('seq');
    my $tag            = $self->param('tag');
    my $dust           = $self->param('dust');
    my $phred64        = $self->param('phred64');
    my $permute        = $self->param('permute');
    my $disk           = $self->param('disk');
    my $threads        = $self->param('cluster_threads') || 1;
    my $overlap        = $self->param('overlap');
    my $csize          = $self->param('csize');
    my $erate          = $self->param('erate');
    my $minreadlen     = $self->param('minreadlen');
    my $sga_executable = $self->param('sga_executable');
    my $sample         = $self->param('sample');
    my $work_dir       = $self->param('work_dir');

    my $ret = mkdir $work_dir;
    print STDERR "# mkdir $work_dir command gave ret value $ret\n" if ($self->debug);

    my ($infilebase,$path,$type) = fileparse($self->param('seq'));
    if (!defined $tag) {
      $tag = $infilebase . ".clst";
    };

    my $cmd;
    my $dust_threshold      = '';
    my $sample_threshold    = '';
    my $phred64_flag        = '';
    my $permute_ambiguous   = '';
    $dust_threshold         = "--dust-threshold=" . $dust if (length $dust > 0);
    my $base_dust_threshold = ''; 
    $base_dust_threshold    = "--dust-threshold=" . ($dust*10) if (length $dust > 0);
    my $base_minreadlen     = $minreadlen - 2;
    $sample_threshold       = "--sample=" . $sample if (length $sample > 0);
    $phred64_flag           = "--phred64" if ($phred64);
    $permute_ambiguous      = "--permute-ambiguous" if ($permute);

    if (!defined $work_dir) {
      $work_dir = $path;
    }
    chdir($work_dir) if (defined ($self->{start_dir}));

    # cleanup before
    my $preprocess_log = $work_dir . "/$tag.sga.preprocess.log";
    my $preprocess_log_base = $work_dir . "/$tag.sga.preprocess.base.log";
    my $tag_fq = $work_dir . "/$tag.fq"; 
    my $tag_fq_base = $work_dir . "/$tag.base.fq";
    $cmd = "rm -f $tag_fq $preprocess_log";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->warn("trying to clean from sga preprocess $!\n");  }
    print STDERR "[preprocess cleanup] ",time()-$self->{starttime}," secs...\n" if ($self->debug);

    my @readfiles = split(':',$seq);
    # sga preprocess
    my $count = 0; my $outpipe = '1>'; my $errpipe = "2>$preprocess_log"; my $errpipe_base = "2>$preprocess_log_base";
    if ($self->debug > 1) {    $errpipe = '';     $errpipe_base = ''; }
    foreach my $file (@readfiles) {
      my $suffix_option = '';
      $DB::single=1;1;
      if ($file =~ /(\@\S+\@)(\S+)/) {
        $suffix_option = "--suffix='$1'";
        $file = $2;
      }
      # preprocess for cluster
      $cmd = "$sga_executable preprocess $suffix_option $sample_threshold $phred64_flag --min-length=$minreadlen $dust_threshold $permute_ambiguous $file $outpipe $tag_fq $errpipe";
      print STDERR "# $cmd\n" if ($self->debug);
      print STDERR "[preprocess $file] ",time()-$self->{starttime}," secs...\n" if ($self->debug);
      my $ret = system("$cmd");

      $cmd = "$sga_executable preprocess $suffix_option $sample_threshold $phred64_flag --min-length=$base_minreadlen $base_dust_threshold --permute-ambiguous $file $outpipe $tag_fq_base $errpipe_base";
      print STDERR "# $cmd\n" if ($self->debug);
      print STDERR "[preprocess base $file] ",time()-$self->{starttime}," secs...\n" if ($self->debug);
      my $ret_base = system("$cmd");
      if (0 != $ret || 0 != $ret_base) {
        print("$cmd\n\# $preprocess_log\n");
        $DB::single=1;1;
        $self->throw("error running sga preprocess $file $!\n");
      } else {
        $count++;
      }
      if ($count>0) {
        $outpipe = '1>>'; $errpipe = "2>> $preprocess_log"; $errpipe_base = "2>> $preprocess_log_base";
        if ($self->debug > 1) {    $errpipe = '';     $errpipe_base = ''; }
      }
    }

    if (-e $tag_fq && !-z $tag_fq) {
      print STDERR "$tag_fq\n" if ($self->debug);
      $self->param('tag_fq', $tag_fq);
      $self->param('tag_fq_base', $tag_fq_base);
    } else {
      $self->throw("error running sga preprocess: empty file\n $cmd\n #$tag_fq\n\# $preprocess_log\n $!\n");
    }

    chdir($self->{start_dir});

    return 0;
}

=head2 write_output

    Description : Implements write_output()

=cut

sub write_output {  # nothing to write out, but some dataflow to perform:
    my $self = shift @_;

    my $work_dir    = $self->param('work_dir');
    my $tag         = $self->param('tag');
    my $tag_fq      = $self->param('tag_fq');
    my $tag_fq_base = $self->param('tag_fq_base');

    my @output_ids;
    push @output_ids, { 'tag_fq'      => $tag_fq,      'work_dir' => $work_dir, 'tag' => $tag };
    push @output_ids, { 'tag_fq_base' => $tag_fq_base, 'work_dir' => $work_dir, 'tag' => "$tag.base" };
    $self->param('output_ids', \@output_ids);
    my $output_ids = $self->param('output_ids');

    my $job_ids = $self->dataflow_output_id($output_ids, 1);
    print join("\n",@$job_ids), "\n" if ($self->debug);

    $self->warning(scalar(@$output_ids).' job(s) created');     # warning messages get recorded into 'job_message' table

    ## then flow into the branch#1 funnel; input_id would flow into branch#1 by default anyway, but we request it here explicitly:
    # $self->dataflow_output_id($self->input_id, 1);
}

1;
