package RepeatCheck;


#myblocktypeのついたhtml木を受け取ってブロックごとに探索し、ブロックの先頭から葉までのタグ列を全部見つける。
#そのうち同じタグ列が3つ以上ある場合、葉(テキストかimgタグ)の親タグにrepeatid属性を付け加える。
#treeを返す。


use utf8;
use strict;
use HTML::TreeBuilder;
use Data::Dumper;



sub new{
    my $this = {};

    bless $this;
}


sub checkline{
    my ($this, $tree) = @_;

    my %linehash = ();

    for my $child($tree->look_down("myblocktype", qr//)){
	$this->checkline_saiki($child, "", \%linehash);
    }

    my %idhash = {};
    my $i = 1;
    for my $line(sort{$linehash{$b} <=> $linehash{$a}}keys(%linehash)){
	next if($linehash{$line} < 3);
	$idhash{$line} = $i;
	$i++;
    }

    $this->{repidhash} = \%idhash;
}

sub checkline_saiki{
    my ($this, $elem, $line, $hashref) = @_;

    if(ref($elem) eq "HTML::Element"){
	my $thistag = $elem->tag;
	return 0 if($thistag eq "script" || $thistag eq "noscript" || $thistag eq "style");

	$line .= $thistag . ",";
	
	for my $child($elem->content_list){
	    my $reflag = $this->checkline_saiki($child, $line, $hashref);
	}

    }elsif(ref($elem) eq ""){

	if(defined($hashref->{$line})){
	    $hashref->{$line} += 1;
	}else{
	    $hashref->{$line} = 1;
	}

    }    

}


sub detectrepeat{
    my ($this, $tree) = @_;
    
    $this->checkline($tree);

    for my $elem($tree->look_down("myblocktype", qr//)){
	$this->detectrepeat_saiki(\$elem, "");
    }

    return $tree;
}


sub detectrepeat_saiki{
    my ($this, $elemref, $line) = @_;

    my $elem = ${$elemref};

    if(ref($elem) eq "HTML::Element"){
	my $thistag = $elem->tag;
	return 0 if($thistag eq "script" || $thistag eq "noscript" || $thistag eq "style");

	$line .= $thistag . ",";
	my $kariline = $line;
	
	for my $child($elem->content_list){
	    $line = $kariline;
	    
	    my $reflag = $this->detectrepeat_saiki(\$child, $line);

	    if(ref($child) eq "HTML::Element" && $child->tag eq "img" && $child->content_list == 0){
		$reflag = 1;
		$line .= $child->tag. ",";
	    }

	    if($reflag == 1){
		my %idhash = %{$this->{repidhash}};

		if(defined($idhash{$line})){
		    $elem->attr("repeatid", $idhash{$line});
		}
	    }
	}
    }elsif(ref($elem) eq ""){
	return 1;
    }
    
    return 0;
}



1;
