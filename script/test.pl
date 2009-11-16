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
use DetectBlocks;
use Encode;
use Encode::Guess;
use Getopt::Long;
use Dumpvalue;

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";

# add_blockname2alltagは後々に撲滅
my (%opt);
GetOptions(\%opt, 'get_source=s', 'proxy=s', 'debug', 'add_class2html', 'printtree', 'get_more_block', 'rel2abs', 'add_blockname2alltag', 'blogcheck', 'juman=s', 'modify', 'print_offset');

$opt{modify} = 1 if $opt{print_offset};

my $DetectBlocks = new DetectBlocks(\%opt);
my $BlogCheck;
if ($opt{blogcheck}) {
    require BlogCheck;
    $BlogCheck = new BlogCheck($DetectBlocks);
}

my $str = "";
my $url;
# HTMLソースを取得
if ($opt{get_source}) {
    ($str, $url) = $DetectBlocks->Get_Source_String($opt{get_source});
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

$DetectBlocks->maketree($str, $url);

if ($opt{debug}) {
    Dumpvalue->new->dumpValue($DetectBlocks->{tree});
    print '-' x 50, "\n";
}

$DetectBlocks->detectblocks;

if ($opt{blogcheck}) {
    $BlogCheck->blog_check;
    $BlogCheck->print_blog;
}

my $tree = $DetectBlocks->gettree;

if ($opt{debug}) {
    Dumpvalue->new->dumpValue($tree);
}


# HTML形式で出力
if ($opt{add_class2html}) {
    $DetectBlocks->addCSSlink($tree, 'style.css');    

    print $tree->as_HTML("<>&","\t", {});
}
# offsetを出力
elsif ($opt{print_offset}) {
    my $body = $tree->find('body');
    $DetectBlocks->print_offset($body, undef, undef);
}
else {
# 木の表示
    print '=' x 50, "\n";
    $DetectBlocks->printtree;
    print '=' x 50, "\n";
}
