package DetectBlocks2;

# $Id$

use strict;
use utf8;
use HTML::TreeBuilder;
use Data::Dumper;
use Encode;
use Dumpvalue;

our $TEXTPER_TH = 0.5;

our $IMG_RATIO_TH = 0.8; # これより大きければimg (葉だけ数える)
our $FOOTER_RATIO_START_TH = 0.85; # これより大きければfooter
our $FOOTER_RATIO_END_TH = 0.95; # これより大きければfooter

our $ITERATION_BLOCK_SIZE = 4; # 繰り返しのかたまりの最大
our $ITERATION_TH = 3; # 繰り返し回数がこれ以上

# COPYRIGHT用の文字列
our $COPYRIGHT_STRING = 'Copyright|\(c\)|著作権|all\s?rights\s?reserved';

# FOOTER用の文字列
our $FOOTER_STRING = '住所|所在地|郵便番号|電話番号|著作権|問[い]?合[わ]?せ|利用案内|質問|意見|\d{3}\-?\d{4}|Tel|TEL|.+[都道府県].+[市区町村]|(06|03)\-?\d{4}\-?\d{4}|\d{3}\-?\d{3}\-?\d{4}|mail|Copyright|\(c\)|著作権|all\s?rights\s?reserved';

#maintext用の文字列
our $MAINTEXT_STRING = '。|、|ます|です|でした|ました';

sub new{
    my (undef, $opt) = @_;

    my $this = {};
    $this->{opt} = $opt;

    bless $this;
}

sub maketree{
    my ($this, $htmltext, $url) = @_;

    my $tree = HTML::TreeBuilder->new;
    $tree->parse($htmltext);
    $tree->eof;

    $this->{url} = $url if(defined($url));
    $this->{tree} = $tree;
}

sub detectblocks{
    my ($this) = @_;

    #url処理
    my $url;
    my $domain;
    $url = $this->{url} if(defined($this->{url}));
    if(defined($url)){
	# 例 : http://www.yahoo.co.jp/news => www.yahoo.co.jp
	if($url =~ /^http:\/\/\/?([.^\/]+)\// || $url =~ /^http:\/\/\/?([.^\/]+)$/){
	    $url = $1;
	}
	# ??
	if($url =~ /\/\/\/?([^\/]+)\// || $url =~ /\/\/\/?([^\/]+)$/){
	    $domain = $1;
	}
    }
    $this->{domain} = $domain;

    my @kariblockarr = ();
    $this->{blockarr} = \@kariblockarr;
    my $body = $this->{tree}->find('body');

    # 要コメント
    $body->objectify_text;

    $this->attach_elem_length($body);
    $this->{alltextlen} = $body->attr('length');

    $this->attach_offset_ratio($body);
    $this->get_subtree_string($body);
    $this->get_leaf_string($body);

    $this->detect_iteration($body);

    $this->detect_block($body);

    $this->text2div($body) if $this->{opt}{add_class2html};

#    $body->deobjectify_text;
}

sub detect_block {
    my ($this, $elem) = @_;

    my $leaf_string1 = $elem->attr('leaf_string');
    my $leaf_string2 = $elem->attr('leaf_string');

    if (!$elem->content_list || $elem->attr('length') / $this->{alltextlen} < $TEXTPER_TH) {
	# リンク領域
	if ($this->check_link_block($elem)) {
	    $elem->attr('myblocktype', 'link');
	}

	# img
	elsif ((($leaf_string1 =~ s/_img_//g) / ($leaf_string2 =~ s/_//g) * 2)
		> $IMG_RATIO_TH) {
	    $elem->attr('myblocktype', 'img');
	}

	# 中身なし
	elsif ($elem->attr('length') == 0) {
	    ;
	}

	# フッター
	elsif ($elem->attr('ratio_start') >= $FOOTER_RATIO_START_TH
	       && $elem->attr('ratio_end') >= $FOOTER_RATIO_END_TH
	       && $this->get_text($elem) =~ /$FOOTER_STRING/) {
	    $elem->attr('myblocktype', 'footer');
	}

	# 本文
	else {
	    $elem->attr('myblocktype', 'maintext');
	}

	# HTML表示用にクラスを付与する
	if ($this->{opt}{add_class2html}) {
	    my $orig_class = $elem->attr('class');
	    my $joint_class;

	    my $block_name = 'myblock_' . $elem->attr('myblocktype');
	    # 元のHTMLのクラスを残す
	    # ★ 表示上ややこしいのでいったんやめる
	    #  my $replaced_class = $orig_class ? $orig_class.' '. $block_name : $block_name;
	    my $replaced_class = $block_name;
	    $elem->attr('class' , $replaced_class);
	}
    }
    else {
	for my $child_elem ($elem->content_list){
	    $this->detect_block($child_elem);
	}
    }
}

sub check_link_block {
    my ($this, $elem) = @_;

    # <a>タグを含む繰り返しあり
    if ($elem->attr('iteration') =~ /_a_/) {
	return 1;
    }

    # 8割を超える子どもに<a>タグを含む繰り返しあり
    for my $child_elem ($elem->content_list){
	if ($elem->attr('length') && $child_elem->attr('length') / $elem->attr('length') > 0.8
	    && $child_elem->attr('iteration') =~ /_a_/) {
	    return 1;
	}
    }

    return 0;
}

sub attach_elem_length {
    my ($this, $elem) = @_;

    my $length_all = 0;

    # もう子供がいない
     if ($elem->content_list == 0){
	my $tag = $elem->tag;
	if ($tag eq 'img') {
	    $length_all = length($elem->attr("alt")) if (defined $elem->attr("alt"));
	}
	elsif ($tag eq '~text') {
	    $length_all = length($elem->attr("text"));
	}
	else {
	    $length_all = 0;
	}
    }
    # さらに子供をたどる
    else {
	for my $child_elem ($elem->content_list){
	    $length_all += $this->attach_elem_length($child_elem);
	}
    }

    # 属性付与
    $elem->attr('length', $length_all);

    return $length_all;
}

sub attach_offset_ratio {
    my ($this, $elem, $offset) = @_;

    # 属性付与
    $elem->attr('ratio_start', $offset / $this->{alltextlen});
    $elem->attr('ratio_end', ($offset + $elem->attr('length')) / $this->{alltextlen});

    # 累積
    my $accumulative_length = $offset;
    for my $child_elem ($elem->content_list){
	$this->attach_offset_ratio($child_elem, $accumulative_length);
	$accumulative_length += $child_elem->attr('length');
    }
}

sub gettree{
    my ($this) = @_;
    
    return $this->{tree};
}


sub settree{
    my ($this, $tree) = @_;

    $this->{tree} = $tree;
}

sub printtree {
    my ($this) = @_;

    my $body = $this->{tree}->find('body');

    $this->print_node($body, 0);
}

sub print_node {
    my ($this, $elem, $depth) = @_;

    return if ref($elem) ne 'HTML::Element';

    my $space = ' ' x ($depth * 2);
    my $length = $elem->attr('length');
    printf "%s %s [%d] (%.2f-%.2f)", $space, $elem->tag, $length, $elem->attr('ratio_start') * 100, $elem->attr('ratio_end') * 100;

    if ($elem->attr('myblocktype')) {
	print ' ★',  $elem->attr('myblocktype'), '★';
    }

    if ($elem->attr('iteration')) {
 	print ' 【', $elem->attr('iteration'), '】';
    }

    if ($elem->attr('text')) {
	print ' ', length $elem->attr('text') > 10 ? substr($elem->attr('text'), 0, 10) . '‥‥' : $elem->attr('text');
    }
    print "\n";

    # もう子供がいない
    if ($elem->content_list == 0){
	;
    }
    # さらに子供をたどる
    else {
	for my $child_elem ($elem->content_list){
	    $this->print_node($child_elem, $depth + 1);
	}
    }
}

sub get_subtree_string {
    my ($this, $elem) = @_;

    my $string = '_' . $elem->tag . '_';

    if ($elem->content_list) {
	$string .= '+';
	for my $child_elem ($elem->content_list){
	    $string .= $this->get_subtree_string($child_elem);
	}
	$string .= '-';
    }

    $elem->attr('subtree_string', $string);

    return $string;
}

sub get_leaf_string {
    my ($this, $elem) = @_;

    my $string;
    unless ($elem->content_list) {
	$string = '_' . $elem->tag . '_';
    }

    if ($elem->content_list) {
	$string .= '+';
	for my $child_elem ($elem->content_list){
	    $string .= $this->get_leaf_string($child_elem);
	}
	$string .= '-';
    }

    $elem->attr('leaf_string', $string);

    return $string;
}

sub detect_iteration {
    my ($this, $elem) = @_;

    # 子供がいない
    return if ($elem->content_list == 0);

    my @substrings;
    for my $child_elem ($elem->content_list){
	push @substrings, $child_elem->attr('subtree_string');
    }
    
  LOOP:
    for (my $i = 1; $i <= $ITERATION_BLOCK_SIZE; $i++) {

	# スタートポイント
	for (my $j = $i; $j < @substrings; $j++) {

	    my $k;
	    for ($k = $j; $k < @substrings; $k++) {
		last if ($substrings[$k] ne $substrings[$k - $i]);
	    }

	    # 繰り返し発見
	    if ($k - $j + $i >= $ITERATION_TH * $i) {
		$elem->attr('iteration', join(':', splice(@substrings, $j, $i)));
		last LOOP;
	    }
	}
    }

    for my $child_elem ($elem->content_list){
	$this->detect_iteration($child_elem);
    }
}

sub get_text {
    my ($this, $elem) = @_;

    my $text;
    if ($elem->tag eq '~text') {
	return $elem->attr('text');
    }
    for my $child_elem ($elem->content_list){
	$text .= $this->get_text($child_elem);
    }

    return $text;
}

# BLOCKをHTML上で色分けして表示するために整形
sub addCSSlink {
    my ($this, $tmp_elem, $css_url) = @_;

    # CSSの部分を追加
    # <link rel="stylesheet" type="text/css" href="style.css">
    my $head = $tmp_elem->find('head');
    $head->push_content(['link', {'href' => $css_url, 'rel' => 'stylesheet', 'type' => 'text/css'}]);
    # CSSの優先順位を変更
    my $tmp = $head->content->[-1];
    $head->content->[-1] = $head->content->[0];
    $head->content->[0] = $tmp;

    # エンコードをutf-8に統一
    # <meta http-equiv="Content-Type" content="text/html; charset=Shift_JIS">
    my $flag;
    foreach my $metatag ($head->find('meta')) {
	if ($metatag->look_down('content', qr/text\/html\;\s*charset\=(.+?)/i)) {
	    $metatag->delete;
	    last;
	}
    }
    $head->push_content(['meta', {'http-equiv' => 'Content-Type', 'content' => 'text/html; charset=utf-8'}]) if !$flag;
}

sub text2div {
    my ($this, $elem) = @_;

    if ($elem->content_list) {
	for my $child_elem ($elem->content_list) {
	    $this->text2div($child_elem);
	}
    }
    else {
	if($elem->tag eq '~text') {
	    $elem->tag("div");
	    $elem->push_content($elem->attr("text"));

	    $elem->attr("text", "");
	}
    }
}


1;
