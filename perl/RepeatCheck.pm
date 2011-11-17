package RepeatCheck;

# $Id$

#myblocktypeのついたhtml木を受け取ってブロックごとに探索し、ブロックの先頭から葉までのタグ列を全部見つける。
#そのうち同じタグ列が3つ以上ある場合、葉(テキストかimgタグ)の親タグにrepeatid属性を付け加える。
#treeを返す。

use utf8;
use strict;
use HTML::TreeBuilder;
use Data::Dumper;

sub new {
    my $this = {};

    bless $this;
}


sub checkline {
    my ($this, $tree) = @_;

    my %linehash = ();
    
    for my $child($tree->look_down("myblocktype", qr//)){
	$this->checkline_saiki($child, "", \%linehash);
    }

    my %idhash = {};
    my $i = 1;

    #回数が多い順にナンバリング
    for my $line(sort{$linehash{$b} <=> $linehash{$a}}keys(%linehash)){
	next if($linehash{$line} < 3);
	$idhash{$line} = $i;
	$i++;
    }

    $this->{repidhash} = \%idhash;
}

sub detect_rep {
    my ($this,  $tree) = @_;
    my $id;
    my $preid;
    my @rrr;
    for my $child($tree->look_down("repeatid", qr//)){
	$id = $child->attr("repeatid");
	if($id eq $preid){                     #id eq preid
	    push(@rrr, \$child);
	}else{                                 #id not eq preid
	    if(scalar(@rrr) >= 3){
		for my $kkk(@rrr){
		    ${$kkk}->attr("rep", "*");
		}
	    }
	    @rrr = (\$child);
	}
	$preid = $id;
    }
}


sub checkline_saiki {
    my ($this, $elem, $line, $hashref) = @_;

    if($elem->tag ne "~text" && $elem->tag ne "img"){
 	my $thistag = $elem->tag;
	return 0 if($thistag eq "script" || $thistag eq "noscript" || $thistag eq "style");

 
	$line .= $thistag . ",";
	 
	for my $child($elem->content_list){
	    $this->checkline_saiki($child, $line, $hashref);
	}
 
    }elsif($elem->tag eq "~text" || $elem->tag eq "img"){
	# objectify_textした後に' 'が残るようなので、その場合はreturn
	my $text = $elem->attr("text");
	return if $text && $text =~ /^[\n\s　]+$/;

	$line .= $elem->tag;
	if(defined($hashref->{$line})){
	    $hashref->{$line} += 1;
	}else{
	    $hashref->{$line} = 1;
	}
    }    
}


sub detectrepeat {
    my ($this, $tree) = @_;

    $tree->objectify_text;
    $this->checkline($tree);

    for my $elem($tree->look_down("myblocktype", qr//)){
	$this->detectrepeat_saiki(\$elem, "");
    }

    $this->detect_rep($tree);

    return $tree;
}


sub detectrepeat_saiki {
    my ($this, $elemref, $line) = @_;

    my $elem = ${$elemref};

    if($elem->tag ne "~text" && $elem->tag ne "img"){
	my $thistag = $elem->tag;
	return 0 if($thistag eq "script" || $thistag eq "noscript" || $thistag eq "style");

	$line .= $thistag . ",";
	my $kariline = $line;
	
	for my $child($elem->content_list){
	    $line = $kariline;
	    
	    $this->detectrepeat_saiki(\$child, $line);
	}
    }elsif($elem->tag eq "~text" || $elem->tag eq "img"){
	$line .= $elem->tag;
	my %idhash = %{$this->{repidhash}};

	if(defined($idhash{$line})){
	    $elem->attr("repeatid", $idhash{$line});
	}
    }
    
    return 0;
}

1;
