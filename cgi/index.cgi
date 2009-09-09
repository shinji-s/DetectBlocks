#!/usr/bin/env perl

# $Id$

# 使い方
# COLOR.cgiとstyle.cssを$HOME/public_html以下の同じディレクトリに置く

use strict;
use utf8;
use CGI;
use Dumpvalue;

my $MACHINE = `uname -n`;
my $PERL = $MACHINE =~ /^orchid/ ? '/share/usr-x86_64/bin/perl' : '/share/usr/bin/perl';

# スタイルシートのパス
my $CSS = './style.css';
# 発信者の正解データのパス
my $ISANS = "/home/funayama/cvs/ISA/samples/siteop-20080702.dat";
# 元URLリストのパス
my $ORIG_URL_LIST = "/home/funayama/cvs/ISA/samples/icc-url.txt";

$| = 1;

my $pid = $$;

my ($ROOT, $cgi);
BEGIN {
    $cgi = new CGI;
    $ROOT = $cgi->param('ROOT') ? $cgi->param('ROOT') : '/home/funayama/cvs/DetectBlocks';
}
use lib qq($ROOT/perl);
use DetectBlocks2;

print $cgi->header(-charset => 'utf-8');

my $url = $cgi->param('inputurl');
my $topic = $cgi->param('topic');
my $docno = $cgi->param('docno');

# urlチェック
if ($url && $url !~ /^http\:\/\//) {
    print qq(<font color="red">★有効なURLを入力してください</font><br>\n);
    $url = '';
}

# ログ
&output_log($url);

$url = &shellEsc($url);

print << "END_OF_HTML";
<html lang="ja">
<head>
<title>ページ領域抽出CGI</title>
</head>
<body>

<form method="GET" action="$ENV{SCRIPT_NAME}">
ROOT_DIR : <input type="text" name="ROOT" value="$ROOT" size="50">
END_OF_HTML

print qq(<input type="hidden" name="input_url" value="$url">\n) if ($url);
print qq(<input type="hidden" name="topic" value="$topic">\n) if ($topic);
print qq(<input type="hidden" name="docno" value="$docno">\n) if ($docno);

print << "END_OF_HTML";
<input type="submit" value="送信">
</form>
<form method="GET" action="$ENV{SCRIPT_NAME}">
<input type="hidden" name="ROOT" value="$ROOT" size="50">
END_OF_HTML

my $ans_ref;
if ($url) {
    print qq(URLを指定 : <input type="text" name="inputurl" value="$url" size="50">);
} else {
    $ans_ref = &read_ISA_ans($topic, $docno);
    print qq(URLを指定 : <input type="text" name="inputurl" value="http://www.kyoto-u.ac.jp/ja" size="50">);
}

print << "END_OF_HTML";
<input type="submit" value="送信">
</form>
END_OF_HTML

# ディレクトリを調べる
opendir(DIR, "$ROOT/sample/htmls/");
my @topic = readdir(DIR);
closedir(DIR);

# トピック
print << "END_OF_HTML";
<form method="GET" action="$ENV{SCRIPT_NAME}">\n
<input type="hidden" name="ROOT" value="$ROOT" size="50">
TOPIC:<select name="topic">
END_OF_HTML


if (!$topic) {
    print qq(<option selected="selected">Select Topic</option>\n);
} 
for (my $i = 0;$i < @topic;$i++) {
    my $tmp = $topic[$i];
    next if $tmp =~ /CVS|^\.+$/;

    if ($topic && $topic eq $tmp) {
	print qq(<option name="topic" value="$tmp" selected="selected">$tmp</option>\n);
    } else {
	print qq(<option name="topic "value="$tmp">$tmp</option>\n);
    }
}

print << "END_OF_HTML";
</select>
END_OF_HTML

# 文書番号
if ($topic) {
    # ファイルを調べる
    opendir(F, "$ROOT/sample/htmls/$topic");
    my @docno = sort readdir(F);
    closedir(F);

    print qq(文書No:<form method="GET" action="$ENV{SCRIPT_NAME}">\n);

    print qq(<select name="docno" width="100">\n);
    if (!$docno) {
	print qq(<option selected="selected">Select Document</option>\n);	
    }
    for (my $i = 0; $i < @docno; $i++) {
	my $tmp_docno = $docno[$i];
	next if $tmp_docno =~ /CVS|^\.+$/;

 	my $tmp_ans = $ans_ref->{$topic}{$tmp_docno} ? $ans_ref->{$topic}{$tmp_docno} : 'なし';
 	if ($docno && $docno eq $tmp_docno) {
 	    print qq(<option name="docno" value="$tmp_docno" selected="selected">$tmp_docno ($tmp_ans)</option>\n);
 	} else {
 	    print qq(<option name="docno "value="$tmp_docno">$tmp_docno ($tmp_ans)</option>\n);
 	}
    }
    print qq(</select>\n);
}

print << "END_OF_HTML";
<input type="submit" value="送信">
</form>
END_OF_HTML

## 解析
# 対象ページ解析
my ($raw_html, $orig_encode_url, $orig_url);
my %opt = (get_more_block => 1,
	   add_class2html => 1);
my $DetectBlocks = new DetectBlocks2(\%opt);

# HTMLソースを取得
if ($url) {
    ($raw_html, $orig_url) = $DetectBlocks->Get_Source_String($url);
}
# キャッシュ
elsif ($topic && $docno) {
    open(FILE, "<:utf8", "$ROOT/sample/htmls/$topic/$docno");
    while(<FILE>){
	$raw_html .= $_;
    }
    close(FILE);

    $orig_url = &read_orig_url($topic, $docno);
    $orig_encode_url = "/home/funayama/cvs/ISA/htmls/$topic/$docno";
}

$DetectBlocks->maketree($raw_html, $orig_url);
$DetectBlocks->detectblocks;
my $tree = $DetectBlocks->gettree;
$DetectBlocks->addCSSlink($tree, 'style.css');


open  F, "> ./COLOR_$pid.html" or die;
print F $tree->as_HTML("<>&","\t", {});
close F;

# 解析結果などを出力
if ($url || ($topic && $docno)) {
    if ($topic && $docno) {
	# http://www.anti-ageing.jp/show/d200609250001.html
	print qq(<a href="$orig_encode_url" target="_blank">色なし</a>, <a href="$orig_url" target="blank">$orig_url</a>, );
	(my $tmp_no = $docno) =~ s/\.html//;
	(my $tmp_url = $orig_url) =~ s/http\:\/\///;
	# http://www1.crawl.kclab.jgn2.jp/~akamine/cache/Agaricus/00001/web/www.keysoft.jp/abmk/index.html
	print qq(<a href="http://www1.crawl.kclab.jgn2.jp/~akamine/cache/$topic/00$tmp_no/web/$tmp_url" target="_blank">Cache</a><br>\n);
    } else {
	print qq(<a href="$url" target="_blank">元ページ</a><br>\n);
    }
    print qq(<strong>色 : </strong>);
    &read_and_print_colortable($CSS);

    if ($topic && $docno) {
	print qq(<strong>発信者\(正解\) : </strong>);
	print $ans_ref->{$topic}{$docno} ? $ans_ref->{$topic}{$docno} : 'なし';
	print qq(<br>\n);
    }
    print qq(<iframe src="./COLOR_$pid.html" width="100%" height="100%"></iframe>\n);
}

print << "END_OF_HTML";
</body>
</html>
END_OF_HTML

sub read_orig_url {
    my ($topic, $docno) = @_;
    my $orig_url;
    
    open URL, "<:encoding(utf8)", $ORIG_URL_LIST or die;
    while (<URL>) {
	my ($ltopic, $ldocno, $lurl) = split(/ /, $_);
	if ($topic eq $ltopic && $docno eq "$ldocno.html") {
	    $orig_url = $lurl;
	}
    }
    close URL;

    return $orig_url;
}


sub read_ISA_ans {
    my ($topic, $docno) = @_;
    my $ref;

    # Agaricus 001;キィーソフト株式会社;Keysoft Co., Ltd.
    open ISANS, "<:encoding(utf8)", $ISANS or die;
    while (<ISANS>) {
	chomp;
	my ($buf_topic, $buf) = split(/ /, $_, 2);
	my ($buf_docno, @cor) = split(/;/, $buf);

	$ref->{$topic}{$buf_docno.'.html'} = join(', ', @cor) if ($buf_topic eq $topic);
    }
    close ISANS;

    return $ref
}



sub read_and_print_colortable {
    my ($css_url) = @_;

    # CSSを読み込む
    my @buf;
    my $type;
    open CSS, "<:encoding(utf8)", $css_url or die;
    while (<CSS>) {
	chomp;
	next if $_ =~ /COLOR_TABLE/ || !$_;

	if ($_ =~ /Type \: ([^\s]+)/ || $_ =~ /END_OF_COLOR/) {
	    if (scalar @buf > 0) {
		print qq(&nbsp;&nbsp;$type : ),join(', ', @buf);
		last if  $_ =~ /END_OF_COLOR/;
	    }
	    @buf = ();
	    $type = $1;
	}
	elsif ($_ =~ /^\*\.(.+?) \{ background\-color \: (.+?) !important\; \}/) {
	    my ($tmp, $color) = ($1, $2);
	    $tmp =~ s/myblock_//;
	    push @buf,qq(<span style="background-color:$color">&nbsp;$tmp&nbsp;</span>);
	}
	elsif ($_ =~ /^\*\.(.+?) \{ border \: 5px (.+?) solid\; \}/) {
	    my ($tmp, $color) = ($1, $2);
	    $tmp =~ s/myblock_//;
	    push @buf,qq(<span style="border : 5px solid $color">&nbsp;$tmp&nbsp;</span>);
	}
    }
    close CSS;    

}

sub output_log {
    my $log = $_ ? $_ : "$topic.$docno";
    my $date = `date`;

    open  F, ">> ./url.log" or die;
    print F "$date\t$log\n";
    close F;
}

sub shellEsc {
    $_ = shift;
    s/([\&\;\`\'\\\"\|\*\?\~\<\>\^\(\)\[\]\{\}\$\n\r])/\\$1/g;
    return $_;
}

