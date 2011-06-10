
=pod 

=head1 NAME

Pinball::Template

=head1 SYNOPSIS

The Template module does something.

=head1 DESCRIPTION

'Pinball::Template' is the XXX step of the Pinball pipeline.

=cut

package Pinball::Template;

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

#    $self->{param1} = $self->param('param1')  || die "'param1' is an obligatory parameter";

}

=head2 run

    Description : Implements run().

=cut

sub run {
    my $self = shift @_;

    my $param1         = $self->param('param1');
    my $param2         = $self->param('param2');
    my $sga_executable = $self->param('sga_executable');

    my $cmd;
    # sga something
    # my $outfile = $input_id . ".something";
    # $cmd = "$sga_executable something something > $outfile";
    print STDERR "$cmd\n" if ($self->debug);

    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running pinball template $!\n");  }

    if (-e $outfile && !-z $outfile) {
      print STDERR "$outfile\n" if ($self->debug);
      $self->param('outfile', $outfile);
    } else {
      $self->throw("error running pinball template\n $cmd\n #$outfile\n $!\n");
    }
}

=head2 write_output

    Description : Implements write_output()

=cut

sub write_output {  # nothing to write out, but some dataflow to perform:
    my $self = shift @_;

    my $minparam = $self->param('minparam');
    my $maxparam = $self->param('maxparam');
    my $work_dir = $self->param('work_dir');

    my $outfile = $self->param('outfile');
    my @output_files;
    my $readsnum;
    open FILE,$outfile or die $!;
    while (<FILE>) {
      # do something
    }
    close FILE;
    print "Created $work_dir ", scalar @output_files, "\n" if ($self->debug);

    $self->param('output_ids', \@output_files);
    my $output_ids = $self->param('output_ids');

    $self->dataflow_output_id($output_ids, 2);

    $self->warning(scalar(@$output_ids).' jobs have been created');     # warning messages get recorded into 'job_message' table

    ## then flow into the branch#1 funnel; input_id would flow into branch#1 by default anyway, but we request it here explicitly:
    # $self->dataflow_output_id($self->input_id, 1);
}

1;

