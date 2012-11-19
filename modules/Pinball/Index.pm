=pod 

=head1 NAME

Pinball::Index

=head1 SYNOPSIS

The Index module does something.

=head1 DESCRIPTION

'Pinball::Index' is the XXX step of the Pinball pipeline.

=cut

package Pinball::Index;

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
    # # TODO: get rid of this debugging info
    # my $worker_id = $self->worker->dbID; my $dbname = $self->worker->db->dbname;
    # `touch /nfs/nobackup/ensembl/avilella/logs/index.$dbname.fetch_input.$worker_id`;
    my $tag = $self->param('tag')  || die "'tag' is an obligatory parameter";

}

=head2 run

    Description : Implements run().

=cut

sub run {
    my $self = shift @_;

    print STDERR "[run init] ",time()-$self->{starttime}," secs...\n" if ($self->debug);

    my $tag            = $self->param('tag');
    my $tag_fq         = $self->param('tag_fq');
    my $tag_fq_base    = $self->param('tag_fq_base');
    my $work_dir       = $self->param('work_dir');
    my $threads        = $self->param('cluster_threads') || 1;
    my $gigs           = $self->param('cluster_gigs') || 4;
    my $disk           = $self->param('disk') || 1000000;
    my $overlap        = $self->param('overlap');
    my $rmdupfiltering = $self->param('rmdupfiltering');

    my $fq = $tag_fq;
    if (!defined $tag_fq) {
      if (!defined $tag_fq_base) {
        die "'tag_fq' or 'tag_fq_base' obligatory parameter";
      } else {
        $fq = $tag_fq_base;
      }
    }

    my $estimated_readlen = int($overlap*1.8);

    # FIXME - trying to optimise for disk
    if ($self->input_job->retry_count > 0) {
      my $retry_count = $self->input_job->retry_count;
      $disk = $disk * 4 * $retry_count;
      print STDERR "# disk=$disk -- retry_count=$retry_count\n" if ($self->debug);
    }
    # if (!defined $disk || '' eq $disk) {
    #   $disk = int($gigs*100000000/(8*$estimated_readlen));
    #   print STDERR "# gigs $gigs $disk $disk\n" if ($self->debug);
    # }

    # $erate = 0.1 if (defined $tag_fq_base);
    my $sga_executable = $self->param('sga_executable');

    my $cmd;
    my ($infilebase,$path,$type) = fileparse($fq);
    if (!defined $work_dir) {
      $work_dir = $path;
    }
    chdir($work_dir) if (defined ($self->{start_dir}));

    # sga index
    # this will take about 500MB of memory
    my $disk_option = ''; $disk_option = "--disk=$disk" if (length($disk)>0);

    # cleanup before
    $cmd = "rm -f $tag.sai $tag.bwt";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->warn("trying to clean from sga index $!\n");  }
    print STDERR "[index cleanup] ",time()-$self->{starttime}," secs...\n" if ($self->debug);
    $DB::single=1;1;
    $self->db->dbc->disconnect_when_inactive(1);
    $cmd = "$sga_executable index -t $threads $disk_option $fq";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga index $!\n");  }
    $self->db->dbc->disconnect_when_inactive(0);
    print STDERR "[index] ",time()-$self->{starttime}," secs...\n" if ($self->debug);

    # cleanup before
    my $tag_filter = "$tag.filter.pass.fa";
    $cmd = "rm -f $tag_filter $tag.discard.fa $tag.filter.pass.sai $tag.filter.pass.bwt $tag.filter.pass.rbwt $tag.filter.pass.rsai";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->warn("trying to clean from sga filter.pass $!\n");  }
    print STDERR "[filter.pass cleanup] ",time()-$self->{starttime}," secs...\n" if ($self->debug);

    # sga filter/rmdup
    $cmd = "$sga_executable filter --no-kmer-check -t $threads $fq";

    # Rmdup is a more stringent filtering that gets rid of duplicate
    # reads, including non-identical reads that would still appear the
    # same when using an error-rate > 0
    if ('' ne $rmdupfiltering) {
      my $erate          = $self->param('erate');
      print STDERR "# Using 'sga rmdup' instead of 'sga filter no-kmer-check'\n" if ($self->debug);
        $cmd = "$sga_executable rmdup -e $erate -t $threads -p $tag -o $tag_filter $fq";
    }
    print STDERR "$cmd\n" if ($self->debug);
    $DB::single=1;1;
    $self->db->dbc->disconnect_when_inactive(1);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga filter: $!\n");  }
    $self->db->dbc->disconnect_when_inactive(0);
    print STDERR "[filter] ",time()-$self->{starttime}," secs...\n" if ($self->debug);

    # index something
    # my $outfile = $input_id . ".something";
    # $cmd = "$sga_executable something something > $outfile";
    # print STDERR "$cmd\n" if ($self->debug);

    # unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running pinball index $!\n");  }

    # # TODO: get rid of this debugging info
    # my $worker_id = $self->worker->dbID; my $dbname = $self->worker->db->dbname;
    # `touch /nfs/nobackup/ensembl/avilella/logs/index.$dbname.run.$worker_id`;

    $self->param('tag_filter', $tag_filter);

    chdir($self->{start_dir});
    return 0;
}

=head2 write_output

    Description : Implements write_output()

=cut

sub write_output {  # nothing to write out, but some dataflow to perform:
  my $self = shift @_;

  my $work_dir  = $self->param('work_dir');
  my $tag       = $self->param('tag');
  my $tag_filter = $self->param('tag_filter');
  my $tag_fq    = $self->param('tag_fq');

  #   # TODO: get rid of this debugging info
  # my $worker_id = $self->worker->dbID; my $dbname = $self->worker->db->dbname;
  # `touch /nfs/nobackup/ensembl/avilella/logs/index.$dbname.write_output.$worker_id`;
  return 0 if (!defined $tag_fq);

  print STDERR "[write_output - preparing tags] ",time()-$self->{starttime}," secs...\n" if ($self->debug);
  my @output_ids;
  push @output_ids, { 'tag_filter' => $tag_filter, 'work_dir' => $work_dir, 'tag' => $tag };
  $self->param('output_ids', \@output_ids);
  my $output_ids = $self->param('output_ids');
  my $job_ids = $self->dataflow_output_id($output_ids, 2);
  print join("\n",@$job_ids), "\n" if ($self->debug);

  $self->warning(scalar(@$output_ids).' job(s) created');
  print STDERR "[write_output - finished] ",time()-$self->{starttime}," secs...\n" if ($self->debug);

  #   # TODO: get rid of this debugging info
  # # my $worker_id = $self->worker->dbID; my $dbname = $self->worker->db->dbname;
  # `touch /nfs/nobackup/ensembl/avilella/logs/index.$dbname.done.$worker_id`;

  return 0;
}


1;

