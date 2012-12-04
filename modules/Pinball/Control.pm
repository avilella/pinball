
=pod 

=head1 NAME

Pinball::Control

=head1 SYNOPSIS

The Control module aligns input/IgG control reads to the clusterwalksfa file and generates a BAM file for them.

=head1 DESCRIPTION

'Pinball::Control' is the 13th step of the Pinball pipeline.

=cut

package Pinball::Control;

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
    my $control   = $self->param('control') || 
      die "'control' is an obligatory parameter, please set it in the input_id hashref";

    my $search_executable   = $self->param('search_executable') || 
      die "'search_executable' is an obligatory parameter, please set it in the input_id hashref";

#    $self->{param1} = $self->param('param1')  || die "'param1' is an obligatory parameter";

}

=head2 run

    Description : Implements run().

=cut

sub run {
    my $self = shift @_;

    my $control             = $self->param('control');
    my $tag                 = $self->param('tag');
    my $work_dir            = $self->param('work_dir');
    my $sga_executable      = $self->param('sga_executable');
    my $phred64             = $self->param('phred64');
    my $minreadlen          = $self->param('minreadlen');
    my $search_executable   = $self->param('search_executable');
    my $samtools_executable = $self->param('samtools_executable') || $ENV{'HOME'}.'/pinball/samtools/samtools';
    my $z_option            = "-z 1";        # Here we use bwasw with default z-best 1
    my $onlyhits_option     = '-F 0x4';      # Here we only keep aligned reads

    my $output_dir = "$work_dir/output/";
    my $clusterwalksfa = $output_dir . join("\.",$tag,"clusters","fa");

    my ($infilebase,$path,$type) = fileparse($control,qr/\.[^.]*/);
    my $outputfilebase           = join("\.", $tag, "control");

    my $sam        = $output_dir . join("\.",$outputfilebase,"sam");
    my $tmp_bam    = $output_dir . join("\.",$outputfilebase,"tmp","bam");
    my $prefix_bam = $output_dir . join("\.",$outputfilebase);
    my $bam        = $output_dir . join("\.",$outputfilebase,"bam");

    my $cmd;

    chdir($work_dir) if (defined ($self->{start_dir}));

    ########################################
    # Preprocess control files
    my $phred64_flag        = '';
    $phred64_flag           = "--phred64" if ($phred64);
    my $permute_ambiguous      = "--permute-ambiguous";
    my $tag_fq = $work_dir . "/$tag.control.fq";
    my $preprocess_log = $work_dir . "/$tag.control.preprocess.log";
    my @readfiles = split(':',$control);
    my $outpipe = '1>'; my $errpipe = "2>$preprocess_log";
    my $count = 0;
    foreach my $file (@readfiles) {
      $cmd = "$sga_executable preprocess $phred64_flag --min-length=$minreadlen $permute_ambiguous $file $outpipe $tag_fq $errpipe";
      print STDERR "# $cmd\n" if ($self->debug);
      print STDERR "[preprocess control $file] ",time()-$self->{starttime}," secs...\n" if ($self->debug);
      my $ret = system("$cmd");

      if (0 != $ret) {
        print("$cmd\n\# $preprocess_log\n");
        $self->throw("error running sga preprocess $file $!\n");
      } else {
        $count++;
      }
      if ($count>0) {
        $outpipe = '1>>'; $errpipe = "2>> $preprocess_log";
        if ($self->debug > 1) {    $errpipe = ''; }
      }

    chdir($self->{start_dir});

    }

    ########################################
    # Align control preprocessed reads against previously indexed clusterwalksfa
    $cmd = "$search_executable bwasw $z_option $clusterwalksfa $tag_fq > $sam";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running pinball control $!\n");  }

    ########################################
    # Generate BAM file from alignments in SAM file (onlyhits)
    $cmd = "$samtools_executable view $onlyhits_option -bt $clusterwalksfa.fai $sam > $tmp_bam";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running pinball control $!\n");  }

    $cmd = "$samtools_executable sort $tmp_bam $prefix_bam";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running pinball control $!\n");  }

    $cmd = "$samtools_executable index $bam";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running pinball control $!\n");  }

    $cmd = "rm -f $tmp_bam"; $cmd .= " $sam" unless ($self->debug);
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running pinball control $!\n");  }

    print STDERR "# $bam\n" if ($self->debug);
    print STDERR "Try:\n$samtools_executable view $bam | wc -l\n" if ($self->debug);

    my $outfile = $bam;
    if (-e $outfile && !-z $outfile) {
      print STDERR "$outfile\n" if ($self->debug);
      $self->param('outfile', $outfile);
    } else {
      $self->throw("error running pinball control\n $cmd\n #$outfile\n $!\n");
    }

    return;
}

=head2 write_output

    Description : Implements write_output()

=cut

sub write_output {

}

1;

