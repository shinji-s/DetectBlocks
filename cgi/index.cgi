#!/usr/bin/env perl

# $Id$

# 使い方
# COLOR.cgiとstyle.cssを$HOME/public_html以下の同じディレクトリに置く

use strict;
use utf8;
use CGI;
use Dumpvalue;
use CGI::Carp qw(fatalsToBrowser);

my $uname = `uname -n`;
my $bit32 = $uname =~ /^reed/ ? 1 : 0;

# スタイルシートのパス
my $CSS = './style.css';

my ($DetectBlocks_default, $DetectSender_default, $NE_default, $Utils_default);
my ($DetectBlocks_ROOT, $DetectSender_ROOT, $NE_ROOT, $Utils_ROOT, $cgi);
BEGIN {
    # 各cvsのdefaultとするRootディレクトリ
    $DetectBlocks_default = '/home/funayama/cvs/DetectBlocks';
    $DetectSender_default = '/home/funayama/DetectSender';
    $NE_default = '/home/funayama/M1_2008/NE';
    $Utils_default = '/home/funayama/cvs/Utils';

    $cgi = new CGI;
    # ROOTの場所を指定
    $DetectBlocks_ROOT = $cgi->param('DetectBlocks_ROOT') ? $cgi->param('DetectBlocks_ROOT') : $DetectBlocks_default;
    $DetectSender_ROOT = $cgi->param('DetectSender_ROOT') ? $cgi->param('DetectSender_ROOT') : $DetectSender_default;
    $NE_ROOT = $NE_default;
    $Utils_ROOT = $Utils_default;
}
use lib split(' ', qq($DetectBlocks_ROOT/perl $DetectSender_ROOT/perl $Utils_ROOT/perl $NE_ROOT/perl));
use DetectBlocks2;
use DetectSender;
use Utils;
use ReadConf;

# 表示に必要なデータ
my $ISANS = $DetectBlocks_ROOT.'/sample/siteop-20080702.dat'; # 発信者の正解データ
my $ORIG_URL_LIST = $DetectBlocks_ROOT.'/sample/icc-url.txt'; # 元URLリストのパス

$| = 1;

# 発信者解析を行うかどうか
my $DetectSender_flag = $cgi->param('DetectSender_flag');

# 領域抽出のoption
my %blockopt = (get_more_block => 1, add_class2html => 1);
# 発信者解析のoption
my %senderopt = (evaluate => 1, ExtractCN => 1, no_dupl => 1, robot_name => '090826', add_class2html => 1, get_more_block => 1);

# 表示の際に相対パスを絶対パスに直すか
$blockopt{rel2abs} = $cgi->param('rel2abs');

my $pid = $$;
my $url = $cgi->param('inputurl');
my $topic = $cgi->param('topic');
my $docno = $cgi->param('docno');
# for API (xml)
my $format = $cgi->param('format');
my $DetectSender_flag = 1 if $format;

if ($format) {
    print $cgi->header(-charset => 'utf8', -type => "text/$format");
}
else {
    print $cgi->header(-charset => 'utf-8');
}    

# urlチェック
if ($url && $url !~ /^http\:\/\//) {
    print qq(<font color="red">Please Type Collect URL!!</font><br>\n);
    $url = '';
}
$url = &shellEsc($url);

# ログ
&output_log($url);

# header
&print_header unless $format; 

my $ans_ref;
# form
&print_form unless $format;

## 解析
# 対象ページ解析
my ($raw_html, $orig_url);
my $DetectBlocks = new DetectBlocks2(\%blockopt);

# HTMLソースを取得
if ($url) {
    ($raw_html, $orig_url) = $DetectBlocks->Get_Source_String($url);
}
# キャッシュ
elsif ($topic && $docno) {
    open(FILE, "<:utf8", "$DetectBlocks_ROOT/sample/htmls/$topic/$docno");
    while(<FILE>){
	$raw_html .= $_;
    }
    close(FILE);
    $orig_url = &read_orig_url($topic, $docno);
}

$DetectBlocks->maketree($raw_html, $orig_url);
$DetectBlocks->detectblocks;
my $tree = $DetectBlocks->gettree;
$DetectBlocks->addCSSlink($tree, 'style.css');

# 発信者解析を行う
my $DetectSender;
if ($DetectSender_flag && (($topic && $docno) || $url)) {
    my $config = &read_config({32 => $bit32});
    my @urls;

    $DetectSender = new DetectSender(\%senderopt, $config);
    
    $DetectSender->DetectSender($tree, $url);

    # "Xのページ => X"など
    $DetectSender->ReplaceString;

    # 文単位でFiltering -> 名詞句抽出 -> 名詞句単位でFiltering
    $DetectSender->SelectCandidates;
    
    unless ($format) {
	# 発信者を表示
	print qq(発信者候補 : <select name="topic">\n);
	foreach my $sender ($DetectSender->Display_Information_Sender({array => 'all'})) {
	    print qq(<option>$sender</option>\n);
	}
	print qq(</select>\n&nbsp;&nbsp;)
    }
}

# API
if ($format eq 'xml') {
    &print_xml;
}
else {
    my $output_html = $tree->as_HTML("<>&","\t", {});
    # API
    if ($format eq 'html') {
	print $output_html;
    }
    # CGI
    else {
        # 色つきのhtmlを別ファイルに掃く
	open  F, "> ./sender_$pid.html" or die;
	print F $output_html;
	close F;

	if ($url || ($topic && $docno)) {
	    # ナビゲーション的なリンク
	    &print_link;

	    # 色づかいの表示
	    &read_and_print_colortable($CSS);

	    # 正しい発信者の表示
	    &print_correct_sender;

	    # 解析結果などを出力
	    print qq(<iframe src="./sender_$pid.html" width="100%" height="100%"></iframe>\n);
	}
    }
}

# footer
&print_footer unless $format;







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

    print qq(<strong>色 : </strong>);

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

sub print_header {

print <<"END_OF_HTML";
<html lang="ja">
<head><title>ページ領域抽出CGI</title></head>
END_OF_HTML

}

sub print_form {

print <<"END_OF_HTML";
<body>
<form method="GET" action="$ENV{SCRIPT_NAME}">
block:<input type="text" name="DetectBlocks_ROOT" value="$DetectBlocks_ROOT" size="40">, 
sender:<input type="text" name="DetectSender_ROOT" value="$DetectSender_ROOT" size="40">,
END_OF_HTML

    my $checkedsender = $DetectSender_flag ? ' checked' : '';
    print qq(発信者解析:<input type="checkbox" name="DetectSender_flag" value="1"$checkedsender>);

    my $checkedabs = $blockopt{rel2abs} ? ' checked' : '';
    print qq(絶対パス:<input type="checkbox" name="rel2abs" value="1"$checkedabs>);

    print qq(<input type="hidden" name="input_url" value="$url">\n) if ($url);
    print qq(<input type="hidden" name="topic" value="$topic">\n) if ($topic);
    print qq(<input type="hidden" name="docno" value="$docno">\n) if ($docno);

print << "END_OF_HTML";
<input type="submit" value="Send">
</form>
<form method="GET" action="$ENV{SCRIPT_NAME}">
<input type="hidden" name="DetectBlocks_ROOT" value="$DetectBlocks_ROOT" size="50">
<input type="hidden" name="DetectSender_ROOT" value="$DetectSender_ROOT" size="50">
END_OF_HTML

    if ($url) {
        print qq(URLを指定 : <input type="text" name="inputurl" value="$url" size="50">);
    } else {
        $ans_ref = &read_ISA_ans($topic, $docno);
        print qq(URLを指定 : <input type="text" name="inputurl" value="http://www.kyoto-u.ac.jp/ja" size="50">);
    }

print << "END_OF_HTML";
<input type="hidden" name="DetectSender_flag" value="$DetectSender_flag">
<input type="hidden" name="rel2abs" value="$blockopt{rel2abs}">
<input type="submit" value="Send">
</form>
END_OF_HTML

# ディレクトリを調べる
opendir(DIR, "$DetectBlocks_ROOT/sample/htmls/");
my @topic = readdir(DIR);
closedir(DIR);

# トピック
print << "END_OF_HTML";
<form method="GET" action="$ENV{SCRIPT_NAME}">\n
<input type="hidden" name="DetectBlocks_ROOT" value="$DetectBlocks_ROOT" size="50">
<input type="hidden" name="DetectSender_ROOT" value="$DetectSender_ROOT" size="50">
TOPIC:<select name="topic">
END_OF_HTML

    if (!$topic) {
        print qq(<option selected="selected" value="">Select Topic</option>\n);
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
    print qq(</select>);


    # 文書番号
    if ($topic) {
	# ファイルを調べる
	opendir(F, "$DetectBlocks_ROOT/sample/htmls/$topic");
	my @docno = sort readdir(F);
	closedir(F);

	print qq(ID:<form method="GET" action="$ENV{SCRIPT_NAME}">\n);

	print qq(<select name="docno" width="100">\n);
	if (!$docno) {
	    print qq(<option name="docno" value="" selected="selected">Select Document</option>\n);	
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
<input type="hidden" name="DetectSender_flag" value="$DetectSender_flag">
<input type="hidden" name="rel2abs" value="$blockopt{rel2abs}">
<input type="submit" value="Send">
</form>
END_OF_HTML
}

sub print_footer {
print << "END_OF_HTML";
</body>
</html>
END_OF_HTML
}

sub print_xml {
    require XML::Writer;

    my $writer = new XML::Writer(OUTPUT => *STDOUT, DATA_MODE => 'true', DATA_INDENT => 2);    
    $writer->xmlDecl('utf-8');    

    $writer->startTag('information_senders');
    foreach my $sender ($DetectSender->Display_Information_Sender({array => 'sender'})) {
	$writer->startTag('information_sender');
	$writer->characters($sender);
	$writer->endTag('information_sender');
    }
    $writer->endTag('information_senders');

    $writer->end();
}

sub print_link {

    if ($topic && $docno) {
	# http://www.anti-ageing.jp/show/d200609250001.html
	print qq(<a href="$orig_url" target="blank">$orig_url</a>, );
	(my $tmp_no = $docno) =~ s/\.html//;
	(my $tmp_url = $orig_url) =~ s/http\:\/\///;
	$tmp_url .= '.html' if $tmp_url !~ /\.html?$/; # .phpとかの場合最後にhtmlがついてる
	# http://www1.crawl.kclab.jgn2.jp/~akamine/cache/Agaricus/00001/web/www.keysoft.jp/abmk/index.html
	print qq(<a href="http://www1.crawl.kclab.jgn2.jp/~akamine/cache/$topic/00$tmp_no/web/$tmp_url" target="_blank">Cache</a><br>\n);
    } else {
	print qq(<a href="$url" target="_blank">元ページ</a><br>\n);
    }
}

sub print_correct_sender {

    if ($topic && $docno) {
	print qq(<strong>発信者\(正解\) : </strong>);
	print $ans_ref->{$topic}{$docno} ? $ans_ref->{$topic}{$docno} : 'なし';
	print qq(<br>\n);
    }
}

