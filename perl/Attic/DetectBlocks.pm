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

    my $allaltlen = 0;
    for my $elem($body->look_down("alt", qr//)){
	$allaltlen += length($elem->attr("alt"));
    }
#コメントやスクリプトがテキストとして認識される問題
    $this->{alltextlen} = length($body->as_text) + $allaltlen;

    $body->objectify_text;
    $this->dblocks_saiki(\$body);
    $body->deobjectify_text;
}


sub dblocks_saiki{
    my ($this, $sourceelem) = @_;

    my $elem = ${$sourceelem};
    return 0 if($elem->tag eq "script" || $elem->tag eq "noscript");
    my $alltextlen = $this->{alltextlen};
#imgタグ内のaltの長さ
    my $textlen = 0;
    my $textper = 0;

    for my $imgelem($elem->find("img")){
	$textlen += length($imgelem->attr("alt")) if(defined($imgelem->attr("alt")));
    }
    for my $textelem($elem->find("~text")){
	$textlen += length($textelem->attr("text"));
    }
    $textper = $textlen / $alltextlen;

    if($textper > 0.5 || $textper == 0.0){

	for my $child($elem->content_list){
	    next if(ref($child) ne "HTML::Element");
	    next if($child->tag eq "comment");
	    $this->dblocks_saiki(\$child);
	}

    }else{
	
#	for my $i($this->recheckblock($sourceelem)){
for my $i(($sourceelem)){
	    my $kk = $this->{blockarr};
	    my @kariblockarr = @$kk;
	    push(@kariblockarr,[]);
	    $this->{blockarr} = \@kariblockarr;
	    my $maxlen = $this->block_saiki($i);
	    if($maxlen < 5){
		pop(@kariblockarr);
		$this->{blockarr} = \@kariblockarr;
	    }else{
		my $blockarr = $this->{blockarr};
		my @blockarr = @$blockarr;
		my @block = $blockarr[$#blockarr];
		$this->writeblocktype(@block, $i);
	    }	
	    
	}
    }
}


sub recheckblock{
    my ($this, $sourceelem) = @_;

    my $elem = ${$sourceelem};

    my @aarr = $elem->find("a");
    my $allanum = $#{aarr} + 1;
    my @farr = $elem->find("form");
    my $allformnum = $#{farr} + 1;
    my @tarr = $elem->find("~text");
    my $alltextnum = $#{tarr} + 1;
    my $allfootnum = 0;
    my $allmaintnum = 0;
    for my $text(@tarr){
	$allfootnum += 1 if($text->attr("text") =~ /住所|所在地|郵便番号|電話番号|著作権|問[い]?合[わ]?せ|利用案内|質問|意見|\d{3}\-?\d{4}|Tel|TEL|.+[都道府県].+[市区町村]|(06|03)\-?\d{4}\-?\d{4}|\d{3}\-?\d{3}\-?\d{4}|mail|Copyright|©|(c)|著作権/);
	$allmaintnum += 1 if($text->attr("text") =~ /。|、|ます|です|でした|ました/);
    }

    my @rearr =();

    $this->recheckblock_saiki($sourceelem, \@rearr, $allanum, $allformnum, $alltextnum, $allfootnum, $allmaintnum);

    return @rearr;

}


sub recheckblock_saiki{
    my ($this, $sourceelem, $rearr, $aa, $af, $at, $af, $amt) = @_;

    my $elem = ${$sourceelem};

    if($at<=3){
	push(@{$rearr}, $sourceelem);
	return 0;
    }

    my $childrenflag = 0;
    my @kariarr;
    for my $child($elem->content_list){
	my @aarr = $child->find("a");
	my $anum = $#{aarr} + 1;
	my @farr = $child->find("form");
	my $formnum = $#{farr} + 1;
	my @tarr = $child->find("~text");
	my $textnum = $#{tarr} + 1;
	my $footnum = 0;
	my $maintnum = 0;
	for my $text(@tarr){
	    $footnum += 1 if($text->attr("text") =~ /住所|所在地|郵便番号|電話番号|著作権|問[い]?合[わ]?せ|利用案内|質問|意見|\d{3}\-?\d{4}|Tel|TEL|.+[都道府県].+[市区町村]|(06|03)\-?\d{4}\-?\d{4}|\d{3}\-?\d{3}\-?\d{4}|mail|Copyright|©|(c)|著作権/);
	    $maintnum += 1 if($text->attr("text") =~ /。|、|ます|です|でした|ました|だった/);
	}

#	if($anum/$aa>0.9 || $formnum/$af>0.9 || $textnum/$at>0.9 || $footnum/$af>0.9 || $maintnum/$amt>0.9){
#	    push(@rearr, \$child);
#	}

	my $flag = 0;
	$flag += 1 if($aa != 0 && $anum/$aa>0.8);
	$flag += 1 if($af != 0 && $formnum/$af>0.8);
	$flag += 1 if($at != 0 && $textnum/$at>0.8);
	$flag += 1 if($af != 0 && $footnum/$af>0.8);
	$flag += 1 if($amt != 0 && $maintnum/$amt>0.8);
#	print $anum/$aa,"\n",$child->find("~text"),"\n\n"if($aa!=0);
	if($flag == 1){
	    for my $karichild(@kariarr){
		push(@{$rearr}, $karichild);
	    }
	    @kariarr =();
	    push(@{$rearr}, \$child);
	    $childrenflag +=1;
	}elsif($flag >=2){
	    for my $karichild(@kariarr){
		push(@{$rearr}, $karichild);
	    }
	    @kariarr = ();
	    $this->recheckblock_saiki(\$child, $rearr, $aa, $af, $at, $af, $amt);
	    $childrenflag += 1;
	}elsif($childrenflag == 0){
	    push(@kariarr, \$child);
	}else{
	    push(@{$rearr}, \$child);
	}
=comment
	if($flag > 0){
	    for my $karichild(@kariarr){
		push(@{$rearr}, $karichild);
	    }
	    @kariarr = ();
	    push(@{$rearr}, \$child);
	    $childrenflag += 1;
	}elsif($childrenflag != 0){
	    push(@{$rearr}, \$child);
	}else{
	    push(@kariarr, \$child);
	}
=cut
    }

    if($childrenflag == 0){
	push(@{$rearr}, $sourceelem);
	return 0;
    }
    return 1;
}


sub block_saiki{
    my ($this, $sourceelem, $maxlen, $ta) = @_;

    my $elem = ${$sourceelem};
    my @karitagarr = @$ta if(defined($ta));
    $maxlen = 0 unless(defined($maxlen));
    @karitagarr = () unless(defined(@$ta));


    #妙な判定法
    if(ref($elem) eq ""){
#    if($elem->tag eq "~text" ||($elem->tag eq "img" && $elem->{"alt"} ne "")){
	
	my $text = $elem;
#	if($elem->tag eq "~text"){
#	    $text = $elem->attr("text");
#	}elsif($elem->tag eq "img"){
#	    $text = $elem->attr("alt");
#	}

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
		if($elem->tag eq "~text"){
		    if($karitagarr[0][0] ne "~text"){
			my $intext = $elem->{"text"};
			$maxlen = $this->block_saiki(\$intext, $maxlen, \@karitagarr);

		    }else{
			@karitagarr = ();
			my $karielem = $elem->clone;
			$elem->tag("myfont");
			$elem->push_content($karielem);
			$maxlen = $this->block_saiki(\$elem, $maxlen, \@karitagarr);
		    }
		}elsif($elem->tag eq "img" && $elem->attr("alt") ne ""){
		    my $alttext=$elem->{"alt"};
		    $maxlen = $this->block_saiki(\$alttext, $maxlen, \@karitagarr);
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

	my %rehash = ();        #(repeatid ,回数)

	$this->makehash($blocktopelem, \%rehash);

	$restr .= $blocktopelem->attr("myblocktype")."***************************\n";

	$this->printblock_saiki($blocktopelem, "", "", \$restr, \%rehash);

	$restr .= "*********************************\n\n";
    }
    print $restr if(defined($flag));

    return $restr;
}


sub printblock_saiki{
    my($this, $elem, $taglist, $repeat, $restr, $rehashref) = @_;
  
    if(ref($elem) eq "HTML::Element" && defined($elem->attr("repeatid"))){
	$repeat = $elem->attr("repeatid") if($rehashref->{$elem->attr("repeatid")} >= 3);
    }    
    my $rep = $elem->attr("rep") if(ref($elem) eq "HTML::Element" && defined($elem->attr("rep")));
	
    if(ref($elem) eq "HTML::Element" && $elem->tag ne "~text" && $elem->tag ne "img"){

	return 0 if($elem->tag eq "style" || $elem->tag eq "script" || $elem->tag eq "noscript");
	$taglist .= $elem->tag . ",";
	for my $childelem($elem->content_list){
	    $this->printblock_saiki($childelem, $taglist, $repeat, $restr, $rehashref);
	}

    }elsif(ref($elem) eq ""){

	unless($elem =~ /^[\s　]+$/ || $elem eq ""){
	    if ($repeat eq ""){
		${$restr} .=  "$rep". "    ". $taglist. $elem. "\n";
	    }else{   
		${$restr} .=  "$rep". "[". $repeat. "] ". $taglist. $elem. "\n";
	    }       
	}


    }elsif(ref($elem) eq "HTML::Element" && $elem->tag eq "~text"){

	my $text = $elem->attr("text");
	unless($text =~ /^[\n\s　]+$/ || $text eq ""){
	    if($repeat eq ""){
		${$restr} .= "$rep". "    ". $taglist. $text. "\n";
	    }else{
		${$restr} .= "$rep". "[". $repeat. "] ". $taglist. $text. "\n";
	    }
	}

    }elsif(ref($elem) eq "HTML::Element" && $elem->tag eq "img"){

	$taglist .= $elem->tag;
	if($elem->content_list == 0){
	    my $altstr = $elem->{"alt"};
	    unless($altstr =~ /^[\s　]+$/ || $altstr eq ""){
		if($repeat eq ""){
		    ${$restr} .= "$rep". "    ". $taglist. $altstr. "\n";
		}else{
		    ${$restr} .= "$rep". "[". $repeat. "] ". $taglist. ".". $altstr. "\n";
		}
	    }
	}
    }
}


sub makehash{
    my ($this, $elem, $rehashref) = @_;
    if(ref($elem) eq "HTML::Element"){
	my $id = $elem->attr("repeatid") if(defined($elem->attr("repeatid")));
	if(defined($rehashref->{$id})){
	    $rehashref->{$id} += 1  if(defined($elem->attr("repeatid")));
	}else{
	    $rehashref->{$id} = 1 if(defined($elem->attr("repeatid")));
	}
	for my $childelem($elem->content_list){
	    $this->makehash($childelem, $rehashref);
	}
    }
}


sub checkfoot{
    my ($this, $block) = @_;
    
    my @block = @$block;

    my $total = $#block + 1;
    my $karifootnum = 0;
    my $karitextlen = 0;
    my $textlen = 0;
    for my $eachleaf(@block){
	my @eachleaf = @$eachleaf;
	my $text = $eachleaf[1];

	next if($text =~ /^[\s　]+$/ || $text eq "");

	if($text =~ /住所|所在地|郵便番号|電話番号|著作権|問[い]?合[わ]?せ|利用案内|質問|意見|\d{3}\-?\d{4}|Tel|TEL|.+[都道府県].+[市区町村]|(06|03)\-?\d{4}\-?\d{4}|\d{3}\-?\d{3}\-?\d{4}|mail|Copyright|©|(c)|著作権/){
	    $karifootnum += 1;
	    $karitextlen += length($text);
	}
	$textlen += length($text);
    }

    if(($karifootnum / $total >= 0.5 || $karitextlen/$textlen > 0.8) && $textlen / $this->{alltextlen} < 0.3){
	if($this->checkcopy($block)){
	    return 2;
	}else{
	    return 1;
	}
    }else{
	return 0;
    }
}


sub checkmaintext{
    my ($this, $block) = @_;

    my @block = @$block;

    my $total = $#block + 1;
    my $karimainnum = 0;
    my $karimainlen = 0;
    my $textlen = 0;
    for my $eachleaf(@block){
        my @eachleaf = @$eachleaf;
        my $text = $eachleaf[1];

        next if($text =~ /^[\s　]+$/ || $text eq "");

        if($text =~ /。|、|ます|です|でした|ました/){
	    $karimainnum += 1; 
	    $karimainlen += length($text);
	}
        $textlen += length($text);
    }

    if($karimainnum/$total >= 0.5 || $karimainlen/$textlen >= 0.8){
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


sub checklink{
    my ($this, $block) = @_;

    my @block = @$block;

    my $karia = 0;
    my $kariatnum = 0;
    my $karinottnum = 0;
    my $kariahref = 0;
    
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

    }

    if($karia/($#block+1) >= 0.5 || $karinottnum < $kariatnum ){
        if(defined($this->{domain})){
            if($kariahref/$karia >= 0.5){
                return 1;
            }else{
		return 2;
            }
        }else{
	    return 3;
	}
    }

    return 0;
}


sub checkform{
    my ($this, $block) = @_;

    my @block = @$block;

    my $total = $#block + 1;
    my $kariformnum = 0;
    my $textlen = 0;

    for my $leaf(@block){

        my @leaf = @$leaf;
        my @tagarr = @{$leaf[0]};
        
	if($this->assoc(\@tagarr,"form") != -1){
	    $kariformnum += 1;
	}

    }

    if($kariformnum/$total >= 0.8){
        return 1;
    }else{
        return 0;
    }
   
}

sub checkimg{
    my ($this, $block) = @_;

    my @block = @$block;

    my $total = $#block + 1;
    my $kariimgnum = 0;
    my $textlen = 0;

    for my $leaf(@block){

        my @leaf = @$leaf;
        my @tagarr = @{$leaf[0]};
        
	if($this->assoc(\@tagarr,"img") != -1){
	    $kariimgnum += 1;
	}

    }

    if($kariimgnum/$total >= 0.8){
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


    my $typeflag = "";
#    if($karia/($#block+1) >= 0.5 || $karinottnum/$kariatnum <= 0.3){
    if((my $lflag = $this->checklink(\@block))){
	if($lflag == 1){
	    $typeflag = "link internal";
	    if($this->checkimg(\@block)){
		$typeflag = "imglink internal";
	    }
	}elsif($lflag == 2){
	    $typeflag = "link external";
	    if($this->checkimg(\@block)){
		$typeflag = "imglink external";
	    }
	}elsif($lflag == 3){
	    $typeflag = "link";
	    if($this->checkimg(\@block)){
		$typeflag = "imglink";
	    }
	}
    }else{
	if($this->checkform(\@block)){
	    $typeflag = "form";
	}elsif((my $fcflag = $this->checkfoot(\@block))){
	    $typeflag = "footer";
	    $typeflag .= " copyright" if($fcflag == 2);
	}elsif($this->checkmaintext(\@block)){
	    $typeflag = "maintext";
	}
	elsif($this->checkimg(\@block)){
	    $typeflag = "img";
	}
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


sub settree{
    my ($this, $tree) = @_;

    $this->{tree} = $tree;
}

1;








