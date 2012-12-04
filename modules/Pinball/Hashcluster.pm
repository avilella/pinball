
=pod 

=head1 NAME

 Pinball::Hashcluster

=head1 SYNOPSIS

 The Hashcluster module does something.

=head1 DESCRIPTION

 'Pinball::Hashcluster' is the XXX step of the Pinball pipeline.

=cut

package Pinball::Hashcluster;

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

    $self->{clustersfile} = $self->param('clustersfile')  || die "'clustersfile' is an obligatory parameter";

}

=head2 run

    Description : Implements run().

=cut

sub run {
    my $self = shift @_;

    # nothing to run, all work is write out data
  }

sub write_output {  
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
        if (scalar @seq_list < $maxclustersize && $minclustersize < scalar @seq_list) {

          my $outfile = $self->create_outdir($last_cluster_id, $work_dir);
          open OUT, ">$outfile" or die $!; print OUT join('',@seq_list); close OUT;
          print STDERR "[ $readsnum - $last_cluster_id - $outfile - $diff secs...]\n" if ($self->debug);
          push @output_ids, { 'clst' => $outfile, 'work_dir' => $work_dir, 'tag' => $tag };
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

    my $job_ids = $self->dataflow_output_id($output_ids, 1);
    print join("\n",@$job_ids), "\n" if ($self->debug);

    $self->warning(scalar(@$output_ids).' jobs have been created');
}

sub create_outdir {
  my $self = shift;
  my $cluster_id = shift;
  my $work_dir   = shift;

  my $outddir;
  if ($self->{this_sizedir} >= $self->{sizedir}) {
    $self->{this_sizedir} = 0;
    $self->{filenum}++;
  }
  $self->{filenum} = sprintf("%06d", $self->{filenum});
  $self->{filenum} =~ /(\d{2})(\d{2})(\d{2})/; #
  my $dir1 = $1; my $dir2 = $2; my $dir3 = $3;
  my $outdir = $work_dir . "/$dir1/$dir2/$dir3";
  $self->{final_dir} = "$dir1:$dir2:$dir3";
  $outdir =~ s/\/\//\//g;
  unless (-d $outdir) {
    system("mkdir -p $outdir");
  }
  $self->{this_sizedir}++;
  my $outfile = $outdir . "/" . $cluster_id . ".clst";

  return $outfile;
}

1;

