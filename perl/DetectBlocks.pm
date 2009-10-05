package DetectBlocks2;

# $Id$

use strict;
use utf8;
use HTML::TreeBuilder;
use Data::Dumper;
use Encode;
use Dumpvalue;
use Juman;

use Encode;
use Encode::Guess;


our $TEXTPER_TH = 0.5;

our $HEADER_START_TH = 100; # これより小さければheader
our $HEADER_END_TH = 200; # これより小さければheader
our $ALT4HEADER_TH = 15; # 画像のみのheaderの際に必要なalt_text

our $FOOTER_START_TH = 300; # これより大きければfooter
our $FOOTER_END_TH = 100; # これより大きければfooter
our $LINK_RATIO_TH = 0.66; #link領域の割合
our $IMG_RATIO_TH = 0.8; # これより大きければimg (葉だけ数える)

our $ITERATION_BLOCK_SIZE = 8; # 繰り返しのかたまりの最大
our $ITERATION_TH = 2; # 繰り返し回数がこれ以上
our $ITERATION_DIV_CHAR = '\||｜|\>|＞|\<|＜|\/|\s'; # a-textの繰り返しのtextとなりうる文字列

# 柔軟なtableの繰り返しの検出
our $TR_SUBSTRING_RATIO = 0.5; # 繰り返しとして認識されるための同じsubstringの割合(tr要素以下)
our $TABLE_TR_MIN = 3; # これ以下のtrしか持たないtableは対象外
our $TABLE_TD_MIN = 2; # これ以下のtdしか持たないtableは対象外
our $ITERATION_TABLE_RATIO_MIN = 0.30; # これ以下の長さしかないtableは対象外
our $ITERATION_TABLE_RATIO_MAX = 0.95; # これ以上の長さのtableは対象外

our $MAINTEXT_MIN = 200;

# FOOTER用の文字列
our $FOOTER_STRING = '住所|所在地|郵便番号|電話番号|著作権|問[い]?合[わ]?せ|利用案内|tel|.+[都道府県].+[市区町村]|(06|03)\-?\d{4}\-?\d{4}|\d{3}\-?\d{3}\-?\d{4}|mail|Copyright|\(c\)|著作権|all\s?rights\s?reserved|免責事項|プライバシー.?ポリシー|home|ホーム(?:ページ|[^\p{Kana}]|$)';
our $FOOTER_STRING_EX = 'all\s?rights\s?reserved|copyright\s.*(?:\(c\)|\d{4})'; # Copyright

# maintext用の文字列
our $MAINTEXT_PARTICLE_TH = 0.05; # 助詞の全形態素に占める割合がこれ以上なら本文
our $MAINTEXT_POINT_TH = 0.05; # 句点の全形態素に占める割合がこれ以上なら本文

# 以下のブロックはmore_blockを探さない
our $NO_MORE_TAG = '^(header|img|form)$';

# more_blockとして検出するもの(優先度順に記述)
our @MORE_BLOCK_NAMES = qw/profile address/;

# more_blockに必要な文字列の数
our $MORE_BLOCK_NUM_TH = 2;
# more_blockに必要な文字列を含むブロックの割合
our $MORE_BLOCK_RATIO_TH = 0.4;
# more_blockの領域サイズの最大値
our $MORE_BLOCK_LENGTH_MAX_TH = 500;

# プロフィール領域用の文字列
our $PROFILE_STRING = '通称|管理人|氏名|名前|author|ニックネーム|ユーザ[名]?|user\-?(id|name)|誕生日|性別|出身|年齢|アバター|プロフィール|profile|自己紹介';
# 住所領域用の文字列 ★誤りが多いので停止中 : (\p{Han}){2,3}[都道府県]|(\p{Han}){1,5}[市町村区]  -> 例 : 室町時代
our $ADDRESS_STRING = '(郵便番号|〒)\d{3}(?:-|ー)\d{4}|住所|連絡先|電話番号|(e?-?mail|ｅ?−?(ｍａｉｌ|メール))|(tel|ｔｅｌ)|フリーダイ(ヤ|ア)ル|(fax|ｆａｘ)';

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
our $EXCEPTIONAL_BLOCK_TAGS = '^(br|li)$';

# HTMLにする際に捨てる属性
our @DECO_ATTRS = qw/bgcolor style id subtree_string leaf_string/;

sub new{
    my (undef, $opt) = @_;

    my $this = {};
    $this->{opt} = $opt;

    # 32/64bit
    my $machine =`uname -m`;
    my $JUMAN_COMMAND = $machine =~ /x86_64/ ? '/share/usr-x86_64/bin/juman' : '/share/usr/bin/juman';

    $this->{juman} = new Juman(-Command => $JUMAN_COMMAND);

    bless $this;
}

sub maketree{
    my ($this, $htmltext, $url) = @_;

    # copyright置換
    $htmltext =~ s/\&copy\;/\(c\)/g;

    my $tree = HTML::TreeBuilder->new;
    $tree->p_strict(1); # タグの閉じ忘れを補完する
    $tree->parse($htmltext);
    $tree->eof;
    
    #url処理
    if (defined $url) {
	$this->{url} = $url;
	if($this->{url} =~ /^http\:\/\/([^\/]+)/) {
	    # 例 : http://www.yahoo.co.jp/news => www.yahoo.co.jp
	    $this->{domain} = $1;
	}
	$this->{url_layers_ref} = &url2layers($this->{url}); # urlを'/'で区切る
    }

    $this->{tree} = $tree;
}

sub detectblocks{
    my ($this) = @_;

    my $body = $this->{tree}->find('body');

    # テキストをタグ化
    $body->objectify_text;

    # 自分以下のテキストの長さを記述
    $this->attach_elem_length($body);
    $this->{alltextlen} = $body->attr('length');

    # テキストの累積率を記述
    $this->attach_offset_ratio($body);
    # 自分以下のタグ木を記述
    $this->get_subtree_string($body);
    # 自分以下の葉タグを記述
    $this->get_leaf_string($body);

    # タグの繰り返し構造を見つける
    $this->detect_iteration($body);

    $this->detect_block($body);

    if ($this->{opt}{add_class2html}) {
	$this->remove_deco_attr($body);	    

	$this->text2span($body);
    }
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


sub detect_block {
    my ($this, $elem, $option) = @_;

    my $leaf_string1 = $elem->attr('leaf_string');
    my $leaf_string2 = $elem->attr('leaf_string');

    my @texts = $this->get_text($elem);

    # # さらに分割するかどうかを判定 (する:1, しない:0)
    my $divide_flag = $this->check_divide_block($elem, \@texts) if !$option->{parent};



    if (defined $option->{parent} ||
    	((!$elem->content_list || ($this->{alltextlen} && $elem->attr('length') / $this->{alltextlen} < $TEXTPER_TH)) && !$divide_flag) ||
	$elem->attr('iteration') =~ /\*/) {
    	my $myblocktype;
	
    	# フッター
    	# 条件 : 以下のすべてを満たす
    	# - ブロックの開始がページ末尾から300文字以内
    	# - ブロックの終了がページ末尾から100文字以内
    	# - 「copyright」など特別な文字列を含む
    	if ($this->check_footer($elem, \@texts)) {
    	    $myblocktype = 'footer';
    	}

    	# ヘッダー
    	# 条件 : 以下のすべてを満たす
    	# - ブロックの開始がページ先頭から100文字以内
    	# - ブロックの終了がページ先頭から200文字以内
    	# - index.*へのリンクを持つ
    	elsif ($this->check_header($elem)) {
    	    $myblocktype = 'header';
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
    	    if ($this->{opt}{get_more_block} && $myblocktype !~ /$NO_MORE_TAG/) {
    		# そのための情報を得る
    		$this->detect_string($elem);

    		$this->detect_more_blocks($elem, \@texts) ;
    	    }
    	}
    }
    else {
    	my $block_start;
    	for (my $i = 0;$i < $elem->content_list; $i++) {
    	    my $child_elem = ($elem->content_list)[$i];
    	    # block要素 or textが50%以上のblock
    	    if (($this->{alltextlen} && $child_elem->attr('length') / $this->{alltextlen} >= $TEXTPER_TH) ||
    		(defined $BLOCK_TAGS{$child_elem->tag} && $child_elem->tag !~ /$EXCEPTIONAL_BLOCK_TAGS/i)) {
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
    	    $this->detect_block_region($elem, $block_start, scalar $elem->content_list - 1);
    	}
    }
}

sub detect_more_blocks {
    my ($this, $elem) = @_;

    # print $elem->{myblocktype},"\n";
    
    # このブロック以下をチェックする意味があるか
    return if !$this->check_under_this_block($elem);

    my $myblocktype_more;
    my $elem_length = $elem->attr('length');

    # myblocktypeで決定した領域をさらに分割「できる」かどうか
    # 分割できる
    if ($this->check_multiple_block($elem)) {
	# 子供が1ブロックしかない場合無条件で再帰
	if (scalar grep($BLOCK_TAGS{$_->tag} && $_->tag !~ /$EXCEPTIONAL_BLOCK_TAGS/i, $elem->content_list) == 1) {
	    $this->detect_more_blocks(($elem->content_list)[0]);
	}

	else {
	    my $devide_flag = 1;;
	    foreach my $more_block_name (@MORE_BLOCK_NAMES)  {
		my $block_ref = $elem->{'_'.$more_block_name};

		# 条件 : 必要な文字列をx個以上含む && 比が0.x以上 && ブロックの長さがxxx以下
		if ($block_ref->{num} >= $MORE_BLOCK_NUM_TH && $block_ref->{ratio} > $MORE_BLOCK_RATIO_TH &&
		    $elem->attr('length') < $MORE_BLOCK_LENGTH_MAX_TH) {
		    # 属性付与
		    $devide_flag = 0;
		    $this->attach_attr_blocktype($elem, $more_block_name, 'myblocktype_more');
		    # last;
		}
	    }

	    # 再帰
	    if ($devide_flag) {
		foreach my $child_elem ($elem->content_list) {
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
# 	print join(':', $this->get_text($elem)),"\n";
# 	print $more_block_name,"\n";
# 	Dumpvalue->new->dumpValue($ref->{$more_block_name});
 	$elem->attr('_'.$more_block_name, $ref->{$more_block_name});
    }
    
    return $ref;
}

sub check_more_block_string {
    my ($this, $elem) = @_;

    my $text = $elem->attr('text');

    my ($profile, $address);
    # profile
    if (my $matches = ($text =~ s/($PROFILE_STRING)/\1/ig)) {
	$profile->{length} += $elem->attr('length');
	$profile->{num} += $matches;
    }

    # address
    if (my $matches = ($text =~ s/($ADDRESS_STRING)/\1/ig)) {
	$address->{length} += $elem->attr('length');
	$address->{num} += $matches;
    }

    return ({profile => $profile, address => $address});
}


# 自分以下を分割しようがあるか
# (子供数が1ブロックでも孫のブロック数が2以上あるかもしれない -> 分割される可能性がある)
sub check_multiple_block {
    my ($this, $elem) = @_;
	
    if (ref($elem) eq 'HTML::Element' && $elem->content_list) {
	if ($elem->content_list == 1) {
	    return $this->check_multiple_block(($elem->content_list)[0]);
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
    my $length = 0;
    my ($subtree_string, $leaf_string);
    my $ratio_start = $this->get_ratio($elem, $start, $end);
    my $ratio_end = $this->get_ratio($elem, $end, $start);

    foreach my $tmp (($elem->content_list)[$start..$end]) {
	$length += $tmp->attr('length');
	$subtree_string .= $tmp->attr('subtree_string');
	$leaf_string .= $tmp->attr('leaf_string');
    }
    my $new_elem = new HTML::Element('div', 'length' => $length,
				     'subtree_string' => $subtree_string, 'leaf_string' => $leaf_string,
				     'ratio_start' => $ratio_start, 'ratio_end' => $ratio_end);
    
    # cloneを作成(こうしないと$elem->content_listのpush_contentした部分が消失)
    my $clone_elem = $elem->clone;
    foreach my $tmp (($clone_elem->content_list)[$start..$end]) {
	$new_elem->push_content($tmp);
    }
	
    return $new_elem;
}
sub get_ratio {
    my ($this, $elem, $start, $end) = @_;
    
    my $search_str = $start < $end ? 'start' : 'end';
    my $ratio;
    my $i =  $start;
    # brなどはratioの情報がない
    do {
	$ratio = ($elem->content_list)[$i]->attr('ratio_'.$search_str);
	return $ratio if $ratio;
	$start < $end ? $i++ : $i--;
    } while ($i != $end);
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

    # 全てのタグにblock名を付与(★仮)
    if ($this->{opt}{add_blockname2alltag} && $elem->content_list) {
	foreach my $child_elem ($elem->content_list) {
	    next if $this->is_stop_elem($child_elem);
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
		    # 末尾の形態素条件
 		    my $last_mrph = ($this->{juman}->analysis($img_elem->attr('alt'))->mrph)[-1];
		    return 1 if $last_mrph->bunrui !~ /^(句点|読点)$/ && $last_mrph->hinsi !~ /^(助詞|助動詞|判定詞)$/;
		}
	    }
	}
    }

    return 0;
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
    # all right researved は無条件でOK
    else {
	foreach my $text (@$texts) {
	    if ($text =~ /$FOOTER_STRING_EX/i) {
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
    if ($total_mrph_num &&
	($particle_num / $total_mrph_num > $MAINTEXT_PARTICLE_TH || $punc_mark_num / $total_mrph_num > $MAINTEXT_POINT_TH)) {
	return 1;
    }
    else {
	return 0;
    }
}

sub check_divide_block {
    my ($this, $elem, $texts) = @_;

    # 下階層を調べる意味があるかをチェック(ある:1, ない:0)
    return 0 if !$this->check_multiple_block($elem);

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

    # content_listサイズが1ならさらに潜る
    if ($elem->content_list == 1) {
    	return $this->check_divide_block_by_copyright(($elem->content_list)[0], $texts);
    }
    else {
	foreach my $child_elem ($elem->content_list) {
	    next if $child_elem ne 'HTML::Element';
	    my @child_texts = $this->get_text($child_elem);
	    return 1 if !$this->check_footer($elem, $texts) && $this->check_footer($child_elem, \@child_texts);
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

sub check_calender {
    my ($this, $elem, $texts) = @_;

    my $counter;
    my %buf;
    foreach my $text (@$texts) {
	if ($text =~ /^(月|火|水|木|金|土|日|mon|tue|wed|thu|fri|satb|sun)$/i) {
	    $buf{$text} = 1;
	    return 1 if scalar keys %buf == 7;
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
    
    # もう子供がいない
    if ($elem->content_list == 0){
	my $tag = $elem->tag;
	if ($tag eq 'img') {
	    $length_all = length($elem->attr("alt")) if (defined $elem->attr("alt"));
	}
	# ホワイトスペースは無視
	elsif ($tag eq '~text' && $elem->attr('text') !~ /^\s+$/) {
	    $length_all = length($elem->attr("text"));
	}
	else {
	    $length_all = 0;
	}
    }
    # さらに子供をたどる
    else {
	for my $child_elem ($elem->content_list){
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
    for my $child_elem ($elem->content_list){
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

    if ($elem->attr('myblocktype_more')) {
	print ' ★',  $elem->attr('myblocktype_more'),'★';
    }

    if ($elem->attr('iteration')) {
 	print ' 【', $elem->attr('iteration'), '】';
    }

    if ($elem->attr('iteration_number')) {
 	print ' (', $elem->attr('iteration_number'), ')';
    }

    if ($elem->attr('text')) {
	print ' ', length $elem->attr('text') > 10 ? substr($elem->attr('text'), 0, 10) . '‥‥' : $elem->attr('text');
    }
    elsif ($elem->tag eq 'img' && $elem->attr('alt')) {
	print ' ', length $elem->attr('alt') > 10 ? substr($elem->attr('alt'), 0, 10) . '‥‥' : $elem->attr('alt');
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

sub cut_table_substring {
    my ($this, $substrings_ref) = @_;

    # trから始まる && 全行が同じcol数 && 3col以上
    my ($pre_col_num, $cur_col_num);
    foreach my $substring (@$substrings_ref) {
	next if $substring =~ /^_tr_\+_th_/; # 例 : Agaricus 055のような場合に対処

	return if $substring !~ /^_tr_/;
	$cur_col_num = scalar split('_td_', $substring) -1;
	return if ($pre_col_num > 0 && $pre_col_num != $cur_col_num) || $cur_col_num <= $TABLE_TD_MIN;
	$pre_col_num = $cur_col_num;

    }

    my $substrings_ref_buf;
    for (my $i = 0; $i < @$substrings_ref; $i++) {
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

    # 子供がいない
    return if ($elem->content_list == 0);

    my @substrings;
    my @tags;
    for my $child_elem ($elem->content_list){
	push @substrings, $child_elem->attr('subtree_string');
	push @tags, $child_elem->tag;
    }
    
    # 本当の表っぽいtableタグを検出(柔軟な繰り返しの検出のため)
    if (defined $elem->{ratio_end}) {
	my $block_ratio = $elem->{ratio_end} - $elem->{ratio_start};
	if ($elem->tag =~ /table|tbody/ &&
	    $block_ratio < $ITERATION_TABLE_RATIO_MAX && $block_ratio > $ITERATION_TABLE_RATIO_MIN) {
	    my @tr_num = $elem->find('tr');
	    $this->cut_table_substring(\@substrings) if scalar @tr_num > $TABLE_TR_MIN;
	}
    }

    my $child_num = scalar $elem->content_list;
    my $iteration_ref;
    # ブロックの大きさ
  LOOP:
    for (my $i = $ITERATION_BLOCK_SIZE; $i >= 1; $i--) {

	# スタートポイント
	for (my $j = 0; $j < $child_num; $j++) {
	    my $k;
	    my ($flag, $div_char) = (0, '');

	    # ブロックタグをチェック
	    for ($k = $j; $k < $j+$i; $k++){
		$flag = 1 if defined $BLOCK_TAGS{$tags[$k]};
	    }
	    # 例外処理
	    if ($flag == 0) {
		# aの後ろに同じテキストが来る場合
		# ★ <a>HOME</a><font>|</font> <a>SITEMAP</a><font>|</font> ... の場合は??
		#   -> @tagsでなく@substringsを利用? $i==2?
		#   -> 例ページを忘れた
		for ($k = $j; $k < $j+$i; $k++){
		    if ($tags[$k] eq 'a' && $k+1 < $j+$i && $tags[$k+1] eq '~text' && 
		    	$k+$i+1 < $child_num && $tags[$k+$i+1] eq '~text' && $substrings[$k+1] eq $substrings[$k+$i+1] &&
		    	($elem->content_list)[$k+1]->attr('text') eq ($elem->content_list)[$k+$i+1]->attr('text')) {
		    	$div_char = ($elem->content_list)[$k+1]->attr('text');
			# text部分の文字列を制限
		    	$flag = 1 if $div_char =~ /^\s*(?:$ITERATION_DIV_CHAR)+\s*$/;
		    }
		}
		# a, img の繰り返し(headerとか)
		if ($i == 1) {
		    for ($k = $j; $k < $j+$i; $k++){
			$flag = 1 if $substrings[$k] eq '_a_+_img_-' && $substrings[$k] eq $substrings[$k+$i+1];
		    }
		}
	    }

	    next if $flag == 0;

	    for ($k = $j+$i; $k < $child_num; $k++) {
	    	last if $substrings[$k] ne $substrings[$k - $i];
	    }

	    # 繰り返し発見
	    if ($k - $j >= $ITERATION_TH * $i) {
	    	my @buf_substrings = @substrings;
	    	%{$iteration_ref->[$i]} = (j => $j, k => $k, iteration => [splice(@buf_substrings, $j, $i)], div_char => $div_char);
	    	next LOOP;
	    }
	}
    }
    
    # 最適な繰り返し単位を見つける
    $this->select_best_iteration($elem, $iteration_ref) if defined $iteration_ref;

    for my $child_elem ($elem->content_list){
	$this->detect_iteration($child_elem);
    }
}


sub select_best_iteration {
    my ($this, $elem, $iteration_ref) = @_;

    my $flag;
    # 最適なiterationを探す
    my $best_iteration_size = 0;
    for (my $i = $#$iteration_ref; $i >= 1; $i--) {
  	my $ref = $iteration_ref->[$i];
	next if !defined $ref;
	if ($best_iteration_size == 0 || $best_iteration_size >= scalar @{$ref->{iteration}}) {
	    ($best_iteration_size, $flag) = (scalar @{$ref->{iteration}}, 1);
	}
    }

    # iteration_numberを付与
    if ($flag) {
	my $ref = $iteration_ref->[$best_iteration_size];
	$elem->attr('iteration', join(':', @{$ref->{iteration}}));
	$elem->attr('div_char', $ref->{div_char}) if $ref->{div_char};
	$this->attach_iteration_number($elem, $best_iteration_size, $ref->{j}, $ref->{k});
    }
}

sub attach_iteration_number {
    my ($this, $elem, $i, $j, $k) = @_;

    my $iteration_num = int(($k - $j) / $i);
    my ($counter_block, $counter_iteration) = (0, 0);
    my $end = $j + $iteration_num * $i - 1;
    for my $l ($j..$end) {
	($elem->content_list)[$l]->attr('iteration_number', $counter_iteration.'/'.$iteration_num);
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
    $head->push_content(['link', {'href' => $css_url, 'rel' => 'stylesheet', 'type' => 'text/css'}]);
    # CSSの優先順位を変更
    my $tmp = $head->content->[-1];
    $head->content->[-1] = $head->content->[0];
    $head->content->[0] = $tmp;

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
    return $link if $link =~ /^http\:\/\//;

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

    if ($elem->content_list) {
	for my $child_elem ($elem->content_list) {
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

    if ($elem->tag =~ /$TAG_IGNORED/i) {
	return 1;
    }
    return 0;
}


sub Get_Source_String {
    my ($this, $url, $option) = @_;

    require LWP::UserAgent;

    my $ua = new LWP::UserAgent;
    $ua->agent('Mozilla/5.0');
    $ua->proxy('http', $this->{opt}{proxy}) if defined $this->{opt}{proxy};
    $ua->timeout($option->{timeout}) if $option->{timeout};
    $ua->max_redirect($option->{max_redirect}) if $option->{max_redirect};
    $ua->parse_head(0);

    my $response = $ua->get($url);

    print $url,"\n" if $this->{opt}{debug};
    return $response->status_line unless $response->is_success;

    my $input_string = decode(guess_encoding($response->content, qw/ascii euc-jp shiftjis 7bit-jis utf8/), $response->content);

    return ($input_string, $url);
}


1;
