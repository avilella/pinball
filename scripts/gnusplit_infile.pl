#!/usr/bin/perl
# gnusplit_infile.pl
#
# Cared for by Albert Vilella <>
#
# Copyright Albert Vilella
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

gnusplit_infile.pl - DESCRIPTION 

=head1 SYNOPSIS

perl gnusplit_infile.pl -i long_file_with_list_of_items.txt -l 100 -hashed

=head1 DESCRIPTION

Considers that infile data atomicity is one-line based.

[-lines] to split the infile into [L] lines per subfile

If [-hashed] is used, it will hash the infile into a three-level depth
subdir. Something like ./00/00/00 -- ./00/00/01 ... ./99/99/99

=head1 AUTHOR - Albert Vilella

Email 

Describe contact details here

=head1 CONTRIBUTORS

Additional contributors names and emails here

=cut


# Let the code begin...
use strict;
use Getopt::Long;
use File::Basename;
use FileHandle;

my ($inputfile,$lines,$hashed,$split_exe,$prefix);

$split_exe = "~/pinball/coreutils/bin/split";

GetOptions(
           'split_exe:s' => \$split_exe,
           'i|input|inputfile:s' => \$inputfile,
           'l|lines:s' => \$lines,
           'hashed' => \$hashed,
#           'prefix:s' => \$prefix,
          );

my ($basename,$path,$type) = fileparse($inputfile,qr/\.[^.]*/);
$DB::single=1;1;
my $linesperfile = $lines || 1000;
print "Splitting into $linesperfile lines per file...\n";
$prefix = $basename;
my $command = "stdbuf -o0 $split_exe --verbose -d -u -a 10 -l $linesperfile $inputfile $prefix";
print STDERR "# $command\n";
my $infh;
STDOUT->autoflush(1);
open($infh, "$command |") || die $!;
my $filenum = sprintf("%06d", 0);
my $final_dir;
while (<$infh>) {
  chomp $_;
  $_ =~ /creating file \`(\S+)\'/;
  print STDERR "# $_\n";
  my $this_file = $1;
  $DB::single=1;1;
  my $outdir = '.';
  if ($hashed) {
    $filenum = sprintf("%06d", $filenum);
    $filenum =~ /(\d{2})(\d{2})(\d{2})/; #
    my $dir1 = $1; my $dir2 = $2; my $dir3 = $3;
    $outdir = "$path/$dir1/$dir2/$dir3";
    $final_dir = "$dir1:$dir2:$dir3";
    $outdir =~ s/\/\//\//g;
    unless (-d $outdir) {
      eval "require File::Path";
      if ($@) {
        print "File::Path not found. trying with mkdir\n";
        mkdir("$outdir");
      } else {
        File::Path::mkpath($outdir);
      }
      $filenum++;
    }
  }
  $DB::single=1;1;
  my $cmd = "mv -f $this_file $outdir/$this_file"."$type";
  print STDERR "# $cmd\n";
  unless(system("$cmd") == 0) {die "couldnt mv file\n\# $cmd \n\# $!\n";}
}


print "finaldir=$final_dir\n";
print "Done.\n";
1;
