
=pod 

=head1 NAME

Pinball::ReportSearch

=head1 SYNOPSIS

The ReportSearch module generates a BAM file from all the search results from the Search module.

=head1 DESCRIPTION

'Pinball::ReportSearch' is the 12th step of the Pinball pipeline.

=cut

package Pinball::ReportSearch;

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

    my $reference = $self->param('reference')  || die "'reference' is an obligatory parameter";

}

=head2 run

    Description : Implements run().

=cut

sub run {
    my $self = shift @_;

    my $work_dir            = $self->param('work_dir');
    my $tag                 = $self->param('tag');
    my $reference           = $self->param('reference');
    my $samtools_executable = $self->param('samtools_executable') || $ENV{'HOME'}.'/pinball/samtools/samtools';
    my $bwa_z               = $self->param('bwa_z') || 1000;

    my $search_dir = "$work_dir/??/??/??/";
    my ($refinfilebase,$refpath,$reftype) = fileparse($reference,qr/\.[^.]*/);

    my $cmd;
    my $output_dir = "$work_dir/output/";
    my $ret = mkdir $output_dir;
    print STDERR "# mkdir $work_dir command gave ret value $ret\n" if ($self->debug);

    my $sam        = $output_dir . join("\.",$tag,$refinfilebase,$bwa_z,"sam");
    my $tmp_bam    = $output_dir . join("\.",$tag,$refinfilebase,$bwa_z,"tmp","bam");
    my $prefix_bam = $output_dir . join("\.",$tag,$refinfilebase,$bwa_z);
    my $bam        = $output_dir . join("\.",$tag,$refinfilebase,$bwa_z,"bam");

    # Add header
    $cmd = "find $search_dir -name \"\*.$refinfilebase.search.$bwa_z.bam\" 2>/dev/null | head -n 1";
    print STDERR "$cmd\n" if ($self->debug);
    my $one_file = `$cmd`;
    chomp $one_file;
    $self->throw("no files found $one_file") if (!defined $one_file || '' eq $one_file);
    $cmd = "$samtools_executable view -H $one_file > $sam";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running pinball reportsearch $!\n");  }
    $cmd = "find $search_dir -name \"\*.$refinfilebase.search.$bwa_z.bam\" -exec $samtools_executable view \{\} \\\; \>\> $sam";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running pinball reportsearch $!\n");  }

    $cmd = "$samtools_executable view -bt $reference.fai $sam > $tmp_bam";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running pinball reportsearch $!\n");  }

    $cmd = "$samtools_executable sort $tmp_bam $prefix_bam";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running pinball reportsearch $!\n");  }

    $cmd = "$samtools_executable index $bam";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running pinball reportsearch $!\n");  }

    $cmd = "rm -f $tmp_bam"; $cmd .= " $sam" unless ($self->debug);
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running pinball reportsearch $!\n");  }

    print STDERR "# $bam\n" if ($self->debug);
    print STDERR "Try:\n$samtools_executable view $bam | wc -l\n" if ($self->debug);

    my $outfile = $bam;
    if (-e $outfile && !-z $outfile) {
      print STDERR "$outfile\n" if ($self->debug);
      $self->param('outfile', $outfile);
    } else {
      $self->throw("error running pinball reportsearch\n $cmd\n #$outfile\n $!\n");
    }

}

=head2 write_output

    Description : Implements write_output()

=cut

sub write_output {  # nothing to write out, but some dataflow to perform:
    my $self = shift @_;

    # my $minparam = $self->param('minparam');
    # my $maxparam = $self->param('maxparam');
    # my $work_dir = $self->param('work_dir');

    # my $outfile = $self->param('outfile');
    # my @output_files;
    # my $readsnum;
    # open FILE,$outfile or die $!;
    # while (<FILE>) {
    #   # do something
    # }
    # close FILE;
    # print "Created $work_dir ", scalar @output_files, "\n" if ($self->debug);

    # $self->param('output_ids', \@output_files);
    # my $output_ids = $self->param('output_ids');

    # my $job_ids = $self->dataflow_output_id($output_ids, 2);
    # print join("\n",@$job_ids), "\n" if ($self->debug);

    # $self->warning(scalar(@$output_ids).' jobs have been created');     # warning messages get recorded into 'job_message' table

    ## then flow into the branch#1 funnel; input_id would flow into branch#1 by default anyway, but we request it here explicitly:
    # $self->dataflow_output_id($self->input_id, 1);
}

1;

