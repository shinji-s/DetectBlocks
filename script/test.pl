#!/usr/bin/perl 


use DetectBlocks;

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";


my $str = "";
open(FILE, "<:utf8", $ARGV[0]);
while(<FILE>){
    $str .= $_;
}
close(FILE);



$url = $ARGV[1];

my $ttt = new DetectBlocks();
$ttt->maketree($str, $url);

$ttt->detectblocks;


my $tree = $ttt->gettree;

#print $tree->as_HTML("<>&","\t");

print $ttt->printblock2
