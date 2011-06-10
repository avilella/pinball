
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

    $self->{readsfile} = $self->param('readsfile')  || die "'readsfile' is an obligatory parameter";

}

=head2 run

    Description : Implements run().

=cut

sub run {
    my $self = shift @_;

    my $readsfile      = $self->param('readsfile');
    my $tag            = $self->param('tag');
    my $dust           = $self->param('dust');
    my $phred64        = $self->param('phred64');
    my $no_permute     = $self->param('no_permute');
    my $disk           = $self->param('disk');
    my $threads        = $self->param('cluster_threads') || 1;
    my $overlap        = $self->param('overlap');
    my $csize          = $self->param('csize');
    my $erate          = $self->param('erate');
    my $minreadlen     = $self->param('minreadlen');
    my $sga_executable = $self->param('sga_executable');
    my $sample         = $self->param('sample');
    my $work_dir       = $self->param('work_dir');

    my ($infilebase,$path,$type) = fileparse($self->param('readsfile'));
    if (!defined $tag) {
      $tag = $infilebase . ".clst";
    };

    my $cmd;
    my $dust_threshold    = '';
    my $sample_threshold  = '';
    my $phred64_flag      = '';
    my $permute_ambiguous = '';
    $dust_threshold       = "--dust-threshold=" . $dust if (length $dust > 0);
    $sample_threshold     = "--sample=" . $sample if (length $sample > 0);
    $phred64_flag         = "--phred64" if ($phred64);
    $permute_ambiguous    = "--permute-ambiguous" unless ($no_permute);

    if (!defined $work_dir) {
      $work_dir = $path;
    }
    chdir($work_dir);

    my @readfiles = split(':',$readsfile);
    # sga preprocess
    my $count = 0; my $outpipe = '1>'; my $errpipe = '2>';
    foreach my $file (@readfiles) {
      my $preprocess_log = $work_dir . "/$tag.sga.preprocess.log";
      $cmd = "$sga_executable preprocess $sample_threshold $phred64_flag --min-length=$minreadlen $dust_threshold $permute_ambiguous $file $outpipe $tag.fq $errpipe $preprocess_log";
      print STDERR "$cmd\n" if ($self->debug);
      unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga preprocess $!\n");  } else {
        print STDERR "[Preprocessed $file] ",time()-$self->{starttime}," secs...\n" if ($self->debug);
        $count++;
      }
      if ($count>0) {
        $outpipe = '1>>'; $errpipe = '2>>';
      }
    }

    # sga index
    # this will take about 500MB of memory
    my $disk_option = ''; $disk_option = "--disk=$disk" if (length($disk)>0);
    $cmd = "$sga_executable index -t $threads $disk_option $tag.fq";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga index $!\n");  }

    # sga rmdup
    $cmd = "$sga_executable rmdup -e $erate -t $threads $tag.fq";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga rmdup: $!\n");  }

    # sga cluster
    # $cmd = "$sga_executable cluster -m $overlap -c $csize -e $erate -t $threads $tag.rmdup.fa -o $tag.d$dust.$csize.$overlap.e$erate.clusters";
    my $clustersfile = $work_dir . "/$tag.clusters";
    $cmd = "$sga_executable cluster -m $overlap -c $csize -e $erate -t $threads $tag.rmdup.fa -o $clustersfile";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga cluster: $!\n");  }

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

    my $minclustersize = $self->param('minclustersize');
    my $maxclustersize = $self->param('maxclustersize');
    my $work_dir       = $self->param('work_dir');

    # Num of clusters per hashed dir
    $self->{sizedir} = 200;

    my $clustersfile = $self->param('clustersfile');
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

            my $outfile = $self->create_outdir($cluster_id, $work_dir);
            open OUT, ">$outfile" or die $!; print OUT join('',@seq_list); close OUT;
            print STDERR "[ $readsnum - $cluster_id - $outfile - $diff secs...]\n" if ($self->debug);
            push @output_ids, { 'clstreadsfile' => $outfile };
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

    $self->dataflow_output_id($output_ids, 2);

    $self->warning(scalar(@$output_ids).' jobs have been created');     # warning messages get recorded into 'job_message' table

    ## then flow into the branch#1 funnel; input_id would flow into branch#1 by default anyway, but we request it here explicitly:
    # $self->dataflow_output_id($self->input_id, 1);
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
  my $outfile = $outdir . "/" . $cluster_id . ".fa";

  return $outfile;
}

1;

