
=pod 

=head1 NAME

Pinball::Extend

=head1 SYNOPSIS

The Extend module does something.

=head1 DESCRIPTION

'Pinball::Extend' is the XXX step of the Pinball pipeline.

=cut

package Pinball::Extend;

use strict;
use File::Basename;
use Cwd;
use Time::HiRes qw(time gettimeofday tv_interval);
use Bio::SeqIO;

use base ('Bio::EnsEMBL::Hive::Process');

=head2 fetch_input

    Description : Implements fetch_input()

=cut

sub fetch_input {
    my $self = shift @_;

    $self->{starttime} = time();
    print STDERR "[init] ",time()-$self->{starttime}," secs...\n" if ($self->debug);

    $self->{start_dir} = getcwd;
    my $work_dir  = $self->param('work_dir')   || die "'work_dir' is an obligatory parameter";
    my $walksfile = $self->param('walksfile')  || die "'walksfile' is an obligatory parameter";

}

=head2 run

    Description : Implements run().

=cut

sub run {
    my $self = shift @_;

    my $walksfile      = $self->param('walksfile');
    my $wdescfile      = $self->param('wdescfile');
    my $work_dir       = $self->param('work_dir');
    my $tag            = $self->param('tag');
    my $sga_executable = $self->param('sga_executable');
    my $overlap        = $self->param('overlap');

    # FIXME - right now we just set overlap to -10%
    $overlap = $overlap - int($overlap/10);

    chdir($work_dir) if (defined ($self->{start_dir}));

    my ($infilebase,$path,$type) = fileparse($walksfile);
    my $cluster_id; $infilebase =~ /(cluster\-\d+)/; $cluster_id = $1;
    $self->throw("cluster_id not defined $cluster_id") if (!defined $cluster_id);

    my $cmd;
    # extend something

    my $walksio = Bio::SeqIO->new
      (-file => $walksfile,
       -format => 'fasta');

    my $tmp_dir = $self->worker_temp_directory;
    my $walksfile_c = $tmp_dir . $cluster_id . ".walks.c";
    my $walksfile_e = $tmp_dir . $cluster_id . ".walks.e";

    open WALKSC, ">$walksfile_c" or die $!;
    my $idhash; my $walkshash; my $seqhash;
    while (my $seq = $walksio->next_seq) {
      my $display_id = $seq->display_id;
      my ($cluster,$cid,$walk,$wid) = split("-",$display_id);
      my $this_cluster_id = $cluster_id;
      my $sequence = $seq->seq;
      $walkshash->{$this_cluster_id}{$display_id} = $sequence;
      $seqhash->{$sequence} = $display_id;
    }

    foreach my $cluster_id (keys %$walkshash) {
      my @keys = keys %{$walkshash->{$cluster_id}};
      my $num = scalar @keys;
      foreach my $walk_id (@keys) {
        my $sequence = $walkshash->{$cluster_id}{$walk_id};
        print WALKSC "$cluster_id\t$num\t$walk_id\t$sequence\n";
      }
    }

    close WALKSC;

    my $tag_fq = $work_dir . '/' . $tag . '.fq';
    $cmd = "$sga_executable cluster -x 100000 -m $overlap $tag_fq --extend=$walksfile_c -o $walksfile_e";
    print STDERR "$cmd\n" if ($self->debug);
    $DB::single=1;1;
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running pinball extend $!\n");  }

    if (-e $walksfile_e && !-z $walksfile_e) {
      print STDERR "$walksfile_e\n" if ($self->debug);
    } else {
      # extend output file is empty, so we just put back the
      # walksfile_c file pointing to the walksfile_e
      $walksfile_e = $walksfile_c;
    }

    my $outdir = $path;
    my $clstext  = $outdir . "$cluster_id.clstext";
    my $clstfile = $outdir . "$cluster_id.clst";
    open WALKSE, "$walksfile_e" or die $!;
    open CLSTEXT, ">$clstext" or die $!;
    my $clstext_present;
    while (<WALKSE>) {
      chomp $_;
      my ($dummy,$num,$walks_e_seq_id,$seq) = split(" ",$_);
      my $seq_id;
      if ($walks_e_seq_id =~ /^seed\-/) {
        # FIXME: we dont want to add the walks to the clstext
        $seq_id = $seqhash->{$seq};
      } else {
        $seq_id = $walks_e_seq_id;
        print CLSTEXT "\>$seq_id\n$seq\n";
        $clstext_present->{$seq} = 1;
      }
      $self->throw("walks_e_seq_id not found with seq [$walks_e_seq_id] - [$seq]") if (!defined $seq_id || !defined ($seq));
    }

    my $clstio = Bio::SeqIO->new
      (-file => $clstfile,
       -format => 'fasta');

    while (my $seq = $clstio->next_seq) {
      my $display_id = $seq->display_id;
      my ($cluster,$cid,$walk,$wid) = split("-",$display_id);
      my $this_cluster_id = $cluster_id;
      my $sequence = $seq->seq;
      $idhash->{$this_cluster_id}{$display_id} = $sequence;
      $seqhash->{$sequence} = $display_id;
    }

    foreach my $cluster_id (keys %$idhash) {
      my @keys = keys %{$idhash->{$cluster_id}};
      my $num = scalar @keys;
      foreach my $walk_id (@keys) {
        my $sequence = $idhash->{$cluster_id}{$walk_id};

        # FIXME: if the following line is in use, then it's unique
        # reads for clstext, but if it's commented out and we are
        # using the original index file with no filter.pass filtering,
        # we basically *should* have the intensity of the peak (needs
        # checking)

        # next if (defined $clstext_present->{$sequence});
        $DB::single=1;1;
        print CLSTEXT "\>$walk_id\n$sequence\n";
        $clstext_present->{$sequence} = 1;
      }
    }
    close CLSTEXT;
    $self->param('clstext',$clstext);
    if (-e $clstext && !-z $clstext) {
      print STDERR "# $clstext\n" if ($self->debug);
    } else {
      $self->throw("error running pinball extend\n $cmd\n #$clstext\n $!\n");
    }

    chdir($self->{start_dir});

    return 0;
}

=head2 write_output

    Description : Implements write_output()

=cut

sub write_output {  # nothing to write out, but some dataflow to perform:
    my $self = shift @_;

    my $work_dir = $self->param('work_dir');
    my $clstext  = $self->param('clstext');
    my $tag  = $self->param('tag');
    my $dataflow = 1;

    my @output_ids;
    push @output_ids, {'clstext'=> $clstext, 'tag'=> $tag, 'work_dir'=> $work_dir };
    print "Created jobs ", scalar @output_ids, "\n" if ($self->debug);
    $self->param('output_ids', \@output_ids);
    my $output_ids = $self->param('output_ids');
    my $job_ids = $self->dataflow_output_id($output_ids, $dataflow);
    print join("\n",@$job_ids), "\n" if ($self->debug);

    $self->warning(scalar(@$output_ids).' jobs have been created');     # warning messages get recorded into 'job_message' table


    ## then flow into the branch#1 funnel; input_id would flow into branch#1 by default anyway, but we request it here explicitly:
    # $self->dataflow_output_id($self->input_id, 1);
}

1;

