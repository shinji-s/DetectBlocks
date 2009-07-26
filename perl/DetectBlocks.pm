package DetectBlocks2;

# $Id$

use strict;
use utf8;
use HTML::TreeBuilder;
use Data::Dumper;
use Encode;
use Dumpvalue;
use Juman;

our $TEXTPER_TH = 0.5;

our $FOOTER_START_TH = 300; # これより大きければfooter
our $FOOTER_END_TH = 100; # これより大きければfooter
our $LINK_RATIO_TH = 0.7; #link領域の割合
our $IMG_RATIO_TH = 0.8; # これより大きければimg (葉だけ数える)

our $ITERATION_BLOCK_SIZE = 8; # 繰り返しのかたまりの最大
our $ITERATION_TH = 2; # 繰り返し回数がこれ以上

our $MAINTEXT_MIN = 200;

# COPYRIGHT用の文字列
our $COPYRIGHT_STRING = 'Copyright|\(c\)|著作権|all\s?rights\s?reserved';

# プロフィール領域用の文字列
our $PROFILE_STRING = '管理人|氏名|名前|ニックネーム|id|ユーザ[名]?|[user][\-]?id|性別|出身|年齢|アバター|プロフィール|profile|自己紹介';

# FOOTER用の文字列
our $FOOTER_STRING = '住所|所在地|郵便番号|電話番号|著作権|問[い]?合[わ]?せ|利用案内|質問|意見|\d{3}\-?\d{4}|Tel|TEL|.+[都道府県].+[市区町村]|(06|03)\-?\d{4}\-?\d{4}|\d{3}\-?\d{3}\-?\d{4}|mail|Copyright|\(c\)|著作権|all\s?rights\s?reserved|免責事項|プライバシー.?ポリシー|HOME|ホーム';

# maintext用の文字列
our $MAINTEXT_STRING = '。|、|ます|です|でした|ました';
our $MAINTEXT_PARTICLE_TH = 0.05; # 助詞の全形態素に占める割合がこれ以上なら本文
our $MAINTEXT_POINT_TH = 0.05; # 句点の全形態素に占める割合がこれ以上なら本文

# 以下のtagは解析対象にしない
our $TAG_IGNORED = '^(script|style|br|option)$';

# 以下のtagを子供以下にふくむ場合は領域を分割
our @MORE_DIVIDE_TAG = qw/address form/;

#ブロックタグのハッシュ
our %BLOCK_TAGS = (
                   address => 1,
                   blockquote => 1,
                   caption => 1,
                   center => 1,
                   dd => 1,
                   dir => 1,
                   div => 1,
                   dl => 1,
                   dt => 1,
                   fieldset => 1,
                   form => 1,
                   h1 => 1,
                   h2 => 1,
                   h3 => 1,
                   h4 => 1,
                   h5 => 1,
                   h6 => 1,
                   hr => 1,
                   isindex => 1,
                   li => 1,
                   listing => 1,
                   menu => 1,
                   multicol => 1,
                   noframes => 1,
                   noscript => 1,
                   ol => 1,
                   option => 1,
                   p => 1,
                   plaintext => 1,
                   pre => 1,
                   select => 1,
                   table => 1,
                   tbody => 1,
                   td => 1,
                   tfoot => 1,
                   th => 1,
                   thead => 1,
                   tr => 1,
                   ul => 1,
                   xmp => 1,
		   br => 1
		       );
# あるブロック以下の全てのブロックのテキスト量が50%以下の場合に
# まわりのインライン要素と同様に1つのmyblocknameにまとめる
our $EXCEPTIONAL_BLOCK_TAGS = '^br$';

sub new{
    my (undef, $opt) = @_;

    my $this = {};
    $this->{opt} = $opt;
    $this->{juman} = new Juman();

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

    if ($this->{opt}{add_class2html}) {
	$this->remove_deco_attr($body);	    
	$this->text2div($body);
    }

    # $body->deobjectify_text;
}

# 不要な属性を削除
sub remove_deco_attr {
    my ($this, $elem) = @_;
    
    foreach my $attr (qw/bgcolor style id subtree_string leaf_string/) {
	$elem->attr($attr, undef) if $elem->attr($attr);
    }

    foreach my $child_elem ($elem->content_list) {
	$this->remove_deco_attr($child_elem);
    }
}


sub detect_block {
    my ($this, $elem, $option) = @_;

    my $leaf_string1 = $elem->attr('leaf_string');
    my $leaf_string2 = $elem->attr('leaf_string');

    # さらに分割するかどうかを判定
    my $divide_flag = $this->check_divide_block($elem) if !$option->{parent};
    
    if (defined $option->{parent} ||  
	((!$elem->content_list || ($this->{alltextlen} && $elem->attr('length') / $this->{alltextlen} < $TEXTPER_TH)) && !$divide_flag)) {
	my @texts = $this->get_text($elem);
	my $myblocktype;
	# フッター
	# 条件 : 以下のすべてを満たす
	# - ブロックの開始がページ末尾から300文字以内
	# - ブロックの終了がページ末尾から100文字以内
	# - 「copyright」など特別な文字列を含む
	if ($this->check_footer($elem, \@texts)) {
	    $myblocktype = 'footer';
	}

	# リンク領域
	# - ブロック以下のaタグを含む繰り返しの割合の和が8割以上
	elsif ($elem->attr("length") != 0 && $this->check_link_block($elem) / $elem->attr("length") > $LINK_RATIO_TH) {
	    $myblocktype = 'link';
	}

	# img
	# - 葉の画像の割合が8割以上
	elsif ((($leaf_string1 =~ s/_img_//g) / ($leaf_string2 =~ s/_//g) * 2)
		> $IMG_RATIO_TH) {
	    $myblocktype = 'img';
	}

	# form
	# - ブロック以下にformタグがある
	# - フロック以下に<input type="submit">がある
	elsif ($this->check_form($elem)) {
	    $myblocktype = 'form';
	}

	# 中身なし
	elsif ($elem->attr('length') == 0) {
	    ;
	}

	# プロフィール
	# elsif ($this->check_profile($elem, \@texts)) {
	#     $elem->attr('myblocktype', 'profile');
        # }

	# 本文
	# - 以下のいずれかを満たす
	# -- 長さが200文字以内
	# -- 「の」を除く助詞のブロック以下の全形態素に占める割合が5%以上
	# -- 句点、読点のブロック以下の全形態素に占める割合が5%以上
	elsif ($this->check_maintext($elem, \@texts)) {
	    $myblocktype = 'maintext';
	}

	# それ以外の場合
	else {
	    $myblocktype = 'unknown_block';
	}

	if ($myblocktype) {
	    if (defined $option->{parent}) {
		my ($start, $end) = ($option->{start}, $option->{end});
		for my $i ($start..$end) {
		    my $tmp_elem = ($option->{parent}->content_list)[$i];
		    $tmp_elem->attr('myblocktype', $myblocktype);
		    $tmp_elem->attr('no', sprintf("%s/%s", $i - $start + 1, $end - $start + 1));

		    # HTML表示用にクラスを付与する
		    if ($this->{opt}{add_class2html}) {
			$tmp_elem->attr('class' , 'myblock_' . $myblocktype);
		    }
		}
	    }
	    else {
		$elem->attr('myblocktype', $myblocktype);
		# HTML表示用にクラスを付与する
		if ($this->{opt}{add_class2html}) {
		    $elem->attr('class' , 'myblock_' . $myblocktype);
		}
	    }
	}


    }
    else {
	my $flag;
	# 50%以上のブロックがあるかチェック
	for my $child_elem ($elem->content_list){
	    if ($this->{alltextlen} && $child_elem->attr('length') / $this->{alltextlen} >= $TEXTPER_TH) {
		$flag = 1;
		last;
	    }
	}

	# 50%以上のものがある場合は通常通り再帰
	if ($flag) {
	    for my $child_elem ($elem->content_list){
		$this->detect_block($child_elem);
	    }
	}
	# 全て50%以下の場合インラインタグがあればそれらをまとめる
	else {
	    my $block_start;
	    for (my $i = 0;$i < $elem->content_list; $i++) {
		my $child_elem = ($elem->content_list)[$i];
		# ブロック要素
		if (defined $BLOCK_TAGS{$child_elem->tag} && $child_elem->tag !~ /$EXCEPTIONAL_BLOCK_TAGS/i) {
		    # インライン要素の末尾を検出
		    if (defined $block_start) {
			# インライン要素を1つにまとめる仮ノードを作成
			my $new_elem  = $this->make_new_elem($elem, $block_start, $i-1);

			# 仮ノードを親と思い領域名を確定
			$this->detect_block($new_elem, {parent => $elem, start => $block_start, end => $i-1});
			$new_elem->delete;
			undef $block_start;
		    }
		    $this->detect_block($child_elem);
		}
		# インライン要素の先頭を検出
		else {
		    if (!defined $block_start) {
			$block_start = $i;
		    }
		}
	    }
	    # 末尾
	    if (defined $block_start) {
		my $new_elem = $this->make_new_elem($elem, $block_start, scalar $elem->content_list - 1);
		$this->detect_block($new_elem, {parent => $elem, start => $block_start, end => scalar $elem->content_list - 1});
	    }

	}
    }
}

sub make_new_elem {
    my ($this, $elem, $block_start, $block_end) = @_;
    
    # 仮ノードに必要な情報を獲得
    my $length = 0;
    my ($subtree_string, $leaf_string);
    my $start_ratio = ($elem->content_list)[$block_start]->attr('start_ratio');
    my $end_ratio = ($elem->content_list)[$block_end]->attr('end_ratio');
    foreach my $tmp_elem (($elem->content_list)[$block_start..$block_end]) {
	$length += $tmp_elem->attr('length');
	$subtree_string .= $tmp_elem->attr('subtree_string');
	$leaf_string .= $tmp_elem->attr('leaf_string');
    }
    my $new_elem = new HTML::Element('div', 'length' => $length,
				     'subtree_string' => $subtree_string, 'leaf_string' => $leaf_string,
				     'start_ratio' => $start_ratio, 'end_ratio' => $end_ratio);
    
    # cloneを作成(こうしないと$elem->content_listの一部が消失?)
    my $clone_elem = $elem->clone;
    foreach my $tmp_elem (($clone_elem->content_list)[$block_start..$block_end]) {
	$new_elem->push_content($tmp_elem);
    }
	
    return $new_elem;
}

sub check_form {
    my ($this, $elem) = @_;
    
    if ($elem->look_down('_tag', 'form')) {
	foreach my $input_elem ($elem->find('input')) {
	    return 1 if $input_elem->look_down('type', 'submit')
	}
    }

    return 0;
}

sub check_profile {
    my ($this, $elem, $texts) = @_;
    
    my $counter = 0;
    foreach my $text (@$texts) {
	$counter++ if $text =~ /$PROFILE_STRING/i;
	return 1 if $counter >= 2;
    }
    
    return 0;;
}

sub check_footer {
    my ($this, $elem, $texts) = @_;

    my $footer_flag = 0;
    if ($this->{alltextlen} * (1 - $elem->attr('ratio_start')) < $FOOTER_START_TH &&
	$this->{alltextlen} * (1 - $elem->attr('ratio_end')) < $FOOTER_END_TH) {
	foreach my $text (@$texts) {
	    if ($text =~ /$FOOTER_STRING/i) {
		$footer_flag = 1;
		last;
	    }
	}
    }

    return $footer_flag;
}


sub check_maintext {
    my ($this, $elem, $texts) = @_;

    return 1 if($elem->attr('length') > $MAINTEXT_MIN);

    my ($total_mrph_num, $particle_num, $punc_mark_num) = (0, 0, 0);
    foreach my $text (@$texts) {
	my $result = $this->{juman}->analysis($text);
	foreach my $mrph ($result->mrph) {
	    $total_mrph_num++;
	    $particle_num++ if $mrph->hinsi eq '助詞' && $mrph->midasi ne "の";
	    $punc_mark_num++ if $mrph->bunrui =~ /^(読点|句点)$/;
	}
    }

    # 助詞,句点の割合を計算し判断
    if ($particle_num / $total_mrph_num > $MAINTEXT_PARTICLE_TH || $punc_mark_num / $total_mrph_num > $MAINTEXT_POINT_TH) {
	return 1;
    }
    else {
	return 0;
    }
}

# さらに分割 : 1を返す
sub check_divide_block {
    my ($this, $elem) = @_;

    # 自分以下に特定のタグを含む
    foreach my $child_elem ($elem->content_list) {
	foreach my $tag (@MORE_DIVIDE_TAG) {
	    return 1 if defined $child_elem->find($tag);
	}
    }
    
    return 0;
}


sub check_link_block {
    my ($this, $elem) = @_;

    # 8割を超える範囲に<a>タグを含む繰り返しあり

    if ($elem->attr('iteration') =~ /_a_/) {
	return $elem->attr('length');
    }

    my $sum = 0;
    for my $child_elem ($elem->content_list){
	$sum += $this->check_link_block($child_elem);
    }

    return $sum;
}


sub attach_elem_length {
    my ($this, $elem) = @_;

    return 0 if $this->is_stop_elem($elem);

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

    return if $this->is_stop_elem($elem);

    # 属性付与
    if ($this->{alltextlen} > 0) {
	$elem->attr('ratio_start', sprintf("%.4f", $offset / $this->{alltextlen}));
	$elem->attr('ratio_end', sprintf("%.4f", ($offset + $elem->attr('length')) / $this->{alltextlen}));
    }
    
    # 累積
    my $accumulative_length = $offset;
    for my $child_elem ($elem->content_list){
	if (!$this->is_stop_elem($elem)) {
	    $this->attach_offset_ratio($child_elem, $accumulative_length);
	    $accumulative_length += $child_elem->attr('length');
	}
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
	print ' ★',  $elem->attr('myblocktype');
	print ' (',$elem->attr('no'),')' if $elem->attr('no');
	print '★';
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
    my @tags;
    for my $child_elem ($elem->content_list){
	push @substrings, $child_elem->attr('subtree_string');
	push @tags, $child_elem->tag;
    }
    
    my $child_num = scalar $elem->content_list;
    # ブロックの大きさ
  LOOP:
    for (my $i = $ITERATION_BLOCK_SIZE; $i >= 1; $i--) {

	# スタートポイント
	for (my $j = 0; $j < $child_num; $j++) {

	    my $k;
	    my $flag = 0;

	    # ブロックタグをチェック
	    for ($k = $j; $k < $j+$i; $k++){
		if (defined $BLOCK_TAGS{$tags[$k]}){
		    $flag = 1;
		}
	    }
	    # aの後ろに同じテキストが来る場合
	    if ($flag == 0) {
		for ($k = $j; $k < $j+$i; $k++){
		    if ($tags[$k] eq 'a' && 
			$k+1 < $j+$i && $tags[$k+1] eq '~text' && 
			$k+$i+1 < $child_num && $tags[$k+$i+1] eq '~text' &&
			$substrings[$k+1] eq $substrings[$k+$i+1] &&
			($elem->content_list)[$k+1]->attr('text') eq ($elem->content_list)[$k+$i+1]->attr('text')) {
			$flag = 1;
		    }
		}
	    }
	    next if($flag == 0);

	    for ($k = $j+$i; $k < $child_num; $k++) {
		last if ($substrings[$k] ne $substrings[$k - $i]);
	    }

	    # 繰り返し発見
	    if ($k - $j >= $ITERATION_TH * $i) {
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

    return if $this->is_stop_elem($elem);


    my @texts;
    # text
    if ($elem->tag eq '~text') {
	push @texts, $elem->attr('text');
    }
    # 画像の場合altを返す
    elsif ($elem->tag eq 'img') {
	push @texts, $elem->attr('alt');
    }

    for my $child_elem ($elem->content_list){
	push @texts, $this->get_text($child_elem);
    }

    return @texts;
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
	    $elem->tag("span");
	    $elem->push_content($elem->attr("text"));

	    $elem->attr("text", undef);
	}
    }
}

sub is_stop_elem {
    my ($this, $elem) = @_;

    if ($elem->tag =~ /$TAG_IGNORED/i) {
	return 1;
    }
    return 0;
}

1;
