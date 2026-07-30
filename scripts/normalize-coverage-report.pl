use strict;
use warnings;
use File::Basename qw(dirname);
use File::Find qw(find);

my ($report_directory, $source_root) = @ARGV;
die "usage: $0 REPORT_DIRECTORY SOURCE_ROOT\n"
  unless defined $report_directory && defined $source_root;

my @html_files;
find(
  {
    no_chdir => 1,
    wanted => sub { push @html_files, $File::Find::name if /\.html\z/ },
  },
  $report_directory,
);

for my $path (@html_files) {
  open my $input, '<', $path or die "open $path: $!";
  local $/;
  my $html = <$input>;
  close $input or die "close $path: $!";
  $html =~ s/\Q$source_root\E/<project-root>/g;
  open my $output, '>', $path or die "open $path: $!";
  print {$output} $html or die "write $path: $!";
  close $output or die "close $path: $!";
}

my $index_path = "$report_directory/cover-index.html";
my $index_directory = dirname $index_path;
open my $input, '<', $index_path or die "open $index_path: $!";
local $/;
my $index = <$input>;
close $input or die "close $index_path: $!";

my %renames;
while ($index =~ /href='([0-9a-f]{32})\.html'>([^<]+)<\/a>/g) {
  my ($digest, $source_name) = ($1, $2);
  die "unsafe source filename: $source_name\n"
    unless $source_name =~ /\A[A-Za-z0-9._-]+\z/;
  $renames{"$digest.html"} = "source-$source_name.html";
}

die "coverage report has no source pages\n" unless %renames;
for my $old (sort keys %renames) {
  my $new = $renames{$old};
  rename "$index_directory/$old", "$index_directory/$new"
    or die "rename $old to $new: $!\n";
  $index =~ s/\Q$old\E/$new/g;
}

open my $output, '>', $index_path or die "open $index_path: $!";
print {$output} $index or die "write $index_path: $!";
close $output or die "close $index_path: $!";
