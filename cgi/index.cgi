#!/share/usr-x86_64/bin/perl

# $Id$

# 使い方
# index.cgiとstyle.cssを$HOME/public_html以下の同じディレクトリに置く

use strict;
use utf8;
use CGI;
use Dumpvalue;
use CGI::Carp qw(fatalsToBrowser);
use Encode;
use Encode::Guess;

my $bit_num = `uname -m`;
my $pid = $$;
my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
my $mmddhhmmJ = sprintf("%02d%02d-%02d%02d", $mon +1, $mday, $hour, $min);

# CGIを設置したディレクトリ
my $CGI_DIR = '/home/funayama/public_html/ISA'; # 自分の環境にあわせて変更
# スタイルシートのパス
my $CSS = $CGI_DIR.'/style.css';

my ($api_method);
my ($DetectBlocks_default, $DetectSender_default, $NE_default, $Utils_default, $EBMT_default);
my ($DetectBlocks_ROOT, $DetectSender_ROOT, $NE_ROOT, $Utils_ROOT, $EBMT_ROOT, $cgi);
BEGIN {
    $api_method = $ENV{'REQUEST_METHOD'};

    # 各cvsのdefaultとするRootディレクトリ
    # 開発版用
    $DetectBlocks_default = '/home/funayama/DetectBlocks';
    $DetectSender_default = '/home/funayama/DetectSender';
    # 安定版用
    # $DetectBlocks_default = '/home/funayama/cvs/stable/DetectBlocks';
    # $DetectSender_default = '/home/funayama/cvs/stable/DetectSender';

    $NE_default = '/home/funayama/M1_2008/NE';
    $Utils_default = '/home/funayama/cvs/Utils';
    $EBMT_default = '/home/funayama/cvs/EBMT';

    # ROOTの場所を指定
    # POST
    if ($api_method eq 'POST') {
	$DetectBlocks_ROOT = $DetectBlocks_default;
	$DetectSender_ROOT = $DetectSender_default;
    }
    # GET
    else {
	$cgi = new CGI;
	$DetectBlocks_ROOT = $cgi->param('DetectBlocks_ROOT') ? $cgi->param('DetectBlocks_ROOT') : $DetectBlocks_default;
	$DetectSender_ROOT = $cgi->param('DetectSender_ROOT') ? $cgi->param('DetectSender_ROOT') : $DetectSender_default;
    }

    $NE_ROOT = $NE_default;
    $Utils_ROOT = $Utils_default;
    $EBMT_ROOT = $EBMT_default;
}
use lib split(' ', qq($DetectBlocks_ROOT/perl $DetectSender_ROOT/perl $Utils_ROOT/perl $NE_ROOT/perl $EBMT_ROOT/lib));
use DetectBlocks;
use DetectSender;
use BlogCheck;
use Utils;
use ReadConf;

# 表示に必要なデータ
my $ISANS = $DetectBlocks_ROOT.'/sample/091212_siteop_plus.dat'; # 発信者の正解データ
my $ORIG_URL_LIST = $DetectBlocks_ROOT.'/sample/icc-url.txt'; # 元URLリストのパス

$| = 1;

# 領域抽出のoption
my %blockopt = (get_more_block => 1, add_class2html => 1, blogcheck => 1, juman => 'kyoto_u'); # juman : 京大の環境
$blockopt{pos_info} = 1;
# 発信者解析のoption
my %senderopt = (evaluate => 1, ExtractCN => 1, add_class2html => 1, get_more_block => 1, debug2file => *DEBUG2FILE, no_dupl => 1);
# $senderopt{debug} = 1;

# 解析のためのパラメータを得る
my ($url, $topic, $pre_topic, $docno, $docno_num);
my ($input_type, $ne_type, $Trans_flag, $DetectSender_flag);
my ($format);
my ($feature_flag);
&get_param;

# inputurlに引数が入る場合用
$url =~ s/@/&/g;

($senderopt{NER}, $senderopt{necrf}) = $ne_type eq 'two_stage_NE' ? (1, 0) : ($ne_type eq 'knp_ne_crf' ? (1, 1) : (0, 0));
$senderopt{Trans} = $Trans_flag; # transliterationをマージするか

# url入力からtopic入力(or 逆)に変えた瞬間に解析してしまうのを防止
if ($input_type eq 'url' && $topic) {
    ($topic, $docno) = ('', '');
} elsif ($input_type eq 'topic' && $url) {
    $url = '';
}

# urlチェック
if ($url && $url !~ /^http\:\/\//) {
    print qq(<font color="red">Please Type Collect URL!!</font><br>\n);
    $url = '';
}
$url = &shellEsc($url);

# 何かしらの解析が行われるというflag
my $analysis_flag = ($input_type && ($url || ($topic && $docno))) || $format ? 1 : 0;

# header
&print_header unless $format; 

my $ans_ref;

# debugの出力
my ($FH, $log_file);
unless ($format) {
    $FH = $senderopt{debug2file};
    # $log_file = './log/debug_'.$mmddhhmmJ.'_'.$pid.'.dat';
    $log_file = $CGI_DIR.'/log/debug_'.$mmddhhmmJ.'_'.$pid.'.dat';
    open $FH, "> $log_file" or die;
}

## 解析
my $config = &read_config({bit_num => $bit_num});
my @urls;
# 周辺ページも解析を行うか
$senderopt{robot_name} = $DetectSender_flag && $cgi && $cgi->param('document_set') eq 'all' ? $config->{robot_name} : 0;

# 対象ページ解析
my ($DetectBlocks, $BlogCheck, $DetectSender);
my ($input_string, $url_orig);
my ($tree_orig, $title_text);
if ($analysis_flag) {
    $DetectBlocks = new DetectBlocks(\%blockopt);
    $BlogCheck = new BlogCheck($DetectBlocks, {dic_path => $DetectBlocks_ROOT.'/dic/blog_url_strings.dic'});
    $DetectSender = new DetectSender(\%senderopt, $config, {DetectBlocks => $DetectBlocks}) if $DetectSender_flag;

    # HTMLソースを取得
    if ($url) {
	($input_string, $url_orig) = $DetectBlocks->Get_Source_String($url);
	push @urls, {type => 'orig', url => $url_orig, filepath => undef, input_string => $input_string};
    }
    # POST
    elsif ($api_method eq 'POST') {
	my $length = $ENV{'CONTENT_LENGTH'} or 0;
	read(STDIN, $input_string, $length);
	$input_string = decode('utf8', $input_string);
	push @urls, {type => 'orig', url => 'http://100mangoku.net/', filepath => undef, input_string => $input_string};
    }
    # キャッシュ
    elsif ($topic && $docno) {
	# 解析対象ページをpush
	$input_string = &read_string_from_file("$DetectBlocks_ROOT/sample_pos_css/htmls/$topic/$docno");
	$url_orig = &read_orig_url($topic, $docno);
	push @urls, {type => 'orig', url => $url_orig, filepath => $ARGV[0], input_string => $input_string};
	# $DetectSender->{topic} = $topic;
	# $DetectSender->{docid} = $docno_num;

	# 解析対象ページ以外をpush
	if ($senderopt{robot_name}) {
	    my $other_file_dir = $config->{ROOT_DIR}.'/htmls/'.$senderopt{robot_name}.'/'.$topic.'/'.$docno_num;

	    if ($url_orig) {
		# リンク元の文字列やURLをみて解析するかどうかを判断
		my @URL_List = $DetectSender->Read_Other_URLs($other_file_dir, $url_orig);

		if (scalar @URL_List) {
		    foreach my $ref (@URL_List) {
			my $other_input_string = &read_string_from_file($ref->{filepath});
			push @urls, {type => 'other', url => $ref->{link}, filepath => $ref->{filepath}, input_string => $other_input_string,
				     link_string => join(', ', @{$ref->{link_string}})};
		    }
		}
	    }
	}
    }

    # 各URLごとに候補文を抽出
    my $analyze_page_flag = 1;
    foreach my $url_ref (@urls) {
	print $FH '>> ', $url_ref->{url},"\n" unless $format;

	## ページ領域抽出
	$DetectBlocks->maketree($url_ref->{input_string}, $url_ref->{url});
	$DetectBlocks->detectblocks;

	# blogかどうか判断
	$BlogCheck->blog_check;
	$DetectSender->{blog_flag} = $BlogCheck::BLOG_FLAG;

	# 後処理
	my $tree = $DetectBlocks->gettree;
	$DetectBlocks->addCSSlink($tree, 'style.css');
	$DetectBlocks->post_process;
	if ($url_ref->{type} eq 'orig') {
	    $tree_orig = $tree;
	    $title_text = defined $tree->find('title') ? $tree->find('title')->{'_content'}[0] : 'no_title';
	}

	# Dumpvalue->new->dumpValue($tree);
	# Dumpvalue->new->dumpValue($DetectBlocks);

	next if !$DetectSender_flag;

	if (ref($DetectBlocks->{url_layers_ref}) eq 'ARRAY') {
	    $url_ref->{url_info}{depth} = scalar @{$DetectBlocks->{url_layers_ref}};
	}
	if ($analyze_page_flag) {
	    $url_ref->{url_info}{analyze_page_flag} = 1;
	    $analyze_page_flag = 0;
	}
	# 発信者解析を行う
	$DetectSender->DetectSender($tree, $url_ref, $DetectBlocks->{alltextlen});

	# Dumpvalue->new->dumpValue($DetectSender);
    }
}

# form
&print_form unless $format;

if ($analysis_flag) {
    if ($DetectSender_flag) {
	# "Xのページ => X"など
	print $FH "--\n* Replace String\n" unless $format; 
	$DetectSender->ReplaceString;

	# Dumpvalue->new->dumpValue($DetectSender);

	# 文単位でFiltering -> 名詞句抽出 -> 名詞句単位でFiltering
	print $FH "--\n* Filtering and Select Candidates\n" unless $format;
	$DetectSender->SelectCandidates;
	
	if ($feature_flag) {
	    $senderopt{feature_K} = 1;

	    use ModelsK;
	    my $ModelsK = new ModelsK($DetectSender, \%senderopt, $config);
	    $ModelsK->{DetectSender} = $DetectSender;

	    $ModelsK->Get_Feature_K;
	    exit;
	}

	unless ($format) {
	    # 発信者を表示
	    print qq(<span style="font-size:10pt;">発信者候補 : </span><select>\n);
	    foreach my $sender ($DetectSender->Display_Information_Sender({array => 'all'})) {
		print qq(<option>$sender</option>\n);
	    }
	    print qq(</select>\n&nbsp;&nbsp;)
	}
    }

    # ログ
    &output_log($url) unless $format;

    # API
    if ($format eq 'xml') {
	&print_xml;
    }
    else {
	my $output_html = $tree_orig->as_HTML("<>&","\t", {});
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

	    &print_correct_sender; # 正しい発信者の表示
	    &read_and_print_colortable($CSS); # 色づかいの表示
	    print qq(<iframe src="$analysis_result_file" width="100%" height="100%"></iframe>\n); # 解析結果などを出力
	}
    }
}

# footer
&print_footer unless $format;

close $FH  unless $format;



sub read_orig_url {
    my ($topic, $docno) = @_;
    my $url_orig;
    
    open URL, "<:encoding(utf8)", $ORIG_URL_LIST or die;
    while (<URL>) {
	my ($ltopic, $ldocno, $lurl) = split(/ /, $_);
	if ($topic eq $ltopic && $docno eq "$ldocno.html") {
	    $url_orig = $lurl;
	}
    }
    close URL;

    return $url_orig;
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

    print qq(<div id="color_parts" style="display:none;font-size:10pt;margin-bottom:3px;");
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
		# print qq(&nbsp;&nbsp;$type : ),join(', ', @buf);
		print qq(&nbsp;&nbsp;&nbsp;),join(', ', @buf);
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

    print qq(</div>);
}

sub output_log {
    my ($url) = @_;

    my $log = $url ? $url : "$topic.$docno";
    my $date = `date +%Y年%m月%d日_%A_%H時%M分%S秒`;
    my $today = `date +%y%m%d`;
    chomp($today);

    # open  F, ">> ./url_log/url_".$today.'.log' or die;
    open  F, ">> $CGI_DIR/url_log/url_".$today.'.log' or die;
    print F '-' x 100,"\n";
    print F "DATE: $date";
    print F "PID: $pid\n";
    print F "URL: $log\n";
    print F "BLOG: ", $BlogCheck::BLOG_FLAG,"\n";
    if ($DetectSender_flag) {
	print F "SENDER:\n";
	foreach my $sender ($DetectSender->Display_Information_Sender({array => 'all'})) {
	    print F "\t$sender\n";
	}
    }
    if ($ENV{REMOTE_ADDR}) {
	my $env = "";
	# for ("HTTP_REFERER", "HTTP_FROM", "HTTP_USER_AGENT", "REMOTE_HOST", "REMOTE_ADDR", "REMOTE_PORT") {
	for ("SCRIPT_NAME", "QUERY_STRING", "HTTP_FROM", "HTTP_USER_AGENT", "REMOTE_HOST", "REMOTE_ADDR", "REMOTE_PORT") {
	    if ($ENV{$_}) {
		chomp $ENV{$_};
		$env .= "$_: $ENV{$_}\n";
	    }
	}
	print F $env;
    }
    close F;
}

sub shellEsc {
    $_ = shift;
    s/([\;\`\'\\\"\|\*\<\>\^\(\)\[\]\{\}\$\n\r])/\\$1/g;
    # s/([\&\;\`\'\\\"\|\*\?\~\<\>\^\(\)\[\]\{\}\$\n\r])/\\$1/g;
    return $_;
}

sub print_header {

print <<"END_OF_HTML";
<html lang="ja">
<head>
<title>ページ領域抽出CGI</title>
<script type="text/javascript">
<!--
function gotoNextSelect(obj) {
    var arg=new Array();

    for(var i=0;i<obj.elements.length;i++){
	var elem_value = obj.elements[i].value;
	var elem_type = obj.elements[i].type;
	var elem_name = obj.elements[i].name;

	if (elem_type == 'checkbox' || elem_type == 'radio') {
	    if (obj.elements[i].checked == true) {
		arg.push(obj.elements[i].name+'='+elem_value);
	    }
	}
	else if (elem_type == 'text') {
	    if (elem_value.search(/.+/) != -1) {
		arg.push(obj.elements[i].name+'='+elem_value);
	    }		
	}
	else if (elem_type == 'select-one') {
	    arg.push(obj.elements[i].name+'='+elem_value);
	}
    }
    location.href="$ENV{SCRIPT_NAME}"+'?'+arg.join('&');
}

function reset_param() {
    location.href="$ENV{SCRIPT_NAME}";
}

function toggle(id) {
    if (document.getElementById(id).style.display == "none") {
	document.getElementById(id).style.display = "block";
    } else {
	document.getElementById(id).style.display = "none";
    }
}

function disableunder() {
    var array=document.getElementById('sender_option').getElementsByTagName('input');

    if (document.getElementById('DetectSender_flag').checked==true) {
	for(var i=0; i<array.length; i++) {
	    array[i].disabled=false;
	}
	document.getElementById('sender_option').style.color = "black"
    }
    else {
	for(var i=0; i<array.length; i++) {
	    array[i].disabled=true;
	}
	document.getElementById('sender_option').style.color = "#888888";
    }
}
// -->
</script>

</head>
END_OF_HTML

}

sub print_url_log {
    opendir(DIR, "$CGI_DIR/url_log");
    my @url_logs = readdir(DIR);
    closedir(DIR);
    
    # url_091019.log
    my $date_ref;
    foreach my $url_log (@url_logs) {
	my ($yy, $mm, $dd) = ($url_log =~ /^url_(\d{2})(\d{2})(\d{2}).log$/);
	$date_ref->{'20'.$yy}{$mm}{$dd} = $url_log if $yy && $mm && $dd;
    }

    print qq(<ul style="margin:0px;">\n);
    foreach my $year (sort keys %$date_ref) {
	print qq(<li>$year</li>\n);
	print qq(<ul style="margin:0px;">\n);
	foreach my $month (sort keys %{$date_ref->{$year}}) {
	    print qq(<li>$month&nbsp;-&nbsp;);
	    foreach my $day (sort keys %{$date_ref->{$year}{$month}}) {
		print qq(<a href="./url_log/).$date_ref->{$year}{$month}{$day}.qq(" target="_blank">$day</a>&nbsp;);
	    }
	    print qq(</li>\n);
	}
	print qq(</ul>\n);
    }
    print qq(</ul>\n);

}

sub print_form {

    print qq(<span style="font-size:10pt;">);
    print qq([<a href="javascript:void(0)" onclick="toggle('option')">■option表示/非表示</a>]);
    print qq(&nbsp;&nbsp;[<a href="javascript:void(0)" onclick="toggle('color_parts')">■色使いの表示/非表示</a>]) if $analysis_flag;
    print qq(&nbsp;&nbsp;[<a href="javascript:void(0)" onclick="toggle('url_log')">■URLのLOG</a>]);
    if ($analysis_flag) {
	&print_link;
	&print_blogcheck_result;
    }
    print qq(</span>);

    print qq(<div id="url_log" style="display:none;border:1px dashed black;background-color:#dddddd;font-size:10pt;margin:0 0 5px 0;">);
    &print_url_log;
    print qq(</div>);


print <<"END_OF_HTML";
<form method="GET" action="$ENV{SCRIPT_NAME}" style="margin:0px;" id="myoption" name="myoption">
<div id="option" style="display:none;border:1px dashed black;background-color:#dddddd;font-size:10pt;margin:0 0 5px 0;">
■解析に用いるモジュールを指定<br>
&nbsp;&nbsp;&nbsp;&nbsp;DetectBlocks&nbsp;:&nbsp;<input type="text" name="DetectBlocks_ROOT" value="$DetectBlocks_ROOT" size="100"><br> 
&nbsp;&nbsp;&nbsp;&nbsp;DetectSender&nbsp;:&nbsp;<input type="text" name="DetectSender_ROOT" value="$DetectSender_ROOT" size="100"><br>
END_OF_HTML

    my $checkedsender = $DetectSender_flag ? ' checked' : '';
    print qq(■<input type="checkbox" name="DetectSender_flag" id="DetectSender_flag" value="1" onchange="disableunder()"$checkedsender>発信者解析<br>);

    my ($disabled, $disabled_color) = !$DetectSender_flag ? (' disabled',  qq( style="color:#888888;")) : ('', '');
    print qq(<div id="sender_option"$disabled_color>\n);
    my $checkeddocset = $cgi->param('document_set') ? ' checked' : '';
    print qq(&nbsp;&nbsp;&nbsp;&nbsp;<input type="checkbox" name="document_set"$disabled value="all"$checkeddocset>周辺ページも解析(時間がかかるため固有表現解析OFFを推奨)<br>) if $input_type eq 'topic';

    my $ne_selected;
    $ne_selected->{$ne_type} = ' checked';
    print qq(&nbsp;&nbsp;&nbsp;&nbsp;固有表現解析:);
    print qq(<input type="radio" name="ne_type"$disabled value="two_stage_NE"),$ne_selected->{two_stage_NE},qq(>two-stage-NE&nbsp;&nbsp);
    print qq(<input type="radio" name="ne_type"$disabled value="knp_ne_crf"),$ne_selected->{knp_ne_crf},qq(>knp -ne-crf&nbsp;&nbsp);
    print qq(<input type="radio" name="ne_type"$disabled value="no_NE"),$ne_selected->{no_NE},qq(>固有表現解析を行わない);
    print qq(<br>\n);
    
    my $checkedtrans = $Trans_flag ? ' checked' : '';
    print qq(&nbsp;&nbsp;&nbsp;&nbsp;<input type="checkbox" name="Trans_flag"$disabled value="1"$checkedtrans>Transliteration<br>\n);
    print qq(</div>\n);

    my $checkedabs = $blockopt{rel2abs} ? ' checked' : '';
    print qq(■その他<br>\n);
    print qq(&nbsp;&nbsp;&nbsp;&nbsp;<input type="checkbox" name="rel2abs" value="1"$checkedabs>相対パスを絶対パスに変換<br>\n);
    print qq(</div>);

    print qq(<input type="hidden" name="pre_topic" id="pre_topic" value="$topic">\n);

    # print qq(<select name="input_type" id="input_type" onchange="gotoNextSelect(this.form)">\n);
    print qq(<select name="input_type" id="input_type" onchange="myoption.submit();">\n);
    if ($input_type eq '') {
	print qq(<option value="0">Select method</option>);
    }
    # URL指定
    if ($input_type eq 'url') {
	print qq(<option value="topic">TOPICを指定</option>);
	print qq(<option selected="selected" value="url">URLを指定</option>);
	print qq(</select>);

	my $value_of_url;
	if ($url) {
	    $value_of_url = $url;
	} else {
	    $value_of_url = 'http://www.kyoto-u.ac.jp/ja';
	    $ans_ref = &read_ISA_ans($topic, $docno);
	}
	print qq(<input type="text" name="inputurl" id="inputurl" value="$value_of_url" size="50">);
	print qq(<input type="submit" value="解析">);
	print qq(<input type="button" value="Reset" onclick="reset_param()">);
    }
    # TOPIC指定
    elsif ($input_type eq 'topic') {
	$ans_ref = &read_ISA_ans($topic, $docno);
	
	print qq(<option selected="selected" value="topic">TOPICを指定</option>);
	print qq(<option value="url">URLを指定</option>);
	print qq(</select>);

        # ディレクトリを調べる
	opendir(DIR, "$DetectBlocks_ROOT/sample/htmls/");
	my @topic = readdir(DIR);
	closedir(DIR);

        # トピック
	# print qq(<select name="topic" id="topic" onchange="gotoNextSelect(this.form)">);
	print qq(<select name="topic" id="topic" onchange="myoption.submit();">);
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

	    # print qq(<select name="docno" id="docno" onchange="gotoNextSelect(this.form)">\n);
	    print qq(<select name="docno" id="docno" onchange="myoption.submit();">\n);
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
	    if ($analysis_flag) {
		print qq(<input type="submit" value="解析">);
		print qq(<input type="button" value="Reset" onclick="reset_param()">);
	    }
	}
    }
    else {
	print qq(<option value="topic">TOPICを指定</option>);
	print qq(<option value="url">URLを指定</option>);
	print qq(</select>);
    }
    print qq(</form>);

print << "END_OF_HTML";
END_OF_HTML
}

sub print_blogcheck_result {

    print qq(&nbsp;&nbsp;[BLOG判定:<font style="color:);
    print $BlogCheck::BLOG_FLAG == 1 ? qq(red;"><b>BLOG) : qq(blue;"><b>notBLOG);
    print qq(</b></font>]);
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
    foreach my $ref ($DetectSender->Display_Information_Sender({array => 'sender'})) {
	next if ref($ref->{blocktype}) ne 'ARRAY';
	$writer->startTag('information_sender');

	$writer->startTag('blocktypes');
	foreach my $blocktype (@{$ref->{blocktype}}) {
	    # <blocktype>footer</blocktype>
	    $writer->startTag('blocktype');
	    $writer->characters($blocktype);
	    $writer->endTag('blocktype');
	}
	$writer->endTag('blocktypes');

	# <string>金沢市産業局観光交流課</string>
	$writer->startTag('string');
	$writer->characters($ref->{string});
	$writer->endTag('string');

	$writer->endTag('information_sender');
    }
    $writer->endTag('information_senders');

    $writer->end();
}

sub print_link {

    if ($topic && $docno) {
	# http://www.anti-ageing.jp/show/d200609250001.html
	print qq(&nbsp;&nbsp;[<a href="$url_orig" target="blank">▽解析対象ページ</a>);
	my $counter = 1;
	foreach my $url_ref (@urls) {
	    if ($url_ref->{type} eq 'other') {
		print qq(,&nbsp;<a href="),$url_ref->{url},qq(" target="blank" title="),$url_ref->{link_string},qq( % ),$url_ref->{url},qq(">▽$counter</a>);
		$counter++;
	    }
	}
	print qq(]);
	(my $tmp_url = $url_orig) =~ s/http\:\/\///;
	$tmp_url .= '.html' if $tmp_url !~ /(\.html?|\/)$/; # .phpとかの場合最後にhtmlがついてる
	# http://www1.crawl.kclab.jgn2.jp/~akamine/cache/Agaricus/00001/web/www.keysoft.jp/abmk/index.html
	print qq(&nbsp;&nbsp;[<a href="http://www1.crawl.kclab.jgn2.jp/~akamine/cache/$topic/00$docno_num/web/$tmp_url" target="_blank">▽Cacheを表示</a>]);
    } else {
	print qq(&nbsp;&nbsp;[<a href="$url" target="_blank">▽解析対象ページ</a>]);
    }

    print qq(&nbsp;&nbsp;[<a href="$log_file" target="_blank">▽LOGを表示</a>]) if $DetectSender_flag;

    print qq(&nbsp;&nbsp;[title:),length($title_text) > 20 ? substr($title_text, 0, 20).'...' : $title_text, qq(]);
}

sub print_correct_sender {

    if ($topic && $docno) {
	print qq(<span style="font-size:10pt;">);
	print qq(<strong>発信者\(正解\) : </strong>);
	print $ans_ref->{$topic}{$docno} ? $ans_ref->{$topic}{$docno} : 'なし';
	print qq(</span>);
	print qq(<br>\n);
    }
}

sub get_param {
    # POST
    if ($api_method eq 'POST') {
	$format		   = 'xml';
	$ne_type	   = 'two_stage_NE';
	$DetectSender_flag = 1;
	$feature_flag	   = 1 if $ENV{HTTP_FEATURE};

	print "Content-type: text/xml\n\n";
    }
    # GET
    else {
	$url	      = $cgi->param('inputurl');
	$feature_flag = $cgi->param('feature');
	$topic	      = $cgi->param('topic');
	$docno	      = $cgi->param('docno');
	($docno_num   = $docno) =~ s/\.html$//;
	$format	      = $cgi->param('format'); # for API (xml or html)
	$input_type   = $cgi->param('input_type'); # URLを直接入力(url) or wisdomの文書セット(topic)
	$ne_type      = $cgi->param('ne_type') ? $cgi->param('ne_type') : 'two_stage_NE'; # どこのNEを使うか(knp_ne_crf or two_stage_NE or no_NE)
	$Trans_flag   = $cgi->param('Trans_flag'); # Transliteration

	$pre_topic = $cgi->param('pre_topic');
	undef $docno if $topic && $topic ne $pre_topic;

        # 表示の際に相対パスを絶対パスに直すか
	$blockopt{rel2abs} = $cgi->param('rel2abs');
	
        # 発信者解析を行うかどうか
	$DetectSender_flag = $format eq 'xml' ? 1 : $cgi->param('DetectSender_flag');

	print $format ? $cgi->header(-charset => 'utf8', -type => "text/$format") : $cgi->header(-charset => 'utf-8');
    }
}
