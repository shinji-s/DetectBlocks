#!/usr/bin/env perl

# $Id$

use strict;
use utf8;
use LWP::Simple;
use URI::Escape qw(uri_escape_utf8);
use XML::Simple;
use Encode;
binmode STDOUT, ':encoding(utf8)';

my $base_url = 'http://orchid.kuee.kyoto-u.ac.jp/ISA/index.cgi';

# 入力URL
my $inputurl = 'http://100mangoku.net/';
$inputurl = uri_escape_utf8($inputurl);

my $req_url = "$base_url?format=xml&inputurl=$inputurl";

# API問い合わせ
my $response = get($req_url);
$response = decode('utf8', $response);
print $response;

# XML読み込み
my $data = XMLin($response);

# 出力
print "\n--- Information Sender ---\n";
foreach my $information_sender (@{$data->{information_sender}}) {
    print " $information_sender\n";
}
