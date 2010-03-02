#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request;
use URI::Escape qw(uri_escape_utf8);
use XML::Simple;
use Encode;
use Encode::Guess;
use Getopt::Long;
use Dumpvalue;

binmode STDOUT, ':encoding(utf8)';
binmode STDIN, ':encoding(utf8)';

my %opt;
&GetOptions(\%opt, 'post', 'url=s', 'feature');

my $base_url = 'http://orchid.kuee.kyoto-u.ac.jp/ISA/index.cgi';

$opt{url} = 'http://100mangoku.net/' unless $opt{url};

# UserAgent の作成
my $ua = LWP::UserAgent->new;

my $req;
# POST
if ($opt{post}) {
    my $html = &get_html;

    $req = HTTP::Request->new(POST => $base_url);
    $req->content(encode('utf8', $html));
}

# GET
else {
    # 入力URL
    my $inputurl = $opt{url};
    $inputurl = uri_escape_utf8($inputurl);

    # my $req_url = "$base_url?format=xml&inputurl=$inputurl";
    my $req_url;
    if ($opt{feature}) {
	$req_url = "$base_url?format=xml&inputurl=$inputurl&feature=1";
    }
    else {
	$req_url = "$base_url?format=xml&inputurl=$inputurl";
    }

    # API問い合わせ
    $req = HTTP::Request->new(GET => $req_url);
}

my $response = $ua->request($req);

print decode('utf8', $response->content);

# XML読み込み
my $data = XMLin(decode('utf8', $response->content), ForceArray => 1);

# 出力
if (ref($data->{information_sender}) eq 'ARRAY') {
    print "\n--- Information Sender ---\n";
    foreach my $information_sender (@{$data->{information_sender}}) {
	# 抽出文字列
	print ' ',$information_sender->{string}[0],"\n";
	if ($opt{feature}) {
	    foreach my $feature (@{$information_sender->{features}[0]{feature}}) {
		print "\t$feature\n";
	    }
	}
	else {
	    # 領域名
	    foreach my $blocktype (@{$information_sender->{blocktypes}[0]{blocktype}}) {
		print $blocktype;
	    }
	}
    }
}

sub get_html {
    my $html;

    while (<STDIN>) {
	$html .= $_;
    }

    return $html;
}
