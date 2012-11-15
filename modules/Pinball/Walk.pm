
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

    $self->{start_dir} = getcwd;

    my $clst    = $self->param('clst');
    my $clstext = $self->param('clstext');
    die "'clst' or 'clstext' are obligatory parameters, please set one of them in the input_id hashref"
      unless (defined $clst || defined $clstext);
    my $work_dir   = $self->param('work_dir') || 
      die "'work_dir' is an obligatory parameter, please set it in the input_id hashref";

    # return 1 unless (-z $clst);

#    $self->{param1} = $self->param('param1')  || die "'param1' is an obligatory parameter";

}

=head2 run

    Description : Implements run().

=cut

sub run {
    my $self = shift @_;

    my $worker_temp_directory = $self->worker_temp_directory;
    print STDERR "# $worker_temp_directory\n" if ($self->debug);
    chdir($worker_temp_directory) if (defined ($self->{start_dir}));

    my $tag            = $self->param('tag');
    my $dust           = $self->param('dust');
    my $phred64        = $self->param('phred64');
    my $no_permute     = $self->param('no_permute');
    my $disk           = $self->param('disk');

    my $overlap        = $self->param('overlap');

    my $csize          = $self->param('csize');
    my $erate          = $self->param('erate');
    my $minreadlen     = $self->param('minreadlen');
    my $walkslimit     = $self->param('walkslimit') || 100;
    my $longest_n      = $self->param('longest_n') || 1;
    my $timelimit      = $self->param('timelimit');
    my $timelimit_executable  = $self->param('timelimit_executable');
    my $sga_executable = $self->param('sga_executable');
    my $sample         = $self->param('sample');
    my $work_dir       = $self->param('work_dir');

    my $clst    = $self->param('clst');
    my $clstext = $self->param('clstext');
    $clst = $clstext if (!(defined $clst) && defined $clstext);
    my $readsfile = $clst; # for convenience
    my ($infilebase,$path,$type) = fileparse($clst);
    my $cluster_id; $infilebase =~ /(cluster\-\d+)/; $cluster_id = $1;
    $tag = join("\.", $tag, $cluster_id, "w");

    my $cmd;
    my $dust_threshold    = '';
    my $sample_threshold  = '';
    my $phred64_flag      = '';
    my $permute_ambiguous = '';
    $dust_threshold       = "--dust-threshold=" . $dust if (length $dust > 0);
    # $sample_threshold     = "--sample=" . $sample if (length $sample > 0);
    # phred64 already comes converted from cluster preprocess
    #    $phred64_flag         = "--phred64" if ($phred64);
    $permute_ambiguous    = "--permute-ambiguous" unless ($no_permute);

    # sga preprocess
    my $preprocess_log = "$tag.sga.preprocess.log";
    $cmd = "$sga_executable preprocess $sample_threshold $phred64_flag --min-length=$minreadlen $dust_threshold $permute_ambiguous $readsfile -o $tag.fq 2>$preprocess_log";
    print STDERR "$cmd\n" if ($self->debug);
    $DB::single=1;1;
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga preprocess $!\n");  }

    # sga index
    # this will take about 500MB of memory
    my $disk_option = ''; $disk_option = "--disk=$disk" if (length($disk)>0);
    $cmd = "$sga_executable index -t 1 $disk_option $tag.fq";
    print STDERR "$cmd\n" if ($self->debug);
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga index $!\n");  }

    # sga filter
    $cmd = "$sga_executable filter --no-kmer-check -t 1 $tag.fq";
    print STDERR "$cmd\n" if ($self->debug);
    $DB::single=1;1;
    unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga filter: $!\n");  }

    my $internal_overlap_value = $overlap;
    my $walk_output = 0;
    my $walksfile;
    my $wdescfile;
    while (0 == $walk_output) {
      print STDERR "# internal_overlap_value=$internal_overlap_value\n" if ($self->debug);
      # sga overlap
      $cmd = "$sga_executable overlap -m $internal_overlap_value -t 1 --exhaustive -e $erate $tag.filter.pass.fa -o $tag.asqg.gz";
      $DB::single=1;1;
      print STDERR "$cmd\n" if ($self->debug);
      unless(system("$cmd") == 0) {    print("$cmd\n");    $self->throw("error running sga overlap $!\n");  }

      # sga walk
      my $outdir = $path;
      my $ext = "walks"; $ext = "walksext" if ($clst =~ /\.clstext$/);
      $walksfile = $outdir . "$cluster_id.$ext";
      $wdescfile = $outdir . "$cluster_id.$ext.sam";

      my $timelimit_prefix = '';
      if (0 < $timelimit) { $timelimit_prefix = "$timelimit_executable -t" . $timelimit; }
      $cmd = "$timelimit_prefix $sga_executable walk --prefix=$cluster_id --component-walks --longest-n=$longest_n -o $walksfile --sam=$wdescfile $tag.asqg.gz";
      print STDERR "$cmd\n" if ($self->debug);
      $DB::single=1;1;#??
      $self->db->dbc->disconnect_when_inactive(1);
      my $ret = system("$cmd");
      unless ($ret == 0) {    print("$cmd\n");    print STDERR "error running sga walk $!\n";  }
      $self->db->dbc->disconnect_when_inactive(0);

      # Preprocess to analyze walks
      my $temp_id  = $self->worker->process_id; $temp_id =~ s/\[\d+\]//; $temp_id .= int(rand(10000));
      my $dust_walks_log = $worker_temp_directory . $temp_id . ".preprocess.walks.log";
      $cmd = "$sga_executable preprocess $walksfile 1> /dev/null 2>$dust_walks_log";
      print STDERR "$cmd\n" if ($self->debug);
      if(system("$cmd") != 0) {    print("$cmd\n");    $self->throw("error running pinball preprocess walks $!\n");  }
      my $numwalks = 1; my $perc_walks = 1; my $numbases = 100; my $perc_bases = 1;
      open DUSTWALKLOG, $dust_walks_log or die $!;
      while (<DUSTWALKLOG>) {
        if (/Reads kept\:/) {
          $_ =~ /Reads kept\:\s+(\d+)\s+\((\S+)\)/;
          $numwalks = $1; $perc_walks = $2;
        }
        if (/Bases kept\:/) {
          $_ =~ /Bases kept\:\s+(\d+)\s+\((\S+)\)/;
          $numbases = $1; $perc_bases = $2;
        }
      }
      $DB::single=1;1;
      my $do_simplified_assembly = 0;
      if ($numwalks > $walkslimit) {
        $do_simplified_assembly = 1;
      }

      if (-e $walksfile && !-z $walksfile) {
        $walk_output = 1;
      } elsif ( $internal_overlap_value > 200) {
        $walk_output = 1;
      } else {
        $do_simplified_assembly = 1;
      } 

      if (1 == $do_simplified_assembly) {
#        my $debugging_cmd = "zcat $tag.asqg.gz | /homes/avilella/src/sga/sgatools/asqg2dot.pl > $tag.dot && dot -Tgif < $tag.dot > $walksfile.gif";
        my $debugging_cmd = "$sga_executable assemble --bubble=0 --cut-terminal=0 --min-branch-length=0 $tag.asqg.gz -o $walksfile";
        print STDERR "# $debugging_cmd\n";
        system($debugging_cmd);
        $internal_overlap_value++;
      }
    }

    if (-e $walksfile && !-z $walksfile || !-z "$walksfile-contigs.fa") {
      print STDERR "$walksfile\n" if ($self->debug);
      $self->param('walksfile', $walksfile);
      $self->param('wdescfile', $wdescfile);
    } else {
      $self->throw("error running sga walk\n $cmd\n #$walksfile\n $!\n");
    }

    # if (-e $wdescfile && !-z $wdescfile) {
    #   print STDERR "$wdescfile\n" if ($self->debug);
    #   $self->param('wdescfile', $wdescfile);
    # } else {
    #   $self->throw("error running sga walk\n $cmd\n #$wdescfile\n $!\n");
    # }

    chdir($self->{start_dir});

    return 0;
}

=head2 write_output

    Description : Implements write_output()

=cut

sub write_output {  # nothing to write out, but some dataflow to perform:
    my $self = shift @_;

    my $work_dir = $self->param('work_dir');
    my $clst     = $self->param('clst');
    my $clstext  = $self->param('clstext');
    my $dataflow = 3;
    $dataflow = 2 if (!(defined $clst) && defined $clstext);
    # return 1 unless (-z $clst);

    my $walksfile = $self->param('walksfile');
    my $wdescfile = $self->param('wdescfile');
    my @output_ids;
    push @output_ids, {'walksfile'=> $walksfile, 'wdescfile' => $wdescfile};
    print "Created jobs ", scalar @output_ids, "\n" if ($self->debug);
    $self->param('output_ids', \@output_ids);
    my $output_ids = $self->param('output_ids');
    my $job_ids;
    # This is inside an eval in case we dont do 'search' so we dont dataflow into it
    eval { $job_ids = $self->dataflow_output_id($output_ids, $dataflow);
           print "# ", join("\n",@$job_ids), "\n" if ($self->debug);
         };

    $self->warning(scalar(@$output_ids).' jobs have been created');     # warning messages get recorded into 'job_message' table

    ## then flow into the branch#1 funnel; input_id would flow into branch#1 by default anyway, but we request it here explicitly:
    # $self->dataflow_output_id($self->input_id, 1);
}

1;

