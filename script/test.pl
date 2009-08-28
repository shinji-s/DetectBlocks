#!/usr/bin/env perl 

# $Id$

# usage: 
# (HTMLソースを取得)
# perl -I../perl test.pl -get_source http://www.shugiin.go.jp/index.nsf/html/index.htm
# (キャッシュ)
# perl -I../perl test.pl ../sample/htmls/Metabolic/001.html
#  - tree表示
# perl -I../perl test.pl -printtree ../sample/htmls/Metabolic/001.html
#  - html用
# perl -I../perl test.pl -add_class2html ../sample/htmls/Metabolic/001.html

use utf8;
use strict;
use RepeatCheck;
#use DetectBlocks;
use DetectBlocks2;
use Encode;
use Encode::Guess;
use Getopt::Long;
use Dumpvalue;

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";

my (%opt);
GetOptions(\%opt, 'get_source=s', 'proxy=s', 'debug', 'add_class2html', 'printtree');

my $str = "";
my $url;
# HTMLソースを取得
if ($opt{get_source}) {
    require LWP::UserAgent;

    my $ua = new LWP::UserAgent;
    $ua->agent('Mozilla/5.0');
    $ua->proxy('http', $opt{proxy}) if (defined $opt{proxy});
    $ua->parse_head(0);

    my $response = $ua->get($opt{get_source});

    die $response->status_line unless $response->is_success;

    $str = decode(guess_encoding($response->content, qw/ascii euc-jp shiftjis 7bit-jis utf8/), $response->content);

    print $str if $opt{debug};
    $url = $opt{get_source};
}
# キャッシュ
else {
    open(FILE, "<:utf8", $ARGV[0]);
    while(<FILE>){
	$str .= $_;
    }
    close(FILE);

    $url = $ARGV[1];
}

#my $ttt = new DetectBlocks(\%opt);
my $DetectBlocks = new DetectBlocks2(\%opt);
$DetectBlocks->maketree($str, $url);

if ($opt{debug}) {
    Dumpvalue->new->dumpValue($DetectBlocks->{tree});
    print '-' x 50, "\n";
}

$DetectBlocks->detectblocks;
my $tree = $DetectBlocks->gettree;

if ($opt{debug}) {
    Dumpvalue->new->dumpValue($tree);
}


# HTML形式で出力
if ($opt{add_class2html}) {
    $DetectBlocks->addCSSlink($tree, 'style.css');    

    print $tree->as_HTML("<>&","\t", {});
}
else {
# 木の表示
    print '=' x 50, "\n";
    $DetectBlocks->printtree;
    print '=' x 50, "\n";
}
