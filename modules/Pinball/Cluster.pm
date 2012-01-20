
=pod 

=head1 NAME

Pinball::Cluster

=head1 SYNOPSIS

Cluster reads in fastq/fasta file by overlap

=head1 DESCRIPTION

'Pinball::Cluster' is the first step of the Pinball pipeline.

=cut

package Pinball::Cluster;

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

    my $tag_filter = $self->param('tag_filter') || die "'tag_filter' is an obligatory parameter";

}

=head2 run

    Description : Implements run().

=cut

sub run {
    my $self = shift @_;

    print STDERR "[run init] ",time()-$self->{starttime}," secs...\n" if ($self->debug);

    my $clusterfile_topup    = $self->param('clusterfile_topup');
    if (defined $clusterfile_topup) {
      # We did a manual top_up, so we don't actually call the cluster method,
      # just skip to write_output
      return 1;
    }

    my $tag_filter      = $self->param('tag_filter');
    my $tag            = $self->param('tag');
    my $threads        = $self->param('cluster_threads') || 1;
    my $overlap        = $self->param('overlap');
    my $csize          = $self->param('csize');
    my $erate          = $self->param('erate');
    my $sga_executable = $self->param('sga_executable');
    my $work_dir       = $self->param('work_dir');

    my ($infilebase,$path,$type) = fileparse($self->param('tag_filter'));
    my $cmd;
    if (!defined $work_dir) {
      $work_dir = $path;
    }
    chdir($work_dir);

    my $verbose_flag = '-v'; $verbose_flag = '-v' if ($self->debug);
    # sga cluster
    # $cmd = "$sga_executable cluster $verbose_flag -m $overlap -c $csize -e $erate -t $threads $tag.filter.pass.fa -o $tag.d$dust.$csize.$overlap.e$erate.clusters";
    my $clustersfile = $work_dir . "/$tag.clusters";
    $cmd = "$sga_executable cluster -m $overlap -c $csize -e $erate -t $threads $tag_filter -o $clustersfile";
    print STDERR "$cmd\n" if ($self->debug);
    $self->db->dbc->disconnect_when_inactive(1);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga cluster: $!\n");  }
    $self->db->dbc->disconnect_when_inactive(0);
    print STDERR "[cluster] ",time()-$self->{starttime}," secs...\n" if ($self->debug);

    if (-e $clustersfile && !-z $clustersfile) {
      print STDERR "$clustersfile\n" if ($self->debug);
      $self->param('clustersfile', $clustersfile);
    } else {
      $self->throw("error running sga cluster\n $cmd\n #$clustersfile\n $!\n");
    }
}

=head2 write_output

    Description : Implements write_output()

=cut

sub write_output {  # nothing to write out, but some dataflow to perform:
    my $self = shift @_;

    my $minclustersize = $self->param('minclustersize') || $self->param('csize');
    my $maxclustersize = $self->param('maxclustersize');
    my $work_dir       = $self->param('work_dir');
    my $tag            = $self->param('tag');

    # Num of clusters per hashed dir
    $self->{sizedir} = 200;

    my $clustersfile = $self->param('clustersfile');

    my $clusterfile_topup    = $self->param('clusterfile_topup');
    $clustersfile = $clusterfile_topup if (defined $clusterfile_topup);
    $DB::single=1;1;
    my $last_cluster_id = 'none';
    my @seq_list;
    my @output_ids;
    my $readsnum;
    open FILE,$clustersfile or die $!;
    while (<FILE>) {
      my $diff = time()-$self->{starttime};
      chomp $_;
      my ($cluster_id,$cluster_size,$read_name,$read_sequence) = split("\t",$_);
      $cluster_id =~ s/\:/\./g;
      if ($cluster_id ne $last_cluster_id) {
        $last_cluster_id = $cluster_id;
        if (defined @seq_list) {
          if (scalar @seq_list < $maxclustersize && $minclustersize < scalar @seq_list) {

            my $outfile = $self->create_outdir($last_cluster_id, $work_dir);
            open OUT, ">$outfile" or die $!; print OUT join('',@seq_list); close OUT;
            print STDERR "[ $readsnum - $last_cluster_id - $outfile - $diff secs...]\n" if ($self->debug);
            push @output_ids, { 'clst' => $outfile, 'work_dir' => $work_dir, 'tag' => $tag };
          }
        }
        @seq_list = undef;
      }
      push @seq_list, ">$read_name\n$read_sequence\n";
      $readsnum++;
    }
    close FILE;
    print "Created $work_dir ", $self->{final_dir}, "\n" if ($self->debug);

    $self->param('output_ids', \@output_ids);
    my $output_ids = $self->param('output_ids');

    my $job_ids = $self->dataflow_output_id($output_ids, 2);
    print join("\n",@$job_ids), "\n" if ($self->debug);

    $self->warning(scalar(@$output_ids).' jobs have been created');
}

sub write_output {
    my $self = shift @_;

    my $work_dir     = $self->param('work_dir');
    my $tag          = $self->param('tag');
    my $clustersfile = $self->param('clustersfile');

    my @output_ids;
    push @output_ids, { 'clustersfile' => $clustersfile, 'work_dir' => $work_dir, 'tag' => $tag };
    $self->param('output_ids', \@output_ids);
    my $output_ids = $self->param('output_ids');

    my $job_ids = $self->dataflow_output_id($output_ids, 2);
    print join("\n",@$job_ids), "\n" if ($self->debug);

    $self->warning(scalar(@$output_ids).' job(s) created');     # warning messages get recorded into 'job_message' table

    ## then flow into the branch#1 funnel; input_id would flow into branch#1 by default anyway, but we request it here explicitly:
    # $self->dataflow_output_id($self->input_id, 1);
}



1;

