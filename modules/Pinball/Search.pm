
=pod 

=head1 NAME

Pinball::Search

=head1 SYNOPSIS

The Search module does something.

=head1 DESCRIPTION

'Pinball::Search' is the 3rd step of the Pinball pipeline.

=cut

package Pinball::Search;

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

    my $walksfile   = $self->param('walksfile') || 
      die "'walksfile' is an obligatory parameter, please set it in the input_id hashref";

    my $reference   = $self->param('reference') || 
      die "'reference' is an obligatory parameter, please set it in the input_id hashref";

    my $search_executable   = $self->param('search_executable') || 
      die "'search_executable' is an obligatory parameter, please set it in the input_id hashref";

#    $self->{param1} = $self->param('param1')  || die "'param1' is an obligatory parameter";

}

=head2 run

    Description : Implements run().

=cut

sub run {
    my $self = shift @_;

    my $walksfile           = $self->param('walksfile');
    my $reference           = $self->param('reference');
    my $tag                 = $self->param('tag');
    my $search_executable   = $self->param('search_executable');
    my $sga_executable      = $self->param('sga_executable');
    my $samtools_executable = $self->param('samtools_executable') || $ENV{'HOME'}.'/pinball/samtools/samtools';
    my $bwa_z               = $self->param('bwa_z') || 1000;
    my $allhits             = $self->param('allhits') || 0;
    my $searchwalkslimit    = $self->param('searchwalkslimit') || 100;

    my ($infilebase,$path,$type)          = fileparse($walksfile,qr/\.[^.]*/);
    my ($refinfilebase,$refpath,$reftype) = fileparse($reference,qr/\.[^.]*/);
    $tag = join("\.", $tag, $refinfilebase);

    my $cmd;
    # search query target
    my $searchfile = "$walksfile.$tag.search.$bwa_z";
    my $temp_dir = $self->worker_temp_directory;
    my $temp_id  = $self->worker->process_id; $temp_id =~ s/\[\d+\]//; $temp_id .= int(rand(10000));
    my $walks_sampled  = $temp_dir . $temp_id . ".sampled";
    my $dust_walks_log = $temp_dir . $temp_id . ".preprocess.dust.log";
    my $dust_param = '--dust';
    my $quiet_out = '1>/dev/null'; $quiet_out = '' if ($self->debug);
    my $quiet_err = '2>/dev/null'; $quiet_err = '' if ($self->debug);

    # First preprocess
    $cmd = "$sga_executable preprocess $dust_param $walksfile 1> $walks_sampled 2>$dust_walks_log";
    print STDERR "$cmd\n" if ($self->debug);
    if(system("$cmd") != 0) {    print("$cmd\n");    $self->throw("error running pinball dust walks $!\n");  }
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
    # Get rid of log files
    $cmd = "rm -f $dust_walks_log";
    print STDERR "$cmd\n" if ($self->debug);
    if(system("$cmd") != 0) {    print("$cmd\n");    $self->throw("error running pinball search $!\n");  }

    # Find parameters for second preprocess:
    # If more than half of the walks are low-complexity, then don't do dust and sample from all
    $dust_param = '' if ($numbases < 0.5);
    # If numwalks after filtering is bigger than searchwalklimit,
    # sample to obtain as many as sqrt(numwalks)
    my $samplerate;
    if ($numwalks > $searchwalkslimit) {
      my $numsampled = sqrt($numwalks);
      $samplerate = $numsampled/$numwalks;
    }
    my $walks_sample_threshold = '';
    $walks_sample_threshold = "--sample=" . $samplerate if (length $samplerate > 0);

    # Second preprocess
    $cmd = "$sga_executable preprocess $walks_sample_threshold $dust_param $walksfile 1> $walks_sampled 2>$dust_walks_log";
    print STDERR "$cmd\n" if ($self->debug);
    if(system("$cmd") != 0) {    print("$cmd\n");    $self->throw("error running pinball sample walks $!\n");  }

    my $temp_sam = $temp_dir . $temp_id . ".sam";
    my $filt_sam = $temp_dir . $temp_id . ".filt.sam";
    my $proj_sam = $temp_dir . $temp_id . ".filt.proj.sam";
    my $temp_bam = $temp_dir . $temp_id . ".bam";
    my $proj_bam = $temp_dir . $temp_id . ".proj.bam";
#    $cmd = "$search_executable bwasw -z $bwa_z $reference $walksfile | $samtools_executable view -F 0x4 -bt $reference.fai - > $temp_bam";

    # Align walks to the reference
    # $cmd = "$search_executable bwasw -z $bwa_z $reference $walksfile > $temp_sam";
    $cmd = "$search_executable bwasw -z $bwa_z $reference $walks_sampled > $temp_sam $quiet_err";
    print STDERR "$cmd\n" if ($self->debug);
    $self->db->dbc->disconnect_when_inactive(1);
    if(system("$cmd") != 0) {    print("$cmd\n");    $self->throw("error running pinball search $!\n");  }
    $self->db->dbc->disconnect_when_inactive(0);

    # Filter only highest scoring hits in the sam output
    open TEMPSAM, "$temp_sam" or die $!;
    open FILTSAM, ">$filt_sam" or die $!;
    my $hits; my $maxscore = 0;
    while (<TEMPSAM>) {
      if (/^\@/) {
        print FILTSAM $_; next;
      }
      my $score = -1;
      $score = $1 if (/AS:i:(\d+)/);
      my @t = split("\t");
      $hits->{$score}{$t[0]} = $_ if ($score > 0);
      $maxscore = $score if ($score > $maxscore);
    }
    close TEMPSAM;
    foreach my $score (sort { $b<=>$a } keys %$hits) {
      foreach my $cluster (keys %{$hits->{$score}}) {
        my $line = $hits->{$score}{$cluster};
        print FILTSAM $line if ($score == $maxscore || 1 == $allhits);
      }
    }
    close FILTSAM;
    my $num_hits = scalar keys %$hits;

    # If we got some hits, then create the bam files
    if (0 < $num_hits) {
      # $self->project_walks_sam($filt_sam,$proj_sam,$walks_sampled);
      $self->project_walks_sam($filt_sam,$proj_sam,$walks_sampled);
      $DB::single=1;1;
      my $cmd2;

      # Non-projected bam
      # $cmd2 = "$samtools_executable view -F 0x4 -bt $reference.fai $filt_sam > $temp_bam";
      # print STDERR "$cmd2\n" if ($self->debug);
      # if(system("$cmd2") != 0) {    print("$cmd2\n");    $self->throw("error running pinball filt bam $!\n");  }
      # $DB::single=1;1;

      # Projected bam
      $cmd2 = "$samtools_executable view -F 0x4 -bt $reference.fai $proj_sam > $proj_bam $quiet_err";
      print STDERR "$cmd2\n" if ($self->debug);
      if(system("$cmd2") != 0) {    print("$cmd2\n");    $self->throw("error running pinball proj bam $!\n");  }
      $DB::single=1;1;
#      $cmd = "$samtools_executable sort $temp_bam $searchfile";
#      $cmd = "$samtools_executable sort $proj_bam $searchfile.proj";
      $cmd = "$samtools_executable sort $proj_bam $searchfile $quiet_out $quiet_err";
      print STDERR "$cmd\n" if ($self->debug);
      if(system("$cmd") != 0) {    print("$cmd\n");    $self->throw("error running pinball search $!\n");  }
    } else {
      print STDERR "No hits found.\n" if ($self->debug);
    }
    return;
}

sub project_walks_sam {
  my $self = shift;
  my $filt_sam = shift;
  my $proj_sam = shift;
  my $walksfile = shift;

  # TODO: Change $self->param('walksfile') to wdescfile
  my $samwalksfile = $self->param('walksfile') . ".sam";

  return if (-z $filt_sam || -z $samwalksfile);
  open PROJSAM, ">$proj_sam" or die $!;
  open FILTSAM, "$filt_sam" or die $!;
  my $hits;
  while (<FILTSAM>) {
      if (/^\@/) {
        print PROJSAM $_; next;
      }
      my @t = split("\t");
      $hits->{$t[0]} = $_;
      print PROJSAM $_;
    }
  close FILTSAM;

  open SAMWALKS, $samwalksfile or die $!;
  my $lines;
  while (<SAMWALKS>) {
    next if (/^\@/);
    my @read = split("\t");
    if (defined $hits->{$read[2]}) {
      # if ($read[0] =~ /SOLEXA1_0001:7:77:438:1353/) {
      $DB::single=1;1;
      # }
      my @walk = split("\t",$hits->{$read[2]});
      my $cigar = $walk[5];
      my $coord_walk = $walk[3];
      my ($expd_cigar,@coord_vector) = $self->expand_cigar($cigar,$coord_walk);
      my $coord_read = $read[3];
      my $proj_coord = $coord_vector[$coord_read];

      my $read_cigar = $self->project_read($expd_cigar,$coord_read,length($read[9]));
      # if there are no M's in the read_cigar, it's unmapped, so we skip it
      next unless ($read_cigar =~ /M/);
      my $encr_cigar = $self->encode_cigar($read_cigar);
      my ($x,$y) = $self->expand_cigar($encr_cigar,1);
      if (length($x) != length($read[9])) {
        $DB::single=1;1;#??
      }
      my $strand = abs($read[1]-$walk[1]);
      my $samline = join("\t",$read[0],$strand,$walk[2],$proj_coord,length($read[9]),$encr_cigar,$read[6],$read[7],$read[8],$read[9],$read[10]);
      print PROJSAM "$samline" unless (defined $lines->{$samline});
      $lines->{$samline} = 1;
    }
  }
  close SAMWALKS;
  close PROJSAM;

  return undef;
}

sub project_read {
  my $self = shift;
  my $expd_cigar = shift;
  my $coord_read = shift;
  my $length = shift;

  my $projected_read;
  my @e = split('',$expd_cigar);
  # $DB::single=1;1;
  while (my $e = shift @e) {
    if ($e eq 'M') {
      $coord_read--;
    } elsif ($e eq 'D') {
#      $coord_read--;
    } elsif ($e eq 'I') {
      $coord_read--;
    } elsif ($e eq 'S') {
      $coord_read--;
    } else {
      die $!;
    }
    if (0 >= $coord_read) {
      $projected_read .= $e;
      $length-- unless ($e eq 'D');
    }
    last if (0 == $length);
  }
  return $projected_read;
}

sub expand_cigar {
  my $self = shift;
  my $cigar_line = shift;
  my $coord_walk = shift;
  my $expanded_cigar;
  my @coord_vector;

  $cigar_line =~ s/([0-9]*[A-Z]{1})/$1\t/g;
  my @cigar_tokens = split /\t/, $cigar_line;
  for(my $i = 0; $i < scalar(@cigar_tokens); $i++) {
    if ($cigar_tokens[$i] =~ /([0-9]+)([A-Z]{1})/g) {
      $expanded_cigar .= $2 x $1;
      if ($2 eq 'S' || $2 eq 'I') {
        for my $i (1 .. $1) {
          push @coord_vector, $coord_walk;
        }
      } elsif ($2 eq 'M') {
        for my $i (1 .. $1) {
          push @coord_vector, ++$coord_walk;
        }
      } elsif ($2 eq 'D') {
        $coord_walk += $1;
        push @coord_vector, $coord_walk;
      }
    }
  }
  return ($expanded_cigar,@coord_vector);
}

sub encode_cigar {
  my $self = shift;
  my $expd_cigar = shift;
  my $encd_cigar;
  my @e = split('',$expd_cigar);
  while (@e) {
    my ($x, $c) = (shift @e, 1);
    $c++, shift @e while $e[0] eq $x;
    $encd_cigar .= "$c$x";
  }
  return $encd_cigar;
}


=head2 write_output

    Description : Implements write_output()

=cut

sub write_output {

}

1;

