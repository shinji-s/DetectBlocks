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
#binmode STDOUT, ":euc-jp";

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
my $ttt = new DetectBlocks2(\%opt);
$ttt->maketree($str, $url);

if ($opt{debug}) {
    Dumpvalue->new->dumpValue($ttt->{tree});
    print '-' x 50, "\n";
}

$ttt->detectblocks;

my $tree = $ttt->gettree;
# my $test = RepeatCheck->new;
# $ttt->settree($test->detectrepeat($tree)); 

if ($opt{debug}) {
    Dumpvalue->new->dumpValue($tree);
}
# 木の表示
if ($opt{printtree}) {
    print '=' x 50, "\n";
    $ttt->printtree;
    print '=' x 50, "\n";
}

# HTML形式で出力
if ($opt{add_class2html}) {
    $ttt->addCSSlink($tree, 'style.css');    
    print $tree->as_HTML("<>&","\t");
}
