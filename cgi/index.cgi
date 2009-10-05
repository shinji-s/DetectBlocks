#!/share/usr-x86_64/bin/perl

# $Id$

# 使い方
# index.cgiとstyle.cssを$HOME/public_html以下の同じディレクトリに置く

use strict;
use utf8;
use CGI;
use Dumpvalue;
use CGI::Carp qw(fatalsToBrowser);

my $uname = `uname -n`;
my $bit32 = $uname =~ /^reed/ ? 1 : 0;
my $bit_num = `uname -m`;
my $pid = $$;
my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
my $mmddhhmmJ = sprintf("%02d%02d-%02d%02d", $mon +1, $mday, $hour, $min);

# スタイルシートのパス
my $CSS = './style.css';

my ($DetectBlocks_default, $DetectSender_default, $NE_default, $Utils_default, $EBMT_default);
my ($DetectBlocks_ROOT, $DetectSender_ROOT, $NE_ROOT, $Utils_ROOT, $EBMT_ROOT, $cgi);
BEGIN {
    # 各cvsのdefaultとするRootディレクトリ
    # 開発版用
    $DetectBlocks_default = '/home/funayama/cvs/DetectBlocks';
    $DetectSender_default = '/home/funayama/DetectSender';
    # 安定版用
    # $DetectBlocks_default = '/home/funayama/cvs/stable/DetectBlocks';
    # $DetectSender_default = '/home/funayama/cvs/stable/DetectSender';

    $NE_default = '/home/funayama/M1_2008/NE';
    $Utils_default = '/home/funayama/cvs/Utils';
    $EBMT_default = '/home/funayama/cvs/EBMT';

    $cgi = new CGI;
    # ROOTの場所を指定
    $DetectBlocks_ROOT = $cgi->param('DetectBlocks_ROOT') ? $cgi->param('DetectBlocks_ROOT') : $DetectBlocks_default;
    $DetectSender_ROOT = $cgi->param('DetectSender_ROOT') ? $cgi->param('DetectSender_ROOT') : $DetectSender_default;
    $NE_ROOT = $NE_default;
    $Utils_ROOT = $Utils_default;
    $EBMT_ROOT = $EBMT_default;
}
use lib split(' ', qq($DetectBlocks_ROOT/perl $DetectSender_ROOT/perl $Utils_ROOT/perl $NE_ROOT/perl $EBMT_ROOT/lib));
use DetectBlocks2;
use DetectSender;
use BlogCheck;
use Utils;
use ReadConf;

# 表示に必要なデータ
my $ISANS = $DetectBlocks_ROOT.'/sample/siteop-20080702.dat'; # 発信者の正解データ
my $ORIG_URL_LIST = $DetectBlocks_ROOT.'/sample/icc-url.txt'; # 元URLリストのパス

$| = 1;

# 発信者解析を行うかどうか
my $DetectSender_flag = $cgi->param('DetectSender_flag');

# 領域抽出のoption
my %blockopt = (get_more_block => 1, add_class2html => 1, blogcheck => 1);
# 発信者解析のoption
my %senderopt = (evaluate => 1, ExtractCN => 1, no_dupl => 1, robot_name => '090826', add_class2html => 1, get_more_block => 1, debug2file => *DEBUG2FILE);
# 表示の際に相対パスを絶対パスに直すか
$blockopt{rel2abs} = $cgi->param('rel2abs');

my $url = $cgi->param('inputurl');
my $topic = $cgi->param('topic');
my $docno = $cgi->param('docno');
my $format = $cgi->param('format'); # for API (xml or html)
my $input_type = $cgi->param('input_type'); # URLを直接入力(url) or wisdomの文書セット(topic)
my $ne_type = $cgi->param('ne_type') ? $cgi->param('ne_type') : 'two_stage_NE'; # どこのNEを使うか(knp_ne_crf or two_stage_NE or no_NE)

($senderopt{NER}, $senderopt{necrf}) = $ne_type eq 'two_stage_NE' ? (1, 0) : ($ne_type eq 'knp_ne_crf' ? (1, 1) : (0, 0));
$DetectSender_flag = 1 if $format eq 'xml';

# url入力からtopic入力(or 逆)に変えた瞬間に解析してしまうのを防止
if ($input_type eq 'url' && $topic) {
    ($topic, $docno) = ('', '');
} elsif ($input_type eq 'topic' && $url) {
    $url = '';
}

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

# debugの出力
my $FH = $senderopt{debug2file};
my $log_file = './log/debug_'.$mmddhhmmJ.'_'.$pid.'.dat';
open $FH, "> $log_file" or die;

## 解析
# 対象ページ解析
my ($raw_html, $orig_url);
my $DetectBlocks = new DetectBlocks2(\%blockopt);
my $BlogCheck = new BlogCheck($DetectBlocks);

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

# 領域抽出
$DetectBlocks->maketree($raw_html, $orig_url);
$DetectBlocks->detectblocks;

# blogかどうか判断
$BlogCheck->blog_check;

# 後処理
my $tree = $DetectBlocks->gettree;
$DetectBlocks->addCSSlink($tree, 'style.css');
$DetectBlocks->post_process;

# 発信者解析を行う
my $DetectSender;
if ($DetectSender_flag && (($topic && $docno) || $url)) {

    my $config = &read_config({bit_num => $bit_num});
    my @urls;

    $DetectSender = new DetectSender(\%senderopt, $config);
    
    $DetectSender->DetectSender($tree, $url, $DetectBlocks->{alltextlen});

    # "Xのページ => X"など
    print $FH "--\n* Replace String\n";
    $DetectSender->ReplaceString;

    # 文単位でFiltering -> 名詞句抽出 -> 名詞句単位でFiltering
    print $FH "--\n* Filtering and Select Candidates\n";
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
	my $analysis_result_file = './analysis_result/sender_'.$mmddhhmmJ.'_'.$pid.'.html';
	open  F, "> $analysis_result_file" or die;
	print F $output_html;
	close F;

	if ($url || ($topic && $docno)) {
	    &print_link; # ナビゲーション的なリンク

	    &print_blogcheck_result;

	    &read_and_print_colortable($CSS); # 色づかいの表示
	    
	    &print_correct_sender; # 正しい発信者の表示

	    print qq(<iframe src="$analysis_result_file" width="100%" height="100%"></iframe>\n); # 解析結果などを出力
	}
    }
}

# footer
&print_footer unless $format;

close $FH;



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
    s/([\;\`\'\\\"\|\*\~\<\>\^\(\)\[\]\{\}\$\n\r])/\\$1/g;
    # s/([\&\;\`\'\\\"\|\*\?\~\<\>\^\(\)\[\]\{\}\$\n\r])/\\$1/g;
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
<form method="GET" action="$ENV{SCRIPT_NAME}">
block:<input type="text" name="DetectBlocks_ROOT" value="$DetectBlocks_ROOT" size="40">, 
sender:<input type="text" name="DetectSender_ROOT" value="$DetectSender_ROOT" size="40">,
END_OF_HTML

    my $checkedsender = $DetectSender_flag ? ' checked' : '';
    print qq(発信者解析:<input type="checkbox" name="DetectSender_flag" value="1"$checkedsender>, );

    my $checkedabs = $blockopt{rel2abs} ? ' checked' : '';
    print qq(絶対パス:<input type="checkbox" name="rel2abs" value="1"$checkedabs>, );

    my $ne_selected;
    $ne_selected->{$ne_type} = ' selected="selected"';
    print qq(固有表現解析:<select name="ne_type">\n);
    print qq(<option value="two_stage_NE"),$ne_selected->{two_stage_NE},qq(>two-stage-NE</option>\n);
    print qq(<option value="knp_ne_crf"),$ne_selected->{knp_ne_crf},qq(>knp -ne-crf</option>\n);
    print qq(<option value="no_NE"),$ne_selected->{no_NE},qq(>固有表現解析を行わない</option>\n);
    print qq(</select>\n);
    
    print qq(<br>\n);
    print qq(<select name="input_type">\n);

    # URL指定
    if ($input_type eq 'url') {
	print qq(<option selected="selected" value="url">URLを指定</option>);
	print qq(<option value="topic">TOPICを指定</option>);
	print qq(</select>);

	print qq(&nbsp;&nbsp;&nbsp;&nbsp;URLを入力 : );
	if ($url) {
	    print qq(<input type="text" name="inputurl" value="$url" size="50">);
	} else {
	    $ans_ref = &read_ISA_ans($topic, $docno);
	    print qq(<input type="text" name="inputurl" value="http://www.kyoto-u.ac.jp/ja" size="50">);
	}
    }
    # TOPIC指定
    elsif ($input_type eq 'topic') {
	$ans_ref = &read_ISA_ans($topic, $docno);
	
	print qq(<option value="url">URLを指定</option>);
	print qq(<option selected="selected" value="topic">TOPICを指定</option>);
	print qq(</select>);

        # ディレクトリを調べる
	opendir(DIR, "$DetectBlocks_ROOT/sample/htmls/");
	my @topic = readdir(DIR);
	closedir(DIR);

        # トピック
	print qq(\n&nbsp;&nbsp;&nbsp;&nbsp;TOPIC:<select name="topic">);
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

	    print qq(<form method="GET" action="$ENV{SCRIPT_NAME}">\n);

	    print qq(  ID:<select name="docno" width="100">\n);
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
    }
    else {
	print qq(<option value="url">URLを指定</option>);
	print qq(<option value="topic">TOPICを指定</option>);
	print qq(</select>);
    }
    print qq(<input type="submit" value="Send">);
    print qq(</form>);
}

sub print_blogcheck_result {

    print qq(, <font style="color:red;"><b>);
    print $BlogCheck::BLOG_FLAG == 1 ? qq(BLOG) : qq(not BLOG);
    print qq(</b></font>);
    print qq(<br>\n);
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
	$tmp_url .= '.html' if $tmp_url !~ /(\.html?|\/)$/; # .phpとかの場合最後にhtmlがついてる
	# http://www1.crawl.kclab.jgn2.jp/~akamine/cache/Agaricus/00001/web/www.keysoft.jp/abmk/index.html
	print qq(<a href="http://www1.crawl.kclab.jgn2.jp/~akamine/cache/$topic/00$tmp_no/web/$tmp_url" target="_blank">Cache</a>);
    } else {
	print qq(<a href="$url" target="_blank">元ページ</a>);
    }

    print qq(, <a href="$log_file" target="_blank">ログを表示</a>) if $DetectSender_flag;
}

sub print_correct_sender {

    if ($topic && $docno) {
	print qq(<strong>発信者\(正解\) : </strong>);
	print $ans_ref->{$topic}{$docno} ? $ans_ref->{$topic}{$docno} : 'なし';
	print qq(<br>\n);
    }
}

