package DetectBlocks;

# $Id$

use strict;
use utf8;
use ModifiedTreeBuilder;
use Encode;
use Dumpvalue;
use Unicode::Japanese;

use Encode;
use Encode::Guess;

use Devel::StackTrace;

our $TEXTPER_TH = 0.5;
# our $TEXTPER_TH = 700;
our $TEXTPER_TH_RATE = 0.5;
our $TEXTPER_TH_LENGTH = 3000;


our $HEADER_START_TH = 100; # これより小さければheader
our $HEADER_END_TH   = 200; # これより小さければheader
our $ALT4HEADER_TH   = 15;  # 画像のみのheaderの際に必要なalt_text

our $FOOTER_START_TH	= 300; # これより大きければfooter
our $FOOTER_END_TH	= 100; # これより大きければfooter
our $FOOTER_HEIGHT_RATE = 0.5; # ブロックの高さこれより大きければfooterでない

our $LINK_RATIO_TH = 0.66; #link領域の割合
our $IMG_RATIO_TH  = 0.80; # これより大きければimg (葉だけ数える)

our $ITERATION_BLOCK_SIZE = 8; # 繰り返しのかたまりの最大
our $ITERATION_TH	  = 2; # 繰り返し回数がこれ以上
our $ITERATION_DIV_CHAR	  = '\||｜|│|\>|＞|\<|＜|\/|\-|ー|—|−|\s|\p{InCJKSymbolsAndPunctuation}|\p{S}|(?:\]\s*\[)'; # a-textの繰り返しのtextとなりうる文字列

our $A_TEXT_ITERATION_MIN = 3;   # a-textで必ず繰り返しとして検出する最低数
our $A_TEXT_RATE	  = 0.5; # a-text部分のblock割合がこれ以下ならiterationにしない

# カラム構成の検出
our $COLUMN_HEIGHT_MIN		= 0.7;
our $CHILD_COLUMN_WIDTH_MAX	= 0.7;
our $CHILD_COLUMN_WIDTH_change	= 0.95;
our $CHILD_COLUMN_HEIGHT_change = 0.96;

# headerとfooterが先頭・末尾から許す割合
our $HEADER_FOOTER_RATE = 0.4;
    
# 柔軟なtableの繰り返しの検出
our $TR_SUBSTRING_RATIO	       = 0.5; # 繰り返しとして認識されるための同じsubstringの割合(tr要素以下)
our $TABLE_TR_MIN	       = 3; # これ以下のtrしか持たないtableは対象外
our $TABLE_TD_MIN	       = 2; # これ以下のtdしか持たないtableは対象外
our $ITERATION_TABLE_RATIO_MIN = 0.30; # これ以下の長さしかないtableは対象外
our $ITERATION_TABLE_RATIO_MAX = 0.95; # これ以上の長さのtableは対象外

our $MAINTEXT_MIN = 200;

# FOOTER用の文字列
our $FOOTER_STRING    = '住所|所在地|郵便番号|電話番号|著作権|問[い]?合[わ]?せ|利用案内|tel|.+[都道府県].+[市区町村]|(06|03)\-?\d{4}\-?\d{4}|\d{3}\-?\d{3}\-?\d{4}|mail|copy\s*right|\(c\)|（(c|Ｃ)）|著作権|(all|some)\s*rights\s*reserved|免責事項|プライバシー.?ポリシー|home|ホーム(?:ページ|[^\p{Kana}]|$)';
our $FOOTER_STRING_EX = '(some|all)\s?rights\s?reserved|copyright\s.*(?:\(c\)|\d{4})'; # Copyright

# maintext用の文字列
our $MAINTEXT_PARTICLE_TH = 0.05; # 助詞の全形態素に占める割合がこれ以上なら本文
our $MAINTEXT_POINT_TH	  = 0.05; # 句点の全形態素に占める割合がこれ以上なら本文

# 以下のブロックはmore_blockを探さない
our %NO_MORE_TAG = (
    header => 1,
    img	   => 1,
    form   => 1
    );

# more_blockとして検出するもの(優先度順に記述)
our @MORE_BLOCK_NAMES = qw/profile address/;

# more_blockに必要な文字列の数
our $MORE_BLOCK_NUM_TH = 2;
# more_blockに必要な文字列を含むブロックの割合
our $MORE_BLOCK_RATIO_TH = 0.4;
# more_blockの領域サイズの最大値
our $MORE_BLOCK_LENGTH_MAX_TH = 500;

# プロフィール領域用の文字列
our $PROFILE_STRING = '通称|管理人|氏名|名前|author|ニックネーム|ユーザ[名]?|user\-?(?:id|name)|誕生日|性別|出身|年齢|アバター|プロフィール|profile|自己紹介';
# 住所領域用の文字列 ★誤りが多いので停止中 : (\p{Han}){2,3}[都道府県]|(\p{Han}){1,5}[市町村区]  -> 例 : 室町時代
our $MAIL_ADDRESS = '[^0-9][a-zA-Z0-9_]+(?:[.][a-zA-Z0-9_]+)*[@][a-zA-Z0-9_]+(?:[.][a-zA-Z0-9_]+)*[.][a-zA-Z]{2,4}';
our $ADDRESS_STRING = '(?:郵便番号|〒)\d{3}(?:-|ー)\d{4}|住所|連絡先|電話番号|(?:e?-?mail|ｅ?−?(?:ｍａｉｌ|メール))|(?:tel|ｔｅｌ)|フリーダイ(?:ヤ|ア)ル|(?:fax|ｆａｘ)|(?:$MAIL_ADDRESS)';

# jumanを使わない場合の助詞、句点、判定詞
our $josi_string_ja = '[。、がをにへとやだで]';
our $josi_string_en = '[,.]'; # 便宜的にjosiにしとく
our $josi_string; # newした時に代入

# 以下のtagは解析対象にしない
our %TAG_IGNORED = (
    script => 1,
    style  => 1,
    br	   => 1,
    option => 1
    );

# 以下のtagを子供以下にふくむ場合は領域を分割
our @MORE_DIVIDE_TAG = qw/address form/;

#ブロックタグのハッシュ
our %BLOCK_TAGS		      =	 (
                   address    => 1,
                   blockquote => 1,
                   caption    => 1,
                   center     => 1,
                   dd	      => 1,
                   dir	      => 1,
                   div	      => 1,
                   dl	      => 1,
                   dt	      => 1,
                   fieldset   => 1,
                   form	      => 1,
                   h1	      => 1,
                   h2	      => 1,
                   h3	      => 1,
                   h4	      => 1,
                   h5	      => 1,
                   h6	      => 1,
                   hr	      => 1,
                   isindex    => 1,
                   li	      => 1,
                   listing    => 1,
                   menu	      => 1,
                   multicol   => 1,
                   noframes   => 1,
                   noscript   => 1,
                   ol	      => 1,
                   option     => 1,
                   p	      => 1,
                   plaintext  => 1,
                   pre	      => 1,
                   select     => 1,
                   table      => 1,
                   tbody      => 1,
                   td	      => 1,
                   tfoot      => 1,
                   th	      => 1,
                   thead      => 1,
                   tr	      => 1,
                   ul	      => 1,
                   xmp	      => 1,
		   br	      => 1,
		   map	      => 1,
		   area	      => 1
		       );

our %TAG_with_ALT = (area => 1, img => 1);


# あるブロック以下の全てのブロックのテキスト量が50%以下の場合に
# まわりのインライン要素と同様に1つのmyblocknameにまとめる
our %EXCEPTIONAL_BLOCK_TAGS  = (br => 1, li => 1);

# HTMLにする際に捨てる属性
our @DECO_ATTRS = qw/bgcolor style id subtree_string leaf_string mywidth_rate myheight_rate mytop_rate myleft_rate mybackgroundcolor/;

our $counter_JUMAN;
our $JUMAN_TH = 30;

sub new {
    my (undef, $opt) = @_;

    my $this = {};
    $this->{opt} = $opt;
    
    if ($this->{opt}{en}) {
	$this->{opt}{without_juman} = 1;
    }

    if (!$this->{opt}{without_juman}) {
	require Juman;
	if ($this->{opt}{juman}) {
	    # 京大の環境
	    if ($this->{opt}{juman} eq 'kyoto_u') {
		my $machine =`uname -m`; # 32/64bit判定
		$this->{JUMAN_COMMAND} = $machine =~ /x86_64/ ? '/share/usr-x86_64/bin/juman' : '/share/usr/bin/juman';
	    }
	    # jumanのpathを指定した場合
	    else {
		$this->{JUMAN_COMMAND} = $this->{opt}{juman};
	    }
	    $this->{JUMAN_RCFILE} = $this->{opt}{jumanrc} if $this->{opt}{jumanrc};
	    if (! -e $this->{JUMAN_COMMAND}) {
		print STDERR "Can't find JUMAN_COMMAND ($this->{JUMAN_COMMAND})!\n";
		exit;
	    }
	}
	$JUMAN_TH = $opt->{JUMAN_TH} if $opt->{JUMAN_TH};
	&ResetJUMAN($this, {first => 1});
    }

    $josi_string = $this->{opt}{en} ? $josi_string_en : $josi_string_ja;

    bless $this;
}

sub maketree{
    my ($this, $htmltext, $url) = @_;

    # copyright置換
    $htmltext =~ s/\&copy\;?/\(c\)/g;
    $htmltext =~ s/\&nbsp\;?/ /g;
    if (!$this->{opt}{print_offset}) {
	$htmltext =~ s/©/\(c\)/g ;
    }
    $this->{tree} = $this->{opt}{modify} ? ModifiedTreeBuilder->new : HTML::TreeBuilder->new;

    #$this->{tree} = HTML::TreeBuilder->new;

    $this->{tree}->no_expand_entities(1);
    # $this->{tree}->attr_encoded(1);

    $this->{tree}->p_strict(1); # タグの閉じ忘れを補完する
    $this->{tree}->parse($htmltext);
    $this->{tree}->eof;

    #url処理
    if (defined $url) {
	$this->{url} = $url;
	if($this->{url} =~ /^http\:\/\/([^\/]+)/) {
	    # 例 : http://www.yahoo.co.jp/news => www.yahoo.co.jp
	    $this->{domain} = $1;
	}
	$this->{url_layers_ref} = &url2layers($this->{url}); # urlを'/'で区切る
    }

    if (!$this->{tree}->find("base") && defined($url)){
        my $new_elem = new HTML::Element('base', 'href' => $url."/");
        $this->{tree}->find("head")->unshift_content($new_elem);
    }
}

sub detectblocks{
    my ($this) = @_;

    my $body = $this->{tree}->find('body');

    # テキストをタグ化
    $body->objectify_text;

    # 自分以下のテキストの長さを記述
    $this->attach_elem_length($body);
    $this->{alltextlen} = $body->attr('length');

    if ($this->{opt}{pos_info}) {
	# bodyをrootにすると大きすぎる
	my $root_elem = $this->find_root_elem($body);

	# 自分以下で最大のwidth, heightを探す
	$this->detect_max_shape($body);

	# rootが幅1とかの場合があるのでｓの対処★ 暫定
	if (!$root_elem->{'myheight'} || !$root_elem->{'mywidth'}) {
	    $root_elem = $body;
	}
	if ($root_elem->{'myheight'} < $root_elem->{'myheight_max'}) {
	    $root_elem = $body;
	    $root_elem->{'myheight'} = $root_elem->{'myheight_max'};
	}
	if ($root_elem->{'mywidth'} < $root_elem->{'mywidth_max'}) {
	    $root_elem = $body;
	    $root_elem->{'mywidth'} = $root_elem->{'mywidth_max'};
	}
	
	# ブロックの位置情報を取得(root以下)
	$this->{root_height} = $root_elem->attr('myheight');
	$this->{root_width}  = $root_elem->attr('mywidth');
	$this->{root_top}    = $root_elem->attr('mytop');
	$this->{root_left}   = $root_elem->attr('myleft');
	$this->attach_pos_info($root_elem);

	# カラム構成を取得
	$this->get_column_structure($root_elem, undef);
    }

    # テキストの累積率を記述
    $this->attach_offset_ratio($body);
    # 自分以下のタグ木を記述
    $this->get_subtree_string($body);
    # 自分以下の葉タグを記述
    $this->get_leaf_string($body);

    # タグの繰り返し構造を見つける
    $this->detect_iteration($body);

    $this->detect_block($body);

    $this->post_process($body) if $this->{opt}{add_class2html} && !$this->{opt}{blogcheck};
}

sub detect_max_shape {
    my ($this, $elem) = @_;

    my ($max_width, $max_height) = ($elem->attr('mywidth'), $elem->attr('myheight'));
    my ($max_width_elem, $max_height_elem) = ($elem, $elem); # 不要??

    my @content_list = $elem->content_list;
    if (!scalar @content_list) {
	;
    }
    else {
	foreach my $child_elem (@content_list) {
	    my ($child_max_width, $child_max_height) = $this->detect_max_shape($child_elem);
	    if ($max_width < $child_max_width) {
		$max_width	= $child_max_width ;
		$max_width_elem = $child_elem;
	    }
	    if ($max_height < $child_max_height) {
		$max_height	 = $child_max_height;
		$max_height_elem = $child_elem;
	    }
	}
    }

    # 属性付与
    $elem->attr('mywidth_max', $max_width);
    $elem->attr('myheight_max', $max_height);
    $elem->attr('_mywidth_max_elem', $max_width_elem);
    $elem->attr('_myheight_max_elem', $max_height_elem);
    
    return ($max_width, $max_height);
}


sub find_root_elem {
    my ($this, $elem) = @_;

    my @content_list = $elem->content_list;
    return $elem if !$this->{alltextlen};
    
    my ($max_rate, $index) = (0, undef);
    for (my $i = 0; $i < @content_list; $i++) {
	my $tmp_rate = $content_list[$i]->attr('length') / $this->{alltextlen};
	if ($tmp_rate > $max_rate) {
	    $max_rate = $tmp_rate;
	    $index = $i;
	}
    }

    if ($max_rate > 0.99 && defined $index) {
	return $this->find_root_elem($content_list[$index]);	
    }
    else {
	return $elem;
    }
}

sub get_column_structure {
    my ($this, $elem, $parent_elem) = @_;

    my $flag = 0;
    foreach my $child_elem ($elem->content_list) {
	if ($this->is_column($child_elem, $elem)) {
	    $this->get_column_structure($child_elem, $elem);
	    $flag = 1;
	}
    }

    if (!$flag && !defined $elem->attr('col_num')) {
	$elem->attr('col_num', ++$this->{allcolumnnum});
    }
}

sub is_column {
    my ($this, $child_elem, $elem) = @_;

    if ($child_elem->attr('myheight_rate') > $COLUMN_HEIGHT_MIN && $child_elem->attr('length')) {

	if (
	    # width以下で分割してもwidthがほとんど変わらない場合は分割しない.
	    $child_elem->attr('mywidth_rate') < $CHILD_COLUMN_WIDTH_MAX &&
	    $child_elem->attr('mywidth_rate') / $elem->attr('mywidth_rate') > $CHILD_COLUMN_WIDTH_change &&
	    $child_elem->attr('myheight_rate') / $elem->attr('myheight_rate') < $CHILD_COLUMN_HEIGHT_change
	    ) {
	    return  0;
	}
	else {
	    return 1;
	}
    }
    return 0;
}


sub post_process {
    my ($this, $body) = @_;

    $body = $this->{tree}->find('body') if !defined $body;

    # HTMLからいらないattrを削除
    $this->remove_deco_attr($body);	    
    # ~textタグをspanタグに変換
    $this->text2span($body);
}


# 不要な属性を削除
sub remove_deco_attr {
    my ($this, $elem) = @_;
    
    foreach my $attr (@DECO_ATTRS) {
	$elem->attr($attr, undef) if $elem->attr($attr);
    }

    foreach my $child_elem ($elem->content_list) {
	$this->remove_deco_attr($child_elem);
    }
}

sub get_ok_flag {
    my ($this, $elem) = @_;
    my $flag;

    return 0 if $this->{alltextlen} == 0;

    my $TH  =  $this->{alltextlen} > $TEXTPER_TH_LENGTH / $TEXTPER_TH_RATE ? $TEXTPER_TH_LENGTH :
	$TEXTPER_TH_RATE * $this->{alltextlen};
    return 1 if $elem->attr('length') < $TH;

    return 0;
}

sub detect_block {
    my ($this, $elem, $option) = @_;

    my $leaf_string1 = $elem->attr('leaf_string');
    my $leaf_string2 = $elem->attr('leaf_string');

    my @texts = $this->get_text($elem);

    # # さらに分割するかどうかを判定 (する:1, しない:0)
    my $divide_flag = $this->check_divide_block($elem, \@texts) if !$option->{parent};
    my @content_list = $elem->content_list;
    my $elem_length = $elem->attr('length');

    if (defined $option->{parent} ||
    	((!@content_list || $this->get_ok_flag($elem)) && !$divide_flag) ||
	$elem->attr('iteration') =~ /\*/) {
    	my $myblocktype;
	
    	# フッター
    	# 条件 : 以下のすべてを満たす
    	# - ブロックの開始がページ末尾から300文字以内
    	# - ブロックの終了がページ末尾から100文字以内
    	# - 「copyright」など特別な文字列を含む
    	if (!$this->{opt}->{disable_footer} && $this->check_footer($elem, \@texts)) {
    	    $myblocktype = 'footer';
    	}

    	# ヘッダー
    	# 条件 : 以下のすべてを満たす
    	# - ブロックの開始がページ先頭から100文字以内
    	# - ブロックの終了がページ先頭から200文字以内
    	# - index.*へのリンクを持つ
    	elsif (!$this->{opt}->{disable_header} && $this->check_header($elem)) {
    	    $myblocktype = 'header';
    	}

    	# リンク領域
    	# - ブロック以下のaタグを含む繰り返しの割合の和が8割以上
    	elsif ($elem_length != 0 && $this->check_link_block($elem) / $elem_length > $LINK_RATIO_TH) {
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
    	elsif ($elem_length == 0) {
    	    ;
    	}

        # 本文 ★ CheckUnknownBlockの段階でJUMANがかかっているので非効率(要修正)
    	# - 以下のいずれかを満たす
    	# -- 長さが200文字以内
    	# -- 「の」を除く助詞のブロック以下の全形態素に占める割合が5%以上
    	# -- 句点、読点のブロック以下の全形態素に占める割合が5%以上
    	elsif ($this->check_maintext($elem, \@texts)) {
    	    $myblocktype = 'maintext';
    	}

	
	#---------------- 例外的な条件 ----------------#
    	# リンク領域(カレンダー)
    	# ^(月|火|水|木|金|土|日)$ を7回含む
    	elsif ($this->check_calender($elem, \@texts)) {
    	    $myblocktype = 'link';
    	}

	# 本文
	# 表っぽいと判断されたtableはunknownにしない
	elsif ($elem->attr('iteration') =~ /\*$/) {
	    $myblocktype = 'maintext';
	}
	#---------------- 例外的な条件 ----------------#


    	# それ以外の場合
    	else {
    	    $myblocktype = 'unknown_block';
    	}

    	if ($myblocktype) {
    	    if (defined $option->{parent}) {
    		my ($start, $end) = ($option->{start}, $option->{end});
    		for my $i ($start..$end) {
    		    my $tmp_elem = ($option->{parent}->content_list)[$i];
    		    $this->attach_attr_blocktype($tmp_elem, $myblocktype, 'myblocktype', {pos => $i - $start + 1, total => $end - $start + 1});
    		}
    	    }
    	    else {
    		$this->attach_attr_blocktype($elem, $myblocktype, 'myblocktype')
    	    }

    	    # 確定した領域の下からもっと細かい領域を探す
    	    if ($this->{opt}{get_more_block} && !$NO_MORE_TAG{lc($myblocktype)}) {
    		# そのための情報を得る
    		$this->detect_string($elem);

    		$this->detect_more_blocks($elem, \@texts) ;
    	    }
    	}
    }
    else {
    	my $block_start;

    	my $array_size = scalar @content_list;
    	for (my $i = 0;$i < $array_size; $i++) {
    	    my $child_elem = $content_list[$i];
    	    my $ctag = $child_elem->tag;
    	    # textが50%以上のblock or block要素
    	    if (($this->{alltextlen} && !$this->get_ok_flag($child_elem)) ||
    		(defined $BLOCK_TAGS{lc($ctag)} && !$EXCEPTIONAL_BLOCK_TAGS{lc($ctag)})) {
    		# インライン要素の末尾を検出
    		if (defined $block_start) {
    		    $this->detect_block_region($elem, $block_start, $i-1);
    		    undef $block_start;
    		}
    		$this->detect_block($child_elem);
    	    }
    	    # インライン要素の先頭を検出
    	    elsif (!defined $block_start) {
    		$block_start = $i;
    	    }
    	}
    	# 末尾
    	if (defined $block_start) {
    	    $this->detect_block_region($elem, $block_start, $array_size - 1);
    	}
    }
}

sub detect_more_blocks {
    my ($this, $elem) = @_;

    # このブロック以下をチェックする意味があるか
    return if !$this->check_under_this_block($elem);

    my $myblocktype_more;
    my $elem_length = $elem->attr('length');
    my @content_list = $elem->content_list;

    # myblocktypeで決定した領域をさらに分割「できる」かどうか
    # 分割できる
    if ($this->check_multiple_block($elem)) {
	# 子供が1ブロックしかない場合無条件で再帰
	if (scalar grep($BLOCK_TAGS{$_->tag} && !$EXCEPTIONAL_BLOCK_TAGS{lc($_->tag)}, @content_list) == 1) {
	    $this->detect_more_blocks($content_list[0]);
	}
	else {
	    my $divide_flag = 1;
	    foreach my $more_block_name (@MORE_BLOCK_NAMES)  {
		my $block_ref = $elem->{'_'.$more_block_name};

		# 条件 : 必要な文字列をx個以上含む && 比が0.x以上 && ブロックの長さがxxx以下
		if ($block_ref->{num} >= $MORE_BLOCK_NUM_TH && $block_ref->{ratio} > $MORE_BLOCK_RATIO_TH &&
		    $elem_length < $MORE_BLOCK_LENGTH_MAX_TH) {
		    # 属性付与
		    $divide_flag = 0;
		    $this->attach_attr_blocktype($elem, $more_block_name, 'myblocktype_more');
		    # last;
		}
	    }

	    # 再帰
	    if ($divide_flag) {
		foreach my $child_elem (@content_list) {
		    $this->detect_more_blocks($child_elem);
		}
	    }
	}
    }

    # 分割できない
    else {
	foreach my $more_block_name (@MORE_BLOCK_NAMES) {
	    my $block_ref = $elem->{$more_block_name};

	    # 属性付与
	    if ($block_ref->{num} >= $MORE_BLOCK_NUM_TH) {
		$this->attach_attr_blocktype($elem, $more_block_name, 'myblocktype_more');
		return;
	    }
	}
    }
}

sub check_under_this_block {
    my ($this, $elem) = @_;

    foreach my $more_block_name (@MORE_BLOCK_NAMES) {
	return 1 if $elem->{'_'.$more_block_name}{num} >= $MORE_BLOCK_NUM_TH;
    }

    return 0;
}

sub detect_string {
    my ($this, $elem) = @_;
    
    my $ref;
    if ($elem->tag eq '~text') {
	# 各々のブロックに必要なstringが含まれてるか
	$ref = $this->check_more_block_string($elem);
    }
    else {
	foreach my $child_elem ($elem->content_list){
	    # 子供以下に必要なstringが含まれているか
	    my $child_ref = $this->detect_string($child_elem);

	    foreach my $more_block_name (@MORE_BLOCK_NAMES) {
		if ($child_ref->{$more_block_name}{num}) {
		    $ref->{$more_block_name}{num} += $child_ref->{$more_block_name}{num};
		    $ref->{$more_block_name}{length} += $child_elem->attr('length');
		}
	    }
	}
    }

    # ratio
    if ($elem->attr('length')) {
	foreach my $more_block_name (@MORE_BLOCK_NAMES) {
	    $ref->{$more_block_name}{ratio} = $ref->{$more_block_name}{length} / $elem->attr('length');
	}
    }
    
    # 属性付与(hash)
    # 自分以下で例えばプロフィール領域に必要な文字の数, 必要な文字を含むブロックの長さとその比, を付与
    foreach my $more_block_name (@MORE_BLOCK_NAMES) {
 	$elem->attr('_'.$more_block_name, $ref->{$more_block_name});
    }
    
    return $ref;
}

sub check_more_block_string {
    my ($this, $elem) = @_;

    my $text = $this->{opt}{print_offset} ? decode('utf8', $elem->attr('text')) : $elem->attr('text');

    my ($profile, $address);
    # profile
    if (my @matches = ($text =~ /($PROFILE_STRING)/go)) {
	$profile->{length} += $elem->attr('length');
	$profile->{num} += scalar @matches;
    }

    # address
    if (my @matches = ($text =~ /($ADDRESS_STRING)/go)) {
    	$address->{length} += $elem->attr('length');
    	$address->{num} += scalar @matches;
    }

    return ({profile => $profile, address => $address});
}


# 自分以下を分割しようがあるか
# (子供数が1ブロックでも孫のブロック数が2以上あるかもしれない -> 分割される可能性がある)
sub check_multiple_block {
    my ($this, $elem) = @_;
	
    my @content_list = $elem->content_list;
    
    if (ref($elem) eq 'HTML::Element' && scalar @content_list) {
	if (@content_list == 1) {
	    return $this->check_multiple_block($content_list[0]);
	}
	else {
	    return 1;
	}
    }
    
    return 0;
}


# start ~ endまでを1つのブロックとして領域名を確定
sub detect_block_region {
    my ($this, $elem, $start, $end) = @_;

    # インライン要素を1つにまとめる仮ノードを作成
    my $new_elem  = $this->make_new_elem($elem, $start, $end);

    # 仮ノードを親と思い領域名を確定
    $this->detect_block($new_elem, {parent => $elem, start => $start, end => $end});

    $new_elem->delete;
}
sub make_new_elem {
    my ($this, $elem, $start, $end) = @_;
    
    # 仮ノードに必要な情報を獲得
    my $length		       = 0;
    my ($subtree_string, $leaf_string);
    my $ratio_start	       = $this->get_new_node_ratio($elem, $start, $end);
    my $ratio_end	       = $this->get_new_node_ratio($elem, $end, $start);
    my ($iteration, $div_char) = $this->get_new_node_iteration($elem, $start, $end);
    my ($mytop, $myleft, $mywidth, $myheight);
    if ($this->{opt}{pos_info}) {
	($mytop, $myleft)     = ($elem->attr('mytop'), $elem->attr('myleft'));
	($myheight, $mywidth) = ($elem->attr('myheight'), $elem->attr('mywidth'));
    }

    foreach my $tmp (($elem->content_list)[$start..$end]) {
	$length += $tmp->attr('length');
	$subtree_string .= $tmp->attr('subtree_string');
	$leaf_string .= $tmp->attr('leaf_string');
    }
    my $new_elem = new HTML::Element(
	'div',
	'length'	 => $length,
	'subtree_string' => $subtree_string,
	'leaf_string'	 => $leaf_string,
	'ratio_start'	 => $ratio_start,
	'ratio_end'	 => $ratio_end,
	'iteration'	 => $iteration,
	'div_char'	 => $div_char,
	'mytop'          => $mytop,
	);
    
    # cloneを作成(こうしないと$elem->content_listのpush_contentした部分が消失)
    my $clone_elem = $elem->clone;
    foreach my $tmp (($clone_elem->content_list)[$start..$end]) {
	$new_elem->push_content($tmp);
    }
    $clone_elem->delete;
	
    return $new_elem;
}
sub get_new_node_ratio {
    my ($this, $elem, $start, $end) = @_;
    
    my $search_str = $start < $end ? 'start' : 'end';
    my $ratio;
    my $i =  $start;
    # brなどはratioの情報がない
    do {
	next if ref(($elem->content_list)[$i]) ne 'HTML::Element';
	$ratio = ($elem->content_list)[$i]->attr('ratio_'.$search_str);
	return $ratio if $ratio;
	$start < $end ? $i++ : $i--;
    } while ($i != $end);
}
sub get_new_node_iteration {
    my ($this, $elem, $start, $end) = @_;

    my (%new_node_iteration, %new_node_div_char);
    foreach my $child_elem (($elem->content_list)[$start..$end]) {
	if ($child_elem->attr('iteration_number')) {
	    foreach my $iteration (split(',', $child_elem->attr('iteration_number'))) {
		my ($iteration_type, $buf) = split('%', $iteration);
		my ($num, $total) = split('/', $buf);
		# ★ 本当は繰り返しの場所を検出しておき、新ノードに属する繰り返しかをチェックすべき
		#    例 : div a font a font div a font a font
		#             =============
		#               新ノード -> a font の繰り返しは必要
		#                        -> div a font a font の繰り返しは不要
		# ★ 暫定的にiterationの大きさ(この例は2or5)と仮ノードの大きさ(この例は4)を比較 -> うまくいかない例ってある??
		$new_node_iteration{$iteration} = 1 if $iteration_type && $end - $start + 1 >= split(':', $iteration_type);
	    }
	}
	if ($child_elem->attr('div_char')) {
	    foreach my $div_char (split('%', $child_elem->attr('div_char'))) {
		$new_node_div_char{$div_char} = 1 if $div_char;
	    }
	}
    }

    # print join(',', keys %new_node_iteration),"\n";
    # print join('%', keys %new_node_div_char),"\n";
    return join(',', keys %new_node_iteration), join('%', keys %new_node_div_char);
}

sub attach_attr_blocktype {
    my ($this, $elem, $myblocktype, $attrname, $num) = @_;

    $elem->attr('no', sprintf("%s/%s", $num->{pos}, $num->{total})) if defined $num;	

    # 属性名($attrname) : myblocktype or myblocktype_more
    $elem->attr($attrname, $myblocktype);

    # HTML表示用にクラスを付与する
    if ($this->{opt}{add_class2html}) {
	my $classname = $elem->attr('class') ? $elem->attr('class').' myblock_'.$myblocktype : 'myblock_'.$myblocktype;
	$elem->attr('class' , $classname);
    }

    my @content_list = $elem->content_list;
    # 全てのタグにblock名を付与(★仮)
    if ($this->{opt}{add_blockname2alltag} && scalar  @content_list > 0) {
	foreach my $child_elem (@content_list) {
	    $this->attach_attr_blocktype($child_elem, $myblocktype, $attrname, $num);
	}
    }
}

sub check_form {
    my ($this, $elem) = @_;
    
    if ($elem->look_down('_tag', 'form')) {
	foreach my $input_elem ($elem->find('input')) {
	    return 1 if $input_elem->look_down('type', qr/(?:submit|button|image)/) || $input_elem->look_down('name', 'submit')
	}
    }

    return 0;
}

sub check_header {
    my ($this, $elem) = @_;

    if ($this->{opt}{pos_info} && $elem->{pos_valid_flag}) {
    	return 0 if
    	    $elem->look_down(sub {defined($_[0]->attr('col_num')) }) ||
    	    $elem->attr('mytop_rate') + $elem->attr('myheight_rate') > $HEADER_FOOTER_RATE;
    }

    my $domain = $this->{domain} ? $this->{domain} : '\/\/\/';
    my $link2index = $elem->look_down('_tag' => 'a', 'href' => qr/(?:$domain\/|(?:\.\.\/)+|^\/|^)(?:index\.(?:html|htm|php|cgi))?$/) ? 1 :0;

    if ($this->{alltextlen} * $elem->attr('ratio_start') < $HEADER_START_TH && $this->{alltextlen} * $elem->attr('ratio_end') < $HEADER_END_TH) {
	# index.*へのリンクが存在する
	if ($link2index) {
	    return 1;
	}
	# ある程度のまともなalt_textの画像が存在する
	else {
	    my @img_elems = $elem->find('img');
	    if (@img_elems > 0) {
		foreach my $img_elem (grep($_->attr('length') >= $ALT4HEADER_TH, @img_elems)) {
		    if ($this->{opt}{without_juman}) {
			my $alt_text = $img_elem->attr('alt');
			return 1 if $alt_text =~ /$josi_string$/o;
		    }
		    else {
			# 末尾の形態素条件
			# $this->ResetJUMAN;
			my $last_mrph = ($this->{juman}->analysis(&han2zen($img_elem->attr('alt')))->mrph)[-1];
			return 1 if
			    ref($last_mrph) eq  'Juman::Morpheme' &&
			    $last_mrph->bunrui !~ /^(句点|読点)$/ && $last_mrph->hinsi !~ /^(助詞|助動詞|判定詞)$/;
		    }
		}
	    }
	}
    }

    return 0;
}

sub check_footer {
    my ($this, $elem, $texts) = @_;

    my $ng_flag = 0;
    if ($this->{opt}{pos_info} && $elem->{pos_valid_flag}) {
	$ng_flag = 1 if
    	    $elem->look_down(sub {defined($_[0]->attr('col_num'))}) ||
    	    $elem->attr('mytop_rate') < $HEADER_FOOTER_RATE;
    }

    my $footer_flag = 0;
    if (!$ng_flag && $this->{alltextlen} * (1 - $elem->attr('ratio_start')) < $FOOTER_START_TH &&
	$this->{alltextlen} * (1 - $elem->attr('ratio_end')) < $FOOTER_END_TH) {
	foreach my $text (@$texts) {
	    if ($text =~ /$FOOTER_STRING/io){
		$footer_flag = 1;
		last;
	    }
	}
    }
    # all right researved は無条件でOK
    else {
	foreach my $text (@$texts) {
	    if ($text =~ /$FOOTER_STRING_EX/io) {
		$footer_flag = 1;
		last;
	    }
	}
    }

    return $footer_flag;
}

# JUMAN_THはnew時のoptionで変更可能
sub ResetJUMAN {
    my ($this, $option) = @_;
    
    $counter_JUMAN++;
    if (($counter_JUMAN > $JUMAN_TH || $option->{first}) && !$this->{opt}{without_juman}) {
	# $this->{opt}{juman}を指定した場合
	if ($this->{JUMAN_COMMAND} || $this->{JUMAN_RCFILE}) {
	    my %JUMAN_ARGS;
	    $JUMAN_ARGS{'-Command'} = $this->{JUMAN_COMMAND} if $this->{JUMAN_COMMAND};
	    $JUMAN_ARGS{'-Rcfile'} = $this->{JUMAN_RCFILE} if $this->{JUMAN_RCFILE};
	    $this->{juman} = new Juman(\%JUMAN_ARGS);
	}
	# $this->{opt}{juman}が空ならばデフォルトのjumanを使う
	else {
	    $this->{juman} = new Juman;
	}
    	$counter_JUMAN = 0;
    }
}

sub check_maintext {
    my ($this, $elem, $texts) = @_;

    return 1 if($elem->attr('length') > $MAINTEXT_MIN);

    my ($total_mrph_num, $particle_num, $punc_mark_num) = (0, 0, 0);
    # $this->ResetJUMAN;
    foreach my $text (@$texts) {
	$text = Unicode::Japanese->new($text)->h2z->getu() if !$this->{opt}{en};
	$text =~ s/。/。%%%/g;
	foreach my $text_splitted (split('%%%', $text)) {
	    if ($this->{opt}{without_juman}) {
		my @buf = $text_splitted =~ /$josi_string/go;
		$particle_num   += scalar @buf;
		$total_mrph_num += length($text_splitted);
	    }
	    else {
		# $this->ResetJUMAN;
		my $result = $this->{juman}->analysis(&han2zen($text_splitted));
		foreach my $mrph ($result->mrph) {
		    $total_mrph_num++;
		    $particle_num++ if $mrph->hinsi eq '助詞' && $mrph->midasi ne "の";
		    my $bunrui = $mrph->bunrui;
		    $punc_mark_num++ if $bunrui eq '読点' || $bunrui eq '句点';
		}
	    }
	}
    }

    # 助詞,句点の割合を計算し判断
    if ($total_mrph_num &&
	($particle_num / $total_mrph_num > $MAINTEXT_PARTICLE_TH || $punc_mark_num / $total_mrph_num > $MAINTEXT_POINT_TH)) {
	return 1;
    }
    else {
	return 0;
    }
}

# 位置情報を利用して変な形の領域かどうかを調べる
# 0 : 普通の形, 1 : 変な形
sub check_shape {
    my ($this, $elem) = @_;
    
    # このブロックの形が変(★2は暫定)
    return 1 if $elem->attr('myheight_max') > 2 * $elem->attr('myheight') || $elem->attr('mywidth_max') > 2 * $elem->attr('mywidth');
    
    return 0;
}

sub check_divide_block {
    my ($this, $elem, $texts) = @_;

    # 下階層を調べる意味があるかをチェック(ある:1, ない:0)
    return 0 if !$this->check_multiple_block($elem);

    # 変な形のblock
    return 1 if $this->{opt}{pos_info} && $elem->{pos_valid_flag} && $this->check_shape($elem);
    
    # チェック
    foreach my $child_elem ($elem->content_list) {
    	## address
    	if (defined $child_elem->find('address')) {
    	    return 1 ;
    	}

    	## form (以下のような場合は分割しない)
    	#------------------------------------#
    	# <table>                            #
    	# <tr><td><form> </form></td></tr>   #
    	# <tr><td><input> </input></td></tr> #
    	# </table>                           #
    	#------------------------------------#
    	unless ($elem->tag eq 'table' && !$child_elem->find('table')) {
    	    return 1 if defined $child_elem->find('form');
    	}

    	## copyright
    	# 分割するとfooter領域が出現する
    	# (address不要かも)
    	if ($this->check_divide_block_by_copyright($elem, $texts)) {
    	    return 1;
    	}
    }

    return 0;
}

sub check_divide_block_by_copyright {
    my ($this, $elem, $texts) = @_;

    return 0 if ref($elem) ne 'HTML::Element';

    my @content_list = $elem->content_list;

    # content_listサイズが1ならさらに潜る
    if (@content_list == 1) {
    	return $this->check_divide_block_by_copyright($content_list[0], $texts);
    }
    else {
	foreach my $child_elem (@content_list) {
	    next if $child_elem ne 'HTML::Element';
	    my @child_texts = $this->get_text($child_elem);
	    return 1 if !$this->check_footer($elem, $texts) && $this->check_footer($child_elem, \@child_texts);
	}
    }

    return 0;
}

sub ignore_a_text {
    my ($this, $iteration_string) = @_;
    
    my ($a_text_text_flag, $a_text_flag) = (0, 0);
    # a-textがあるかをチェック
    # _a_+_~text_-:_~text_:_br_%0/41, 
    $iteration_string =~ s/\%\d+\/\d+//g;
    my @iteration_strings = split(/,/, $iteration_string);
  LOOP:
    for (my $i = 0; $i < @iteration_strings; $i++) {
	my $tag_string = $iteration_strings[$i];
	
	# aタグを含まない繰り返しは無視
	if ($tag_string !~ /_a_/) {
	    undef $iteration_strings[$i];
	    next;
	}

	# print "\n",'pre ',$tag_string,"\n";
	my @tags = split(/:/, $tag_string);
	for (my $i = 0; $i < @tags; $i++) {
	    my $i_next = $i == $#tags ? 0 : $i+1;
	    my $checked_string = $tags[$i].':'.$tags[$i_next];
	    if ($checked_string eq '_a_+_~text_-:_~text_') {
		$a_text_text_flag = 1;
		$a_text_flag = 1;
		$tags[$i] = $tags[$i_next] = undef;
		$i++;
	    }
	    elsif ($tags[$i] eq '_a_+_~text_-') {
	    	$a_text_flag = 1;		
	    	$tags[$i] = undef;
	    }
	}
	$iteration_strings[$i] = join(':', grep(defined $_, @tags));
	# print $a_text_flag,"\n";
	# print 'pos ',$iteration_strings[$i],"\n";
    }

    return ($a_text_text_flag, $a_text_flag, \@iteration_strings);
}

sub check_link_block {
    my ($this, $elem, $depth) = @_;

    my $iteration_string = $elem->attr('iteration');
    # 8割を超える範囲に<a>タグを含む繰り返しあり
    if ($iteration_string =~ /_a_/) {
	# a-text以外の部分でlink領域についたiterationかどうかを判断する
	my ($a_text_text_flag, $a_text_flag, $iteration_strings) = $this->ignore_a_text($iteration_string);
	$iteration_string = join(',', @$iteration_strings);

	# a-textを含む場合
	if ($a_text_flag) {
	    my $flag = 0;
	    foreach my $tag_string (@$iteration_strings) {
		next if !defined $tag_string;
		if (defined $elem->attr('div_char') &&
		    (scalar grep($_ eq 'br', split(/_/, $tag_string))) < 2 && (scalar grep($_ eq '~text', split(/_/, $tag_string))) < 2) {
		    return $elem->attr('length');
		}
	    }
	    return 0;
	}
	# a-textを含まない場合
	else {
	    # blockタグを含む
	    return $elem->attr('length') if scalar grep(defined $BLOCK_TAGS{$_} > 0, split(/_/, $iteration_string)) > 0;
	}
    }

    my $sum = 0;
    for my $child_elem ($elem->content_list){
	$sum += $this->check_link_block($child_elem, $depth++);
    }

    return $sum;
}

sub check_calender {
    my ($this, $elem, $texts) = @_;

    my $counter;
    my %buf;
    foreach my $text (@$texts) {
	if ($text =~ /^([月火水木金土日]|mon|tue|wed|thu|fri|sat|sun)$/i) {
	    $buf{$text} = 1;
	    return 1 if scalar keys %buf == 7;
	}
    }
}

sub attach_pos_info {
    my ($this, $elem) = @_;    

    return if $this->is_stop_elem($elem) || !$this->{root_width} || !$this->{root_height};

    # 属性付与
    $elem->attr('myleft_rate', ($elem->attr('myleft') - $this->{root_left}) / $this->{root_width});
    $elem->attr('mytop_rate', ($elem->attr('mytop') - $this->{root_top}) / $this->{root_height});
    $elem->attr('mywidth_rate', $elem->attr('mywidth') / $this->{root_width});
    $elem->attr('myheight_rate', $elem->attr('myheight') / $this->{root_height});
    
    $elem->attr('pos_valid_flag', 1) if $elem->{'mywidth_rate'} && $elem->{'myheight_rate'};

    # 再帰
    foreach my $child_elem ($elem->content_list){
    	if (!$this->is_stop_elem($child_elem)) {
    	    $this->attach_pos_info($child_elem);
    	}
    }
}

sub attach_elem_length {
    my ($this, $elem) = @_;

    return if $this->is_stop_elem($elem);

    my $length_all = 0;

    # classを消去(ついで)
    if (ref($elem) eq 'HTML::Element' && $elem->attr('class')) {
	$elem->attr('class', undef);
    }

    my @content_list = $elem->content_list;
    
    # もう子供がいない
    if (@content_list == 0){
	my $tag = $elem->tag;
	if ($TAG_with_ALT{$tag} && !$elem->attr('usemap')) {
	    $length_all = ($this->{opt}{print_offset} ? length(decode('utf8', $elem->attr("alt"))) : length($elem->attr("alt"))) if defined $elem->attr("alt");
	}
	# ホワイトスペースは無視
	elsif ($tag eq '~text') {
	    my $text_buf = $this->{opt}{print_offset} ? decode('utf8', $elem->attr('text')) : $elem->attr('text');
	    $length_all = length($text_buf) if $text_buf !~ /^\s+$/;
	}
	else {
	    $length_all = 0;
	}
    }
    # さらに子供をたどる
    else {
	for my $child_elem (@content_list){
	    if (!$this->is_stop_elem($child_elem)) {
		$length_all += $this->attach_elem_length($child_elem);
	    }
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
    foreach my $child_elem ($elem->content_list){
    	if (!$this->is_stop_elem($child_elem)) {
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

sub print_offset {
    my ($this, $elem, $num, $p_elem) = @_;

    return if ref($elem) ne 'HTML::Element';

    if (defined $elem->attr('myblocktype')) {
	my $offset;
	my $closing_offset;
	$offset = $elem->attr('-offset');
	$closing_offset = $elem->attr('-closing_offset');
	if (defined($offset) && defined($closing_offset)) {
	    print $offset,' ', $closing_offset,' ',
		$elem->attr('myblocktype'),' ', $elem->tag,"\n";
	} else {
	    print '0 0 no-offsets ', $elem->tag, "\n";
	}
    }

    my @content_list = $elem->content_list;
    if (@content_list) {
	my $array_size = scalar @content_list;
	for (my $i = 0;$i < $array_size; $i++) {
	    $this->print_offset($content_list[$i], $i, $elem);
	}
    }
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
    print $space, '●COL_NUM : ', $elem->attr('col_num'), "\n" if $elem->attr('col_num');

    # タグ名 [文字長] (ブロックの最初の位置におけるHTML先頭からの割合-ブロックの最後の位置におけるHTML先頭からの割合) ★ブロック名★ 《_a_:(リンクの割合)》(文字列)
    # 出力例
    #  td [78] (17.86-27.81) ★link★《_a_:1.00》
    #  img [8] (11.73-12.76)《_a_:0.00》 協和のアガリクス

    printf "%s %s [%d] (%.2f-%.2f)", $space, $elem->tag, $length, $elem->attr('ratio_start') * 100, $elem->attr('ratio_end') * 100;

    if ($elem->attr('myblocktype')) {
	print ' ★',  $elem->attr('myblocktype');
	print ' (',$elem->attr('no'),')' if $elem->attr('no');
	print '★';
    }

    if ($elem->attr('myblocktype_more')) {
	print ' ★',  $elem->attr('myblocktype_more'),'★';
    }

    if ($elem->attr('iteration')) {
 	print ' 【', $elem->attr('iteration'), '】';
    }

    if ($elem->attr('iteration_number')) {
 	print ' (', $elem->attr('iteration_number'), ')';
    }

    if ($elem->attr("length") != 0) {
	printf "《_a_:%.2f》" ,$this->check_link_block($elem) / $elem->attr("length");
    }

    # printf " *(t, l, h, w) = (%.2f, %.2f, %.2f, %.2f)" ,
    # $elem->attr('mytop_rate'), $elem->attr('myleft_rate'), $elem->attr('myheight_rate'), $elem->attr('mywidth_rate');

    # printf " *(h, w) = (%d, %d)",
    # $elem->attr('myheight'), $elem->attr('mywidth'); 

    # printf " *(mh, mw) = (%d, %d)",
    # $elem->attr('myheight_max'), $elem->attr('mywidth_max'); 

    # print '[',$elem->attr('div_char'),']' if defined $elem->attr('div_char');

    if ($elem->attr('text')) {
	my $text_buf = $this->{opt}{print_offset} ? decode('utf8', $elem->attr('text')) : $elem->attr('text');
	print ' ', length $text_buf > 10 ? substr($text_buf, 0, 10) . '‥‥' : $text_buf;
    }
    elsif ($TAG_with_ALT{$elem->tag} && !$elem->attr('usemap') && $elem->attr('alt')) {
	my $text_buf = $this->{opt}{print_offset} ? decode('utf8', $elem->attr('alt')) : $elem->attr('alt');
	print ' ', length $text_buf > 10 ? substr($text_buf, 0, 10) . '‥‥' : $text_buf;
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
    my @content_list = $elem->content_list;

    if (@content_list) {
	$string .= '+';
	for my $child_elem (@content_list){
	    $string .= $this->get_subtree_string($child_elem);
	}
	$string .= '-';
    }

    $elem->attr('subtree_string', $string);

    return $string;
}

sub get_leaf_string {
    my ($this, $elem) = @_;

    my @content_list = $elem->content_list;
    my $string;
    unless (@content_list) {
	$string = '_' . $elem->tag . '_';
    }

    if (@content_list) {
	$string .= '+';
	for my $child_elem (@content_list){
	    $string .= $this->get_leaf_string($child_elem);
	}
	$string .= '-';
    }

    $elem->attr('leaf_string', $string);

    return $string;
}

sub cut_table_substring {
    my ($this, $elem, $substrings_ref) = @_;

    my $block_ratio = $elem->{ratio_end} - $elem->{ratio_start};
    return if $elem->tag !~ /table|tbody/ || $block_ratio >= $ITERATION_TABLE_RATIO_MAX || $block_ratio <= $ITERATION_TABLE_RATIO_MIN;

    my @tr_num = $elem->find('tr');
    return if scalar @tr_num <= $TABLE_TR_MIN; # table中のtrの数が少ない

    # trから始まる && 全行が同じcol数 && 3col(=tdが3つ)以上
    my ($pre_col_num, $cur_col_num);
    foreach my $substring (@$substrings_ref) {
	next if $substring =~ /^_tr_\+_th_/; # 例 : Agaricus 055のような場合に対処

	return if $substring !~ /^_tr_/;
	$cur_col_num = scalar split('_td_', $substring) -1;
	return if ($pre_col_num > 0 && $pre_col_num != $cur_col_num) || $cur_col_num <= $TABLE_TD_MIN;
	$pre_col_num = $cur_col_num;

    }

    my $substrings_ref_buf;
    my $array_size = scalar @$substrings_ref;
    for (my $i = 0; $i < $array_size; $i++) {
	# substringsの左側2カラム以外の部分は'*'に変換
	# 例 : <変換前> _tr_+_td_+_img_-_td_+_~text_-_td_+_~text_--
	#      <変換後> _tr_+_td_+_img_-_td_+_~text_-_td_*
	if ($substrings_ref->[$i] =~ /^(_tr_\+_td_\+(?:.+?)-_td_\+(?:.+?)-_td_)/) {
	    $substrings_ref_buf->[$i] = $1.'*';
	}
	# thとかの場合
	else {
	    $substrings_ref_buf->[$i] = $substrings_ref->[$i]
	}
    }

    # 同じsubstringsの割合が閾値以上
    my %group_substrings;
    foreach my $substring (@$substrings_ref_buf) {
	$group_substrings{$substring}++;
    }
    foreach my $num (reverse sort values %group_substrings) {
	@$substrings_ref = @$substrings_ref_buf if $num / scalar @$substrings_ref > $TR_SUBSTRING_RATIO;
	last;
    }
}

sub detect_iteration {
    my ($this, $elem) = @_;

    my @content_list = $elem->content_list;

    # 子供がいない
    return if (@content_list == 0);

    my (@substrings, @tags);
    for my $child_elem (@content_list){

	push @substrings, $child_elem->attr('subtree_string');
	push @tags, $child_elem->tag;
    }
    
    # 本当の表っぽいtableタグを検出(柔軟な繰り返しの検出のため)
    $this->cut_table_substring($elem, \@substrings) if defined $elem->{ratio_end};

    my $child_num = scalar @content_list;
    my ($iteration_ref, $iteration_buffer);
    # ブロックの大きさ
  LOOP:
    for (my $i = $ITERATION_BLOCK_SIZE; $i >= 1; $i--) {

	# スタートポイント
	for (my $j = 0; $j < $child_num; $j++) {
	    my $k;
	    my ($flag, $a_text_flag, $div_char) = (0, 0, '');

	    # ブロックタグをチェック
	    for ($k = $j; $k < $j+$i; $k++){
		$flag = 1 if defined $BLOCK_TAGS{$tags[$k]};
	    }
	    # 例外処理
	    if ($flag == 0) {
		# _a_+_img_-
		if ($i == 1) {
		    for ($k = $j; $k < $j+$i; $k++){
			$flag = 1 if $substrings[$k] eq '_a_+_img_-' && $substrings[$k] eq $substrings[$k+$i+1];
		    }
		}
		# aの後ろに同じテキストが来る場合
		elsif ($i == 2) {
		    for ($k = $j; $k < $j+$i; $k++){
			# _a_+_~text_-:_~text_
			if ($tags[$k] eq 'a' && $k+1 < $j+$i && $tags[$k+1] eq '~text' &&
			    $k+$i+1 < $child_num && $tags[$k+$i+1] eq '~text' && $substrings[$k+1] eq $substrings[$k+$i+1]) {

			    ($flag, $a_text_flag, $div_char) = $this->Get_div_char(
				$this->{opt}{print_offset} ? decode('utf8', $content_list[$k+1]->attr('text')) : $content_list[$k+1]->attr('text'),
				$this->{opt}{print_offset} ? decode('utf8', $content_list[$k+$i+1]->attr('text')):$content_list[$k+$i+1]->attr('text'),
				$flag, $div_char
				);
			}
			# ~text_:_a_+_~text_-
			elsif ($tags[$k] eq '~text' && $k+1 < $j+$i && $tags[$k+1] eq 'a' && 
			       $k+$i < $child_num && $tags[$k+$i] eq '~text' && $substrings[$k] eq $substrings[$k+$i]) {

			    ($flag, $a_text_flag, $div_char) = $this->Get_div_char(
				$this->{opt}{print_offset} ? decode('utf8', $content_list[$k]->attr('text')) : $content_list[$k]->attr('text'),
				$this->{opt}{print_offset} ? decode('utf8', $content_list[$k+$i]->attr('text')):$content_list[$k+$i]->attr('text'),
				$flag, $div_char
				);
			}
		    }
		}
	    }

	    next if $flag == 0;

	    for ($k = $j+$i; $k < $child_num; $k++) {
		# 繰り返し終了
		last if $substrings[$k] ne $substrings[$k - $i];

		# a-textの場合
		#-------------------------------------------#
                # 下の例文が3回のa-textとなることを防ぐ	    #
		# <a>市民</a>、<a>女性</a>、<a>子供</a>たち #
                #-------------------------------------------#
		if ($a_text_flag) {
		    last if $tags[$k] eq '~text' && $content_list[$k]->attr('text') ne $div_char;
		}

	    }

	    # 繰り返し発見
	    if ($k - $j >= $ITERATION_TH * $i) {
		# 普通の文中のa-textの繰り返しは許さない
                #                    繰り返し回数が少ない                      繰り返し部分の占める割合が低い
		if (!$a_text_flag || ($k - $j) / $i > $A_TEXT_ITERATION_MIN || scalar @tags * $A_TEXT_RATE < $k - $j) {

		    my @buf_substrings = @substrings;
		    my @iteration_types = splice(@buf_substrings, $j, $i); 

		    # $jのみ異なるものは無視
		    if (!defined $iteration_buffer->{$k.'%'.join(':', @iteration_types)}) {
			my %hash = (j => $j, k => $k, iteration => \@iteration_types, iteration_string => join(':', @iteration_types), div_char => $div_char);
			push @{$iteration_ref->[$i]}, \%hash;

			$iteration_buffer->{$k.'%'.join(':', @iteration_types)} = 1;
		    }
		}
	    }
	}
    }

    # 最適な繰り返し単位を見つける
    $this->select_best_iteration($elem, $iteration_ref) if defined $iteration_ref;

    # 再帰
    for my $child_elem (@content_list){
	$this->detect_iteration($child_elem);
	$child_elem->attr('div_char', $elem->attr('div_char')) if $elem->attr('div_char');
    }
}


sub Get_div_char {
    my ($this, $text_buf_a, $text_buf_b, $flag, $div_char) = @_;
    my ($a_text_flag);

    if ($text_buf_a eq $text_buf_b) {
	$div_char = $text_buf_a;
	# text部分の文字列を制限
	if ($div_char =~ /^\s*(?:$ITERATION_DIV_CHAR)+\s*$/o) {
	    $flag = 1;
	    $a_text_flag = 1;
	}
    }

    return ($flag, $a_text_flag, $div_char);
}


sub select_best_iteration {
    my ($this, $elem, $iteration_ref) = @_;

    # 最適なiterationを探す
    my $best_iteration_block_size = 0;
    my $best_iteration_size = 0;
    my $j_buf;
    my @best_iterations_buffer;
    for (my $i = $#$iteration_ref; $i >= 1; $i--) {
	next if !defined $iteration_ref->[$i];
	my $iteration_ref_size = scalar @{$iteration_ref->[$i]};
	for (my $j = 0; $j < $iteration_ref_size; $j++) {
	    my $ref = $iteration_ref->[$i][$j];
	    next if !defined $ref;

	    # 初期状態
	    if (scalar @best_iterations_buffer == 0) {
		$this->push_best_iteration_info(\@best_iterations_buffer, -1, $ref, $i);
	    }
	    else {
		my $covered_flag;
		my $best_iterations_buffer_size = scalar @best_iterations_buffer;
		for (my $m = 0; $m < $best_iterations_buffer_size; $m++) {
		    my $best_now = $best_iterations_buffer[$m];
		    # 既存のものと重複がある場合
		    if ($ref->{j} <= $best_now->{j} && $best_now->{k} <= $ref->{k}) {
			#        string : a a a a a 
			#——————————————————————
			# best_now(i=2) : --- ---   (破棄)
			#      ref(i=1) : - - - - - (採用=上書き)
			$this->push_best_iteration_info(\@best_iterations_buffer, $m, $ref, $i) if $i < $best_now->{i};

			$covered_flag = 1;
			last;
		    }
		}

		# 既存のものと重複がない場合 -> 採用
		$this->push_best_iteration_info(\@best_iterations_buffer, -1, $ref, $i) if !$covered_flag;
	    }
	}
    }

    if (scalar @best_iterations_buffer) {
	my $tmp;
	my $div_char = join('%', grep {!$tmp->{$_}++ && $_} (map {$_->{div_char}} @best_iterations_buffer));
	undef $tmp;

	# (親ノード)
	# 重複したものは削除 例: a a a b b a a -> a,b,a とおもいきや a,b
	$elem->attr('iteration', join(',', grep {!$tmp->{$_}++} (map {$_->{iteration_string}} @best_iterations_buffer)));
	$elem->attr('div_char', $div_char) if $div_char;

	# (子ノード)
	# 全てに対して付与
	foreach my $ref (@best_iterations_buffer) {
	    $this->attach_iteration_number($elem, $ref->{i}, $ref);
	}
    }
}

sub push_best_iteration_info {
    my ($this, $best_iterations_buffer, $pos, $ref, $i) = @_;

    if ($pos == -1) {
	push @$best_iterations_buffer, {i => $i};
    }
    else {
	$best_iterations_buffer->[$pos]{i} = $i
    }
    foreach my $key (keys %$ref) {
	$best_iterations_buffer->[$pos]{$key} = $ref->{$key};
    }
}

sub attach_iteration_number {
    my ($this, $elem, $i, $ref) = @_;
    my ($j, $k, $iteration_string) = ($ref->{j}, $ref->{k}, $ref->{iteration_string});

    my $iteration_num = int(($k - $j) / $i);
    my ($counter_block, $counter_iteration) = (0, 0);
    my $end = $j + $iteration_num * $i - 1;
    for my $l ($j..$end) {
	my $attr;
	my $l_elem = ($elem->content_list)[$l];
	# 複数ある場合はコンマ区切りで付与
	if ($l_elem->attr('iteration_number')) {
	    $attr .= $l_elem->attr('iteration_number').','.$iteration_string.'%'.$counter_iteration.'/'.$iteration_num;
	}
	else {
	    $attr = $iteration_string.'%'.$counter_iteration.'/'.$iteration_num;
	}
	
	# _a_+_~text_-:_~text_%0/4
	$l_elem->attr('iteration_number', $attr);
	$counter_block++;
	if ($counter_block == $i) {
	    $counter_block = 0;
	    $counter_iteration++;
	}
    }
}


sub get_text {
    my ($this, $elem) = @_;

    return if $this->is_stop_elem($elem);

    my @texts;
    my $tag = $elem->tag;
    # text
    if ($tag eq '~text') {
	push @texts, $this->{opt}{print_offset} ? decode('utf8', $elem->attr('text')) : $elem->attr('text');
    }
    # 画像の場合altを返す
    elsif ($TAG_with_ALT{$tag} && !$elem->attr('usemap') && $elem->attr('alt')) {
	push @texts, $this->{opt}{print_offset} ? decode('utf8', $elem->attr('alt')) : $elem->attr('alt');
    }

    for my $child_elem ($elem->content_list){
	push @texts, $this->get_text($child_elem);
    }

    return @texts;
}

# BLOCKをHTML上で色分けして表示するために整形
sub addCSSlink {
    my ($this, $tmp_elem) = @_;

    my $css_url = '../style.css';

    my $head = $tmp_elem->find('head');
    my $body = $tmp_elem->find('body');

    # 相対パス -> 絶対パスの変換
    # <link href="text.css" rel="stylesheet" type="text/css" />
    if ($this->{opt}{rel2abs} && defined $this->{url}) {
	# CSS
	foreach my $linktag ($head->find('link')) {
	    if ($linktag->attr('rel') eq 'stylesheet' && $linktag->attr('type') eq 'text/css' && defined $linktag->attr('href')) {
		$linktag->attr('href', $this->Rel2Abs($linktag->attr('href')));
	    }
	}

	# 画像
	foreach my $imgtag ($body->find('img')) {
	    $imgtag->attr('src', $this->Rel2Abs($imgtag->attr('src'))) if (defined $imgtag->attr('src'));
	}
    }

    # CSSの部分を追加
    # <link rel="stylesheet" type="text/css" href="style.css">
    $head->unshift_content(['link', {'href' => $css_url, 'rel' => 'stylesheet', 'type' => 'text/css'}]);
    # CSSの優先順位を変更
#    my $tmp = $head->content->[-1];
#    $head->content->[-1] = $head->content->[0];
#    $head->content->[0] = $tmp;

    # エンコードをutf-8に統一
    # <meta http-equiv="Content-Type" content="text/html; charset=Shift_JIS">
    # <META http-equiv="Content-Type" content="text/html; charset=Shift_JIS">
    my $flag;
    foreach my $metatag ($head->find('meta')) {
	if ($metatag->look_down('content', qr/text\/html\;\s*charset\=(.+?)/i)) {
	    $metatag->delete();
	    last;
	}
    }
    $head->push_content(['meta', {'http-equiv' => 'Content-Type', 'content' => 'text/html; charset=utf-8'}]) if !$flag;
}

# 相対パスを絶対パスに変換する関数
# /bb.html, ../bb.html, ./bb.html, bb.html
sub Rel2Abs {
    my ($this, $link) = @_;

    # もともと絶対リンク
    return $link if $link =~ /^https?\:\/\//;

    $link =~ s/^\.\///; # ./bb.html -> bb.html

    my $abs_path = 'http:/';
    my $depth = scalar @{$this->{url_layers_ref}};

    my ($dot, $dir) = ($link =~ /^((?:(?:\.\.)?\/)*)(.*)$/);
    my $up_num = scalar split('/', $dot);

    # /bb.htmlの場合 -> Root
    my $end = $link =~ /^\// ? 0 : $depth-$up_num-1;

    for my $i (0..$end) {
	$abs_path .= '/'.$this->{url_layers_ref}[$i];
    }
    $abs_path .= '/'.$dir;

    return $abs_path;
}

sub url2layers {
    my ($url) = @_;
    my $layers;

    $url =~ s/^http\:\/\///;       # http://aa/bb.html -> aa/bb.html
    $url =~ s/^(.+?)(?:\?|\&)/\1/; # bb.html?foo1=bar1&foo2=bar2 -> bb.html
    $url =~ s/^(.+?)([^\/]*)$/\1/; # aa/bb.html -> aa/

    push @$layers, split('/', $url);
    
    return $layers;
}

sub text2span {
    my ($this, $elem) = @_;

    my @content_list = $elem->content_list;

    if (@content_list) {
	for my $child_elem (@content_list) {
	    $this->text2span($child_elem);
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

    return $TAG_IGNORED{lc($elem->tag)} ? 1 : 0;
}


sub Get_Source_String {
    my ($this, $url, $option) = @_;

    require LWP::UserAgent;

    my $ua = new LWP::UserAgent;
    if ($option->{Google_agent}) {
	$ua->agent('Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US) AppleWebKit/525.19 (KHTML, like Gecko) Chrome/1.0.154.48 Safari/525.19');
    } else {
	$ua->agent('Mozilla/5.0');
    }
    $ua->proxy('http', $this->{opt}{proxy}) if defined $this->{opt}{proxy};
    $ua->proxy('http', $option->{proxy}) if defined $option->{proxy};
    $ua->timeout($option->{timeout}) if $option->{timeout};
    $ua->max_redirect($option->{max_redirect}) if $option->{max_redirect};
    $ua->parse_head(0);

    my $response = $ua->get($url);

    print $url,"\n" if $this->{opt}{debug};
    return $response->status_line unless $response->is_success;

    my $input_string;
    if (defined $option->{nodec}) {
	$input_string = $response->content;
    } else {
	$input_string = decode(guess_encoding($response->content, qw/ascii euc-jp shiftjis 7bit-jis utf8/), $response->content);
    }

    return ($input_string, $url);
}


sub addJavascript {

    my ($this) = @_;
    my $newScript = new HTML::Element('script', 'type' => 'text/javascript', src => './layer.js');

    $this->{tree}->find('body')->push_content($newScript);

    return 1;
}

sub han2zen {
    my ($text) = @_;
    return Unicode::Japanese->new($text)->h2z->getu();
}


1;
