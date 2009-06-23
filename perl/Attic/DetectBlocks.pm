package DetectBlocks;


use strict;
use utf8;
use HTML::TreeBuilder;
use Data::Dumper;
use Encode;




sub new{
    my $this = {};

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
	if($url =~ /^http:\/\/\/?([.^\/]+)\// || $url =~ /^http:\/\/\/?([.^\/]+)$/){
	    $url = $1;
	}
	if($url =~ /\/\/\/?([^\/]+)\// || $url =~ /\/\/\/?([^\/]+)$/){
	    $domain = $1;
	}
    }
    $this->{domain} = $domain;

    my @kariblockarr = ();
    $this->{blockarr} = \@kariblockarr;
    my $body = $this->{tree}->find("body");
    $this->{alltextlen} = length($this->{tree}->as_text);

    $this->dblocks_saiki(\$body);

}


sub dblocks_saiki{
    my ($this, $sourceelem) = @_;

    my $elem = ${$sourceelem};
    return 0 if($elem->tag eq "script");
    my $alltextlen = $this->{alltextlen};
#imgタグ内のaltの長さ
    my $altlen = 0;
    for my $imgelem($elem->find("img")){
	$altlen += length($imgelem->attr("alt")) if(defined($imgelem->attr("alt")));
    }

    my $textper = (length($elem->as_text) + $altlen) / $alltextlen;

    if($textper > 0.5 || $textper == 0.0){

	for my $child($elem->content_list){
	    next unless(ref($child) eq "HTML::Element");
	    next if($child->tag eq "comment");
	    $this->dblocks_saiki(\$child);
	}    

    }else{
	my $kk = $this->{blockarr};
	my @kariblockarr = @$kk;
	push(@kariblockarr,[]);
	$this->{blockarr} = \@kariblockarr;
	my $maxlen = $this->block_saiki($sourceelem);

	if($maxlen < 5){
	    pop(@kariblockarr);
	    $this->{blockarr} = \@kariblockarr;
	}else{
	    my $blockarr = $this->{blockarr};
	    my @blockarr = @$blockarr;
	    my @block = $blockarr[$#blockarr];
	    $this->writeblocktype(@block, $sourceelem);
	}	

    }
}


sub block_saiki{
    my ($this, $sourceelem, $maxlen, $ta) = @_;

    my $elem = ${$sourceelem};
    my @karitagarr = @$ta if(defined($ta));
    $maxlen = 0 unless(defined($maxlen));
    @karitagarr = () unless(defined(@$ta));


    #妙な判定法
    if(ref($elem) eq ""){
	
	my $text = $elem;

	if($text =~ /^[\s　\n]+$/){
	    return $maxlen;
	}

	my @tagarr = @karitagarr;
	my @allblockarr = @{$this->{blockarr}};
	my $last = $#allblockarr;
	my @kariblockarr = @{$allblockarr[$last]};

	if($#kariblockarr == -1){
	    @kariblockarr = ([\@tagarr,$text]);
	}else{
	    push(@kariblockarr, [\@tagarr,$text]);
	}

	@allblockarr[$last] = \@kariblockarr;

	$this->{blockarr} = \@allblockarr;

	$maxlen = length($text) if($maxlen < length($text));

    }else{

	if(ref($elem) eq "HTML::Element"){
	    if($elem->tag eq "style" || $elem->tag eq "script"){
		pop(@karitagarr);
		return $maxlen;
	    }elsif($elem->tag eq "a"){
		push(@karitagarr, [$elem->tag,$sourceelem]);
	    }else{
		push(@karitagarr, [$elem->tag,$sourceelem]);
	    }

	    if($elem->content_list != 0){
		for my $child($elem->content_list){
		    $maxlen = $this->block_saiki(\$child, $maxlen, \@karitagarr);
		}
	    }else{
		if($elem->tag eq "img" && $elem->attr("alt") ne ""){
		    my $kk=$elem->{"alt"};
		    $maxlen = $this->block_saiki(\$kk, $maxlen, \@karitagarr);
		}
	    }
	}

    }
    pop(@karitagarr);

    return $maxlen;
}


#２次元配列で各要素配列の先頭が一致するものを検索する。
sub assoc{
    my ($this, $arr, $key) = @_;
    my @arr = @$arr;

    my $i = 0;
    for my $eacharr(@arr){
	my @eacharr = @$eacharr;
	return $i if(@eacharr[0] eq $key);
	$i += 1;
    }
    return -1;
}


=comment
sub printblock{
    my ($this, $bbb) = @_;

    my @block = @$bbb;
    my $flag = 0;
    my @kkk;

    print "*************************************\n";
    for my $mmm(@block){
	my @mmm = @$mmm;
	my @k = @{$mmm[0]};
	my $v = $mmm[1];
	my @kari = [];

	if($flag == 0 || @k != @kari){
	    if(defined(@kkk)){
		push(@kkk, 1);
	    }else{
		$kkk[0] = 1;
	    }
	}elsif($flag == 0){
	    $kkk[$#kkk] += 1;
	}
	$flag = 1;
	
	@kari = @k;

	foreach my $nnn(@k){
	    my @tagarr = @$nnn;
	    print $tagarr[0], ",";
	}

	print ":",$v,"\n";
    }
    print "[@kkk]\n";
    print "************************************\n\n";
}
=cut


sub printblock2{
    my ($this, $flag) = @_;

    my $restr = "";
#    for my $blocktopelem($this->{tree}->look_down("myblock", "true")){
    for my $blocktopelem($this->{tree}->look_down("myblocktype",qr//)){

	$restr .= $blocktopelem->attr("myblocktype")."***************************\n";

	$this->printblock_saiki($blocktopelem, "", \$restr);

	$restr .= "*********************************\n\n";
    }
    print $restr if(defined($flag));

    return $restr;
}

sub printblock_saiki{
    my($this, $elem, $taglist, $restr) = @_;


    if(ref($elem) eq "HTML::Element"){

	return 0 if($elem->tag eq "style" || $elem->tag eq "script");
	$taglist .= $elem->tag . ",";
	for my $childelem($elem->content_list){
	    $this->printblock_saiki($childelem, $taglist, $restr);
	}

	if($elem->tag eq "img" && $elem->content_list == 0){
	    my $altstr = $elem->{"alt"};
	    unless($altstr =~ /^[\s　]+$/ || $altstr eq ""){
		${$restr} .= $taglist. $altstr. "\n";
	    }
	}

    }elsif(ref($elem) eq ""){

	unless($elem =~ /^[\s　]+$/ || $elem eq ""){
	    ${$restr} .= $taglist. $elem. "\n";
	}       

    }
}


sub checkfoot{
    my ($this, $block) = @_;
    
    my @block = @$block;

    my $total = $#block + 1;
    my $karifootnum = 0;
    my $textlen = 0;
    for my $eachleaf(@block){
	my @eachleaf = @$eachleaf;
	my $text = $eachleaf[1];

	next if($text =~ /^[\s　]+$/ || $text eq "");

	$karifootnum += 1 if($text =~ /住所|所在地|郵便番号|電話番号|著作権|問[い]?合[わ]?せ|利用案内|質問|意見|\d{3}\-?\d{4}|Tel|TEL|.+[都道府県].+[市区町村]|(06|03)\-?\d{4}\-?\d{4}|\d{3}\-?\d{3}\-?\d{4}|mail/);
	$textlen += length($text);
    }

    if($karifootnum / $total >= 0.5 && $textlen / $this->{alltextlen} < 0.3){
	return 1;
    }else{
	return 0;
    }
}


sub checkmaintext{
    my ($this, $block) = @_;

    my @block = @$block;

    my $total = $#block + 1;
    my $karimainnum = 0;
    my $textlen = 0;
    for my $eachleaf(@block){
        my @eachleaf = @$eachleaf;
        my $text = $eachleaf[1];

        next if($text =~ /^[\s　]+$/ || $text eq "");

        $karimainnum += 1 if($text =~ /。|、|ます|です/);
        $textlen += length($text);
    }

    if($karimainnum / $total >= 0.5){
        return 1;
    }else{
        return 0;
    }

}


sub checkcopy{
    my ($this, $block) = @_;
    
    my @block = @$block;

    my $total = $#block + 1;
    my $karicopynum = 0;
    my $textlen = 0;
    for my $eachleaf(@block){
	my @eachleaf = @$eachleaf;
	my $text = $eachleaf[1];

	next if($text =~ /^[\s　]+$/ || $text eq "");

	$karicopynum += 1 if($text =~ /Copyright|©|(c)|著作権/);
	$textlen += length($text);
    }

    if($karicopynum / $total >= 0.5 && $textlen / $this->{alltextlen} < 0.3){
	return 1;
    }else{
	return 0;
    }
}


sub writeblocktype{
    my ($this, $kariblock, $sourceelem) = @_;

    my @block = @$kariblock;
    my $elem = ${$sourceelem};

    return 0 if(@block == []);

    my $karia = 0;
    my $kariatnum = 0;
    my $karinottnum = 0;
    my $kariahref = 0;
    my $formnum = 0;

    for my $leaf(@block){

	my @leaf = @$leaf;
	my @tagarr = @{$leaf[0]};
	my $text = $leaf[1];
	my $aposition = $this->assoc(\@tagarr,"a");
	
	if($aposition != -1){
	    $karia += 1;
	    $kariatnum += length($text);
	    my $atag = ${$tagarr[$aposition][1]};
	    ####リンク処理,変数名ちょっとごちゃごちゃ
	    if(defined($atag->attr("href")) && defined($this->{domain})){
		my $href = $atag->attr("href");
		$kariahref += 1 if($href =~ $this->{domain} || !($href =~ /:\/\//));
	    }
	}else{
	    $karinottnum += length($text);
	}

	$formnum += 1 if($this->assoc(\@tagarr, "form") != -1);

    }

    my $typeflag = "";
#    if($karia/($#block+1) >= 0.5 || $karinottnum/$kariatnum <= 0.3){
    if($karia/($#block+1) >= 0.5 || $karinottnum < $kariatnum ){
	if(defined($this->{domain})){
	    if($kariahref/$karia >= 0.5){
		$typeflag = "inlink";
	    }else{
		$typeflag = "outlink";
	    }
	}else{
	    $typeflag = "link"
	}
    }else{
	if($formnum/($#block+1) > 0.8){
	    $typeflag = "form";
	}elsif($this->checkfoot(\@block)){
	    $typeflag = "footer";
	}elsif($this->checkmaintext(\@block)){
	    $typeflag = "maintext";
	}
    }
    if($this->checkcopy(\@block)){
	$typeflag .= " copyright";
    }
    if($typeflag eq ""){
	$typeflag = "unknown_text";
    }

#    $konelem->attr("myblock","true");
    $elem->attr("myblocktype",$typeflag);

}


sub gettree{
    my ($this) = @_;
    
    return $this->{tree};
}



1;








